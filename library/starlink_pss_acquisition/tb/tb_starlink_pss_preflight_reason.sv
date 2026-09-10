`timescale 1ns/1ps
// Isolated unpublished preflight phase; actual-core wrapper suite separately
// proves no emitted start/config/read and the descriptor/bank ownership lease.
module tb_starlink_pss_preflight_reason;
  parameter integer MUTATE_REASON = 0;
  reg clk = 0, resetn = 0, job_valid = 0, preflight_fault = 0;
  reg frame_event = 0, status_valid = 0, output_valid = 0;
  reg input_beat = 0, input_complete = 0;
  wire [1:0] ready, valid, private_valid, commit_valid, busy, commit, fault;
  wire [7:0] reasons [0:1];
  integer phase, first_event, next_event, row = 0, ready_differences = 0;
  genvar g;
  generate for (g = 0; g < 2; g = g + 1) begin : guards
    starlink_pss_realtime_result_guard #(.USE_PREFLIGHT_REASON_ONLY(g)) dut (
      .clk(clk), .resetn(resetn), .job_valid(job_valid), .job_ready(ready[g]),
      .job_descriptor(70'h12340), .input_bank_reserved(1'b1), .output_bank_reserved(1'b1),
      .certified_input_beat(input_beat), .certified_input_complete(input_complete),
      .final_fence_certified(1'b0), .external_fault_now(g == 0 ? preflight_fault : 1'b0),
      .phase_input_fault_now(1'bz), .completed_input_certified(1'bz), .completed_input_fault_now(1'bz),
      .preflight_fault_evidence_now(g == 1 && !MUTATE_REASON ? preflight_fault : 1'b0),
      .core_event_frame_started(frame_event), .core_output_tdata(48'b0),
      .core_output_tuser(24'b0), .core_output_tvalid(output_valid), .core_output_tlast(1'b0),
      .core_status_tdata(8'b0), .core_status_tvalid(status_valid),
      .mailbox_input_valid(valid[g]), .mailbox_private_valid(private_valid[g]),
      .mailbox_commit_valid(commit_valid[g]), .mailbox_input_ready(1'b1),
      .mailbox_input_fault(1'b0), .mailbox_input_data(), .mailbox_input_position(),
      .mailbox_input_last(), .mailbox_input_metadata(), .busy(busy[g]),
      .commit_pulse(commit[g]), .protocol_fault(fault[g]), .fault_reasons(reasons[g])
    );
  end endgenerate
  task automatic check_public;
    begin
      if ({valid[0], private_valid[0], commit_valid[0], busy[0], commit[0], fault[0], reasons[0]} !==
          {valid[1], private_valid[1], commit_valid[1], busy[1], commit[1], fault[1], reasons[1]})
        $fatal(1, "PREFLIGHT_REASON_MISMATCH phase=%0d first=%0d next=%0d reference=%h candidate=%h",
          phase, first_event, next_event, reasons[0], reasons[1]);
      if (|valid || |private_valid || |commit_valid || |commit)
        $fatal(1, "preflight published without completed input");
      if (ready[0] !== ready[1]) begin
        if (!preflight_fault || ready[0] || !ready[1]) $fatal(1, "unexpected private readiness difference");
        ready_differences = ready_differences + 1;
      end
    end
  endtask
  task automatic tick;
    begin #2; check_public(); clk = 1; #1; check_public(); clk = 0; #1; end
  endtask
  task automatic set_event(input integer event_kind);
    begin
      status_valid = event_kind == 1; frame_event = event_kind == 2;
      output_valid = event_kind == 3; input_beat = event_kind == 4;
      input_complete = event_kind == 5;
    end
  endtask
  initial begin
    for (phase = 0; phase < 3; phase = phase + 1)
    for (first_event = 0; first_event < 6; first_event = first_event + 1)
    for (next_event = 0; next_event < 6; next_event = next_event + 1) begin
      resetn = 0; preflight_fault = 0; job_valid = 0; set_event(0); tick();
      resetn = 1; tick();
      if (phase == 2) begin job_valid = 1; tick(); job_valid = 0; end
      job_valid = phase == 1; preflight_fault = 1; set_event(first_event); tick();
      if (!fault[1] || !reasons[1][0]) $fatal(1, "preflight bit0 missing on original fault edge");
      preflight_fault = 0; job_valid = 0; set_event(next_event); tick();
      set_event(0); tick(); tick();
      if (busy[1] || ready[1]) $fatal(1, "preflight quarantine resumed without epoch reset");
      row = row + 1;
    end
    if (!ready_differences) $fatal(1, "no private admission difference witnessed");
    $display("PREFLIGHT_REASON_ONLY_PASS rows=%0d phases=3 event_kinds=6 exact_reasons=1 private_ready_differences=%0d", row, ready_differences);
    $finish;
  end
endmodule
