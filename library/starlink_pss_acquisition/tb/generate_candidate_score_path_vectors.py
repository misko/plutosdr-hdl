#!/usr/bin/env python3
"""Generate exact integration vectors for one 512-point PSS score block."""

from __future__ import annotations

import argparse
from pathlib import Path

BASE_INDEX = 100_000
FFT_POINTS = 512
TEMPLATE_SAMPLES = 66
INVALID_PREFIX = TEMPLATE_SAMPLES - 1
COEFFICIENT_ENERGY = 1_073_742_825
RATIO_MAX = (1 << 69) - 1
FORWARD_EXPONENT = 2
INVERSE_EXPONENT = 2


def sample_i(offset: int) -> int:
    return offset * 31 - 7_000


def sample_q(offset: int) -> int:
    return 9_000 - offset * 29


def correlation_i(ifft_index: int) -> int:
    return -8_000_000 + ifft_index * 30_000


def correlation_q(ifft_index: int) -> int:
    return 7_000_000 - ifft_index * 25_000


def exact_score(numerator: int, denominator: int) -> int:
    if numerator == 0 or denominator == 0:
        return 0
    if numerator >= denominator:
        return 255
    quotient, remainder = divmod(255 * numerator, denominator)
    if 2 * remainder > denominator or (2 * remainder == denominator and quotient & 1):
        quotient += 1
    return quotient


def write_vectors(path: Path) -> None:
    powers = [
        sample_i(offset) ** 2 + sample_q(offset) ** 2 for offset in range(FFT_POINTS)
    ]
    lines = [str(FFT_POINTS - INVALID_PREFIX)]
    scores: list[int] = []
    for ifft_index in range(INVALID_PREFIX, FFT_POINTS):
        candidate_offset = ifft_index - INVALID_PREFIX
        energy = sum(powers[candidate_offset : candidate_offset + TEMPLATE_SAMPLES])
        power = correlation_i(ifft_index) ** 2 + correlation_q(ifft_index) ** 2
        mathematical_numerator = power << (
            2 * (1 + FORWARD_EXPONENT + INVERSE_EXPONENT)
        )
        numerator = min(mathematical_numerator, RATIO_MAX)
        denominator = energy * COEFFICIENT_ENERGY
        score = exact_score(numerator, denominator)
        scores.append(score)
        lines.append(f"{BASE_INDEX + candidate_offset:016x} {energy:010x} {score:02x}")

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="ascii")
    print(
        "CANDIDATE_SCORE_PATH_VECTORS_PASS "
        f"results={len(scores)} score_min={min(scores)} score_max={max(scores)} "
        f"distinct_scores={len(set(scores))}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    write_vectors(args.output)


if __name__ == "__main__":
    main()
