// Exact four-iteration normalized-power score divider.
//
// Computes round_ties_even(255 * numerator / denominator), saturating at 255
// when numerator >= denominator and returning zero for a zero numerator or
// denominator. Two quotient bits are resolved per calculation clock. Every
// accepted item, including special cases, has the same four calculation
// cycles followed by one registered rounding cycle.

`timescale 1ns/1ps

module starlink_pss_score_divider_radix4 #(
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
  output reg [63:0]              output_start_index,
  output reg                     output_denominator_zero,

  output reg                     accepted_pulse,
  output reg                     completed_pulse,
  output reg                     zero_denominator_pulse,
  output reg                     busy
);

  localparam [SCORE_BITS-1:0] SCORE_MAX = {SCORE_BITS{1'b1}};

  reg [WORK_BITS-1:0] remainder;
  reg [WORK_BITS-1:0] shifted_denominator;
  reg [WORK_BITS-1:0] denominator_extended;
  reg [SCORE_BITS-1:0] quotient;
  reg [1:0] iteration;
  reg round_pending;
  reg special_case;
  reg [SCORE_BITS-1:0] special_score;
  reg special_denominator_zero;
  reg [63:0] pending_start_index;

  wire output_stage_ready;
  wire input_accept;
  wire [WORK_BITS-1:0] high_denominator;
  wire [WORK_BITS:0] high_difference;
  wire subtract_high;
  wire [WORK_BITS-1:0] high_remainder;
  wire [WORK_BITS:0] low_difference;
  wire subtract_low;
  wire [WORK_BITS-1:0] next_remainder;
  reg [SCORE_BITS-1:0] next_quotient;
  wire [WORK_BITS:0] doubled_remainder;
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

  // shifted_denominator represents the lower quotient bit in this radix-4
  // step. Comparing its double first resolves the adjacent higher bit; the
  // second comparison then resolves the lower bit from the residual.
  assign high_denominator = shifted_denominator << 1;
  assign high_difference = {1'b0, remainder} -
                           {1'b0, high_denominator};
  assign subtract_high = !high_difference[WORK_BITS];
  assign high_remainder = subtract_high ?
                          high_difference[WORK_BITS-1:0] : remainder;
  assign low_difference = {1'b0, high_remainder} -
                          {1'b0, shifted_denominator};
  assign subtract_low = !low_difference[WORK_BITS];
  assign next_remainder = subtract_low ?
                          low_difference[WORK_BITS-1:0] : high_remainder;

  always @(*) begin
    next_quotient = quotient;
    case (iteration)
      2'd3: begin
        next_quotient[7] = subtract_high;
        next_quotient[6] = subtract_low;
      end
      2'd2: begin
        next_quotient[5] = subtract_high;
        next_quotient[4] = subtract_low;
      end
      2'd1: begin
        next_quotient[3] = subtract_high;
        next_quotient[2] = subtract_low;
      end
      default: begin
        next_quotient[1] = subtract_high;
        next_quotient[0] = subtract_low;
      end
    endcase
  end

  assign doubled_remainder = {remainder, 1'b0};
  assign round_up = doubled_remainder > denominator_extended ||
    (doubled_remainder == denominator_extended && quotient[0]);
  assign rounded_quotient = {1'b0, quotient} + round_up;

  assign input_numerator_extended =
    {{SCORE_BITS{1'b0}}, input_numerator};
  assign input_denominator_extended =
    {{SCORE_BITS{1'b0}}, input_denominator};
  assign input_scaled_by_score_max =
    {input_numerator, {SCORE_BITS{1'b0}}} - input_numerator_extended;

  always @(posedge clk) begin
    if (!resetn || flush) begin
      remainder <= 0;
      shifted_denominator <= 0;
      denominator_extended <= 0;
      quotient <= 0;
      iteration <= 0;
      round_pending <= 1'b0;
      special_case <= 1'b0;
      special_score <= 0;
      special_denominator_zero <= 1'b0;
      pending_start_index <= 0;
      output_valid <= 1'b0;
      output_score <= 0;
      output_start_index <= 0;
      output_denominator_zero <= 1'b0;
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
                               (SCORE_BITS - 2);
        denominator_extended <= input_denominator_extended;
        quotient <= 0;
        iteration <= (SCORE_BITS / 2) - 1;
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
        shifted_denominator <= shifted_denominator >> 2;
        if (iteration == 0) begin
          busy <= 1'b0;
          round_pending <= 1'b1;
        end else begin
          iteration <= iteration - 1'b1;
        end
      end else if (round_pending) begin
        output_valid <= 1'b1;
        output_score <= special_case ?
                        special_score : rounded_quotient[SCORE_BITS-1:0];
        output_start_index <= pending_start_index;
        output_denominator_zero <= special_denominator_zero;
        completed_pulse <= 1'b1;
        zero_denominator_pulse <= special_denominator_zero;
        round_pending <= 1'b0;
      end
    end
  end

endmodule
