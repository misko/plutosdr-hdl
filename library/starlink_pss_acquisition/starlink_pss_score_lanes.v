// Ordered two-lane wrapper for the exact normalized-power score divider.
//
// Consecutive inputs alternate between identical fixed-latency lanes.  Output
// selection alternates independently and only advances on a completed output
// handshake, so arbitrary downstream stalls cannot reorder candidate indexes.

`timescale 1ns/1ps

module starlink_pss_score_lanes #(
  parameter integer RATIO_BITS = 69,
  parameter integer SCORE_BITS = 8
) (
  input  wire                    clk,
  input  wire                    resetn,
  input  wire                    flush,

  input  wire                    input_valid,
  output wire                    input_ready,
  input  wire [RATIO_BITS-1:0]   input_numerator,
  input  wire [RATIO_BITS-1:0]   input_denominator,
  input  wire [63:0]             input_start_index,

  output wire                    output_valid,
  input  wire                    output_ready,
  output wire [SCORE_BITS-1:0]   output_score,
  output wire [63:0]             output_start_index,
  output wire                    output_denominator_zero,

  output reg                     accepted_pulse,
  output reg                     emitted_pulse,
  output wire                    lane_zero_busy,
  output wire                    lane_one_busy,
  output wire                    next_input_lane,
  output wire                    next_output_lane
);

  reg input_lane_select;
  reg output_lane_select;

  wire lane_zero_input_valid;
  wire lane_zero_input_ready;
  wire lane_zero_output_valid;
  wire lane_zero_output_ready;
  wire [SCORE_BITS-1:0] lane_zero_output_score;
  wire [63:0] lane_zero_output_start_index;
  wire lane_zero_output_denominator_zero;

  wire lane_one_input_valid;
  wire lane_one_input_ready;
  wire lane_one_output_valid;
  wire lane_one_output_ready;
  wire [SCORE_BITS-1:0] lane_one_output_score;
  wire [63:0] lane_one_output_start_index;
  wire lane_one_output_denominator_zero;

  wire input_accept;
  wire output_accept;

  assign lane_zero_input_valid = input_valid && !input_lane_select;
  assign lane_one_input_valid = input_valid && input_lane_select;
  assign input_ready = resetn && !flush &&
                       (input_lane_select ? lane_one_input_ready :
                                            lane_zero_input_ready);
  assign input_accept = input_valid && input_ready;

  assign output_valid = output_lane_select ? lane_one_output_valid :
                                             lane_zero_output_valid;
  assign output_score = output_lane_select ? lane_one_output_score :
                                             lane_zero_output_score;
  assign output_start_index = output_lane_select ?
                              lane_one_output_start_index :
                              lane_zero_output_start_index;
  assign output_denominator_zero = output_lane_select ?
                                   lane_one_output_denominator_zero :
                                   lane_zero_output_denominator_zero;
  assign lane_zero_output_ready = !output_lane_select && output_ready;
  assign lane_one_output_ready = output_lane_select && output_ready;
  assign output_accept = output_valid && output_ready;
  assign next_input_lane = input_lane_select;
  assign next_output_lane = output_lane_select;

  starlink_pss_score_divider #(
    .RATIO_BITS (RATIO_BITS),
    .SCORE_BITS (SCORE_BITS)
  ) lane_zero (
    .clk                      (clk),
    .resetn                   (resetn),
    .flush                    (flush),
    .input_valid              (lane_zero_input_valid),
    .input_ready              (lane_zero_input_ready),
    .input_numerator          (input_numerator),
    .input_denominator        (input_denominator),
    .input_start_index        (input_start_index),
    .output_valid             (lane_zero_output_valid),
    .output_ready             (lane_zero_output_ready),
    .output_score             (lane_zero_output_score),
    .output_start_index       (lane_zero_output_start_index),
    .output_denominator_zero  (lane_zero_output_denominator_zero),
    .accepted_pulse           (),
    .completed_pulse          (),
    .zero_denominator_pulse   (),
    .busy                     (lane_zero_busy)
  );

  starlink_pss_score_divider #(
    .RATIO_BITS (RATIO_BITS),
    .SCORE_BITS (SCORE_BITS)
  ) lane_one (
    .clk                      (clk),
    .resetn                   (resetn),
    .flush                    (flush),
    .input_valid              (lane_one_input_valid),
    .input_ready              (lane_one_input_ready),
    .input_numerator          (input_numerator),
    .input_denominator        (input_denominator),
    .input_start_index        (input_start_index),
    .output_valid             (lane_one_output_valid),
    .output_ready             (lane_one_output_ready),
    .output_score             (lane_one_output_score),
    .output_start_index       (lane_one_output_start_index),
    .output_denominator_zero  (lane_one_output_denominator_zero),
    .accepted_pulse           (),
    .completed_pulse          (),
    .zero_denominator_pulse   (),
    .busy                     (lane_one_busy)
  );

  always @(posedge clk) begin
    if (!resetn || flush) begin
      input_lane_select <= 1'b0;
      output_lane_select <= 1'b0;
      accepted_pulse <= 1'b0;
      emitted_pulse <= 1'b0;
    end else begin
      accepted_pulse <= input_accept;
      emitted_pulse <= output_accept;
      if (input_accept)
        input_lane_select <= !input_lane_select;
      if (output_accept)
        output_lane_select <= !output_lane_select;
    end
  end

endmodule
