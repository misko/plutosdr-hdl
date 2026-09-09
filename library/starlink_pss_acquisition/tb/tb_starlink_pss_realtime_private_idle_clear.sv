// Observe the existing reachable golden differential workload, without driving
// or forcing any guard state. This adds a nonvacuous private ACK/idle witness.
`timescale 1ns/1ps
module tb_starlink_pss_realtime_private_idle_clear;
  tb_starlink_pss_realtime_private_observations workload();
  integer clear_edges = 0;
  integer ack_witnesses = 0;
  reg expected_clear;
  reg nonzero_ack;
  always @(posedge workload.clk) begin
    expected_clear = workload.resetn && !workload.dut.active && !workload.new_fault;
    nonzero_ack = expected_clear && workload.dut.awaiting_ack &&
      (workload.dut.input_count != 0 || workload.dut.output_count != 0);
    #0.05;
    if (expected_clear) begin
      if ({workload.dut.input_count, workload.dut.output_count,
           workload.dut.input_complete_seen, workload.dut.frame_seen,
           workload.dut.status_seen, workload.dut.exponent_seen} !== 24'd0)
        $fatal(1, "PRIVATE_IDLE_CLEAR_MISSING");
      clear_edges = clear_edges + 1;
    end
    if (nonzero_ack) begin
      // The original workload independently checks every public ready, valid,
      // busy, commit, reason and valid-payload bit against immutable ff4229.
      ack_witnesses = ack_witnesses + 1;
      if (ack_witnesses == 1)
        $display("PRIVATE_IDLE_CLEAR_ACK_WITNESS public_golden_comparison_active=1");
    end
  end
  final begin
    if (clear_edges == 0 || ack_witnesses != 11)
      $error("PRIVATE_IDLE_CLEAR_VACUOUS edges=%0d ack_witnesses=%0d", clear_edges, ack_witnesses);
  end
endmodule
