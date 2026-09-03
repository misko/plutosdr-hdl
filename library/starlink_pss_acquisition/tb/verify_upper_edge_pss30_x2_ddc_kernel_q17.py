#!/usr/bin/env python3
"""Verify the immutable 18-bit kernel bound to the 30->15 MS/s DDC."""

from __future__ import annotations

import hashlib
import json
import struct
from pathlib import Path


WORD_COUNT = 512
COMPONENT_BITS = 18
HEX_DIGITS = 9
CANONICAL_BINARY_SHA256 = (
    "926a6477ded55f163a888945ec35ccf4fa55614beea62339fc19f266721d6b8f"
)
TEXT_SHA256 = (
    "23996c80f79f112ea7739049050ad8cb2c85a8067792889bf2a774886ac2ce24"
)
DDC_CONTRACT_SHA256 = (
    "731426047077b036f9213db3574e4a556fd424b97a293843bd6ee085c2bf33af"
)
COEFFICIENT_ENERGY = 1_073_744_004


def signed_component(value: int) -> int:
    sign_bit = 1 << (COMPONENT_BITS - 1)
    return value - (1 << COMPONENT_BITS) if value & sign_bit else value


def main() -> None:
    directory = Path(__file__).resolve().parent
    memory_path = directory / "upper_edge_pss30_x2_ddc_kernel_q17.mem"
    evidence_path = directory / "upper_edge_pss30_x2_ddc_kernel_q17.json"
    raw = memory_path.read_bytes()
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
                f"word {index} is not exactly {HEX_DIGITS} lowercase hex digits"
            )
        word = int(line, 16)
        coefficient_i = signed_component(word & component_mask)
        coefficient_q = signed_component((word >> COMPONENT_BITS) & component_mask)
        coefficients.extend((coefficient_i, coefficient_q))
        canonical.extend(struct.pack("<ii", coefficient_i, coefficient_q))

    canonical_digest = hashlib.sha256(canonical).hexdigest()
    text_digest = hashlib.sha256(raw).hexdigest()
    if canonical_digest != CANONICAL_BINARY_SHA256:
        raise SystemExit(f"canonical kernel SHA-256 mismatch: {canonical_digest}")
    if text_digest != TEXT_SHA256:
        raise SystemExit(f"memory-file SHA-256 mismatch: {text_digest}")

    evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
    expected = {
        "schema": "starlink-pss30-x2-ddc-kernel-v1",
        "input_sample_rate_hz": 30_000_000,
        "acquisition_sample_rate_hz": 15_000_000,
        "edge": "upper",
        "data_bits": COMPONENT_BITS,
        "kernel_words": WORD_COUNT,
        "template_samples": 66,
        "coefficient_energy": COEFFICIENT_ENERGY,
        "ddc_contract_sha256": DDC_CONTRACT_SHA256,
        "kernel_canonical_sha256": CANONICAL_BINARY_SHA256,
        "kernel_memory_sha256": TEXT_SHA256,
    }
    for field, value in expected.items():
        if evidence.get(field) != value:
            raise SystemExit(
                f"evidence field {field!r} is {evidence.get(field)!r}, expected {value!r}"
            )

    print(
        "UPPER_EDGE_PSS30_X2_DDC_KERNEL_Q17_PASS "
        f"words={len(lines)} min={min(coefficients)} max={max(coefficients)} "
        f"energy={COEFFICIENT_ENERGY} canonical_sha256={canonical_digest}"
    )


if __name__ == "__main__":
    main()
