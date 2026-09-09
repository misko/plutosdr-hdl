`timescale 1ns/1ps
// Public interfaces only. Used with frozen/current RTL or two actual netlists.
module tb_pilot_snapshot_replication;
  reg clk = 0;
  always #5 clk = !clk;
  reg resetn = 0, awvalid = 0, wvalid = 0, arvalid = 0;
  reg [7:0] awaddr = 0, araddr = 0;
  reg [31:0] wdata = 0;
  reg [3:0] wstrb = 15;
  wire [1:0] awready, wready, bvalid, arready, rvalid, enabled, valid, irq;
  wire [1:0] bresp [0:1], rresp [0:1];
  wire [31:0] rdata [0:1], data [0:1];
  reg input_valid = 0, input_gap = 0, input_flush = 0;
  reg [63:0] input_index = 0;
  reg [31:0] input_data = 0;
  reg permit_output = 1;
  integer cycles = 0, delivered = 0, snapshots = 0, reads = 0;
  always @(negedge clk) cycles = cycles + 1;
  wire ready = permit_output && cycles % 31 > 4;
`define PILOT_CONNECT(N) \
    .s_axi_aclk(clk), .s_axi_aresetn(resetn), \
    .s_axi_awvalid(awvalid), .s_axi_awaddr(awaddr), .s_axi_awready(awready[N]), \
    .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid), \
    .s_axi_wready(wready[N]), .s_axi_bvalid(bvalid[N]), .s_axi_bresp(bresp[N]), .s_axi_bready(1'b1), \
    .s_axi_arvalid(arvalid), .s_axi_araddr(araddr), .s_axi_arready(arready[N]), \
    .s_axi_rvalid(rvalid[N]), .s_axi_rdata(rdata[N]), .s_axi_rresp(rresp[N]), .s_axi_rready(1'b1), \
    .s_axi_awprot(3'd0), .s_axi_arprot(3'd0), \
    .canonical_valid(input_valid), .canonical_gap(input_gap), .canonical_flush(input_flush), \
    .canonical_i(input_data[15:0]), .canonical_q(input_data[31:16]), .canonical_index(input_index), \
    .pilot_enable(enabled[N]), .m_axis_tvalid(valid[N]), .m_axis_tdata(data[N]), .m_axis_tready(ready), .irq(irq[N])
  pilot_snapshot_baseline baseline (`PILOT_CONNECT(0));
  pilot_snapshot_replicated candidate (`PILOT_CONNECT(1));
