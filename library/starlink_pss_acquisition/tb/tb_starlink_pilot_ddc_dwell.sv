// SPDX-License-Identifier: GPL-2.0
// Full 120 ms valid-output gate, plus startup history. No RF or GLRT claim.
`timescale 1ns/1ps
module tb_starlink_pilot_ddc_dwell #(
  parameter integer INPUT_COUNT = 1800540
);
  reg clk = 0;
  always #5 clk = ~clk;
  reg resetn = 0, input_valid = 0;
  reg signed [15:0] input_i = 0, input_q = 0;
  reg [63:0] input_index = 0;
  wire output_valid, output_support_valid, halted;
  wire signed [15:0] output_i, output_q;
  wire [63:0] output_index, accepted_sample_count, emitted_sample_count;
  wire [31:0] output_visit_id, saturation_event_count;
  wire [7:0] fifo_high_water, sticky_fault;
  starlink_pilot_ddc dut (
    .clk(clk), .resetn(resetn), .flush(1'b0), .edge_upper(1'b1), .visit_id(32'd17),
    .input_valid(input_valid), .input_gap(1'b0), .input_i(input_i), .input_q(input_q),
    .input_index(input_index), .input_support_valid(1'b1),
    .output_valid(output_valid), .output_i(output_i), .output_q(output_q),
    .output_index(output_index), .output_visit_id(output_visit_id),
    .output_support_valid(output_support_valid),
    .accepted_sample_count(accepted_sample_count), .emitted_sample_count(emitted_sample_count),
    .saturation_event_count(saturation_event_count), .fifo_high_water(fifo_high_water),
    .sticky_fault(sticky_fault), .halted(halted)
  );
  integer n, gap, phase;
  integer outputs = 0, supported = 0;
  initial begin
    if (INPUT_COUNT < 546 || INPUT_COUNT % 6) $fatal(1, "invalid input count");
    repeat (3) @(negedge clk);
    resetn = 1;
    for (n = 0; n < INPUT_COUNT; n = n + 1) begin
      gap = n % 3 == 0 ? 6 : 7;
      repeat (gap-1) begin @(negedge clk); input_valid = 0; end
      @(negedge clk);
      input_valid = 1;
      input_index = n;
      phase = (n * 12) % 64;
      // A positive 2.8125 MHz CW: conjugate of the frozen downmixer,
      // quantized to about 8192 CI16 amplitude. It should emerge at DC.
      input_i = $signed(dut.mixer[phase][17:0]) >>> 3;
      input_q = (-$signed(dut.mixer[phase][35:18])) >>> 3;
    end
    @(negedge clk);
    input_valid = 0;
    repeat (1500) @(negedge clk);
    if (sticky_fault || halted || saturation_event_count ||
        accepted_sample_count != INPUT_COUNT || emitted_sample_count != INPUT_COUNT / 6 ||
        outputs != INPUT_COUNT / 6 || supported != (INPUT_COUNT - 540) / 6)
      $fatal(1, "dwell count or health gate failed");
    $display("PILOT_DDC_DWELL_PASS accepted=%0d emitted=%0d supported=%0d fifo_high_water=%0d",
        accepted_sample_count, emitted_sample_count, supported, fifo_high_water);
    $finish(0);
  end
  always @(posedge clk) begin
    if (resetn && (sticky_fault || halted)) $fatal(1, "unexpected pilot fault");
    if (output_valid) begin
      if (output_index !== 64'(outputs * 6) || output_visit_id !== 32'd17 ||
          output_support_valid !== (output_index >= 538)) $fatal(1, "counter/support mismatch");
      outputs = outputs + 1;
      if (output_support_valid) begin
        if (output_i < 8189 || output_i > 8195 || output_q < -3 || output_q > 3 ||
            (^output_i === 1'bx) || (^output_q === 1'bx)) $fatal(1, "CW gain/phase mismatch");
        supported = supported + 1;
        if (supported % 100000 == 0) $display("PILOT_DDC_DWELL_PROGRESS supported=%0d", supported);
      end
    end
  end
  initial begin
    #200000000;
    $fatal(1, "dwell watchdog");
  end
endmodule
