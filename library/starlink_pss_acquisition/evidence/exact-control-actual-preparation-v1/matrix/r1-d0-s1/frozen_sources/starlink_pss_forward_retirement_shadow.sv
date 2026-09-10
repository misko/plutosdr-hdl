`timescale 1ns/1fs
// Frozen full old guard: no candidate forward predicates feed this witness.
module starlink_pss_forward_retirement_shadow #(
  parameter integer ENABLED = 1,
  parameter integer COMPLETED = 1,
  parameter integer PHASE_INPUT = 0,
  parameter integer PREFLIGHT = 0,
  parameter integer WATCHDOG = 8192
) (
  input wire clk, resetn, job_valid,
  input wire [69:0] job_descriptor,
  input wire input_bank_reserved, output_bank_reserved,
  input wire certified_input_beat, certified_input_complete, final_fence_certified,
  input wire external_fault_now, phase_input_fault_now,
  input wire completed_input_certified, completed_input_fault_now, preflight_fault_evidence_now,
  input wire core_event_frame_started,
  input wire [47:0] core_output_tdata,
  input wire [23:0] core_output_tuser,
  input wire core_output_tvalid, core_output_tlast,
  input wire [7:0] core_status_tdata,
  input wire core_status_tvalid, mailbox_input_ready, mailbox_input_fault,
  input wire inverse_phase, forward_mailbox_fault, mailbox_current_fault_now,
  input wire [135:0] actual_public,
  input wire actual_forward_valid,
  output wire old_valid, old_private_valid,
  output integer checks = 0,
  output integer forward_cycles = 0,
  output integer inverse_current_faults = 0,
  output integer sticky_forward_faults = 0
);
  wire old_ready, old_commit_valid, old_last, old_busy, old_commit, old_fault;
  wire [35:0] old_data;
  wire [8:0] old_position;
  wire [74:0] old_metadata;
  wire [7:0] old_reasons;
  starlink_pss_realtime_result_guard_ce6a885e_golden #(
    .WATCHDOG_CYCLES(WATCHDOG), .USE_COMPLETED_INPUT_FAULT(COMPLETED),
    .USE_PHASE_INPUT_FAULT(PHASE_INPUT), .USE_PREFLIGHT_REASON_ONLY(PREFLIGHT)) old_guard (
    .clk(clk), .resetn(resetn), .job_valid(job_valid), .job_ready(old_ready),
    .job_descriptor(job_descriptor), .input_bank_reserved(input_bank_reserved),
    .output_bank_reserved(output_bank_reserved), .certified_input_beat(certified_input_beat),
    .certified_input_complete(certified_input_complete), .final_fence_certified(final_fence_certified),
    .external_fault_now(external_fault_now), .phase_input_fault_now(phase_input_fault_now),
    .completed_input_certified(completed_input_certified), .completed_input_fault_now(completed_input_fault_now),
    .preflight_fault_evidence_now(preflight_fault_evidence_now), .core_event_frame_started(core_event_frame_started),
    .core_output_tdata(core_output_tdata), .core_output_tuser(core_output_tuser),
    .core_output_tvalid(core_output_tvalid), .core_output_tlast(core_output_tlast),
    .core_status_tdata(core_status_tdata), .core_status_tvalid(core_status_tvalid),
    .mailbox_input_ready(mailbox_input_ready), .mailbox_input_fault(mailbox_input_fault),
    .mailbox_input_valid(old_valid), .mailbox_private_valid(old_private_valid),
    .mailbox_commit_valid(old_commit_valid), .mailbox_input_data(old_data),
    .mailbox_input_position(old_position), .mailbox_input_last(old_last), .mailbox_input_metadata(old_metadata),
    .busy(old_busy), .commit_pulse(old_commit), .protocol_fault(old_fault), .fault_reasons(old_reasons)
  );
  task check;
    begin
      checks = checks + 1;
      if (mailbox_current_fault_now === 1'b1 && inverse_phase !== 1'b1)
        $fatal(1, "FORWARD_CALLER_PHASE_INVARIANT_BROKEN");
      if (mailbox_input_fault !== (forward_mailbox_fault || mailbox_current_fault_now))
        $fatal(1, "FORWARD_CALLER_FAULT_SPLIT_BROKEN");
      if (actual_public !== {old_ready, old_valid, old_private_valid, old_commit_valid,
          old_data, old_position, old_last, old_metadata, old_busy, old_commit, old_fault, old_reasons})
        $fatal(1, "FORWARD_OLD_PUBLIC_MISMATCH");
      if (actual_forward_valid !== (ENABLED && old_valid && !inverse_phase))
        $fatal(1, "FORWARD_RETIREMENT_MISMATCH phase=%0d sticky=%0d old=%0d new=%0d",
          inverse_phase, forward_mailbox_fault, old_valid, actual_forward_valid);
      if (resetn && old_valid && !inverse_phase) forward_cycles = forward_cycles + 1;
      if (resetn && mailbox_current_fault_now) inverse_current_faults = inverse_current_faults + 1;
      if (resetn && !inverse_phase && forward_mailbox_fault) sticky_forward_faults = sticky_forward_faults + 1;
    end
  endtask
  always @(posedge clk or negedge clk) begin #0.001; check(); end
endmodule
