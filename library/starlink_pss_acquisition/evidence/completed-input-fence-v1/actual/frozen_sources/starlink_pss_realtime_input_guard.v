// SPDX-License-Identifier: GPL-2.0
// ISOLATED EXPERIMENT; no production instantiation or realtime qualification.
// One reset epoch admits exactly one reserved 512-word input job. The caller
// owns reservation, core reset/configuration, result guard and event policy.
// Register the admission/start token; do not form a combinational loop from
// result job_ready through job_start/duplicate_start/fault_now back to job_ready.
// This checker certifies actual correctly framed input handshakes, not output
// numerics, bank ownership, or a bound on delayed vendor events.
//
// PG109 (May 4, 2022), pp51-53: after the first realtime input word, every
// asserted TREADY requires a valid word; ordinary pre-first-word idle and core
// waitstates are legal. Detect a violated demand immediately, even if the
// caller accidentally withdraws input_enable. Do not wait for vendor halt.
`timescale 1ns/1ps
module starlink_pss_realtime_input_guard #(
  parameter integer CHECK_INPUT_BLOCK_IDENTITY = 1
) (
  input wire clk,
  input wire resetn,
  input wire job_start,
  input wire [69:0] job_descriptor,
  input wire input_enable,
  input wire input_valid,
  output wire input_ready,
  output wire input_transport_ready,
  input wire [35:0] input_data,
  input wire [8:0] input_position,
  input wire input_last,
  input wire [69:0] input_metadata,
  output wire [47:0] core_input_tdata,
  output wire core_input_tvalid,
  input wire core_input_tready,
  output wire core_input_tlast,
  output wire certified_input_beat,
  output wire certified_input_complete,
  output reg input_complete,
  output wire fault_now,
  // In the registered input_complete phase, slot_open is closed: this is
  // exactly fault_now, not a delayed sample of it. Per-beat checks remain live
  // during input delivery and still feed the unchanged full reason bank.
  output wire duplicate_start_fault_now,
  output wire protocol_fault,
  output reg [2:0] fault_reasons
);
  initial begin
    if (CHECK_INPUT_BLOCK_IDENTITY != 0 && CHECK_INPUT_BLOCK_IDENTITY != 1)
      $fatal(1, "CHECK_INPUT_BLOCK_IDENTITY must be zero or one");
  end
  reg job_started, input_started;
  reg [69:0] descriptor;
  reg [8:0] expected_position;
  assign protocol_fault = |fault_reasons;
  wire slot_open = resetn && job_started && !input_complete && !protocol_fault;
  wire eligible = slot_open && input_enable;
  wire metadata_valid = input_position == expected_position &&
    input_last == (expected_position == 511) &&
    (!CHECK_INPUT_BLOCK_IDENTITY || input_metadata == descriptor);
  // Checker consumes malformed presented input even while the core stalls.
  // Mailbox retirement uses the explicitly metadata-independent transport cone.
  assign input_ready = eligible && (metadata_valid ? core_input_tready : 1'b1);
  assign input_transport_ready = eligible && core_input_tready;
  assign core_input_tdata = {6'b0, input_data[35:18], 6'b0, input_data[17:0]};
  assign core_input_tvalid = eligible && input_valid && metadata_valid;
  assign core_input_tlast = input_last;
  wire framing_error = eligible && input_valid && !metadata_valid;
  wire delivery_error = slot_open && input_started && core_input_tready &&
    !core_input_tvalid;
  wire duplicate_start = resetn && job_start && job_started;
  assign duplicate_start_fault_now = duplicate_start;
  wire [2:0] errors_now = {duplicate_start, framing_error, delivery_error};
  assign fault_now = |errors_now;
  // A current malformed/duplicate/delivery event cannot certify that edge.
  // The result guard must also consume fault_now as a direct commit veto.
  assign certified_input_beat = core_input_tvalid && core_input_tready && !fault_now;
  assign certified_input_complete = certified_input_beat && expected_position == 511;

  always @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      job_started <= 0;
      input_started <= 0;
      input_complete <= 0;
      descriptor <= 0;
      expected_position <= 0;
      fault_reasons <= 0;
    end else begin
      fault_reasons <= fault_reasons | errors_now;
      if (!protocol_fault && !fault_now) begin
        if (job_start) begin
          job_started <= 1;
          descriptor <= job_descriptor;
        end
        if (certified_input_beat) begin
          input_started <= 1;
          if (certified_input_complete) input_complete <= 1;
        end
      end
      // This cursor is private, not a delivered-beat certificate. A presented
      // malformed/duplicate beat may advance it on its fault edge; unchanged
      // errors_now sets sticky quarantine on that same edge, closing slot_open
      // before any later certificate or delivery. All public checks still use
      // the original pre-edge ordinal. Saturate rather than wrap at the final
      // slot, and purge the private value only through the existing reset.
      // Keep the ordinal/metadata comparator off this counter's enable path.
      if (slot_open && input_enable && input_valid && core_input_tready &&
          expected_position != 511)
        expected_position <= expected_position + 1'b1;
    end
  end
endmodule
