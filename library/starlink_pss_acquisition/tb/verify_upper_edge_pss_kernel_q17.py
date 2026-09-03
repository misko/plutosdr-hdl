#!/usr/bin/env python3
"""Verify the immutable 18-bit upper-edge PSS kernel artifact."""

from __future__ import annotations

import hashlib
import struct
from pathlib import Path


WORD_COUNT = 512
COMPONENT_BITS = 18
HEX_DIGITS = 9
CANONICAL_BINARY_SHA256 = (
    "0fb4bcf5ce7e2dc7c9354cf3770a9630687b8abeccfbb913465bc19022b26ed7"
)
TEXT_SHA256 = (
    "694d0d9b8dd55368bcaaedec37a7cda3a837d491d592ede60eec57a9821fc99a"
)


def signed_component(value: int) -> int:
    sign_bit = 1 << (COMPONENT_BITS - 1)
    return value - (1 << COMPONENT_BITS) if value & sign_bit else value


def main() -> None:
    path = Path(__file__).with_name("upper_edge_pss_kernel_q17.mem")
    raw = path.read_bytes()
    lines = raw.decode("ascii").splitlines()
    if len(lines) != WORD_COUNT:
        raise SystemExit(f"expected {WORD_COUNT} words, got {len(lines)}")

    component_mask = (1 << COMPONENT_BITS) - 1
    canonical = bytearray()
    coefficients: list[int] = []
    for index, line in enumerate(lines):
        if len(line) != HEX_DIGITS or any(
            character not in "0123456789abcdef" for character in line
        ):
            raise SystemExit(
                f"word {index} is not exactly {HEX_DIGITS} lowercase "
                "hexadecimal digits"
            )
        word = int(line, 16)
        coefficient_i = signed_component(word & component_mask)
        coefficient_q = signed_component(
            (word >> COMPONENT_BITS) & component_mask
        )
        coefficients.extend((coefficient_i, coefficient_q))
        canonical.extend(struct.pack("<ii", coefficient_i, coefficient_q))

    canonical_digest = hashlib.sha256(canonical).hexdigest()
    text_digest = hashlib.sha256(raw).hexdigest()
    if canonical_digest != CANONICAL_BINARY_SHA256:
        raise SystemExit(f"canonical kernel SHA-256 mismatch: {canonical_digest}")
    if text_digest != TEXT_SHA256:
        raise SystemExit(f"memory-file SHA-256 mismatch: {text_digest}")

    print(
        "UPPER_EDGE_PSS_KERNEL_Q17_PASS "
        f"words={len(lines)} min={min(coefficients)} max={max(coefficients)} "
        f"canonical_sha256={canonical_digest} text_sha256={text_digest}"
    )


if __name__ == "__main__":
    main()