`undef PILOT_CONNECT

  task automatic fail(input string reason);
    $display("PILOT_SNAPSHOT_EQ_FAIL %s cycle=%0d", reason, cycles);
    $fatal(1, "%s", reason);
  endtask
  reg stalled = 0;
  reg [31:0] held;
  always @(posedge clk) begin
    // Check the promised beat before this edge can consume it; after the
    // edge a newly-ready consumer is allowed to advance the FIFO output.
    if (resetn && stalled && (!valid[0] || data[0] !== held)) fail("AXIS promise changed");
    if (resetn && valid[0] && ready) delivered = delivered + 1;
    // Vendor functional FFs have a 100 ps update; compare within the same
    // cycle after it, not at that update instant. This is not timing simulation.
    #1;
    if (resetn) begin
      if ((^{awready[0], wready[0], bvalid[0], bresp[0], arready[0],
             rvalid[0], rresp[0], enabled[0], valid[0], irq[0]}) === 1'bx)
        fail("unknown public control");
      if ({awready[0], wready[0], bvalid[0], bresp[0], arready[0], rvalid[0],
           rresp[0], enabled[0], valid[0], irq[0]} !==
          {awready[1], wready[1], bvalid[1], bresp[1], arready[1], rvalid[1],
           rresp[1], enabled[1], valid[1], irq[1]}) fail("public control differs");
      if (rvalid[0] && rdata[0] !== rdata[1]) fail("AXI snapshot/read data differs");
      if (rvalid[0] && (^rdata[0]) === 1'bx) fail("unknown AXI data");
      if (valid[0] && data[0] !== data[1]) fail("promised pilot data differs");
      if (valid[0] && (^data[0]) === 1'bx) fail("unknown promised pilot data");
    end
    stalled = resetn && valid[0] && !ready;
    held = data[0];
  end
  task automatic write_reg(input [7:0] address, input [31:0] value);
    @(negedge clk); awaddr = address; awvalid = 1;
    do @(posedge clk); while (!awready[0]);
    @(negedge clk); awvalid = 0;
    repeat(3) @(negedge clk);
    wdata = value; wvalid = 1;
    do @(posedge clk); while (!wready[0]);
    @(negedge clk); wvalid = 0;
    do @(posedge clk); while (!bvalid[0]);
    if (bresp[0] != 0) fail("AXI write response");
    @(negedge clk);
  endtask
  task automatic read_reg(input [7:0] address, output [31:0] value);
    @(negedge clk); araddr = address; arvalid = 1;
    do @(posedge clk); while (!arready[0]);
    @(negedge clk); arvalid = 0;
    do @(posedge clk); while (!rvalid[0]);
    if (rresp[0] != 0) fail("AXI read response");
    value = rdata[0]; reads = reads + 1;
    @(negedge clk);
  endtask
  task automatic snapshot;
    reg [31:0] word, saved;
    write_reg(8'h08, 8);
    snapshots = snapshots + 1;
    for (integer n = 0; n < 26; n = n + 1) read_reg(8'h30 + 4*n, word);
    read_reg(8'h40, saved);
    repeat(30) @(negedge clk);
    read_reg(8'h40, word);
    if (saved !== word) fail("snapshot followed live counter");
  endtask
  task automatic source(input integer count, input [63:0] first);
    for (integer n = 0; n < count; n = n + 1) begin
      repeat(n % 3 == 0 ? 5 : 6) @(negedge clk);
      input_valid = 1; input_index = first + n;
      input_data = {16'((n*17)%2000), 16'((n*23)%1900)};
      @(negedge clk); input_valid = 0;
    end
  endtask
  task automatic start_capture(input integer visit);
    write_reg(8'h08, 4); write_reg(8'h20, visit); write_reg(8'h08, 1);
  endtask
  reg [31:0] word;
  integer first_delivered;
  initial begin
    // Hold past the global startup reset in vendor functional simulation.
    repeat(20) @(negedge clk); resetn = 1;
    read_reg(0, word); if (word != 32'h50494c31) fail("identity");
    for (integer n = 0; n < 26; n = n + 1) begin
      read_reg(8'h30 + 4*n, word); if (word != 0) fail("reset snapshot");
    end
    start_capture(17);
    fork
      source(3600, 0);
      begin
        repeat(8) begin repeat(180) @(negedge clk); snapshot(); end
      end
    join
    repeat(200) @(negedge clk); write_reg(8'h08, 2); snapshot();
    read_reg(8'h10, word); if (word != 0) fail("healthy capture fault");
    if (delivered < 400) fail("insufficient real pilot output");
    first_delivered = delivered;
    read_reg(8'h98, word); if (word != 9) fail("snapshot generation");
    read_reg(8'h48, word); if (word != delivered) fail("delivered snapshot");

    start_capture(18); permit_output = 0;
    source(1200, 64'hffffff00);
    repeat(200) @(negedge clk); snapshot();
    read_reg(8'h10, word); if (word != 4 || !irq[0]) fail("overflow fault missing");
    permit_output = 1; repeat(300) @(negedge clk); snapshot();
    if (delivered != first_delivered + 32) fail("overflow prefix not drained");
    write_reg(8'h08, 4);
    for (integer n = 0; n < 26; n = n + 1) begin
      read_reg(8'h30 + 4*n, word); if (word != 0) fail("CLEAR snapshot");
    end
    read_reg(8'h98, word); if (word != 0) fail("CLEAR generation");
    start_capture(19); source(700, 64'h100000005);
    write_reg(8'h08, 4); snapshot();
    read_reg(8'h10, word); if (word != 32) fail("active CLEAR fault missing");
    @(negedge clk); resetn = 0; repeat(8) @(negedge clk); resetn = 1;
    read_reg(8'h98, word); if (word != 0) fail("new reset epoch");
    $display("PILOT_SNAPSHOT_EQ_PASS cycles=%0d snapshots=%0d reads=%0d pilot_samples=%0d no_receiver_timing_or_hardware_claim=1", cycles, snapshots, reads, delivered);
    $finish;
  end
  initial begin
    repeat(100000) @(posedge clk);
    fail("watchdog");
  end
endmodule
