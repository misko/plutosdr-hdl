// TEST-ONLY GOLDEN: ff4229bb230437fcd975413390a34c00ffcc226f.
// Original acquisition/starlink_pss_realtime_result_guard.v SHA256:
// a3637871ad72551987006b5d5c1e0de716f28a07e706c0decf036e072cd7f35c.
// Only the module identifier below is renamed; never instantiate in production.
// SPDX-License-Identifier: GPL-2.0
// ISOLATED EXPERIMENT: not connected to the production shared-XFFT service.
// One reserved result bank plus one 52-bit return slot; no extra payload RAM.
// The unchanged block mailbox publishes on its final write, so word 511 stays
// here until independent status and all explicitly certified premises pass.
//
// CALLER OBLIGATIONS (not established by this module):
// - resetn is a common, synchronously released epoch for BOTH mailbox clocks;
// - input_bank_reserved means a complete, checked/prefetched 512-word bank;
// - output_bank_reserved is exclusive whole-bank ownership, not just READY;
// - certified_input_beat denotes an actually delivered, fully checked core beat;
// - certified_input_complete certifies the input framing/identity checks;
// - external_fault_now includes immediate starvation/input/core/ownership faults;
// - final_fence_certified proves all potentially corrupting delayed events have
//   been observed or excluded. NO vendor-event latency bound is inferred here.
// A pulse/claim from an unqualified caller cannot make a qualified FFT service.
// There is no output/status backpressure to the realtime core. Unexpected
// transport stalls fault closed. A new job waits for the mailbox's actual ACK.
`timescale 1ns/1ps

module starlink_pss_realtime_result_guard_ff4229_golden #(
  parameter integer WATCHDOG_CYCLES = 8192
) (
  input wire clk,
  input wire resetn,
  input wire job_valid,
  output wire job_ready,
  input wire [69:0] job_descriptor,
  input wire input_bank_reserved,
  input wire output_bank_reserved,
  input wire certified_input_beat,
  input wire certified_input_complete,
  input wire final_fence_certified,
  input wire external_fault_now,
  input wire core_event_frame_started,
  input wire [47:0] core_output_tdata,
  input wire [23:0] core_output_tuser,
  input wire core_output_tvalid,
  input wire core_output_tlast,
  input wire [7:0] core_status_tdata,
  input wire core_status_tvalid,
  output wire mailbox_input_valid,
  input wire mailbox_input_ready,
  input wire mailbox_input_fault,
  output wire [35:0] mailbox_input_data,
  output wire [8:0] mailbox_input_position,
  output wire mailbox_input_last,
  output wire [74:0] mailbox_input_metadata,
  output wire busy,
  output reg commit_pulse,
  output wire protocol_fault,
  output reg [7:0] fault_reasons
);
  localparam integer AGE_WIDTH = $clog2(WATCHDOG_CYCLES);
  initial begin
    if (WATCHDOG_CYCLES < 2 || WATCHDOG_CYCLES > 1048576)
      $fatal(1, "realtime result guard requires a finite 2..1048576 cycle watchdog");
  end

  reg active, awaiting_ack;
  reg [69:0] descriptor;
  reg [9:0] input_count, output_count;
  reg input_complete_seen, frame_seen, status_seen, exponent_seen;
  reg [4:0] status_exponent, output_exponent;
  reg [AGE_WIDTH-1:0] age;
  reg return_valid, return_last;
  reg [35:0] return_data;
  reg [8:0] return_position;
  reg [4:0] return_exponent;

  wire [10:0] effective_input_count = {1'b0, input_count} + certified_input_beat;
  wire effective_input_complete = input_complete_seen || certified_input_complete;
  wire effective_frame_seen = frame_seen || core_event_frame_started;
  wire reservation_error = active && (!output_bank_reserved ||
    (!input_complete_seen && !input_bank_reserved));
  wire input_error = (certified_input_beat &&
    (!active || input_complete_seen || input_count == 512)) ||
    (certified_input_complete &&
    (!active || input_complete_seen || effective_input_count != 512));
  wire frame_error = core_event_frame_started &&
    (!active || frame_seen || (input_count == 0 && !certified_input_beat));
  wire status_error = core_status_tvalid &&
    (!active || status_seen || core_status_tdata[7:5] != 0 ||
     (exponent_seen && core_status_tdata[4:0] != output_exponent));
  // Preserve the existing BFP18 layout: two 18-bit values in 24-bit AXI slots;
  // TUSER is {3'b0, exponent[4:0], 7'b0, XK_INDEX[8:0]}.
  // The unused upper component-slot bits are ignored, as in the old adapter.
  wire output_error = core_output_tvalid &&
    (!active || output_count == 512 || !effective_input_complete ||
     effective_input_count != 512 || !effective_frame_seen ||
     core_output_tuser[15:9] != 0 || core_output_tuser[23:21] != 0 ||
     core_output_tuser[8:0] != output_count[8:0] ||
     core_output_tlast != (output_count == 511) ||
     (exponent_seen && core_output_tuser[20:16] != output_exponent) ||
     (status_seen && core_output_tuser[20:16] != status_exponent) ||
     (core_status_tvalid && core_output_tuser[20:16] != core_status_tdata[4:0]));
  wire slot_error = active && return_valid &&
    ((!return_last && !mailbox_input_ready) ||
     (core_output_tvalid && (return_last || !mailbox_input_ready)));
  wire watchdog_error = active && age == WATCHDOG_CYCLES - 1;
  wire [7:0] faults_now = {watchdog_error, slot_error, output_error, status_error,
    frame_error, input_error, reservation_error, external_fault_now || mailbox_input_fault};
  wire fault_now = |faults_now;
  assign protocol_fault = |fault_reasons;
  assign busy = active || awaiting_ack;
  assign job_ready = resetn && !protocol_fault && !fault_now &&
    !active && !awaiting_ack && !return_valid &&
    input_bank_reserved && output_bank_reserved && mailbox_input_ready;
  wire job_accept = job_valid && job_ready;

  // Only REGISTERED complete evidence opens the final write. A coincident new
  // status, duplicate status, frame event, raw extra word, timeout or external
  // fault still participates in faults_now and directly vetoes that same edge.
  wire final_qualified = input_count == 512 && input_complete_seen &&
    output_count == 512 && frame_seen && exponent_seen && status_seen &&
    output_exponent == status_exponent && final_fence_certified;
  assign mailbox_input_valid = resetn && active && !protocol_fault && !fault_now &&
    return_valid && (!return_last || final_qualified);
  assign mailbox_input_data = return_data;
  assign mailbox_input_position = return_position;
  assign mailbox_input_last = return_last;
  // Same ordering as the existing service: descriptor, then new exponent.
  assign mailbox_input_metadata = {descriptor, return_exponent};
  wire mailbox_accept = mailbox_input_valid && mailbox_input_ready;
  wire final_commit = mailbox_accept && return_last;

  always @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      active <= 0;
      awaiting_ack <= 0;
      descriptor <= 0;
      input_count <= 0;
      output_count <= 0;
      input_complete_seen <= 0;
      frame_seen <= 0;
      status_seen <= 0;
      exponent_seen <= 0;
      status_exponent <= 0;
      output_exponent <= 0;
      age <= 0;
      return_valid <= 0;
      return_last <= 0;
      return_data <= 0;
      return_position <= 0;
      return_exponent <= 0;
      commit_pulse <= 0;
      fault_reasons <= 0;
    end else begin
      commit_pulse <= 0;
      fault_reasons <= fault_reasons | faults_now;
      // Account the raw arriving beat even if it triggers quarantine. This
      // counter is private; malformed data still cannot enter the return slot
      // or publish. Saturate beyond the one allowed block rather than wrap.
      if (active && !protocol_fault && core_output_tvalid && output_count < 513)
        output_count <= output_count + 1'b1;
      if (protocol_fault || fault_now) begin
        active <= 0;
        return_valid <= 0;
      end else begin
        if (awaiting_ack && mailbox_input_ready) awaiting_ack <= 0;
        if (job_accept) begin
          active <= 1;
          descriptor <= job_descriptor;
          input_count <= 0;
          output_count <= 0;
          input_complete_seen <= 0;
          frame_seen <= 0;
          status_seen <= 0;
          exponent_seen <= 0;
          age <= 0;
        end
        if (active) begin
          age <= age + 1'b1;
          if (certified_input_beat) input_count <= input_count + 1'b1;
          if (certified_input_complete) input_complete_seen <= 1;
          if (core_event_frame_started) frame_seen <= 1;
          if (core_status_tvalid) begin
            status_seen <= 1;
            status_exponent <= core_status_tdata[4:0];
          end
          if (mailbox_accept) return_valid <= 0;
          if (core_output_tvalid) begin
            if (!exponent_seen) output_exponent <= core_output_tuser[20:16];
            exponent_seen <= 1;
            return_valid <= 1;
            return_data <= {core_output_tdata[41:24], core_output_tdata[17:0]};
            return_position <= core_output_tuser[8:0];
            return_last <= core_output_tlast;
            return_exponent <= core_output_tuser[20:16];
          end
          if (final_commit) begin
            active <= 0;
            awaiting_ack <= 1;
            commit_pulse <= 1;
          end
        end
      end
    end
  end
endmodule
