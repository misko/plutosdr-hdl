// EXPERIMENT ONLY: six folded complex MAC lanes, 11 issue beats per 66 taps.
// External owner supplies ordered groups, first/last and raw first-tap tag.
// This arithmetic slice has no ADC interface, sample RAM, job validator,
// coefficient manager, energy normalization, CDC or visit-expiry scheduler.
`timescale 1ns/1ps
module starlink_pss_direct_mac6 (
  input wire clk, input wire resetn, input wire flush,
  input wire input_valid, output wire input_ready,
  input wire input_first, input wire input_last,
  input wire [95:0] input_i, input wire [95:0] input_q,
  input wire [95:0] coefficient_i, input wire [95:0] coefficient_q,
  input wire [63:0] input_timestamp,
  input wire [31:0] input_epoch,
  output reg output_valid, input wire output_ready,
  output reg signed [39:0] output_i, output reg signed [39:0] output_q,
  output reg [63:0] output_timestamp,
  output reg [31:0] output_epoch
);
  wire advance = !output_valid || output_ready;
  assign input_ready = resetn && !flush && advance;
  reg op_valid, op_first, op_last, mul_valid, mul_first, mul_last;
  reg tap_valid, tap_first, tap_last;
  reg [95:0] op_tag, mul_tag, tap_tag, accumulator_tag;
  reg [95:0] r0_tag, r1_tag, r2_tag;
  reg r0_valid, r1_valid, r2_valid;
  reg signed [15:0] xi [0:5], xq [0:5], hi [0:5], hq [0:5];
  reg signed [16:0] xs [0:5], hd [0:5];
  (* use_dsp = "yes" *) reg signed [31:0] m0 [0:5], m1 [0:5];
  (* use_dsp = "yes" *) reg signed [33:0] m2 [0:5];
  reg signed [34:0] tap_i [0:5], tap_q [0:5];
  reg signed [39:0] acc_i [0:5], acc_q [0:5];
  reg signed [39:0] r0_i [0:5], r0_q [0:5];
  reg signed [39:0] r1_i [0:2], r1_q [0:2];
  reg signed [39:0] r2_i [0:1], r2_q [0:1];
  integer lane;
  always @(posedge clk) begin
    if (!resetn || flush) begin
      op_valid <= 0; mul_valid <= 0; tap_valid <= 0;
      r0_valid <= 0; r1_valid <= 0; r2_valid <= 0;
      output_valid <= 0;
      // Data RAM/DSP registers do not need reset: all data use is valid gated.
    end else if (advance) begin
      op_valid <= input_valid;
      op_first <= input_first; op_last <= input_last;
      op_tag <= {input_epoch, input_timestamp};
      mul_valid <= op_valid; mul_first <= op_first; mul_last <= op_last;
      mul_tag <= op_tag;
      tap_valid <= mul_valid; tap_first <= mul_first; tap_last <= mul_last;
      tap_tag <= mul_tag;
      r0_valid <= tap_valid && tap_last;
      r1_valid <= r0_valid; r2_valid <= r1_valid; output_valid <= r2_valid;
      if (tap_valid && tap_first) accumulator_tag <= tap_tag;
      if (tap_valid && tap_last) r0_tag <= accumulator_tag;
      r1_tag <= r0_tag; r2_tag <= r1_tag;
      if (r2_valid) begin
        output_i <= r2_i[0] + r2_i[1];
        output_q <= r2_q[0] + r2_q[1];
        {output_epoch, output_timestamp} <= r2_tag;
      end
      for (lane = 0; lane < 6; lane = lane + 1) begin
        xi[lane] <= input_i[lane*16 +: 16];
        xq[lane] <= input_q[lane*16 +: 16];
        hi[lane] <= coefficient_i[lane*16 +: 16];
        hq[lane] <= coefficient_q[lane*16 +: 16];
        xs[lane] <= $signed(input_i[lane*16 +: 16]) +
                    $signed(input_q[lane*16 +: 16]);
        hd[lane] <= $signed(coefficient_i[lane*16 +: 16]) -
                    $signed(coefficient_q[lane*16 +: 16]);
        m0[lane] <= xi[lane] * hi[lane];
        m1[lane] <= xq[lane] * hq[lane];
        m2[lane] <= xs[lane] * hd[lane];
        tap_i[lane] <= {{3{m0[lane][31]}}, m0[lane]} +
                       {{3{m1[lane][31]}}, m1[lane]};
        tap_q[lane] <= {m2[lane][33], m2[lane]} -
                       {{3{m0[lane][31]}}, m0[lane]} +
                       {{3{m1[lane][31]}}, m1[lane]};
        if (tap_valid) begin
          acc_i[lane] <= (tap_first ? 40'sd0 : acc_i[lane]) + tap_i[lane];
          acc_q[lane] <= (tap_first ? 40'sd0 : acc_q[lane]) + tap_q[lane];
          if (tap_last) begin
            r0_i[lane] <= (tap_first ? 40'sd0 : acc_i[lane]) + tap_i[lane];
            r0_q[lane] <= (tap_first ? 40'sd0 : acc_q[lane]) + tap_q[lane];
          end
        end
      end
      for (lane = 0; lane < 3; lane = lane + 1) begin
        r1_i[lane] <= r0_i[2*lane] + r0_i[2*lane+1];
        r1_q[lane] <= r0_q[2*lane] + r0_q[2*lane+1];
      end
      r2_i[0] <= r1_i[0] + r1_i[1]; r2_i[1] <= r1_i[2];
      r2_q[0] <= r1_q[0] + r1_q[1]; r2_q[1] <= r1_q[2];
    end
  end
endmodule
