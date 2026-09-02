#!/usr/bin/env python3
"""Generate deterministic exact vectors for PSS score-ratio preparation."""

from __future__ import annotations

import argparse
import random
from pathlib import Path

COEFFICIENT_ENERGY = 1_073_742_825
RATIO_BITS = 69
RATIO_MAX = (1 << RATIO_BITS) - 1
ENERGY_MAX = (1 << 38) - 1
CORRELATION_MIN = -(1 << 23)
CORRELATION_MAX = (1 << 23) - 1


def prepare_ratio(
    correlation_i: int,
    correlation_q: int,
    sample_energy: int,
    forward_exponent: int,
    inverse_exponent: int,
) -> tuple[int, int, int, bool]:
    power = correlation_i * correlation_i + correlation_q * correlation_q
    power_shift = 2 * (1 + forward_exponent + inverse_exponent)
    mathematical_numerator = power << power_shift
    saturated = mathematical_numerator > RATIO_MAX
    numerator = RATIO_MAX if saturated else mathematical_numerator
    denominator = sample_energy * COEFFICIENT_ENERGY
    if denominator > RATIO_MAX:
        raise AssertionError("31-by-38-bit denominator exceeded 69 bits")
    return numerator, denominator, power_shift, saturated


def directed_vectors() -> list[tuple[int, int, int, int, int]]:
    return [
        (0, 0, 0, 0, 0),
        (0, 0, 1, 0, 0),
        (1, 0, 1, 0, 0),
        (-1, 1, 1, 0, 0),
        (CORRELATION_MIN, CORRELATION_MIN, ENERGY_MAX, 0, 0),
        (CORRELATION_MAX, CORRELATION_MAX, ENERGY_MAX, 0, 0),
        (CORRELATION_MIN, 0, ENERGY_MAX, 9, 0),
        (1, 0, ENERGY_MAX, 0, 31),
        (1, 0, ENERGY_MAX, 31, 0),
        (1, 0, ENERGY_MAX, 31, 31),
        (3, -5, 7, 1, 2),
        (-0x123456, 0x654321, 0x123456789A, 2, 1),
        (CORRELATION_MAX, 0, 1, 1, 1),
        (0, CORRELATION_MIN, 0, 2, 2),
        (1, 0, ENERGY_MAX, 0, 0),
        (-2, -3, ENERGY_MAX, 8, 1),
    ]


def encode_signed_24(value: int) -> int:
    return value & ((1 << 24) - 1)


def write_vectors(path: Path, random_count: int) -> None:
    rng = random.Random(0x50535369)
    vectors = directed_vectors()
    for ordinal in range(random_count):
        if ordinal % 4 == 0:
            forward_exponent = rng.randint(0, 2)
            inverse_exponent = rng.randint(0, 2)
        else:
            forward_exponent = rng.randint(0, 31)
            inverse_exponent = rng.randint(0, 31)
        vectors.append(
            (
                rng.randint(CORRELATION_MIN, CORRELATION_MAX),
                rng.randint(CORRELATION_MIN, CORRELATION_MAX),
                rng.randint(0, ENERGY_MAX),
                forward_exponent,
                inverse_exponent,
            )
        )

    lines = [str(len(vectors))]
    saturation_count = 0
    zero_denominator_count = 0
    for correlation_i, correlation_q, energy, forward, inverse in vectors:
        numerator, denominator, shift, saturated = prepare_ratio(
            correlation_i, correlation_q, energy, forward, inverse
        )
        saturation_count += int(saturated)
        zero_denominator_count += int(denominator == 0)
        lines.append(
            f"{encode_signed_24(correlation_i):06x} "
            f"{encode_signed_24(correlation_q):06x} {energy:010x} "
            f"{forward:02x} {inverse:02x} {numerator:018x} "
            f"{denominator:018x} {shift:02x} {int(saturated)} "
            f"{int(denominator == 0)}"
        )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="ascii")
    print(
        "SCORE_PREPARE_VECTORS_PASS "
        f"vectors={len(vectors)} random={random_count} "
        f"saturated={saturation_count} denominator_zero={zero_denominator_count}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    parser.add_argument("--random-count", type=int, default=4096)
    args = parser.parse_args()
    if args.random_count < 0:
        parser.error("--random-count must be nonnegative")
    write_vectors(args.output, args.random_count)


if __name__ == "__main__":
    main()
