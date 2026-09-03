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
            "CAPTURE_COUNT = 130 * RATE_MULTIPLIER",
            "CAPTURE_SLOT_WIDTH = $clog2(CAPTURE_COUNT)",
            "CAPTURE_BEFORE_CENTER = 64'd32 * RATE_MULTIPLIER",
            "64'd98 * RATE_MULTIPLIER - 1'b1",
            "CAPTURE_LAST_SLOT =",
            "RATE_MULTIPLIER must be 1, 2, or 4",
            ".ADDRESS_WIDTH (COMMAND_FIFO_ADDRESS_WIDTH)",
            "command_lead[63]",
            "command_lead < MINIMUM_LEAD_SAMPLES",
            "command_center_index == last_admitted_center_index",
            "command_center_index - last_admitted_center_index",
            "command_center_distance <= CAPTURE_COUNT - 1",
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
    remaining = re.sub(
        r"\b(?:32|64|66|130)\s*\*\s*RATE_MULTIPLIER\b", "", remaining
    )
    if "*" in remaining or re.search(r"\s/\s", remaining):
        raise RuntimeError("sliding engine gained undeclared multiply/divide arithmetic")
    if sliding_source.count('use_dsp = "yes"') != 3:
        raise RuntimeError("sliding engine must request exactly three DSP result registers")
    for ready_name in (
        "o_coefficient_ready",
        "o_coefficient_commit_ready",
        "o_sample_ready",
        "o_start_ready",
    ):
        ready_expression = re.search(
            rf"assign\s+{ready_name}\s*=(.*?);", sliding, flags=re.DOTALL
        )
        if ready_expression is None or re.search(
            r"\bi_(coefficient_clear|coefficient_valid|coefficient_commit|"
            r"sample_clear|sample_valid|start)\b",
            ready_expression.group(1),
        ):
            raise RuntimeError(
                f"{ready_name} must describe capacity independently of inputs"
            )

    require(
        bridge,
        (
            "DESCRIPTOR_WIDTH = 161",
            "CAPTURE_COUNT = 130 * RATE_MULTIPLIER",
            "CAPTURE_MEMORY_ADDRESS_WIDTH = CAPTURE_SLOT_WIDTH + 1",
            "CAPTURE_LAST_SLOT =",
            ".ADDRESS_WIDTH (2)",
            ".DATA_WIDTH    (96)",
            ".ADDRESS_WIDTH (CAPTURE_MEMORY_ADDRESS_WIDTH)",
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
            "COEFFICIENT_COUNT = 66 * RATE_MULTIPLIER",
            "CAPTURE_COUNT = 130 * RATE_MULTIPLIER",
            "RESULT_COUNT = 64 * RATE_MULTIPLIER + 1",
            "COEFFICIENT_ADDRESS_WIDTH = $clog2(COEFFICIENT_COUNT)",
            "SAMPLE_ADDRESS_WIDTH = $clog2(CAPTURE_COUNT)",
            "LAG_WIDTH = $clog2(RESULT_COUNT)",
            "shadow_coefficient_memory",
            "active_coefficient_memory",
            "sample_complex_memory",
            "sample_energy_remove_memory",
            "sample_energy_add_memory",
            "memory_read_valid <= multiplier_issue",
            "coefficient_copy_read_valid",
            "STATE_COEFFICIENT_COPY_FINISH",
            "coefficient_energy_accumulator > 48'sh0000_7fff_ffff",
            "sample_energy_remove_memory[phase_consume_count]",
            "sample_energy_add_memory[phase_consume_count]",
            "sample_energy_remove_read_data",
            "sample_energy_add_read_data",
            "sample_timestamp_read_data",
            "o_result_coefficient_generation",
            "o_bound_error_count",
            "sliding_energy_bound_error_pending",
            "i_coefficient_saturator",
            "i_sample_saturator",
            "i_correlation_real_saturator",
            "i_correlation_imag_saturator",
            "add_saturating_9",
            "total_saturation_events",
        ),
        label="sliding correlator",
    )
    if sliding_source.count('ram_style = "block"') != 6:
        raise RuntimeError("sliding correlator must retain six explicit block-RAM banks")
    if "saturator_0_accumulator" in sliding:
        raise RuntimeError("sliding correlator reintroduced the phase-shared carry mux")

    require(
        tracking,
        (
            ".i_control_resetn              (i_control_resetn)",
            ".i_sample_resetn               (i_sample_resetn)",
            ".i_engine_resetn                 (i_engine_resetn)",
            ".i_reset                          (!i_engine_resetn)",
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
            "FIRST_LAG =",
            "-30 * RATE_MULTIPLIER",
            "LAST_LAG =",
            "30 * RATE_MULTIPLIER",
            "reg [76:0] current_magnitude_squared",
            "reg [68:0] current_denominator",
            "reg [145:0] left_cross_product",
            "reg [146:0] multiply_work",
            "reg [76:0] multiply_multiplicand",
            "reg [6:0] multiply_bit_index",
            "multiply_multiplicand <= current_magnitude_squared",
            "multiply_multiplicand <= winner_magnitude_squared",
            "correlation_bound_legal",
            "energy_bound_legal",
            "left_cross_product > multiply_work[145:0]",
            "multiply_work[0]",
            "multiply_bit_index <= 7'd68",
            "o_result_score_numerator = winner_magnitude_squared",
            "o_result_score_denominator = winner_denominator",
        ),
        label="exact rational reducer",
    )
    for retired_workspace in (
        "square_multiplier_shift",
        "denominator_multiplier_shift",
        "compare_multiplier_shift",
        "compare_accumulator",
        "square_accumulator",
        "denominator_accumulator",
        "compare_multiplicand",
    ):
        if retired_workspace in reducer:
            raise RuntimeError(
                "exact reducer reintroduced retired parallel serial workspace: "
                f"{retired_workspace}"
            )
    reducer_runtime = re.sub(
        r"\b(?:30|64)\s*\*\s*RATE_MULTIPLIER\b", "", reducer
    )
    if "*" in reducer_runtime or re.search(r"\s/\s", reducer_runtime):
        raise RuntimeError("exact reducer gained a multiply/divide operator")

    print(
        "SCHEDULER_SLIDING_STRUCTURE_PASS queue_payload_bits=160 "
        "small_async_fifo=1 command_memory=block descriptor_memory=distributed "
        "descriptor_payload_bits=161 capture_banks=2 "
        "capture_samples=rate_scaled multipliers=3 cached_eh=1 "
        "sliding_ex=1 exact_reducer=1 reducer_multipliers=0 shared_serial=1"
    )


if __name__ == "__main__":
    main()
