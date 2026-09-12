// SPDX-License-Identifier: GPL-2.0
// Real AXI helper + capture + DDC. Seed otherwise expensive terminal states,
// but send every control transaction through AXI, including rejection races.
`timescale 1ns/1ps
module tb_starlink_pilot_clear_commit;
  parameter integer SCENARIO = 0;
  reg clk = 0;
  always #5 clk = !clk;
  reg resetn = 0, awvalid = 0, wvalid = 0, arvalid = 0, bready = 0;
  reg [7:0] awaddr = 8, araddr = 8'h98;
  reg [31:0] wdata = 4;
  wire awready, wready, bvalid, arready, rvalid;
  wire [31:0] rdata, data;
  wire [1:0] bresp, rresp;
  reg source_valid = 0, gap = 0, flush = 0, ready = 0;
  wire valid, enabled, irq;
  axi_starlink_pilot_capture dut (
    .s_axi_aclk(clk), .s_axi_aresetn(resetn),
    .s_axi_awvalid(awvalid), .s_axi_awaddr(awaddr), .s_axi_awready(awready),
    .s_axi_wvalid(wvalid), .s_axi_wdata(wdata), .s_axi_wstrb(4'hf), .s_axi_wready(wready),
    .s_axi_bvalid(bvalid), .s_axi_bresp(bresp), .s_axi_bready(bready),
    .s_axi_arvalid(arvalid), .s_axi_araddr(araddr), .s_axi_arready(arready),
    .s_axi_rvalid(rvalid), .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rready(1'b1),
    .s_axi_awprot(3'd0), .s_axi_arprot(3'd0),
    .canonical_valid(source_valid), .canonical_gap(gap), .canonical_flush(flush),
    .canonical_i(16'sd123), .canonical_q(-16'sd456), .canonical_index(64'd9000),
    .pilot_enable(enabled), .m_axis_tvalid(valid), .m_axis_tdata(data),
    .m_axis_tready(ready), .irq(irq)
  );

  integer commits = 0, admits = 0, rejected = 0, pops = 0, n;
  reg expected_clear = 0;
  reg [31:0] popped_data;
  always @(posedge clk) begin
    if (!resetn) begin
      expected_clear <= 0;
      commits = 0; admits = 0; rejected = 0; pops = 0;
    end else begin
      if (dut.clear_ok !== expected_clear) $fatal(1, "CLEAR token not exactly one clock");
      expected_clear <= dut.clear_admit;
      if (dut.clear_admit) begin
        admits = admits + 1;
        if (dut.bad_write || dut.wack || !dut.g_pilot_ddc.ddc.resetn)
          $fatal(1, "accepted CLEAR rejected, acknowledged or reset before commit");
      end
      if (dut.clear_ok) begin
        commits = commits + 1;
        if (dut.active || !dut.empty || dut.write_pending || dut.g_pilot_ddc.ddc.resetn || bvalid)
          $fatal(1, "CLEAR commit not isolated quiescent execution");
      end
      if (dut.clear_request && !dut.clear_admit) begin
        rejected = rejected + 1;
        if (!dut.bad_write || !dut.g_pilot_ddc.ddc.resetn) $fatal(1, "invalid CLEAR did not reject immediately");
      end
      if (valid && ready) begin
        pops = pops + 1;
        popped_data = data;
      end
    end
  end

  task automatic launch_write(input [7:0] address, input [31:0] value);
    begin
      @(negedge clk); awaddr = address; wdata = value; awvalid = 1; wvalid = 1;
      do @(posedge clk); while (!(awready && wready));
      @(negedge clk); awvalid = 0; wvalid = 0;
    end
  endtask
  task automatic wait_request;
    begin while (!dut.write_pending) @(negedge clk); end
  endtask
  task automatic finish_write;
    begin
      while (!bvalid) @(negedge clk);
      if (bresp != 0) $fatal(1, "unexpected AXI response");
      bready = 1;
      @(negedge clk); bready = 0;
    end
  endtask
  task automatic read_register(input [7:0] address, input [31:0] expected);
    begin
      @(negedge clk); araddr = address; arvalid = 1;
      do @(posedge clk); while (!arready);
      @(negedge clk); arvalid = 0;
      while (!rvalid) @(negedge clk);
      if (rdata !== expected || rresp != 0)
        $fatal(1, "read %h got %h expected %h", address, rdata, expected);
      @(negedge clk);
    end
  endtask
  task automatic seed_terminal;
    begin
      dut.visit_id = 17; dut.sample_limit = 300000; dut.used = 1;
      dut.faults = 2; dut.admitted = 3; dut.delivered = 3;
      dut.unsupported = 90; dut.first_index = 64'h800000000000021c;
      dut.last_index = 64'h8000000000000228; dut.lost_index = 9000;
      dut.fifo_high_water = 3; dut.snapshot_generation = 19;
      for (n = 0; n < 26; n = n + 1) dut.snapshot[n] = 32'h80000000 + n;
      dut.g_pilot_ddc.ddc.accepted_sample_count = 560; dut.g_pilot_ddc.ddc.emitted_sample_count = 94;
      dut.g_pilot_ddc.ddc.saturation_event_count = 7; dut.g_pilot_ddc.ddc.fifo_high_water = 5;
      dut.g_pilot_ddc.ddc.sticky_fault = 8'h81;
    end
  endtask
  task automatic assert_cleared;
    begin
      if (dut.active || dut.used || dut.faults || dut.admitted || dut.delivered ||
          dut.unsupported || dut.first_index || dut.last_index || dut.lost_index ||
          dut.fifo_count || dut.fifo_high_water || dut.capture_valid ||
          dut.snapshot_generation || dut.ddc_accepted || dut.ddc_emitted ||
          dut.ddc_clips || dut.ddc_high_water || dut.ddc_fault || dut.ddc_halted)
        $fatal(1, "CLEAR did not reset capture, snapshot and DDC together");
      for (n = 0; n < 26; n = n + 1)
        if (dut.snapshot[n] != 0) $fatal(1, "stale snapshot word %0d", n);
      if (dut.visit_id != 17 || dut.sample_limit != 300000)
        $fatal(1, "CLEAR changed configured payload");
    end
  endtask

  initial begin
    repeat (4) @(negedge clk);
    resetn = 1;
    @(negedge clk); seed_terminal();
    case (SCENARIO)
      0, 1, 2: begin
        // Inactive source/gap/flush and an old registered DDC halt cannot
        // manufacture activity or prevent an otherwise legal recovery CLEAR.
        if (SCENARIO == 1) begin source_valid = 1; gap = 1; flush = 1; end
        launch_write(8, 4); wait_request();
        if (SCENARIO == 2) begin dut.g_pilot_ddc.ddc.halted = 1; dut.capture_valid = 1; end
        if (!dut.clear_admit || dut.clear_ok) $fatal(1, "wrong CLEAR eligibility");
        @(posedge clk); #1;
        if (!dut.clear_ok || dut.wack || dut.snapshot_generation != 19 ||
            dut.admitted != 3 || dut.ddc_accepted != 560)
          $fatal(1, "state or ACK changed at admission instead of commit");
        @(posedge clk); #1;
        assert_cleared();
        if (!dut.wack || dut.clear_ok || commits != 1 || admits != 1)
          $fatal(1, "CLEAR did not commit/ack exactly once");
        finish_write(); read_register(8'h98, 0);
        launch_write(8, 8); finish_write(); read_register(8'h98, 1);
      end
      3, 4, 5: begin
        // 3: active rejection; 4: stalled queued promise; 5: final pop on
        // the eligibility edge still rejects based on pre-edge nonempty.
        dut.faults = 0;
        if (SCENARIO == 3) dut.active = 1;
        else begin
          dut.fifo_count = 1; dut.fifo[0] = 32'h1234abcd;
          dut.admitted = 1; dut.delivered = 0;
        end
        launch_write(8, 4); wait_request();
        if (SCENARIO == 5) ready = 1;
        if (dut.clear_admit || !dut.bad_write) $fatal(1, "invalid CLEAR admitted");
        @(posedge clk); #1;
        if (!dut.wack || dut.clear_ok || dut.active || dut.faults != 32 ||
            dut.snapshot_generation != 19 || dut.ddc_accepted != 560)
          $fatal(1, "invalid CLEAR changed rejection edge or reset evidence");
        finish_write();
        if (admits || commits || rejected != 1) $fatal(1, "rejected CLEAR committed later");
        if (SCENARIO == 4) begin
          if (!valid || data != 32'h1234abcd || dut.delivered != 0)
            $fatal(1, "invalid CLEAR discarded stalled AXIS promise");
          ready = 1; @(negedge clk);
        end
        if (SCENARIO != 3 && (pops != 1 || popped_data != 32'h1234abcd ||
            dut.delivered != 1 || dut.fifo_count != 0))
          $fatal(1, "drain/rejection boundary lost or repeated promised data");
        launch_write(8, 4); finish_write(); assert_cleared();
      end
      6: begin
        // Last queued word drains on the preceding decode edge: accept.
        launch_write(8, 4);
        while (!dut.wreq) @(negedge clk);
        dut.fifo_count = 1; dut.fifo[0] = 32'h98765432; ready = 1;
        wait_request();
        if (!dut.clear_admit || pops != 1) $fatal(1, "preceding drain was not eligible");
        finish_write(); assert_cleared();
        if (pops != 1 || popped_data != 32'h98765432 || commits != 1 || rejected)
          $fatal(1, "preceding drain/CLEAR accounting changed");
      end
      7: begin
        // Reset between acceptance and commit cancels the outstanding AXI
        // operation and its token; it must not ACK a later transaction.
        launch_write(8, 4); wait_request();
        @(posedge clk); #1;
        if (!dut.clear_ok || dut.wack) $fatal(1, "reset fixture missed admission");
        @(negedge clk); resetn = 0;
        repeat (3) @(negedge clk);
        if (dut.clear_ok || dut.wack || bvalid) $fatal(1, "reset retained pending CLEAR/ACK");
        resetn = 1;
        @(negedge clk); seed_terminal();
        launch_write(8, 4); finish_write(); assert_cleared();
        if (commits != 1 || admits != 1) $fatal(1, "reset leaked or lost CLEAR token");
      end
      8: begin
        // Read and write channels are independent. A concurrently launched
        // read latches the old generation before CLEAR commits, not a promise
        // that reads are serialized behind an outstanding control write.
        fork
          read_register(8'h98, 19);
          begin launch_write(8, 4); finish_write(); end
        join
        assert_cleared(); read_register(8'h98, 0);
      end
      9: begin
        launch_write(8, 4);
        while (!bvalid) @(negedge clk);
        assert_cleared();
        // Offer the next payload throughout BVALID backpressure. The helper
        // must neither overwrite CLEAR's held payload nor issue it twice.
        awaddr = 8'h20; wdata = 23; awvalid = 1; wvalid = 1;
        repeat (8) begin
          @(negedge clk);
          if (!bvalid || awready || wready || dut.wreq || dut.wdata != 4 ||
              commits != 1 || dut.visit_id != 17)
            $fatal(1, "BVALID stall admitted a new payload or repeated CLEAR");
        end
        read_register(8'h98, 0);
        finish_write();
        do @(posedge clk); while (!(awready && wready));
        @(negedge clk); awvalid = 0; wvalid = 0;
        finish_write();
        if (dut.visit_id != 23 || commits != 1 || dut.faults)
          $fatal(1, "next configuration was mixed with CLEAR payload");
      end
      10: begin
        // No host delay is required between completed STOP and CLEAR, or
        // CLEAR and rearm. Absolute source coordinates are never reset here.
        dut.active = 1; dut.faults = 0;
        launch_write(8, 2); finish_write();
        if (dut.active || dut.clear_ok || commits) $fatal(1, "STOP semantics changed");
        launch_write(8, 4); finish_write(); assert_cleared();
        launch_write(8, 1); finish_write();
        if (!dut.active || !dut.used || dut.faults || dut.ddc_fault || commits != 1)
          $fatal(1, "STOP/CLEAR/ARM back-to-back did not establish a clean epoch");
      end
      default: $fatal(1, "unknown scenario");
    endcase
    $display("PILOT_CLEAR_COMMIT_PASS scenario=%0d", SCENARIO);
    $finish(0);
  end
  initial begin
    repeat (2000) @(posedge clk);
    $fatal(1, "CLEAR transaction watchdog");
  end
endmodule
