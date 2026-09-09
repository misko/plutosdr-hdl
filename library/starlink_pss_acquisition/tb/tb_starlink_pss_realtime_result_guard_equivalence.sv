// Test-only differential regression against immutable ff4229 golden RTL.
// Public controls compare every half-cycle; payload compares only while valid.
// Private age may differ only outside an active, not-yet-quarantined job.
`timescale 1ns/1ps

`define GUARD_EQ_INPUTS \
  .clk(clk), .resetn(resetn), .job_valid(job_valid), .job_descriptor(job_descriptor), \
  .input_bank_reserved(input_bank_reserved), .output_bank_reserved(output_bank_reserved), \
  .certified_input_beat(certified_input_beat), \
  .certified_input_complete(certified_input_complete), \
  .final_fence_certified(final_fence_certified), .external_fault_now(external_fault_now), \
  .core_event_frame_started(core_event_frame_started), \
  .core_output_tdata(core_output_tdata), .core_output_tuser(core_output_tuser), \
  .core_output_tvalid(core_output_tvalid), .core_output_tlast(core_output_tlast), \
  .core_status_tdata(core_status_tdata), .core_status_tvalid(core_status_tvalid), \
  .mailbox_input_ready(mailbox_input_ready), .mailbox_input_fault(mailbox_input_fault)

module guard_equivalence_pair #(parameter integer WATCHDOG_CYCLES = 2048) (
  input wire clk, resetn, job_valid,
  input wire [69:0] job_descriptor,
  input wire input_bank_reserved, output_bank_reserved,
  input wire certified_input_beat, certified_input_complete, final_fence_certified,
  input wire external_fault_now, core_event_frame_started,
  input wire [47:0] core_output_tdata,
  input wire [23:0] core_output_tuser,
  input wire core_output_tvalid, core_output_tlast,
  input wire [7:0] core_status_tdata,
  input wire core_status_tvalid, mailbox_input_ready, mailbox_input_fault
);
  wire new_ready, old_ready, new_valid, old_valid, new_last, old_last;
  wire new_busy, old_busy, new_commit, old_commit, new_fault, old_fault;
  wire [7:0] new_reasons, old_reasons;
  wire [35:0] new_data, old_data;
  wire [8:0] new_position, old_position;
  wire [74:0] new_metadata, old_metadata;
  integer comparisons = 0;
  starlink_pss_realtime_result_guard #(.WATCHDOG_CYCLES(WATCHDOG_CYCLES)) dut (
    `GUARD_EQ_INPUTS,
    .job_ready(new_ready), .mailbox_input_valid(new_valid),
    .mailbox_input_data(new_data), .mailbox_input_position(new_position),
    .mailbox_input_last(new_last), .mailbox_input_metadata(new_metadata),
    .busy(new_busy), .commit_pulse(new_commit), .protocol_fault(new_fault),
    .fault_reasons(new_reasons)
  );
  starlink_pss_realtime_result_guard_ff4229_golden #(.WATCHDOG_CYCLES(WATCHDOG_CYCLES)) golden (
    `GUARD_EQ_INPUTS,
    .job_ready(old_ready), .mailbox_input_valid(old_valid),
    .mailbox_input_data(old_data), .mailbox_input_position(old_position),
    .mailbox_input_last(old_last), .mailbox_input_metadata(old_metadata),
    .busy(old_busy), .commit_pulse(old_commit), .protocol_fault(old_fault),
    .fault_reasons(old_reasons)
  );
  task automatic compare_public;
    begin
      comparisons = comparisons + 1;
      if ({new_ready, new_valid, new_busy, new_commit, new_fault, new_reasons} !==
          {old_ready, old_valid, old_busy, old_commit, old_fault, old_reasons})
        $fatal(1, "%m public guard control mismatch at %0t", $time);
      if (new_valid && {new_data, new_position, new_last, new_metadata} !==
                       {old_data, old_position, old_last, old_metadata})
        $fatal(1, "%m valid mailbox payload/descriptor mismatch at %0t", $time);
      if (resetn && golden.active && !old_fault && dut.age !== golden.age)
        $fatal(1, "%m healthy active watchdog age diverged at %0t", $time);
    end
  endtask
  always @(posedge clk or negedge clk or negedge resetn) begin
    #0.001;
    compare_public();
  end
