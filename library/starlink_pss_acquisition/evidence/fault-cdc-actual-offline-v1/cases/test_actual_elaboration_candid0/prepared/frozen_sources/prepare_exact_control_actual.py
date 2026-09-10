"""Offline only: freeze two independent islands/benches; never launch Vivado."""

import argparse
import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path

BASE = "dec20d6371f2d77b6e09c4bcdda2f3d7f8715776"
TESTED_RTL = "ae50b1889fd10cd762fb60266aecbb7c163e1d1a"
RTL = (
    "fft_bank_owned_slice",
    "realtime_input_guard",
    "realtime_result_guard",
    "block_mailbox",
    "forward_kernel_join",
    "kernel_rom",
    "spectrum_product",
)
SHADOWS = (
    "starlink_pss_forward_kernel_join_7ee87258_golden.v",
    "starlink_pss_kernel_rom_7ee87258_golden.v",
    "starlink_pss_spectrum_product_7ee87258_golden.v",
    "starlink_pss_payload_bubble_shadow.sv",
    "starlink_pss_realtime_result_guard_ce6a885e_golden.v",
    "starlink_pss_forward_retirement_shadow.sv",
)
VECTORS = (
    "samples_ci16",
    "forward_q17",
    "product_q17",
    "inverse_q17",
    "forward_exponents",
    "inverse_exponents",
    "upper_edge_pss_kernel_q17",
)
TOP = "tb_starlink_pss_fft_bank_owned_slice"
REFERENCE = "tb_starlink_pss_exact_control_reference"
EXTRA_PARAMETER_CHECK = """  initial begin
    if (EXACT_EXTRA_EPOCHS !== 0 && EXACT_EXTRA_EPOCHS !== 1)
      $fatal(1, "EXACT_EXTRA_EPOCHS_REQUIRES_ZERO_OR_ONE");
  end
"""
TB_FIELDS = [
    "resetn",
    "fft_resetn",
    "input_valid",
    "input_last",
    "input_data",
    "input_position",
    "input_block_start",
    "input_ready",
    "output_valid",
    "output_ready",
    "output_last",
    "output_data",
    "output_position",
    "output_metadata",
    "fault",
    "epoch",
    "profile",
    "expected_fault",
    "expected_results",
    "injecting_readiness",
    "reader_enable",
    "allow_inverse_commit_before_late_fault",
    "allow_provisional_prefix_after_fault",
]
WRAPPER_FIELDS = [
    "fast_running",
    "slow_running",
    "fast_fault",
    "state",
    "core_release",
    "input_job_start_private",
    "input_job_start",
    "next_inverse",
    "engine_metadata",
    "engine_input_reserved",
    "engine_output_reserved",
    "forward_committed",
    "held_phase",
    "held_lease",
    "source_consume_generation",
    "product_consume_generation",
    "descriptor_certified",
    "admission_receipt",
    "completion_receipt",
    "expected_product_metadata",
    "preparation_age",
    "epoch_input_reasons",
    "epoch_preflight_reasons",
    "core_aresetn",
    "config_valid",
    "config_ready",
    "engine_input_enable",
    "job_ready",
    "job_accept",
    "result_busy",
    "result_commit",
    "result_fault",
    "source_valid",
    "source_read_ready",
    "source_data",
    "source_position",
    "source_last",
    "source_metadata",
    "product_bank_valid",
    "product_bank_read_ready",
    "product_bank_data",
    "product_bank_position",
    "product_bank_last",
    "product_bank_metadata",
    "checked_input_complete",
    "certified_input_beat",
    "certified_input_complete",
    "input_fault_now",
    "input_guard_fault",
    "input_fault_events_now",
    "duplicate_start_fault_now",
    "core_input_data",
    "core_input_valid",
    "core_input_ready",
    "core_input_last",
    "core_output_data",
    "core_output_user",
    "core_output_valid",
    "core_output_last",
    "core_status_data",
    "core_status_valid",
    "event_frame",
    "event_last_unexpected",
    "event_last_missing",
    "event_input_halt",
    "return_valid",
    "return_private_valid",
    "return_commit_valid",
    "return_data",
    "return_position",
    "return_last",
    "return_metadata",
    "forward_retirement_valid",
    "external_fault_now",
    "any_fast_fault",
    "preflight_events_now",
    "preparation_fault_now",
    "final_fence",
    "completed_input_fault_now",
    "forward_handoff_ack",
    "forward_handoff_identity",
    "handoff_fault_now",
    "result_destination_ready",
    "product_commit_authorized",
    "product_bank_ready",
    "product_bank_fault",
    "product_bank_framing_fault_now",
    "output_bank_ready",
    "output_bank_fault",
    "output_bank_framing_fault_now",
    "product_overflow",
]
GUARD_FIELDS = [
    "active_private",
    "awaiting_ack",
    "descriptor",
    "input_count",
    "output_count",
    "input_complete_seen",
    "frame_seen",
    "status_seen",
    "exponent_seen",
    "status_exponent",
    "output_exponent",
    "age",
    "return_occupied",
    "return_last",
    "return_data",
    "return_position",
    "return_exponent",
    "fault_reasons",
    "faults_now",
]
INPUT_FIELDS = [
    "job_started",
    "input_started",
    "descriptor",
    "expected_position",
    "input_complete",
    "fault_reasons",
    "slot_open",
    "fault_events_now",
    "core_input_tvalid",
    "certified_input_beat",
    "certified_input_complete",
]
ROM_FIELDS = [
    "expected_bin_index",
    "block_exponent",
    "block_start_index",
    "have_previous_block",
    "output_kernel_word",
    "output_valid",
    "output_bin_index",
    "output_block_exponent",
    "output_last",
    "output_block_start_index",
    "accepted_pulse",
    "emitted_pulse",
    "input_block_complete_pulse",
    "sequence_error_pulse",
    "metadata_error_pulse",
    "protocol_fault",
    "input_ready",
    "input_accept",
    "protocol_error_now",
]
BANK_FIELDS = [
    "request_toggle",
    "acknowledge_toggle",
    "request_sync",
    "acknowledge_sync",
    "metadata_in_hold",
    "metadata_out_hold",
    "write_position",
    "reading",
    "read_all_loaded",
    "read_address",
    "read_output_position",
    "read_payload",
    "read_valid",
    "input_ready",
    "input_fault",
    "input_framing_fault_now",
    "output_valid",
    "output_ready",
]
FIELDS = (
    TB_FIELDS
    + ["dut." + x for x in WRAPPER_FIELDS]
    + ["dut.result_guard." + x for x in GUARD_FIELDS]
    + ["dut.input_guard." + x for x in INPUT_FIELDS]
    + ["dut.joiner.kernel_rom." + x for x in ROM_FIELDS]
    + [
        f"dut.{bank}.{x}"
        for bank in ("source_bank", "product_bank", "output_bank")
        for x in BANK_FIELDS
    ]
)


