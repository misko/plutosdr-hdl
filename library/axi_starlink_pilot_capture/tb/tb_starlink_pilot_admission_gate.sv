// Finite combinational equivalence check of the actual PIL1 admission gates.
// Clock stays low: vary registered command/state and staged DDC outputs without
// assuming reachable FIFO/fault combinations. Temporal behavior is tested by
// tb_starlink_pilot_capture, including live STOP and malformed AXI writes.
`timescale 1ns/1ps
module tb_starlink_pilot_admission_gate;
  reg input_flush = 0, input_gap = 0, ready = 0;
  reg test_valid = 0, test_support = 0, test_halted = 0;
  reg [63:0] test_index = 0;
  reg [31:0] test_visit = 0;
  axi_starlink_pilot_capture dut (
    .s_axi_aclk(1'b0), .s_axi_aresetn(1'b1),
    .s_axi_awvalid(1'b0), .s_axi_awaddr(8'd0), .s_axi_wdata(32'd0),
    .s_axi_wstrb(4'd0), .s_axi_wvalid(1'b0), .s_axi_bready(1'b1),
    .s_axi_arvalid(1'b0), .s_axi_araddr(8'd0), .s_axi_rready(1'b1),
    .s_axi_awprot(3'd0), .s_axi_arprot(3'd0),
    .canonical_valid(1'b0), .canonical_gap(input_gap),
    .canonical_flush(input_flush), .canonical_i(16'd0),
    .canonical_q(16'd0), .canonical_index(64'd0), .m_axis_tready(ready)
  );
  integer state, command, data_case, boundary, checked = 0, pushed = 0;
  reg old_running, old_push, old_source;
  initial begin
    force dut.capture_valid = test_valid;
    force dut.capture_support = test_support;
    force dut.ddc_halted = test_halted;
    force dut.capture_index = test_index;
    force dut.capture_visit = test_visit;
    // 32 lifecycle states x 8 command choices x 256 data/fault combinations
    // x 4 counter/FIFO boundaries = 262144 independent settled comparisons.
    for (state = 0; state < 32; state = state + 1) begin
      for (command = 0; command < 8; command = command + 1) begin
        for (data_case = 0; data_case < 256; data_case = data_case + 1) begin
          for (boundary = 0; boundary < 4; boundary = boundary + 1) begin
            dut.active = state[0];
            dut.used = state[1];
            dut.faults = state[2] ? 32'hffffffff : 0;
            dut.visit_id = state[3] ? 17 : 0;
            dut.fifo_count = state[4] ? (boundary[0] ? 32 : 1) : 0;
            dut.rd_pointer = 0;
            dut.write_pending = command != 0;
            dut.arm_request = command == 1;
            dut.stop_request = command == 2;
            dut.clear_request = command == 3;
            dut.snapshot_request = command == 4;
            dut.visit_request = command == 5;
            dut.limit_request = command == 6;
            // command 7 is a fully decoded but unsupported write.
            test_valid = data_case[0];
            test_support = data_case[1];
            test_halted = data_case[2];
            input_flush = data_case[3];
            input_gap = data_case[4];
            ready = data_case[5];
            dut.admitted = boundary == 0 ? 0 : (boundary == 3 ? 64'hffffffffffffffff : 1);
            dut.delivered = boundary[1] ? 64'hffffffffffffffff : 0;
            dut.unsupported = boundary[1] ? 64'hffffffffffffffff : 0;
            dut.last_index = boundary == 2 ? 64'hfffffffffffffffa : 600;
            test_index = data_case[6] ? 607 : 606;
            test_visit = data_case[7] ? 18 : dut.visit_id;
            #1;
            old_running = dut.active && dut.faults_now == 0 && !dut.stop_request;
            old_push = dut.eligible && dut.faults_now == 0 && !dut.stop_request;
            old_source = dut.active && !dut.stop_request && !input_flush && !dut.bad_write;
            if (dut.running !== old_running || dut.push !== old_push || dut.source_run !== old_source)
              $fatal(1, "PIL1 gate mismatch state=%0d command=%0d data=%0d boundary=%0d",
                     state, command, data_case, boundary);
            if (dut.push) pushed = pushed + 1;
            checked = checked + 1;
          end
        end
      end
    end
    if (pushed == 0 || pushed == checked) $fatal(1, "vacuous admission comparison");
    $display("PILOT_ADMISSION_GATE_EQUIVALENCE_PASS checked=%0d pushed=%0d", checked, pushed);
    $finish;
  end
endmodule
