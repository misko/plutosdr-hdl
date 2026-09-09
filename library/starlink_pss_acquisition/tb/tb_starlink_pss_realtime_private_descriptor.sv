// Test-only speculative descriptor capture against immutable ff4229 behavior.
// Synthetic core/certificates and modeled READY/ACK; no mailbox, CDC, vendor
// numeric or timing qualification. Every state is reached through real inputs.
`timescale 1ns/1ps
`define DESC_INPUTS \
  .clk(clk), .resetn(resetn), .job_valid(job_valid), .job_descriptor(descriptor), \
  .input_bank_reserved(input_reserved), .output_bank_reserved(output_reserved), \
  .certified_input_beat(beat), .certified_input_complete(complete), \
  .final_fence_certified(fence), .external_fault_now(external_fault), \
  .core_event_frame_started(frame), .core_output_tdata(core_data), \
  .core_output_tuser(core_user), .core_output_tvalid(core_valid), \
  .core_output_tlast(core_last), .core_status_tdata(status_data), \
  .core_status_tvalid(status_valid), .mailbox_input_ready(ready), \
  .mailbox_input_fault(mailbox_fault)

module tb_starlink_pss_realtime_private_descriptor;
  reg clk = 0, resetn = 0;
  always #2.5 clk = !clk;
  reg job_valid = 0, input_reserved = 1, output_reserved = 1;
  reg beat = 0, complete = 0, fence = 0, external_fault = 0, frame = 0;
  reg core_valid = 0, core_last = 0, status_valid = 0, ready = 1, mailbox_fault = 0;
  reg [69:0] descriptor = 0;
  reg [47:0] core_data = 0;
  reg [23:0] core_user = 0;
  reg [7:0] status_data = 9;
  wire new_ready, old_ready, new_valid, old_valid, new_last, old_last;
  wire new_busy, old_busy, new_commit, old_commit, new_fault, old_fault, private_valid;
  wire [7:0] new_reasons, old_reasons;
  wire [35:0] new_data, old_data;
  wire [8:0] new_position, old_position;
  wire [74:0] new_metadata, old_metadata;
  reg [69:0] admitted_descriptor;
  integer idle_rows = 0, fault_rows = 0, comparisons = 0;
  integer healthy_jobs = 0, exact_words = 0, word_ordinal = 0;
  integer active_faults = 0, reset_challenges = 0;
  integer speculative_rejections = 0, current_fault_captures = 0, invalid_payload_differences = 0;
  starlink_pss_realtime_result_guard #(.WATCHDOG_CYCLES(4096)) dut (
    `DESC_INPUTS, .job_ready(new_ready), .mailbox_input_valid(new_valid),
    .mailbox_private_valid(private_valid), .mailbox_input_data(new_data),
    .mailbox_input_position(new_position), .mailbox_input_last(new_last),
    .mailbox_input_metadata(new_metadata), .busy(new_busy), .commit_pulse(new_commit),
    .protocol_fault(new_fault), .fault_reasons(new_reasons)
  );
  starlink_pss_realtime_result_guard_ff4229_golden #(.WATCHDOG_CYCLES(4096)) golden (
    `DESC_INPUTS, .job_ready(old_ready), .mailbox_input_valid(old_valid),
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
      $fatal(1, "DESC_PUBLIC_EQ time=%0t new=%h old=%h", $time, new_reasons, old_reasons);
    if (new_valid && {new_data,new_position,new_last,new_metadata} !==
        {old_data,old_position,old_last,old_metadata})
      $fatal(1, "DESC_VALID_PAYLOAD_EQ");
    if (!new_valid && new_metadata !== old_metadata)
      invalid_payload_differences = invalid_payload_differences + 1;
    if (new_fault && (new_ready || new_valid || private_valid || new_commit))
      $fatal(1, "DESC_QUARANTINE_PUBLICATION");
  end
  always @(posedge clk) begin
    if (!resetn) word_ordinal = 0;
    else begin
      if (job_valid && new_ready) begin
        admitted_descriptor = descriptor;
        word_ordinal = 0;
      end
      if (new_valid && ready) begin
        if (new_position !== 9'(word_ordinal) || new_last !== (word_ordinal == 511) ||
            new_data !== {18'(word_ordinal + 13),18'(word_ordinal + 7)} ||
            new_metadata !== {admitted_descriptor,5'd9})
          $fatal(1, "DESC_EXACT_ADMITTED_PAYLOAD ordinal=%0d", word_ordinal);
        word_ordinal = word_ordinal + 1;
        exact_words = exact_words + 1;
      end
    end
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
    if (dut.descriptor !== 0 || golden.descriptor !== 0 || new_busy || new_fault)
      $fatal(1, "DESC_RESET_PURGE");
    @(negedge clk); resetn = 1; #0.1;
  endtask
  task hold_descriptor(input [69:0] expected, input string phase_name);
    if (dut.descriptor !== expected)
      $fatal(1, "DESC_OWNERSHIP_HOLD phase=%s actual=%h expected=%h", phase_name, dut.descriptor, expected);
  endtask
  task admit(input [69:0] value);
    @(negedge clk); quiet(); fence = 0; descriptor = value; job_valid = 1;
    #0.1;
    if (!new_ready || !old_ready) $fatal(1, "DESC_ADMISSION_NOT_READY");
    tick();
    if (!new_busy || dut.descriptor !== value || golden.descriptor !== value)
      $fatal(1, "DESC_ADMISSION_CAPTURE");
    @(negedge clk); job_valid = 0;
  endtask

  // This task starts with an admitted descriptor, challenges every active
  // phase with different candidate metadata, then models a held consumer ACK.
  task complete_job;
    reg [69:0] owned;
    begin
      owned = admitted_descriptor;
      for (integer n = 0; n < 512; n = n + 1) begin
        @(negedge clk); job_valid = n[0]; descriptor = 70'h2aa000000000000000 + n;
        beat = 1; complete = n == 511; frame = n == 0;
        tick(); hold_descriptor(owned, "active input");
      end
      @(negedge clk); beat = 0; complete = 0; frame = 0;
      status_valid = 1; status_data = 9; tick(); hold_descriptor(owned, "status");
      @(negedge clk); status_valid = 0;
      for (integer n = 0; n < 512; n = n + 1) begin
        @(negedge clk); job_valid = 1; descriptor = 70'h155000000000000000 + n;
        core_valid = 1; core_last = n == 511;
        core_user = {3'd0,5'd9,7'd0,9'(n)};
        core_data = {6'd0,18'(n + 13),6'd0,18'(n + 7)};
        tick(); hold_descriptor(owned, "active output");
      end
      @(negedge clk); core_valid = 0; core_last = 0;
      repeat (3) begin
        descriptor = descriptor + 1; tick(); hold_descriptor(owned, "final fence");
        if (new_valid || new_commit || !dut.return_valid || !dut.return_last)
          $fatal(1, "DESC_FINAL_NOT_HELD");
        @(negedge clk);
      end
      fence = 1; ready = 0;
      repeat (3) begin tick(); hold_descriptor(owned, "final READY stall"); @(negedge clk); end
      ready = 1; tick(); hold_descriptor(owned, "commit edge");
      if (!new_commit || !dut.awaiting_ack || word_ordinal != 512)
        $fatal(1, "DESC_FINAL_COMMIT");
      @(negedge clk); ready = 0;
      repeat (3) begin
        descriptor = descriptor + 1; tick(); hold_descriptor(owned, "ACK ownership");
        if (new_ready || new_valid || !new_busy) $fatal(1, "DESC_ACK_NOT_HELD");
        @(negedge clk);
      end
      ready = 1; descriptor = 70'h3b0000000000000001; job_valid = 1;
      #0.1;
      if (new_ready) $fatal(1, "DESC_ACK_EDGE_ADMITTED_EARLY");
      tick(); hold_descriptor(owned, "exact ACK edge");
      if (new_busy || !new_ready || new_fault) $fatal(1, "DESC_ACK_RELEASE");
      @(negedge clk); job_valid = 0; descriptor = 70'h3c0000000000000002;
      tick(); hold_descriptor(owned, "idle job_valid zero");
      healthy_jobs = healthy_jobs + 1;
    end
  endtask

  integer faults, reservations, valid;
  reg [7:0] expected_reasons;
  reg [69:0] expected_descriptor;
  reg expected_ready;
  initial begin
    // Full clean-idle truth table: seven orphan/direct causes, three READY /
    // whole-bank premises, and job_valid. Every row begins in a real reset epoch.
    for (faults = 0; faults < 128; faults = faults + 1)
      for (reservations = 0; reservations < 8; reservations = reservations + 1)
        for (valid = 0; valid < 2; valid = valid + 1) begin
          reset_epoch();
          @(negedge clk);
          {mailbox_fault,external_fault,core_valid,status_valid,frame,complete,beat} = 7'(faults);
          {input_reserved,output_reserved,ready} = 3'(reservations);
          job_valid = valid; descriptor = 70'h123000000000000001 + idle_rows;
          core_data = 48'(idle_rows * 7919); core_user = 24'(idle_rows * 397);
          core_last = faults[0]; status_data = 8'(faults * 7);
          expected_reasons = {2'b0,faults[4],faults[3],faults[2],
            (faults[0] || faults[1]),1'b0,(faults[5] || faults[6])};
          expected_ready = faults == 0 && reservations == 7;
          expected_descriptor = valid ? descriptor : 70'd0;
          #0.1;
          if (new_ready !== expected_ready || new_valid || private_valid || new_busy || new_commit)
            $fatal(1, "DESC_IDLE_TRUTH_TABLE");
          tick();
          if (dut.descriptor !== expected_descriptor || new_reasons !== expected_reasons ||
              old_reasons !== expected_reasons || new_busy !== (expected_ready && valid))
            $fatal(1, "DESC_IDLE_CAPTURE faults=%0d reservations=%0d valid=%0d", faults, reservations, valid);
          if (valid && !expected_ready) speculative_rejections = speculative_rejections + 1;
          if (valid && faults) current_fault_captures = current_fault_captures + 1;
          if (faults) begin
            fault_rows = fault_rows + 1;
            @(negedge clk); quiet(); job_valid = 1; descriptor = 70'h3ff000000000000001;
            tick(); hold_descriptor(expected_descriptor, "sticky quarantine");
            if (new_reasons !== expected_reasons || new_ready || new_valid || private_valid || new_commit)
              $fatal(1, "DESC_STICKY_REASONS");
            // Post-fault orphan payloads cannot revive admission or change the
            // held descriptor; exact reason accumulation still matches ff4229.
            @(negedge clk); beat = 1; complete = 1; frame = 1; status_valid = 1; core_valid = 1;
            descriptor = descriptor + 1; tick(); hold_descriptor(expected_descriptor, "quarantine orphan events");
            if (new_reasons !== (expected_reasons | 8'h3c)) $fatal(1, "DESC_ORPHAN_REASONS");
          end
          idle_rows = idle_rows + 1;
        end

    // Several changing private candidates must not select an earlier rejected
    // descriptor. Only the actual admission descriptor can tag public words.
    reset_epoch();
    for (integer n = 0; n < 3; n = n + 1) begin
      @(negedge clk); job_valid = 1; descriptor = 70'h250000000000000000 + n;
      input_reserved = n != 0; output_reserved = n != 1; ready = n != 2;
      tick(); hold_descriptor(descriptor, "rejected candidate");
      if (new_busy || new_ready || new_fault) $fatal(1, "DESC_REJECTED_ADMISSION");
    end
    admit(70'h111111112222222233); complete_job();
    // No reset between these complete jobs: actual modeled ACK owns the reuse.
    admit(70'h244444445555555566); complete_job();
    // The active gate still holds the admitted descriptor on a current fault,
    // despite both a different candidate and a valid first input certificate.
    admit(70'h233333334444444455);
    @(negedge clk); job_valid = 1; descriptor = 70'h311111112222222233;
    beat = 1; frame = 1; external_fault = 1; tick();
    hold_descriptor(70'h233333334444444455, "same-edge active fault");
    if (new_reasons !== 8'h01 || new_busy || !new_fault)
      $fatal(1, "DESC_ACTIVE_FAULT_REASONS");
    active_faults = active_faults + 1;
    // Reset priority must dominate a candidate both from quarantine and from a
    // partially delivered active job, even when job_valid stays asserted.
    @(negedge clk); descriptor = 70'h377777778888888899; job_valid = 1; resetn = 0;
    tick();
    if (dut.descriptor !== 0 || golden.descriptor !== 0 || new_ready || new_busy)
      $fatal(1, "DESC_RESET_WITH_CANDIDATE");
    reset_challenges = reset_challenges + 1;
    @(negedge clk); quiet(); fence = 0; resetn = 1;
    admit(70'h255555556666666677);
    @(negedge clk); beat = 1; frame = 1; tick();
    @(negedge clk); frame = 0; tick();
    @(negedge clk); job_valid = 1; descriptor = 70'h366666667777777788; resetn = 0;
    tick();
    if (dut.descriptor !== 0 || golden.descriptor !== 0 || new_ready || new_busy)
      $fatal(1, "DESC_ACTIVE_RESET_WITH_CANDIDATE");
    reset_challenges = reset_challenges + 1;
    @(negedge clk); quiet(); fence = 0; resetn = 1;
    admit(70'h122222223333333344); complete_job();
    if (idle_rows != 2048 || fault_rows != 2032 || speculative_rejections != 1023 ||
        current_fault_captures != 1016 || healthy_jobs != 3 || exact_words != 1536 ||
        active_faults != 1 || reset_challenges != 2 ||
        invalid_payload_differences == 0 || comparisons < 20000)
      $fatal(1, "DESC_COVERAGE_MISSING rows=%0d faults=%0d words=%0d", idle_rows, fault_rows, exact_words);
    $display("PRIVATE_DESCRIPTOR_PASS idle_rows=2048 fault_rows=2032 speculative_rejections=1023 current_fault_captures=1016 active_faults=1 reset_challenges=2 healthy_jobs=3 exact_words=1536 ff4229_public_and_reasons=1");
    $finish;
  end
  initial begin #400000; $fatal(1, "DESC_TEST_WATCHDOG"); end
endmodule
`undef DESC_INPUTS