def git_file(hdl, pin, relative):
    return subprocess.run(
        ["git", "-C", str(hdl), "show", f"{pin}:{relative}"],
        capture_output=True,
        check=True,
        timeout=10,
    ).stdout


def renamed(text):
    for kind in RTL:
        name = "starlink_pss_" + kind
        text = re.sub(rf"\b{name}\b", name + "_dec20d63_golden", text)
    return text


def once(text, old, new):
    if text.count(old) != 1:
        raise ValueError(f"nonunique immutable anchor: {old}")
    return text.replace(old, new, 1)


def block(label, text):
    return f"  // BEGIN EXACT_CONTROL_{label}\n{text}  // END EXACT_CONTROL_{label}\n"


def candidate_bench(original):
    params = block(
        "PARAMETERS",
        "  parameter integer DISTRIBUTED_FAST_FAULT = 0;\n"
        "  parameter integer PRIVATE_NEXT_START_SCRATCH = 0;\n"
        "  parameter integer EXACT_EXTRA_EPOCHS = 0;\n" + EXTRA_PARAMETER_CHECK,
    )
    text = once(
        original, "  reg clk = 0, fft_clk = 0;", params + "  reg clk = 0, fft_clk = 0;"
    )
    text = once(
        text,
        "#(.REGISTERED_SCHEDULING(REGISTERED_SCHEDULING)) dut (.*);",
        "#(.REGISTERED_SCHEDULING(REGISTERED_SCHEDULING),\n"
        "    .DISTRIBUTED_FAST_FAULT(DISTRIBUTED_FAST_FAULT),\n"
        "    .PRIVATE_NEXT_START_SCRATCH(PRIVATE_NEXT_START_SCRATCH)) dut (.*);",
    )
    actual = ",\n    ".join(FIELDS)
    reference = ",\n    ".join("exact_reference." + x for x in FIELDS)
    shadow = f"""  {REFERENCE} #(.FAST_MHZ(FAST_MHZ), .QUICK_MUTATION(QUICK_MUTATION),
    .REGISTERED_SCHEDULING(REGISTERED_SCHEDULING), .EXACT_EXTRA_EPOCHS(EXACT_EXTRA_EPOCHS)) exact_reference ();
  // Self-sized concatenations avoid a tool-dependent hierarchical $bits
  // localparam (Icarus resolved that parameter to zero during elaboration).
  wire exact_public_equal = ({{{actual}}} === {{{reference}}});
  wire [31:0] exact_checks, exact_active_checks, exact_consumed, exact_private_differences;
  wire [31:0] exact_final_faults, exact_owned_stalls, exact_reset_owned;
  starlink_pss_exact_control_actual_compare #(.WIDTH(1)) exact_compare (
    .clk(fft_clk), .actual_public(exact_public_equal), .reference_public(1'b1),
    .actual_consume(dut.joiner.kernel_rom.input_accept && dut.joiner.kernel_rom.at_block_start && dut.joiner.kernel_rom.have_previous_block),
    .reference_consume(exact_reference.dut.joiner.kernel_rom.input_accept && exact_reference.dut.joiner.kernel_rom.at_block_start && exact_reference.dut.joiner.kernel_rom.have_previous_block),
    .actual_scratch(dut.joiner.kernel_rom.expected_next_block_start),
    .reference_scratch(exact_reference.dut.joiner.kernel_rom.expected_next_block_start),
    .active_job(dut.result_guard.active), .final_slot(dut.joiner.kernel_rom.expected_bin_index == 511),
    .current_fault(dut.any_fast_fault),
    .owned_bank(dut.engine_input_reserved || dut.engine_output_reserved || dut.product_bank_valid || dut.output_bank.slow_output_valid),
    .stalled_bank(!dut.product_bank_ready || !dut.output_bank_ready), .running(dut.fast_running),
    .checks(exact_checks), .active_checks(exact_active_checks), .consumed_identities(exact_consumed),
    .private_differences(exact_private_differences), .final_fault_edges(exact_final_faults),
    .owned_stall_edges(exact_owned_stalls), .reset_owned_edges(exact_reset_owned));
  `include "starlink_pss_exact_control_extra_epochs.svh"
"""
    # slow_output_valid belongs to the wrapper, not the output mailbox.
    shadow = shadow.replace(
        "dut.output_bank.slow_output_valid", "dut.slow_output_valid"
    )
    text = once(
        text,
        "  // BEGIN PAYLOAD_BUBBLE_SHADOW:",
        block("SHADOW", shadow) + "  // BEGIN PAYLOAD_BUBBLE_SHADOW:",
    )
    receipt = """    $fclose(trace);
    if (EXACT_EXTRA_EPOCHS) begin
      trace = $fopen("exact_control_extra_trace.csv", "w");
      exact_control_extra_epochs();
    end else trace = $fopen("exact_control_no_extra_trace.csv", "w");
    #0.003;
    if (dut.DISTRIBUTED_FAST_FAULT != DISTRIBUTED_FAST_FAULT ||
        dut.PRIVATE_NEXT_START_SCRATCH != PRIVATE_NEXT_START_SCRATCH ||
        dut.joiner.PRIVATE_NEXT_START_SCRATCH != PRIVATE_NEXT_START_SCRATCH ||
        dut.joiner.kernel_rom.PRIVATE_NEXT_START_SCRATCH != PRIVATE_NEXT_START_SCRATCH)
      $fatal(1, "EXACT_ACTUAL_PARAMETER_FORWARDING_MISMATCH");
    if (!exact_reference.exact_reference_done || !exact_checks || !exact_active_checks || !exact_consumed)
      $fatal(1, "EXACT_ACTUAL_REFERENCE_OR_COVERAGE_INCOMPLETE");
    if (EXACT_EXTRA_EPOCHS && (!exact_final_faults || !exact_owned_stalls))
      $fatal(1, "EXACT_ACTUAL_FINAL_FAULT_OR_STALL_NOT_OBSERVED");
    $display("EXACT_CONTROL_ACTUAL_PASS registered=%0d distributed=%0d scratch=%0d extra=%0d checks=%0d active=%0d consumed=%0d private_differences=%0d final_fault_edges=%0d owned_stalls=%0d reset_owned_edges=%0d independent_actual_core=1",
      REGISTERED_SCHEDULING, DISTRIBUTED_FAST_FAULT, PRIVATE_NEXT_START_SCRATCH, EXACT_EXTRA_EPOCHS,
      exact_checks, exact_active_checks, exact_consumed, exact_private_differences,
      exact_final_faults, exact_owned_stalls, exact_reset_owned);
"""
    return once(
        text,
        "    $fclose(trace); $finish;",
        block("RECEIPT", receipt) + "    $fclose(trace); $finish;",
    )


