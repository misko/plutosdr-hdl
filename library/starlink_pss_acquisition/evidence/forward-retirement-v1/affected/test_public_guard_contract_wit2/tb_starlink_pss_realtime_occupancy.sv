// Reachable public-only differential stimulus, also usable with a synthesized
// guard netlist. Independent golden is the unchanged ff4229 public contract.
// The downstream is an ACK model here, not a RAM/CDC mailbox or actual FFT.
`timescale 1ns/1ps
module tb_starlink_pss_realtime_occupancy;
  reg clk = 0;
  always #2.5 clk = !clk;
  reg resetn = 0, job_valid = 0;
  reg [69:0] job_descriptor = 0;
  reg input_bank_reserved = 1, output_bank_reserved = 1;
  reg certified_input_beat = 0, certified_input_complete = 0;
  reg final_fence_certified = 1, external_fault_now = 0;
  wire phase_input_fault_now = certified_input_beat || certified_input_complete; // Default mode must ignore this input.
  wire completed_input_certified = 1'bz, completed_input_fault_now = 1'bz;
  wire preflight_fault_evidence_now = 1'bz;
  reg core_event_frame_started = 0;
  reg [47:0] core_output_tdata = 0;
  reg [23:0] core_output_tuser = 0;
  reg core_output_tvalid = 0, core_output_tlast = 0;
  reg [7:0] core_status_tdata = 0;
  reg core_status_tvalid = 0, mailbox_input_ready = 1, mailbox_input_fault = 0;
  wire job_ready, mailbox_input_valid, mailbox_private_valid, mailbox_input_last, busy;
  wire commit_pulse, protocol_fault;
  wire mailbox_commit_valid;
  wire [35:0] mailbox_input_data;
  wire [8:0] mailbox_input_position;
  wire [74:0] mailbox_input_metadata;
  wire [7:0] fault_reasons;
  wire old_ready, old_valid, old_last, old_busy, old_commit, old_fault;
  wire [35:0] old_data;
  wire [8:0] old_position;
  wire [74:0] old_metadata;
  wire [7:0] old_reasons;
  starlink_pss_realtime_result_guard #(.USE_PHASE_INPUT_FAULT(1)) dut (
    .inverse_phase(1'b0), .forward_mailbox_fault(1'b0), .forward_retirement_valid(), .*);
  starlink_pss_realtime_result_guard_ff4229_golden golden (
    .clk(clk), .resetn(resetn), .job_valid(job_valid), .job_descriptor(job_descriptor),
    .input_bank_reserved(input_bank_reserved), .output_bank_reserved(output_bank_reserved),
    .certified_input_beat(certified_input_beat), .certified_input_complete(certified_input_complete),
    .final_fence_certified(final_fence_certified), .external_fault_now(external_fault_now),
    .core_event_frame_started(core_event_frame_started), .core_output_tdata(core_output_tdata),
    .core_output_tuser(core_output_tuser), .core_output_tvalid(core_output_tvalid),
    .core_output_tlast(core_output_tlast), .core_status_tdata(core_status_tdata),
    .core_status_tvalid(core_status_tvalid), .mailbox_input_ready(mailbox_input_ready),
    .mailbox_input_fault(mailbox_input_fault), .job_ready(old_ready), .mailbox_input_valid(old_valid),
    .mailbox_input_data(old_data), .mailbox_input_position(old_position),
    .mailbox_input_last(old_last), .mailbox_input_metadata(old_metadata), .busy(old_busy),
    .commit_pulse(old_commit), .protocol_fault(old_fault), .fault_reasons(old_reasons));
  integer words = 0, comparisons = 0, jobs = 0, fault_cases = 0, healthy_cases = 0;
  integer events, ready, n;
  reg check_enabled = 0;
  reg [7:0] expected_reasons;
  task automatic check_public;
    begin
      comparisons = comparisons + 1;
      if ({job_ready, mailbox_input_valid, busy, commit_pulse, protocol_fault, fault_reasons} !==
          {old_ready, old_valid, old_busy, old_commit, old_fault, old_reasons})
        $fatal(1, "OCCUPANCY_PUBLIC_MISMATCH events=%0d ready=%0d time=%0t new=%h old=%h",
          events, ready, $time,
          {job_ready, mailbox_input_valid, busy, commit_pulse, protocol_fault, fault_reasons},
          {old_ready, old_valid, old_busy, old_commit, old_fault, old_reasons});
      if (mailbox_input_valid &&
          {mailbox_input_data, mailbox_input_position, mailbox_input_last, mailbox_input_metadata} !==
          {old_data, old_position, old_last, old_metadata})
        $fatal(1, "OCCUPANCY_PAYLOAD_MISMATCH");
      if (mailbox_commit_valid !== (old_valid && old_last))
        $fatal(1, "FINAL_AUTH_PUBLIC_MISMATCH");
      if (protocol_fault && mailbox_private_valid) $fatal(1, "OCCUPANCY_PRIVATE_ESCAPE");
    end
  endtask
  always @(posedge clk or negedge clk) if (check_enabled) begin
    if (clk && mailbox_input_valid && mailbox_input_ready) words = words + 1;
    // Unmodified UNISIM FDCE has a 100 ps clock-to-Q functional-model delay.
    // Compare after that delay, still within the same 5 ns cycle; no SDF claim.
    #0.2; check_public();
  end
  task automatic tick;
    begin @(posedge clk); #0.3; end
  endtask
  task automatic clear_events;
    begin
      external_fault_now = 0; mailbox_input_fault = 0;
      certified_input_beat = 0; certified_input_complete = 0;
      core_event_frame_started = 0; core_status_tvalid = 0; core_output_tvalid = 0;
    end
  endtask
  initial begin
    // Allow the real unisim netlist's power-up GSR to finish before comparison.
    #120;
    // Exercise pin transitions under reset before settling the first epoch.
    // This also initializes event-driven vendor LUT models when a simulator
    // elaborates declaration-initialized inputs before their sensitivity blocks.
    {core_output_tvalid, core_status_tvalid, core_event_frame_started,
     certified_input_complete, certified_input_beat, mailbox_input_fault,
     external_fault_now} = 7'h7f;
    input_bank_reserved = 0; output_bank_reserved = 0; mailbox_input_ready = 0;
    #1;
    for (ready = 0; ready < 2; ready = ready + 1)
      for (events = 0; events < 128; events = events + 1) begin
        @(negedge clk); resetn = 0; clear_events(); job_valid = 0;
        input_bank_reserved = 1; output_bank_reserved = 1; mailbox_input_ready = 1;
        tick(); @(negedge clk); resetn = 1; check_enabled = 1; #0.3;
        if (!job_ready) $fatal(1, "OCCUPANCY_RESET_ADMISSION");
        job_descriptor = 70'h1234567800 + jobs; job_valid = 1;
        tick();
        if (!busy || job_ready || protocol_fault) $fatal(1, "OCCUPANCY_ADMISSION");
        @(negedge clk); job_valid = 0;
        for (n = 0; n < 512; n = n + 1) begin
          certified_input_beat = 1; certified_input_complete = n == 511;
          core_event_frame_started = n == 0;
          tick(); @(negedge clk);
        end
        clear_events();
        for (n = 0; n < 512; n = n + 1) begin
          core_output_tvalid = 1; core_output_tlast = n == 511;
          core_output_tdata = {24'(n * 3), 24'(n * 7)};
          core_output_tuser = {3'b0, 5'd3, 7'b0, 9'(n)};
          core_status_tvalid = n == 0; core_status_tdata = 3;
          tick(); @(negedge clk);
        end
        clear_events(); tick();
        if (!commit_pulse || !busy || protocol_fault) $fatal(1, "OCCUPANCY_FINAL_COMMIT");
        jobs = jobs + 1;
        @(negedge clk); mailbox_input_ready = 0;
        repeat (3) begin
          tick();
          if (!busy || commit_pulse || mailbox_input_valid || job_ready || protocol_fault)
            $fatal(1, "OCCUPANCY_ACK_HOLD");
          @(negedge clk);
        end
        // Every seven-orphan combination, with ACK unavailable or arriving.
        {core_output_tvalid, core_status_tvalid, core_event_frame_started,
         certified_input_complete, certified_input_beat, mailbox_input_fault,
         external_fault_now} = 7'(events);
        mailbox_input_ready = ready;
        expected_reasons = {2'b00, events[6], events[5], events[4],
          events[3] || events[2], 1'b0, events[1] || events[0]};
        tick();
        if (fault_reasons !== expected_reasons || busy !== (!ready || events != 0) ||
            commit_pulse || mailbox_input_valid || mailbox_private_valid)
          $fatal(1, "OCCUPANCY_ACK_EDGE events=%0d ready=%0d reasons=%h busy=%b",
            events, ready, fault_reasons, busy);
        @(negedge clk); clear_events(); mailbox_input_ready = 1;
        repeat (3) begin
          tick();
          if (busy !== (events != 0) || fault_reasons !== expected_reasons ||
              job_ready !== (events == 0)) $fatal(1, "OCCUPANCY_ACK_RETENTION");
          @(negedge clk);
        end
        if (events != 0) begin
          // Next-cycle orphan reasons must stay exact after private-state clear.
          external_fault_now = 1; certified_input_beat = 1;
          core_event_frame_started = 1; core_status_tvalid = 1; core_output_tvalid = 1;
          tick();
          if (fault_reasons !== 8'h3d || !busy || job_ready || mailbox_input_valid)
            $fatal(1, "OCCUPANCY_STICKY_ORPHAN");
          fault_cases = fault_cases + 1;
        end else healthy_cases = healthy_cases + 1;
      end
    if (jobs != 256 || words != 131072 || fault_cases != 254 || healthy_cases != 2 ||
        comparisons < 500000) $fatal(1, "OCCUPANCY_INVENTORY");
    $display("OCCUPANCY_REACHABLE_PASS jobs=256 exact_words=131072 ack_fault_cases=254 healthy_ack_cases=2 public_golden=1 no_internal_deposits=1");
    $finish;
  end
  initial begin #2000000; $fatal(1, "OCCUPANCY_TIMEOUT"); end
endmodule
