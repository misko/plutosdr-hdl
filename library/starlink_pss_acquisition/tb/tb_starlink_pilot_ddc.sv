// SPDX-License-Identifier: GPL-2.0
`timescale 1ns/1ps
module tb_starlink_pilot_ddc #(
  parameter integer SOURCE_RATE_MSPS = 15,
  parameter integer SOURCE_EDGE_UPPER = 1
);
  reg clk = 0;
  always #5 clk = ~clk;
  reg resetn = 0, flush = 0, input_valid = 0, input_gap = 0;
  reg edge_upper = 0;
  reg [31:0] visit_id = 0;
  reg signed [15:0] input_i = 0, input_q = 0;
  reg [63:0] input_index = 0;
  reg input_support_valid = 0;
  wire output_valid, output_support_valid, halted;
  wire signed [15:0] output_i, output_q;
  wire [63:0] output_index;
  wire [31:0] output_visit_id;
  wire [63:0] accepted_sample_count, emitted_sample_count;
  wire [31:0] saturation_event_count;
  wire [7:0] fifo_high_water, sticky_fault;
  wire canonical_valid, canonical_gap;
  wire signed [15:0] canonical_i, canonical_q;
  wire [63:0] canonical_index;
  generate if (SOURCE_RATE_MSPS == 15) begin : g_native
    assign canonical_valid = input_valid;
    assign canonical_gap = input_gap;
    assign canonical_i = input_i;
    assign canonical_q = input_q;
    assign canonical_index = input_index;
  end else begin : g_conditioned
    wire first_valid, first_gap;
    wire signed [15:0] first_i, first_q;
    wire [63:0] first_index;
    starlink_pss_x2_ddc #(.EDGE_UPPER(SOURCE_EDGE_UPPER)) first_ddc (
      .clk(clk), .resetn(resetn), .enable(1'b1), .flush(flush),
      .input_valid(input_valid), .input_gap(input_gap), .input_i(input_i),
      .input_q(input_q), .input_index(input_index), .output_enable(),
      .output_valid(first_valid), .output_gap(first_gap), .output_i(first_i),
      .output_q(first_q), .output_index(first_index), .accepted_sample_count(),
      .emitted_sample_count(), .discontinuity_count(), .saturation_event_count()
    );
    if (SOURCE_RATE_MSPS == 30) begin : g_x2
      assign canonical_valid = first_valid;
      assign canonical_gap = first_gap;
      assign canonical_i = first_i;
      assign canonical_q = first_q;
      assign canonical_index = first_index;
    end else if (SOURCE_RATE_MSPS == 60) begin : g_x4
      starlink_pss_x2_ddc #(.EDGE_UPPER(SOURCE_EDGE_UPPER)) second_ddc (
        .clk(clk), .resetn(resetn), .enable(1'b1), .flush(flush),
        .input_valid(first_valid), .input_gap(first_gap), .input_i(first_i),
        .input_q(first_q), .input_index(first_index), .output_enable(),
        .output_valid(canonical_valid), .output_gap(canonical_gap),
        .output_i(canonical_i), .output_q(canonical_q), .output_index(canonical_index),
        .accepted_sample_count(), .emitted_sample_count(), .discontinuity_count(),
        .saturation_event_count()
      );
    end else begin : g_invalid_rate
      initial $fatal(1, "unsupported source rate");
    end
  end endgenerate
  starlink_pilot_ddc dut (
    .input_valid(canonical_valid), .input_gap(canonical_gap),
    .input_i(canonical_i), .input_q(canonical_q), .input_index(canonical_index), .*
  );
  integer source, fields, gap, op, i_value, q_value, edge_value, support;
  reg [63:0] index_value;
  reg [31:0] visit_value;
  integer cycle = 0;
  integer previous_hb_cycle = -100;
  integer phase_test;
  initial begin
    if (dut.quantize_q16(35'sd32768) !== 17'h00000 ||
        dut.quantize_q16(-35'sd32768) !== 17'h00000 ||
        dut.quantize_q16(35'sd98304) !== 17'h00002 ||
        dut.quantize_q16(-35'sd98304) !== 17'h0fffe ||
        dut.quantize_q16(35'sd32767 * 35'sd65536 + 35'sd32768) !== 17'h17fff ||
        dut.halfband.quantize_q17(-39'sd32768 * 39'sd131072 - 39'sd65536) !== 17'h08000 ||
        dut.halfband.quantize_q17(-39'sd32768 * 39'sd131072 - 39'sd65537) !== 17'h18000)
      $fatal(1, "quantization boundary mismatch");
    for (phase_test = 0; phase_test < 4096; phase_test = phase_test + 1)
      if (dut.phase_from_index(64'hfedcba9876543000 + phase_test) !==
          ((64'hfedcba9876543000 + phase_test) >> 1) % 3)
        $fatal(1, "absolute phase seed mismatch");
    source = $fopen("stimulus.txt", "r");
    if (!source) $fatal(1, "missing stimulus.txt");
    repeat (3) @(negedge clk);
    resetn = 1;
    while (!$feof(source)) begin
      fields = $fscanf(source, "%d %d %h %d %h %d %d %d\n",
          gap, op, index_value, edge_value, visit_value, i_value, q_value, support);
      if (fields != 8 || gap < 1) $fatal(1, "bad stimulus record");
      repeat (gap-1) begin
        @(negedge clk);
        input_valid = 0;
        input_gap = 0;
        flush = 0;
      end
      @(negedge clk);
      input_valid = op == 1;
      input_gap = op == 3;
      flush = op == 2;
      input_index = index_value;
      edge_upper = edge_value;
      visit_id = visit_value;
      input_i = i_value;
      input_q = q_value;
      input_support_valid = support;
    end
    @(negedge clk);
    input_valid = 0;
    input_gap = 0;
    flush = 0;
    repeat (1500) @(negedge clk);
    $display("STATUS %d %d %d %d %d %d", sticky_fault, halted,
        accepted_sample_count, emitted_sample_count, saturation_event_count, fifo_high_water);
    $fclose(source);
    $finish(0);
  end
  always @(posedge clk) begin
    // Sample the transfer at the edge, like a downstream synchronous FIFO.
    // The combinational fail-closed qualifier uses the current ingress beat;
    // sampling after NBA updates but before the next stimulus is not a transfer.
    cycle = cycle + 1;
    if ($test$plusargs("TRACE")) begin
      if (dut.mixed_valid) $display("MIX %d %d %d %d", dut.mixed_index, dut.mixed_i, dut.mixed_q, cycle);
      if (dut.hb_valid && !dut.pipe_flush) $display("HB %d %d %d %d", dut.hb_index, dut.hb_i, dut.hb_q, cycle);
    end
    if (flush || !resetn) previous_hb_cycle = -100;
    if (dut.hb_valid && !dut.pipe_flush) begin
      if (cycle - previous_hb_cycle < 13) $fatal(1, "halfband output overspeed");
      if (dut.hb_index[0] || dut.hb_phase !== (dut.hb_index >> 1) % 3)
        $fatal(1, "halfband absolute phase mismatch");
      previous_hb_cycle = cycle;
    end
    if (output_valid) begin
      if ((^output_index === 1'bx) || (^output_i === 1'bx) ||
          (^output_q === 1'bx) || (^output_support_valid === 1'bx) ||
          (^output_visit_id === 1'bx)) $fatal(1, "unknown valid output");
      $display("OUT %016h %08h %d %d %d %d", output_index, output_visit_id,
          output_i, output_q, output_support_valid, cycle);
    end
  end
  initial begin
    #1000000000;
    $fatal(1, "watchdog");
  end
endmodule
