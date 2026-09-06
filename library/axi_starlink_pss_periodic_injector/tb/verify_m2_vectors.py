#!/usr/bin/env python3
"""Verify immutable M2 periodic samples, score profile, and timing matrix."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

SAMPLES_SHA256 = "ab6211c0450c033d620ff3f423719c5d1bc09e78edc0e161e4c2db8384db6da0"
SCORES_SHA256 = "cc3904e652c80ed51bca28f4dd110caaae1dceef33b95a0d827698c4063f468b"
SCORE_BINARY_SHA256 = "a93aa4939aeb94ccc62ea0047fa04ef45a77e7c84b06d8dd9d3109826dd36092"


def main() -> None:
    directory = Path(__file__).resolve().parent
    samples = (directory / "m2_period_samples_ci16.mem").read_bytes()
    scores_raw = (directory / "m2_period_scores_u8.mem").read_bytes()
    evidence = json.loads((directory / "m2_periodic_vectors.json").read_text())

    if hashlib.sha256(samples).hexdigest() != SAMPLES_SHA256:
        raise SystemExit("M2 sample-vector SHA-256 mismatch")
    if hashlib.sha256(scores_raw).hexdigest() != SCORES_SHA256:
        raise SystemExit("M2 score-vector SHA-256 mismatch")
    sample_lines = samples.decode("ascii").splitlines()
    score_lines = scores_raw.decode("ascii").splitlines()
    if len(sample_lines) != 20_180 or len(score_lines) != 20_000:
        raise SystemExit("M2 vector geometry mismatch")
    scores = bytes(int(line, 16) for line in score_lines)
    if hashlib.sha256(scores).hexdigest() != SCORE_BINARY_SHA256:
        raise SystemExit("M2 score binary SHA-256 mismatch")
    peak = max(scores)
    if peak != 255 or [i for i, value in enumerate(scores) if value == peak] != [32]:
        raise SystemExit("M2 score profile no longer has one exact peak at 32")

    if evidence.get("schema") != "starlink-pss15-m2-periodic-vectors-v1":
        raise SystemExit("M2 evidence schema mismatch")
    if evidence.get("data_bits") != 18:
        raise SystemExit("M2 XFFT data-width mismatch")
    if (
        evidence.get("input_sample_count") != 20_180
        or evidence.get("scheduled_score_count") != 20_115
    ):
        raise SystemExit("M2 overlap-save completion geometry mismatch")
    if (
        evidence.get("forward_overflow_blocks") != 0
        or evidence.get("inverse_overflow_blocks") != 0
        or evidence.get("product_overflow_blocks") != 0
    ):
        raise SystemExit("M2 bit-accurate oracle overflowed")
    matrix = evidence.get("timing_matrix")
    if not isinstance(matrix, list) or len(matrix) != 16:
        raise SystemExit("M2 timing matrix size mismatch")
    required_phases = {0, 1, 32, 129, 10_000, 19_999}
    phases = {row["expected_peak_phase"] for row in matrix}
    if not required_phases.issubset(phases):
        raise SystemExit("M2 timing matrix lost an edge phase")
    for row in matrix:
        expected = (row["injection_start"] + 32 - row["map_start"]) % 20_000
        if row["expected_peak_phase"] != expected:
            raise SystemExit(f"M2 timing case {row['case']} mapping mismatch")
        if row["expected_peak_absolute_index"] != row["map_start"] + expected:
            raise SystemExit(f"M2 timing case {row['case']} absolute index mismatch")
        if row["peak_value"] != 16_320 or row["runner_up_value"] != 7_424:
            raise SystemExit(f"M2 timing case {row['case']} map score mismatch")

    print(
        "M2_PERIODIC_VECTORS_VERIFY_PASS "
        f"samples={len(sample_lines)} scores={len(score_lines)} cases={len(matrix)} "
        f"score_binary_sha256={SCORE_BINARY_SHA256}"
    )


if __name__ == "__main__":
    main()
