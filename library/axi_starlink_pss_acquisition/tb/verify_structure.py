#!/usr/bin/env python3
"""Machine-check the 15/30/60 MS/s acquisition wrapper composition."""

from __future__ import annotations

from pathlib import Path


DIRECTORY = Path(__file__).resolve().parents[1]
WRAPPER = (DIRECTORY / "axi_starlink_pss_acquisition.v").read_text()
CONTROL = (DIRECTORY / "axi_starlink_pss_phase_map_sync.v").read_text()
IP_TCL = (DIRECTORY / "axi_starlink_pss_acquisition_ip.tcl").read_text()


def require(source: str, fragment: str, label: str) -> None:
    if fragment not in source:
        raise SystemExit(f"ACQUISITION_WRAPPER_STRUCTURE_FAIL {label}: {fragment}")


for fragment, label in (
    ("parameter integer INPUT_RATE_MSPS = 15", "rate parameter"),
    ("INPUT_RATE_MSPS must be 15, 30, or 60", "rate guard"),
    ("if (INPUT_RATE_MSPS == 15) begin : g_rate_15", "15 MS/s bypass"),
    ("end else if (INPUT_RATE_MSPS == 30) begin : g_rate_30", "30 MS/s branch"),
    ("end else begin : g_rate_60", "60 MS/s branch"),
    ("starlink_pss_x2_ddc", "DDC instance"),
    ("upper_edge_pss30_x2_ddc_kernel_q17.mem", "DDC-conditioned kernel"),
    ("upper_edge_pss60_x4_ddc_kernel_q17.mem", "cascade-conditioned kernel"),
    ("31'd1073744004", "DDC-conditioned coefficient energy"),
    ("31'd1073765335", "cascade-conditioned coefficient energy"),
    (".sample_valid                         (acquisition_sample_valid)", "adapted valid"),
    (".sample_index                         (acquisition_sample_index)", "adapted index"),
    (".input_valid            (ingress_sample_valid)", "post-CDC DDC placement"),
    (".enable                 (acquisition_enable)", "common enable"),
    (".flush                  (acquisition_flush)", "common flush"),
):
    require(WRAPPER, fragment, label)

if WRAPPER.count("starlink_pss_x2_ddc #(") != 3:
    raise SystemExit(
        "ACQUISITION_WRAPPER_STRUCTURE_FAIL expected one x2 and one x4 path"
    )

for fragment, label in (
    ("32'h0001_0003", "60 MS/s ABI version"),
    ("32'h0000_007f : 32'h0000_003f", "conditional capabilities"),
    ("REG_INPUT_RATE_MSPS = 6'h2c", "rate register"),
    ("REG_DDC_CONTRACT_0 = 6'h30", "contract register start"),
    ("REG_DDC_CONTRACT_7 = 6'h37", "contract register end"),
    ("256'h731426047077b036f9213db3574e4a556fd424b97a293843bd6ee085c2bf33af", "x2 contract digest"),
    ("256'h8e807d15d5372b0a9669d1190d899697e7c2911a73ddfb23095806c2a31de5b2", "cascade contract digest"),
    ("REG_DDC_ACCEPTED = 6'h38", "accepted counter"),
    ("REG_DDC_SATURATION = 6'h3b", "saturation counter"),
    ("HEALTH_DDC_SATURATION = 13", "saturation health bit"),
):
    require(CONTROL, fragment, label)

for fragment, label in (
    ('"$acq_dir/starlink_pss_x2_ddc.v"', "packaged DDC RTL"),
    ('"$acq_dir/tb/upper_edge_pss30_x2_ddc_kernel_q17.mem"', "packaged DDC kernel"),
    ('"$acq_dir/tb/upper_edge_pss60_x4_ddc_kernel_q17.mem"', "packaged cascade kernel"),
    ('value_validation_list "15 30 60"', "packager rate validation"),
):
    require(IP_TCL, fragment, label)

print(
    "ACQUISITION_WRAPPER_STRUCTURE_PASS rates=15,30,60 bypass15=1 "
    "ddc30_stages=1 ddc60_stages=2 contract_words=8 live_counters=4"
)
