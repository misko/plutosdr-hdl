// ISOLATED actual-generated-core + two real-mailbox numeric/protocol harness.
// The coordinator below is TESTBENCH ONLY, not a production service. In
// particular assumed_final_fence is an explicitly supplied experimental premise,
// NOT a proof of any universal bound on delayed vendor events.
`timescale 1ns/1ps
module tb_starlink_pss_realtime_guarded_mailbox_probe;
  reg fft_clk = 0, slow_clk = 0;
  always #2.5 fft_clk = !fft_clk;
  initial begin #1.3; forever #5 slow_clk = !slow_clk; end
  reg fast_resetn = 0, slow_resetn = 0, core_resetn = 0;
  wire common_resetn = fast_resetn && slow_resetn;
  reg [1:0] fast_release = 0;
  always @(posedge fft_clk or negedge common_resetn)
    if (!common_resetn) fast_release <= 0;
    else fast_release <= {fast_release[0], 1'b1};
  wire resetn = fast_release[1];

  reg source_valid = 0, source_last = 0;
  reg [35:0] source_data = 0;
  reg [8:0] source_position = 0;
  reg [69:0] descriptor = 0;
  wire source_ready, source_fault;
  wire bank_valid, bank_last;
  wire [35:0] bank_data;
  wire [8:0] bank_position;
  wire [69:0] bank_metadata;
  wire bank_ready;
  starlink_pss_block_mailbox input_mailbox (
    .input_clk(slow_clk), .input_resetn(slow_resetn), .input_valid(source_valid),
    .input_ready(source_ready), .input_data(source_data), .input_position(source_position),
    .input_last(source_last), .input_metadata(descriptor), .input_fault(source_fault),
    .output_clk(fft_clk), .output_resetn(fast_resetn), .output_valid(bank_valid),
    .output_ready(bank_ready), .output_data(bank_data), .output_position(bank_position),
    .output_last(bank_last), .output_metadata(bank_metadata)
  );

  reg job_valid = 0, input_enable = 0;
  wire job_ready;
  reg input_reserved = 0, output_reserved = 0;
  reg input_job_start = 0;
  // Break the potential job_ready -> duplicate_start -> fault -> job_ready loop.
  // Result admission is edge N; input admission is a registered token at N+1.
  always @(posedge fft_clk or negedge resetn)
    if (!resetn) input_job_start <= 0;
    else input_job_start <= job_valid && job_ready;
  reg inject_gap = 0;
  wire [47:0] core_input_data;
  wire core_input_valid, core_input_ready, core_input_last;
  wire checker_ready, transport_ready, certified_beat, certified_complete;
  wire input_complete, input_fault_now, input_fault;
  wire [2:0] input_fault_reasons;
  // The adversarial shim withholds a single demanded beat AND storage retirement.
  assign bank_ready = transport_ready && !inject_gap;
  starlink_pss_realtime_input_guard input_guard (
    .clk(fft_clk), .resetn(resetn), .job_start(input_job_start),
    .job_descriptor(descriptor), .input_enable(input_enable),
    .input_valid(bank_valid && !inject_gap), .input_ready(checker_ready),
    .input_transport_ready(transport_ready), .input_data(bank_data),
    .input_position(bank_position), .input_last(bank_last), .input_metadata(bank_metadata),
    .core_input_tdata(core_input_data), .core_input_tvalid(core_input_valid),
    .core_input_tready(core_input_ready), .core_input_tlast(core_input_last),
    .certified_input_beat(certified_beat), .certified_input_complete(certified_complete),
    .input_complete(input_complete), .fault_now(input_fault_now),
    .protocol_fault(input_fault), .fault_reasons(input_fault_reasons)
  );

  reg [7:0] config_data = 0;
  reg config_valid = 0, configured = 0;
  wire config_ready;
  wire [47:0] core_output_data;
  wire [23:0] core_output_user;
  wire core_output_valid, core_output_last;
  wire [7:0] core_status_data;
  wire core_status_valid, event_frame, event_last_unexpected, event_last_missing, event_input_halt;
  starlink_pss_fft512_bfp18_rt_guarded_probe core (
    .aclk(fft_clk), .aresetn(core_resetn),
    .s_axis_config_tdata(config_data), .s_axis_config_tvalid(config_valid),
    .s_axis_config_tready(config_ready), .s_axis_data_tdata(core_input_data),
    .s_axis_data_tvalid(core_input_valid), .s_axis_data_tready(core_input_ready),
    .s_axis_data_tlast(core_input_last), .m_axis_data_tdata(core_output_data),
    .m_axis_data_tuser(core_output_user), .m_axis_data_tvalid(core_output_valid),
    .m_axis_data_tlast(core_output_last), .m_axis_status_tdata(core_status_data),
    .m_axis_status_tvalid(core_status_valid), .event_frame_started(event_frame),
    .event_tlast_unexpected(event_last_unexpected), .event_tlast_missing(event_last_missing),
    .event_data_in_channel_halt(event_input_halt)
  );

  reg assumed_final_fence = 0;
  wire return_valid, return_ready, return_last, return_fault;
  wire [35:0] return_data;
  wire [8:0] return_position;
  wire [74:0] return_metadata;
  wire result_busy, result_commit, result_fault;
  wire [7:0] result_fault_reasons;
  // This conservative EXPERIMENTAL event policy remains live through the entire
  // admitted job/drain. Passing these jobs does not certify its universal timing.
  wire external_fault = input_fault_now || input_fault || source_fault ||
    event_last_unexpected || event_last_missing || event_input_halt;
  starlink_pss_realtime_result_guard result_guard (
    .clk(fft_clk), .resetn(resetn), .job_valid(job_valid), .job_ready(job_ready),
    .job_descriptor(descriptor), .input_bank_reserved(input_reserved),
    .output_bank_reserved(output_reserved), .certified_input_beat(certified_beat),
    .certified_input_complete(certified_complete), .final_fence_certified(assumed_final_fence),
    .external_fault_now(external_fault), .core_event_frame_started(event_frame),
    .core_output_tdata(core_output_data), .core_output_tuser(core_output_user),
    .core_output_tvalid(core_output_valid), .core_output_tlast(core_output_last),
    .core_status_tdata(core_status_data), .core_status_tvalid(core_status_valid),
    .mailbox_input_valid(return_valid), .mailbox_input_ready(return_ready),
    .mailbox_input_fault(return_fault), .mailbox_input_data(return_data),
    .mailbox_input_position(return_position), .mailbox_input_last(return_last),
    .mailbox_input_metadata(return_metadata), .busy(result_busy), .commit_pulse(result_commit),
    .protocol_fault(result_fault), .fault_reasons(result_fault_reasons)
  );
  wire sink_valid, sink_last;
  wire [35:0] sink_data;
  wire [8:0] sink_position;
  wire [74:0] sink_metadata;
  reg sink_enable = 0;
  integer slow_cycles = 0;
  wire sink_ready = sink_enable && slow_cycles % 11 < 7;
  starlink_pss_block_mailbox #(.METADATA_WIDTH(75)) output_mailbox (
    .input_clk(fft_clk), .input_resetn(fast_resetn), .input_valid(return_valid),
    .input_ready(return_ready), .input_data(return_data), .input_position(return_position),
    .input_last(return_last), .input_metadata(return_metadata), .input_fault(return_fault),
    .output_clk(slow_clk), .output_resetn(slow_resetn), .output_valid(sink_valid),
    .output_ready(sink_ready), .output_data(sink_data), .output_position(sink_position),
    .output_last(sink_last), .output_metadata(sink_metadata)
  );

  reg [31:0] samples [0:1405];
  reg [35:0] forward_values [0:1535], products [0:1535], inverse_values [0:1535];
  reg [4:0] forward_exponents [0:2], inverse_exponents [0:2];
  integer fixture = 0, job = -1, cycle = 0;
  reg inverse = 0, starved = 0;
  integer deliveries = 0, input_admissions = 0, result_admissions = 0, completions = 0;
  integer raw_outputs = 0, statuses = 0, frames = 0, published = 0, commits = 0, private_writes = 0;
  integer first_gap = -1, first_local_fault = -1, first_vendor_halt = -1;
  integer first_data = -1, first_status = -1, raw_mismatches = 0;
  integer healthy_jobs = 0, healthy_words = 0, rejected_jobs = 0, recovery_jobs = 0;
  integer gap_index = -1, trace_file, f, direction, gap_case, next_job = 0;
  reg [35:0] expected_word;
  reg [4:0] expected_exponent;
  reg stalled_sink = 0;
  reg [120:0] stalled_sink_value;

  always @(posedge fft_clk) begin
    cycle = cycle + 1;
    if (cycle > 350000) $fatal(1, "joint actual-core harness watchdog");
    $fdisplay(trace_file, "%0d,%0d,%0b,%0b,%0b,%0b,%0b,%0b,%0d,%0b,%0b,%0b,%0b,%0b,%0b,%0d,%0b,%0b,%0b,%h,%h",
      cycle, job, resetn, core_resetn, job_valid && job_ready, input_job_start,
      core_input_valid, core_input_ready, deliveries, certified_beat, certified_complete,
      input_fault_now, input_fault, result_fault, event_input_halt, raw_outputs,
      core_output_valid, core_status_valid, assumed_final_fence, core_output_user, core_output_data);
    if (resetn) begin
      if (job_valid && job_ready) result_admissions = result_admissions + 1;
      if (input_job_start) begin
        if (result_admissions != 1) $fatal(1, "input admission before result reservation");
        input_admissions = input_admissions + 1;
      end
      if (core_input_valid && core_input_ready) begin
        if (!configured || input_admissions != 1 || result_admissions != 1 || !certified_beat)
          $fatal(1, "uncertified core delivery or delivery before both admissions/config");
      end
      if (certified_beat) deliveries = deliveries + 1;
      if (certified_complete) completions = completions + 1;
      if (inject_gap && core_input_ready && first_gap < 0) first_gap = cycle;
      if (input_fault_now && first_local_fault < 0) first_local_fault = cycle;
      if (event_input_halt && first_vendor_halt < 0) first_vendor_halt = cycle;
      if (event_frame) frames = frames + 1;
      if (core_status_valid) begin
        statuses = statuses + 1;
        if (first_status < 0) first_status = cycle;
        if (!starved && core_status_data !== {3'b0, expected_exponent})
          $fatal(1, "independent status exponent mismatch");
      end
      if (core_output_valid) begin
        if (first_data < 0) first_data = cycle;
        if (raw_outputs >= 512) $fatal(1, "unaccounted extra actual-core output");
        expected_word = inverse ? inverse_values[fixture*512+raw_outputs] :
                                  forward_values[fixture*512+raw_outputs];
        if ({core_output_data[41:24], core_output_data[17:0]} !== expected_word)
          raw_mismatches = raw_mismatches + 1;
        if (!starved && (core_output_user !== {3'b0, expected_exponent, 7'b0, 9'(raw_outputs)} ||
            core_output_last !== (raw_outputs == 511)))
          $fatal(1, "actual-core output index/padding/exponent/TLAST mismatch");
        raw_outputs = raw_outputs + 1;
      end
      if (return_valid && return_ready) begin
        private_writes = private_writes + 1;
        if (return_last) begin
          if (starved || !assumed_final_fence || deliveries != 512 || completions != 1 ||
              statuses != 1 || frames != 1 || external_fault || result_fault)
            $fatal(1, "unqualified final actual-core result published");
          commits = commits + 1;
        end
      end
      if (!starved && (input_fault || result_fault || source_fault || return_fault))
        $fatal(1, "healthy actual-core joint job fault job=%0d input=%h result=%h",
               job, input_fault_reasons, result_fault_reasons);
    end
  end
  always @(posedge slow_clk) begin
    slow_cycles = slow_cycles + 1;
    if (!common_resetn) stalled_sink = 0;
    else begin
      if (stalled_sink && sink_valid &&
          {sink_data, sink_position, sink_last, sink_metadata} !== stalled_sink_value)
        $fatal(1, "slow mailbox changed a stalled result");
      stalled_sink = sink_valid && !sink_ready;
      stalled_sink_value = {sink_data, sink_position, sink_last, sink_metadata};
      if (sink_valid) begin
        if (starved || !commits) $fatal(1, "unpublished/quarantined result escaped");
        if (sink_ready) begin
          if (published >= 512) $fatal(1, "extra slow result");
          expected_word = inverse ? inverse_values[fixture*512+published] :
                                    forward_values[fixture*512+published];
          if (sink_data !== expected_word || sink_position !== 9'(published) ||
              sink_last !== (published == 511) ||
              sink_metadata !== {descriptor, expected_exponent})
            $fatal(1, "frozen numeric result/descriptor mismatch job=%0d word=%0d", job, published);
          published = published + 1;
        end
      end
    end
  end

  task automatic tick;
    @(posedge fft_clk); #0.1;
  endtask
  task automatic run_job(input integer next_fixture, input bit next_inverse,
                         input integer inject_at, input integer control_delay,
                         input integer fence_delay, input integer reader_delay);
    integer p, waited;
    reg [35:0] word_in;
    begin
      @(negedge fft_clk);
      fast_resetn = 0; slow_resetn = 0; core_resetn = 0;
      job_valid = 0; input_enable = 0; input_reserved = 0; output_reserved = 0;
      source_valid = 0; config_valid = 0; configured = 0;
      assumed_final_fence = 0; sink_enable = 0; inject_gap = 0;
      fixture = next_fixture; inverse = next_inverse; gap_index = inject_at;
      starved = inject_at >= 0; job = next_job; next_job = next_job + 1;
      descriptor = {next_inverse, 64'(64'h100000000 + fixture*447),
                    next_inverse ? forward_exponents[fixture] : 5'b0};
      expected_exponent = inverse ? inverse_exponents[fixture] : forward_exponents[fixture];
      deliveries = 0; input_admissions = 0; result_admissions = 0; completions = 0;
      raw_outputs = 0; statuses = 0; frames = 0; published = 0; commits = 0; private_writes = 0;
      first_gap = -1; first_local_fault = -1; first_vendor_halt = -1;
      first_data = -1; first_status = -1; raw_mismatches = 0;
      repeat (10) tick();
      @(negedge fft_clk); fast_resetn = 1; slow_resetn = 1; core_resetn = 1;
      repeat (12) tick();
      if (bank_valid || sink_valid || result_busy) $fatal(1, "reset epoch leaked stale transaction");
      // Arbitrarily paced slow filling occurs BEFORE any core/job admission.
      for (p = 0; p < 512; p = p + 1) begin
        @(negedge slow_clk);
        word_in = inverse ? products[fixture*512+p] :
          {samples[fixture*447+p][31:16], 2'b00, samples[fixture*447+p][15:0], 2'b00};
        source_data = word_in; source_position = p; source_last = p == 511; source_valid = 1;
        @(posedge slow_clk);
        while (!source_ready) @(posedge slow_clk);
        @(negedge slow_clk); source_valid = 0;
        if (p % 67 == 0) repeat (3) @(negedge slow_clk);
      end
      waited = 0;
      while (!bank_valid && waited < 100) begin tick(); waited = waited + 1; end
      if (!bank_valid || bank_position != 0 || bank_metadata != descriptor || !return_ready)
        $fatal(1, "complete input bank/prefetch or output reservation unavailable");
      @(negedge fft_clk); input_reserved = 1; output_reserved = 1; job_valid = 1;
      tick();
      if (result_admissions != 1) $fatal(1, "reserved result job not admitted");
      @(negedge fft_clk); job_valid = 0;
      repeat (3) tick();
      if (input_admissions != 1 || deliveries) $fatal(1, "registered admission token mismatch");
      repeat (control_delay) tick();
      @(negedge fft_clk); config_data = inverse ? 0 : 1; config_valid = 1;
      @(posedge fft_clk);
      while (!config_ready) @(posedge fft_clk);
      @(negedge fft_clk); config_valid = 0; configured = 1;
      repeat (17 + control_delay) tick();
      @(negedge fft_clk); input_enable = 1;
      if (starved) begin
        waited = 0;
        while (deliveries < gap_index && waited < 1500) begin
          tick(); waited = waited + 1;
        end
        if (deliveries != gap_index) $fatal(1, "starvation target was not reached");
        @(negedge fft_clk); inject_gap = 1;
        #0.1;
        // Core waitstates are legal, including initialization after word zero.
        // Keep the target word private while waiting for the next ACTUAL demand.
        waited = 0;
        while (!core_input_ready && waited < 100) begin
          @(negedge fft_clk); #0.1; waited = waited + 1;
        end
        if (!core_input_ready || !input_fault_now || certified_beat || core_input_valid)
          $fatal(1, "active demanded gap not detected immediately");
        tick();
        if (!input_fault || !result_fault || commits)
          $fatal(1, "same-edge input failure did not quarantine the result");
        @(negedge fft_clk); inject_gap = 0;
      end
      waited = 0;
      while (raw_outputs < 512 && waited < 6500) begin tick(); waited = waited + 1; end
      if (raw_outputs != 512) $fatal(1, "actual core failed bounded output drain");
      if (starved) begin
        repeat (96) tick();
        if (first_gap != first_local_fault || first_vendor_halt <= first_local_fault ||
            first_local_fault < 0 || !raw_mismatches || commits || published || private_writes ||
            input_admissions != 1 || result_admissions != 1)
          $fatal(1, "starvation was not detected before vendor event / quarantined");
        rejected_jobs = rejected_jobs + 1;
      end else begin
        if (deliveries != 512 || completions != 1 || frames != 1 || statuses != 1 ||
            raw_mismatches || first_local_fault >= 0 || first_vendor_halt >= 0)
          $fatal(1, "healthy actual-core job evidence mismatch");
        // Hold final 511 privately even though matching status already exists.
        if (commits || private_writes != 511 || !result_guard.return_valid ||
            !result_guard.return_last || sink_valid)
          $fatal(1, "last actual-core word did not remain private");
        repeat (fence_delay) tick();
        if (commits || private_writes != 511) $fatal(1, "final-fence premise bypassed");
        @(negedge fft_clk); assumed_final_fence = 1;
        waited = 0;
        while (!commits && waited < 100) begin tick(); waited = waited + 1; end
        if (commits != 1 || private_writes != 512) $fatal(1, "qualified mailbox did not commit");
        repeat (reader_delay + 12) tick();
        if (!result_busy || published) $fatal(1, "held slow bank acknowledged prematurely");
        @(negedge fft_clk); sink_enable = 1;
        waited = 0;
        while ((published != 512 || result_busy) && waited < 5000) begin
          tick(); waited = waited + 1;
        end
        if (published != 512 || result_busy || !source_ready)
          $fatal(1, "slow output drain/input ownership return failed");
        healthy_jobs = healthy_jobs + 1; healthy_words = healthy_words + published;
      end
      $display("RT_GUARDED_JOB job=%0d fixture=%0d inverse=%0d gap_index=%0d admissions=%0d/%0d deliveries=%0d completion=%0d raw_outputs=%0d statuses=%0d frames=%0d raw_mismatches=%0d private_writes=%0d commits=%0d published=%0d local_fault=%0d vendor_halt=%0d status_minus_first_data=%0d fence_delay=%0d reader_delay=%0d",
        job, fixture, inverse, gap_index, result_admissions, input_admissions, deliveries,
        completions, raw_outputs, statuses, frames, raw_mismatches, private_writes,
        commits, published, first_local_fault, first_vendor_halt, first_status-first_data,
        fence_delay, reader_delay);
    end
  endtask
  initial begin
    trace_file = $fopen("realtime_guarded_mailbox_trace.csv", "w");
    if (!trace_file) $fatal(1, "cannot create guarded mailbox trace");
    $fdisplay(trace_file, "cycle,job,resetn,core_resetn,result_admission,input_admission,core_input_valid,core_input_ready,deliveries,certified_beat,certified_complete,input_fault_now,input_fault,result_fault,vendor_input_halt,raw_outputs,core_output_valid,core_status_valid,assumed_final_fence,core_output_user,core_output_data");
    $readmemh("samples_ci16.mem", samples);
    $readmemh("forward_q17.mem", forward_values);
    $readmemh("product_q17.mem", products);
    $readmemh("inverse_q17.mem", inverse_values);
    $readmemh("forward_exponents.mem", forward_exponents);
    $readmemh("inverse_exponents.mem", inverse_exponents);
    for (f = 0; f < 3; f = f + 1)
      for (direction = 0; direction < 2; direction = direction + 1)
        run_job(f, direction != 0, -1, 47*f, 17+113*f, 131*f);
    for (direction = 0; direction < 2; direction = direction + 1)
      for (gap_case = 0; gap_case < 3; gap_case = gap_case + 1) begin
        run_job(gap_case, direction != 0, gap_case == 0 ? 1 : gap_case == 1 ? 255 : 511,
                13, 0, 0);
        run_job((gap_case+1)%3, direction == 0, -1, 211, 257, 1024);
        recovery_jobs = recovery_jobs + 1;
      end
    if (healthy_jobs != 12 || healthy_words != 6144 || rejected_jobs != 6 || recovery_jobs != 6)
      $fatal(1, "joint probe coverage mismatch");
    $display("REALTIME_GUARDED_MAILBOX_PROBE_PASS healthy_jobs=%0d exact_published_words=%0d starved_jobs=%0d explicit_reset_recoveries=%0d real_mailboxes=2 registered_admission=1 PRODUCTION_SERVICE_UNQUALIFIED EVENT_FENCE_PREMISE_UNQUALIFIED CAPACITY_UNQUALIFIED",
      healthy_jobs, healthy_words, rejected_jobs, recovery_jobs);
    $fclose(trace_file);
    $finish;
  end
endmodule
