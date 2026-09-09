// Actual generated XFFT + isolated synthesizable service, not receiver/capacity qualification.
`timescale 1ns/1ps
module tb_starlink_pss_shared_realtime_xfft_service;
  reg clk = 0, fft_clk = 0;
  always #2.5 fft_clk = !fft_clk;
  initial begin #1.3; forever #5 clk = !clk; end
  reg resetn = 0, fft_resetn = 0;
  reg input_valid = 0, input_last = 0;
  reg [35:0] input_data = 0;
  reg [8:0] input_position = 0;
  reg [69:0] input_metadata = 0;
  wire input_ready, output_valid, output_last, service_fault;
  wire [35:0] output_data;
  wire [8:0] output_position;
  wire [74:0] output_metadata;
  reg reader_enable = 0, reader_stalls = 0;
  integer slow_cycle = 0, cycle = 0;
  wire output_ready = reader_enable && (!reader_stalls || slow_cycle % 11 < 7);
  starlink_pss_shared_realtime_xfft_service dut (
    .clk(clk), .resetn(resetn), .fft_clk(fft_clk), .fft_resetn(fft_resetn),
    .input_valid(input_valid), .input_ready(input_ready), .input_data(input_data),
    .input_position(input_position), .input_last(input_last), .input_metadata(input_metadata),
    .output_valid(output_valid), .output_ready(output_ready), .output_data(output_data),
    .output_position(output_position), .output_last(output_last),
    .output_metadata(output_metadata), .service_fault(service_fault)
  );
  // Independent frozen public guard consumes the same actual checker/core
  // pins, but retains the original input-completion fence and all full input
  // fault checks. It does not receive the new retired-input shortcut.
  wire old_job_ready, old_return_valid, old_return_last, old_busy, old_commit, old_fault;
  wire [35:0] old_return_data;
  wire [8:0] old_return_position;
  wire [74:0] old_return_metadata;
  wire [7:0] old_fault_reasons;
  wire old_final_fence = dut.checked_input_complete && !dut.input_guard_fault && !dut.input_fault_now;
  starlink_pss_realtime_result_guard_ff4229_golden shadow (
    .clk(fft_clk), .resetn(dut.fast_running), .job_valid(dut.job_valid),
    .job_ready(old_job_ready), .job_descriptor(dut.fast_input_metadata),
    .input_bank_reserved(dut.result_guard.input_bank_reserved),
    .output_bank_reserved(dut.result_guard.output_bank_reserved),
    .certified_input_beat(dut.certified_input_beat),
    .certified_input_complete(dut.certified_input_complete),
    .final_fence_certified(old_final_fence), .external_fault_now(dut.external_fault_now),
    .core_event_frame_started(dut.event_frame), .core_output_tdata(dut.core_output_data),
    .core_output_tuser(dut.core_output_user), .core_output_tvalid(dut.core_output_valid),
    .core_output_tlast(dut.core_output_last), .core_status_tdata(dut.core_status_data),
    .core_status_tvalid(dut.core_status_valid), .mailbox_input_valid(old_return_valid),
    .mailbox_input_ready(dut.output_mailbox_ready),
    .mailbox_input_fault(dut.output_mailbox_fault || dut.output_mailbox_framing_fault_now),
    .mailbox_input_data(old_return_data), .mailbox_input_position(old_return_position),
    .mailbox_input_last(old_return_last), .mailbox_input_metadata(old_return_metadata),
    .busy(old_busy), .commit_pulse(old_commit), .protocol_fault(old_fault),
    .fault_reasons(old_fault_reasons)
  );
  integer shadow_rows = 0, retired_final_rows = 0, retired_ack_rows = 0, idle_input_rows = 0;
  always @(posedge fft_clk or negedge fft_clk) begin
    #0.2;
    if (dut.fast_running) begin
      shadow_rows = shadow_rows + 1;
      if (dut.return_commit_valid !== (old_return_valid && old_return_last))
        $fatal(1, "FINAL_AUTH_SERVICE_MISMATCH");
      if ({dut.job_ready, dut.return_valid, dut.result_busy, dut.result_commit,
           dut.result_fault, dut.result_guard.fault_reasons} !==
          {old_job_ready, old_return_valid, old_busy, old_commit, old_fault, old_fault_reasons})
        $fatal(1, "RETIRED_SERVICE_PUBLIC_MISMATCH cycle=%0d", cycle);
      if (dut.return_valid &&
          {dut.return_data, dut.return_position, dut.return_last, dut.return_metadata} !==
          {old_return_data, old_return_position, old_return_last, old_return_metadata})
        $fatal(1, "RETIRED_SERVICE_PAYLOAD_MISMATCH");
      if (dut.final_fence !== old_final_fence)
        $fatal(1, "RETIRED_SERVICE_FENCE_MISMATCH");
      if (!dut.result_guard.active && !dut.result_fault) begin
        idle_input_rows = idle_input_rows + 1;
        if ((dut.core_aresetn && !dut.checked_input_complete) ||
            dut.phase_input_fault_now !== (dut.external_fault_now ||
              dut.certified_input_beat || dut.certified_input_complete))
          $fatal(1, "RETIRED_SERVICE_IDLE_PREMISE_MISSING");
      end
      if ((dut.result_guard.active && dut.result_guard.return_valid &&
           dut.result_guard.return_last && dut.result_guard.final_qualified) ||
          dut.result_guard.awaiting_ack) begin
        if (!dut.checked_input_complete ||
            dut.phase_input_fault_now !== (dut.external_fault_now ||
              dut.certified_input_beat || dut.certified_input_complete))
          $fatal(1, "RETIRED_SERVICE_CALLER_PREMISE_MISSING");
        if (dut.result_guard.awaiting_ack) retired_ack_rows = retired_ack_rows + 1;
        else retired_final_rows = retired_final_rows + 1;
      end
    end
  end
  reg [31:0] samples [0:1405];
  reg [35:0] forward_values [0:1535], products [0:1535], inverse_values [0:1535];
  reg [4:0] forward_exponents [0:2], inverse_exponents [0:2];
  reg [69:0] descriptors [0:15];
  integer fixtures [0:15];
  reg directions [0:15];
  integer start_cycles [0:15];
  integer expected_jobs = 0, admitted = 0, checker_admitted = 0;
  integer current_job = 0, delivered = 0, raw_words = 0, statuses = 0, frames = 0;
  integer commits = 0, published_jobs = 0, published_word = 0;
  integer total_words = 0, healthy_jobs = 0, starvation_cases = 0, final_veto_cases = 0;
  integer reset_cases = 0, bad_bank_cases = 0, ack_fault_cases = 0;
  integer configure_reset_cases = 0, partial_input_reset_cases = 0;
  integer duplicate_phase_cases = 0;
  reg injecting_duplicate_start = 0;
  integer reset_clocks = 0, config_cycle = -1, admission_cycle = -1;
  integer first_local_fault = -1, first_vendor_halt = -1;
  integer max_job_interval = 0, max_pair_interval = 0, max_commit_latency = 0;
  reg previous_core_resetn = 0, expected_fault = 0, measure_lane = 0;
  reg previous_stall = 0;
  reg [120:0] held_output;
  reg [35:0] expected_word;
  reg [4:0] expected_exponent;
  integer trace_file, i, direction, gap_case, kind, side, bad_position;

  always @(posedge fft_clk) begin
    cycle = cycle + 1;
    if (cycle > 800000) $fatal(1, "realtime candidate bench watchdog");
    $fdisplay(trace_file, "%0d,%0d,%0b,%0b,%0b,%0b,%0b,%0d,%0b,%0b,%0b,%0b,%0b,%0b,%0b,%0b,%h",
      cycle, dut.state, dut.fast_running, dut.core_aresetn, dut.job_accept,
      dut.input_job_start, dut.config_valid && dut.config_ready, delivered,
      dut.certified_input_beat, dut.certified_input_complete, dut.final_fence,
      dut.input_fault_now, dut.vendor_fault_now, dut.result_commit,
      dut.result_busy, dut.fast_input_valid, dut.engine_metadata);
    if (!dut.fast_running) begin
      admitted = 0; checker_admitted = 0; delivered = 0; raw_words = 0;
      statuses = 0; frames = 0; commits = 0; reset_clocks = 0;
      previous_core_resetn = 0; config_cycle = -1; admission_cycle = -1;
      first_local_fault = -1; first_vendor_halt = -1;
    end else begin
      if (!dut.core_aresetn) reset_clocks = reset_clocks + 1;
      if (dut.core_aresetn && !previous_core_resetn) begin
        if (reset_clocks < 2) $fatal(1, "core had fewer than two full reset clocks");
        reset_clocks = 0;
      end
      previous_core_resetn = dut.core_aresetn;
      if (dut.job_accept) begin
        current_job = admitted;
        if (current_job >= expected_jobs || dut.fast_input_metadata !== descriptors[current_job] ||
            !dut.fast_input_valid || dut.fast_input_position != 0 || !dut.output_mailbox_ready)
          $fatal(1, "job admitted without committed prefetched input / owned output");
        if (measure_lane && admitted > 0 && cycle-start_cycles[admitted-1] > max_job_interval)
          max_job_interval = cycle-start_cycles[admitted-1];
        if (measure_lane && admitted > 1 && cycle-start_cycles[admitted-2] > max_pair_interval)
          max_pair_interval = cycle-start_cycles[admitted-2];
        start_cycles[admitted] = cycle;
        admission_cycle = cycle; config_cycle = -1;
        admitted = admitted + 1;
        delivered = 0; raw_words = 0; statuses = 0; frames = 0;
      end
      if (dut.input_job_start && !injecting_duplicate_start) begin
        if (cycle != admission_cycle + 1 || !dut.core_aresetn ||
            dut.engine_metadata !== descriptors[current_job])
          $fatal(1, "registered checker admission / fast descriptor mismatch");
        checker_admitted = checker_admitted + 1;
      end
      if (dut.config_valid && dut.config_ready) config_cycle = cycle;
      if (dut.certified_input_beat) begin
        if (checker_admitted != admitted || config_cycle < 0 || cycle <= config_cycle + 1)
          $fatal(1, "input enabled before registered admission/configuration separation");
        delivered = delivered + 1;
      end
      if (dut.certified_input_complete && delivered != 512)
        $fatal(1, "incorrect local input completion count");
      if (dut.final_fence && (!dut.checked_input_complete || delivered != 512 ||
          dut.input_guard_fault || dut.input_fault_now))
        $fatal(1, "cause-coverage fence lacks full checked input delivery");
      if (dut.input_fault_now && first_local_fault < 0) first_local_fault = cycle;
      if (dut.event_input_halt && first_vendor_halt < 0) first_vendor_halt = cycle;
      if (dut.event_frame) frames = frames + 1;
      expected_exponent = directions[current_job] ? inverse_exponents[fixtures[current_job]] :
                                                   forward_exponents[fixtures[current_job]];
      if (dut.core_status_valid) begin
        statuses = statuses + 1;
        if (!expected_fault && dut.core_status_data !== {3'b0, expected_exponent})
          $fatal(1, "independent status numeric mismatch");
      end
      if (dut.core_output_valid) begin
        if (!expected_fault) begin
          if (raw_words >= 512) $fatal(1, "extra healthy raw output");
          expected_word = directions[current_job] ?
            inverse_values[fixtures[current_job]*512+raw_words] :
            forward_values[fixtures[current_job]*512+raw_words];
          if ({dut.core_output_data[41:24], dut.core_output_data[17:0]} !== expected_word ||
              dut.core_output_user !== {3'b0, expected_exponent, 7'b0, 9'(raw_words)} ||
              dut.core_output_last !== (raw_words == 511))
            $fatal(1, "raw service FFT word/exponent/order mismatch");
        end
        raw_words = raw_words + 1;
      end
      if (dut.return_valid && dut.output_mailbox_ready && dut.return_last) begin
        if (expected_fault || delivered != 512 || raw_words != 512 || statuses != 1 ||
            frames != 1 || !dut.final_fence || dut.external_fault_now)
          $fatal(1, "service committed an unqualified/faulted final word");
        commits = commits + 1;
        if (measure_lane && cycle-start_cycles[current_job] > max_commit_latency)
          max_commit_latency = cycle-start_cycles[current_job];
      end
      if (!expected_fault && (dut.fast_fault || service_fault))
        $fatal(1, "healthy service fault state=%0d", dut.state);
    end
  end
  always @(posedge clk) begin
    slow_cycle = slow_cycle + 1;
    if (!dut.slow_running) begin
      published_jobs = 0; published_word = 0; previous_stall = 0;
    end else begin
      if (previous_stall && output_valid &&
          {output_data, output_position, output_last, output_metadata} !== held_output)
        $fatal(1, "service changed stalled result");
      previous_stall = output_valid && !output_ready;
      held_output = {output_data, output_position, output_last, output_metadata};
      if (output_valid && output_ready) begin
        if (expected_fault || published_jobs >= expected_jobs || commits <= published_jobs)
          $fatal(1, "uncommitted/quarantined service output escaped");
        expected_word = directions[published_jobs] ?
          inverse_values[fixtures[published_jobs]*512+published_word] :
          forward_values[fixtures[published_jobs]*512+published_word];
        expected_exponent = directions[published_jobs] ? inverse_exponents[fixtures[published_jobs]] :
                                                       forward_exponents[fixtures[published_jobs]];
        if (output_data !== expected_word || output_position !== 9'(published_word) ||
            output_last !== (published_word == 511) ||
            output_metadata !== {descriptors[published_jobs], expected_exponent})
          $fatal(1, "published frozen service numeric/descriptor mismatch job=%0d word=%0d",
                 published_jobs, published_word);
        published_word = published_word + 1; total_words = total_words + 1;
        if (output_last) begin
          $display("RT_SERVICE_RESULT fixture=%0d inverse=%0d words=512 descriptor=%h",
                   fixtures[published_jobs], directions[published_jobs], descriptors[published_jobs]);
          published_jobs = published_jobs + 1; published_word = 0;
          healthy_jobs = healthy_jobs + 1;
        end
      end
    end
  end
  task automatic tick;
    @(posedge fft_clk); #0.1;
  endtask
  task automatic reset_epoch(input integer reset_side);
    @(negedge fft_clk);
    input_valid = 0; reader_enable = 0; reader_stalls = 0; measure_lane = 0;
    if (reset_side != 2) resetn = 0;
    if (reset_side != 1) fft_resetn = 0;
    repeat (20) tick();
    expected_jobs = 0; expected_fault = 0;
    @(negedge fft_clk); resetn = 1; fft_resetn = 1;
    repeat (16) tick();
    if (service_fault || dut.result_busy || dut.fast_input_valid || output_valid ||
        dut.input_mailbox.request_toggle || dut.output_mailbox.request_toggle)
      $fatal(1, "common service reset leaked a stale mailbox/core epoch");
  endtask
  task automatic send_block(input integer index, input integer fixture, input bit inverse);
    integer p;
    begin
      fixtures[index] = fixture; directions[index] = inverse;
      descriptors[index] = {inverse, 64'(64'h200000000+index*447+fixture*10000),
                            inverse ? forward_exponents[fixture] : 5'b0};
      expected_jobs = index + 1;
      for (p = 0; p < 512; p = p + 1) begin
        @(negedge clk);
        input_valid = 1; input_position = p; input_last = p == 511;
        input_metadata = descriptors[index];
        input_data = inverse ? products[fixture*512+p] :
          {samples[fixture*447+p][31:16], 2'b0, samples[fixture*447+p][15:0], 2'b0};
        @(posedge clk);
        while (!input_ready) @(posedge clk);
      end
      @(negedge clk); input_valid = 0;
    end
  endtask
  task automatic await_results(input integer count);
    integer waited;
    waited = 0;
    while ((published_jobs != count || dut.state != dut.WAIT_BANK) && waited < 25000) begin
      tick(); waited = waited + 1;
    end
    if (published_jobs != count || dut.state != dut.WAIT_BANK || service_fault)
      $fatal(1, "service failed bounded output/ACK/reset/config lifecycle");
  endtask
  task automatic await_fault(input integer expected_commits);
    integer waited;
    waited = 0;
    // A slow input-mailbox fault is immediately local, but its sticky fast
    // observation intentionally crosses two flops before result quarantine.
    while (!(service_fault && dut.fast_fault && dut.result_fault) && waited < 100) begin
      tick(); waited = waited + 1;
    end
    if (!service_fault || !dut.fast_fault || !dut.result_fault ||
        commits != expected_commits || published_jobs || published_word)
      $fatal(1, "service quarantine/CDC evidence mismatch commits=%0d", commits);
    repeat (40) tick();
    if (output_valid || input_ready || dut.job_ready) $fatal(1, "faulted service reopened");
  endtask
  task automatic healthy_recovery(input integer fixture, input bit inverse);
    reset_epoch(0); reader_enable = 1; reader_stalls = 1;
    send_block(0, fixture, inverse); await_results(1);
  endtask
  task automatic prepare_prefetched_pair;
    reg request_hold;
    begin
      reset_epoch(0);
      send_block(0, 0, 0); send_block(1, 1, 1);
      while (commits != 1 || !dut.fast_input_valid) tick();
      if (admitted != 1 || dut.fast_input_position != 0 ||
          dut.fast_input_metadata !== descriptors[1] ||
          dut.engine_metadata !== descriptors[0] || !dut.core_aresetn)
        $fatal(1, "prefetched next bank or held prior descriptor was lost");
      request_hold = dut.input_mailbox.request_toggle;
      repeat (64) tick();
      if (admitted != 1 || dut.input_mailbox.request_toggle !== request_hold ||
          dut.fast_input_metadata !== descriptors[1] || !dut.core_aresetn)
        $fatal(1, "ACK stall changed queued bank / prematurely reset core");
    end
  endtask
  task automatic interrupt_active_job(input integer reset_side, input bit partial_input);
    integer waited;
    begin
      reset_epoch(0); send_block(0, reset_side, partial_input);
      waited = 0;
      while ((partial_input ? delivered != 128 : dut.state != dut.CONFIGURE) &&
             waited < 3000) begin
        tick(); waited = waited + 1;
      end
      if (waited == 3000 || admitted != 1 || checker_admitted != 1 ||
          commits || published_jobs || published_word ||
          dut.output_mailbox.request_toggle || !dut.result_busy)
        $fatal(1, "active-reset target missing or prematurely published");
      if (partial_input) begin
        if (dut.state != dut.RUN_JOB || delivered != 128 || config_cycle < 0 ||
            dut.checked_input_complete || dut.final_fence)
          $fatal(1, "partial-input reset did not interrupt an incomplete checked frame");
        partial_input_reset_cases = partial_input_reset_cases + 1;
      end else begin
        if (config_cycle != -1 || delivered || dut.engine_input_enable ||
            dut.checked_input_complete || dut.final_fence)
          $fatal(1, "configuration reset was not before the config handshake");
        configure_reset_cases = configure_reset_cases + 1;
      end
      // reset_epoch asserts the selected raw reset at the next falling fast
      // edge, still in the observed phase. Local reset release chains retain
      // their real synchronization latency; no immediate CDC revocation claim.
      $display("RT_SERVICE_ACTIVE_RESET raw_side=%0d phase=%s deliveries=%0d state=%0d",
               reset_side, partial_input ? "PARTIAL_INPUT" : "CONFIGURE", delivered, dut.state);
      reset_epoch(reset_side); reset_cases = reset_cases + 1;
      reader_enable = 1; reader_stalls = 1;
      send_block(0, reset_side, !partial_input); await_results(1);
    end
  endtask
  initial begin
    trace_file = $fopen("realtime_service_trace.csv", "w");
    if (!trace_file) $fatal(1, "cannot create service trace");
    $fdisplay(trace_file, "cycle,state,fast_running,core_resetn,result_admission,input_admission,config_handshake,deliveries,certified_beat,certified_complete,cause_fence,input_fault_now,vendor_fault_now,result_commit,result_busy,prefetched_valid,engine_metadata");
    $readmemh("samples_ci16.mem", samples); $readmemh("forward_q17.mem", forward_values);
    $readmemh("product_q17.mem", products); $readmemh("inverse_q17.mem", inverse_values);
    $readmemh("forward_exponents.mem", forward_exponents);
    $readmemh("inverse_exponents.mem", inverse_exponents);
    reset_epoch(0); reader_enable = 1; measure_lane = 1;
    for (i = 0; i < 6; i = i + 1) send_block(i, i/2, (i%2) != 0);
    await_results(6);
    $display("RT_SERVICE_LATENCY fast_clock_ns=5 max_commit_cycles=%0d max_job_admission_interval_cycles=%0d max_pair_admission_interval_cycles=%0d includes_slow_ACK_reset_config=1 SIX_JOBS_NOT_CAPACITY_QUALIFICATION",
             max_commit_latency, max_job_interval, max_pair_interval);
    prepare_prefetched_pair(); reader_enable = 1; reader_stalls = 1; await_results(2);
    for (direction = 0; direction < 2; direction = direction + 1)
      for (gap_case = 0; gap_case < 3; gap_case = gap_case + 1) begin
        reset_epoch(0); expected_fault = 1;
        send_block(0, gap_case, direction != 0);
        while (delivered < (gap_case == 0 ? 1 : gap_case == 1 ? 255 : 511)) tick();
        @(negedge fft_clk);
        force dut.fast_input_valid = 1'b0;
        force dut.fast_input_ready = 1'b0;
        while (!dut.core_input_ready) @(negedge fft_clk);
        #0.1;
        if (!dut.input_fault_now || dut.certified_input_beat || dut.return_valid)
          $fatal(1, "missing active demand not rejected before delivery/publication");
        tick();
        @(negedge fft_clk); release dut.fast_input_valid; release dut.fast_input_ready;
        await_fault(0);
        if (first_local_fault < 0 || first_vendor_halt <= first_local_fault)
          $fatal(1, "local input failure did not precede vendor halt");
        starvation_cases = starvation_cases + 1;
        healthy_recovery((gap_case+1)%3, direction == 0);
      end
    // All delayed vendor error classes remain direct final-edge commit vetoes.
    for (kind = 0; kind < 3; kind = kind + 1) begin
      reset_epoch(0); send_block(0, kind, (kind%2) != 0);
      while (!(dut.result_guard.return_valid && dut.result_guard.return_last)) @(negedge fft_clk);
      expected_fault = 1;
      case (kind)
        0: force dut.event_last_missing = 1'b1;
        1: force dut.event_last_unexpected = 1'b1;
        2: force dut.event_input_halt = 1'b1;
      endcase
      #0.1;
      if (dut.return_valid) $fatal(1, "delayed vendor event missed same-cycle final veto");
      tick(); @(negedge fft_clk);
      release dut.event_last_missing; release dut.event_last_unexpected; release dut.event_input_halt;
      await_fault(0); final_veto_cases = final_veto_cases + 1;
      healthy_recovery(kind, (kind%2) == 0);
    end
    // Both a partial-bank and framing-correct final-word identity mismatch
    // remain private: neither may toggle the request or admit a descriptor.
    for (kind = 0; kind < 2; kind = kind + 1) begin
      reset_epoch(0); expected_fault = 1;
      bad_position = kind == 0 ? 10 : 511;
      for (i = 0; i <= bad_position; i = i + 1) begin
        @(negedge clk); input_valid = 1; input_position = i;
        input_last = i == 511;
        input_metadata = i == bad_position ? 70'h124 : 70'h123; input_data = i;
        @(posedge clk);
        if (!input_ready) $fatal(1, "malformed bank stimulus was not accepted");
      end
      @(negedge clk); input_valid = 0;
      await_fault(0);
      if (admitted || dut.input_mailbox.request_toggle) $fatal(1, "malformed slow bank admitted");
      $display("RT_SERVICE_BAD_BANK metadata_mismatch_position=%0d no_admission_or_commit=1", bad_position);
      bad_bank_cases = bad_bank_cases + 1; healthy_recovery(kind, kind != 0);
    end
    for (side = 1; side <= 2; side = side + 1) begin
      prepare_prefetched_pair(); reset_epoch(side); reset_cases = reset_cases + 1;
      reader_enable = 1; send_block(0, side, side == 1); await_results(1);
      interrupt_active_job(side, 0);
      interrupt_active_job(side, 1);
    end
    // After commit there is no revocation claim, but a raw late event must still
    // poison the persistent service while the actual slow ACK is outstanding.
    reset_epoch(0); send_block(0, 0, 0);
    while (commits != 1 || dut.state != dut.ACK_DRAIN) tick();
    @(negedge fft_clk); expected_fault = 1; force dut.event_last_missing = 1'b1;
    tick(); @(negedge fft_clk); release dut.event_last_missing;
    await_fault(1); ack_fault_cases = ack_fault_cases + 1;
    // Explicitly violate the input checker's one-job-per-reset public start
    // contract at final retirement and during ACK. The scoreboard exception
    // names only this injected duplicate token, not an admitted normal job.
    for (kind = 0; kind < 2; kind = kind + 1) begin
      reset_epoch(0); send_block(0, kind, kind != 0);
      if (kind == 0) begin
        while (!(dut.result_guard.return_valid && dut.result_guard.return_last)) @(negedge fft_clk);
      end else begin
        while (commits != 1 || dut.state != dut.ACK_DRAIN) tick();
        @(negedge fft_clk);
      end
      expected_fault = 1; injecting_duplicate_start = 1;
      force dut.input_job_start = 1'b1;
      #0.1;
      if (!dut.input_fault_now || !dut.phase_input_fault_now || dut.return_valid ||
          (kind == 0 && dut.final_fence))
        $fatal(1, "RETIRED_SERVICE_DUPLICATE_VETO_MISSING");
      tick(); @(negedge fft_clk); release dut.input_job_start;
      tick(); @(negedge fft_clk); injecting_duplicate_start = 0;
      await_fault(kind); duplicate_phase_cases = duplicate_phase_cases + 1;
    end
    healthy_recovery(2, 1);
    if (healthy_jobs != 26 || total_words != 13312 || starvation_cases != 6 ||
        final_veto_cases != 3 || bad_bank_cases != 2 || reset_cases != 6 ||
        configure_reset_cases != 2 || partial_input_reset_cases != 2 || ack_fault_cases != 1)
      $fatal(1, "service candidate test inventory mismatch");
    if (shadow_rows < 1000 || retired_final_rows < 26 || retired_ack_rows < 26 || idle_input_rows < 26 || duplicate_phase_cases != 2)
      $fatal(1, "RETIRED_SERVICE_SHADOW_COVERAGE_MISSING");
    $display("RETIRED_SERVICE_SHADOW_PASS public_golden=1 original_fence=1 actual_input_checker=1 actual_FFT=1 idle_final_and_ACK_premises=1");
    $display("RETIRED_SERVICE_DUPLICATE_PASS final=1 ACK=1 same_edge_veto=1 actual_checker_fault=1");
    $display("RETIRED_SERVICE_SHADOW_COUNTS comparisons=%0d final_rows=%0d ACK_rows=%0d idle_rows=%0d", shadow_rows, retired_final_rows, retired_ack_rows, idle_input_rows);
    $display("REALTIME_SERVICE_CANDIDATE_PASS healthy_jobs=26 exact_words=13312 starvation_cases=6 final_veto_cases=3 malformed_bank_cases=2 independent_reset_cases=6 configure_reset_cases=2 partial_input_reset_cases=2 postcommit_ACK_fault_cases=1 CAUSE_FENCE_REVIEW_REQUIRED CAPACITY_AND_PHYSICAL_UNQUALIFIED");
    $fclose(trace_file); $finish;
  end
endmodule
