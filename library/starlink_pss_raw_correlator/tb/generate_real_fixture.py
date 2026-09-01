#!/usr/bin/env python3
"""Generate and independently verify the frozen Stage-15 raw-engine fixture.

Generation and receipt qualification require an explicit immutable capture
manifest and its first compressed chunk. Normal test runs use the separate
pure-standard-library checker and therefore need neither production storage nor
NumPy.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import platform
import subprocess
import sys
from pathlib import Path

import numpy as np

THIS_DIR = Path(__file__).resolve().parent
PARENT_REPOSITORY = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(PARENT_REPOSITORY))

from tests.starlink_oracle import (  # noqa: E402
    FIXED_CORRELATOR_SCHEMA,
    fixed_correlate_ci16,
    projected_pss,
    quantize_q15,
)
from tests.starlink_oracle.waveforms import PROJECTED_PSS_SHA256  # noqa: E402

CAPTURE_ID = "cap-20260831T071200-9184cf0ad6cc"
STREAM_ID = "stream-1"
RADIO_SERIAL = "10400056f695001322002d0010ad1719f2"
SAMPLE_RATE_HZ = 15_000_000
BANDWIDTH_HZ = 15_000_000
CENTER_FREQUENCY_HZ = 1_187_500_000
PREDICTED_START_SAMPLE = 1185
CAPTURE_FIRST_SAMPLE = PREDICTED_START_SAMPLE - 32
CAPTURE_SAMPLE_COUNT = 130
FIRST_DEVICE_SAMPLE_COUNTER = 480_554_573_351
CFO_HZ = -100_000
MANIFEST_SCHEMA_VERSION = 5
STREAM_SCHEMA_VERSION = 3
MANIFEST_STATE = "degraded"
STREAM_STATE = "partial"
FIRST_CHUNK_SAMPLE_COUNT = 4_194_304
FIRST_CHUNK_COMPRESSED_BYTES = 12_027_005
FIRST_CHUNK_UNCOMPRESSED_BYTES = 16_777_216
MANIFEST_SHA256 = "be6a196eaf0894667b835a73afe3aa83ff3200eadc0349b4a45cc5420f7b6f09"
COMPRESSED_SHA256 = "68732179d9e147e0f173677f810e032d5240fc3ba024cb9045fe17dff9f38946"
UNCOMPRESSED_SHA256 = "fd922ab9913b72e545ff526d99ebe884170170d2c817a6a56384740316d661ae"
QUALIFICATION_PYTHON_VERSION = "3.13.15"
QUALIFICATION_NUMPY_VERSION = "2.4.6"
QUALIFICATION_LAUNCH_POLICY = "uv-run-isolated-no-project-no-config-managed-python"
LOGICAL_URI = (
    "bulk://recordings/2026/08/31/"
    f"{CAPTURE_ID}/radio-{RADIO_SERIAL}/iq-000000.ci16.zst"
)
SAMPLES_FILE = THIS_DIR / "real_071200_samples_ci16.mem"
TIMESTAMPS_FILE = THIS_DIR / "real_071200_timestamps.mem"
COEFFICIENTS_FILE = THIS_DIR / "upper_minus100k_coefficients_q15.mem"
GOLDEN_FILE = THIS_DIR / "real_071200_golden_tuples.txt"
PROVENANCE_FILE = THIS_DIR / "real_071200_fixture_provenance.json"
QUALIFICATION_REQUIREMENTS_FILE = THIS_DIR.parent / "qualification-requirements.txt"


def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _sha256_file(path: Path) -> str:
    return _sha256_bytes(path.read_bytes())


def _expect(name: str, actual: object, expected: object) -> None:
    if actual != expected:
        raise RuntimeError(f"{name} must be {expected!r}, got {actual!r}")


def _validated_capture_authority(
    manifest_path: Path, chunk_path: Path
) -> tuple[dict[str, object], bytes]:
    """Validate the external authority before trusting bytes or timestamps."""

    _expect("recording manifest SHA-256", _sha256_file(manifest_path), MANIFEST_SHA256)
    manifest = json.loads(manifest_path.read_text())
    _expect("manifest schema", manifest.get("schema_version"), MANIFEST_SCHEMA_VERSION)
    _expect("manifest session", manifest.get("session_id"), CAPTURE_ID)
    _expect("manifest source type", manifest.get("source_type"), "live")
    _expect("manifest state", manifest.get("state"), MANIFEST_STATE)

    matching_streams = [
        stream for stream in manifest.get("streams", []) if stream.get("stream_id") == STREAM_ID
    ]
    if len(matching_streams) != 1:
        raise RuntimeError(f"expected exactly one {STREAM_ID}, got {len(matching_streams)}")
    stream = matching_streams[0]
    _expect("stream schema", stream.get("schema_version"), STREAM_SCHEMA_VERSION)
    _expect("stream state", stream.get("state"), STREAM_STATE)
    _expect("stream radio serial", stream["radio"].get("serial"), RADIO_SERIAL)

    for settings_name in ("requested_settings", "applied_settings"):
        settings = stream[settings_name]
        _expect(f"{settings_name} sample rate", settings.get("sample_rate_hz"), SAMPLE_RATE_HZ)
        _expect(f"{settings_name} bandwidth", settings.get("bandwidth_hz"), BANDWIDTH_HZ)
        _expect(
            f"{settings_name} center frequency",
            settings.get("center_frequency_hz"),
            CENTER_FREQUENCY_HZ,
        )
        _expect(f"{settings_name} receivers", settings.get("receiver_ids"), [1])

    continuity = stream["continuity"]
    _expect(
        "first device sample counter",
        continuity.get("first_device_sample_counter"),
        FIRST_DEVICE_SAMPLE_COUNTER,
    )
    _expect("sample-loss observability", continuity.get("sample_loss_observable"), True)

    matching_chunks = [
        chunk for chunk in stream.get("chunks", []) if chunk.get("chunk_index") == 0
    ]
    if len(matching_chunks) != 1:
        raise RuntimeError(f"expected exactly one chunk 0, got {len(matching_chunks)}")
    chunk = matching_chunks[0]
    expected_relative_path = f"radio-{RADIO_SERIAL}/iq-000000.ci16.zst"
    expected_chunk_fields = {
        "relative_path": expected_relative_path,
        "content_kind": "observed",
        "continuity_segment_index": 0,
        "device_sample_start": 0,
        "sample_count": FIRST_CHUNK_SAMPLE_COUNT,
        "sample_format": "ci16_le",
        "sample_layout": "sample_receiver_iq",
        "compressed_bytes": FIRST_CHUNK_COMPRESSED_BYTES,
        "uncompressed_bytes": FIRST_CHUNK_UNCOMPRESSED_BYTES,
        "compressed_sha256": f"sha256:{COMPRESSED_SHA256}",
        "uncompressed_sha256": f"sha256:{UNCOMPRESSED_SHA256}",
    }
    for field, expected in expected_chunk_fields.items():
        _expect(f"chunk 0 {field}", chunk.get(field), expected)
    _expect("chunk filename", chunk_path.name, Path(expected_relative_path).name)
    if CAPTURE_FIRST_SAMPLE + CAPTURE_SAMPLE_COUNT > FIRST_CHUNK_SAMPLE_COUNT:
        raise RuntimeError("fixture extends beyond the continuous observed chunk")

    compressed = chunk_path.read_bytes()
    _expect("compressed chunk size", len(compressed), FIRST_CHUNK_COMPRESSED_BYTES)
    _expect("compressed chunk SHA-256", _sha256_bytes(compressed), COMPRESSED_SHA256)
    completed = subprocess.run(
        ("zstd", "--decompress", "--stdout", str(chunk_path)),
        check=True,
        stdout=subprocess.PIPE,
    )
    raw = completed.stdout
    _expect("uncompressed chunk size", len(raw), FIRST_CHUNK_UNCOMPRESSED_BYTES)
    _expect("uncompressed chunk SHA-256", _sha256_bytes(raw), UNCOMPRESSED_SHA256)

    return (
        {
            "manifest_schema_version": MANIFEST_SCHEMA_VERSION,
            "manifest_sha256": MANIFEST_SHA256,
            "manifest_state": MANIFEST_STATE,
            "capture_id": CAPTURE_ID,
            "stream_id": STREAM_ID,
            "stream_schema_version": STREAM_SCHEMA_VERSION,
            "stream_state": STREAM_STATE,
            "radio_serial": RADIO_SERIAL,
            "sample_rate_hz": SAMPLE_RATE_HZ,
            "receiver_ids": [1],
            "first_device_sample_counter": FIRST_DEVICE_SAMPLE_COUNTER,
            "chunk_relative_path": expected_relative_path,
            "chunk_content_kind": "observed",
            "chunk_continuity_segment_index": 0,
            "chunk_compressed_sha256": COMPRESSED_SHA256,
            "chunk_uncompressed_sha256": UNCOMPRESSED_SHA256,
            "fixture_interval": [
                CAPTURE_FIRST_SAMPLE,
                CAPTURE_FIRST_SAMPLE + CAPTURE_SAMPLE_COUNT,
            ],
            "fixture_interval_continuous": True,
        },
        raw,
    )


def _pack_ci16_lines(values: np.ndarray) -> str:
    return "".join(
        f"{int(i) & 0xffff:04x}{int(q) & 0xffff:04x}\n" for i, q in values
    )


def _load_ci16_memory(path: Path) -> np.ndarray:
    words = [int(line, 16) for line in path.read_text().splitlines()]
    output = np.empty((len(words), 2), dtype=np.int16)
    for index, word in enumerate(words):
        output[index, 0] = np.asarray((word >> 16) & 0xFFFF, dtype=np.uint16).view(
            np.int16
        )
        output[index, 1] = np.asarray(word & 0xFFFF, dtype=np.uint16).view(np.int16)
    return output


def _conditioned_coefficients() -> np.ndarray:
    template = np.asarray(projected_pss(SAMPLE_RATE_HZ, "upper"), dtype=np.complex128)
    sample_indices = np.arange(template.size, dtype=np.float64)
    conditioned = template * np.exp(
        2j * np.pi * CFO_HZ * sample_indices / SAMPLE_RATE_HZ
    )
    return quantize_q15(conditioned)


def _golden_rows(samples: np.ndarray, timestamps: list[int], coefficients: np.ndarray):
    rows: list[tuple[int, int, int, int, int, int, int]] = []
    for lag_index in range(65):
        result = fixed_correlate_ci16(
            samples[lag_index : lag_index + 66], coefficients
        )
        rows.append(
            (
                lag_index - 32,
                timestamps[lag_index],
                result.real,
                result.imag,
                result.sample_energy,
                result.coefficient_energy,
                result.saturation_events,
            )
        )
    return rows


def generate(raw: bytes) -> None:
    """Regenerate only from bytes already validated against the manifest."""

    all_samples = np.frombuffer(raw, dtype="<i2").reshape(-1, 2)
    samples = np.asarray(
        all_samples[
            CAPTURE_FIRST_SAMPLE : CAPTURE_FIRST_SAMPLE + CAPTURE_SAMPLE_COUNT
        ],
        dtype=np.int16,
    )
    if samples.shape != (CAPTURE_SAMPLE_COUNT, 2):
        raise RuntimeError("capture chunk does not contain the requested 130 samples")
    timestamps = [
        FIRST_DEVICE_SAMPLE_COUNTER + CAPTURE_FIRST_SAMPLE + index
        for index in range(CAPTURE_SAMPLE_COUNT)
    ]
    coefficients = _conditioned_coefficients()
    if coefficients.shape != (66, 2):
        raise RuntimeError("conditioned Stage-15 coefficient bank is not 66 taps")
    rows = _golden_rows(samples, timestamps, coefficients)

    SAMPLES_FILE.write_text(_pack_ci16_lines(samples))
    TIMESTAMPS_FILE.write_text("".join(f"{value:016x}\n" for value in timestamps))
    COEFFICIENTS_FILE.write_text(_pack_ci16_lines(coefficients))
    GOLDEN_FILE.write_text(
        "# lag first_tap_timestamp C_re C_im Ex Eh saturation_events\n"
        + "".join(" ".join(str(value) for value in row) + "\n" for row in rows)
    )

    oracle_path = PARENT_REPOSITORY / "tests/starlink_oracle/fixed.py"
    coefficient_bytes = np.asarray(coefficients, dtype="<i2").tobytes(order="C")
    provenance = {
        "schema": "starlink-pss-raw-correlator-real-fixture-v1",
        "capture": {
            "capture_id": CAPTURE_ID,
            "stream_id": STREAM_ID,
            "radio_serial": RADIO_SERIAL,
            "sample_rate_hz": SAMPLE_RATE_HZ,
            "manifest_sha256": MANIFEST_SHA256,
            "chunk_logical_uri": LOGICAL_URI,
            "chunk_compressed_sha256": COMPRESSED_SHA256,
            "chunk_uncompressed_sha256": UNCOMPRESSED_SHA256,
            "chunk_sample_format": "ci16_le",
            "chunk_receiver_ids": [1],
            "first_device_sample_counter": FIRST_DEVICE_SAMPLE_COUNTER,
            "predicted_start_sample": PREDICTED_START_SAMPLE,
            "fixture_first_sample": CAPTURE_FIRST_SAMPLE,
            "fixture_sample_count": CAPTURE_SAMPLE_COUNT,
        },
        "coefficient_bank": {
            "edge": "upper",
            "cfo_hz": CFO_HZ,
            "sample_rate_hz": SAMPLE_RATE_HZ,
            "tap_count": 66,
            "projected_complex64_sha256": PROJECTED_PSS_SHA256[
                (SAMPLE_RATE_HZ, "upper")
            ],
            "conditioned_q15_le_sha256": _sha256_bytes(coefficient_bytes),
            "quantizer": "clip(rint(x*32768),-32768,32767)",
        },
        "golden": {
            "oracle_schema": FIXED_CORRELATOR_SCHEMA,
            "oracle_relative_path": "tests/starlink_oracle/fixed.py",
            "oracle_sha256": _sha256_file(oracle_path),
            "lag_order": [-32, 32],
            "tuple_fields": [
                "lag",
                "first_tap_timestamp",
                "C_re",
                "C_im",
                "Ex",
                "Eh",
                "saturation_events",
            ],
        },
        "fixture_file_sha256": {
            path.name: _sha256_file(path)
            for path in (
                SAMPLES_FILE,
                TIMESTAMPS_FILE,
                COEFFICIENTS_FILE,
                GOLDEN_FILE,
            )
        },
    }
    PROVENANCE_FILE.write_text(json.dumps(provenance, indent=2, sort_keys=True) + "\n")


def verify() -> list[tuple[int, ...]]:
    provenance = json.loads(PROVENANCE_FILE.read_text())
    if provenance["schema"] != "starlink-pss-raw-correlator-real-fixture-v1":
        raise RuntimeError("unexpected fixture provenance schema")
    expected_capture = {
        "capture_id": CAPTURE_ID,
        "stream_id": STREAM_ID,
        "radio_serial": RADIO_SERIAL,
        "sample_rate_hz": SAMPLE_RATE_HZ,
        "manifest_sha256": MANIFEST_SHA256,
        "chunk_logical_uri": LOGICAL_URI,
        "chunk_compressed_sha256": COMPRESSED_SHA256,
        "chunk_uncompressed_sha256": UNCOMPRESSED_SHA256,
        "chunk_sample_format": "ci16_le",
        "chunk_receiver_ids": [1],
        "first_device_sample_counter": FIRST_DEVICE_SAMPLE_COUNTER,
        "predicted_start_sample": PREDICTED_START_SAMPLE,
        "fixture_first_sample": CAPTURE_FIRST_SAMPLE,
        "fixture_sample_count": CAPTURE_SAMPLE_COUNT,
    }
    for name, expected in expected_capture.items():
        _expect(f"frozen provenance capture.{name}", provenance["capture"].get(name), expected)
    expected_bank = {
        "edge": "upper",
        "cfo_hz": CFO_HZ,
        "sample_rate_hz": SAMPLE_RATE_HZ,
        "tap_count": 66,
        "projected_complex64_sha256": PROJECTED_PSS_SHA256[(SAMPLE_RATE_HZ, "upper")],
        "quantizer": "clip(rint(x*32768),-32768,32767)",
    }
    for name, expected in expected_bank.items():
        _expect(
            f"frozen provenance coefficient_bank.{name}",
            provenance["coefficient_bank"].get(name),
            expected,
        )
    _expect(
        "golden oracle schema",
        provenance["golden"].get("oracle_schema"),
        FIXED_CORRELATOR_SCHEMA,
    )
    _expect(
        "golden oracle path",
        provenance["golden"].get("oracle_relative_path"),
        "tests/starlink_oracle/fixed.py",
    )
    oracle_path = PARENT_REPOSITORY / provenance["golden"]["oracle_relative_path"]
    _expect(
        "golden oracle SHA-256",
        _sha256_file(oracle_path),
        provenance["golden"]["oracle_sha256"],
    )
    _expect("golden lag order", provenance["golden"].get("lag_order"), [-32, 32])

    expected_fixture_names = {
        SAMPLES_FILE.name,
        TIMESTAMPS_FILE.name,
        COEFFICIENTS_FILE.name,
        GOLDEN_FILE.name,
    }
    _expect(
        "fixture digest inventory",
        set(provenance["fixture_file_sha256"]),
        expected_fixture_names,
    )
    for name, expected in provenance["fixture_file_sha256"].items():
        actual = _sha256_file(THIS_DIR / name)
        if actual != expected:
            raise RuntimeError(f"fixture SHA-256 mismatch for {name}: {actual}")

    samples = _load_ci16_memory(SAMPLES_FILE)
    coefficients = _load_ci16_memory(COEFFICIENTS_FILE)
    recomputed_coefficients = _conditioned_coefficients()
    if not np.array_equal(coefficients, recomputed_coefficients):
        raise RuntimeError("frozen coefficient bank differs from the waveform oracle")
    coefficient_bytes = np.asarray(coefficients, dtype="<i2").tobytes(order="C")
    _expect(
        "conditioned coefficient SHA-256",
        _sha256_bytes(coefficient_bytes),
        provenance["coefficient_bank"]["conditioned_q15_le_sha256"],
    )
    timestamps = [int(line, 16) for line in TIMESTAMPS_FILE.read_text().splitlines()]
    if len(samples) != 130 or len(timestamps) != 130 or len(coefficients) != 66:
        raise RuntimeError("frozen fixture geometry changed")
    expected_timestamps = [
        FIRST_DEVICE_SAMPLE_COUNTER + CAPTURE_FIRST_SAMPLE + index
        for index in range(CAPTURE_SAMPLE_COUNT)
    ]
    if timestamps != expected_timestamps:
        raise RuntimeError("frozen raw timestamps are not the declared capture indices")

    frozen_rows = []
    for line in GOLDEN_FILE.read_text().splitlines():
        if line and not line.startswith("#"):
            frozen_rows.append(tuple(int(value) for value in line.split()))
    recomputed_rows = _golden_rows(samples, timestamps, coefficients)
    if frozen_rows != recomputed_rows:
        raise RuntimeError("frozen tuples differ from the independent Python oracle")
    if [row[0] for row in frozen_rows] != list(range(-32, 33)):
        raise RuntimeError("frozen result order is not exactly -32 through +32")
    print(
        "PYTHON_ORACLE_PASS "
        f"rows={len(frozen_rows)} eh={frozen_rows[0][5]} "
        f"best_fixture_lag={max(frozen_rows, key=lambda row: row[2]**2 + row[3]**2)[0]}"
    )
    return frozen_rows


def _verify_frozen_slice(raw: bytes) -> None:
    byte_start = CAPTURE_FIRST_SAMPLE * 4
    byte_stop = (CAPTURE_FIRST_SAMPLE + CAPTURE_SAMPLE_COUNT) * 4
    frozen_bytes = np.asarray(_load_ci16_memory(SAMPLES_FILE), dtype="<i2").tobytes(
        order="C"
    )
    if raw[byte_start:byte_stop] != frozen_bytes:
        raise RuntimeError("frozen 130-sample fixture differs from the manifest-bound chunk")


def _write_qualification_receipt(
    receipt_path: Path,
    authority: dict[str, object],
    frozen_rows: list[tuple[int, ...]],
) -> None:
    python_version = platform.python_version()
    _expect("qualification Python", python_version, QUALIFICATION_PYTHON_VERSION)
    _expect("qualification NumPy", np.__version__, QUALIFICATION_NUMPY_VERSION)
    uv_version = os.environ.get("STARLINK_QUALIFICATION_UV_VERSION")
    if not uv_version:
        raise RuntimeError("qualification receipt requires the pinned uv launcher")
    _expect(
        "qualification launch policy",
        os.environ.get("STARLINK_QUALIFICATION_LAUNCH_POLICY"),
        QUALIFICATION_LAUNCH_POLICY,
    )

    oracle_directory = PARENT_REPOSITORY / "tests/starlink_oracle"
    oracle_files = tuple(
        oracle_directory / name
        for name in ("__init__.py", "fixed.py", "numerology.py", "search.py", "waveforms.py")
    )
    source_files = (
        Path(__file__).resolve(),
        QUALIFICATION_REQUIREMENTS_FILE,
        THIS_DIR.parent / "run_fixture_qualification.sh",
        PROVENANCE_FILE,
        *oracle_files,
    )
    provenance = json.loads(PROVENANCE_FILE.read_text())
    best_row = max(frozen_rows, key=lambda row: row[2] ** 2 + row[3] ** 2)
    payload = {
        "schema": "starlink-pss-raw-correlator-fixture-qualification-v1",
        "outcome": "PASS",
        "generated_utc": dt.datetime.now(dt.UTC).isoformat(),
        "claim": "algorithm fixture provenance and oracle equivalence only",
        "environment": {
            "python_version": python_version,
            "numpy_version": np.__version__,
            "uv_version": uv_version,
            "platform": platform.platform(),
            "requirements_sha256": _sha256_file(QUALIFICATION_REQUIREMENTS_FILE),
        },
        "launch_policy": {
            "uv_run": True,
            "isolated": True,
            "no_project": True,
            "no_config": True,
            "managed_python": True,
            "python_version": QUALIFICATION_PYTHON_VERSION,
            "requirements_relative_path": QUALIFICATION_REQUIREMENTS_FILE.relative_to(
                PARENT_REPOSITORY
            ).as_posix(),
            "receipt_creation": "exclusive_create",
        },
        "authority": authority,
        "source_file_sha256": {
            path.relative_to(PARENT_REPOSITORY).as_posix(): _sha256_file(path)
            for path in source_files
        },
        "fixture_file_sha256": provenance["fixture_file_sha256"],
        "result": {
            "row_count": len(frozen_rows),
            "first_lag": frozen_rows[0][0],
            "last_lag": frozen_rows[-1][0],
            "coefficient_energy": frozen_rows[0][5],
            "best_fixture_lag": best_row[0],
        },
    }
    receipt_path.parent.mkdir(parents=True, exist_ok=True)
    with receipt_path.open("x") as receipt:
        json.dump(payload, receipt, indent=2, sort_keys=True)
        receipt.write("\n")
    print(
        "FIXTURE_QUALIFICATION_PASS "
        f"receipt={receipt_path.resolve()} sha256={_sha256_file(receipt_path)}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--verify-only", action="store_true")
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--chunk", type=Path)
    parser.add_argument("--receipt", type=Path)
    args = parser.parse_args()

    if (args.manifest is None) != (args.chunk is None):
        parser.error("--manifest and --chunk must be supplied together")

    authority = None
    raw = None
    if args.manifest is not None and args.chunk is not None:
        authority, raw = _validated_capture_authority(args.manifest, args.chunk)
    if not args.verify_only:
        if raw is None:
            parser.error("fixture generation requires explicit --manifest and --chunk")
        generate(raw)
    frozen_rows = verify()
    if raw is not None:
        _verify_frozen_slice(raw)
        print(
            "CAPTURE_AUTHORITY_PASS "
            f"manifest_state={authority['manifest_state']} "
            f"stream_state={authority['stream_state']} continuous_fixture_interval=true"
        )
    if args.receipt is not None:
        if authority is None:
            parser.error("--receipt requires explicit --manifest and --chunk")
        _write_qualification_receipt(args.receipt, authority, frozen_rows)


if __name__ == "__main__":
    main()
