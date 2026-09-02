// Composed IFFT-to-normalized-score path for the PSS acquisition engine.
//
// This source-only top qualifies overlap-save IFFT output, absorbs one dense
// 447-result burst, joins every result to its absolute-indexed energy, forms
// the exact exponent-aware ratio, and drains it through two ordered divider
// lanes.  The sample-energy cache and XFFT cores remain external.  Any framing,
// FIFO-capacity, or cache-identity error immediately quarantines the interfaces
// and latches path_fault. The external controller's explicit flush then clears
// every stage synchronously, retaining fault evidence until recovery begins.

`timescale 1ns/1ps

module starlink_pss_candidate_score_path #(
  parameter [30:0] COEFFICIENT_ENERGY = 31'd1073742825
) (
  input  wire                    clk,
  input  wire                    resetn,
  input  wire                    flush,

  input  wire                    ifft_valid,
  output wire                    ifft_ready,
  input  wire signed [23:0]      ifft_correlation_i,
  input  wire signed [23:0]      ifft_correlation_q,
  input  wire [8:0]              ifft_index,
  input  wire [4:0]              forward_exponent,
  input  wire [4:0]              inverse_exponent,
  input  wire [63:0]             block_start_index,
  input  wire                    ifft_last,

  output wire                    cache_lookup_valid,
  input  wire                    cache_lookup_ready,
  output wire [63:0]             cache_lookup_start_index,
  input  wire                    cache_output_valid,
  output wire                    cache_output_ready,
  input  wire [37:0]             cache_output_energy,
  input  wire [63:0]             cache_output_start_index,
  input  wire                    cache_output_found,

  output wire                    score_valid,
  input  wire                    score_ready,
  output wire [7:0]              score_value,
  output wire [63:0]             score_start_index,
  output wire                    score_denominator_zero,

  output reg                     path_fault,
  output reg                     ifft_protocol_fault,
  output reg                     fifo_overflow_fault,
  output reg                     energy_join_fault,
  output wire [9:0]              fifo_stored_count,
  output wire [9:0]              fifo_maximum_stored_count
);

  wire qualifier_valid;
  wire qualifier_ready;
  wire qualifier_input_ready;
  wire signed [23:0] qualifier_correlation_i;
  wire signed [23:0] qualifier_correlation_q;
  wire [4:0] qualifier_forward_exponent;
  wire [4:0] qualifier_inverse_exponent;
  wire [63:0] qualifier_start_index;
  wire qualifier_block_last;
  wire qualifier_fault;

  wire fifo_valid;
  wire fifo_ready;
  wire signed [23:0] fifo_correlation_i;
  wire signed [23:0] fifo_correlation_q;
  wire [4:0] fifo_forward_exponent;
  wire [4:0] fifo_inverse_exponent;
  wire [63:0] fifo_start_index;
  wire fifo_overflow_pulse;

  wire joined_valid;
  wire joined_ready;
  wire signed [23:0] joined_correlation_i;
  wire signed [23:0] joined_correlation_q;
  wire [37:0] joined_sample_energy;
  wire [4:0] joined_forward_exponent;
  wire [4:0] joined_inverse_exponent;
  wire [63:0] joined_start_index;
  wire join_fault;

  wire ratio_valid;
  wire ratio_ready;
  wire [68:0] ratio_numerator;
  wire [68:0] ratio_denominator;
  wire [63:0] ratio_start_index;
  wire lane_score_valid;
  wire fault_event;

  assign fault_event = qualifier_fault || fifo_overflow_pulse || join_fault;
  assign ifft_ready = qualifier_input_ready && !path_fault && !fault_event;
  assign score_valid = lane_score_valid && !path_fault && !fault_event;

  starlink_pss_ifft_qualifier qualifier (
    .clk                     (clk),
    .resetn                  (resetn),
    .flush                   (flush),
    .input_valid             (ifft_valid && !path_fault && !fault_event),
    .input_ready             (qualifier_input_ready),
    .input_correlation_i     (ifft_correlation_i),
    .input_correlation_q     (ifft_correlation_q),
    .input_ifft_index        (ifft_index),
    .input_forward_exponent  (forward_exponent),
    .input_inverse_exponent  (inverse_exponent),
    .input_block_start_index (block_start_index),
    .input_last              (ifft_last),
    .output_valid            (qualifier_valid),
    .output_ready            (qualifier_ready),
    .output_correlation_i    (qualifier_correlation_i),
    .output_correlation_q    (qualifier_correlation_q),
    .output_forward_exponent (qualifier_forward_exponent),
    .output_inverse_exponent (qualifier_inverse_exponent),
    .output_start_index      (qualifier_start_index),
    .output_block_last       (qualifier_block_last),
    .accepted_pulse          (),
    .discarded_prefix_pulse  (),
    .emitted_pulse           (),
    .sequence_error_pulse    (),
    .metadata_error_pulse    (),
    .protocol_fault          (qualifier_fault)
  );

  starlink_pss_raw_result_fifo result_fifo (
    .clk                     (clk),
    .resetn                  (resetn),
    .flush                   (flush),
    .input_valid             (qualifier_valid),
    .input_ready             (qualifier_ready),
    .input_correlation_i     (qualifier_correlation_i),
    .input_correlation_q     (qualifier_correlation_q),
    .input_forward_exponent  (qualifier_forward_exponent),
    .input_inverse_exponent  (qualifier_inverse_exponent),
    .input_start_index       (qualifier_start_index),
    .input_block_last        (qualifier_block_last),
    .output_valid            (fifo_valid),
    .output_ready            (fifo_ready),
    .output_correlation_i    (fifo_correlation_i),
    .output_correlation_q    (fifo_correlation_q),
    .output_forward_exponent (fifo_forward_exponent),
    .output_inverse_exponent (fifo_inverse_exponent),
    .output_start_index      (fifo_start_index),
    .output_block_last       (),
    .stored_count            (fifo_stored_count),
    .maximum_stored_count    (fifo_maximum_stored_count),
    .accepted_pulse          (),
    .emitted_pulse           (),
    .overflow_pulse          (fifo_overflow_pulse)
  );

  starlink_pss_energy_join energy_join (
    .clk                      (clk),
    .resetn                   (resetn),
    .flush                    (flush),
    .input_valid              (fifo_valid),
    .input_ready              (fifo_ready),
    .input_correlation_i      (fifo_correlation_i),
    .input_correlation_q      (fifo_correlation_q),
    .input_forward_exponent   (fifo_forward_exponent),
    .input_inverse_exponent   (fifo_inverse_exponent),
    .input_start_index        (fifo_start_index),
    .cache_lookup_valid       (cache_lookup_valid),
    .cache_lookup_ready       (cache_lookup_ready),
    .cache_lookup_start_index (cache_lookup_start_index),
    .cache_output_valid       (cache_output_valid),
    .cache_output_ready       (cache_output_ready),
    .cache_output_energy      (cache_output_energy),
    .cache_output_start_index (cache_output_start_index),
    .cache_output_found       (cache_output_found),
    .output_valid             (joined_valid),
    .output_ready             (joined_ready),
    .output_correlation_i     (joined_correlation_i),
    .output_correlation_q     (joined_correlation_q),
    .output_sample_energy     (joined_sample_energy),
    .output_forward_exponent  (joined_forward_exponent),
    .output_inverse_exponent  (joined_inverse_exponent),
    .output_start_index       (joined_start_index),
    .accepted_pulse           (),
    .joined_pulse             (),
    .cache_miss_pulse         (),
    .index_mismatch_pulse     (),
    .orphan_response_pulse    (),
    .protocol_fault           (join_fault)
  );

  starlink_pss_score_prepare #(
    .COEFFICIENT_ENERGY (COEFFICIENT_ENERGY)
  ) score_prepare (
    .clk                        (clk),
    .resetn                     (resetn),
    .flush                      (flush),
    .input_valid                (joined_valid),
    .input_ready                (joined_ready),
    .input_correlation_i        (joined_correlation_i),
    .input_correlation_q        (joined_correlation_q),
    .input_sample_energy        (joined_sample_energy),
    .input_forward_exponent     (joined_forward_exponent),
    .input_inverse_exponent     (joined_inverse_exponent),
    .input_start_index          (joined_start_index),
    .output_valid               (ratio_valid),
    .output_ready               (ratio_ready),
    .output_numerator           (ratio_numerator),
    .output_denominator         (ratio_denominator),
    .output_power_shift         (),
    .output_start_index         (ratio_start_index),
    .output_numerator_saturated (),
    .output_denominator_zero    (),
    .accepted_pulse             (),
    .completed_pulse            (),
    .numerator_saturation_pulse (),
    .denominator_zero_pulse     ()
  );

  starlink_pss_score_lanes score_lanes (
    .clk                     (clk),
    .resetn                  (resetn),
    .flush                   (flush),
    .input_valid             (ratio_valid),
    .input_ready             (ratio_ready),
    .input_numerator         (ratio_numerator),
    .input_denominator       (ratio_denominator),
    .input_start_index       (ratio_start_index),
    .output_valid            (lane_score_valid),
    .output_ready            (score_ready),
    .output_score            (score_value),
    .output_start_index      (score_start_index),
    .output_denominator_zero (score_denominator_zero),
    .accepted_pulse          (),
    .emitted_pulse           (),
    .lane_zero_busy          (),
    .lane_one_busy           (),
    .next_input_lane         (),
    .next_output_lane        ()
  );

  always @(posedge clk) begin
    if (!resetn || flush) begin
      path_fault <= 1'b0;
      ifft_protocol_fault <= 1'b0;
      fifo_overflow_fault <= 1'b0;
      energy_join_fault <= 1'b0;
    end else begin
      if (fault_event)
        path_fault <= 1'b1;
      if (qualifier_fault)
        ifft_protocol_fault <= 1'b1;
      if (fifo_overflow_pulse)
        fifo_overflow_fault <= 1'b1;
      if (join_fault)
        energy_join_fault <= 1'b1;
    end
  end

endmodule