def reference_bench(original):
    text = once(original, f"module {TOP};", f"module {REFERENCE};")
    text = once(
        text,
        "  reg clk = 0, fft_clk = 0;",
        "  parameter integer EXACT_EXTRA_EPOCHS = 0;\n"
        + EXTRA_PARAMETER_CHECK
        + "  reg exact_reference_done = 0;\n"
        '  `include "starlink_pss_exact_control_extra_epochs.svh"\n'
        "  reg clk = 0, fft_clk = 0;",
    )
    text = once(
        text, '"fft_bank_owned_trace.csv"', '"exact_control_reference_trace.csv"'
    )
    text = once(
        text,
        "    $fclose(trace); $finish;",
        """    $fclose(trace);
    if (EXACT_EXTRA_EPOCHS) begin
      trace = $fopen("exact_control_reference_extra_trace.csv", "w");
      exact_control_extra_epochs(); $fclose(trace);
    end
    exact_reference_done = 1;
""",
    )
    return renamed(text)


def prepare(output, vectors, registered, distributed, scratch, extras):
    if any(value not in (0, 1) for value in (registered, distributed, scratch, extras)):
        raise ValueError("all options must be explicitly zero or one")
    if output.exists():
        raise FileExistsError("refusing to overwrite prepared evidence")
    acq = Path(__file__).resolve().parent
    hdl = acq.parents[1]
    original = git_file(hdl, BASE, f"library/starlink_pss_acquisition/tb/{TOP}.sv")
    if original != (acq / "tb" / f"{TOP}.sv").read_bytes():
        raise ValueError("immutable actual stimulus changed")
    for kind in RTL:
        name = f"starlink_pss_{kind}.v"
        if (acq / name).read_bytes() != git_file(
            hdl, TESTED_RTL, f"library/starlink_pss_acquisition/{name}"
        ):
            raise ValueError(f"tested RTL changed: {name}")
    source = output / "frozen_sources"
    source.mkdir(parents=True)
    for kind in RTL:
        name = f"starlink_pss_{kind}"
        shutil.copyfile(acq / f"{name}.v", source / f"{name}.v")
        reference = git_file(
            hdl, BASE, f"library/starlink_pss_acquisition/{name}.v"
        ).decode()
        (source / f"{name}_dec20d63_golden.v").write_text(renamed(reference))
    (source / f"{TOP}.sv").write_text(candidate_bench(original.decode()))
    (source / f"{REFERENCE}.sv").write_text(reference_bench(original.decode()))
    for name in SHADOWS:
        baseline = git_file(hdl, BASE, f"library/starlink_pss_acquisition/tb/{name}")
        if baseline != (acq / "tb" / name).read_bytes():
            raise ValueError(f"immutable old shadow changed: {name}")
        (source / name).write_bytes(baseline)
    for name in (
        "starlink_pss_exact_control_actual_compare.sv",
        "starlink_pss_exact_control_extra_epochs.svh",
    ):
        shutil.copyfile(acq / "tb" / name, source / name)
    for name in VECTORS:
        shutil.copyfile(vectors / f"{name}.mem", source / f"{name}.mem")
    for name in (
        "prepare_exact_control_actual.py",
        "create_shared_realtime_xfft_ip.tcl",
        "simulate_exact_control_prepared.tcl",
    ):
        shutil.copyfile(acq / name, source / name)
    manifest = {
        p.name: hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted(source.iterdir())
    }
    settings = {
        "REGISTERED_SCHEDULING": registered,
        "DISTRIBUTED_FAST_FAULT": distributed,
        "PRIVATE_NEXT_START_SCRATCH": scratch,
        "EXACT_EXTRA_EPOCHS": extras,
        "FAST_MHZ": 175,
        "QUICK_MUTATION": 0,
    }
    (output / "preparation.json").write_text(
        json.dumps(
            {
                "scope": "offline_preparation_only_not_executed_actual_fft",
                "baseline_hdl": BASE,
                "tested_rtl": TESTED_RTL,
                "settings": settings,
                "compared_fields": FIELDS,
                "source_sha256": manifest,
            },
            indent=2,
        )
        + "\n"
    )
    (output / "settings.tcl").write_text(
        "set exact_generics {"
        + " ".join(f"{key}={value}" for key, value in settings.items())
        + "}\n"
    )
    inventory = "".join(
        f"{digest}  frozen_sources/{name}\n" for name, digest in manifest.items()
    )
    for name in ("settings.tcl", "preparation.json"):
        inventory += (
            f"{hashlib.sha256((output / name).read_bytes()).hexdigest()}  {name}\n"
        )
    (output / "SHA256SUMS").write_text(inventory)
    return settings


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--vectors", type=Path, required=True)
    for option in ("registered", "distributed", "scratch", "extras"):
        parser.add_argument(f"--{option}", type=int, choices=(0, 1), required=True)
    args = parser.parse_args()
    print(
        json.dumps(
            prepare(
                args.output,
                args.vectors,
                args.registered,
                args.distributed,
                args.scratch,
                args.extras,
            )
        )
    )


if __name__ == "__main__":
    main()