endmodule

// No clock during enumeration: independently exercise every idle combination
// without letting an orphan event latch quarantine before the next truth row.
module guard_idle_truth_table(output reg done = 0);
  reg clk = 0, resetn = 1, job_valid = 0;
  reg [69:0] job_descriptor = 70'h123456789;
  reg input_bank_reserved = 0, output_bank_reserved = 0;
  reg certified_input_beat = 0, certified_input_complete = 0;
  reg final_fence_certified = 0, external_fault_now = 0, core_event_frame_started = 0;
  reg [47:0] core_output_tdata = 48'hfedcba987654;
  reg [23:0] core_output_tuser = 24'hffffff;
  reg core_output_tvalid = 0, core_output_tlast = 1;
  reg [7:0] core_status_tdata = 8'hff;
  reg core_status_tvalid = 0, mailbox_input_ready = 0, mailbox_input_fault = 0;
  integer mode, bits, rows = 0;
  reg expected_ready;
  guard_equivalence_pair pair (`GUARD_EQ_INPUTS);
  initial begin
    #0.01; resetn = 0; #0.01;
    // Reset, clean idle, and sticky-faulted idle are all tested independently.
    for (mode = 0; mode < 3; mode = mode + 1) begin
      if (mode == 1) begin resetn = 1; #0.01; end
      if (mode == 2) begin
        job_valid = 0; external_fault_now = 1;
        #0.01; clk = 1; #0.01; clk = 0;
        if (!pair.new_fault || !pair.old_fault) $fatal(1, "truth-table quarantine setup failed");
      end
      for (bits = 0; bits < 4096; bits = bits + 1) begin
        {final_fence_certified, job_valid, mailbox_input_fault, external_fault_now,
         core_output_tvalid, core_status_tvalid, core_event_frame_started,
         certified_input_complete, certified_input_beat, mailbox_input_ready,
         output_bank_reserved, input_bank_reserved} = 12'(bits);
        #0.001;
        expected_ready = mode == 1 && (&bits[2:0]) && !(|bits[9:3]);
        pair.compare_public();
        if (pair.new_ready !== expected_ready || pair.old_ready !== expected_ready ||
            pair.new_busy || pair.new_valid || pair.new_commit)
          $fatal(1, "idle truth-table mismatch mode=%0d row=%0d", mode, bits);
        rows = rows + 1;
      end
    end
    done = 1;
    $display("GUARD_IDLE_TRUTH_PASS combinations=%0d reset_clean_and_sticky=1", rows);
  end
endmodule

// Tiny watchdog settings cannot complete a512-word job. Exercise an otherwise
// clean active prefix, exact expiration edge, sticky quarantine, and reset reuse.
module guard_watchdog_equivalence #(parameter integer CYCLES = 2)(output reg done = 0);
  reg clk = 0, resetn = 0, job_valid = 0;
  always begin #2.5; if (!done) clk = !clk; end
  wire [69:0] job_descriptor = 70'h1b23456789;
  wire input_bank_reserved = 1, output_bank_reserved = 1;
  wire certified_input_beat = 0, certified_input_complete = 0;
  wire final_fence_certified = 0, external_fault_now = 0, core_event_frame_started = 0;
  wire [47:0] core_output_tdata = 0;
  wire [23:0] core_output_tuser = 0;
  wire core_output_tvalid = 0, core_output_tlast = 0;
  wire [7:0] core_status_tdata = 0;
  wire core_status_tvalid = 0, mailbox_input_ready = 1, mailbox_input_fault = 0;
  integer epoch, elapsed;
  guard_equivalence_pair #(.WATCHDOG_CYCLES(CYCLES)) pair (`GUARD_EQ_INPUTS);
  initial begin
    for (epoch = 0; epoch < 2; epoch = epoch + 1) begin
      @(negedge clk); resetn = 0; job_valid = 0;
      repeat (2) @(negedge clk);
      resetn = 1; #0.01;
      if (!pair.new_ready || !pair.old_ready) $fatal(1, "watchdog admission failed");
      job_valid = 1;
      @(posedge clk); #0.01;
      if (!pair.new_busy || pair.new_fault || pair.dut.age != 0)
        $fatal(1, "watchdog admission did not start age zero");
      @(negedge clk); job_valid = 0;
      for (elapsed = 1; elapsed <= CYCLES; elapsed = elapsed + 1) begin
        #0.01;
        if (pair.dut.age != elapsed - 1 || pair.golden.age != elapsed - 1 ||
            pair.new_fault || pair.old_fault || !pair.new_busy || pair.new_ready ||
            pair.dut.watchdog_error !== (elapsed == CYCLES) ||
            pair.golden.watchdog_error !== (elapsed == CYCLES))
          $fatal(1, "watchdog pre-edge mismatch cycles=%0d elapsed=%0d", CYCLES, elapsed);
        @(posedge clk); #0.01;
        pair.compare_public();
        if (elapsed < CYCLES) begin
          if (pair.new_fault || !pair.new_busy || pair.new_reasons != 0)
            $fatal(1, "watchdog expired early cycles=%0d elapsed=%0d", CYCLES, elapsed);
        end else if (!pair.new_fault || pair.new_busy || pair.new_reasons != 8'h80 ||
                     pair.new_ready || pair.new_valid || pair.new_commit)
          $fatal(1, "watchdog failed exact quarantine edge cycles=%0d", CYCLES);
        @(negedge clk);
      end
      repeat (4) begin
        @(posedge clk); #0.01;
        if (!pair.new_fault || pair.new_ready || pair.new_reasons != 8'h80)
          $fatal(1, "watchdog quarantine not sticky");
      end
    end
    done = 1;
    $display("GUARD_WATCHDOG_EQ_PASS cycles=%0d epochs=2", CYCLES);
  end
endmodule

module tb_starlink_pss_realtime_result_guard_equivalence;
  // Reuse the full real-mailbox adversarial stimulus without modifying it.
  tb_starlink_pss_realtime_result_guard stimulus();
  guard_equivalence_pair legacy_pair (
    .clk(stimulus.clk), .resetn(stimulus.resetn), .job_valid(stimulus.job_valid),
    .job_descriptor(stimulus.job_descriptor),
    .input_bank_reserved(stimulus.input_bank_reserved),
    .output_bank_reserved(stimulus.output_bank_reserved),
    .certified_input_beat(stimulus.certified_input_beat),
    .certified_input_complete(stimulus.certified_input_complete),
    .final_fence_certified(stimulus.final_fence_certified),
    .external_fault_now(stimulus.external_fault_now),
    .core_event_frame_started(stimulus.core_event_frame_started),
    .core_output_tdata(stimulus.core_output_tdata),
    .core_output_tuser(stimulus.core_output_tuser),
    .core_output_tvalid(stimulus.core_output_tvalid),
    .core_output_tlast(stimulus.core_output_tlast),
    .core_status_tdata(stimulus.core_status_tdata),
    .core_status_tvalid(stimulus.core_status_tvalid),
    .mailbox_input_ready(stimulus.guard_ready),
    .mailbox_input_fault(stimulus.mailbox_fault || stimulus.inject_mailbox_fault)
  );
  wire truth_done;
  wire [5:0] watchdog_done;
  guard_idle_truth_table truth_table(truth_done);
  guard_watchdog_equivalence #(2) watchdog2(watchdog_done[0]);
  guard_watchdog_equivalence #(3) watchdog3(watchdog_done[1]);
  guard_watchdog_equivalence #(5) watchdog5(watchdog_done[2]);
  guard_watchdog_equivalence #(17) watchdog17(watchdog_done[3]);
  guard_watchdog_equivalence #(2048) watchdog2048(watchdog_done[4]);
  guard_watchdog_equivalence #(2049) watchdog2049(watchdog_done[5]);
  final begin
    if (!truth_done || !(&watchdog_done) || legacy_pair.comparisons < 1000 ||
        stimulus.healthy != 23 || stimulus.rejected != 37 || stimulus.reset_cases != 12)
      $fatal(1, "guard equivalence inventory incomplete");
    $display("GUARD_FACTORED_EQ_PASS legacy_healthy=23 legacy_rejected=37 independent_resets=12 idle_combinations=12288 watchdog_configurations=6 watchdog_epochs=12");
  end
endmodule
`undef GUARD_EQ_INPUTS
