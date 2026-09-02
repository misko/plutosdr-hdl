#!/usr/bin/env python3
"""Generate deterministic Q1.23 complex-product vectors for RTL replay."""

from __future__ import annotations

import argparse
import random
from pathlib import Path


WIDTH = 24
FRACTION_BITS = 23
PRODUCT_SAFETY_SHIFT = 1
ROUND_SHIFT = FRACTION_BITS + PRODUCT_SAFETY_SHIFT
SIGNED_MIN = -(1 << (WIDTH - 1))
SIGNED_MAX = (1 << (WIDTH - 1)) - 1
MASK = (1 << WIDTH) - 1


def round_shift_ties_even(value: int, shift: int) -> int:
    divisor = 1 << shift
    quotient, remainder = divmod(value, divisor)
    twice_remainder = remainder << 1
    if twice_remainder > divisor or (
        twice_remainder == divisor and quotient & 1
    ):
        quotient += 1
    return quotient


def saturate(value: int) -> tuple[int, int]:
    if value > SIGNED_MAX:
        return SIGNED_MAX, 1
    if value < SIGNED_MIN:
        return SIGNED_MIN, 1
    return value, 0


def complex_product(
    left_i: int,
    left_q: int,
    kernel_i: int,
    kernel_q: int,
) -> tuple[int, int, int]:
    real = left_i * kernel_i - left_q * kernel_q
    imag = left_i * kernel_q + left_q * kernel_i
    rounded_real = round_shift_ties_even(real, ROUND_SHIFT)
    rounded_imag = round_shift_ties_even(imag, ROUND_SHIFT)
    output_i, overflow_i = saturate(rounded_real)
    output_q, overflow_q = saturate(rounded_imag)
    return output_i, output_q, overflow_i | overflow_q


def as_hex(value: int) -> str:
    return f"{value & MASK:06x}"


def directed_vectors() -> list[tuple[int, int, int, int]]:
    half_scale = 1 << 22
    return [
        (0, 0, 0, 0),
        (1, 0, 1, 0),
        (2, 0, half_scale, 0),  # +0.5 LSB -> even zero.
        (6, 0, half_scale, 0),  # +1.5 LSB -> even two.
        (-2, 0, half_scale, 0),  # -0.5 LSB -> even zero.
        (-6, 0, half_scale, 0),  # -1.5 LSB -> even negative two.
        (0, 2, 0, half_scale),  # Negative real half-way tie.
        (0, -6, 0, half_scale),
        (SIGNED_MAX, SIGNED_MAX, SIGNED_MAX, SIGNED_MAX),
        (SIGNED_MIN, SIGNED_MIN, SIGNED_MIN, SIGNED_MAX),
        (SIGNED_MIN, SIGNED_MIN, SIGNED_MAX, SIGNED_MIN),
        (SIGNED_MAX, SIGNED_MIN, SIGNED_MIN, SIGNED_MAX),
        (SIGNED_MIN, SIGNED_MAX, SIGNED_MAX, SIGNED_MIN),
        (SIGNED_MIN, 0, SIGNED_MIN, 0),
        (SIGNED_MAX, 0, SIGNED_MAX, 0),
        (1234567, -7654321, -3456789, 4567890),
    ]


def generate_vectors(random_count: int) -> list[tuple[int, int, int, int]]:
    rng = random.Random(0x50535324)
    vectors = directed_vectors()
    for _ in range(random_count):
        vectors.append(
            tuple(rng.randint(SIGNED_MIN, SIGNED_MAX) for _ in range(4))
        )
    return vectors


def write_vectors(path: Path, random_count: int) -> None:
    vectors = generate_vectors(random_count)
    lines = [str(len(vectors))]
    overflow_count = 0
    for left_i, left_q, kernel_i, kernel_q in vectors:
        output_i, output_q, overflow = complex_product(
            left_i, left_q, kernel_i, kernel_q
        )
        overflow_count += overflow
        lines.append(
            " ".join(
                (
                    as_hex(left_i),
                    as_hex(left_q),
                    as_hex(kernel_i),
                    as_hex(kernel_q),
                    as_hex(output_i),
                    as_hex(output_q),
                    str(overflow),
                )
            )
        )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="ascii")
    print(
        "SPECTRUM_PRODUCT_VECTORS_PASS "
        f"vectors={len(vectors)} random={random_count} "
        f"overflow_vectors={overflow_count}"
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
