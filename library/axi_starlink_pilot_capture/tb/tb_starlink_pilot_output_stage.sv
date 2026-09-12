// SPDX-License-Identifier: GPL-2.0
// Isolate the output register/admission boundary with a controllable DDC beat.
// Full DDC numerics and real AXI command execution are tested separately.
`timescale 1ns/1ps
module tb_starlink_pilot_output_stage;
  reg clk = 0;
  always #5 clk = !clk;
  reg resetn = 0, gap = 0, flush = 0, ready = 0;
  reg source_valid = 0;
  reg [63:0] source_index = 42;
  reg beat_valid = 0, beat_support = 1, halted = 0;
  reg [63:0] beat_index = 64'h8000000000000200;
  reg [31:0] beat_visit = 17, beat_data = 32'h8abc1234;
  wire signed [15:0] beat_i = beat_data[15:0], beat_q = beat_data[31:16];
  wire valid;
  wire [31:0] data;
  axi_starlink_pilot_capture dut (
    .s_axi_aclk(clk), .s_axi_aresetn(resetn),
    .s_axi_awvalid(1'b0), .s_axi_awaddr(8'd0), .s_axi_wdata(32'd0),
    .s_axi_wstrb(4'd0), .s_axi_wvalid(1'b0), .s_axi_bready(1'b1),
    .s_axi_arvalid(1'b0), .s_axi_araddr(8'd0), .s_axi_rready(1'b1),
    .s_axi_awprot(3'd0), .s_axi_arprot(3'd0),
    .canonical_valid(source_valid), .canonical_gap(gap), .canonical_flush(flush),
    .canonical_i(16'd0), .canonical_q(16'd0), .canonical_index(source_index),
    .m_axis_tvalid(valid), .m_axis_tdata(data), .m_axis_tready(ready)
  );
  integer scenario;
  reg [31:0] expected_fault;
  reg seed_full;
  task automatic tick;
    begin @(posedge clk); #1; @(negedge clk); end
  endtask
  initial begin
    force dut.ddc_valid = beat_valid;
    force dut.ddc_support = beat_support;
    force dut.ddc_halted = halted;
    force dut.ddc_i = beat_i;
    force dut.ddc_q = beat_q;
    force dut.ddc_index = beat_index;
    force dut.ddc_visit = beat_visit;
    for (scenario = 0; scenario < 19; scenario = scenario + 1) begin
      release dut.stop_request;
      release dut.write_pending;
      resetn = 0; gap = 0; flush = 0; ready = 0; halted = 0;
      beat_valid = 0; beat_support = 1; beat_visit = 17;
      seed_full = 0;
      beat_index = 64'h8000000000000200; beat_data = 32'h8abc1234;
      tick(); tick();
      resetn = 1;
      // Reachability of ARM/config and command timing is covered by the AXI
      // integration bench. Seed one active observation for this boundary test.
      dut.active = 1; dut.used = 1; dut.visit_id = 17;
      beat_valid = 1;
      tick();
      if (!dut.capture_valid || dut.admitted != 0 || valid)
        $fatal(1, "DDC output bypassed the one-clock observation register");
      beat_valid = 0;
      tick();
      if (dut.admitted != 1 || !valid || data !== 32'h8abc1234 ||
          dut.first_index !== beat_index || dut.last_index !== beat_index)
        $fatal(1, "first coherent observation missing");

      // Stage the next word while the previously promised AXIS beat stalls.
      beat_index = beat_index + 6; beat_data = 32'hfedc5678; beat_valid = 1;
      if (scenario == 4 || scenario == 12) beat_index = beat_index + 1;
      if (scenario == 5) beat_visit = 18;
      if (scenario == 8 || scenario == 13) beat_support = 0;
      tick();
      beat_valid = 0;
      expected_fault = 0;
      case (scenario)
        0: force dut.stop_request = 1;
        1: begin gap = 1; expected_fault = 2; end
        2: begin flush = 1; expected_fault = 16; end
        3: begin halted = 1; expected_fault = 1; end
        4, 5: expected_fault = 8;
        6: begin force dut.write_pending = 1; expected_fault = 32; end
        7: begin seed_full = 1; expected_fault = 4; end
        8: begin dut.unsupported = 64'hffffffffffffffff; expected_fault = 64; end
        9: begin dut.admitted = 64'hffffffffffffffff; expected_fault = 64; end
        10: begin dut.sample_limit = 2; gap = 1; expected_fault = 2; end
        11: begin force dut.stop_request = 1; seed_full = 1; end
        12: force dut.stop_request = 1;
        13: begin force dut.stop_request = 1; dut.unsupported = 64'hffffffffffffffff; end
        14: begin force dut.stop_request = 1; dut.admitted = 64'hffffffffffffffff; end
        15: begin gap = 1; seed_full = 1; expected_fault = 2; end
        16: begin flush = 1; seed_full = 1; expected_fault = 16; end
        17: begin halted = 1; seed_full = 1; expected_fault = 1; end
        18: begin force dut.write_pending = 1; seed_full = 1; expected_fault = 32; end
      endcase
      if (seed_full) dut.fifo_count = 32;
      #1;
      if (dut.push) $fatal(1, "termination admitted staged word case=%0d", scenario);
      tick();
      if (dut.active || dut.faults !== expected_fault || !valid || data !== 32'h8abc1234)
        $fatal(1, "termination lost fault or changed AXIS promise case=%0d fault=%h",
               scenario, dut.faults);
      if (scenario != 9 && scenario != 14 && dut.admitted != 1)
        $fatal(1, "termination changed admitted count case=%0d", scenario);
      if (expected_fault != 0 && dut.lost_index !== beat_index)
        $fatal(1, "fault index detached from rejected observation case=%0d", scenario);
      if ((scenario == 8 || scenario == 13) && dut.unsupported !== 64'hffffffffffffffff)
        $fatal(1, "unsupported counter wrapped");
      if ((scenario == 9 || scenario == 14) && dut.admitted !== 64'hffffffffffffffff)
        $fatal(1, "admitted counter wrapped");
      // No unpromised staged word may leak after STOP/fault; queued data is
      // still drainable. Full-FIFO scenario deliberately seeded occupancy only.
      tick();
      if (dut.capture_valid || dut.push || data !== 32'h8abc1234)
        $fatal(1, "terminated observation was replayed");
      if (!seed_full) begin
        ready = 1; tick();
        if (valid || dut.delivered != 1 || dut.fifo_count != 0)
          $fatal(1, "promised word did not drain after termination");
      end
    end
    // A newly discovered internal DDC fault may coincide with admission of a
    // valid EARLIER staged prefix. Exercise the final finite word specifically:
    // capture can finish before observing registered DDC halt, but the real DDC
    // sticky fault must survive automatic source flush and invalidate evidence.
    release dut.stop_request; release dut.write_pending; release dut.ddc_halted;
    resetn = 0; gap = 0; flush = 0; ready = 0; beat_valid = 0;
    beat_support = 1; beat_visit = 17;
    beat_index = 540; beat_data = 32'h8abc1234;
    tick(); tick(); resetn = 1;
    dut.active = 1; dut.used = 1; dut.visit_id = 17; dut.sample_limit = 2;
    beat_valid = 1; tick();
    beat_index = 546; beat_data = 32'hfedc5678; tick();
    beat_valid = 0; source_valid = 1; source_index = 64'hffffffffffffffff;
    #1;
    if (dut.g_pilot_ddc.ddc.run || !dut.push) $fatal(1, "internal fault/final-prefix fixture missed edge");
    tick(); source_valid = 0;
    if (dut.active || dut.admitted != 2 || dut.faults != 0 || dut.ddc_fault != 1)
      $fatal(1, "final admission hid real DDC input-index fault");
    tick(); tick();
    if (dut.ddc_fault != 1 || dut.ddc_halted)
      $fatal(1, "automatic flush cleared sticky DDC fault evidence");
    ready = 1; tick();
    if (!valid || data !== 32'hfedc5678) $fatal(1, "valid staged prefix was corrupted");
    tick();
    if (valid || dut.delivered != 2 || dut.ddc_fault != 1)
      $fatal(1, "drain lost final word or terminal DDC fault evidence");
    scenario = scenario + 1;
    $display("PILOT_OUTPUT_STAGE_PASS cases=%0d latency_clocks=1", scenario);
    $finish;
  end
  initial begin #100000; $fatal(1, "stage test timeout"); end
endmodule
