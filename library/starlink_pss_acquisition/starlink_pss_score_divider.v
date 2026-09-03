// Exact eight-iteration normalized-power score divider.
//
// Computes round_ties_even(255 * numerator / denominator), saturating at 255
// when numerator >= denominator and returning zero for a zero numerator or
// denominator. Every accepted item, including special cases, performs eight
// restoring iterations followed by one registered ties-to-even rounding cycle.

`timescale 1ns/1ps

module starlink_pss_score_divider #(
  parameter integer RATIO_BITS = 69,
  parameter integer SCORE_BITS = 8,
  parameter integer WORK_BITS = RATIO_BITS + SCORE_BITS
) (
  input  wire                    clk,
  input  wire                    resetn,
  input  wire                    flush,

  input  wire                    input_valid,
  output wire                    input_ready,
  input  wire [RATIO_BITS-1:0]   input_numerator,
  input  wire [RATIO_BITS-1:0]   input_denominator,
  input  wire [63:0]             input_start_index,

  output reg                     output_valid,
  input  wire                    output_ready,
  output reg [SCORE_BITS-1:0]    output_score,
  output wire [63:0]             output_start_index,
  output wire                    output_denominator_zero,

  output reg                     accepted_pulse,
  output reg                     completed_pulse,
  output reg                     zero_denominator_pulse,
  output reg                     busy
);

  localparam [SCORE_BITS-1:0] SCORE_MAX = {SCORE_BITS{1'b1}};

  reg [WORK_BITS-1:0] remainder;
  reg [WORK_BITS-1:0] shifted_denominator;
  reg [SCORE_BITS-1:0] quotient;
  reg [2:0] iteration;
  reg round_pending;
  reg special_case;
  reg [SCORE_BITS-1:0] special_score;
  reg special_denominator_zero;
  reg [63:0] pending_start_index;

  wire output_stage_ready;
  wire input_accept;
  wire [WORK_BITS:0] difference;
  wire subtract_step;
  wire [WORK_BITS-1:0] next_remainder;
  wire [SCORE_BITS-1:0] next_quotient;
  wire [WORK_BITS-1:0] doubled_remainder;
  wire round_up;
  wire [SCORE_BITS:0] rounded_quotient;
  wire [WORK_BITS-1:0] input_numerator_extended;
  wire [WORK_BITS-1:0] input_denominator_extended;
  (* use_dsp = "yes" *) wire [WORK_BITS-1:0]
    input_scaled_by_score_max;

  assign output_stage_ready = !output_valid || output_ready;
  assign input_ready = resetn && !flush && !busy && !round_pending &&
                       output_stage_ready;
  assign input_accept = input_valid && input_ready;

  // One extended subtraction supplies both the comparison sign and the
  // accepted difference.  This prevents synthesis from constructing a
  // separate wide comparator beside the restoring subtractor.
  assign difference = {1'b0, remainder} -
                      {1'b0, shifted_denominator};
  assign subtract_step = !difference[WORK_BITS];
  assign next_remainder = subtract_step ?
                          difference[WORK_BITS-1:0] : remainder;
  assign next_quotient = subtract_step ?
                         quotient | ({{(SCORE_BITS-1){1'b0}}, 1'b1}
                                     << iteration) : quotient;
  assign doubled_remainder = remainder << 1;
  // After the final iteration, shifted_denominator is deliberately held at
  // the original unshifted denominator for the registered rounding cycle.
  assign round_up = doubled_remainder > shifted_denominator ||
    (doubled_remainder == shifted_denominator && quotient[0]);
  assign rounded_quotient = {1'b0, quotient} + round_up;

  assign input_numerator_extended =
    {{SCORE_BITS{1'b0}}, input_numerator};
  assign input_denominator_extended =
    {{SCORE_BITS{1'b0}}, input_denominator};
  assign input_scaled_by_score_max =
    {input_numerator, {SCORE_BITS{1'b0}}} - input_numerator_extended;

  // The pending metadata cannot be replaced while output_valid is stalled.
  // Reuse it directly as the output stage instead of duplicating 64 index bits
  // and the denominator-zero flag in a second bank of registers.
  assign output_start_index = pending_start_index;
  assign output_denominator_zero = special_denominator_zero;

  always @(posedge clk) begin
    if (!resetn || flush) begin
      remainder <= 0;
      shifted_denominator <= 0;
      quotient <= 0;
      iteration <= 0;
      round_pending <= 1'b0;
      special_case <= 1'b0;
      special_score <= 0;
      special_denominator_zero <= 1'b0;
      pending_start_index <= 0;
      output_valid <= 1'b0;
      output_score <= 0;
      accepted_pulse <= 1'b0;
      completed_pulse <= 1'b0;
      zero_denominator_pulse <= 1'b0;
      busy <= 1'b0;
    end else begin
      accepted_pulse <= 1'b0;
      completed_pulse <= 1'b0;
      zero_denominator_pulse <= 1'b0;

      if (output_valid && output_ready)
        output_valid <= 1'b0;

      if (input_accept) begin
        remainder <= input_scaled_by_score_max;
        shifted_denominator <= input_denominator_extended <<
                               (SCORE_BITS - 1);
        quotient <= 0;
        iteration <= SCORE_BITS - 1;
        special_case <= input_numerator == 0 ||
                        input_denominator == 0 ||
                        input_numerator >= input_denominator;
        special_score <= (input_numerator != 0 &&
                          input_denominator != 0 &&
                          input_numerator >= input_denominator) ?
                         SCORE_MAX : 0;
        special_denominator_zero <= input_denominator == 0;
        pending_start_index <= input_start_index;
        accepted_pulse <= 1'b1;
        busy <= 1'b1;
      end else if (busy) begin
        remainder <= next_remainder;
        quotient <= next_quotient;
        if (iteration == 0) begin
          busy <= 1'b0;
          round_pending <= 1'b1;
        end else begin
          shifted_denominator <= shifted_denominator >> 1;
          iteration <= iteration - 1'b1;
        end
      end else if (round_pending) begin
        output_valid <= 1'b1;
        output_score <= special_case ?
                        special_score : rounded_quotient[SCORE_BITS-1:0];
        completed_pulse <= 1'b1;
        zero_denominator_pulse <= special_denominator_zero;
        round_pending <= 1'b0;
      end
    end
  end

endmodule
