// SPDX-License-Identifier: GPL-2.0
//
// Deterministic 30-to-15 MS/s acquisition-only DDC.  The selected Starlink
// edge is translated by exactly +/-Fs/4 using sign/swap operations, then a
// fixed 15-tap Q1.15 half-band FIR rejects the opposite Nyquist image before
// decimation by two.  Sparse exact tracking and RX DMA do not use this path.
//
// The FIR has seven input-sample clocks of group delay.  Outputs are emitted
// only for odd absolute source indexes, so every result has the exact mapping
//   source_center_index = 2 * output_index
//   output_index = (newest_source_index - 7) / 2.
// A reset, flush, explicit gap, disable, or source-index discontinuity purges
// validity and requires fifteen new consecutive source samples.

`timescale 1ns/1ps

module starlink_pss_x2_ddc #(
  parameter integer EDGE_UPPER = 1
) (
  input  wire                 clk,
  input  wire                 resetn,
  input  wire                 enable,
  input  wire                 flush,

  input  wire                 input_valid,
  input  wire                 input_gap,
  input  wire signed [15:0]   input_i,
  input  wire signed [15:0]   input_q,
  input  wire [63:0]          input_index,

  output wire                 output_enable,
  output reg                  output_valid,
  output reg                  output_gap,
  output reg signed [15:0]    output_i,
  output reg signed [15:0]    output_q,
  output reg [63:0]           output_index,

  output reg [31:0]           accepted_sample_count,
  output reg [31:0]           emitted_sample_count,
  output reg [31:0]           discontinuity_count,
  output reg [31:0]           saturation_event_count
);

  localparam integer FILTER_TAPS = 15;
  localparam integer GROUP_DELAY_SAMPLES = 7;
  localparam signed [15:0] COEFFICIENT_0 = -16'sd572;
  localparam signed [15:0] COEFFICIENT_2 =  16'sd1260;
  localparam signed [15:0] COEFFICIENT_4 = -16'sd2923;
  localparam signed [15:0] COEFFICIENT_6 =  16'sd10235;

  generate
    if ((EDGE_UPPER != 0) && (EDGE_UPPER != 1)) begin : g_invalid_edge
      initial $fatal(1, "EDGE_UPPER must be zero or one");
    end
  endgenerate

  function automatic [31:0] add_saturating_32;
    input [31:0] value;
    input [1:0] increment;
    reg [32:0] sum;
    begin
      sum = {1'b0, value} + increment;
      add_saturating_32 = sum[32] ? 32'hffff_ffff : sum[31:0];
    end
  endfunction

  // Return {saturated, signed-CI16}.  Magnitude-domain convergent rounding
  // makes negative and positive halfway cases symmetric.
  function automatic [16:0] quantize_magnitude_q15;
    input negative;
    input [36:0] magnitude;
    reg [21:0] integer_magnitude;
    reg [22:0] rounded_magnitude;
    reg round_up;
    begin
      integer_magnitude = magnitude[36:15];
      round_up = (magnitude[14:0] > 15'h4000) ||
                 ((magnitude[14:0] == 15'h4000) &&
                  integer_magnitude[0]);
      rounded_magnitude = {1'b0, integer_magnitude} + round_up;
      if (negative) begin
        if (rounded_magnitude > 23'd32768)
          quantize_magnitude_q15 = {1'b1, 16'h8000};
        else
          quantize_magnitude_q15 = {
            1'b0, (~rounded_magnitude[15:0] + 1'b1)
          };
      end else begin
        if (rounded_magnitude > 23'd32767)
          quantize_magnitude_q15 = {1'b1, 16'h7fff};
        else
          quantize_magnitude_q15 = {1'b0, rounded_magnitude[15:0]};
      end
    end
  endfunction

  assign output_enable = enable && resetn && !flush;

  wire signed [16:0] extended_i = {input_i[15], input_i};
  wire signed [16:0] extended_q = {input_q[15], input_q};
  reg signed [16:0] mixed_i;
  reg signed [16:0] mixed_q;

  // Upper-edge acquisition moves +7.5 MHz to DC with exp(-j*pi*n/2).
  // Lower-edge acquisition uses the conjugate rotation.
  always @* begin
    case (input_index[1:0])
      2'd0: begin
        mixed_i = extended_i;
        mixed_q = extended_q;
      end
      2'd1: begin
        if (EDGE_UPPER) begin
          mixed_i = extended_q;
          mixed_q = -extended_i;
        end else begin
          mixed_i = -extended_q;
          mixed_q = extended_i;
        end
      end
      2'd2: begin
        mixed_i = -extended_i;
        mixed_q = -extended_q;
      end
      default: begin
        if (EDGE_UPPER) begin
          mixed_i = -extended_q;
          mixed_q = extended_i;
        end else begin
          mixed_i = extended_q;
          mixed_q = -extended_i;
        end
      end
    endcase
  end

  reg signed [16:0] delay_i [0:FILTER_TAPS-2];
  reg signed [16:0] delay_q [0:FILTER_TAPS-2];
  reg [3:0] history_count;
  reg stream_locked;
  reg [63:0] expected_input_index;
  reg gap_pending;

  wire source_contiguous = stream_locked && !input_gap &&
      (input_index == expected_input_index);
  wire filter_issue = input_valid && source_contiguous &&
      (history_count == FILTER_TAPS-1) && input_index[0];

  reg pair_valid;
  reg signed [17:0] pair_0_i;
  reg signed [17:0] pair_2_i;
  reg signed [17:0] pair_4_i;
  reg signed [17:0] pair_6_i;
  reg signed [16:0] pair_center_i;
  reg signed [17:0] pair_0_q;
  reg signed [17:0] pair_2_q;
  reg signed [17:0] pair_4_q;
  reg signed [17:0] pair_6_q;
  reg signed [16:0] pair_center_q;

  reg product_valid;
  (* use_dsp = "yes" *) reg signed [33:0] product_0_i;
  (* use_dsp = "yes" *) reg signed [33:0] product_2_i;
  (* use_dsp = "yes" *) reg signed [33:0] product_4_i;
  (* use_dsp = "yes" *) reg signed [33:0] product_6_i;
  reg signed [33:0] product_center_i;
  (* use_dsp = "yes" *) reg signed [33:0] product_0_q;
  (* use_dsp = "yes" *) reg signed [33:0] product_2_q;
  (* use_dsp = "yes" *) reg signed [33:0] product_4_q;
  (* use_dsp = "yes" *) reg signed [33:0] product_6_q;
  reg signed [33:0] product_center_q;

  reg accumulator_valid;
  reg signed [36:0] accumulator_i;
  reg signed [36:0] accumulator_q;

  reg magnitude_valid;
  reg magnitude_i_negative;
  reg magnitude_q_negative;
  reg [36:0] magnitude_i;
  reg [36:0] magnitude_q;

  wire [16:0] quantized_i = quantize_magnitude_q15(
      magnitude_i_negative, magnitude_i);
  wire [16:0] quantized_q = quantize_magnitude_q15(
      magnitude_q_negative, magnitude_q);
  reg quantized_valid;
  reg [16:0] quantized_i_register;
  reg [16:0] quantized_q_register;

  // A discontinuity forces fifteen new source samples before the next FIR
  // result can issue.  That interval is longer than this five-stage data
  // pipeline, so no old result can overlap the first result of a restarted
  // segment.  Retain the restart index once instead of transporting 64 bits
  // through every arithmetic stage.  Subsequent output indexes are exactly
  // consecutive by construction.
  reg restart_output_pending;
  reg [63:0] restart_output_index;

  // Keep arithmetic registers free of stage-specific clock enables.  Validity
  // is carried by the small control pipeline below, so values computed during
  // invalid clocks are explicitly don't-care.  This lets the 7-series packer
  // colocate the datapath registers efficiently on the constrained Zynq-7010.
  always @(posedge clk) begin
    pair_0_i <= $signed(mixed_i) + $signed(delay_i[13]);
    pair_2_i <= $signed(delay_i[1]) + $signed(delay_i[11]);
    pair_4_i <= $signed(delay_i[3]) + $signed(delay_i[9]);
    pair_6_i <= $signed(delay_i[5]) + $signed(delay_i[7]);
    pair_center_i <= delay_i[6];
    pair_0_q <= $signed(mixed_q) + $signed(delay_q[13]);
    pair_2_q <= $signed(delay_q[1]) + $signed(delay_q[11]);
    pair_4_q <= $signed(delay_q[3]) + $signed(delay_q[9]);
    pair_6_q <= $signed(delay_q[5]) + $signed(delay_q[7]);
    pair_center_q <= delay_q[6];

    product_0_i <= pair_0_i * COEFFICIENT_0;
    product_2_i <= pair_2_i * COEFFICIENT_2;
    product_4_i <= pair_4_i * COEFFICIENT_4;
    product_6_i <= pair_6_i * COEFFICIENT_6;
    product_center_i <= {
      {3{pair_center_i[16]}}, pair_center_i, 14'd0
    };
    product_0_q <= pair_0_q * COEFFICIENT_0;
    product_2_q <= pair_2_q * COEFFICIENT_2;
    product_4_q <= pair_4_q * COEFFICIENT_4;
    product_6_q <= pair_6_q * COEFFICIENT_6;
    product_center_q <= {
      {3{pair_center_q[16]}}, pair_center_q, 14'd0
    };

    accumulator_i <=
        {{3{product_0_i[33]}}, product_0_i} +
        {{3{product_2_i[33]}}, product_2_i} +
        {{3{product_4_i[33]}}, product_4_i} +
        {{3{product_6_i[33]}}, product_6_i} +
        {{3{product_center_i[33]}}, product_center_i};
    accumulator_q <=
        {{3{product_0_q[33]}}, product_0_q} +
        {{3{product_2_q[33]}}, product_2_q} +
        {{3{product_4_q[33]}}, product_4_q} +
        {{3{product_6_q[33]}}, product_6_q} +
        {{3{product_center_q[33]}}, product_center_q};

    magnitude_i_negative <= accumulator_i[36];
    magnitude_q_negative <= accumulator_q[36];
    magnitude_i <= accumulator_i[36] ?
        (~accumulator_i + 1'b1) : accumulator_i;
    magnitude_q <= accumulator_q[36] ?
        (~accumulator_q + 1'b1) : accumulator_q;

    quantized_i_register <= quantized_i;
    quantized_q_register <= quantized_q;
  end

  integer delay_index;
  always @(posedge clk) begin
    if (!resetn) begin
      output_valid <= 1'b0;
      output_gap <= 1'b0;
      output_i <= 16'sd0;
      output_q <= 16'sd0;
      output_index <= 64'd0;
      accepted_sample_count <= 32'd0;
      emitted_sample_count <= 32'd0;
      discontinuity_count <= 32'd0;
      saturation_event_count <= 32'd0;
      history_count <= 4'd0;
      stream_locked <= 1'b0;
      expected_input_index <= 64'd0;
      gap_pending <= 1'b1;
      pair_valid <= 1'b0;
      product_valid <= 1'b0;
      accumulator_valid <= 1'b0;
      magnitude_valid <= 1'b0;
      quantized_valid <= 1'b0;
      restart_output_pending <= 1'b0;
      restart_output_index <= 64'd0;
    end else if (flush || !enable) begin
      output_valid <= 1'b0;
      output_gap <= 1'b0;
      history_count <= 4'd0;
      stream_locked <= 1'b0;
      expected_input_index <= 64'd0;
      gap_pending <= 1'b1;
      pair_valid <= 1'b0;
      product_valid <= 1'b0;
      accumulator_valid <= 1'b0;
      magnitude_valid <= 1'b0;
      quantized_valid <= 1'b0;
      restart_output_pending <= 1'b0;
    end else begin
      output_valid <= quantized_valid;
      pair_valid <= 1'b0;
      product_valid <= pair_valid;
      accumulator_valid <= product_valid;
      magnitude_valid <= accumulator_valid;
      quantized_valid <= magnitude_valid;

      if (quantized_valid) begin
        output_gap <= restart_output_pending;
        output_i <= quantized_i_register[15:0];
        output_q <= quantized_q_register[15:0];
        if (restart_output_pending)
          output_index <= restart_output_index;
        else
          output_index <= output_index + 1'b1;
        restart_output_pending <= 1'b0;
        emitted_sample_count <= add_saturating_32(
            emitted_sample_count, 2'd1);
        saturation_event_count <= add_saturating_32(
            saturation_event_count,
            {1'b0, quantized_i_register[16]} +
            {1'b0, quantized_q_register[16]});
      end

      if (input_valid) begin
        accepted_sample_count <= add_saturating_32(
            accepted_sample_count, 2'd1);
        expected_input_index <= input_index + 1'b1;
        stream_locked <= 1'b1;

        for (delay_index = FILTER_TAPS-2; delay_index > 0;
             delay_index = delay_index - 1) begin
          delay_i[delay_index] <= delay_i[delay_index-1];
          delay_q[delay_index] <= delay_q[delay_index-1];
        end
        delay_i[0] <= mixed_i;
        delay_q[0] <= mixed_q;

        if (!source_contiguous) begin
          history_count <= 4'd1;
          gap_pending <= 1'b1;
          if (input_gap || stream_locked)
            discontinuity_count <= add_saturating_32(
                discontinuity_count, 2'd1);
        end else begin
          if (history_count < FILTER_TAPS-1)
            history_count <= history_count + 1'b1;

          if (filter_issue) begin
            pair_valid <= 1'b1;
            if (gap_pending) begin
              restart_output_pending <= 1'b1;
              restart_output_index <=
                  (input_index - GROUP_DELAY_SAMPLES) >> 1;
            end
            gap_pending <= 1'b0;
          end
        end
      end
    end
  end

endmodule
