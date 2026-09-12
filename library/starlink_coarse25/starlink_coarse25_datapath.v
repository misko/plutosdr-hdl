// Coarse correlation plus exact uint8 score. IQ transport is an independent fanout.
module starlink_coarse25_datapath (
  input wire clk,
  input wire reset,
  input wire sample_valid,
  input wire signed [15:0] sample_i,
  input wire signed [15:0] sample_q,
  input wire [63:0] sample_index,
  output wire score_valid,
  output wire [7:0] score,
  output wire [63:0] score_first_index,
  output wire denominator_zero,
  output wire gap,
  output wire mac_overrun,
  output wire score_overrun
);
  wire mac_valid;
  wire signed [36:0] re, im;
  wire [35:0] energy;
  wire [63:0] first;
  starlink_coarse25_mac mac (
    .clk(clk), .reset(reset), .sample_valid(sample_valid), .sample_i(sample_i),
    .sample_q(sample_q), .sample_index(sample_index), .result_valid(mac_valid),
    .result_re(re), .result_im(im), .result_energy(energy), .result_first_index(first),
    .gap(gap), .overrun(mac_overrun)
  );
  starlink_coarse25_score normalize (
    .clk(clk), .reset(reset), .flush(gap || mac_overrun), .input_valid(mac_valid),
    .input_re(re), .input_im(im), .input_energy(energy), .input_first_index(first),
    .score_valid(score_valid), .score(score), .score_first_index(score_first_index),
    .denominator_zero(denominator_zero), .overrun(score_overrun)
  );
endmodule
