// One-RX loss-aware crossing only. No FFT, native tracker, or rate conversion.
module starlink_coarse25_ingress (
  input wire sample_clk,
  input wire sample_reset,
  input wire sample_strobe,
  input wire signed [15:0] sample_i,
  input wire signed [15:0] sample_q,
  input wire [63:0] sample_index,
  input wire calc_clk,
  input wire calc_resetn,
  output wire canonical_valid,
  output wire canonical_gap,
  output wire canonical_flush,
  output wire signed [15:0] canonical_i,
  output wire signed [15:0] canonical_q,
  output wire [63:0] canonical_index
);
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *) reg [1:0] sample_reset_release;
  always @(posedge sample_clk or posedge sample_reset) begin
    if (sample_reset) sample_reset_release <= 0;
    else sample_reset_release <= {sample_reset_release[0], 1'b1};
  end
  wire gap, overflow;
  assign canonical_gap = gap || overflow;
  assign canonical_flush = 1'b0;
  starlink_pss_sample_cdc #(.FIFO_ADDRESS_WIDTH(7)) ingress (
    .source_clk(sample_clk), .source_resetn(sample_reset_release[1]),
    .source_sample_valid(sample_strobe), .source_sample_gap(1'b0),
    .source_sample_i(sample_i), .source_sample_q(sample_q), .source_sample_index(sample_index),
    .source_fifo_full(), .acquisition_clk(calc_clk), .acquisition_resetn(calc_resetn),
    .acquisition_sample_valid(canonical_valid), .acquisition_sample_gap(gap),
    .acquisition_sample_i(canonical_i), .acquisition_sample_q(canonical_q),
    .acquisition_sample_index(canonical_index), .dropped_sample_count(),
    .overflow_sticky(overflow), .fifo_level(), .maximum_fifo_level()
  );
endmodule
