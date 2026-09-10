// Isolated synthetic-core protocol tests with the REAL dual-clock block mailbox.
// Not actual-core numerics, input-delivery qualification, capacity or physical CDC.
`timescale 1ns/1ps
module tb_starlink_pss_realtime_result_guard;
  parameter real SLOW_HALF_NS = 5.0;
  parameter real SLOW_PHASE_NS = 1.3;
  reg clk = 0, slow_clk = 0;
  always #2.5 clk = !clk;
  initial begin
    #(SLOW_PHASE_NS);
    forever #(SLOW_HALF_NS) slow_clk = !slow_clk;
  end
  reg fast_resetn = 0, slow_resetn = 0;
  wire common_resetn = fast_resetn && slow_resetn;
  reg [1:0] release_sync = 0;
  always @(posedge clk or negedge common_resetn)
    if (!common_resetn) release_sync <= 0;
    else release_sync <= {release_sync[0], 1'b1};
  wire resetn = release_sync[1];
  reg job_valid = 0;
  wire job_ready;
  reg [69:0] job_descriptor = 0;
  reg input_bank_reserved = 1, output_bank_reserved = 1;
  reg certified_input_beat = 0, certified_input_complete = 0;
  reg final_fence_certified = 0, external_fault_now = 0;
  reg core_event_frame_started = 0;
  reg [47:0] core_output_tdata = 0;
  reg [23:0] core_output_tuser = 0;
  reg core_output_tvalid = 0, core_output_tlast = 0;
  reg [7:0] core_status_tdata = 6;
  reg core_status_tvalid = 0;
  wire guard_valid, guard_ready, mailbox_ready, mailbox_fault;
  wire [35:0] guard_data;
  wire [8:0] guard_position;
  wire guard_last;
  wire [74:0] guard_metadata;
  reg inject_stall = 0, inject_mailbox_fault = 0;
  wire busy, commit_pulse, protocol_fault;
  wire [7:0] fault_reasons;
  assign guard_ready = mailbox_ready && !inject_stall;
  starlink_pss_realtime_result_guard #(.WATCHDOG_CYCLES(2048)) dut (
    .clk(clk), .resetn(resetn), .job_valid(job_valid), .job_ready(job_ready),
    .job_descriptor(job_descriptor), .input_bank_reserved(input_bank_reserved),
    .output_bank_reserved(output_bank_reserved),
    .certified_input_beat(certified_input_beat),
    .certified_input_complete(certified_input_complete),
    .final_fence_certified(final_fence_certified), .external_fault_now(external_fault_now),
    .core_event_frame_started(core_event_frame_started),
    .core_output_tdata(core_output_tdata), .core_output_tuser(core_output_tuser),
    .core_output_tvalid(core_output_tvalid), .core_output_tlast(core_output_tlast),
    .core_status_tdata(core_status_tdata), .core_status_tvalid(core_status_tvalid),
    .mailbox_input_valid(guard_valid), .mailbox_input_ready(guard_ready),
    .mailbox_input_fault(mailbox_fault || inject_mailbox_fault),
    .mailbox_input_data(guard_data), .mailbox_input_position(guard_position),
    .mailbox_input_last(guard_last), .mailbox_input_metadata(guard_metadata),
    .busy(busy), .commit_pulse(commit_pulse), .protocol_fault(protocol_fault),
    .fault_reasons(fault_reasons)
  );
  wire output_valid, output_last;
  wire [35:0] output_data;
  wire [8:0] output_position;
  wire [74:0] output_metadata;
  reg read_enable = 0, stall_reader = 0;
  integer slow_cycles = 0;
  wire output_ready = read_enable && (!stall_reader || slow_cycles % 7 < 4);
  starlink_pss_block_mailbox #(.METADATA_WIDTH(75)) mailbox (
    .input_clk(clk), .input_resetn(fast_resetn),
    .input_valid(guard_valid && !inject_stall), .input_ready(mailbox_ready),
    .input_data(guard_data), .input_position(guard_position), .input_last(guard_last),
    .input_metadata(guard_metadata), .input_fault(mailbox_fault),
    .output_clk(slow_clk), .output_resetn(slow_resetn),
    .output_valid(output_valid), .output_ready(output_ready),
    .output_data(output_data), .output_position(output_position),
    .output_last(output_last), .output_metadata(output_metadata)
  );

  integer writes = 0, reads = 0, commits = 0, status_events = 0;
  integer input_events = 0, complete_events = 0, frame_events = 0;
  integer healthy = 0, rejected = 0, reset_cases = 0, seed = 1;
  integer seed_expected = 1;
  reg [69:0] descriptor_expected = 0;
  reg allow_commit = 0;
  reg suppress_frame = 0;
  function automatic [35:0] word_at(input integer index);
    word_at = {18'((index * 719 + seed_expected * 317) ^ 18'h2bdef),
               18'((index * 137 + seed_expected * 123) ^ 18'h175ad)};
  endfunction

  always @(posedge clk) begin
    if (!resetn) begin
      writes = 0; commits = 0; status_events = 0;
      input_events = 0; complete_events = 0; frame_events = 0;
    end else begin
      if (certified_input_beat) input_events = input_events + 1;
      if (certified_input_complete) complete_events = complete_events + 1;
      if (core_event_frame_started) frame_events = frame_events + 1;
      if (core_status_tvalid) status_events = status_events + 1;
      if (guard_valid && guard_ready) begin
        if (guard_position !== 9'(writes % 512) ||
            guard_last !== (writes % 512 == 511) ||
            guard_data !== word_at(writes % 512) ||
            guard_metadata !== {descriptor_expected, 5'd6})
          $fatal(1, "private mailbox payload/order/descriptor mismatch write=%0d", writes);
        writes = writes + 1;
        if (guard_last) begin
          if (!allow_commit || !final_fence_certified || external_fault_now ||
              protocol_fault || status_events != 1 || input_events != 512 ||
              complete_events != 1 || frame_events != 1)
            $fatal(1, "unqualified or early final write");
          commits = commits + 1;
        end
      end
      if (protocol_fault && job_ready) $fatal(1, "poisoned guard admitted reuse");
    end
  end
  reg was_stalled = 0;
  reg [120:0] stalled_word;
  always @(posedge slow_clk) begin
    slow_cycles = slow_cycles + 1;
    if (!common_resetn) begin reads = 0; was_stalled = 0; end
    else begin
      if (was_stalled && output_valid &&
          {output_data, output_position, output_last, output_metadata} !== stalled_word)
        $fatal(1, "published mailbox word changed under backpressure");
      was_stalled = output_valid && !output_ready;
      stalled_word = {output_data, output_position, output_last, output_metadata};
      if (output_valid) begin
        if (!commits) $fatal(1, "partial block escaped before commit");
        if (output_ready) begin
          if (output_position !== 9'(reads % 512) || output_last !== (reads % 512 == 511) ||
              output_data !== word_at(reads % 512) ||
              output_metadata !== {descriptor_expected, 5'd6})
            $fatal(1, "public result mismatch read=%0d", reads);
          reads = reads + 1;
        end
      end
    end
  end

  task automatic tick;
    @(posedge clk); #0.1;
  endtask
  task automatic quiet;
    job_valid = 0;
    certified_input_beat = 0; certified_input_complete = 0;
    core_event_frame_started = 0; core_output_tvalid = 0; core_output_tlast = 0;
    core_status_tvalid = 0; core_status_tdata = 6;
    external_fault_now = 0; inject_stall = 0; inject_mailbox_fault = 0;
  endtask
  task automatic reset_epoch(input integer side);
    @(negedge clk);
    quiet(); final_fence_certified = 0; allow_commit = 0;
    suppress_frame = 0;
    read_enable = 0; stall_reader = 0;
    input_bank_reserved = 1; output_bank_reserved = 1;
    if (side != 2) fast_resetn = 0;
    if (side != 1) slow_resetn = 0;
    repeat (8) tick();
    @(negedge clk); fast_resetn = 1; slow_resetn = 1;
    repeat (12) tick();
    if (protocol_fault || output_valid || !job_ready || mailbox.request_toggle || writes || reads)
      $fatal(1, "reset failed to purge guard/mailbox epoch side=%0d", side);
  endtask
  task automatic begin_job;
    @(negedge clk);
    if (commits) begin
      if (writes != 512 || reads != 512 || busy)
        $fatal(1, "next job began before whole-bank ACK");
      writes = 0; reads = 0; commits = 0; status_events = 0;
      input_events = 0; complete_events = 0; frame_events = 0;
    end
    seed = seed + 1; seed_expected = seed;
    descriptor_expected = {1'(seed & 1), 64'(64'h123456789abcdef0 + seed), 5'(seed)};
    job_descriptor = descriptor_expected;
    if (!job_ready) $fatal(1, "reserved bank did not admit job");
    job_valid = 1;
    tick();
    @(negedge clk); job_valid = 0;
    // Changing the next-job input must not mutate the owned descriptor.
    job_descriptor = ~descriptor_expected;
  endtask
  task automatic deliver_inputs(input integer count, input integer certify_at_end);
    integer i;
    for (i = 0; i < count; i = i + 1) begin
      @(negedge clk);
      certified_input_beat = 1;
      certified_input_complete = certify_at_end && i == count - 1;
      core_event_frame_started = i == 0 && !suppress_frame;
      tick();
    end
    @(negedge clk); quiet();
  endtask
  task automatic send_status(input integer value);
    @(negedge clk); core_status_tvalid = 1; core_status_tdata = value;
    tick();
    @(negedge clk); core_status_tvalid = 0;
  endtask
  task automatic drive_word(input integer index);
    reg [35:0] value;
    value = word_at(index);
    core_output_tdata = {6'b0, value[35:18], 6'b0, value[17:0]};
    core_output_tuser = {3'b0, 5'd6, 7'b0, 9'(index)};
    core_output_tlast = index == 511;
    core_output_tvalid = 1;
  endtask
  task automatic send_outputs(input integer status_at, input integer kind,
                              input integer bad_index, input integer last_index);
    integer i;
    for (i = 0; i <= last_index; i = i + 1) begin
      @(negedge clk);
      drive_word(i);
      core_status_tvalid = i == status_at;
      core_status_tdata = 6;
      if (i == bad_index) begin
        case (kind)
          1: core_output_tuser[8:0] = 9'(i + 1);
          2: core_output_tlast = !core_output_tlast;
          3: core_output_tuser[9] = 1;
          4: core_output_tuser[21] = 1;
          5: core_output_tuser[20:16] = 7;
          6: inject_stall = 1;
          7: external_fault_now = 1;
          8: core_event_frame_started = 1;
        endcase
      end
      tick();
      if (protocol_fault && core_output_tvalid && dut.output_count != i + 1)
        $fatal(1, "malformed raw output was not accounted index=%0d count=%0d", i,
               dut.output_count);
      if (protocol_fault) i = last_index;
    end
    @(negedge clk); quiet();
  endtask
  task automatic expect_private_final;
    if (commits || writes != 511 || mailbox.write_position != 511 ||
        !dut.return_valid || !dut.return_last || output_valid)
      $fatal(1, "final word not retained privately writes=%0d commits=%0d", writes, commits);
  endtask
  task automatic expect_rejected;
    integer i;
    for (i = 0; i < 2200 && !protocol_fault; i = i + 1) tick();
    if (!protocol_fault || !fault_reasons || commits || writes > 511 ||
        mailbox.request_toggle || reads)
      $fatal(1, "bad job not quarantined reasons=%h writes=%0d commits=%0d",
             fault_reasons, writes, commits);
    repeat (24) tick();
    if (output_valid || job_ready || guard_valid) $fatal(1, "quarantine was not sticky");
    rejected = rejected + 1;
  endtask
  task automatic drain_healthy;
    integer i;
    read_enable = 1; stall_reader = 1;
    for (i = 0; i < 10000 && (!job_ready || reads != 512); i = i + 1) tick();
    if (protocol_fault || commits != 1 || writes != 512 || reads != 512 || busy || !job_ready)
      $fatal(1, "healthy drain/ACK failed fault=%h writes=%0d reads=%0d",
             fault_reasons, writes, reads);
    healthy = healthy + 1;
  endtask
  task automatic healthy_job(input integer status_at, input integer late_delay);
    begin_job(); deliver_inputs(512, 1);
    allow_commit = 1; final_fence_certified = 1;
    if (status_at == -2) send_status(6);
    send_outputs(status_at, 0, -1, 511);
    expect_private_final();
    if (status_at == -1) begin
      repeat (late_delay) tick();
      expect_private_final();
      send_status(6);
    end
    drain_healthy();
  endtask

  integer i, kind, side;
  initial begin
    reset_epoch(0);
    // Neither ready nor an incomplete reservation may authorize a job.
    @(negedge clk); input_bank_reserved = 0; job_valid = 1;
    repeat (8) tick();
    if (busy || job_ready || protocol_fault) $fatal(1, "missing input reservation admitted");
    @(negedge clk); input_bank_reserved = 1; output_bank_reserved = 0;
    repeat (8) tick();
    if (busy || job_ready || protocol_fault) $fatal(1, "missing output reservation admitted");
    @(negedge clk); job_valid = 0; output_bank_reserved = 1;
    healthy_job(-2, 0);
    // Reuse after actual slow-side ACK, without resetting the guard/core epoch.
    healthy_job(-1, 31);
    healthy_job(3, 0);
    reset_epoch(0); healthy_job(0, 0);
    reset_epoch(0); healthy_job(2, 0);
    reset_epoch(0); healthy_job(3, 0);
    reset_epoch(0); healthy_job(511, 0);
    reset_epoch(0); healthy_job(-1, 1);
    reset_epoch(0); healthy_job(-1, 777);

    // Matching status is insufficient without an externally certified fence.
    reset_epoch(0); begin_job(); deliver_inputs(512, 1); send_status(6);
    send_outputs(-1, 0, -1, 511); expect_private_final();
    repeat (50) tick(); expect_private_final();
    @(negedge clk); final_fence_certified = 1; allow_commit = 1; inject_stall = 1;
    repeat (30) tick(); expect_private_final();
    @(negedge clk); inject_stall = 0;
    repeat (30) tick();
    if (commits != 1 || !busy || job_ready || reads) $fatal(1, "bank ACK not respected");
    drain_healthy();

    // First/middle/final index, TLAST, both TUSER padding fields and exponent.
    for (kind = 1; kind <= 5; kind = kind + 1)
      for (i = 0; i < 3; i = i + 1) begin
        reset_epoch(0); begin_job(); deliver_inputs(512, 1); send_status(6);
        final_fence_certified = 1;
        send_outputs(-1, kind, i == 0 ? 0 : i == 1 ? 255 : 511, 511);
        expect_rejected();
      end
    // Non-final slot backpressure is an overrun, not a hidden core stall.
    reset_epoch(0); begin_job(); deliver_inputs(512, 1); send_status(6);
    send_outputs(-1, 6, 123, 511); expect_rejected();
    // Missing status and truncated output fail finitely; no two-cycle assumption.
    reset_epoch(0); begin_job(); deliver_inputs(512, 1);
    final_fence_certified = 1;
    send_outputs(-1, 0, -1, 511); expect_private_final(); expect_rejected();
    reset_epoch(0); begin_job(); deliver_inputs(512, 1); send_status(6);
    final_fence_certified = 1;
    send_outputs(-1, 0, -1, 123); expect_rejected();
    // Independent status mismatch, padding, duplication and orphan events.
    for (kind = 0; kind < 3; kind = kind + 1) begin
      reset_epoch(0); begin_job(); deliver_inputs(512, 1);
      if (kind == 2) send_status(6);
      send_outputs(-1, 0, -1, 10);
      send_status(kind == 0 ? 7 : kind == 1 ? 8'h26 : 6);
      expect_rejected();
    end
    reset_epoch(0); send_status(6); expect_rejected();
    reset_epoch(0); begin_job(); deliver_inputs(512, 1); send_status(7);
    send_outputs(-1, 0, -1, 0); expect_rejected();
    // Exact final commit edge: every new fault must combinationally veto it.
    for (kind = 0; kind < 8; kind = kind + 1) begin
      reset_epoch(0); begin_job(); deliver_inputs(512, 1); send_status(6);
      send_outputs(-1, 0, -1, 511); expect_private_final();
      @(negedge clk); final_fence_certified = 1;
      case (kind)
        0: external_fault_now = 1;
        1: begin core_status_tvalid = 1; core_status_tdata = 6; end
        2: drive_word(0);
        3: core_event_frame_started = 1;
        4: inject_mailbox_fault = 1;
        5: output_bank_reserved = 0;
        6: certified_input_beat = 1;
        7: certified_input_complete = 1;
      endcase
      #0.1;
      if (guard_valid) $fatal(1, "same-cycle final fault did not veto commit kind=%0d", kind);
      tick(); @(negedge clk); quiet();
      expect_rejected();
    end
    // Early/late input certification, partial reservation loss and absent frame.
    reset_epoch(0); begin_job(); deliver_inputs(511, 1); expect_rejected();
    reset_epoch(0); begin_job(); deliver_inputs(512, 0);
    repeat (31) tick();
    @(negedge clk); certified_input_complete = 1; tick();
    @(negedge clk); certified_input_complete = 0;
    send_status(6); final_fence_certified = 1; allow_commit = 1;
    send_outputs(-1, 0, -1, 511); drain_healthy();
    reset_epoch(0); begin_job(); deliver_inputs(128, 0);
    @(negedge clk); input_bank_reserved = 0; tick(); expect_rejected();
    reset_epoch(0); begin_job(); deliver_inputs(512, 0);
    send_outputs(-1, 0, -1, 0); expect_rejected();
    reset_epoch(0); begin_job(); suppress_frame = 1; deliver_inputs(512, 1);
    send_status(6); send_outputs(-1, 0, -1, 0); expect_rejected();
    reset_epoch(0); begin_job(); deliver_inputs(512, 1); send_status(6);
    send_outputs(-1, 7, 511, 511); expect_rejected();
    // Timeout must veto the very edge that would otherwise publish.
    reset_epoch(0); begin_job(); deliver_inputs(512, 1); send_status(6);
    send_outputs(-1, 0, -1, 511); expect_private_final();
    while (dut.age < 2047) tick();
    @(negedge clk); final_fence_certified = 1;
    #0.1;
    if (guard_valid) $fatal(1, "watchdog expiry failed final-edge veto");
    tick(); expect_rejected();

    // Independent resets purge private prefixes, held final words and status.
    for (side = 1; side <= 2; side = side + 1)
      for (kind = 0; kind < 4; kind = kind + 1) begin
        reset_epoch(0); begin_job();
        if (kind == 0) deliver_inputs(128, 0);
        else begin
          deliver_inputs(512, 1);
          if (kind != 3) send_status(6);
          send_outputs(-1, 0, -1, kind == 1 ? 123 : 511);
        end
        reset_epoch(side);
        reset_cases = reset_cases + 1;
        healthy_job(-1, 7);
      end
    // Reset at final-commit boundary: asynchronous common reset must veto write.
    for (side = 1; side <= 2; side = side + 1) begin
      reset_epoch(0); begin_job(); deliver_inputs(512, 1); send_status(6);
      send_outputs(-1, 0, -1, 511);
      @(negedge clk); final_fence_certified = 1;
      if (side == 1) fast_resetn = 0; else slow_resetn = 0;
      #0.1;
      if (guard_valid) $fatal(1, "reset failed same-cycle final veto");
      reset_epoch(side); reset_cases = reset_cases + 1; healthy_job(-2, 0);
    end
    // A reset while the slow side holds a published word aborts only that old
    // epoch; it must not leak its read prefetch or ACK into a recovered job.
    for (side = 1; side <= 2; side = side + 1) begin
      reset_epoch(0); begin_job(); deliver_inputs(512, 1); send_status(6);
      allow_commit = 1; final_fence_certified = 1;
      send_outputs(-1, 0, -1, 511);
      repeat (30) tick();
      if (!output_valid || !busy || reads || commits != 1)
        $fatal(1, "slow drain reset setup failed");
      reset_epoch(side); reset_cases = reset_cases + 1; healthy_job(3, 0);
    end
    $display("REALTIME_RESULT_GUARD_PASS healthy=%0d rejected=%0d independent_resets=%0d private_words=511 held_slots=1 real_mailbox=1 ack_reuse=2 isolated_only=1",
             healthy, rejected, reset_cases);
    $finish;
  end
  initial begin #10000000; $fatal(1, "isolated result guard test watchdog"); end
endmodule
