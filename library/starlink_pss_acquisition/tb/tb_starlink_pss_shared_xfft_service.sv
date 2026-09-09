`timescale 1ns/1ps
// Both mailbox crossings plus the real generated XFFT, using independently
// frozen forward/product/inverse vectors. Not a full acquisition capacity gate.
module tb_starlink_pss_shared_xfft_service;
  parameter integer MAIN_JOBS = 6;
  parameter integer OUTPUT_STALL_MODE = 1;
  reg clk = 0, fft_clk = 0, resetn = 0, fft_resetn = 0;
  always #5 clk = !clk;
  initial begin #1.3; forever #2.5 fft_clk = !fft_clk; end
  reg input_valid = 0, output_ready = 0, expect_fault = 0;
  reg [35:0] input_data = 0;
  reg [8:0] input_position = 0;
  reg input_last = 0;
  reg [69:0] input_metadata = 0;
  wire input_ready, output_valid, output_last, service_fault;
  wire [35:0] output_data;
  wire [8:0] output_position;
  wire [74:0] output_metadata;
  reg [31:0] samples [0:1405];
  reg [35:0] forward_values [0:1535], products [0:1535], inverse_values [0:1535];
  reg [4:0] forward_exponents [0:2], inverse_exponents [0:2];
  integer cycle_count = 0, output_job = 0, output_word = 0, checked_words = 0;
  integer job, position, fixture, previous_pair_cycle = 0, maximum_pair_cycles = 0;
  integer final_fault_cases = 0, drain_reset_cases = 0, committed_jobs = 0;
  integer transport_fault_cases = 0, raw_only_overruns = 0;
  integer input_retirement_fault_cases = 0, unmatched_input_accepts = 0;
  integer speculative_counter_advances = 0;
  reg [8:0] validated_position_shadow = 0;
  integer idle_input_cycles = 0, idle_return_cycles = 0, config_cycles = 0;
  integer load_cycles = 0, compute_cycles = 0, output_cycles = 0, drain_cycles = 0;
  reg output_phase_seen = 0;
  reg stalled = 0;
  reg [120:0] stalled_word;
  reg staged_stalled = 0;
  reg [120:0] staged_word;
  reg old_closed_shadow = 0, previous_engine_active = 0;
  reg [69:0] previous_engine_metadata;
  wire old_validated_overrun = dut.fast_output_valid &&
      (old_closed_shadow || (dut.return_valid && !dut.return_accept));
  wire old_fault_event = dut.adapter_fault || dut.output_mailbox_fault ||
      (dut.return_valid && !dut.output_mailbox_ready) || old_validated_overrun;
  starlink_pss_shared_xfft_service dut (.*);

  function automatic [69:0] tag(input integer job_id);
    reg [63:0] start_index;
    begin
      start_index = 64'd1000000 + (job_id / 2) * 447;
      start_index[63:58] = job_id[5:0] ^ 6'h2d;
      tag = {job_id[0], start_index, forward_exponents[(job_id / 2) % 3]};
    end
  endfunction
  always @(posedge fft_clk) begin
    if (!dut.adapter.resetn) validated_position_shadow <= 0;
    else begin
      if (!dut.adapter_fault &&
          dut.adapter.expected_output_position !== validated_position_shadow)
        $fatal(1, "shared private position differs from healthy validated shadow");
      if (dut.adapter.output_position_advance && !dut.adapter.output_state_advance) begin
        if (!dut.adapter.fault_event_now)
          $fatal(1, "shared speculative position lacks same-cycle fault");
        speculative_counter_advances = speculative_counter_advances + 1;
      end
      if (dut.adapter.output_state_advance)
        validated_position_shadow <= validated_position_shadow + 1'b1;
    end
    if (dut.fast_running && !dut.fast_fault) begin
      if (dut.fast_input_valid && dut.fast_input_ready && !dut.adapter.input_accept)
        $fatal(1, "mailbox retired an input not accepted by adapter");
      if (dut.adapter.input_accept && !(dut.fast_input_valid && dut.fast_input_ready)) begin
        if (!dut.adapter.input_framing_error_now || dut.core_input_ready)
          $fatal(1, "unmatched adapter input is not a malformed stalled word");
        unmatched_input_accepts = unmatched_input_accepts + 1;
      end
      if (dut.fast_output_valid && !dut.raw_output_accept)
        $fatal(1, "checked output lacked a raw core handshake");
      if (old_validated_overrun && !dut.output_transport_overrun)
        $fatal(1, "transport refactor lost a validated-beat overrun");
      if (dut.output_transport_overrun && !old_validated_overrun &&
          !dut.adapter_fault && !dut.adapter.fault_event_now)
        $fatal(1, "raw-only overrun did not coincide with adapter fault");
      if (dut.output_transport_overrun && !dut.fast_output_valid && !dut.adapter_fault)
        raw_only_overruns = raw_only_overruns + 1;
      if (dut.engine_output_closed !== old_closed_shadow)
        $fatal(1, "derived output closed state differs on a healthy epoch");
      if (dut.engine_active && previous_engine_active &&
          dut.engine_metadata !== previous_engine_metadata)
        $fatal(1, "active descriptor changed before final return retirement");
    end
    previous_engine_active = dut.fast_running && dut.engine_active && !dut.fast_fault;
    previous_engine_metadata = dut.engine_metadata;
    // Reproduce the preceding revision's independent closed-state register.
    // Differences after sticky quarantine are unobservable and intentionally
    // excluded above; all healthy cycles, including final drain, must match.
    if (!dut.fast_running) old_closed_shadow = 0;
    else if (!old_fault_event) begin
      if (dut.fast_output_valid && !dut.fast_fault && dut.fast_output_last)
        old_closed_shadow = 1;
      if ((!dut.engine_active && !dut.fast_fault && !dut.return_valid &&
           dut.fast_input_valid && dut.output_mailbox_ready) ||
          (dut.engine_active && dut.return_accept && dut.return_last))
        old_closed_shadow = 0;
    end
    if (!dut.fast_running || !dut.engine_active) output_phase_seen = 0;
    if (dut.fast_running && output_job < MAIN_JOBS) begin
      if (!dut.engine_active) begin
        if (!dut.output_mailbox_ready) idle_return_cycles = idle_return_cycles + 1;
        else idle_input_cycles = idle_input_cycles + 1;
      end else if (!dut.adapter.configured) config_cycles = config_cycles + 1;
      else if (!dut.engine_input_closed) load_cycles = load_cycles + 1;
      else if (dut.engine_output_closed) drain_cycles = drain_cycles + 1;
      else if (dut.fast_output_valid || output_phase_seen) output_cycles = output_cycles + 1;
      else compute_cycles = compute_cycles + 1;
    end
    if (dut.fast_output_valid) output_phase_seen = 1;
    if (!dut.fast_running || dut.fast_fault || expect_fault) staged_stalled = 0;
    else begin
      if (dut.adapter.input_start_accept && dut.adapter.expected_output_position !== 0)
        $fatal(1, "new shared job has stale output position");
      if (staged_stalled && (!dut.return_valid ||
          {dut.engine_metadata, dut.return_last, dut.return_position,
           dut.return_exponent, dut.return_data} !== staged_word))
        $fatal(1, "staged return/descriptor changed before acceptance");
      staged_stalled = dut.return_valid && !dut.return_accept;
      staged_word = {dut.engine_metadata, dut.return_last, dut.return_position,
                     dut.return_exponent, dut.return_data};
      if (dut.return_accept && dut.return_last) begin
        if (!dut.engine_active || !dut.engine_output_closed || !dut.return_complete_seen)
          $fatal(1, "last return committed before qualified drain completion");
        committed_jobs = committed_jobs + 1;
      end
    end
  end
  always @(negedge clk) output_ready = !OUTPUT_STALL_MODE ||
      (cycle_count % 19 != 7 && cycle_count % 19 != 8);
  always @(posedge clk) begin
    cycle_count = cycle_count + 1;
    if (cycle_count > 3000 * (MAIN_JOBS + 10)) $fatal(1, "shared mailbox service watchdog");
    if (!resetn || !fft_resetn) stalled = 0;
    else begin
      if (service_fault && !expect_fault) $fatal(1, "unexpected transform service fault");
      if (stalled && (!output_valid ||
          {output_metadata, output_last, output_position, output_data} !== stalled_word))
        $fatal(1, "stalled transform output changed");
      stalled = output_valid && !output_ready;
      stalled_word = {output_metadata, output_last, output_position, output_data};
      if (output_valid && output_ready) begin
        fixture = (output_job / 2) % 3;
        if (output_data !== (output_job % 2 ? inverse_values[fixture*512 + output_word] :
                                           forward_values[fixture*512 + output_word]) ||
            output_metadata[74:5] !== tag(output_job) ||
            output_metadata[4:0] !== (output_job % 2 ? inverse_exponents[fixture] :
                                                     forward_exponents[fixture]) ||
            output_position !== output_word || output_last !== (output_word == 511))
          $fatal(1, "transform mismatch job=%0d position=%0d got=%h tag=%h",
                 output_job, output_word, output_data, output_metadata);
        checked_words = checked_words + 1;
        if (output_word == 511) begin
          $display("SHARED_MAILBOX_JOB job=%0d cycle=%0d", output_job, cycle_count);
          if (output_job % 2 && output_job < MAIN_JOBS) begin
            if (previous_pair_cycle) begin
              $display("SHARED_MAILBOX_PAIR_INTERVAL slow_cycles=%0d", cycle_count - previous_pair_cycle);
              if (cycle_count - previous_pair_cycle > maximum_pair_cycles)
                maximum_pair_cycles = cycle_count - previous_pair_cycle;
            end
            previous_pair_cycle = cycle_count;
          end
          output_job = output_job + 1;
          output_word = 0;
        end else output_word = output_word + 1;
      end
    end
  end
  task automatic send_job(input integer job_id);
    integer p, f;
    begin
      f = (job_id / 2) % 3;
      for (p = 0; p < 512; p = p + 1) begin
        @(negedge clk);
        input_valid = 1;
        input_position = p;
        input_last = p == 511;
        input_metadata = tag(job_id);
        input_data = job_id % 2 ? products[f*512+p] :
          {samples[f*447+p][31:16], 2'b00, samples[f*447+p][15:0], 2'b00};
        @(posedge clk);
        while (!input_ready) @(posedge clk);
      end
      @(negedge clk); input_valid = 0;
    end
  endtask
  task automatic stalled_malformed_input_job(input integer target, input bit corrupt_last);
    reg committed_before, acknowledged_before;
    reg [8:0] address_before, position_before;
    reg [35:0] payload_before;
    integer output_before;
    begin
      expect_fault = 1;
      committed_before = dut.output_mailbox.request_toggle;
      output_before = output_job;
      fork
        send_job(output_before);
        begin
          wait (dut.fast_input_valid && dut.fast_input_position == target &&
                dut.adapter.configured && dut.adapter_input_ready);
          @(negedge fft_clk);
          force dut.core_input_ready = 1'b0;
          if (corrupt_last) begin
            if (target == 511) force dut.fast_input_last = 1'b0;
            else force dut.fast_input_last = 1'b1;
          end else force dut.fast_input_position = 9'd510;
          acknowledged_before = dut.input_mailbox.acknowledge_toggle;
          address_before = dut.input_mailbox.read_address;
          position_before = dut.input_mailbox.read_output_position;
          payload_before = dut.input_mailbox.read_payload;
          @(posedge fft_clk);
          if (!dut.adapter.input_framing_error_now || dut.fast_input_ready ||
              dut.core_input_valid)
            $fatal(1, "malformed stalled input not consumed only by checker");
          @(negedge fft_clk);
          if (!dut.adapter_fault || dut.input_mailbox.acknowledge_toggle !== acknowledged_before ||
              dut.input_mailbox.read_address !== address_before ||
              dut.input_mailbox.read_output_position !== position_before ||
              dut.input_mailbox.read_payload !== payload_before)
            $fatal(1, "malformed stalled input retired mailbox storage");
          release dut.core_input_ready;
          release dut.fast_input_position;
          release dut.fast_input_last;
          repeat (12) @(negedge clk);
          if (!service_fault || output_valid || input_ready || output_job != output_before ||
              dut.output_mailbox.request_toggle !== committed_before ||
              dut.input_mailbox.acknowledge_toggle !== acknowledged_before)
            $fatal(1, "malformed stalled input escaped quarantine target=%0d last=%0d", target, corrupt_last);
        end
      join
      input_retirement_fault_cases = input_retirement_fault_cases + 1;
      recover(corrupt_last);
      send_job(output_before);
      while (output_job != output_before + 1) @(negedge clk);
      repeat (12) @(negedge clk);
    end
  endtask
  task automatic blocked_return_job(input bit corrupt_metadata);
    reg committed_before;
    integer output_before;
    begin
      expect_fault = 1;
      committed_before = dut.output_mailbox.request_toggle;
      output_before = output_job;
      fork
        send_job(output_before);
        begin
          wait (dut.fast_output_valid && dut.fast_output_position == 10);
          @(negedge fft_clk);
          force dut.output_mailbox_ready = 1'b0;
          if (corrupt_metadata) force dut.core_output_user[8:0] = 9'd11;
          @(negedge fft_clk);
          release dut.output_mailbox_ready;
          release dut.core_output_user;
          repeat (12) @(negedge clk);
          if (!service_fault || output_valid || input_ready || output_job != output_before ||
              dut.output_mailbox.request_toggle !== committed_before)
            $fatal(1, "blocked return escaped quarantine corrupt=%0d", corrupt_metadata);
        end
      join
      transport_fault_cases = transport_fault_cases + 1;
      recover(corrupt_metadata);
      send_job(output_before);
      while (output_job != output_before + 1) @(negedge clk);
      repeat (12) @(negedge clk);
    end
  endtask
  task automatic final_fault_job(input integer kind);
    reg committed_before;
    integer output_before;
    begin
      expect_fault = 1;
      committed_before = dut.output_mailbox.request_toggle;
      output_before = output_job;
      fork
        send_job(output_before);
        begin
          if (kind == 5)
            wait (dut.return_valid && dut.return_last && !dut.return_complete_seen);
          else
            wait (dut.fast_output_valid && dut.fast_output_position == 511);
          @(negedge fft_clk);
          case (kind)
            0, 5: force dut.event_last_missing = 1'b1;
            1: force dut.event_frame = 1'b1;
            2: force dut.event_status_halt = 1'b1;
            3: force dut.core_output_user[8:0] = 9'd510;
            4: force dut.core_output_user[20:16] = 5'd31;
          endcase
          @(negedge fft_clk);
          release dut.event_last_missing;
          release dut.event_frame;
          release dut.event_status_halt;
          release dut.core_output_user;
          repeat (12) @(negedge clk);
          if (!service_fault || output_valid || input_ready || output_job != output_before ||
              dut.output_mailbox.request_toggle !== committed_before)
            $fatal(1, "final fault escaped commit fence kind=%0d", kind);
        end
      join
      final_fault_cases = final_fault_cases + 1;
      recover(kind[0]);
      send_job(output_before);
      while (output_job != output_before + 1) @(negedge clk);
      repeat (12) @(negedge clk);
    end
  endtask
  task automatic reset_in_drain(input bit fast_side);
    integer output_before;
    begin
      expect_fault = 1;
      output_before = output_job;
      fork
        send_job(output_before);
        begin
          wait (dut.return_valid && dut.return_last && !dut.return_complete_seen);
          @(negedge fft_clk);
          if (fast_side) fft_resetn = 0;
          else resetn = 0;
          repeat (12) @(negedge clk);
          if (output_valid || output_job != output_before || dut.return_valid)
            $fatal(1, "drain reset published or retained final staged word");
          if (fast_side) fft_resetn = 1;
          else resetn = 1;
          repeat (12) @(negedge clk);
          if (service_fault || !input_ready)
            $fatal(1, "drain reset failed recovery");
        end
      join
      expect_fault = 0;
      drain_reset_cases = drain_reset_cases + 1;
      send_job(output_before);
      while (output_job != output_before + 1) @(negedge clk);
      repeat (12) @(negedge clk);
    end
  endtask
  task automatic recover(input bit fast_side);
    begin
      @(negedge clk);
      if (fast_side) fft_resetn = 0;
      else resetn = 0;
      repeat (8) @(negedge clk);
      if (fast_side) fft_resetn = 1;
      else resetn = 1;
      repeat (12) @(negedge clk);
      if (service_fault || output_valid || !input_ready) $fatal(1, "service recovery failed");
      expect_fault = 0;
    end
  endtask
  initial begin
    $readmemh("samples_ci16.mem", samples);
    $readmemh("forward_q17.mem", forward_values);
    $readmemh("product_q17.mem", products);
    $readmemh("inverse_q17.mem", inverse_values);
    $readmemh("forward_exponents.mem", forward_exponents);
    $readmemh("inverse_exponents.mem", inverse_exponents);
    repeat (8) @(negedge clk);
    resetn = 1;
    fft_resetn = 1;
    if (MAIN_JOBS < 6 || MAIN_JOBS % 2) $fatal(1, "requires an even number of at least six jobs");
    for (job = 0; job < MAIN_JOBS; job = job + 1) send_job(job);
    while (output_job < MAIN_JOBS) @(negedge clk);
    repeat (12) @(negedge clk);
    expect_fault = 1;
    // Inject a real adapter fault AFTER partial output has entered the return
    // mailbox. That incomplete transform must never become host-visible.
    fork
      send_job(MAIN_JOBS);
      begin
        wait (dut.fast_output_valid && dut.fast_output_position == 10);
        @(negedge fft_clk);
        force dut.adapter.protocol_fault = 1;
        repeat (12) @(negedge clk);
        if (!service_fault || output_valid || input_ready || output_job != MAIN_JOBS)
          $fatal(1, "in-flight FFT fault was not fenced");
        release dut.adapter.protocol_fault;
      end
    join
    recover(0);
    send_job(MAIN_JOBS);
    while (output_job < MAIN_JOBS + 1) @(negedge clk);
    repeat (12) @(negedge clk);
    expect_fault = 1;
    input_position = 1; input_last = 0; input_valid = 1;
    @(negedge clk); input_valid = 0;
    repeat (12) @(negedge clk);
    if (!service_fault || output_valid || input_ready) $fatal(1, "framing fault was not fenced");
    recover(1);
    send_job(MAIN_JOBS + 1);
    while (output_job < MAIN_JOBS + 2) @(negedge clk);
    repeat (20) @(negedge clk);
    for (job = 0; job < 6; job = job + 1) final_fault_job(job);
    reset_in_drain(0);
    reset_in_drain(1);
    blocked_return_job(0);
    blocked_return_job(1);
    stalled_malformed_input_job(0, 0);
    stalled_malformed_input_job(0, 1);
    stalled_malformed_input_job(255, 0);
    stalled_malformed_input_job(255, 1);
    stalled_malformed_input_job(511, 0);
    stalled_malformed_input_job(511, 1);
    if (checked_words != (MAIN_JOBS + 18) * 512 || committed_jobs != MAIN_JOBS + 18 ||
        final_fault_cases != 6 || drain_reset_cases != 2 || transport_fault_cases != 2 ||
        input_retirement_fault_cases != 6 || unmatched_input_accepts != 6 ||
        speculative_counter_advances == 0 ||
        raw_only_overruns == 0 || output_valid || service_fault)
      $fatal(1, "final service count");
    if (maximum_pair_cycles > 2980) $fatal(1, "saturated service misses nominal pair budget");
    $display("SHARED_XFFT_MAILBOX_PASS jobs=%0d exact_words=%0d max_saturated_pair_cycles=%0d slow_mhz=100 fft_mhz=200 stalls=%0d in_flight_fft_fault=1 framing_fault=1 independent_reset_recovery=2 RECEIVER_UNQUALIFIED",
             MAIN_JOBS + 18, checked_words, maximum_pair_cycles, OUTPUT_STALL_MODE);
    $display("SHARED_XFFT_RETURN_FENCE_PASS final_fault_cases=%0d drain_reset_cases=%0d committed_jobs=%0d metadata_high_bits=1 last_word_drain=1",
             final_fault_cases, drain_reset_cases, committed_jobs);
    $display("SHARED_XFFT_SERVICE_CYCLES main_jobs=%0d output_stall_mode=%0d fast_mhz=200 wait_input=%0d wait_return=%0d config=%0d load=%0d compute=%0d output=%0d drain=%0d",
             MAIN_JOBS, OUTPUT_STALL_MODE, idle_input_cycles, idle_return_cycles,
             config_cycles, load_cycles, compute_cycles, output_cycles, drain_cycles);
    $display("SHARED_XFFT_TRANSPORT_SPLIT_PASS blocked_return_cases=%0d raw_only_overruns=%0d old_validated_overruns_preserved=1 healthy_closed_state_equivalent=1 active_descriptor_stable=1",
             transport_fault_cases, raw_only_overruns);
    $display("SHARED_XFFT_COUNTER_RETIREMENT_PASS stalled_malformed_input_cases=%0d unmatched_input_accepts=%0d speculative_counter_advances=%0d healthy_shadow_counter=1 mailbox_ack_held=1 public_completion_fenced=1",
             input_retirement_fault_cases, unmatched_input_accepts, speculative_counter_advances);
    $finish(0);
  end
endmodule
