// SPDX-License-Identifier: GPL-2.0
//
// Complete Stage-15 TRACK_ONE composition.  The existing tracking core remains
// the raw 65-tuple trace implementation and independent arithmetic evidence.
// This wrapper applies the exact normalized winner reducer over the frozen
// oracle aperture (-30..+30) and publishes one versioned result packet through
// the atomic dual-clock result store.  The raw trace retains its historical
// -32..+32 evidence aperture; the two tuples at each edge are consumed but are
// deliberately excluded from TRACK_ONE winner selection.

`timescale 1ns/1ps

module starlink_pss_reduced_tracking_core #(
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

  output wire                o_result_available,
  output wire                o_result_bank,
  input  wire          [4:0] i_result_word_index,
  input  wire                i_result_word_read,
  output wire                o_result_word_valid,
  output wire         [31:0] o_result_word_data,
  input  wire                i_result_release,

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
  output wire         [31:0] o_correlator_bound_error_count,

  output wire         [31:0] o_reducer_processed_job_count,
  output wire         [31:0] o_reducer_emitted_result_count,
  output wire         [31:0] o_reducer_invalid_tuple_count,
  output wire         [31:0] o_reducer_bound_error_count,
  output wire         [31:0] o_reducer_protocol_error_count,

  output wire          [1:0] o_result_bank_free,
  output wire         [31:0] o_result_published_count,
  output wire         [31:0] o_result_overrun_count,
  output wire         [31:0] o_result_consumed_count
);

  wire raw_result_valid;
  wire raw_result_ready;
  wire [31:0] raw_result_request_id;
  wire [63:0] raw_result_center_index;
  wire [63:0] raw_result_center_timestamp;
  wire signed [6:0] raw_result_lag;
  wire [63:0] raw_result_timestamp;
  wire [31:0] raw_result_coefficient_generation;
  wire signed [47:0] raw_result_c_re;
  wire signed [47:0] raw_result_c_im;
  wire signed [47:0] raw_result_ex;
  wire signed [47:0] raw_result_eh;
  wire [8:0] raw_result_saturation_events;
  localparam signed [6:0] TRACK_FIRST_LAG = -7'sd30;
  localparam signed [6:0] TRACK_LAST_LAG = 7'sd30;
  wire raw_result_in_track_aperture =
      (raw_result_lag >= TRACK_FIRST_LAG) &&
      (raw_result_lag <= TRACK_LAST_LAG);
  wire reducer_tuple_ready;

  // Out-of-aperture raw trace tuples are drained without entering the reducer.
  // In-aperture tuples preserve ordinary ready/valid backpressure.
  assign raw_result_ready =
      !raw_result_in_track_aperture || reducer_tuple_ready;

  starlink_pss_tracking_core #(
    .COMMAND_FIFO_ADDRESS_WIDTH (COMMAND_FIFO_ADDRESS_WIDTH),
    .MINIMUM_LEAD_SAMPLES       (MINIMUM_LEAD_SAMPLES)
  ) i_raw_tracking_core (
    .i_control_clk                     (i_control_clk),
    .i_sample_clk                      (i_sample_clk),
    .i_engine_clk                      (i_engine_clk),
    .i_control_resetn                  (i_control_resetn),
    .i_sample_resetn                   (i_sample_resetn),
    .i_engine_resetn                   (i_engine_resetn),
    .i_candidate_submit                (i_candidate_submit),
    .i_candidate_request_id            (i_candidate_request_id),
    .i_candidate_center_index          (i_candidate_center_index),
    .i_candidate_center_timestamp      (i_candidate_center_timestamp),
    .o_candidate_submit_ready          (o_candidate_submit_ready),
    .o_candidate_submit_accepted       (o_candidate_submit_accepted),
    .o_candidate_queue_room            (o_candidate_queue_room),
    .o_queue_overrun_count             (o_queue_overrun_count),
    .i_sample_enable                   (i_sample_enable),
    .i_sample_valid                    (i_sample_valid),
    .i_sample_index                    (i_sample_index),
    .i_sample_timestamp                (i_sample_timestamp),
    .i_sample_i                        (i_sample_i),
    .i_sample_q                        (i_sample_q),
    .i_coefficient_clear               (i_coefficient_clear),
    .i_coefficient_valid               (i_coefficient_valid),
    .o_coefficient_ready               (o_coefficient_ready),
    .i_coefficient_i                   (i_coefficient_i),
    .i_coefficient_q                   (i_coefficient_q),
    .i_coefficient_commit              (i_coefficient_commit),
    .o_coefficient_commit_ready        (o_coefficient_commit_ready),
    .i_coefficient_generation          (i_coefficient_generation),
    .o_coefficient_commit_accepted     (o_coefficient_commit_accepted),
    .o_coefficient_commit_rejected     (o_coefficient_commit_rejected),
    .o_active_coefficient_valid        (o_active_coefficient_valid),
    .o_active_coefficient_generation   (o_active_coefficient_generation),
    .o_active_coefficient_energy       (o_active_coefficient_energy),
    .o_shadow_coefficient_count        (o_shadow_coefficient_count),
    .o_configuration_idle              (o_configuration_idle),
    .o_result_valid                    (raw_result_valid),
    .i_result_ready                    (raw_result_ready),
    .o_result_request_id               (raw_result_request_id),
    .o_result_center_index             (raw_result_center_index),
    .o_result_center_timestamp         (raw_result_center_timestamp),
    .o_result_lag                      (raw_result_lag),
    .o_result_timestamp                (raw_result_timestamp),
    .o_result_coefficient_generation   (raw_result_coefficient_generation),
    .o_result_c_re                     (raw_result_c_re),
    .o_result_c_im                     (raw_result_c_im),
    .o_result_ex                       (raw_result_ex),
    .o_result_eh                       (raw_result_eh),
    .o_result_saturation_events        (raw_result_saturation_events),
    .o_candidate_pending               (o_candidate_pending),
    .o_capture_active                  (o_capture_active),
    .o_admitted_count                  (o_admitted_count),
    .o_completed_capture_count         (o_completed_capture_count),
    .o_rejected_count                  (o_rejected_count),
    .o_late_count                      (o_late_count),
    .o_duplicate_count                 (o_duplicate_count),
    .o_overlap_count                   (o_overlap_count),
    .o_aborted_count                   (o_aborted_count),
    .o_valid_gap_abort_count           (o_valid_gap_abort_count),
    .o_index_jump_abort_count          (o_index_jump_abort_count),
    .o_timestamp_abort_count           (o_timestamp_abort_count),
    .o_capture_bank_free               (o_capture_bank_free),
    .o_capture_published_count         (o_capture_published_count),
    .o_capture_abort_discard_count     (o_capture_abort_discard_count),
    .o_capture_buffer_overrun_count    (o_capture_buffer_overrun_count),
    .o_capture_protocol_error_count    (o_capture_protocol_error_count),
    .o_engine_consumed_count           (o_engine_consumed_count),
    .o_bound_error_count               (o_correlator_bound_error_count)
  );

  wire reduced_result_valid;
  wire reduced_result_ready;
  wire reduced_result_score_valid;
  wire reduced_result_includes_eh;
  wire [31:0] reduced_result_request_id;
  wire [63:0] reduced_result_center_index;
  wire [63:0] reduced_result_center_timestamp;
  wire signed [6:0] reduced_result_lag;
  wire [63:0] reduced_result_timestamp;
  wire [31:0] reduced_result_coefficient_generation;
  wire signed [47:0] reduced_result_c_re;
  wire signed [47:0] reduced_result_c_im;
  wire signed [47:0] reduced_result_ex;
  wire signed [47:0] reduced_result_eh;
  wire [8:0] reduced_result_saturation_events;
  wire [76:0] reduced_result_score_numerator;
  wire [68:0] reduced_result_score_denominator;

  starlink_pss_exact_reducer i_exact_reducer (
    .i_clk                            (i_engine_clk),
    .i_reset                          (!i_engine_resetn),
    .i_tuple_valid                    (raw_result_valid &&
                                       raw_result_in_track_aperture),
    .o_tuple_ready                    (reducer_tuple_ready),
    .i_tuple_first                    (raw_result_lag == TRACK_FIRST_LAG),
    .i_tuple_last                     (raw_result_lag == TRACK_LAST_LAG),
    .i_include_eh                     (1'b0),
    .i_request_id                     (raw_result_request_id),
    .i_center_index                   (raw_result_center_index),
    .i_center_timestamp               (raw_result_center_timestamp),
    .i_lag                            (raw_result_lag),
    .i_timestamp                      (raw_result_timestamp),
    .i_coefficient_generation         (raw_result_coefficient_generation),
    .i_c_re                           (raw_result_c_re),
    .i_c_im                           (raw_result_c_im),
    .i_ex                             (raw_result_ex),
    .i_eh                             (raw_result_eh),
    .i_saturation_events              (raw_result_saturation_events),
    .o_result_valid                   (reduced_result_valid),
    .i_result_ready                   (reduced_result_ready),
    .o_result_score_valid             (reduced_result_score_valid),
    .o_result_includes_eh             (reduced_result_includes_eh),
    .o_result_request_id              (reduced_result_request_id),
    .o_result_center_index            (reduced_result_center_index),
    .o_result_center_timestamp        (reduced_result_center_timestamp),
    .o_result_lag                     (reduced_result_lag),
    .o_result_timestamp               (reduced_result_timestamp),
    .o_result_coefficient_generation  (reduced_result_coefficient_generation),
    .o_result_c_re                    (reduced_result_c_re),
    .o_result_c_im                    (reduced_result_c_im),
    .o_result_ex                      (reduced_result_ex),
    .o_result_eh                      (reduced_result_eh),
    .o_result_saturation_events       (reduced_result_saturation_events),
    .o_result_score_numerator         (reduced_result_score_numerator),
    .o_result_score_denominator       (reduced_result_score_denominator),
    .o_processed_job_count            (o_reducer_processed_job_count),
    .o_emitted_result_count           (o_reducer_emitted_result_count),
    .o_invalid_tuple_count            (o_reducer_invalid_tuple_count),
    .o_bound_error_count              (o_reducer_bound_error_count),
    .o_protocol_error_count           (o_reducer_protocol_error_count)
  );

  starlink_pss_result_store i_result_store (
    .i_engine_clk                       (i_engine_clk),
    .i_engine_resetn                    (i_engine_resetn),
    .i_result_valid                     (reduced_result_valid),
    .o_result_ready                     (reduced_result_ready),
    .i_result_score_valid               (reduced_result_score_valid),
    .i_result_includes_eh               (reduced_result_includes_eh),
    .i_result_request_id                (reduced_result_request_id),
    .i_result_center_index              (reduced_result_center_index),
    .i_result_center_timestamp          (reduced_result_center_timestamp),
    .i_result_lag                       (reduced_result_lag),
    .i_result_timestamp                 (reduced_result_timestamp),
    .i_result_coefficient_generation    (reduced_result_coefficient_generation),
    .i_result_c_re                      (reduced_result_c_re),
    .i_result_c_im                      (reduced_result_c_im),
    .i_result_ex                        (reduced_result_ex),
    .i_result_eh                        (reduced_result_eh),
    .i_result_saturation_events         (reduced_result_saturation_events),
    .i_result_score_numerator           (reduced_result_score_numerator),
    .i_result_score_denominator         (reduced_result_score_denominator),
    .o_result_bank_free                 (o_result_bank_free),
    .o_result_published_count           (o_result_published_count),
    .o_result_overrun_count             (o_result_overrun_count),
    .i_control_clk                      (i_control_clk),
    .i_control_resetn                   (i_control_resetn),
    .o_control_result_available         (o_result_available),
    .o_control_result_bank              (o_result_bank),
    .i_control_word_index               (i_result_word_index),
    .i_control_word_read                (i_result_word_read),
    .o_control_word_valid               (o_result_word_valid),
    .o_control_word_data                (o_result_word_data),
    .i_control_result_release           (i_result_release),
    .o_control_consumed_count           (o_result_consumed_count)
  );

endmodule
