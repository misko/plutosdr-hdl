#!/usr/bin/env python3
"""Generate deterministic exact-rational vectors for the score divider."""

from __future__ import annotations

import argparse
import random
from pathlib import Path

RATIO_BITS = 69
RATIO_MAX = (1 << RATIO_BITS) - 1
SCORE_MAX = 255


def normalized_score(numerator: int, denominator: int) -> int:
    if numerator <= 0 or denominator <= 0:
        return 0
    if numerator >= denominator:
        return SCORE_MAX
    quotient, remainder = divmod(numerator * SCORE_MAX, denominator)
    doubled = remainder * 2
    if doubled > denominator or (
        doubled == denominator and quotient & 1
    ):
        quotient += 1
    return quotient


def directed_vectors() -> list[tuple[int, int]]:
    return [
        (0, 0),
        (0, 1),
        (1, 0),
        (1, 2),  # 127.5, odd floor rounds up to even 128.
        (1, 6),  # 42.5, even floor stays at 42.
        (1, 3),
        (2, 3),
        (1, 510),  # 0.5 LSB, even zero.
        (3, 510),  # 1.5 LSB, odd one rounds to even two.
        (509, 510),
        (510, 510),
        (511, 510),
        (RATIO_MAX - 1, RATIO_MAX),
        (RATIO_MAX, RATIO_MAX),
        (RATIO_MAX, RATIO_MAX - 1),
        (0x123456789ABCDEF01, 0x1EDCBA9876543210F),
    ]


def write_vectors(path: Path, random_count: int) -> None:
    rng = random.Random(0x50535308)
    vectors = directed_vectors()
    for _ in range(random_count):
        vectors.append(
            (rng.randint(0, RATIO_MAX), rng.randint(0, RATIO_MAX))
        )
    lines = [str(len(vectors))]
    for numerator, denominator in vectors:
        lines.append(
            f"{numerator:018x} {denominator:018x} "
            f"{normalized_score(numerator, denominator):02x} "
            f"{int(denominator == 0)}"
        )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="ascii")
    print(
        "SCORE_DIVIDER_VECTORS_PASS "
        f"vectors={len(vectors)} random={random_count}"
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
