#!/usr/bin/env python3
"""Verify immutable Stage-15 periodic-injection fixture identities."""

from __future__ import annotations

import hashlib
import json
import struct
from pathlib import Path

MEMORY_SHA256 = "a983f90ccc0c4e8717ff40a5b0717a4abbea54aaacdd4fb7815adcb86f2dc6f3"
CANONICAL_SHA256 = "367ffcb92be0b37bb41ab161e7e7e9ebe9730e2f255a9d7c7ff6a7bae2341d4f"


def main() -> None:
    directory = Path(__file__).resolve().parent
    memory_path = directory / "upper_edge_pss_periodic_fixture_ci16.mem"
    evidence_path = directory / "upper_edge_pss_periodic_fixture_ci16.json"
    raw = memory_path.read_bytes()
    lines = raw.decode("ascii").splitlines()
    if len(lines) != 130:
        raise SystemExit(f"expected 130 fixture words, got {len(lines)}")
    canonical = bytearray()
    for index, line in enumerate(lines):
        if len(line) != 8 or any(c not in "0123456789abcdef" for c in line):
            raise SystemExit(f"fixture word {index} is not eight lowercase hex digits")
        word = int(line, 16)
        i = (word >> 16) & 0xFFFF
        q = word & 0xFFFF
        canonical.extend(struct.pack("<HH", i, q))

    memory_digest = hashlib.sha256(raw).hexdigest()
    canonical_digest = hashlib.sha256(canonical).hexdigest()
    if memory_digest != MEMORY_SHA256:
        raise SystemExit(f"fixture memory SHA-256 mismatch: {memory_digest}")
    if canonical_digest != CANONICAL_SHA256:
        raise SystemExit(f"fixture canonical SHA-256 mismatch: {canonical_digest}")

    evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
    required = {
        "schema": "starlink-pss15-periodic-injection-fixture-v1",
        "sample_rate_hz": 15_000_000,
        "fixture_samples": 130,
        "template_samples": 66,
        "template_offset": 32,
        "period_samples": 20_000,
        "repetitions": 130,
        "last_sample_offset": 2_580_129,
        "inter_fixture_i": 1,
        "inter_fixture_q": 0,
        "expected_score_offset": 32,
        "expected_exact_match_score_u8": 255,
        "fixture_ci16_sha256": CANONICAL_SHA256,
        "fixture_memory_sha256": MEMORY_SHA256,
    }
    for key, expected in required.items():
        if evidence.get(key) != expected:
            raise SystemExit(
                f"fixture evidence {key}: expected {expected!r}, got {evidence.get(key)!r}"
            )
    print(
        "PERIODIC_FIXTURE_VERIFY_PASS "
        f"words={len(lines)} memory_sha256={memory_digest} "
        f"canonical_sha256={canonical_digest}"
    )


if __name__ == "__main__":
    main()
