// Exact normalized match score; no IQ backpressure. One result per >=12 clocks.
// Uses the existing exact eight-iteration restoring divider at explicit width.
module starlink_coarse25_score #(
  parameter [35:0] COEFFICIENT_ENERGY = 36'd1073660387
) (
  input wire clk,
  input wire reset,
  input wire flush,
  input wire input_valid,
  input wire signed [36:0] input_re,
  input wire signed [36:0] input_im,
  input wire [35:0] input_energy,
  input wire [63:0] input_first_index,
  output wire score_valid,
  output wire [7:0] score,
  output wire [63:0] score_first_index,
  output wire denominator_zero,
  output reg overrun
);
  reg valid1, valid2;
  (* use_dsp = "yes" *) reg [73:0] square_re, square_im;
  (* use_dsp = "yes" *) reg [71:0] denominator1;
  reg [74:0] numerator2, denominator2;
  reg [63:0] index1, index2;
  wire divider_ready, divider_valid;
  wire abort_pipeline = reset || flush || overrun;
  assign score_valid = divider_valid && !abort_pipeline;
  always @(posedge clk) begin
    if (abort_pipeline) begin
      valid1 <= 0;
      valid2 <= 0;
      overrun <= 0;
    end else begin
      valid1 <= input_valid;
      valid2 <= valid1;
      overrun <= valid2 && !divider_ready;
      if (input_valid) begin
        square_re <= input_re * input_re;
        square_im <= input_im * input_im;
        denominator1 <= input_energy * COEFFICIENT_ENERGY;
        index1 <= input_first_index;
      end
      if (valid1) begin
        numerator2 <= {1'b0,square_re} + {1'b0,square_im};
        denominator2 <= {3'b0,denominator1};
        index2 <= index1;
      end
    end
  end
  starlink_pss_score_divider #(.RATIO_BITS(75), .SCORE_BITS(8)) divider (
    .clk(clk), .resetn(!reset), .flush(flush || overrun),
    .input_valid(valid2), .input_ready(divider_ready),
    .input_numerator(numerator2), .input_denominator(denominator2),
    .input_start_index(index2), .output_valid(divider_valid), .output_ready(1'b1),
    .output_score(score), .output_start_index(score_first_index),
    .output_denominator_zero(denominator_zero),
    .accepted_pulse(), .completed_pulse(), .zero_denominator_pulse(), .busy()
  );
endmodule
