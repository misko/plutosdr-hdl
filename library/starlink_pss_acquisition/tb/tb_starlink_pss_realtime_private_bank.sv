// Private RAM writes versus certified retirement/publication. Synthetic core,
// real dual-clock mailboxes; no actual-core, capacity or physical qualification.
`timescale 1ns/1ps
module tb_starlink_pss_realtime_private_bank;
  parameter real SLOW_HALF_NS = 5.0;
  parameter real SLOW_PHASE_NS = 1.3;
  // Retain the complete legacy adversarial stimulus and immutable guard golden.
  tb_starlink_pss_realtime_result_guard_equivalence probe();
  defparam probe.stimulus.SLOW_HALF_NS = SLOW_HALF_NS;
  defparam probe.stimulus.SLOW_PHASE_NS = SLOW_PHASE_NS;
  defparam probe.stimulus.mailbox.EXPLICIT_COMMIT = 1;
  wire private_drive = probe.stimulus.dut.mailbox_private_valid &&
    !probe.stimulus.inject_stall;
  wire commit_drive = probe.stimulus.guard_valid;
  wire fault_drive = probe.stimulus.mailbox_fault || probe.stimulus.inject_mailbox_fault ||
    probe.stimulus.mailbox.input_framing_fault_now;
  initial begin
    force probe.stimulus.mailbox.input_valid = private_drive;
    force probe.stimulus.mailbox.input_commit_authorized = commit_drive;
    force probe.stimulus.dut.mailbox_input_fault = fault_drive;
  end
  wire clk = probe.stimulus.clk;
  wire slow_clk = probe.stimulus.slow_clk;
  wire shadow_ready, shadow_fault, shadow_valid, shadow_last;
  wire [35:0] shadow_data;
  wire [8:0] shadow_position;
  wire [74:0] shadow_metadata;
  // Default mailbox receives only the old certified stream. Every public word,
  // publication toggle, ownership ready and fault must match the private mode.
  starlink_pss_block_mailbox #(.METADATA_WIDTH(75)) shadow (
    .input_clk(clk), .input_resetn(probe.stimulus.fast_resetn),
    .input_valid(probe.stimulus.guard_valid && !probe.stimulus.inject_stall),
    .input_commit_authorized(1'b0), .input_ready(shadow_ready),
    .input_data(probe.stimulus.guard_data), .input_position(probe.stimulus.guard_position),
    .input_last(probe.stimulus.guard_last), .input_metadata(probe.stimulus.guard_metadata),
    .input_fault(shadow_fault), .output_clk(slow_clk),
    .output_resetn(probe.stimulus.slow_resetn), .output_valid(shadow_valid),
    .output_ready(probe.stimulus.output_ready), .output_data(shadow_data),
    .output_position(shadow_position), .output_last(shadow_last),
    .output_metadata(shadow_metadata)
  );
  integer private_writes = 0, fault_writes = 0, final_rewrites = 0, comparisons = 0;
  reg [8:0] before_position;
  reg [35:0] before_data;
  reg before_write, before_fault, before_held_final, before_toggle;
  always @(posedge clk) begin
    before_write = probe.stimulus.mailbox.input_accept;
    before_position = probe.stimulus.mailbox.write_position;
    before_data = probe.stimulus.guard_data;
    before_fault = probe.stimulus.dut.fault_now;
    before_held_final = before_write && before_position == 511 &&
      !probe.stimulus.guard_valid;
    before_toggle = probe.stimulus.mailbox.request_toggle;
    #0.02;
    if (before_write) begin
      private_writes = private_writes + 1;
      if (probe.stimulus.mailbox.payload_memory[before_position] !== before_data)
        $fatal(1, "PRIVATE_BANK_WRITE_MISMATCH");
      if (before_fault) begin
        fault_writes = fault_writes + 1;
        if (!probe.stimulus.protocol_fault || probe.stimulus.commit_pulse ||
            probe.stimulus.dut.mailbox_private_valid || probe.stimulus.guard_valid ||
            probe.stimulus.mailbox.request_toggle !== before_toggle)
          $fatal(1, "PRIVATE_BANK_FAULT_PUBLICATION");
      end
      if (before_held_final) begin
        final_rewrites = final_rewrites + 1;
        if (probe.stimulus.mailbox.write_position !== 9'd511 ||
            probe.stimulus.mailbox.request_toggle !== before_toggle)
          $fatal(1, "PRIVATE_BANK_FINAL_HOLD_ADVANCED");
      end
    end
    comparisons = comparisons + 1;
    if ({shadow_ready, shadow_fault, shadow.request_toggle} !==
        {probe.stimulus.mailbox_ready, probe.stimulus.mailbox_fault,
         probe.stimulus.mailbox.request_toggle})
      $fatal(1, "PRIVATE_BANK_OWNERSHIP_DIFFERENTIAL");
  end
  always @(posedge slow_clk or negedge slow_clk) begin
    #0.02;
    if (shadow_valid !== probe.stimulus.output_valid ||
        (shadow_valid && {shadow_data, shadow_position, shadow_last, shadow_metadata} !==
         {probe.stimulus.output_data, probe.stimulus.output_position,
          probe.stimulus.output_last, probe.stimulus.output_metadata}))
      $fatal(1, "PRIVATE_BANK_PUBLIC_DIFFERENTIAL");
  end
  final begin
    if (private_writes < 25000 || fault_writes < 10 || final_rewrites < 1000 ||
        comparisons < 50000 || probe.stimulus.healthy != 23 ||
        probe.stimulus.rejected != 37 || probe.stimulus.reset_cases != 12)
      $fatal(1, "PRIVATE_BANK_COVERAGE_MISSING");
    $display("PRIVATE_BANK_PASS healthy=23 rejected=37 independent_resets=12 private_writes=%0d fault_writes=%0d final_rewrites=%0d comparisons=%0d public_golden_and_shadow=1",
      private_writes, fault_writes, final_rewrites, comparisons);
  end
endmodule

module tb_starlink_pss_private_bank_late_ack;
  parameter integer CORRUPT_LINK = 0;
  reg clk = 0, slow_clk = 0, resetn = 0;
  always #2.5 clk = !clk;
  always #5.3 slow_clk = !slow_clk;
  reg job_valid = 0, beat = 0, complete = 0, frame = 0, external_fault = 0;
  reg core_valid = 0, core_last = 0, status_valid = 0, drain = 0;
  reg fence = 1;
  integer corrupt_kind = -1;
  reg [47:0] core_data = 0;
  reg [23:0] core_user = 0;
  wire job_ready, busy, commit, protocol_fault, valid, private_valid, ready, fault, last;
  wire [7:0] reasons;
  wire [35:0] data, out_data;
  wire [8:0] position, out_position;
  wire [74:0] metadata, out_metadata;
  wire out_valid, out_last, framing_fault_now;
  integer i, scenario, reads = 0, commits = 0;
  reg committed_toggle;
  starlink_pss_realtime_result_guard guard (
    .clk(clk), .resetn(resetn), .job_valid(job_valid), .job_ready(job_ready),
    .job_descriptor(70'h32123456789abcdefff), .input_bank_reserved(1'b1),
    .output_bank_reserved(1'b1), .certified_input_beat(beat),
    .certified_input_complete(complete), .final_fence_certified(fence),
    .external_fault_now(external_fault), .core_event_frame_started(frame),
    .core_output_tdata(core_data), .core_output_tuser(core_user),
    .core_output_tvalid(core_valid), .core_output_tlast(core_last),
    .core_status_tdata(8'd6), .core_status_tvalid(status_valid),
    .mailbox_input_valid(valid), .mailbox_private_valid(private_valid),
    .mailbox_input_ready(ready), .mailbox_input_fault(fault || framing_fault_now),
    .mailbox_input_data(data), .mailbox_input_position(position),
    .mailbox_input_last(last), .mailbox_input_metadata(metadata),
    .busy(busy), .commit_pulse(commit), .protocol_fault(protocol_fault), .fault_reasons(reasons)
  );
  starlink_pss_block_mailbox #(.METADATA_WIDTH(75), .EXPLICIT_COMMIT(1)) mailbox (
    .input_clk(clk), .input_resetn(resetn), .input_valid(private_valid),
    .input_commit_authorized(valid), .input_ready(ready), .input_fault(fault),
    .input_data(data), .input_position(position ^ (corrupt_kind == 0 ? 9'd1 : 9'd0)),
    .input_last(last ^ (corrupt_kind == 1)),
    .input_metadata(metadata ^ (corrupt_kind == 2 ? 75'd1 : 75'd0)),
    .input_framing_fault_now(framing_fault_now),
    .output_clk(slow_clk), .output_resetn(resetn), .output_valid(out_valid),
    .output_ready(drain), .output_data(out_data), .output_position(out_position),
    .output_last(out_last), .output_metadata(out_metadata)
  );
  always @(posedge clk) if (resetn && commit) commits = commits + 1;
  always @(posedge slow_clk) if (resetn && out_valid && drain) begin
    if (out_data !== {18'(reads + 13), 18'(reads + 7)} ||
        out_position !== 9'(reads) || out_last !== (reads == 511) ||
        out_metadata !== {70'h32123456789abcdefff, 5'd6})
      $fatal(1, "LATE_ACK_PRIVATE_BANK_REWRITTEN");
    reads = reads + 1;
  end
  task tick; @(posedge clk); #0.1; endtask
  initial begin
    for (scenario = 0; scenario < (CORRUPT_LINK ? 6 : 3); scenario = scenario + 1) begin
      @(negedge clk); resetn = 0; job_valid = 0; beat = 0; complete = 0;
      frame = 0; external_fault = 0; core_valid = 0; status_valid = 0; drain = 0;
      fence = !CORRUPT_LINK; corrupt_kind = -1;
      repeat (10) tick();
      @(negedge clk); resetn = 1; reads = 0; commits = 0;
      repeat (12) tick();
      if (!job_ready || protocol_fault) $fatal(1, "LATE_ACK_RESET");
      @(negedge clk); job_valid = 1; tick();
      @(negedge clk); job_valid = 0;
      for (i = 0; i < 512; i = i + 1) begin
        @(negedge clk); beat = 1; frame = i == 0; complete = i == 511; tick();
      end
      @(negedge clk); beat = 0; frame = 0; complete = 0; status_valid = 1; tick();
      @(negedge clk); status_valid = 0;
      for (i = 0; i < (CORRUPT_LINK && scenario < 3 ? 18 : 512); i = i + 1) begin
        @(negedge clk); core_valid = 1; core_last = i == 511;
        core_data = {6'b0, 18'(i + 13), 6'b0, 18'(i + 7)};
        core_user = {3'b0, 5'd6, 7'b0, 9'(i)}; tick();
      end
      @(negedge clk); core_valid = 0;
      if (CORRUPT_LINK) begin
        if (scenario >= 3) repeat (12) tick();
        // The first three rows corrupt the prior valid nonfinal return; the
        // last three corrupt an already-rewritten final slot exactly when its
        // fence opens. Guard commit must reflect the mailbox's current check.
        if (scenario >= 3) @(negedge clk);
        corrupt_kind = scenario % 3; fence = 1;
        #0.1;
        if (!framing_fault_now || valid || !private_valid)
          $fatal(1, "PRIVATE_LINK_CURRENT_FAULT_NOT_VETOED");
        tick();
        if (!fault || !protocol_fault || reasons != 8'h01 || commit || valid ||
            private_valid || mailbox.request_toggle || commits || reads)
          $fatal(1, "PRIVATE_LINK_FALSE_COMMIT_RECEIPT");
        repeat (24) begin
          tick();
          if (!fault || !protocol_fault || valid || private_valid || job_ready ||
              mailbox.request_toggle || out_valid || commits)
            $fatal(1, "PRIVATE_LINK_FAULT_REUSED");
        end
      end else begin
      repeat (12) tick();
      if (!out_valid || ready || reads || commits != 1 || !busy)
        $fatal(1, "LATE_ACK_COMMITTED_SETUP");
      committed_toggle = mailbox.request_toggle;
      if (scenario == 2) begin
        // Current fault on the edge that receives synchronized ACK. Published
        // data are already immutable, and no new admission may be forgiven.
        drain = 1;
        for (i = 0; i < 3000 &&
             mailbox.acknowledge_sync[0] == mailbox.acknowledge_sync[1]; i = i + 1) tick();
        if (i == 3000 || reads != 512) $fatal(1, "LATE_ACK_SYNC_SETUP");
      end
      @(negedge clk);
      if (scenario == 1) status_valid = 1; else external_fault = 1;
      tick();
      if (!protocol_fault || !reasons || job_ready || private_valid || valid || commit)
        $fatal(1, "LATE_ACK_FAULT_NOT_STICKY");
      @(negedge clk); status_valid = 0; external_fault = 0; drain = 1; job_valid = 1;
      for (i = 0; i < 3000 && (!ready || reads != 512); i = i + 1) tick();
      if (!ready || reads != 512) $fatal(1, "LATE_ACK_PHYSICAL_DRAIN");
      repeat (24) begin
        tick();
        if (!protocol_fault || job_ready || private_valid || valid || commit ||
            commits != 1 || mailbox.request_toggle !== committed_toggle)
          $fatal(1, "LATE_ACK_QUARANTINE_REUSED");
      end
      end
    end
    if (CORRUPT_LINK)
      $display("PRIVATE_LINK_FAULT_PASS nonfinal=3 held_final=3 exact_same_edge_reason=01 no_false_commit=1");
    else
      $display("PRIVATE_BANK_LATE_ACK_PASS cases=3 published_words=1536 reset_recovery=2 same_edge_sync_ack=1");
    $finish;
  end
  initial begin #200000; $fatal(1, "LATE_ACK_WATCHDOG"); end
endmodule

module tb_starlink_pss_explicit_commit_disabled;
  reg clk = 0, slow_clk = 0, resetn = 0, valid = 0;
  always #2.5 clk = !clk;
  always #5.3 slow_clk = !slow_clk;
  reg [1:0] position = 0;
  reg [35:0] data = 0;
  reg last = 0;
  wire [4:0] ready, fault, out_valid, out_last, framing_fault_now;
  wire [35:0] out_data [0:4];
  wire [1:0] out_position [0:4];
  wire [74:0] out_metadata [0:4];
  wire [74:0] metadata = 75'h6123456789abcdef0123;
  integer frame, i, g, reads = 0;
  generate for (genvar n = 0; n < 5; n = n + 1) begin : variants
    wire ignored_authorize = n == 0 ? 1'b0 : n == 1 ? 1'b1 : n == 2 ? 1'bx : 1'bz;
    if (n == 4) begin : omitted
      starlink_pss_block_mailbox #(.ADDRESS_WIDTH(2), .METADATA_WIDTH(75)) dut (
        .input_clk(clk), .input_resetn(resetn), .input_valid(valid),
        .input_ready(ready[n]), .input_fault(fault[n]),
        .input_framing_fault_now(framing_fault_now[n]), .input_data(data),
        .input_position(position), .input_last(last), .input_metadata(metadata),
        .output_clk(slow_clk), .output_resetn(resetn), .output_valid(out_valid[n]),
        .output_ready(1'b1), .output_data(out_data[n]), .output_position(out_position[n]),
        .output_last(out_last[n]), .output_metadata(out_metadata[n])
      );
    end else begin : connected
      starlink_pss_block_mailbox #(.ADDRESS_WIDTH(2), .METADATA_WIDTH(75),
        .EXPLICIT_COMMIT(0)) dut (
        .input_clk(clk), .input_resetn(resetn), .input_valid(valid),
        .input_commit_authorized(ignored_authorize),
        .input_ready(ready[n]), .input_fault(fault[n]),
        .input_framing_fault_now(framing_fault_now[n]), .input_data(data),
        .input_position(position), .input_last(last), .input_metadata(metadata),
        .output_clk(slow_clk), .output_resetn(resetn), .output_valid(out_valid[n]),
        .output_ready(1'b1), .output_data(out_data[n]), .output_position(out_position[n]),
        .output_last(out_last[n]), .output_metadata(out_metadata[n])
      );
    end
  end endgenerate
  always @(posedge slow_clk) if (resetn && out_valid[0]) begin
    if (out_data[0] !== 36'(reads) || out_position[0] !== 2'(reads) ||
        out_last[0] !== (reads % 4 == 3) || out_metadata[0] !== metadata)
      $fatal(1, "DISABLED_COMMIT_LEGACY_PAYLOAD");
    reads = reads + 1;
  end
  always @(posedge clk or negedge clk) begin
    #0.02;
    if (framing_fault_now !== 5'b0) $fatal(1, "DISABLED_COMMIT_FAULT_NOT_INERT");
    for (g = 1; g < 5; g = g + 1)
      if ({ready[g], fault[g], out_valid[g]} !== {ready[0], fault[0], out_valid[0]} ||
          (out_valid[0] && {out_data[g], out_position[g], out_last[g], out_metadata[g]} !==
           {out_data[0], out_position[0], out_last[0], out_metadata[0]}))
        $fatal(1, "DISABLED_COMMIT_NOT_INERT");
  end
  initial begin
    repeat (10) @(negedge clk);
    resetn = 1;
    repeat (12) @(negedge clk);
    for (frame = 0; frame < 4; frame = frame + 1) begin
      for (i = 0; i < 4; i = i + 1) begin
        @(negedge clk); if (!ready[0]) $fatal(1, "DISABLED_COMMIT_READY");
        valid = 1; position = 2'(i); last = i == 3; data = 36'(frame * 4 + i);
      end
      @(negedge clk); valid = 0;
      while (!ready[0]) @(negedge clk);
    end
    if (reads != 16 || fault) $fatal(1, "DISABLED_COMMIT_INVENTORY");
    @(negedge clk); valid = 1; position = 1; last = 0;
    @(negedge clk); valid = 0;
    if (fault !== 5'b11111 || ready || framing_fault_now)
      $fatal(1, "DISABLED_COMMIT_LEGACY_FAULT");
    $display("DISABLED_COMMIT_PASS variants=5 zero_one_x_z_omitted=1 exact_words_each=16 malformed_faults_each=1");
    $finish;
  end
  initial begin #100000; $fatal(1, "DISABLED_COMMIT_WATCHDOG"); end
endmodule

module tb_starlink_pss_explicit_commit_mailbox;
  parameter integer EXPLICIT_COMMIT = 1;
  reg clk = 0, slow_clk = 0, resetn = 0;
  always #2.5 clk = !clk;
  always #5.3 slow_clk = !slow_clk;
  reg valid = 0, last = 0, authorize = 0, drain = 0;
  reg [1:0] position = 0;
  reg [35:0] data = 0;
  reg [74:0] metadata = 75'h6123456789abcdef0123;
  wire ready, fault, out_valid, out_last;
  wire [35:0] out_data;
  wire [1:0] out_position;
  wire [74:0] out_metadata;
  integer i, kind, index, reads = 0, healthy = 0, rejected = 0, held = 0;
  starlink_pss_block_mailbox #(.ADDRESS_WIDTH(2), .METADATA_WIDTH(75),
    .EXPLICIT_COMMIT(EXPLICIT_COMMIT)) dut (
    .input_clk(clk), .input_resetn(resetn), .input_valid(valid),
    .input_commit_authorized(authorize), .input_ready(ready), .input_fault(fault),
    .input_data(data), .input_position(position), .input_last(last),
    .input_metadata(metadata), .output_clk(slow_clk), .output_resetn(resetn),
    .output_valid(out_valid), .output_ready(drain), .output_data(out_data),
    .output_position(out_position), .output_last(out_last), .output_metadata(out_metadata)
  );
  always @(posedge slow_clk) if (resetn && out_valid && drain) begin
    if (out_position !== 2'(reads) || out_last !== (reads == 3) ||
        out_data !== 36'(36'h123456780 + reads) ||
        out_metadata !== 75'h6123456789abcdef0123)
      $fatal(1, "EXPLICIT_MAILBOX_PUBLIC_PAYLOAD");
    reads = reads + 1;
  end
  task tick; @(posedge clk); #0.1; endtask
  task reset_epoch;
    @(negedge clk); resetn = 0; valid = 0; authorize = 0; drain = 0;
    repeat (10) tick();
    @(negedge clk); resetn = 1; reads = 0;
    metadata = 75'h6123456789abcdef0123;
    repeat (12) tick();
    if (!ready || fault || out_valid || dut.request_toggle || dut.write_position)
      $fatal(1, "EXPLICIT_MAILBOX_RESET");
  endtask
  task present(input integer word_index);
    @(negedge clk); valid = 1; position = 2'(word_index); last = word_index == 3;
    data = 36'h123456780 + word_index;
  endtask
  task reject_and_hold;
    tick();
    if (!fault || ready || dut.request_toggle || out_valid)
      $fatal(1, "EXPLICIT_MAILBOX_MALFORMED_PUBLISHED");
    @(negedge clk); authorize = 1;
    repeat (24) begin
      tick();
      if (!fault || ready || dut.request_toggle || out_valid)
        $fatal(1, "EXPLICIT_MAILBOX_QUARANTINE_REUSED");
    end
    rejected = rejected + 1;
  endtask
  initial begin
    // Repeated healthy bank use, including no reset between ACK and admission.
    reset_epoch();
    for (kind = 0; kind < 3; kind = kind + 1) begin
      for (i = 0; i < 4; i = i + 1) begin present(i); tick(); end
      repeat (31) begin
        tick(); held = held + 1;
        if (!ready || fault || out_valid || dut.write_position !== 2'd3 ||
            dut.payload_memory[3] !== data)
          $fatal(1, "EXPLICIT_MAILBOX_UNAUTHORIZED_FINAL");
      end
      @(negedge clk); authorize = 1; tick();
      if (ready || fault) $fatal(1, "EXPLICIT_MAILBOX_COMMIT_OWNERSHIP");
      @(negedge clk); authorize = 0; valid = 0;
      repeat (12) tick();
      if (!out_valid || ready || reads || dut.write_position)
        $fatal(1, "EXPLICIT_MAILBOX_ACK_HOLD");
      drain = 1;
      for (i = 0; i < 100 && (!ready || reads != 4); i = i + 1) tick();
      if (!ready || fault || reads != 4 || dut.write_position)
        $fatal(1, "EXPLICIT_MAILBOX_ACK_REUSE");
      @(negedge clk); drain = 0; reads = 0;
      healthy = healthy + 1;
    end
    // Wrong ordinal/TLAST/metadata at every eligible private position. Final
    // authorization is already high on the corrupt edge: checking cannot lag.
    for (kind = 0; kind < 3; kind = kind + 1)
      for (index = kind == 2 ? 1 : 0; index < 4; index = index + 1) begin
        reset_epoch();
        for (i = 0; i <= index; i = i + 1) begin
          present(i);
          if (i == index) begin
            authorize = 1;
            case (kind)
              0: position = position ^ 1;
              1: last = !last;
              2: metadata[74] = !metadata[74];
            endcase
            reject_and_hold();
          end else tick();
        end
      end
    // Previously written final data is still private: corruption of the held
    // descriptor on the later authorization edge must veto publication too.
    reset_epoch();
    for (i = 0; i < 4; i = i + 1) begin present(i); tick(); end
    repeat (8) tick();
    @(negedge clk); metadata[0] = !metadata[0]; authorize = 1;
    reject_and_hold();
    $display("EXPLICIT_MAILBOX_PASS healthy=%0d malformed=%0d held_rewrites=%0d real_ram=1", healthy, rejected, held);
    $finish;
  end
  initial begin #100000; $fatal(1, "EXPLICIT_MAILBOX_WATCHDOG"); end
endmodule
