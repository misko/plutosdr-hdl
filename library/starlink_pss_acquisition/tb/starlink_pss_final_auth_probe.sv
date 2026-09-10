// SystemVerilog structural measurement composition only. These are the actual guard and
// output mailbox, not an FFT core, input checker, or whole receiver.
// Mode zero selects the prior publication wiring; mode one selects final-only
// authorization. Other wiring is identical to the actual realtime service.
module starlink_pss_final_auth_probe #(
  parameter integer USE_FINAL_AUTH = 0
) (
  input wire clk, resetn, slow_clk, slow_resetn,
  input wire job_valid,
  output wire job_ready,
  input wire [69:0] job_descriptor,
  input wire input_bank_reserved, output_bank_reserved,
  input wire certified_input_beat, certified_input_complete,
  input wire final_fence_certified, external_fault_now, phase_input_fault_now,
  input wire core_event_frame_started,
  input wire [47:0] core_output_tdata,
  input wire [23:0] core_output_tuser,
  input wire core_output_tvalid, core_output_tlast,
  input wire [7:0] core_status_tdata,
  input wire core_status_tvalid,
  output wire busy, commit_pulse, protocol_fault,
  output wire [7:0] fault_reasons,
  output wire output_valid,
  input wire output_ready,
  output wire [35:0] output_data,
  output wire [8:0] output_position,
  output wire output_last,
  output wire [74:0] output_metadata,
  output wire mailbox_fault
);
  wire mailbox_input_valid, mailbox_private_valid, mailbox_commit_valid;
  wire mailbox_input_ready, mailbox_input_last, mailbox_framing_fault;
  wire mailbox_input_fault = mailbox_fault || mailbox_framing_fault;
  wire [35:0] mailbox_input_data;
  wire [8:0] mailbox_input_position;
  wire [74:0] mailbox_input_metadata;
  wire completed_input_certified = 1'bz, completed_input_fault_now = 1'bz;
  wire preflight_fault_evidence_now = 1'bz;
  starlink_pss_realtime_result_guard #(.USE_PHASE_INPUT_FAULT(1)) result_guard (.*);
  starlink_pss_block_mailbox #(.METADATA_WIDTH(75), .RESET_RELEASE_EXTERNAL(1),
    .EXPLICIT_COMMIT(1)) output_mailbox (
    .input_clk(clk), .input_resetn(resetn), .input_valid(mailbox_private_valid),
    .input_commit_authorized(USE_FINAL_AUTH ? mailbox_commit_valid : mailbox_input_valid),
    .input_ready(mailbox_input_ready), .input_data(mailbox_input_data),
    .input_position(mailbox_input_position), .input_last(mailbox_input_last),
    .input_metadata(mailbox_input_metadata), .input_fault(mailbox_fault),
    .input_framing_fault_now(mailbox_framing_fault),
    .output_clk(slow_clk), .output_resetn(slow_resetn), .output_valid(output_valid),
    .output_ready(output_ready), .output_data(output_data),
    .output_position(output_position), .output_last(output_last), .output_metadata(output_metadata)
  );
endmodule
