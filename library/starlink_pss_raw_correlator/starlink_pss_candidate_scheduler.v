// SPDX-License-Identifier: GPL-2.0
//
// Queued-center and accepted-sample capture contract for the experimental
// Starlink RX-only branch.  This module does not score samples.  It crosses
// host/MMIO candidate commands into the accepted-sample clock domain, admits
// them deterministically, and emits the exact 130 tagged samples consumed by
// the Stage-15 correlator.

`timescale 1ns/1ps

module starlink_pss_candidate_scheduler #(
  parameter integer COMMAND_FIFO_ADDRESS_WIDTH = 3,
  parameter [63:0] MINIMUM_LEAD_SAMPLES = 64'd64
) (
  input  wire                i_control_clk,
  input  wire                i_control_resetn,

  // One control-clock pulse represents one MMIO submission attempt.  A
  // successful pulse is queued exactly once; a pulse while full increments
  // the overrun counter exactly once.
  input  wire                i_candidate_submit,
  input  wire         [31:0] i_candidate_request_id,
  input  wire         [63:0] i_candidate_center_index,
  input  wire         [63:0] i_candidate_center_timestamp,
  output wire                o_candidate_submit_ready,
  output reg                 o_candidate_submit_accepted,
  output wire [COMMAND_FIFO_ADDRESS_WIDTH-1:0] o_candidate_queue_room,
  output reg          [31:0] o_queue_overrun_count,

  input  wire                i_sample_clk,
  input  wire                i_sample_resetn,
  input  wire                i_sample_enable,
  input  wire                i_sample_valid,
  input  wire         [63:0] i_sample_index,
  input  wire         [63:0] i_sample_timestamp,
  input  wire signed  [15:0] i_sample_i,
  input  wire signed  [15:0] i_sample_q,

  // No backpressure is allowed at this boundary.  The later capture-buffer
  // writer either commits all 130 beats or discards the job on o_capture_abort.
  output reg                 o_capture_valid,
  output reg                 o_capture_start,
  output reg                 o_capture_done,
  output reg                 o_capture_abort,
  output reg           [7:0] o_capture_slot,
  output wire         [31:0] o_capture_request_id,
  output wire         [63:0] o_capture_center_index,
  output wire         [63:0] o_capture_center_timestamp,
  output reg          [63:0] o_capture_sample_index,
  output reg          [63:0] o_capture_sample_timestamp,
  output reg  signed  [15:0] o_capture_sample_i,
  output reg  signed  [15:0] o_capture_sample_q,

  output wire                o_candidate_pending,
  output wire                o_capture_active,
  output reg          [31:0] o_admitted_count,
  output reg          [31:0] o_completed_count,
  output reg          [31:0] o_rejected_count,
  output reg          [31:0] o_late_count,
  output reg          [31:0] o_duplicate_count,
  output reg          [31:0] o_overlap_count,
  output reg          [31:0] o_aborted_count,
  output reg          [31:0] o_valid_gap_abort_count,
  output reg          [31:0] o_index_jump_abort_count,
  output reg          [31:0] o_timestamp_abort_count
);

  localparam integer COMMAND_WIDTH = 160;
  localparam [63:0] CAPTURE_BEFORE_CENTER = 64'd32;
  localparam [63:0] CAPTURE_AFTER_CENTER = 64'd97;
  localparam [7:0] CAPTURE_LAST_SLOT = 8'd129;

  function automatic [31:0] increment_saturating_32;
    input [31:0] value;
    begin
      increment_saturating_32 = (&value) ? value : value + 1'b1;
    end
  endfunction

  wire [COMMAND_WIDTH-1:0] command_write_data = {
    i_candidate_request_id,
    i_candidate_center_index,
    i_candidate_center_timestamp
  };
  wire command_write =
      i_control_resetn && i_candidate_submit && o_candidate_submit_ready;
  wire command_read_valid;
  wire command_read_ready;
  wire [COMMAND_WIDTH-1:0] command_read_data;

  starlink_pss_async_fifo #(
    .DATA_WIDTH    (COMMAND_WIDTH),
    .ADDRESS_WIDTH (COMMAND_FIFO_ADDRESS_WIDTH),
    .RAM_STYLE     ("block")
  ) i_command_fifo (
    .i_write_clk    (i_control_clk),
    .i_write_resetn (i_control_resetn),
    .i_write_valid  (command_write),
    .o_write_ready  (o_candidate_submit_ready),
    .i_write_data   (command_write_data),
    .o_write_room   (o_candidate_queue_room),
    .i_read_clk     (i_sample_clk),
    .i_read_resetn  (i_sample_resetn),
    .o_read_valid   (command_read_valid),
    .i_read_ready   (command_read_ready),
    .o_read_data    (command_read_data)
  );

  always @(posedge i_control_clk) begin
    if (!i_control_resetn) begin
      o_candidate_submit_accepted <= 1'b0;
      o_queue_overrun_count <= 32'd0;
    end else begin
      o_candidate_submit_accepted <= command_write;
      if (i_candidate_submit && !o_candidate_submit_ready)
        o_queue_overrun_count <= increment_saturating_32(o_queue_overrun_count);
    end
  end

  wire [31:0] command_request_id = command_read_data[159:128];
  wire [63:0] command_center_index = command_read_data[127:64];
  wire [63:0] command_center_timestamp = command_read_data[63:0];
  wire [63:0] command_start_index =
      command_center_index - CAPTURE_BEFORE_CENTER;
  wire [63:0] command_end_index =
      command_center_index + CAPTURE_AFTER_CENTER;
  assign o_capture_request_id = command_request_id;
  assign o_capture_center_index = command_center_index;
  assign o_capture_center_timestamp = command_center_timestamp;

  reg stream_locked;
  reg [63:0] next_expected_index;
  reg candidate_pending;
  reg capture_active;
  reg [7:0] current_capture_slot;

  reg last_admitted_valid;
  reg [63:0] last_admitted_center_index;

  assign o_candidate_pending = candidate_pending;
  assign o_capture_active = capture_active;

  // A disabled lane drains one queued request per sample clock only after an
  // already admitted request has been flushed.  An enabled lane pops only on
  // a consecutive accepted sample, so admission lead is measured from the
  // exact next accepted index rather than from an inferred wall-clock cycle.
  wire sample_is_consecutive =
      stream_locked && i_sample_valid && (i_sample_index == next_expected_index);
  assign command_read_ready =
      (!i_sample_resetn) ? 1'b0 :
      (!i_sample_enable) ? !(candidate_pending || capture_active) :
      (!(candidate_pending || capture_active) && sample_is_consecutive);

  wire command_handshake = command_read_valid && command_read_ready;
  wire [63:0] admission_next_index = i_sample_index + 1'b1;
  wire [63:0] command_lead = command_start_index - admission_next_index;
  wire command_late =
      command_lead[63] || (command_lead < MINIMUM_LEAD_SAMPLES);
  wire command_duplicate =
      last_admitted_valid &&
      (command_center_index == last_admitted_center_index);
  wire [63:0] command_center_distance =
      command_center_index - last_admitted_center_index;
  wire command_overlap =
      last_admitted_valid && !command_duplicate &&
      (command_center_distance[63] ||
       (command_center_distance <= 64'd129));
  wire [63:0] current_start_pass_distance =
      i_sample_index - command_start_index;

  task automatic publish_capture_beat;
    input [7:0] slot;
    begin
      o_capture_valid <= 1'b1;
      o_capture_slot <= slot;
      o_capture_sample_index <= i_sample_index;
      o_capture_sample_timestamp <= i_sample_timestamp;
      o_capture_sample_i <= i_sample_i;
      o_capture_sample_q <= i_sample_q;
    end
  endtask

  always @(posedge i_sample_clk) begin
    if (!i_sample_resetn) begin
      stream_locked <= 1'b0;
      next_expected_index <= 64'd0;
      candidate_pending <= 1'b0;
      capture_active <= 1'b0;
      current_capture_slot <= 8'd0;
      last_admitted_valid <= 1'b0;
      last_admitted_center_index <= 64'd0;
      o_capture_valid <= 1'b0;
      o_capture_start <= 1'b0;
      o_capture_done <= 1'b0;
      o_capture_abort <= 1'b0;
      o_capture_slot <= 8'd0;
      o_capture_sample_index <= 64'd0;
      o_capture_sample_timestamp <= 64'd0;
      o_capture_sample_i <= 16'sd0;
      o_capture_sample_q <= 16'sd0;
      o_admitted_count <= 32'd0;
      o_completed_count <= 32'd0;
      o_rejected_count <= 32'd0;
      o_late_count <= 32'd0;
      o_duplicate_count <= 32'd0;
      o_overlap_count <= 32'd0;
      o_aborted_count <= 32'd0;
      o_valid_gap_abort_count <= 32'd0;
      o_index_jump_abort_count <= 32'd0;
      o_timestamp_abort_count <= 32'd0;
    end else begin
      o_capture_valid <= 1'b0;
      o_capture_start <= 1'b0;
      o_capture_done <= 1'b0;
      o_capture_abort <= 1'b0;

      if (!i_sample_enable) begin
        stream_locked <= 1'b0;
        if (candidate_pending || capture_active) begin
          candidate_pending <= 1'b0;
          capture_active <= 1'b0;
          o_capture_abort <= 1'b1;
          o_aborted_count <= increment_saturating_32(o_aborted_count);
        end else if (command_handshake) begin
          // The command entered the CDC FIFO but the detector lane was
          // disabled before sample-domain admission.
          o_rejected_count <= increment_saturating_32(o_rejected_count);
          o_aborted_count <= increment_saturating_32(o_aborted_count);
        end
      end else if (!i_sample_valid) begin
        stream_locked <= 1'b0;
        if (candidate_pending || capture_active) begin
          candidate_pending <= 1'b0;
          capture_active <= 1'b0;
          o_capture_abort <= 1'b1;
          o_aborted_count <= increment_saturating_32(o_aborted_count);
          o_valid_gap_abort_count <=
              increment_saturating_32(o_valid_gap_abort_count);
        end
      end else if (!stream_locked) begin
        stream_locked <= 1'b1;
        next_expected_index <= i_sample_index + 1'b1;
      end else if (i_sample_index != next_expected_index) begin
        // The current sample becomes the new stream anchor, but every admitted
        // request spanning the discontinuity is failed closed.
        next_expected_index <= i_sample_index + 1'b1;
        if (candidate_pending || capture_active) begin
          candidate_pending <= 1'b0;
          capture_active <= 1'b0;
          o_capture_abort <= 1'b1;
          o_aborted_count <= increment_saturating_32(o_aborted_count);
          o_index_jump_abort_count <=
              increment_saturating_32(o_index_jump_abort_count);
        end
      end else begin
        next_expected_index <= i_sample_index + 1'b1;

        if (command_handshake) begin
          // Rejection priority is part of the ABI: duplicate, overlap or
          // out-of-order, then insufficient lead/late.
          if (command_duplicate) begin
            o_rejected_count <= increment_saturating_32(o_rejected_count);
            o_duplicate_count <= increment_saturating_32(o_duplicate_count);
          end else if (command_overlap) begin
            o_rejected_count <= increment_saturating_32(o_rejected_count);
            o_overlap_count <= increment_saturating_32(o_overlap_count);
          end else if (command_late) begin
            o_rejected_count <= increment_saturating_32(o_rejected_count);
            o_late_count <= increment_saturating_32(o_late_count);
          end else begin
            candidate_pending <= 1'b1;
            current_capture_slot <= 8'd0;
            last_admitted_valid <= 1'b1;
            last_admitted_center_index <= command_center_index;
            o_admitted_count <= increment_saturating_32(o_admitted_count);
          end
        end else if (candidate_pending) begin
          if (i_sample_index == command_start_index) begin
            candidate_pending <= 1'b0;
            capture_active <= 1'b1;
            current_capture_slot <= 8'd0;
            publish_capture_beat(8'd0);
            o_capture_start <= 1'b1;
          end else if (current_start_pass_distance[63] == 1'b0) begin
            // Consecutive input passed the start without observing it.  This
            // should be unreachable after a legal admission, but is retained
            // as an explicit fail-closed late path.
            candidate_pending <= 1'b0;
            o_capture_abort <= 1'b1;
            o_rejected_count <= increment_saturating_32(o_rejected_count);
            o_late_count <= increment_saturating_32(o_late_count);
            o_aborted_count <= increment_saturating_32(o_aborted_count);
          end
        end else if (capture_active) begin
          publish_capture_beat(current_capture_slot + 1'b1);
          current_capture_slot <= current_capture_slot + 1'b1;

          if ((i_sample_index == command_center_index) &&
              (i_sample_timestamp != command_center_timestamp)) begin
            capture_active <= 1'b0;
            o_capture_abort <= 1'b1;
            o_aborted_count <= increment_saturating_32(o_aborted_count);
            o_timestamp_abort_count <=
                increment_saturating_32(o_timestamp_abort_count);
          end else if ((current_capture_slot + 1'b1 == CAPTURE_LAST_SLOT) &&
                       (i_sample_index == command_end_index)) begin
            capture_active <= 1'b0;
            o_capture_done <= 1'b1;
            o_completed_count <= increment_saturating_32(o_completed_count);
          end
        end
      end
    end
  end

endmodule
