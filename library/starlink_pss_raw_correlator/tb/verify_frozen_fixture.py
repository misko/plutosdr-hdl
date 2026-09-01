#!/usr/bin/env python3
"""Pure-stdlib, independent check of the frozen raw-correlator fixture."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

THIS_DIR = Path(__file__).resolve().parent
PARENT_REPOSITORY = Path(__file__).resolve().parents[4]
PROVENANCE_FILE = THIS_DIR / "real_071200_fixture_provenance.json"
ACCUMULATOR_MIN = -(1 << 47)
ACCUMULATOR_MAX = (1 << 47) - 1
TAP_COUNT = 66
MAX_COMPONENT_MAGNITUDE = 1 << 15
MAX_COMPLETE_TAP_MAGNITUDE = 2 * MAX_COMPONENT_MAGNITUDE**2
MAX_LEGAL_ACCUMULATOR_MAGNITUDE = TAP_COUNT * MAX_COMPLETE_TAP_MAGNITUDE


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def signed16(value: int) -> int:
    return value - (1 << 16) if value & (1 << 15) else value


def load_ci16(path: Path) -> list[tuple[int, int]]:
    output = []
    for line in path.read_text().splitlines():
        word = int(line, 16)
        output.append((signed16(word >> 16), signed16(word & 0xFFFF)))
    return output


def saturating_add(accumulator: int, addend: int) -> tuple[int, int]:
    total = accumulator + addend
    if total > ACCUMULATOR_MAX:
        return ACCUMULATOR_MAX, 1
    if total < ACCUMULATOR_MIN:
        return ACCUMULATOR_MIN, 1
    return total, 0


def correlate(
    samples: list[tuple[int, int]], coefficients: list[tuple[int, int]]
) -> tuple[int, int, int, int, int]:
    real = imag = sample_energy = coefficient_energy = saturation_events = 0
    for (sample_i, sample_q), (coefficient_i, coefficient_q) in zip(
        samples, coefficients, strict=True
    ):
        additions = (
            sample_i * coefficient_i + sample_q * coefficient_q,
            sample_q * coefficient_i - sample_i * coefficient_q,
            sample_i * sample_i + sample_q * sample_q,
            coefficient_i * coefficient_i + coefficient_q * coefficient_q,
        )
        accumulators = (real, imag, sample_energy, coefficient_energy)
        updated = []
        for accumulator, addend in zip(accumulators, additions, strict=True):
            value, event = saturating_add(accumulator, addend)
            updated.append(value)
            saturation_events += event
        real, imag, sample_energy, coefficient_energy = updated
    return real, imag, sample_energy, coefficient_energy, saturation_events


def main() -> None:
    # Every complete correlation or energy addend has magnitude <= 2^31.
    # Therefore no legal fixed-geometry engine job can reach either 48-bit
    # rail.  Positive rail-event behavior is tested on the shared primitive;
    # the structural checker proves that both primitive events feed the ABI.
    if MAX_LEGAL_ACCUMULATOR_MAGNITUDE > ACCUMULATOR_MAX:
        raise RuntimeError("the legal 66-tap arithmetic bound can reach a 48-bit rail")

    provenance = json.loads(PROVENANCE_FILE.read_text())
    if provenance["schema"] != "starlink-pss-raw-correlator-real-fixture-v1":
        raise RuntimeError("unexpected fixture schema")
    for filename, expected in provenance["fixture_file_sha256"].items():
        actual = sha256(THIS_DIR / filename)
        if actual != expected:
            raise RuntimeError(f"SHA-256 mismatch for {filename}: {actual}")
    oracle_path = PARENT_REPOSITORY / provenance["golden"]["oracle_relative_path"]
    if sha256(oracle_path) != provenance["golden"]["oracle_sha256"]:
        raise RuntimeError("the versioned Python fixed-point oracle changed")

    samples = load_ci16(THIS_DIR / "real_071200_samples_ci16.mem")
    coefficients = load_ci16(THIS_DIR / "upper_minus100k_coefficients_q15.mem")
    timestamps = [
        int(line, 16)
        for line in (THIS_DIR / "real_071200_timestamps.mem").read_text().splitlines()
    ]
    if (len(samples), len(coefficients), len(timestamps)) != (130, 66, 130):
        raise RuntimeError("fixture geometry changed")
    capture = provenance["capture"]
    first_timestamp = (
        capture["first_device_sample_counter"] + capture["fixture_first_sample"]
    )
    if timestamps != list(range(first_timestamp, first_timestamp + 130)):
        raise RuntimeError("stored raw timestamps changed")

    frozen_rows = [
        tuple(int(value) for value in line.split())
        for line in (THIS_DIR / "real_071200_golden_tuples.txt").read_text().splitlines()
        if line and not line.startswith("#")
    ]
    recomputed_rows = []
    for index in range(65):
        real, imag, ex, eh, saturation_events = correlate(
            samples[index : index + 66], coefficients
        )
        recomputed_rows.append(
            (
                index - 32,
                timestamps[index],
                real,
                imag,
                ex,
                eh,
                saturation_events,
            )
        )
    if frozen_rows != recomputed_rows:
        raise RuntimeError("golden tuples fail the independent integer model")
    print(
        "INDEPENDENT_FIXTURE_PASS "
        f"rows={len(frozen_rows)} first_lag={frozen_rows[0][0]} "
        f"last_lag={frozen_rows[-1][0]} eh={frozen_rows[0][5]} "
        f"legal_peak_bound={MAX_LEGAL_ACCUMULATOR_MAGNITUDE}"
    )


if __name__ == "__main__":
    main()
