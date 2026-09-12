// One centered 2.5 MS/s coarse PSS detector. Host IQ is a separate input fanout.
module starlink_coarse25_detector #(
  parameter integer GROUPS = 29
) (
  input wire clk,
  input wire reset,
  input wire sample_valid,
  input wire signed [15:0] sample_i,
  input wire signed [15:0] sample_q,
  input wire [63:0] sample_index,
  output wire initializing,
  output wire fault,
  output wire candidate_valid,
  output wire detected,
  output wire [63:0] candidate_map_first_index,
  output wire [13:0] candidate_phase,
  output wire [14:0] candidate_peak,
  output wire [27:0] candidate_background_sum,
  output wire [42:0] candidate_background_sumsq,
  output wire [13:0] candidate_background_count
);
  wire score_valid, zero_energy, gap, mac_overrun, score_overrun, fold_fault;
  wire [7:0] score;
  wire [63:0] first;
  wire upstream_fault = gap || mac_overrun || score_overrun;
  assign fault = upstream_fault || fold_fault;
  starlink_coarse25_datapath arithmetic (
    .clk(clk), .reset(reset), .sample_valid(sample_valid), .sample_i(sample_i),
    .sample_q(sample_q), .sample_index(sample_index), .score_valid(score_valid),
    .score(score), .score_first_index(first), .denominator_zero(zero_energy),
    .gap(gap), .mac_overrun(mac_overrun), .score_overrun(score_overrun)
  );
  starlink_coarse25_fold #(.GROUPS(GROUPS)) fold (
    .clk(clk), .reset(reset), .flush(upstream_fault), .score_valid(score_valid),
    .score(score), .score_first_index(first), .initializing(initializing), .fault(fold_fault),
    .candidate_valid(candidate_valid), .detected(detected),
    .candidate_map_first_index(candidate_map_first_index), .candidate_phase(candidate_phase),
    .candidate_peak(candidate_peak), .candidate_background_sum(candidate_background_sum),
    .candidate_background_sumsq(candidate_background_sumsq),
    .candidate_background_count(candidate_background_count)
  );
endmodule
