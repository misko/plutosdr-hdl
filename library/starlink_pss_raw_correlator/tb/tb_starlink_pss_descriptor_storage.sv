`timescale 1ns/1ps

// Public cycle equivalence to pinned old RTL, plus an independent queue oracle.
// The two clocks never share an edge. This is functional simulation, not an
// analog metastability or physical CDC proof. No private state is driven.
module tb_starlink_pss_descriptor_storage #(
  parameter integer WRITE_HALF = 7,
  parameter integer READ_HALF = 5,
  parameter integer RELEASE_READ_FIRST = 0
);
  reg write_clk = 0, read_clk = 0;
  always #WRITE_HALF write_clk = ~write_clk;
  initial begin
    #0.7;
    forever #READ_HALF read_clk = ~read_clk;
  end
  reg write_resetn = 0, read_resetn = 0;
  reg write_valid = 0, read_ready = 0, automatic_reader = 0;
  reg [160:0] write_data = 0;
  wire write_ready, read_valid, golden_write_ready, golden_read_valid;
  wire [1:0] write_room, golden_write_room;
  wire [160:0] read_data, golden_read_data;

`ifdef DESCRIPTOR_SYNTH_NETLIST
  starlink_pss_async_fifo dut (
`else
  starlink_pss_async_fifo #(
    .DATA_WIDTH(161), .ADDRESS_WIDTH(2), .RAM_STYLE("block")
  ) dut (
`endif
    .i_write_clk(write_clk), .i_write_resetn(write_resetn),
    .i_write_valid(write_valid), .o_write_ready(write_ready),
    .i_write_data(write_data), .o_write_room(write_room),
    .i_read_clk(read_clk), .i_read_resetn(read_resetn),
    .o_read_valid(read_valid), .i_read_ready(read_ready), .o_read_data(read_data)
  );
  starlink_pss_async_fifo_golden #(
    .DATA_WIDTH(161), .ADDRESS_WIDTH(2), .RAM_STYLE("distributed")
  ) golden (
    .i_write_clk(write_clk), .i_write_resetn(write_resetn),
    .i_write_valid(write_valid), .o_write_ready(golden_write_ready),
    .i_write_data(write_data), .o_write_room(golden_write_room),
    .i_read_clk(read_clk), .i_read_resetn(read_resetn),
    .o_read_valid(golden_read_valid), .i_read_ready(read_ready),
    .o_read_data(golden_read_data)
  );

  reg [160:0] expected [0:255];
  integer written = 0, consumed = 0, total_written = 0, total_consumed = 0;
  integer blocked_writes = 0, compared_reads = 0, reader_cycles = 0;
  integer held_after_consumption = 0;
  integer ordinal;
  reg [160:0] retained_payload;

  function automatic [160:0] word(input integer n);
    reg [31:0] request_id;
    reg [63:0] center_index, center_timestamp;
    begin
      request_id = 32'h5aa5_ffff ^ n;
      center_index = 64'hffff_ffff_ffff_ff00 + 64'h100000013 * n;
      center_timestamp = 64'h8000_0000_ffff_ffff ^ (64'h200000021 * n);
      word = {n[0], request_id, center_index, center_timestamp};
    end
  endfunction

  always @(posedge write_clk) begin
    if (!write_resetn) written = 0;
    else if (write_valid && write_ready) begin
      if (written >= 256) $fatal(1, "DESCRIPTOR_QUEUE_OVERFLOW");
      expected[written] = write_data;
      written = written + 1;
      total_written = total_written + 1;
    end else if (write_valid && !write_ready) blocked_writes = blocked_writes + 1;
    // UNISIM functional flops have a 100 ps clock-to-Q delay. Observe after
    // that delay and combinational settling, still within this same clock.
    #1;
    if ($time > 150 && {write_ready, write_room} !==
                         {golden_write_ready, golden_write_room})
      $fatal(1, "DESCRIPTOR_EQUIVALENCE_WRITE_FAIL actual=%b/%b expected=%b/%b",
             write_ready, write_room, golden_write_ready, golden_write_room);
  end
  always @(posedge read_clk) begin
    if (!read_resetn) consumed = 0;
    else if (read_valid && read_ready) begin
      if (consumed >= written || read_data !== expected[consumed])
        $fatal(1, "DESCRIPTOR_QUEUE_ORDER_FAIL consumed=%0d written=%0d", consumed, written);
      consumed = consumed + 1;
      total_consumed = total_consumed + 1;
    end
    #1;
    if ($time > 150) begin
      if (read_valid !== golden_read_valid)
        $fatal(1, "DESCRIPTOR_EQUIVALENCE_VALID_FAIL");
      // Before its first prefetch the old unreset payload is unspecified.
      // Once known, compare it even while invalid, consumed, or reset.
      if ((^golden_read_data) !== 1'bx) begin
        if (read_data !== golden_read_data)
          $fatal(1, "DESCRIPTOR_EQUIVALENCE_PAYLOAD_FAIL");
        compared_reads = compared_reads + 1;
      end
    end
  end
  always @(negedge read_clk) begin
    reader_cycles = reader_cycles + 1;
    if (automatic_reader) read_ready = (reader_cycles % 7) < 5;
  end

  task automatic reset_epoch;
    begin
      @(negedge write_clk);
      write_valid = 0;
      automatic_reader = 0;
      read_ready = 0;
      write_resetn = 0;
      read_resetn = 0;
      // Both resets assert together; exercise either legal release ordering.
      #250;
      if (RELEASE_READ_FIRST) begin
        @(negedge read_clk); read_resetn = 1;
        repeat (3) @(negedge write_clk);
        write_resetn = 1;
      end else begin
        @(negedge write_clk); write_resetn = 1;
        repeat (3) @(negedge read_clk);
        read_resetn = 1;
      end
      repeat (5) @(negedge write_clk);
      if (!write_ready || write_room != 3 || read_valid)
        $fatal(1, "DESCRIPTOR_RESET_EMPTY_FAIL");
    end
  endtask
  task automatic send_word(input integer n);
    begin
      @(negedge write_clk);
      write_valid = 1;
      write_data = word(n);
      @(posedge write_clk);
      while (!write_ready) @(posedge write_clk);
      @(negedge write_clk);
      write_valid = 0;
    end
  endtask
  task automatic drain(input integer target);
    begin
      @(negedge read_clk);
      automatic_reader = 1;
      while (consumed < target) @(negedge read_clk);
      automatic_reader = 0;
      read_ready = 0;
      repeat (6) @(negedge write_clk);
      if (read_valid || write_room != 3 || written != target || consumed != target)
        $fatal(1, "DESCRIPTOR_DRAIN_FAIL");
    end
  endtask

  initial begin
    $display("DESCRIPTOR_CLOCK_CONFIG write_half=%0d read_half=%0d release_read_first=%0d",
             WRITE_HALF, READ_HALF, RELEASE_READ_FIRST);
    reset_epoch();
    // Three usable slots, not four; rejected writes must not change the queue.
    for (ordinal = 0; ordinal < 3; ordinal = ordinal + 1) send_word(ordinal);
    @(negedge write_clk);
    if (write_ready || write_room != 0) $fatal(1, "DESCRIPTOR_FULL_FAIL");
    write_valid = 1;
    write_data = word(999);
    repeat (5) @(negedge write_clk);
    write_valid = 0;
    if (written != 3) $fatal(1, "DESCRIPTOR_FULL_WRITE_ACCEPTED");

    // Prefetch, stall, consume, then retain the consumed metadata while invalid.
    @(negedge read_clk); read_ready = 1;
    @(posedge read_clk); #0.2;
    while (!read_valid) begin @(posedge read_clk); #0.2; end
    @(negedge read_clk); read_ready = 0;
    retained_payload = read_data;
    repeat (8) @(negedge read_clk);
    if (!read_valid || read_data !== word(0) || consumed != 0)
      $fatal(1, "DESCRIPTOR_STALLED_PREFETCH_FAIL");
    read_ready = 1;
    @(posedge read_clk); #0.2;
    @(negedge read_clk); read_ready = 0;
    repeat (12) begin
      @(negedge read_clk);
      if (read_valid || read_data !== retained_payload || consumed != 1)
        $fatal(1, "DESCRIPTOR_CONSUMED_HOLD_FAIL");
      held_after_consumption = held_after_consumption + 1;
    end
    automatic_reader = 1;
    for (ordinal = 3; ordinal < 128; ordinal = ordinal + 1) send_word(ordinal);
    drain(128);

    // Reset a full, unpublished queue, then prove no stale descriptor escapes.
    for (ordinal = 1000; ordinal < 1003; ordinal = ordinal + 1) send_word(ordinal);
    reset_epoch();
    @(negedge read_clk); read_ready = 1;
    repeat (12) begin
      @(negedge read_clk);
      if (read_valid || consumed != 0) $fatal(1, "DESCRIPTOR_STALE_AFTER_RESET");
    end
    automatic_reader = 1;
    for (ordinal = 2000; ordinal < 2064; ordinal = ordinal + 1) send_word(ordinal);
    drain(64);
    if (total_written != 195 || total_consumed != 192 || blocked_writes < 5 ||
        compared_reads < 192 || held_after_consumption != 12)
      $fatal(1, "DESCRIPTOR_COVERAGE_FAIL");
    $display("DESCRIPTOR_STORAGE_WITNESS writes=195 reads=192 reset_discard=3 consumed_hold=12");
    $display("DESCRIPTOR_STORAGE_PASS full=1 wrap=1 stalls=1 coordinated_reset=1 queue_oracle=1 public_equivalence=1");
    $finish;
  end
  initial begin
    #1000000;
    $fatal(1, "DESCRIPTOR_TIMEOUT");
  end
endmodule
