// SPDX-License-Identifier: GPL-2.0
`timescale 1ns/1ps
module tb_starlink_pilot_capture;
  parameter integer SOURCE_RATE_MSPS = 15;
  parameter integer WATCHDOG_CYCLES = 3000000;
  reg clk = 0;
  always #5 clk = !clk;
  reg resetn = 0, awvalid = 0, wvalid = 0, arvalid = 0;
  reg [7:0] awaddr = 0, araddr = 0;
  reg [31:0] wdata = 0;
  reg [3:0] wstrb = 15;
  wire awready, wready, bvalid, arready, rvalid;
  wire [1:0] bresp, rresp;
  wire [31:0] rdata;
  reg input_valid = 0, input_gap = 0, input_flush = 0;
  reg [63:0] input_index = 0;
  reg [31:0] input_data = 0;
  reg [1:0] ready_mode = 1;
  wire ready = ready_mode == 2 ? dut.ddc_valid : ready_mode[0];
  wire valid, enabled, irq;
  wire [31:0] data;
  axi_starlink_pilot_capture #(.INPUT_RATE_MSPS(SOURCE_RATE_MSPS)) dut (
    .s_axi_aclk(clk), .s_axi_aresetn(resetn), .s_axi_awvalid(awvalid), .s_axi_awaddr(awaddr),
    .s_axi_awready(awready), .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid),
    .s_axi_wready(wready), .s_axi_bvalid(bvalid), .s_axi_bresp(bresp), .s_axi_bready(1'b1),
    .s_axi_arvalid(arvalid), .s_axi_araddr(araddr), .s_axi_arready(arready),
    .s_axi_rvalid(rvalid), .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rready(1'b1),
    .s_axi_awprot(3'd0), .s_axi_arprot(3'd0),
    .canonical_valid(input_valid), .canonical_gap(input_gap), .canonical_flush(input_flush),
    .canonical_i(input_data[15:0]), .canonical_q(input_data[31:16]), .canonical_index(input_index),
    .pilot_enable(enabled), .m_axis_tvalid(valid), .m_axis_tdata(data), .m_axis_tready(ready), .irq(irq)
  );
  reg stalled = 0;
  reg [31:0] held;
  always @(posedge clk) begin
    if (!resetn) stalled <= 0;
    else begin
      if (stalled && (!valid || data !== held)) $fatal(1, "AXIS promise changed under stall");
      stalled <= valid && !ready;
      held <= data;
      if (valid && ready) $display("OUT %08x", data);
    end
  end
  task automatic write_reg(input [7:0] address, input [31:0] value, input integer args);
    begin
      @(negedge clk); awaddr = address; awvalid = 1;
      do @(posedge clk); while (!awready);
      @(negedge clk); awvalid = 0;
      repeat(args >> 8) @(negedge clk);
      wdata = value; wstrb = args & 15; wvalid = 1;
      do @(posedge clk); while (!wready);
      @(negedge clk); wvalid = 0;
      do @(posedge clk); while (!bvalid);
      if (bresp != 0) $fatal(1, "bad write response");
      @(negedge clk);
    end
  endtask
  task automatic read_reg(input [7:0] address);
    begin
      @(negedge clk); araddr = address; arvalid = 1;
      do @(posedge clk); while (!arready);
      @(negedge clk); arvalid = 0;
      do @(posedge clk); while (!rvalid);
      if (rresp != 0) $fatal(1, "bad read response");
      $display("READ %02x %08x", address, rdata);
      @(negedge clk);
    end
  endtask
  integer fd, rc, delay_cycles, op, arg, cw_n, cw_gap, cw_phase;
  reg signed [15:0] cw_i, cw_q;
  reg [63:0] index;
  reg [31:0] value;
  initial begin
    repeat(5) @(negedge clk);
    resetn = 1;
    fd = $fopen("stimulus.txt", "r");
    if (!fd) $fatal(1, "missing stimulus");
    while (!$feof(fd)) begin
      rc = $fscanf(fd, "%d %d %h %h %d\n", delay_cycles, op, index, value, arg);
      if (rc != 5) $fatal(1, "invalid stimulus");
      repeat(delay_cycles) @(negedge clk);
      case (op)
        1: begin
          input_valid = 1; input_index = index; input_data = value;
          @(negedge clk); input_valid = 0;
        end
        2: write_reg(index[7:0], value, arg);
        3: read_reg(index[7:0]);
        4: ready_mode = value[1:0];
        5: begin input_gap = 1; @(negedge clk); input_gap = 0; end
        6: begin input_flush = 1; @(negedge clk); input_flush = 0; end
        7: ;
        8: begin resetn = 0; repeat(4) @(negedge clk); resetn = 1; end
        // Procedural canonical 15 MS/s CW, avoiding a multi-million-line
        // stimulus file for the exact 120 ms supported-output capture gate.
        9: begin
          for (cw_n = 0; cw_n < value; cw_n = cw_n + 1) begin
            cw_gap = cw_n % 3 == 0 ? 6 : 7;
            repeat(cw_gap-1) begin @(negedge clk); input_valid = 0; end
            @(negedge clk);
            input_valid = 1;
            input_index = index + cw_n;
            cw_phase = (input_index[5:0] * 12) % 64;
            cw_i = $signed(dut.ddc.mixer[cw_phase][17:0]) >>> 3;
            cw_q = (-$signed(dut.ddc.mixer[cw_phase][35:18])) >>> 3;
            input_data = {cw_q, cw_i};
          end
          @(negedge clk); input_valid = 0;
        end
        default: $fatal(1, "unknown stimulus");
      endcase
    end
    repeat(100) @(negedge clk);
    $display("FINAL %d %d", enabled, irq);
    $finish(0);
  end
  initial begin
    repeat(WATCHDOG_CYCLES) @(posedge clk);
    $fatal(1, "watchdog");
  end
endmodule
