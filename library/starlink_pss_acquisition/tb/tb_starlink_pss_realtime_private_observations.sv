// Test-only private observation capture versus immutable ff4229 public behavior.
// Synthetic certificates/core/status and a modeled READY/ACK, not an XFFT or
// mailbox capacity/CDC test. No state is forced or deposited in either guard.
`timescale 1ns/1ps
`define OBSERVED(g) {g.input_count, g.input_complete_seen, g.frame_seen, \
  g.status_seen, g.status_exponent, g.exponent_seen, g.output_exponent}
`define OBS_INPUTS \
  .clk(clk), .resetn(resetn), .job_valid(job_valid), .job_descriptor(descriptor), \
  .input_bank_reserved(input_reserved), .output_bank_reserved(output_reserved), \
  .certified_input_beat(beat), .certified_input_complete(complete), \
  .final_fence_certified(fence), .external_fault_now(external_fault), \
  .core_event_frame_started(frame), .core_output_tdata(core_data), \
  .core_output_tuser(core_user), .core_output_tvalid(core_valid), \
  .core_output_tlast(core_last), .core_status_tdata(status_data), \
  .core_status_tvalid(status_valid), .mailbox_input_ready(ready), \
  .mailbox_input_fault(mailbox_fault)

module tb_starlink_pss_realtime_private_observations;
  reg clk = 0, resetn = 0;
  always #2.5 clk = !clk;
  reg job_valid = 0, input_reserved = 1, output_reserved = 1;
  reg beat = 0, complete = 0, fence = 0, external_fault = 0, frame = 0;
  reg core_valid = 0, core_last = 0, status_valid = 0, ready = 1, mailbox_fault = 0;
  reg [69:0] descriptor = 70'h123456789abcdef012;
  reg [47:0] core_data = 0;
  reg [23:0] core_user = 0;
  reg [7:0] status_data = 6;
  wire new_ready, old_ready, new_valid, old_valid, new_last, old_last;
  wire new_busy, old_busy, new_commit, old_commit, new_fault, old_fault, private_valid;
  wire [7:0] new_reasons, old_reasons;
  wire [35:0] new_data, old_data;
  wire [8:0] new_position, old_position;
  wire [74:0] new_metadata, old_metadata;
  integer comparisons = 0, fault_cases = 0, quarantine_rows = 0, healthy_jobs = 0;
  integer healthy_words = 0, reset_epochs = 0;
  reg [6:0] observed_witnesses = 0;
  starlink_pss_realtime_result_guard #(.WATCHDOG_CYCLES(2048)) dut (
    `OBS_INPUTS, .job_ready(new_ready), .mailbox_input_valid(new_valid),
    .mailbox_private_valid(private_valid), .mailbox_input_data(new_data),
    .mailbox_input_position(new_position), .mailbox_input_last(new_last),
    .mailbox_input_metadata(new_metadata), .busy(new_busy), .commit_pulse(new_commit),
    .protocol_fault(new_fault), .fault_reasons(new_reasons)
  );
  starlink_pss_realtime_result_guard_ff4229_golden #(.WATCHDOG_CYCLES(2048)) golden (
    `OBS_INPUTS, .job_ready(old_ready), .mailbox_input_valid(old_valid),
    .mailbox_input_data(old_data), .mailbox_input_position(old_position),
    .mailbox_input_last(old_last), .mailbox_input_metadata(old_metadata),
    .busy(old_busy), .commit_pulse(old_commit), .protocol_fault(old_fault),
    .fault_reasons(old_reasons)
  );
  always @(posedge clk or negedge clk or negedge resetn) begin
    #0.01;
    comparisons = comparisons + 1;
    if ({new_ready,new_valid,new_busy,new_commit,new_fault,new_reasons} !==
        {old_ready,old_valid,old_busy,old_commit,old_fault,old_reasons})
      $fatal(1, "OBS_PUBLIC_EQ time=%0t new=%h old=%h", $time, new_reasons, old_reasons);
    if (new_valid && {new_data,new_position,new_last,new_metadata} !==
        {old_data,old_position,old_last,old_metadata})
      $fatal(1, "OBS_VALID_PAYLOAD_EQ");
    if (resetn && dut.active && !new_fault && `OBSERVED(dut) !== `OBSERVED(golden))
      $fatal(1, "OBS_HEALTHY_PRIVATE_EQ");
    if (new_fault && (new_ready || new_valid || private_valid || new_commit))
      $fatal(1, "OBS_QUARANTINE_PUBLICATION");
  end
  task tick; @(posedge clk); #0.1; endtask
  task quiet;
    job_valid = 0; beat = 0; complete = 0; frame = 0; core_valid = 0;
    core_last = 0; status_valid = 0; external_fault = 0; mailbox_fault = 0;
    input_reserved = 1; output_reserved = 1; ready = 1;
  endtask
  task reset_epoch;
    @(negedge clk); quiet(); resetn = 0; fence = 0;
    repeat (2) tick();
    if (`OBSERVED(dut) !== 24'd0 || `OBSERVED(golden) !== 24'd0 ||
        new_fault || old_fault || new_busy || old_busy)
      $fatal(1, "OBS_RESET_DID_NOT_PURGE");
    @(negedge clk); resetn = 1; #0.1;
    if (!new_ready || !old_ready) $fatal(1, "OBS_RESET_REUSE_NOT_READY");
    reset_epochs = reset_epochs + 1;
  endtask
  task admit;
    @(negedge clk); quiet(); fence = 0; job_valid = 1;
    if (!new_ready || !old_ready) $fatal(1, "OBS_ADMISSION");
    tick();
    @(negedge clk); job_valid = 0;
    if (!new_busy || new_fault || `OBSERVED(dut) !== `OBSERVED(golden))
      $fatal(1, "OBS_ADMISSION_STATE");
  endtask
  task inputs(input integer count);
    for (integer k = 0; k < count; k = k + 1) begin
      @(negedge clk); beat = 1; frame = k == 0; complete = k == 511; tick();
    end
    @(negedge clk); quiet();
  endtask
  task status(input integer exponent);
    @(negedge clk); status_valid = 1; status_data = exponent; tick();
    @(negedge clk); status_valid = 0;
  endtask
  task output_word(input integer index, input integer exponent);
    @(negedge clk); core_valid = 1; core_last = index == 511;
    core_data = {6'd0,18'(index + 13),6'd0,18'(index + 7)};
    core_user = {3'd0,5'(exponent),7'd0,9'(index)};
    #0.1;
  endtask

  // Each current-fault edge must capture exactly the requested private fields,
  // while golden retains them. Publication and exact fault masks still match.
  task capture_fault;
    reg [23:0] before_new, before_old, expected;
    reg [7:0] expected_reasons;
    begin
      #0.1;
      if (!dut.active || new_fault || !dut.fault_now || !golden.fault_now)
        $fatal(1, "OBS_FAULT_EDGE_SETUP");
      before_new = `OBSERVED(dut); before_old = `OBSERVED(golden);
      expected = {beat ? dut.input_count + 10'd1 : dut.input_count,
        dut.input_complete_seen || complete, dut.frame_seen || frame,
        dut.status_seen || status_valid, status_valid ? status_data[4:0] : dut.status_exponent,
        dut.exponent_seen || core_valid,
        core_valid && !dut.exponent_seen ? core_user[20:16] : dut.output_exponent};
      expected_reasons = new_reasons | dut.faults_now;
      if (new_valid || old_valid || dut.final_commit || golden.final_commit)
        $fatal(1, "OBS_CURRENT_FAULT_VALID_NOT_VETOED");
      tick();
      if (`OBSERVED(dut) !== expected || `OBSERVED(golden) !== before_old ||
          new_reasons !== expected_reasons || !new_fault || new_busy)
        $fatal(1, "OBS_FAULT_CAPTURE_MISSING got=%h expected=%h", `OBSERVED(dut), expected);
      observed_witnesses = observed_witnesses | {
        expected[23:14] != before_new[23:14], expected[13] != before_new[13],
        expected[12] != before_new[12], expected[11] != before_new[11],
        expected[10:6] != before_new[10:6], expected[5] != before_new[5],
        expected[4:0] != before_new[4:0]};
      fault_cases = fault_cases + 1;
    end
  endtask
  task quarantine;
    reg [23:0] held_new, held_old;
    reg [7:0] expected_reasons;
    begin
      held_new = `OBSERVED(dut); held_old = `OBSERVED(golden);
      expected_reasons = new_reasons;
      // Exhaust every combination of orphan certificates/frame/status/output
      // and direct faults. Payloads, reservation/ready and admission keep moving.
      for (integer row = 0; row < 128; row = row + 1) begin
        @(negedge clk);
        {mailbox_fault,external_fault,core_valid,status_valid,frame,complete,beat} = 7'(row);
        job_valid = 1; input_reserved = row[0]; output_reserved = row[1]; ready = row[2];
        core_data = 48'(row * 7919); core_user = 24'(row * 397);
        core_last = row[0]; status_data = 8'(row * 7); fence = row[3];
        expected_reasons = expected_reasons |
          {2'b0,row[4],row[3],row[2],(row[0] || row[1]),1'b0,(row[5] || row[6])};
        tick();
        if (`OBSERVED(dut) !== held_new || `OBSERVED(golden) !== held_old ||
            new_reasons !== expected_reasons || old_reasons !== expected_reasons ||
            new_busy || new_ready || new_valid || private_valid || new_commit)
          $fatal(1, "OBS_QUARANTINE_EVENT_EQ row=%0d expected=%h got=%h", row, expected_reasons, new_reasons);
        quarantine_rows = quarantine_rows + 1;
      end
    end
  endtask
  task healthy_reuse;
    integer accepted;
    begin
      reset_epoch(); admit(); inputs(512); status(6); accepted = 0;
      for (integer word_index = 0; word_index < 512; word_index = word_index + 1) begin
        output_word(word_index, 6);
        if (new_valid) begin
          if (new_position !== 9'(accepted) ||
              new_data !== {18'(accepted + 13),18'(accepted + 7)} || new_last ||
              new_metadata !== {descriptor,5'd6}) $fatal(1, "OBS_HEALTHY_WORD");
          accepted = accepted + 1;
        end
        tick();
      end
      @(negedge clk); quiet();
      repeat (3) tick();
      if (accepted != 511 || new_valid || new_commit || !dut.return_valid || !dut.return_last)
        $fatal(1, "OBS_FINAL_FENCE_HOLD accepted=%0d valid=%b commit=%b return=%b last=%b reasons=%h count=%0d",
          accepted, new_valid, new_commit, dut.return_valid, dut.return_last, new_reasons, dut.output_count);
      @(negedge clk); fence = 1; #0.1;
      if (!new_valid || !new_last || new_position != 511 ||
          new_data !== {18'd524,18'd518} || new_metadata !== {descriptor,5'd6})
        $fatal(1, "OBS_FINAL_FENCE_OPEN");
      tick();
      if (!new_commit || new_fault || !new_busy) $fatal(1, "OBS_HEALTHY_COMMIT");
      @(negedge clk); ready = 0;
      repeat (3) tick();
      if (!new_busy || new_ready) $fatal(1, "OBS_ACK_HOLD");
      @(negedge clk); ready = 1; tick();
      if (new_busy || !new_ready || new_fault) $fatal(1, "OBS_ACK_REUSE");
      healthy_jobs = healthy_jobs + 1; healthy_words = healthy_words + 512;
    end
  endtask

  integer scenario;
  initial begin
    for (scenario = 0; scenario < 10; scenario = scenario + 1) begin
      reset_epoch(); admit();
      case (scenario)
        0: begin @(negedge clk); beat = 1; frame = 1; external_fault = 1; end
        1: begin inputs(511); @(negedge clk); beat = 1; complete = 1; external_fault = 1; end
        2: begin inputs(512); @(negedge clk); status_valid = 1; status_data = 17; external_fault = 1; end
        3: begin inputs(512); output_word(0,11); external_fault = 1; end
        4: begin inputs(512); output_word(0,21); status_valid = 1; status_data = 21; external_fault = 1; end
        5: begin
          output_word(0,19); beat = 1; complete = 1; frame = 1;
          status_valid = 1; status_data = 19; // Illegal premature completion/output.
        end
        6: begin
          inputs(512); output_word(0,6); tick();
          @(negedge clk); core_valid = 0; status_valid = 1; status_data = 7;
        end
        7: begin
          inputs(512); status(6);
          for (integer n = 0; n < 512; n = n + 1) begin output_word(n,6); tick(); end
          @(negedge clk); quiet(); repeat (3) tick();
          output_word(0,7); beat = 1; complete = 1; frame = 1;
          status_valid = 1; status_data = 7; fence = 1; external_fault = 1;
        end
        8: begin
          while (dut.age < 2047) begin @(negedge clk); if (dut.age < 2047) tick(); end
          // Deadline is reached naturally, without depositing private state.
          beat = 1; frame = 1; status_valid = 1; status_data = 9;
        end
        9: begin @(negedge clk); beat = 1; frame = 1; output_reserved = 0; end
      endcase
      capture_fault(); quarantine(); healthy_reuse();
    end
    // Clean idle orphan traffic faults but must never capture job observations.
    reset_epoch();
    @(negedge clk); beat = 1; complete = 1; frame = 1;
    status_valid = 1; status_data = 23; core_valid = 1; core_user = {3'd0,5'd23,16'd0};
    tick();
    if (`OBSERVED(dut) !== 24'd0 || new_reasons !== 8'h3c || new_busy)
      $fatal(1, "OBS_IDLE_CAPTURE");
    quarantine(); healthy_reuse();
    if (observed_witnesses !== 7'h7f || fault_cases != 10 || quarantine_rows != 1408 ||
        healthy_jobs != 11 || healthy_words != 5632 || reset_epochs != 22 || comparisons < 25000)
      $fatal(1, "OBS_COVERAGE_MISSING witnesses=%h comparisons=%0d", observed_witnesses, comparisons);
    $display("PRIVATE_OBSERVATIONS_PASS fault_edges=10 fields_witnessed=7 quarantine_rows=1408 idle_orphans=1 reset_epochs=22 healthy_jobs=11 exact_words=5632 ff4229_public_and_reasons=1");
    $finish;
  end
  initial begin #300000; $fatal(1, "OBS_TEST_WATCHDOG"); end
endmodule
`undef OBSERVED
`undef OBS_INPUTS
