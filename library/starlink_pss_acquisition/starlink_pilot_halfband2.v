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
  // A halfband job consumes the 16 even samples plus one delayed odd sample.
  // Keep those phases in small RAMs, not 960 history FFs and 18 parallel
  // pair-adders. The even ring cannot be overwritten during a >=13-clock job;
  // the odd center is captured at start because the next odd input can arrive
  // before row 8 is issued. Arithmetic and external latency remain unchanged.
  (* ram_style = "distributed" *) reg [31:0] even_memory [0:15];
  (* ram_style = "distributed" *) reg [31:0] odd_memory [0:7];
  reg [3:0] even_pointer, job_pointer;
  reg [2:0] odd_pointer;
  reg [4:0] job_history;
  reg signed [15:0] center_i, center_q;
  reg [4:0] history_count;
  reg [4:0] support_count;
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

  always @(posedge clk) begin
    if (run && input_valid) begin
      if (input_index[0]) odd_memory[odd_pointer] <= {input_q, input_i};
      else even_memory[even_pointer] <= {input_q, input_i};
    end
    if (start) begin
      center_i <= history_count >= 15 ? $signed(odd_memory[odd_pointer][15:0]) : 16'sd0;
      center_q <= history_count >= 15 ? $signed(odd_memory[odd_pointer][31:16]) : 16'sd0;
    end
  end

  wire [3:0] address_a = job_pointer - row;
  wire [3:0] address_b = job_pointer - 4'd15 + row;
  wire [4:0] tap_a = {row, 1'b0};
  wire [4:0] tap_b = 5'd30 - tap_a;
  wire signed [15:0] a_i = job_history >= tap_a ? $signed(even_memory[address_a][15:0]) : 16'sd0;
  wire signed [15:0] a_q = job_history >= tap_a ? $signed(even_memory[address_a][31:16]) : 16'sd0;
  wire signed [15:0] b_i = job_history >= tap_b ? $signed(even_memory[address_b][15:0]) : 16'sd0;
  wire signed [15:0] b_q = job_history >= tap_b ? $signed(even_memory[address_b][31:16]) : 16'sd0;

  reg signed [16:0] pair_i, pair_q;
  reg signed [17:0] coefficient_read;
  (* use_dsp = "yes" *) reg signed [34:0] product_i, product_q;
  reg signed [38:0] accumulator_i, accumulator_q;
  reg pair_valid, pair_first, pair_last;
  reg product_valid, product_first, product_last;
  reg quantize_valid;
  always @(posedge clk) begin
    pair_i <= row == 8 ? $signed(center_i) : $signed({a_i[15], a_i}) + $signed({b_i[15], b_i});
    pair_q <= row == 8 ? $signed(center_q) : $signed({a_q[15], a_q}) + $signed({b_q[15], b_q});
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
      even_pointer <= 0;
      odd_pointer <= 0;
      job_pointer <= 0;
      job_history <= 0;
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
        if (input_index[0]) odd_pointer <= odd_pointer + 1'b1;
        else even_pointer <= even_pointer + 1'b1;
        if (history_count < 30) history_count <= history_count + 1'b1;
        if (!input_support_valid) support_count <= 0;
        else if (support_count < 30) support_count <= support_count + 1'b1;
      end
      if (start) begin
        job_pointer <= even_pointer;
        job_history <= history_count;
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
