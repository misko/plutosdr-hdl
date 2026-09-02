#!/usr/bin/env python3
"""Verify the immutable 512-bin upper-edge PSS kernel artifact."""

from __future__ import annotations

import hashlib
import struct
from pathlib import Path


WORD_COUNT = 512
CANONICAL_BINARY_SHA256 = (
    "d96c56b3d6bcd03419a57f23f3ce4929f1e478663119f5cb5ec9b14327b7ff2b"
)
TEXT_SHA256 = (
    "7c89ff2a026f5fab91e655ab969ac07c11bf9715215173dadec07084527aea7d"
)


def signed_q23(value: int) -> int:
    return value - (1 << 24) if value & (1 << 23) else value


def main() -> None:
    path = Path(__file__).with_name("upper_edge_pss_kernel_q23.mem")
    raw = path.read_bytes()
    lines = raw.decode("ascii").splitlines()
    if len(lines) != WORD_COUNT:
        raise SystemExit(f"expected {WORD_COUNT} words, got {len(lines)}")

    canonical = bytearray()
    coefficients: list[int] = []
    for index, line in enumerate(lines):
        if len(line) != 12 or any(
            character not in "0123456789abcdef" for character in line
        ):
            raise SystemExit(
                f"word {index} is not exactly 12 lowercase hexadecimal digits"
            )
        word = int(line, 16)
        coefficient_i = signed_q23(word & 0xFFFFFF)
        coefficient_q = signed_q23((word >> 24) & 0xFFFFFF)
        coefficients.extend((coefficient_i, coefficient_q))
        canonical.extend(struct.pack("<ii", coefficient_i, coefficient_q))

    canonical_digest = hashlib.sha256(canonical).hexdigest()
    text_digest = hashlib.sha256(raw).hexdigest()
    if canonical_digest != CANONICAL_BINARY_SHA256:
        raise SystemExit(f"canonical kernel SHA-256 mismatch: {canonical_digest}")
    if text_digest != TEXT_SHA256:
        raise SystemExit(f"memory-file SHA-256 mismatch: {text_digest}")

    print(
        "UPPER_EDGE_PSS_KERNEL_PASS "
        f"words={len(lines)} min={min(coefficients)} max={max(coefficients)} "
        f"canonical_sha256={canonical_digest} text_sha256={text_digest}"
    )


if __name__ == "__main__":
    main()
