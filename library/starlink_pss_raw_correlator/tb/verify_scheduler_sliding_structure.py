#!/usr/bin/env python3
"""Fail closed if the queued scheduler or sliding engine contract drifts."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCHEDULER = ROOT / "starlink_pss_candidate_scheduler.v"
ASYNC_FIFO = ROOT / "starlink_pss_async_fifo.v"
BRIDGE = ROOT / "starlink_pss_capture_bridge.v"
SLIDING = ROOT / "starlink_pss_sliding_correlator.v"
TRACKING = ROOT / "starlink_pss_tracking_core.v"
REDUCER = ROOT / "starlink_pss_exact_reducer.v"


def executable_verilog(path: Path) -> str:
    source = path.read_text()
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.DOTALL)
    source = re.sub(r"//.*", "", source)
    source = re.sub(r"\(\*.*?\*\)", "", source, flags=re.DOTALL)
    return source.replace("@*", "@")


def require(source: str, fragments: tuple[str, ...], *, label: str) -> None:
    for fragment in fragments:
        if fragment not in source:
            raise RuntimeError(f"{label} is missing frozen fragment: {fragment}")


def main() -> None:
    scheduler = executable_verilog(SCHEDULER)
    async_fifo_source = ASYNC_FIFO.read_text()
    async_fifo = executable_verilog(ASYNC_FIFO)
    bridge = executable_verilog(BRIDGE)
    sliding_source = SLIDING.read_text()
    sliding = executable_verilog(SLIDING)
    tracking = executable_verilog(TRACKING)
    reducer = executable_verilog(REDUCER)

    require(
        scheduler,
        (
            "COMMAND_WIDTH = 160",
            "CAPTURE_BEFORE_CENTER = 64'd32",
            "CAPTURE_AFTER_CENTER = 64'd97",
            "CAPTURE_LAST_SLOT = 8'd129",
            ".ADDRESS_WIDTH (COMMAND_FIFO_ADDRESS_WIDTH)",
            "command_lead[63]",
            "command_lead < MINIMUM_LEAD_SAMPLES",
            "command_center_index == last_admitted_center_index",
            "command_center_index - last_admitted_center_index",
            "command_center_distance <= 64'd129",
            "i_sample_index != next_expected_index",
            "i_sample_timestamp != command_center_timestamp",
            "o_capture_request_id = command_request_id",
            "o_capture_center_index = command_center_index",
            "o_capture_center_timestamp = command_center_timestamp",
        ),
        label="candidate scheduler",
    )

    require(
        async_fifo,
        (
            "USABLE_CAPACITY",
            "binary_to_gray",
            "gray_to_binary",
            "read_gray_write_sync_2",
            "write_gray_read_sync_2",
            "payload_memory[write_binary[ADDRESS_WIDTH-1:0]] <= i_write_data",
            "read_data <= payload_memory[read_binary[ADDRESS_WIDTH-1:0]]",
            "o_read_data = read_data",
            "!read_valid && i_read_ready && unread_payload_available",
        ),
        label="small async FIFO",
    )
    if "ram_style = RAM_STYLE" not in async_fifo_source:
        raise RuntimeError("small async FIFO payload style must remain explicit")
    if async_fifo_source.count('ASYNC_REG = "TRUE"') != 4:
        raise RuntimeError("small async FIFO must mark all four synchronizer stages")

    products = re.findall(
        r"multiplier_([0-2])_a_registered\s*\*\s*"
        r"multiplier_\1_b_registered",
        sliding,
    )
    if products != ["0", "1", "2"]:
        raise RuntimeError(
            f"sliding engine expected multiplier set 0,1,2 once, got {products}"
        )
    remaining = re.sub(
        r"multiplier_([0-2])_a_registered\s*\*\s*"
        r"multiplier_\1_b_registered",
        "",
        sliding,
    )
    if "*" in remaining or re.search(r"\s/\s", remaining):
        raise RuntimeError("sliding engine gained undeclared multiply/divide arithmetic")
    if sliding_source.count('use_dsp = "yes"') != 3:
        raise RuntimeError("sliding engine must request exactly three DSP result registers")

    require(
        bridge,
        (
            "DESCRIPTOR_WIDTH = 161",
            "CAPTURE_LAST_SLOT = 8'd129",
            ".ADDRESS_WIDTH (2)",
            ".DATA_WIDTH    (96)",
            ".ADDRESS_WIDTH (9)",
            "capture_memory_write = capture_first_write || capture_active_write",
            "if (i_capture_abort)",
            "engine_release_toggle[engine_bank]",
            "o_capture_buffer_overrun_count",
            "o_capture_protocol_error_count",
            "i_capture_request_id",
            "i_capture_center_index",
            "i_capture_center_timestamp",
        ),
        label="capture bridge",
    )
    if "capture_writer_request_id" in bridge:
        raise RuntimeError("bridge reintroduced redundant scheduler metadata storage")

    require(
        sliding,
        (
            "COEFFICIENT_COUNT = 66",
            "CAPTURE_COUNT = 130",
            "RESULT_COUNT = 65",
            "shadow_coefficient_i_memory",
            "active_coefficient_i_memory",
            "sample_energy_memory",
            "coefficient_energy_accumulator > 48'sh0000_7fff_ffff",
            "sample_energy_memory[phase_consume_count] <= tap_energy_addend[31:0]",
            "sample_energy_memory[lag_index]",
            "sample_energy_memory[sliding_add_address]",
            "sample_timestamp_memory[lag_index]",
            "o_result_coefficient_generation",
            "o_bound_error_count",
        ),
        label="sliding correlator",
    )

    require(
        tracking,
        (
            ".i_control_resetn              (i_resetn)",
            ".i_sample_resetn               (i_resetn)",
            ".i_engine_resetn                 (i_resetn)",
            ".i_reset                          (!i_resetn)",
            "bridge_engine_job_done && correlator_start_ready",
            "bridge_engine_sample_valid",
            "bridge_engine_sample_ready",
            "o_result_request_id = bridge_engine_request_id",
        ),
        label="tracking composition",
    )

    require(
        reducer,
        (
            "FIRST_LAG = -7'sd32",
            "LAST_LAG = 7'sd32",
            "reg [76:0] current_magnitude_squared",
            "reg [68:0] current_denominator",
            "reg [145:0] left_cross_product",
            "correlation_bound_legal",
            "energy_bound_legal",
            "left_cross_product > compare_accumulator",
            "square_multiplier_shift[37]",
            "denominator_multiplier_shift[30]",
            "compare_multiplier_shift[68]",
            "o_result_score_numerator = winner_magnitude_squared",
            "o_result_score_denominator = winner_denominator",
        ),
        label="exact rational reducer",
    )
    if "*" in reducer or re.search(r"\s/\s", reducer):
        raise RuntimeError("exact reducer gained a multiply/divide operator")

    print(
        "SCHEDULER_SLIDING_STRUCTURE_PASS queue_payload_bits=160 "
        "small_async_fifo=1 command_memory=block descriptor_memory=distributed "
        "descriptor_payload_bits=161 capture_banks=2 "
        "capture_samples=130 multipliers=3 cached_eh=1 "
        "sliding_ex=1 exact_reducer=1 reducer_multipliers=0"
    )


if __name__ == "__main__":
    main()
