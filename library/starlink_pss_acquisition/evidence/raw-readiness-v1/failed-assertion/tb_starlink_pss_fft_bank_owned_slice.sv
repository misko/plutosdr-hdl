`timescale 1ns/1fs
module tb_starlink_pss_fft_bank_owned_slice;
  parameter integer FAST_MHZ = 200;
  parameter integer QUICK_MUTATION = 0;
  reg clk = 0, fft_clk = 0;
  initial begin #1.3; forever #5 clk = !clk; end
  always #(500.0/FAST_MHZ) fft_clk = !fft_clk;
  reg resetn = 0, fft_resetn = 0;
  reg input_valid = 0, input_last = 0;
  reg [35:0] input_data = 0;
  reg [8:0] input_position = 0;
  reg [63:0] input_block_start = 0;
  wire input_ready, output_valid, output_last, fault;
  wire [35:0] output_data;
  wire [8:0] output_position;
  wire [74:0] output_metadata;
  integer fast_cycle = 0, slow_cycle = 0, epoch = 0, profile = 0;
  always @(negedge clk) slow_cycle = slow_cycle + 1;
  always @(negedge fft_clk) fast_cycle = fast_cycle + 1;
  reg reader_enable = 1, expected_fault = 0, expected_results = 1, injecting_readiness = 0;
  reg allow_inverse_commit_before_late_fault = 0;
  reg allow_provisional_prefix_after_fault = 0;
  wire output_ready = reader_enable && (profile == 0 || slow_cycle % 17 < 13);
  starlink_pss_fft_bank_owned_slice dut (.*);
  // Default-mode shadow retains the original full nonfinal predicate and full
  // final fence. Compare before and after every edge, including injected faults.
  wire shadow_ready, shadow_valid, shadow_private, shadow_commit_valid;
  wire shadow_busy, shadow_commit, shadow_fault, shadow_last;
  wire [7:0] shadow_reasons;
  wire [35:0] shadow_data;
  wire [8:0] shadow_position;
  wire [74:0] shadow_metadata;
  integer completed_return_checks = 0, full_shadow_checks = 0;
  wire original_destination_ready = dut.next_inverse ? dut.output_bank_ready :
    (dut.forward_committed ? dut.forward_handoff_ack : (dut.kernel_ready && dut.product_bank_ready));
  integer raw_ready_handoff_fault_cases = 0, raw_ready_differences = 0, late_ack_witnesses = 0;
  starlink_pss_realtime_result_guard shadow (
    .clk(fft_clk), .resetn(dut.fast_running), .job_valid(dut.job_valid), .job_ready(shadow_ready),
    .job_descriptor(dut.selected_metadata),
    .input_bank_reserved(dut.state == dut.WAIT_BANK ? dut.selected_valid : dut.engine_input_reserved),
    .output_bank_reserved(dut.state == dut.WAIT_BANK ? dut.destination_reserved : dut.engine_output_reserved),
    .certified_input_beat(dut.certified_input_beat), .certified_input_complete(dut.certified_input_complete),
    .final_fence_certified(dut.checked_input_complete && !dut.input_guard_fault && !dut.input_fault_now),
    .external_fault_now(dut.external_fault_now), .phase_input_fault_now(1'bz),
    .completed_input_certified(1'bz), .completed_input_fault_now(1'bz),
    .core_event_frame_started(dut.event_frame), .core_output_tdata(dut.core_output_data),
    .core_output_tuser(dut.core_output_user), .core_output_tvalid(dut.core_output_valid),
    .core_output_tlast(dut.core_output_last), .core_status_tdata(dut.core_status_data),
    .core_status_tvalid(dut.core_status_valid), .mailbox_input_valid(shadow_valid),
    .mailbox_private_valid(shadow_private), .mailbox_commit_valid(shadow_commit_valid),
    .mailbox_input_ready(original_destination_ready),
    .mailbox_input_fault(dut.output_bank_fault || dut.output_bank_framing_fault_now),
    .mailbox_input_data(shadow_data), .mailbox_input_position(shadow_position),
    .mailbox_input_last(shadow_last), .mailbox_input_metadata(shadow_metadata),
    .busy(shadow_busy), .commit_pulse(shadow_commit), .protocol_fault(shadow_fault),
    .fault_reasons(shadow_reasons)
  );
  always @(posedge fft_clk or negedge fft_clk) begin
    #0.001;
    if (dut.fast_running) begin
      full_shadow_checks = full_shadow_checks + 1;
      if (dut.result_guard.awaiting_ack !== shadow.awaiting_ack)
        $fatal(1, "raw ownership readiness changed guard ACK-clear edge");
      if (dut.result_destination_ready !== original_destination_ready) begin
        raw_ready_differences = raw_ready_differences + 1;
        if (!dut.forward_committed || dut.result_guard.active || dut.result_guard.return_valid ||
            !dut.result_guard.idle_fault_now || !shadow.idle_fault_now)
          $fatal(1, "raw/certified readiness differed outside fault-vetoed inactive handoff");
      end
      if (dut.state == dut.ACK_DRAIN && !dut.result_busy && !dut.any_fast_fault &&
          dut.result_destination_ready !== (dut.next_inverse ? dut.output_bank_ready : dut.forward_handoff_ack))
        $fatal(1, "raw readiness changed healthy controller drain edge");
      if ({dut.job_ready, dut.return_valid, dut.return_private_valid, dut.return_commit_valid,
           dut.result_busy, dut.result_commit, dut.result_fault, dut.result_guard.fault_reasons} !==
          {shadow_ready, shadow_valid, shadow_private, shadow_commit_valid,
           shadow_busy, shadow_commit, shadow_fault, shadow_reasons})
        $fatal(1, "completed-input full shadow control/reasons mismatch");
      if (dut.return_private_valid &&
          {dut.return_data, dut.return_position, dut.return_last, dut.return_metadata} !==
          {shadow_data, shadow_position, shadow_last, shadow_metadata})
        $fatal(1, "completed-input full shadow private payload mismatch");
      if (dut.final_fence !== (dut.checked_input_complete && !dut.input_guard_fault && !dut.input_fault_now))
        $fatal(1, "completed-input fence differs from original same-edge fence");
      if (dut.result_guard.return_valid) begin
        completed_return_checks = completed_return_checks + 1;
        if (!dut.checked_input_complete || dut.input_guard.slot_open ||
            dut.result_guard.input_count != 512 || !dut.result_guard.input_complete_seen ||
            !dut.result_guard.frame_seen || !dut.result_guard.exponent_seen ||
            dut.certified_input_beat || dut.certified_input_complete || dut.handoff_fault_now ||
            dut.completed_input_fault_now !== dut.external_fault_now ||
            dut.result_guard.completed_return_fault_now !== dut.result_guard.fault_now ||
            dut.result_guard.completed_final_fault_now !== dut.result_guard.final_fault_now)
          $fatal(1, "completed-return phase invariant/predicate mismatch");
      end
    end
  end
  reg [31:0] samples [0:1405];
  reg [35:0] forwards [0:1535], products [0:1535], inverses [0:1535];
  reg [4:0] forward_exponents [0:2], inverse_exponents [0:2];
  reg [63:0] epoch_base = 64'h200000000;
  integer output_words = 0, published = 0, loaded = 0, consumed = 0;
  integer forward_jobs = 0, inverse_jobs = 0, delivered = 0, raw_words = 0;
  integer total_inverse = 0, total_forward = 0, total_products = 0, total_blocks = 0;
  integer fault_cases = 0, purge_cases = 0, overlapping_loads = 0, equality_witnesses = 0;
  integer completed_input_prefetch_witnesses = 0;
  integer held_final_ready_witnesses = 0;
  integer provisional_prefix_words = 0;
  integer active_fixture = 0, output_fixture = 0, trace, job_index, previous_admit = -1;
  integer max_forward_interval = 0, admission_cycle = 0, config_cycle = 0, first_core_output = 0;
  integer first_core_input = 0, last_core_input = 0, statuses = 0, frames = 0;
  integer held_core_reset_cycles = 0;
  reg previous_core_resetn = 0;
  reg [7:0] injected_status = 0;
  integer n, test_kind, i, wait_count;
  real epoch_first_admit_ns = 0;

  always @(posedge fft_clk) begin
    if (fast_cycle > 1500000) $fatal(1, "bank-owned bench watchdog");
    $fdisplay(trace, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
      fast_cycle, epoch, profile, dut.fast_running, dut.state, dut.core_aresetn,
      dut.job_accept, dut.config_valid && dut.config_ready, dut.next_inverse,
      dut.certified_input_beat, dut.core_output_valid, dut.core_status_valid,
      dut.return_commit_valid && dut.result_destination_ready,
      dut.forward_committed, dut.product_valid && dut.product_bank_ready && dut.product_last && dut.product_commit_authorized,
      dut.forward_handoff_ack, dut.result_busy, dut.source_valid, dut.source_ready,
      dut.product_bank_valid, dut.product_bank_read_ready, dut.output_bank_ready,
      dut.fast_fault, dut.engine_metadata[68:5]);
    if (!dut.fast_running) begin
      forward_jobs = 0; inverse_jobs = 0; delivered = 0; raw_words = 0; consumed = 0;
      previous_admit = -1; held_core_reset_cycles = 0; previous_core_resetn = 0;
    end else begin
      if (!dut.core_aresetn) held_core_reset_cycles = held_core_reset_cycles + 1;
      if (dut.core_aresetn && !previous_core_resetn) begin
        if (held_core_reset_cycles < 2) $fatal(1, "short core reset");
        held_core_reset_cycles = 0;
      end
      previous_core_resetn = dut.core_aresetn;
      if (!expected_fault && dut.fast_fault) $fatal(1, "unexpected fast fault epoch=%0d state=%0d", epoch, dut.state);
      if ((dut.joiner.input_valid && dut.kernel_ready) !==
          (dut.return_valid && !dut.next_inverse && !dut.fast_fault && dut.result_destination_ready))
        $fatal(1, "join acceptance differs from guard retirement");
      if (!expected_fault && dut.state == dut.RUN_JOB && !dut.next_inverse &&
          dut.checked_input_complete && dut.source_valid &&
          dut.source_metadata[68:5] != dut.engine_metadata[68:5]) begin
        completed_input_prefetch_witnesses = completed_input_prefetch_witnesses + 1;
        if (!dut.engine_input_enable || dut.core_input_valid || dut.certified_input_beat || dut.source_read_ready)
          $fatal(1, "prefetched N+1 was delivered into completed N input epoch");
      end
      if (injecting_readiness && !dut.product_bank_ready && dut.kernel_ready) begin
        equality_witnesses = equality_witnesses + 1;
        if (dut.joiner.input_valid) $fatal(1, "unretired return reached joiner");
      end
      if (!expected_fault && dut.result_guard.return_last && dut.result_guard.final_qualified &&
          !dut.next_inverse && !dut.product_bank_ready && dut.kernel_ready) begin
        held_final_ready_witnesses = held_final_ready_witnesses + 1;
        if (!dut.return_valid || dut.result_destination_ready || dut.joiner.input_valid || dut.forward_committed)
          $fatal(1, "held final escaped its actual guard retirement");
      end
      if (dut.job_accept) begin
        job_index = (dut.selected_metadata[68:5] - epoch_base) / 447;
        active_fixture = job_index % 3;
        admission_cycle = fast_cycle;
        delivered = 0; raw_words = 0; statuses = 0; frames = 0;
        if (dut.next_inverse) begin
          inverse_jobs = inverse_jobs + 1;
          if (!dut.product_bank_valid || dut.product_bank_position != 0 ||
              dut.product_bank_metadata !== {1'b1, 64'(epoch_base+job_index*447), forward_exponents[active_fixture]})
            $fatal(1, "inverse admitted without validated owned product descriptor");
        end else begin
          if (profile == 0 && previous_admit >= 0 && fast_cycle-previous_admit > max_forward_interval)
            max_forward_interval = fast_cycle - previous_admit;
          $display("BANK_FORWARD_ADMIT epoch=%0d profile=%0d index=%0d fast_cycle=%0d time_ns=%0.6f interval_cycles=%0d",
            epoch, profile, job_index, fast_cycle, $realtime, previous_admit < 0 ? 0 : fast_cycle-previous_admit);
          previous_admit = fast_cycle;
          forward_jobs = forward_jobs + 1;
        end
      end
      if (dut.config_valid && dut.config_ready) config_cycle = fast_cycle;
      if (dut.certified_input_beat) begin
        if (delivered == 0) first_core_input = fast_cycle;
        last_core_input = fast_cycle;
        if (!expected_fault && dut.selected_data !== (dut.next_inverse ? products[active_fixture*512+delivered] :
            {samples[active_fixture*447+delivered][31:16], 2'b00, samples[active_fixture*447+delivered][15:0], 2'b00}))
          $fatal(1, "source/product bank input changed or reordered");
        delivered = delivered + 1;
      end
      if (dut.certified_input_complete && !dut.next_inverse) consumed = consumed + 1;
      if (dut.core_status_valid) statuses = statuses + 1;
      if (dut.event_frame) frames = frames + 1;
      if (dut.core_output_valid) begin
        if (raw_words == 0) first_core_output = fast_cycle;
        raw_words = raw_words + 1;
      end
      if (dut.return_valid && dut.result_destination_ready && !dut.next_inverse && !expected_fault) begin
        if (dut.return_data !== forwards[active_fixture*512+dut.return_position] ||
            dut.return_metadata[4:0] !== forward_exponents[active_fixture]) $fatal(1, "forward mismatch");
        total_forward = total_forward + 1;
      end
      if (dut.product_valid && dut.product_bank_ready && !expected_fault) begin
        if ({dut.product_q, dut.product_i} !== products[active_fixture*512+dut.product_position] ||
            dut.product_exponent !== forward_exponents[active_fixture]) $fatal(1, "product mismatch");
        total_products = total_products + 1;
      end
      if (dut.return_commit_valid && dut.result_destination_ready) begin
        if (delivered != 512 || raw_words != 512 || statuses != 1 || frames != 1 || !dut.final_fence)
          $fatal(1, "unqualified guard commit");
        if (expected_fault && dut.next_inverse && !allow_inverse_commit_before_late_fault)
          $fatal(1, "inverse commit escaped its planned current fault veto");
        $display("BANK_JOB epoch=%0d inverse=%0d admit=%0d config_delta=%0d input_span=%0d input_last_to_output_first=%0d commit_delta=%0d",
          epoch, dut.next_inverse, admission_cycle, config_cycle-admission_cycle,
          last_core_input-first_core_input+1, first_core_output-last_core_input, fast_cycle-admission_cycle);
      end
    end
  end
  always @(posedge clk) begin
    if (!dut.slow_running) begin loaded = 0; published = 0; output_words = 0; end
    else begin
      if (input_valid && input_ready) begin
        if (loaded > consumed) $fatal(1, "N+1 overwrote source bank while N still needed it");
        if (input_position == 0 && loaded > 0 && dut.core_aresetn) overlapping_loads = overlapping_loads + 1;
        if (input_position == 0)
          $display("BANK_CAPTURE_START epoch=%0d profile=%0d block=%0d time_ns=%0.6f", epoch, profile, loaded, $realtime);
        if (input_last) begin
          $display("BANK_CAPTURE_COMMIT epoch=%0d profile=%0d block=%0d time_ns=%0.6f", epoch, profile, loaded, $realtime);
          loaded = loaded + 1;
        end
      end
      if (output_valid && output_ready) begin
        output_fixture = ((output_metadata[73:10]-epoch_base) / 447) % 3;
        if (!expected_results || (expected_fault && !allow_provisional_prefix_after_fault) ||
            output_position != output_words || output_last != (output_words == 511) ||
            output_metadata !== {1'b1, 64'(epoch_base+published*447), forward_exponents[output_fixture], inverse_exponents[output_fixture]} ||
            output_data !== inverses[output_fixture*512+output_words]) $fatal(1, "inverse output mismatch/invalid publication");
        if (allow_provisional_prefix_after_fault && output_last)
          $fatal(1, "faulted provisional prefix became a complete block");
        total_inverse = total_inverse + 1;
        if (output_position == 0)
          $display("BANK_OUTPUT_START epoch=%0d profile=%0d block=%0d time_ns=%0.6f", epoch, profile, published, $realtime);
        if (output_last) begin
          output_words = 0; published = published + 1; total_blocks = total_blocks + 1;
          $display("BANK_OUTPUT epoch=%0d profile=%0d block=%0d time_ns=%0.6f", epoch, profile, published-1, $realtime);
        end else output_words = output_words + 1;
      end
    end
  end
  task automatic tick;
    @(posedge fft_clk); #0.001;
  endtask
  task automatic reset_epoch(input integer side);
    @(negedge clk); input_valid = 0;
    if (side != 2) resetn = 0;
    if (side != 1) fft_resetn = 0;
    repeat (20) tick();
    @(negedge clk); resetn = 1; fft_resetn = 1;
    epoch = epoch + 1; epoch_base = 64'h200000000 + 64'(epoch)*65536;
    repeat (20) tick();
    if (fault || output_valid || dut.result_busy || dut.product_bank_valid || dut.source_valid)
      $fatal(1, "reset leaked bank ownership/results");
    expected_fault = 0; expected_results = 1; reader_enable = 1;
    allow_inverse_commit_before_late_fault = 0;
    allow_provisional_prefix_after_fault = 0;
  endtask
  task automatic send_words(input integer index, input integer count);
    integer word_index, fixture;
    fixture = index % 3;
    for (word_index = 0; word_index < count; word_index = word_index + 1) begin
      @(negedge clk); input_valid = 1;
      input_block_start = epoch_base + index*447;
      input_position = word_index; input_last = word_index == 511;
      input_data = {samples[fixture*447+word_index][31:16], 2'b00, samples[fixture*447+word_index][15:0], 2'b00};
      @(posedge clk); while (!input_ready) @(posedge clk);
      if (profile == 1 && word_index % 13 == 0) begin
        @(negedge clk); input_valid = 0; repeat (3) @(posedge clk);
      end
    end
    @(negedge clk); input_valid = 0;
  endtask
  task automatic await_results(input integer count);
    integer timeout;
    timeout = 0;
    while ((published != count || dut.state != dut.WAIT_BANK || dut.next_inverse) && timeout < 25000) begin
      tick(); timeout = timeout + 1;
    end
    if (timeout == 25000 || fault) $fatal(1, "outputs/final real ACK failed to drain");
  endtask
  task automatic await_fault;
    repeat (24) tick();
    if (!fault || !dut.fast_fault || output_valid || dut.state != dut.QUARANTINE)
      $fatal(1, "fault was not sticky/fail closed");
    repeat (32) tick();
    if (output_valid || dut.job_accept) $fatal(1, "quarantine leaked result/job");
    fault_cases = fault_cases + 1;
  endtask
  initial begin
    trace = $fopen("fft_bank_owned_trace.csv", "w");
    $fdisplay(trace, "cycle,epoch,profile,running,state,core_resetn,admit,config,inverse,core_input,core_output,status,guard_commit,forward_committed,product_commit,handoff_ack,result_busy,source_valid,source_ready,product_read_valid,product_read_ready,output_bank_ready,fault,block_start");
    $readmemh("samples_ci16.mem", samples); $readmemh("forward_q17.mem", forwards);
    $readmemh("product_q17.mem", products); $readmemh("inverse_q17.mem", inverses);
    $readmemh("forward_exponents.mem", forward_exponents); $readmemh("inverse_exponents.mem", inverse_exponents);
    reset_epoch(0);
    for (n = 0; n < (QUICK_MUTATION ? 0 : 32); n = n + 1) send_words(n, 512);
    await_results(QUICK_MUTATION ? 0 : 32);
    profile = 1; reset_epoch(0);
    for (n = 0; n < (QUICK_MUTATION ? 0 : 6); n = n + 1) send_words(n, 512);
    await_results(QUICK_MUTATION ? 0 : 6); profile = 0;
    // Partial capture, active forward, active inverse, and inverse ACK resets.
    for (test_kind = 0; test_kind < (QUICK_MUTATION ? 0 : 4); test_kind = test_kind + 1) begin
      reset_epoch(0); expected_results = 0;
      if (test_kind == 0) send_words(0, 128);
      else begin
        reader_enable = 0; send_words(0, 512);
        if (test_kind == 3) wait(dut.next_inverse && dut.result_guard.awaiting_ack);
        else begin
          wait(dut.certified_input_beat && dut.next_inverse == (test_kind == 2));
          repeat (128) tick();
        end
      end
      reset_epoch(test_kind % 2 + 1); purge_cases = purge_cases + 1;
      send_words(0, 512); await_results(1);
    end
    // Forward status absent: even an apparent product candidate cannot admit
    // an inverse; deliver the one delayed valid status, then recover exactly.
    reset_epoch(0); send_words(0, 512);
    wait(dut.config_valid && dut.config_ready);
    force dut.core_status_valid = 0;
    wait(dut.result_guard.output_count == 512);
    repeat (8) tick();
    force dut.product_bank_valid = 1;
    repeat (8) tick();
    if (dut.forward_committed || inverse_jobs || dut.next_inverse || dut.job_accept)
      $fatal(1, "inverse candidate bypassed missing forward status");
    release dut.product_bank_valid;
    // All preceding products have drained. Hold the actually qualified final
    // return with the bank unavailable while the real empty joiner can accept.
    // Removing only the joiner's product_bank_ready gate MUST fail equality.
    @(negedge fft_clk); force dut.product_bank_ready = 0;
    injected_status = {3'b0, forward_exponents[0]};
    force dut.core_status_data = injected_status; force dut.core_status_valid = 1;
    tick(); @(negedge fft_clk); release dut.core_status_data; release dut.core_status_valid;
    repeat (3) tick();
    if (!held_final_ready_witnesses || fault) $fatal(1, "missing healthy held-final readiness witness");
    @(negedge fft_clk); release dut.product_bank_ready;
    await_results(1);
    if (QUICK_MUTATION) $fatal(1, "join-gate mutation unexpectedly survived witness");
    // Current and late forward faults: immediately after guard commit and at
    // the actual product handoff; do not reset away the forward epoch.
    for (test_kind = 0; test_kind < 2; test_kind = test_kind + 1) begin
      reset_epoch(0); expected_fault = 1; expected_results = 0; send_words(0, 512);
      if (test_kind == 0) wait(dut.forward_committed);
      else wait(dut.forward_handoff_ack);
      if (!dut.core_aresetn) $fatal(1, "forward epoch retired before ownership ACK");
      force dut.event_last_missing = 1;
      tick(); @(negedge fft_clk); release dut.event_last_missing;
      await_fault();
      if (inverse_jobs || !dut.core_aresetn) $fatal(1, "late forward fault was reset or admitted inverse");
    end
    // Product overflow flag, ordinal corruption, metadata mismatch.
    for (test_kind = 0; test_kind < 3; test_kind = test_kind + 1) begin
      reset_epoch(0); expected_fault = 1; expected_results = 0; send_words(0, 512);
      wait(dut.product_valid && dut.product_position == 64);
      if (test_kind == 0) force dut.product_overflow = 1;
      if (test_kind == 1) force dut.product_position = 9'd19;
      if (test_kind == 2) force dut.product_start = 64'hdeadbeef;
      tick(); @(negedge fft_clk);
      release dut.product_overflow; release dut.product_position; release dut.product_start;
      await_fault();
      if (dut.product_bank_valid || inverse_jobs) $fatal(1, "malformed product bank published");
    end
    // Missing active input and loss of reserved product-write readiness.
    reset_epoch(0); expected_fault = 1; expected_results = 0; send_words(0, 512);
    wait(dut.certified_input_beat); repeat (128) tick();
    @(negedge fft_clk); force dut.selected_valid = 0;
    repeat (2) tick(); release dut.selected_valid; await_fault();
    reset_epoch(0); expected_fault = 1; expected_results = 0; send_words(0, 512);
    wait(dut.core_output_valid); @(negedge fft_clk);
    injecting_readiness = 1; force dut.product_bank_ready = 0;
    repeat (2) tick(); release dut.product_bank_ready; injecting_readiness = 0;
    await_fault();
    if (!equality_witnesses) $fatal(1, "missing product-not-ready/kernel-ready witness");
    // Inverse final commit veto and postcommit actual slow ACK fault.
    for (test_kind = 0; test_kind < 2; test_kind = test_kind + 1) begin
      reset_epoch(0); expected_fault = 1; expected_results = 0; reader_enable = 0; send_words(0, 512);
      allow_inverse_commit_before_late_fault = test_kind == 1;
      if (test_kind == 0) wait(dut.next_inverse && dut.return_commit_valid);
      else wait(dut.next_inverse && dut.result_guard.awaiting_ack);
      allow_inverse_commit_before_late_fault = 0;
      force dut.event_last_missing = 1;
      #0.001;
      if (test_kind == 0 && dut.return_commit_valid) $fatal(1, "inverse final fault missed current veto");
      tick(); @(negedge fft_clk); release dut.event_last_missing;
      await_fault();
    end
    // Some already accepted words cannot be retracted across a clock domain.
    // Keep the exact prefix provisional, permit the real sticky-fault crossing
    // to close validity, and prohibit a completed result or the queued N+1.
    reset_epoch(0); send_words(0, 512); send_words(1, 512);
    wait(output_words == 128);
    @(negedge fft_clk);
    expected_fault = 1; allow_provisional_prefix_after_fault = 1;
    $display("BANK_PREFIX_FAULT_INJECT fast_cycle=%0d slow_cycle=%0d accepted_words=%0d time_ns=%0.6f",
      fast_cycle, slow_cycle, output_words, $realtime);
    force dut.event_last_missing = 1;
    tick(); @(negedge fft_clk); release dut.event_last_missing;
    await_fault();
    provisional_prefix_words = output_words;
    if (published || forward_jobs != 1 || inverse_jobs != 1 || loaded != 2 ||
        provisional_prefix_words < 128 || provisional_prefix_words > 132)
      $fatal(1, "late prefix fault lost evidence, escaped CDC bound, or admitted queued N+1");
    $display("BANK_PREFIX_FAULT_QUARANTINED accepted_words=%0d complete_blocks=%0d queued_source_blocks=%0d",
      provisional_prefix_words, published, loaded-consumed);
    reset_epoch(0); send_words(0, 512); await_results(1);
    if (!overlapping_loads || !completed_input_prefetch_witnesses)
      $fatal(1, "no capture/prefetch N+1 with closed N input epoch observed");
    if (!completed_return_checks || !full_shadow_checks)
      $fatal(1, "no completed-input equivalence witnesses");
    $display("COMPLETED_INPUT_ACTUAL_CORE_EQ_PASS return_checks=%0d full_shadow_checks=%0d",
      completed_return_checks, full_shadow_checks);
    $display("FFT_BANK_OWNED_SLICE_PASS fast_mhz=%0d healthy_blocks=%0d inverse_words=%0d forward_words=%0d product_words=%0d purge_cases=%0d fault_cases=%0d overlap_loads=%0d acceptance_equality_witnesses=%0d closed_input_prefetch_witnesses=%0d held_final_ready_witnesses=%0d provisional_prefix_words=%0d nominal_max_forward_interval_cycles=%0d",
      FAST_MHZ, total_blocks, total_inverse, total_forward, total_products, purge_cases,
      fault_cases, overlapping_loads, equality_witnesses, completed_input_prefetch_witnesses,
      held_final_ready_witnesses, provisional_prefix_words, max_forward_interval);
    // Additional raw-ready/certified-ACK tests follow the unchanged suite's
    // receipt. Any failure still fails the complete log gate; this separate
    // receipt does not redefine its original numerical/fault counters.
    for (test_kind = 0; test_kind < 8; test_kind = test_kind + 1) begin
      reset_epoch(0); expected_fault = 1; expected_results = 0; send_words(0, 512);
      wait(dut.forward_handoff_ack);
      if (test_kind == 7) begin
        wait(!dut.result_guard.awaiting_ack);
        if (dut.state != dut.ACK_DRAIN || !dut.core_aresetn)
          $fatal(1, "no late post-ACK/pre-controller-drain boundary");
        late_ack_witnesses = late_ack_witnesses + 1;
      end
      case (test_kind)
        0: force dut.product_bank_metadata = 70'h123456789;
        1: force dut.product_bank_position = 9'd7;
        2: force dut.product_bank_last = 1;
        3: force dut.event_frame = 1;
        4: force dut.core_status_valid = 1;
        5: force dut.core_output_valid = 1;
        6: force dut.input_job_start = 1;
        7: force dut.event_last_missing = 1;
      endcase
      #0.001;
      if (dut.forward_handoff_ack && test_kind != 3 && test_kind != 4 && test_kind != 5)
        $fatal(1, "certified handoff ACK missed current external/identity fault");
      tick(); @(negedge fft_clk);
      release dut.product_bank_metadata; release dut.product_bank_position; release dut.product_bank_last;
      release dut.event_frame; release dut.core_status_valid; release dut.core_output_valid;
      release dut.input_job_start; release dut.event_last_missing;
      await_fault(); raw_ready_handoff_fault_cases = raw_ready_handoff_fault_cases + 1;
      if (inverse_jobs || !dut.core_aresetn) $fatal(1, "raw ownership admitted inverse or reset away handoff fault");
    end
    // One-sided reset while valid product ownership is waiting for the forward
    // controller must purge the unpublished/owned state before healthy reuse.
    reset_epoch(0); expected_results = 0; send_words(0, 512); wait(dut.forward_handoff_ack);
    reset_epoch(1); send_words(0, 512); await_results(1);
    if (raw_ready_handoff_fault_cases != 8 || !raw_ready_differences || late_ack_witnesses != 1)
      $fatal(1, "missing raw-ready/certified-ACK negative witnesses");
    $display("RAW_READY_CERTIFIED_ACK_PASS handoff_fault_cases=%0d raw_ready_differences=%0d late_ack_witnesses=%0d handoff_reset_recovery=1 full_shadow_checks=%0d",
      raw_ready_handoff_fault_cases, raw_ready_differences, late_ack_witnesses, full_shadow_checks);
    $fclose(trace); $finish;
  end
endmodule
