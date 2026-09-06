#!/usr/bin/env python3
"""Structural contract for the sustained dual-XFFT acquisition engine."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
COMPOSITION = (ROOT / "starlink_pss_iq_to_score.v").read_text()
NORMALIZED = " ".join(COMPOSITION.split())


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"DUAL_XFFT_STRUCTURE_FAIL {message}")


xfft_instances = re.findall(
    r"\bstarlink_pss_fft512_bfp18\s+(\w+)\s*\(", COMPOSITION
)
require(
    xfft_instances == ["forward_xfft", "inverse_xfft"],
    f"expected dedicated forward/inverse cores, got {xfft_instances}",
)
require(
    len(
        re.findall(
            r"\bstarlink_pss_xfft_block_adapter\s*#\(", COMPOSITION
        )
    )
    == 2,
    "forward and inverse boundary adapters are required",
)
require(
    re.search(
        r"\bstarlink_pss_xfft_intermediate_buffer\s*#\(", COMPOSITION
    )
    is None,
    "serialized intermediate buffer must not remain instantiated",
)

for token in (
    "assign scheduler_fft_ready = forward_adapter_input_ready",
    "starlink_pss_transform_fifo #(",
    "assign inverse_input_valid = inverse_stream_valid",
    ".input_i (inverse_stream_i)",
    ".input_q (inverse_stream_q)",
    "inverse_forward_exponent_error_now",
    "inverse_stage_valid <= inverse_output_valid",
    "candidate_backpressure_fault = inverse_stage_valid",
):
    require(token in NORMALIZED, f"missing sustained-flow contract: {token}")

require(
    "processing_inverse" not in COMPOSITION,
    "single-core ownership state must not remain",
)
require(
    "shared_core_" not in COMPOSITION,
    "single-core routing mux must not remain",
)

print(
    "DUAL_XFFT_STRUCTURE_PASS cores=2 adapters=2 "
    "registered_spectrum_boundary=1 inverse_elastic_boundary=1"
)
