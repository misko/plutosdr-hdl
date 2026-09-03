#!/usr/bin/env python3
"""Structural contract for the serialized one-XFFT acquisition engine."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
COMPOSITION = (ROOT / "starlink_pss_iq_to_score.v").read_text()
BUFFER = (ROOT / "starlink_pss_xfft_intermediate_buffer.v").read_text()
NORMALIZED_COMPOSITION = " ".join(COMPOSITION.split())


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"SHARED_XFFT_STRUCTURE_FAIL {message}")


xfft_instances = re.findall(
    r"\bstarlink_pss_fft512_bfp18\s+(\w+)\s*\(", COMPOSITION
)
require(xfft_instances == ["shared_xfft"],
        f"expected only shared_xfft, got {xfft_instances}")
require(len(re.findall(r"\bstarlink_pss_xfft_block_adapter\s*#\(",
                       COMPOSITION)) == 2,
        "forward and inverse boundary adapters are required")
require(len(re.findall(
    r"\bstarlink_pss_xfft_intermediate_buffer\s*#\(", COMPOSITION
)) == 1, "one intermediate buffer is required")

for token in (
    "processing_inverse ? inverse_core_aresetn : forward_core_aresetn",
    "forward_input_block_complete_pulse",
    "intermediate_write_complete_pulse",
    "intermediate_release = inverse_output_accept && inverse_output_last",
):
    require(token in NORMALIZED_COMPOSITION,
            f"missing ownership contract: {token}")

require('ram_style = "block"' in BUFFER,
        "intermediate payload must request block RAM")
require(re.search(
    r"payload_memory\s*\[0:511\]", BUFFER
) is not None, "intermediate payload must contain exactly 512 words")
require("DATA_WIDTH != 18" in BUFFER,
        "one-RAMB18 width guard is missing")
require("input_metadata_valid" in BUFFER and "protocol_fault" in BUFFER,
        "metadata errors must quarantine the intermediate buffer")

source_manifests = (
    ROOT / "simulate_iq_to_score_xfft.tcl",
    ROOT / "simulate_iq_to_phase_map_xfft.tcl",
    ROOT / "simulate_pss30_ddc_to_score_xfft.tcl",
    ROOT / "synthesize_iq_to_score_xfft_ooc.tcl",
    ROOT / "synthesize_iq_to_phase_map_xfft_ooc.tcl",
    ROOT.parent / "axi_starlink_pss_acquisition" / "Makefile",
    ROOT.parent / "axi_starlink_pss_acquisition" /
    "axi_starlink_pss_acquisition_ip.tcl",
)
for manifest in source_manifests:
    require("starlink_pss_xfft_intermediate_buffer.v" in manifest.read_text(),
            f"missing buffer source dependency in {manifest.name}")

print(
    "SHARED_XFFT_STRUCTURE_PASS cores=1 adapters=2 "
    "buffer_words=512 buffer_width=36 atomic_commit=1"
)
