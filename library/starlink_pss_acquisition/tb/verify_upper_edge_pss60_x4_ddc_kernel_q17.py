#!/usr/bin/env python3
"""Verify the immutable 18-bit kernel bound to the 60->15 MS/s cascade."""

from __future__ import annotations

import hashlib
import json
import struct
from pathlib import Path


WORD_COUNT = 512
COMPONENT_BITS = 18
HEX_DIGITS = 9
CANONICAL_BINARY_SHA256 = (
    "497ab1527fefaf2e0c2ed0ad7260c1fc01bec6b9062a1857b66bd7ec45bedccb"
)
TEXT_SHA256 = (
    "7b006bac23a3c58f614728dbfdb17d28bd77defb3d6d0d24aaa76255669c0c67"
)
DDC_X4_CONTRACT_SHA256 = (
    "8e807d15d5372b0a9669d1190d899697e7c2911a73ddfb23095806c2a31de5b2"
)
COEFFICIENT_ENERGY = 1_073_765_335


def signed_component(value: int) -> int:
    sign_bit = 1 << (COMPONENT_BITS - 1)
    return value - (1 << COMPONENT_BITS) if value & sign_bit else value


def main() -> None:
    directory = Path(__file__).resolve().parent
    memory_path = directory / "upper_edge_pss60_x4_ddc_kernel_q17.mem"
    evidence_path = directory / "upper_edge_pss60_x4_ddc_kernel_q17.json"
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
        "schema": "starlink-pss60-x4-ddc-kernel-v1",
        "input_sample_rate_hz": 60_000_000,
        "acquisition_sample_rate_hz": 15_000_000,
        "edge": "upper",
        "data_bits": COMPONENT_BITS,
        "kernel_words": WORD_COUNT,
        "template_samples": 66,
        "coefficient_energy": COEFFICIENT_ENERGY,
        "ddc_x4_contract_sha256": DDC_X4_CONTRACT_SHA256,
        "kernel_canonical_sha256": CANONICAL_BINARY_SHA256,
        "kernel_memory_sha256": TEXT_SHA256,
    }
    for field, value in expected.items():
        if evidence.get(field) != value:
            raise SystemExit(
                f"evidence field {field!r} is {evidence.get(field)!r}, expected {value!r}"
            )

    print(
        "UPPER_EDGE_PSS60_X4_DDC_KERNEL_Q17_PASS "
        f"words={len(lines)} min={min(coefficients)} max={max(coefficients)} "
        f"energy={COEFFICIENT_ENERGY} canonical_sha256={canonical_digest}"
    )


if __name__ == "__main__":
    main()
