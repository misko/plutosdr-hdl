// SPDX-License-Identifier: GPL-2.0
`timescale 1ns/1ps
module tb_starlink_pilot_fir3;
  reg clk = 0;
  always #5 clk = ~clk;
  reg resetn = 0, flush = 0, input_valid = 0;
  reg signed [15:0] input_i = 0, input_q = 0;
  reg [63:0] input_index = 0;
  reg [1:0] input_phase = 0;
  reg input_support_valid = 0;
  wire output_valid, output_support_valid, halted;
  wire signed [15:0] output_i, output_q;
  wire [63:0] output_index;
  wire [1:0] output_saturations;
  wire [2:0] sticky_fault;
  starlink_pilot_fir3 dut (.*);
  integer source, fields, gap, op, i_value, q_value, phase, support;
  reg [63:0] index_value;
  integer count = 0;
  integer cycle = 0;
  initial begin
    // Exact rounding boundaries are too rare to entrust to random replay.
    if (dut.quantize_q17(44'sd65536) !== 17'h00000 ||
        dut.quantize_q17(-44'sd65536) !== 17'h00000 ||
        dut.quantize_q17(44'sd196608) !== 17'h00002 ||
        dut.quantize_q17(-44'sd196608) !== 17'h0fffe ||
        dut.quantize_q17(44'sd32767 * 44'sd131072 + 44'sd65536) !== 17'h17fff ||
        dut.quantize_q17(-44'sd32768 * 44'sd131072 - 44'sd65536) !== 17'h08000 ||
        dut.quantize_q17(-44'sd32768 * 44'sd131072 - 44'sd65537) !== 17'h18000)
      $fatal(1, "quantization boundary mismatch");
    source = $fopen("stimulus.txt", "r");
    if (!source) $fatal(1, "missing stimulus.txt");
    repeat (3) @(negedge clk);
    resetn = 1;
    while (!$feof(source)) begin
      fields = $fscanf(source, "%d %d %h %d %d %d %d\n",
          gap, op, index_value, phase, i_value, q_value, support);
      if (fields != 7 || gap < 1) $fatal(1, "bad stimulus record");
      repeat (gap-1) begin
        @(negedge clk);
        input_valid = 0;
        flush = 0;
      end
      @(negedge clk);
      input_valid = op == 1;
      flush = op == 2;
      input_index = index_value;
      input_phase = phase;
      input_i = i_value;
      input_q = q_value;
      input_support_valid = support;
    end
    @(negedge clk);
    input_valid = 0;
    flush = 0;
    repeat (100) @(negedge clk);
    $display("STATUS %d %d %d", sticky_fault, halted, count);
    $fclose(source);
    $finish(0);
  end
  always @(posedge clk) begin
    #1;
    cycle = cycle + 1;
    if (output_valid) begin
      if ((^output_index === 1'bx) || (^output_i === 1'bx) ||
          (^output_q === 1'bx) || (^output_support_valid === 1'bx) ||
          (^output_saturations === 1'bx)) $fatal(1, "unknown valid output");
      $display("OUT %016h %d %d %d %d %d", output_index, output_i,
          output_q, output_support_valid, output_saturations, cycle);
      count = count + 1;
    end
  end
  initial begin
    #100000000;
    $fatal(1, "watchdog");
  end
endmodule
