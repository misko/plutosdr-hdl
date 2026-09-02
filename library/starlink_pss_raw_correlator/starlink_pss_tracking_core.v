// SPDX-License-Identifier: GPL-2.0
//
// Host-commanded Stage-15 tracking slice.  This composition keeps the three
// clocks explicit while enforcing one shared reset epoch, and connects the
// queued candidate scheduler through an abort-atomic double capture buffer to
// the cached-Eh/sliding-Ex correlator.

`timescale 1ns/1ps

module starlink_pss_tracking_core #(
  parameter integer COMMAND_FIFO_ADDRESS_WIDTH = 3,
  parameter [63:0] MINIMUM_LEAD_SAMPLES = 64'd64
) (
  input  wire                i_control_clk,
  input  wire                i_sample_clk,
  input  wire                i_engine_clk,
  input  wire                i_control_resetn,
  input  wire                i_sample_resetn,
  input  wire                i_engine_resetn,

  input  wire                i_candidate_submit,
  input  wire         [31:0] i_candidate_request_id,
  input  wire         [63:0] i_candidate_center_index,
  input  wire         [63:0] i_candidate_center_timestamp,
  output wire                o_candidate_submit_ready,
  output wire                o_candidate_submit_accepted,
  output wire [COMMAND_FIFO_ADDRESS_WIDTH-1:0] o_candidate_queue_room,
  output wire         [31:0] o_queue_overrun_count,

  input  wire                i_sample_enable,
  input  wire                i_sample_valid,
  input  wire         [63:0] i_sample_index,
  input  wire         [63:0] i_sample_timestamp,
  input  wire signed  [15:0] i_sample_i,
  input  wire signed  [15:0] i_sample_q,

  input  wire                i_coefficient_clear,
  input  wire                i_coefficient_valid,
  output wire                o_coefficient_ready,
  input  wire signed  [15:0] i_coefficient_i,
  input  wire signed  [15:0] i_coefficient_q,
  input  wire                i_coefficient_commit,
  output wire                o_coefficient_commit_ready,
  input  wire         [31:0] i_coefficient_generation,
  output wire                o_coefficient_commit_accepted,
  output wire                o_coefficient_commit_rejected,
  output wire                o_active_coefficient_valid,
  output wire         [31:0] o_active_coefficient_generation,
  output wire signed  [47:0] o_active_coefficient_energy,
  output wire          [6:0] o_shadow_coefficient_count,
  output wire                o_configuration_idle,

  output wire                o_result_valid,
  input  wire                i_result_ready,
  output wire         [31:0] o_result_request_id,
  output wire         [63:0] o_result_center_index,
  output wire         [63:0] o_result_center_timestamp,
  output wire signed   [6:0] o_result_lag,
  output wire         [63:0] o_result_timestamp,
  output wire         [31:0] o_result_coefficient_generation,
  output wire signed  [47:0] o_result_c_re,
  output wire signed  [47:0] o_result_c_im,
  output wire signed  [47:0] o_result_ex,
  output wire signed  [47:0] o_result_eh,
  output wire          [8:0] o_result_saturation_events,

  output wire                o_candidate_pending,
  output wire                o_capture_active,
  output wire         [31:0] o_admitted_count,
  output wire         [31:0] o_completed_capture_count,
  output wire         [31:0] o_rejected_count,
  output wire         [31:0] o_late_count,
  output wire         [31:0] o_duplicate_count,
  output wire         [31:0] o_overlap_count,
  output wire         [31:0] o_aborted_count,
  output wire         [31:0] o_valid_gap_abort_count,
  output wire         [31:0] o_index_jump_abort_count,
  output wire         [31:0] o_timestamp_abort_count,
  output wire          [1:0] o_capture_bank_free,
  output wire         [31:0] o_capture_published_count,
  output wire         [31:0] o_capture_abort_discard_count,
  output wire         [31:0] o_capture_buffer_overrun_count,
  output wire         [31:0] o_capture_protocol_error_count,
  output wire         [31:0] o_engine_consumed_count,
  output wire         [31:0] o_bound_error_count
);

  wire scheduler_capture_valid;
  wire scheduler_capture_start;
  wire scheduler_capture_done;
  wire scheduler_capture_abort;
  wire [7:0] scheduler_capture_slot;
  wire [31:0] scheduler_capture_request_id;
  wire [63:0] scheduler_capture_center_index;
  wire [63:0] scheduler_capture_center_timestamp;
  wire [63:0] scheduler_capture_sample_index_unused;
  wire [63:0] scheduler_capture_sample_timestamp;
  wire signed [15:0] scheduler_capture_sample_i;
  wire signed [15:0] scheduler_capture_sample_q;

  starlink_pss_candidate_scheduler #(
    .COMMAND_FIFO_ADDRESS_WIDTH (COMMAND_FIFO_ADDRESS_WIDTH),
    .MINIMUM_LEAD_SAMPLES       (MINIMUM_LEAD_SAMPLES)
  ) i_candidate_scheduler (
    .i_control_clk                 (i_control_clk),
    .i_control_resetn              (i_control_resetn),
    .i_candidate_submit            (i_candidate_submit),
    .i_candidate_request_id        (i_candidate_request_id),
    .i_candidate_center_index      (i_candidate_center_index),
    .i_candidate_center_timestamp  (i_candidate_center_timestamp),
    .o_candidate_submit_ready      (o_candidate_submit_ready),
    .o_candidate_submit_accepted   (o_candidate_submit_accepted),
    .o_candidate_queue_room        (o_candidate_queue_room),
    .o_queue_overrun_count         (o_queue_overrun_count),
    .i_sample_clk                  (i_sample_clk),
    .i_sample_resetn               (i_sample_resetn),
    .i_sample_enable               (i_sample_enable),
    .i_sample_valid                (i_sample_valid),
    .i_sample_index                (i_sample_index),
    .i_sample_timestamp            (i_sample_timestamp),
    .i_sample_i                    (i_sample_i),
    .i_sample_q                    (i_sample_q),
    .o_capture_valid               (scheduler_capture_valid),
    .o_capture_start               (scheduler_capture_start),
    .o_capture_done                (scheduler_capture_done),
    .o_capture_abort               (scheduler_capture_abort),
    .o_capture_slot                (scheduler_capture_slot),
    .o_capture_request_id          (scheduler_capture_request_id),
    .o_capture_center_index        (scheduler_capture_center_index),
    .o_capture_center_timestamp    (scheduler_capture_center_timestamp),
    .o_capture_sample_index        (scheduler_capture_sample_index_unused),
    .o_capture_sample_timestamp    (scheduler_capture_sample_timestamp),
    .o_capture_sample_i            (scheduler_capture_sample_i),
    .o_capture_sample_q            (scheduler_capture_sample_q),
    .o_candidate_pending           (o_candidate_pending),
    .o_capture_active              (o_capture_active),
    .o_admitted_count              (o_admitted_count),
    .o_completed_count             (o_completed_capture_count),
    .o_rejected_count              (o_rejected_count),
    .o_late_count                  (o_late_count),
    .o_duplicate_count             (o_duplicate_count),
    .o_overlap_count               (o_overlap_count),
    .o_aborted_count               (o_aborted_count),
    .o_valid_gap_abort_count       (o_valid_gap_abort_count),
    .o_index_jump_abort_count      (o_index_jump_abort_count),
    .o_timestamp_abort_count       (o_timestamp_abort_count)
  );

  wire bridge_capture_ready_unused;
  wire bridge_engine_job_start;
  wire bridge_engine_job_done;
  wire [31:0] bridge_engine_request_id;
  wire [63:0] bridge_engine_center_index;
  wire [63:0] bridge_engine_center_timestamp;
  wire bridge_engine_sample_valid;
  wire bridge_engine_sample_ready;
  wire [7:0] bridge_engine_sample_slot_unused;
  wire [63:0] bridge_engine_sample_timestamp;
  wire signed [15:0] bridge_engine_sample_i;
  wire signed [15:0] bridge_engine_sample_q;
  wire bridge_engine_job_ready;

  starlink_pss_capture_bridge i_capture_bridge (
    .i_sample_clk                    (i_sample_clk),
    .i_sample_resetn                 (i_sample_resetn),
    .i_capture_valid                 (scheduler_capture_valid),
    .i_capture_start                 (scheduler_capture_start),
    .i_capture_done                  (scheduler_capture_done),
    .i_capture_abort                 (scheduler_capture_abort),
    .i_capture_slot                  (scheduler_capture_slot),
    .i_capture_request_id            (scheduler_capture_request_id),
    .i_capture_center_index          (scheduler_capture_center_index),
    .i_capture_center_timestamp      (scheduler_capture_center_timestamp),
    .i_capture_sample_timestamp      (scheduler_capture_sample_timestamp),
    .i_capture_sample_i              (scheduler_capture_sample_i),
    .i_capture_sample_q              (scheduler_capture_sample_q),
    .o_capture_ready                 (bridge_capture_ready_unused),
    .o_capture_bank_free             (o_capture_bank_free),
    .o_capture_published_count       (o_capture_published_count),
    .o_capture_abort_discard_count   (o_capture_abort_discard_count),
    .o_capture_buffer_overrun_count  (o_capture_buffer_overrun_count),
    .o_capture_protocol_error_count  (o_capture_protocol_error_count),
    .i_engine_clk                    (i_engine_clk),
    .i_engine_resetn                 (i_engine_resetn),
    .i_engine_job_ready              (bridge_engine_job_ready),
    .o_engine_job_start              (bridge_engine_job_start),
    .o_engine_job_done               (bridge_engine_job_done),
    .o_engine_request_id             (bridge_engine_request_id),
    .o_engine_center_index           (bridge_engine_center_index),
    .o_engine_center_timestamp       (bridge_engine_center_timestamp),
    .o_engine_sample_valid           (bridge_engine_sample_valid),
    .i_engine_sample_ready           (bridge_engine_sample_ready),
    .o_engine_sample_slot            (bridge_engine_sample_slot_unused),
    .o_engine_sample_timestamp       (bridge_engine_sample_timestamp),
    .o_engine_sample_i               (bridge_engine_sample_i),
    .o_engine_sample_q               (bridge_engine_sample_q),
    .o_engine_consumed_count         (o_engine_consumed_count)
  );

  wire [7:0] correlator_sample_count;
  wire correlator_start_ready;
  wire correlator_busy;
  wire correlator_done_unused;
  wire correlator_start = bridge_engine_job_done && correlator_start_ready;

  assign bridge_engine_job_ready =
      bridge_engine_sample_ready && (correlator_sample_count == 8'd0);

  starlink_pss_sliding_correlator i_sliding_correlator (
    .i_clk                            (i_engine_clk),
    .i_reset                          (!i_engine_resetn),
    .i_coefficient_clear              (i_coefficient_clear),
    .i_coefficient_valid              (i_coefficient_valid),
    .o_coefficient_ready              (o_coefficient_ready),
    .i_coefficient_i                  (i_coefficient_i),
    .i_coefficient_q                  (i_coefficient_q),
    .i_coefficient_commit             (i_coefficient_commit),
    .o_coefficient_commit_ready       (o_coefficient_commit_ready),
    .i_coefficient_generation         (i_coefficient_generation),
    .o_coefficient_commit_accepted    (o_coefficient_commit_accepted),
    .o_coefficient_commit_rejected    (o_coefficient_commit_rejected),
    .o_active_coefficient_valid       (o_active_coefficient_valid),
    .o_active_coefficient_generation  (o_active_coefficient_generation),
    .o_active_coefficient_energy      (o_active_coefficient_energy),
    .o_shadow_coefficient_count       (o_shadow_coefficient_count),
    .o_configuration_idle             (o_configuration_idle),
    .i_sample_clear                   (1'b0),
    .i_sample_valid                   (bridge_engine_sample_valid),
    .o_sample_ready                   (bridge_engine_sample_ready),
    .i_sample_i                       (bridge_engine_sample_i),
    .i_sample_q                       (bridge_engine_sample_q),
    .i_sample_timestamp               (bridge_engine_sample_timestamp),
    .o_sample_count                   (correlator_sample_count),
    .i_start                          (correlator_start),
    .o_start_ready                    (correlator_start_ready),
    .o_busy                           (correlator_busy),
    .o_result_valid                   (o_result_valid),
    .i_result_ready                   (i_result_ready),
    .o_result_lag                     (o_result_lag),
    .o_result_timestamp               (o_result_timestamp),
    .o_result_coefficient_generation  (o_result_coefficient_generation),
    .o_result_c_re                    (o_result_c_re),
    .o_result_c_im                    (o_result_c_im),
    .o_result_ex                      (o_result_ex),
    .o_result_eh                      (o_result_eh),
    .o_result_saturation_events       (o_result_saturation_events),
    .o_done                           (correlator_done_unused),
    .o_bound_error_count              (o_bound_error_count)
  );

  // The bridge holds the active descriptor until it accepts the next job, and
  // the next descriptor cannot be accepted until the correlator has completed
  // the current result stream.  Avoid a redundant 160-bit metadata register.
  assign o_result_request_id = bridge_engine_request_id;
  assign o_result_center_index = bridge_engine_center_index;
  assign o_result_center_timestamp = bridge_engine_center_timestamp;

endmodule
