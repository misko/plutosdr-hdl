#!/usr/bin/env python3
"""Generate or verify the 210-window Stage-15 AXI replay fixture.

Generation is deliberately bound to the retained recording manifest, its first
compressed CI16 chunk, and the reviewed timing-replay JSON.  Ordinary HDL test
runs use ``verify`` and the committed memory files, so they need neither the
bulk recording nor NumPy.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from collections import Counter
from pathlib import Path


THIS_DIR = Path(__file__).resolve().parent
REPOSITORY = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(REPOSITORY))

CAPTURE_ID = "cap-20260831T071200-9184cf0ad6cc"
STREAM_ID = "stream-1"
RADIO_SERIAL = "10400056f695001322002d0010ad1719f2"
SAMPLE_RATE_HZ = 15_000_000
FIRST_DEVICE_SAMPLE_COUNTER = 480_554_573_351
FIRST_CHUNK_SAMPLES = 4_194_304
MANIFEST_SHA256 = "be6a196eaf0894667b835a73afe3aa83ff3200eadc0349b4a45cc5420f7b6f09"
CHUNK_COMPRESSED_SHA256 = "68732179d9e147e0f173677f810e032d5240fc3ba024cb9045fe17dff9f38946"
CHUNK_UNCOMPRESSED_SHA256 = "fd922ab9913b72e545ff526d99ebe884170170d2c817a6a56384740316d661ae"
REPLAY_SHA256 = "3e324d8841cd4d806de9963049c7a18f2042abd59eaa0549bcdd22ac86f88d70"
COEFFICIENT_SHA256 = "c660bf9a60fc112697a5939db4682e55a0ce9b5ef8c99f2e4dee7e2b328d62c2"
TEMPLATE_SHA256 = "3c4e6e36250c970c2905ae64d177e0d9d40e941702483f15f11cc57e88edaced"
WINDOWS = 210
RAW_CAPTURE_SAMPLES = 130
TAPS = 66
FIRST_LAG = -30
LAST_LAG = 30
SYNTHETIC_FIRST_CENTER = 128
SYNTHETIC_CENTER_STRIDE = 225
REQUEST_BASE = 0x7120_0000
COEFFICIENT_GENERATION = 0x0712_0001

SAMPLES_FILE = THIS_DIR / "real_071200_wrapper_samples_ci16.mem"
INJECTION_FILE = THIS_DIR / "real_071200_window0_samples_ci16.mem"
PACKETS_FILE = THIS_DIR / "real_071200_wrapper_packets.mem"
PROVENANCE_FILE = THIS_DIR / "real_071200_wrapper_replay_provenance.json"
COEFFICIENT_FILE = (
    THIS_DIR.parent.parent
    / "starlink_pss_raw_correlator"
    / "tb"
    / "upper_minus100k_coefficients_q15.mem"
)


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def expect(label: str, actual: object, expected: object) -> None:
    if actual != expected:
        raise RuntimeError(f"{label}: expected {expected!r}, got {actual!r}")


def selected_windows(replay: dict[str, object]) -> list[dict[str, object]]:
    targets = [target for target in replay["targets"] if target["stream_id"] == STREAM_ID]
    expect("stream target count", len(targets), 1)
    result = targets[0]["blocks"][0]["result"]
    expect("block status", result["status"], "complete")
    expect("block sample rate", result["sample_rate_hz"], float(SAMPLE_RATE_HZ))
    expect("block sample count", result["sample_count"], FIRST_CHUNK_SAMPLES)
    expect("frame period", result["frame_period_samples"], 20_000.0)
    expect("template samples", result["template_sample_count"], TAPS)
    expect("template SHA-256", result["template_sha256"], TEMPLATE_SHA256)
    candidate = result["candidates"][0]
    expect("candidate qualified", candidate["qualified"], True)
    expect("candidate frame support", candidate["frame_support"], WINDOWS)
    expect("candidate CFO", candidate["frequency_offset_hz"], -100_000.0)
    windows = result["windows"]
    expect("window count", len(windows), WINDOWS)
    for index, window in enumerate(windows):
        expect(f"window {index} frame index", window["frame_index"], index)
        expect(f"window {index} candidate", window["candidate_index"], 0)
        expect(f"window {index} CFO", window["frequency_offset_hz"], -100_000.0)
        expect(
            f"window {index} prediction",
            window["predicted_local_sample"],
            1185 + 20_000 * index,
        )
    return windows


def validate_authorities(manifest_path: Path, chunk_path: Path, replay_path: Path) -> bytes:
    expect("manifest SHA-256", sha256_file(manifest_path), MANIFEST_SHA256)
    expect("chunk SHA-256", sha256_file(chunk_path), CHUNK_COMPRESSED_SHA256)
    expect("timing replay SHA-256", sha256_file(replay_path), REPLAY_SHA256)
    expect("coefficient SHA-256", sha256_file(COEFFICIENT_FILE), COEFFICIENT_SHA256)

    manifest = json.loads(manifest_path.read_text())
    expect("capture ID", manifest["session_id"], CAPTURE_ID)
    streams = [stream for stream in manifest["streams"] if stream["stream_id"] == STREAM_ID]
    expect("manifest stream count", len(streams), 1)
    stream = streams[0]
    expect("radio serial", stream["radio"]["serial"], RADIO_SERIAL)
    expect("sample rate", stream["applied_settings"]["sample_rate_hz"], SAMPLE_RATE_HZ)
    expect(
        "first device sample counter",
        stream["continuity"]["first_device_sample_counter"],
        FIRST_DEVICE_SAMPLE_COUNTER,
    )
    chunk = next(item for item in stream["chunks"] if item["chunk_index"] == 0)
    expect("chunk sample count", chunk["sample_count"], FIRST_CHUNK_SAMPLES)
    expect("chunk format", chunk["sample_format"], "ci16_le")
    expect("chunk layout", chunk["sample_layout"], "sample_receiver_iq")
    expect(
        "manifest compressed digest",
        chunk["compressed_sha256"],
        f"sha256:{CHUNK_COMPRESSED_SHA256}",
    )
    expect(
        "manifest uncompressed digest",
        chunk["uncompressed_sha256"],
        f"sha256:{CHUNK_UNCOMPRESSED_SHA256}",
    )

    completed = subprocess.run(
        ("zstd", "--decompress", "--quiet", "--stdout", str(chunk_path)),
        check=True,
        stdout=subprocess.PIPE,
    )
    raw = completed.stdout
    expect("uncompressed bytes", len(raw), FIRST_CHUNK_SAMPLES * 4)
    expect("uncompressed SHA-256", sha256_bytes(raw), CHUNK_UNCOMPRESSED_SHA256)
    return raw


def packed_ci16(values: object) -> str:
    return "".join(f"{int(i) & 0xffff:04x}{int(q) & 0xffff:04x}\n" for i, q in values)


def u32(value: int) -> int:
    return value & 0xFFFF_FFFF


def packet_words(
    *,
    request_id: int,
    center_index: int,
    center_timestamp: int,
    lag: int,
    generation: int,
    result: object,
) -> list[int]:
    numerator = result.correlation_power
    denominator = result.sample_energy
    winner_timestamp = center_timestamp + lag
    return [
        0x3153_5350,
        0x1A01_0001,
        request_id,
        u32(center_index),
        u32(center_index >> 32),
        u32(center_timestamp),
        u32(center_timestamp >> 32),
        u32(lag),
        u32(winner_timestamp),
        u32(winner_timestamp >> 32),
        generation,
        u32(result.real),
        u32(result.real >> 32),
        u32(result.imag),
        u32(result.imag >> 32),
        u32(result.sample_energy),
        u32(result.sample_energy >> 32),
        u32(result.coefficient_energy),
        u32(result.coefficient_energy >> 32),
        result.saturation_events,
        u32(numerator),
        u32(numerator >> 32),
        u32(numerator >> 64),
        u32(denominator),
        u32(denominator >> 32),
        u32(denominator >> 64),
    ]


def generate(manifest_path: Path, chunk_path: Path, replay_path: Path) -> None:
    import numpy as np

    from tests.starlink_oracle import FIXED_CORRELATOR_SCHEMA, fixed_correlate_ci16

    raw = validate_authorities(manifest_path, chunk_path, replay_path)
    replay = json.loads(replay_path.read_text())
    windows = selected_windows(replay)
    all_samples = np.frombuffer(raw, dtype="<i2").reshape(-1, 2)

    coefficient_words = [int(line, 16) for line in COEFFICIENT_FILE.read_text().splitlines()]
    coefficients = np.empty((TAPS, 2), dtype=np.int16)
    for index, word in enumerate(coefficient_words):
        coefficients[index, 0] = np.asarray(
            (word >> 16) & 0xFFFF, dtype=np.uint16
        ).view(np.int16)
        coefficients[index, 1] = np.asarray(
            word & 0xFFFF, dtype=np.uint16
        ).view(np.int16)

    frozen_samples = []
    frozen_packets: list[int] = []
    selected_lags: list[int] = []
    outer_mismatches: list[dict[str, int]] = []
    for index, window in enumerate(windows):
        predicted = int(window["predicted_local_sample"])
        capture = np.asarray(
            all_samples[predicted - 32 : predicted + 98], dtype=np.int16
        )
        expect(f"window {index} capture shape", capture.shape, (RAW_CAPTURE_SAMPLES, 2))
        frozen_samples.extend(capture)

        rows = []
        for lag in range(-32, 33):
            first = lag + 32
            rows.append(fixed_correlate_ci16(capture[first : first + TAPS], coefficients))

        def winner(lags: range) -> int:
            best = lags.start
            for lag in lags:
                candidate = rows[lag + 32]
                retained = rows[best + 32]
                if (
                    candidate.correlation_power * retained.sample_energy
                    > retained.correlation_power * candidate.sample_energy
                ):
                    best = lag
            return best

        selected = winner(range(FIRST_LAG, LAST_LAG + 1))
        float_lag = int(window["measured_local_sample"]) - predicted
        expect(f"window {index} fixed/float lag", selected, float_lag)
        selected_lags.append(selected)
        outer = winner(range(-32, 33))
        if outer != float_lag:
            outer_mismatches.append(
                {"window": index, "frozen_lag": float_lag, "legacy_outer_lag": outer}
            )

        center_index = SYNTHETIC_FIRST_CENTER + SYNTHETIC_CENTER_STRIDE * index
        center_timestamp = FIRST_DEVICE_SAMPLE_COUNTER + predicted
        frozen_packets.extend(
            packet_words(
                request_id=REQUEST_BASE + index,
                center_index=center_index,
                center_timestamp=center_timestamp,
                lag=selected,
                generation=COEFFICIENT_GENERATION,
                result=rows[selected + 32],
            )
        )

    expect("legacy outer mismatch count", len(outer_mismatches), 3)
    expect(
        "legacy outer mismatches",
        outer_mismatches,
        [
            {"window": 141, "frozen_lag": 20, "legacy_outer_lag": -32},
            {"window": 195, "frozen_lag": -19, "legacy_outer_lag": 32},
            {"window": 201, "frozen_lag": -30, "legacy_outer_lag": -31},
        ],
    )

    SAMPLES_FILE.write_text(packed_ci16(frozen_samples))
    INJECTION_FILE.write_text(packed_ci16(frozen_samples[:RAW_CAPTURE_SAMPLES]))
    PACKETS_FILE.write_text("".join(f"{word:08x}\n" for word in frozen_packets))
    provenance = {
        "schema": "starlink-pss15-axi-wrapper-replay-v1",
        "claim": "retained real-window AXI arithmetic and packet equivalence only",
        "authority": {
            "capture_id": CAPTURE_ID,
            "stream_id": STREAM_ID,
            "radio_serial": RADIO_SERIAL,
            "sample_rate_hz": SAMPLE_RATE_HZ,
            "first_device_sample_counter": FIRST_DEVICE_SAMPLE_COUNTER,
            "manifest_sha256": MANIFEST_SHA256,
            "chunk_compressed_sha256": CHUNK_COMPRESSED_SHA256,
            "chunk_uncompressed_sha256": CHUNK_UNCOMPRESSED_SHA256,
            "timing_replay_sha256": REPLAY_SHA256,
            "coefficient_file_sha256": COEFFICIENT_SHA256,
            "template_sha256": TEMPLATE_SHA256,
        },
        "contract": {
            "oracle_schema": FIXED_CORRELATOR_SCHEMA,
            "windows": WINDOWS,
            "raw_capture_samples_per_window": RAW_CAPTURE_SAMPLES,
            "taps": TAPS,
            "first_lag": FIRST_LAG,
            "last_lag": LAST_LAG,
            "packet_words": 26,
            "coefficient_generation": COEFFICIENT_GENERATION,
            "request_base": REQUEST_BASE,
            "synthetic_first_center": SYNTHETIC_FIRST_CENTER,
            "synthetic_center_stride": SYNTHETIC_CENTER_STRIDE,
        },
        "result": {
            "fixed_float_lag_matches": WINDOWS,
            "lag_histogram": {
                str(key): value for key, value in sorted(Counter(selected_lags).items())
            },
            "legacy_minus32_plus32_mismatches": outer_mismatches,
        },
        "fixture_sha256": {
            SAMPLES_FILE.name: sha256_file(SAMPLES_FILE),
            INJECTION_FILE.name: sha256_file(INJECTION_FILE),
            PACKETS_FILE.name: sha256_file(PACKETS_FILE),
        },
    }
    PROVENANCE_FILE.write_text(json.dumps(provenance, indent=2, sort_keys=True) + "\n")
    verify()
    print(
        "AXI_REAL_REPLAY_FIXTURE_GENERATED "
        f"windows={WINDOWS} fixed_float_matches={WINDOWS} "
        f"legacy_outer_mismatches={len(outer_mismatches)}"
    )


def verify() -> None:
    provenance = json.loads(PROVENANCE_FILE.read_text())
    expect("fixture schema", provenance["schema"], "starlink-pss15-axi-wrapper-replay-v1")
    contract = provenance["contract"]
    for name, expected in (
        ("windows", WINDOWS),
        ("raw_capture_samples_per_window", RAW_CAPTURE_SAMPLES),
        ("taps", TAPS),
        ("first_lag", FIRST_LAG),
        ("last_lag", LAST_LAG),
        ("packet_words", 26),
        ("coefficient_generation", COEFFICIENT_GENERATION),
        ("request_base", REQUEST_BASE),
        ("synthetic_first_center", SYNTHETIC_FIRST_CENTER),
        ("synthetic_center_stride", SYNTHETIC_CENTER_STRIDE),
    ):
        expect(f"contract {name}", contract[name], expected)
    expect("fixed/float matches", provenance["result"]["fixed_float_lag_matches"], WINDOWS)
    expect(
        "legacy outer mismatch count",
        len(provenance["result"]["legacy_minus32_plus32_mismatches"]),
        3,
    )
    for name, digest in provenance["fixture_sha256"].items():
        expect(f"fixture {name} SHA-256", sha256_file(THIS_DIR / name), digest)
    sample_lines = SAMPLES_FILE.read_text().splitlines()
    injection_lines = INJECTION_FILE.read_text().splitlines()
    expect("sample memory lines", len(sample_lines), WINDOWS * RAW_CAPTURE_SAMPLES)
    expect("injection memory lines", len(injection_lines), RAW_CAPTURE_SAMPLES)
    expect("injection is retained window zero", injection_lines, sample_lines[:RAW_CAPTURE_SAMPLES])
    packet_lines = PACKETS_FILE.read_text().splitlines()
    expect("packet memory lines", len(packet_lines), WINDOWS * 26)
    for index in range(WINDOWS):
        base = index * 26
        expect(f"packet {index} magic", int(packet_lines[base], 16), 0x3153_5350)
        expect(f"packet {index} flags", int(packet_lines[base + 1], 16), 0x1A01_0001)
        lag = int(packet_lines[base + 7], 16)
        if lag & 0x8000_0000:
            lag -= 1 << 32
        if not FIRST_LAG <= lag <= LAST_LAG:
            raise RuntimeError(f"packet {index} lag {lag} is outside frozen aperture")
    print(
        "AXI_REAL_REPLAY_FIXTURE_PASS "
        f"windows={WINDOWS} samples={WINDOWS * RAW_CAPTURE_SAMPLES} "
        f"injection_samples={RAW_CAPTURE_SAMPLES} packets={WINDOWS} "
        f"first_lag={FIRST_LAG} last_lag={LAST_LAG}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    generate_parser = subparsers.add_parser("generate")
    generate_parser.add_argument("--manifest", type=Path, required=True)
    generate_parser.add_argument("--chunk", type=Path, required=True)
    generate_parser.add_argument("--replay", type=Path, required=True)
    subparsers.add_parser("verify")
    arguments = parser.parse_args()
    if arguments.command == "generate":
        generate(arguments.manifest, arguments.chunk, arguments.replay)
    else:
        verify()


if __name__ == "__main__":
    main()
