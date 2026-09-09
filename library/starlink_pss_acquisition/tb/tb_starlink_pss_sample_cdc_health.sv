// SPDX-License-Identifier: GPL-2.0
// Exercise the actual destination health registers, including same-edge flags.
`timescale 1ns/1ps
module tb_starlink_pss_sample_cdc_health;
  reg source_clk = 0, acquisition_clk = 0;
  always #8 source_clk = ~source_clk;
  always #5 acquisition_clk = ~acquisition_clk;
  reg source_resetn = 0, acquisition_resetn = 0;
  wire [31:0] dropped_sample_count;
  wire overflow_sticky;
  reg [31:0] forced_gray = 0;
  reg [31:0] previous_count = 0;
  reg [31:0] random_state = 32'h72c5a091;
  integer bit_number, iteration, checked = 0;

  starlink_pss_sample_cdc #(.FIFO_ADDRESS_WIDTH(2)) dut (
    .source_clk(source_clk), .source_resetn(source_resetn),
    .source_sample_valid(1'b0), .source_sample_gap(1'b0),
    .source_sample_i(16'sd0), .source_sample_q(16'sd0),
    .source_sample_index(64'd0), .source_fifo_full(),
    .acquisition_clk(acquisition_clk), .acquisition_resetn(acquisition_resetn),
    .acquisition_sample_valid(), .acquisition_sample_gap(),
    .acquisition_sample_i(), .acquisition_sample_q(), .acquisition_sample_index(),
    .dropped_sample_count(dropped_sample_count), .overflow_sticky(overflow_sticky),
    .fifo_level(), .maximum_fifo_level()
  );

  task automatic check_word(input [31:0] binary_count);
    begin
      @(negedge acquisition_clk);
      forced_gray = binary_count ^ (binary_count >> 1);
      #1;
      if (dropped_sample_count !== previous_count ||
          overflow_sticky !== (previous_count != 0))
        $fatal(1, "health changed before destination clock");
      @(posedge acquisition_clk);
      #1;
      if (dropped_sample_count !== binary_count ||
          overflow_sticky !== (binary_count != 0))
        $fatal(1, "health not coherent on same edge: count=%h expected=%h flag=%b",
               dropped_sample_count, binary_count, overflow_sticky);
      previous_count = binary_count;
      checked = checked + 1;
    end
  endtask

  initial begin
    repeat (4) @(negedge acquisition_clk);
    source_resetn = 1;
    acquisition_resetn = 1;
    repeat (8) @(negedge acquisition_clk);
    // Force only the already-synchronized word: this test proves local logic,
    // not metastability/physical CDC. The separate FIFO bench exercises CDC.
    force dut.dropped_count_gray_sync_2 = forced_gray;
    check_word(0);
    for (bit_number = 0; bit_number < 32; bit_number = bit_number + 1) begin
      check_word(32'd1 << bit_number);
      check_word((32'd1 << bit_number) - 1'b1);
      check_word((32'd1 << bit_number) + 1'b1);
      check_word(0);
    end
    for (iteration = 0; iteration < 4096; iteration = iteration + 1) begin
      random_state = {random_state[30:0],
          random_state[31] ^ random_state[21] ^ random_state[1] ^ random_state[0]};
      check_word(random_state);
      check_word(0);
    end
    check_word(32'hffffffff);
    check_word(32'hffffffff);
    release dut.dropped_count_gray_sync_2;
    @(negedge acquisition_clk);
    source_resetn = 0;
    repeat (8) @(negedge acquisition_clk);
    if (dropped_sample_count !== 0 || overflow_sticky !== 0)
      $fatal(1, "source reset did not clear both health outputs");
    source_resetn = 1;
    repeat (8) @(negedge acquisition_clk);
    previous_count = 0;
    forced_gray = 0;
    force dut.dropped_count_gray_sync_2 = forced_gray;
    check_word(32'hffffffff);
    release dut.dropped_count_gray_sync_2;
    @(negedge acquisition_clk);
    acquisition_resetn = 0;
    repeat (8) @(negedge acquisition_clk);
    if (dropped_sample_count !== 0 || overflow_sticky !== 0)
      $fatal(1, "destination reset did not clear both health outputs");
    $display("SAMPLE_CDC_HEALTH_PASS words=%0d same_edge=1 independent_resets=2", checked);
    $finish;
  end
  initial begin
    #1000000;
    $fatal(1, "watchdog");
  end
endmodule
