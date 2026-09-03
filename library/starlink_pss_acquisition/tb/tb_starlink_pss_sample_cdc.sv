`timescale 1ns/1ps

module tb_starlink_pss_sample_cdc #(
  parameter integer FIFO_ADDRESS_WIDTH = 7
);

  localparam integer FIFO_DEPTH = 1 << FIFO_ADDRESS_WIDTH;
  localparam integer MAX_EXPECTED = 512;

  reg source_clk = 1'b0;
  reg acquisition_clk = 1'b0;
  reg acquisition_clock_enable = 1'b1;
  reg source_resetn = 1'b0;
  reg acquisition_resetn = 1'b0;
  reg source_sample_valid = 1'b0;
  reg source_sample_gap = 1'b0;
  reg signed [15:0] source_sample_i = 16'sd0;
  reg signed [15:0] source_sample_q = 16'sd0;
  reg [63:0] source_sample_index = 64'd0;

  wire source_fifo_full;
  wire acquisition_sample_valid;
  wire acquisition_sample_gap;
  wire signed [15:0] acquisition_sample_i;
  wire signed [15:0] acquisition_sample_q;
  wire [63:0] acquisition_sample_index;
  wire [31:0] dropped_sample_count;
  wire overflow_sticky;
  wire [FIFO_ADDRESS_WIDTH:0] fifo_level;
  wire [FIFO_ADDRESS_WIDTH:0] maximum_fifo_level;

  reg [63:0] expected_index [0:MAX_EXPECTED-1];
  reg signed [15:0] expected_i [0:MAX_EXPECTED-1];
  reg signed [15:0] expected_q [0:MAX_EXPECTED-1];
  reg expected_gap [0:MAX_EXPECTED-1];
  integer expected_write = 0;
  integer expected_read = 0;
  integer output_count = 0;
  integer dropped_at_source = 0;
  integer sample_number;
  integer timeout;
  reg model_gap_pending = 1'b1;

  always #8 source_clk = ~source_clk;
  always #5 begin
    if (acquisition_clock_enable)
      acquisition_clk = ~acquisition_clk;
  end

  starlink_pss_sample_cdc #(
    .FIFO_ADDRESS_WIDTH(FIFO_ADDRESS_WIDTH)
  ) dut (
    .source_clk                    (source_clk),
    .source_resetn                 (source_resetn),
    .source_sample_valid           (source_sample_valid),
    .source_sample_gap             (source_sample_gap),
    .source_sample_i               (source_sample_i),
    .source_sample_q               (source_sample_q),
    .source_sample_index           (source_sample_index),
    .source_fifo_full              (source_fifo_full),
    .acquisition_clk               (acquisition_clk),
    .acquisition_resetn            (acquisition_resetn),
    .acquisition_sample_valid      (acquisition_sample_valid),
    .acquisition_sample_gap        (acquisition_sample_gap),
    .acquisition_sample_i          (acquisition_sample_i),
    .acquisition_sample_q          (acquisition_sample_q),
    .acquisition_sample_index      (acquisition_sample_index),
    .dropped_sample_count          (dropped_sample_count),
    .overflow_sticky               (overflow_sticky),
    .fifo_level                    (fifo_level),
    .maximum_fifo_level            (maximum_fifo_level)
  );

  task automatic fail(input string message);
    begin
      $display("SAMPLE_CDC_FAIL %0s expected_read=%0d expected_write=%0d",
               message, expected_read, expected_write);
      $fatal(1);
    end
  endtask

  function automatic signed [15:0] encoded_i(input [63:0] index);
    encoded_i = index[15:0] ^ 16'h5a3c;
  endfunction

  function automatic signed [15:0] encoded_q(input [63:0] index);
    encoded_q = ~(index[15:0] ^ 16'ha5c3);
  endfunction

  task automatic append_expected(input [63:0] index, input gap);
    begin
      if (expected_write >= MAX_EXPECTED)
        fail("expected queue overflow");
      expected_index[expected_write] = index;
      expected_i[expected_write] = encoded_i(index);
      expected_q[expected_write] = encoded_q(index);
      expected_gap[expected_write] = gap || model_gap_pending;
      expected_write = expected_write + 1;
      model_gap_pending = 1'b0;
    end
  endtask

  task automatic send_sample(input [63:0] index, input gap);
    reg accepted;
    begin
      @(negedge source_clk);
      source_sample_index = index;
      source_sample_i = encoded_i(index);
      source_sample_q = encoded_q(index);
      source_sample_gap = gap;
      source_sample_valid = 1'b1;
      accepted = !source_fifo_full;
      if (accepted)
        append_expected(index, gap);
      else begin
        dropped_at_source = dropped_at_source + 1;
        model_gap_pending = 1'b1;
      end
      @(negedge source_clk);
      source_sample_valid = 1'b0;
      source_sample_gap = 1'b0;
    end
  endtask

  task automatic wait_for_outputs;
    begin
      timeout = 0;
      while (expected_read != expected_write && timeout < 2000) begin
        @(negedge acquisition_clk);
        timeout = timeout + 1;
      end
      if (timeout == 2000)
        fail("timed out waiting for output queue to drain");
      repeat (4) @(negedge acquisition_clk);
    end
  endtask

  always @(negedge acquisition_clk) begin
    if (acquisition_sample_valid) begin
      if (expected_read >= expected_write)
        fail("unexpected or stale destination sample");
      if (acquisition_sample_index !== expected_index[expected_read])
        fail("destination sample index mismatch");
      if (acquisition_sample_i !== expected_i[expected_read])
        fail("destination I mismatch");
      if (acquisition_sample_q !== expected_q[expected_read])
        fail("destination Q mismatch");
      if (acquisition_sample_gap !== expected_gap[expected_read])
        fail("destination gap marker mismatch");
      expected_read = expected_read + 1;
      output_count = output_count + 1;
    end
  end

  initial begin
    $dumpfile("build/tb_starlink_pss_sample_cdc.vcd");
    $dumpvars(0, tb_starlink_pss_sample_cdc);

    repeat (3) @(negedge source_clk);
    source_resetn = 1'b1;
    acquisition_resetn = 1'b1;

    // Normal 61.44-to-100 MHz operation: exact data/index transport, an
    // epoch marker on the first sample, and preservation of an explicit gap.
    repeat (4) @(negedge source_clk);
    for (sample_number = 0; sample_number < 12; sample_number = sample_number + 1) begin
      send_sample(64'd1000 + sample_number, sample_number == 7);
      repeat (2) @(negedge source_clk);
    end
    wait_for_outputs();
    if (dropped_sample_count != 0 || overflow_sticky)
      fail("normal asynchronous transfer reported overflow");

    // A source-only reset purges queued data in both domains.  Nothing from
    // the prior epoch may escape, and the new epoch must start with a gap.
    acquisition_clock_enable = 1'b0;
    repeat (2) @(negedge source_clk);
    send_sample(64'd2000, 1'b0);
    send_sample(64'd2001, 1'b0);
    expected_read = expected_write;
    source_resetn = 1'b0;
    model_gap_pending = 1'b1;
    repeat (2) @(negedge source_clk);
    acquisition_clock_enable = 1'b1;
    repeat (4) @(negedge acquisition_clk);
    source_resetn = 1'b1;
    repeat (4) @(negedge source_clk);
    send_sample(64'd3000, 1'b0);
    send_sample(64'd3001, 1'b0);
    wait_for_outputs();

    // A destination-only reset has the same atomic purge/recovery contract.
    acquisition_clock_enable = 1'b0;
    repeat (2) @(negedge source_clk);
    send_sample(64'd4000, 1'b0);
    expected_read = expected_write;
    acquisition_resetn = 1'b0;
    model_gap_pending = 1'b1;
    repeat (2) @(negedge source_clk);
    acquisition_clock_enable = 1'b1;
    repeat (3) @(negedge acquisition_clk);
    acquisition_resetn = 1'b1;
    repeat (4) @(negedge source_clk);
    send_sample(64'd5000, 1'b0);
    wait_for_outputs();

    // Stop the faster destination clock, fill all four FIFO entries, and
    // prove that every later source beat is counted as lost.  Once space is
    // visible again, the first retained beat must carry the gap marker.
    acquisition_clock_enable = 1'b0;
    repeat (2) @(negedge source_clk);
    for (sample_number = 0; sample_number < FIFO_DEPTH + 6;
         sample_number = sample_number + 1)
      send_sample(64'd6000 + sample_number, 1'b0);
    if (dropped_at_source != 6)
      fail("source full/drop accounting mismatch");

    acquisition_clock_enable = 1'b1;
    wait_for_outputs();
    timeout = 0;
    while (source_fifo_full && timeout < 100) begin
      @(negedge source_clk);
      timeout = timeout + 1;
    end
    if (timeout == 100)
      fail("source full did not clear after destination resumed");
    send_sample(64'd7000, 1'b0);
    send_sample(64'd7001, 1'b0);
    wait_for_outputs();

    timeout = 0;
    while (dropped_sample_count != dropped_at_source && timeout < 100) begin
      @(negedge acquisition_clk);
      timeout = timeout + 1;
    end
    if (timeout == 100 || dropped_sample_count != 6 || !overflow_sticky)
      fail("destination drop telemetry mismatch");
    if (maximum_fifo_level != FIFO_DEPTH)
      fail("maximum FIFO level did not observe the full FIFO");
    if (fifo_level != 0)
      fail("FIFO did not finish empty");

    $display("SAMPLE_CDC_PASS outputs=%0d fifo_depth=%0d drops=%0d independent_reset_purge=2 gap_recovery=1",
             output_count, FIFO_DEPTH, dropped_at_source);
    $finish;
  end

endmodule
