// SPDX-License-Identifier: GPL-2.0
// 15 -> 7.5 MS/s pilot halfband. Nine folded terms on two shared DSP MACs.
// Input pacing must provide >=13 clocks between successive even-index jobs.
`timescale 1ns/1ps
module starlink_pilot_halfband2 #(
  parameter COEFFICIENT_FILE = "pilot_halfband2_q17.mem"
) (
  input wire clk,
  input wire resetn,
  input wire flush,
  input wire input_valid,
  input wire signed [15:0] input_i,
  input wire signed [15:0] input_q,
  input wire [63:0] input_index,
  input wire [1:0] input_phase,
  input wire input_support_valid,
  output reg output_valid,
  output reg signed [15:0] output_i,
  output reg signed [15:0] output_q,
  output reg [63:0] output_index,
  output reg [1:0] output_phase,
  output reg output_support_valid,
  output reg [1:0] output_saturations,
  output reg sticky_overrun,
  output reg halted
);
  reg signed [15:0] history_i [0:29];
  reg signed [15:0] history_q [0:29];
  reg [4:0] history_count;
  reg [4:0] support_count;
  reg signed [16:0] snapshot_i [0:8];
  reg signed [16:0] snapshot_q [0:8];
  (* rom_style = "distributed" *) reg signed [17:0] coefficient [0:8];
  initial $readmemh(COEFFICIENT_FILE, coefficient);
  reg busy, issuing;
  reg [3:0] row;
  reg [63:0] job_index;
  reg [1:0] job_phase;
  reg job_support;
  wire wanted = input_valid && !input_index[0];
  wire overrun = wanted && busy;
  wire run = resetn && !flush && !halted && !overrun;
  wire start = run && wanted;
  wire issue = run && issuing;

  genvar term;
  generate for (term = 0; term < 8; term = term + 1) begin : g_pair
    wire signed [15:0] a_i;
    wire signed [15:0] a_q;
    wire signed [15:0] b_i = history_count >= (30 - 2*term) ? history_i[29 - 2*term] : 16'sd0;
    wire signed [15:0] b_q = history_count >= (30 - 2*term) ? history_q[29 - 2*term] : 16'sd0;
    if (term == 0) begin : g_current
      assign a_i = input_i;
      assign a_q = input_q;
    end else begin : g_delayed
      assign a_i = history_count >= 2*term ? history_i[2*term-1] : 16'sd0;
      assign a_q = history_count >= 2*term ? history_q[2*term-1] : 16'sd0;
    end
    always @(posedge clk) begin
      if (start) begin
        snapshot_i[term] <= $signed({a_i[15], a_i}) + $signed({b_i[15], b_i});
        snapshot_q[term] <= $signed({a_q[15], a_q}) + $signed({b_q[15], b_q});
      end
    end
  end endgenerate

  integer h;
  always @(posedge clk) begin
    if (run && input_valid) begin
      history_i[0] <= input_i;
      history_q[0] <= input_q;
      for (h = 1; h < 30; h = h + 1) begin
        history_i[h] <= history_i[h-1];
        history_q[h] <= history_q[h-1];
      end
    end
    if (start) begin
      snapshot_i[8] <= history_count >= 15 ? $signed(history_i[14]) : 17'sd0;
      snapshot_q[8] <= history_count >= 15 ? $signed(history_q[14]) : 17'sd0;
    end
  end

  reg signed [16:0] pair_i, pair_q;
  reg signed [17:0] coefficient_read;
  (* use_dsp = "yes" *) reg signed [34:0] product_i, product_q;
  reg signed [38:0] accumulator_i, accumulator_q;
  reg pair_valid, pair_first, pair_last;
  reg product_valid, product_first, product_last;
  reg quantize_valid;
  always @(posedge clk) begin
    pair_i <= snapshot_i[row];
    pair_q <= snapshot_q[row];
    coefficient_read <= coefficient[row];
    product_i <= pair_i * coefficient_read;
    product_q <= pair_q * coefficient_read;
    if (product_valid) begin
      if (product_first) begin
        accumulator_i <= {{4{product_i[34]}}, product_i};
        accumulator_q <= {{4{product_q[34]}}, product_q};
      end else begin
        accumulator_i <= accumulator_i + {{4{product_i[34]}}, product_i};
        accumulator_q <= accumulator_q + {{4{product_q[34]}}, product_q};
      end
    end
  end

  function automatic [16:0] quantize_q17;
    input signed [38:0] value;
    reg [38:0] magnitude;
    reg [22:0] rounded;
    begin
      magnitude = value[38] ? -value : value;
      rounded = {1'b0, magnitude[38:17]} +
          ((magnitude[16:0] > 17'h10000) ||
           ((magnitude[16:0] == 17'h10000) && magnitude[17]));
      if (value[38]) begin
        if (rounded > 32768) quantize_q17 = {1'b1, 16'h8000};
        else quantize_q17 = {1'b0, -rounded[15:0]};
      end else begin
        if (rounded > 32767) quantize_q17 = {1'b1, 16'h7fff};
        else quantize_q17 = {1'b0, rounded[15:0]};
      end
    end
  endfunction
  wire [16:0] quantized_i = quantize_q17(accumulator_i);
  wire [16:0] quantized_q = quantize_q17(accumulator_q);
  always @(posedge clk) begin
    output_i <= quantized_i[15:0];
    output_q <= quantized_q[15:0];
    output_index <= job_index;
    output_phase <= job_phase;
    output_support_valid <= job_support;
    output_saturations <= {1'b0, quantized_i[16]} + {1'b0, quantized_q[16]};
    if (!resetn) begin
      halted <= 0;
      sticky_overrun <= 0;
    end else if (flush) halted <= 0;
    else if (overrun && !halted) begin
      halted <= 1;
      sticky_overrun <= 1;
    end
    if (!run) begin
      history_count <= 0;
      support_count <= 0;
      busy <= 0;
      issuing <= 0;
      row <= 0;
      job_index <= 0;
      job_phase <= 0;
      job_support <= 0;
      pair_valid <= 0;
      pair_first <= 0;
      pair_last <= 0;
      product_valid <= 0;
      product_first <= 0;
      product_last <= 0;
      quantize_valid <= 0;
      output_valid <= 0;
    end else begin
      pair_valid <= issue;
      pair_first <= row == 0;
      pair_last <= row == 8;
      product_valid <= pair_valid;
      product_first <= pair_first;
      product_last <= pair_last;
      quantize_valid <= product_valid && product_last;
      output_valid <= quantize_valid;
      if (product_valid && product_last) busy <= 0;
      if (input_valid) begin
        if (history_count < 30) history_count <= history_count + 1'b1;
        if (!input_support_valid) support_count <= 0;
        else if (support_count < 30) support_count <= support_count + 1'b1;
      end
      if (start) begin
        busy <= 1;
        issuing <= 1;
        row <= 0;
        job_index <= input_index;
        job_phase <= input_phase;
        job_support <= input_support_valid && support_count == 30;
      end else if (issue) begin
        if (row == 8) issuing <= 0;
        else row <= row + 1'b1;
      end
    end
  end
endmodule
