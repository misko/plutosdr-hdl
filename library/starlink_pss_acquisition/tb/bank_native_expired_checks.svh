// Separate expired-request epoch. No product signal is forced or driven here.
// Public AXI owns all configuration/commands/telemetry; hierarchy is observation.
`define EN_BANK dut.acquisition.bank_transform.iq_to_score.island
`define EN_RAW native.i_core.i_raw_tracking_core
`define EN_SCHED native.i_core.i_raw_tracking_core.i_candidate_scheduler
  parameter integer NATIVE_OFFSET = 520;
  parameter integer NATIVE_TRUE_PSS = 1;
  initial if (NATIVE_OFFSET != 520 || NATIVE_TRUE_PSS != 1)
    fail("expired profile requires unchanged520-PSS cohort");
  localparam [63:0] NATIVE_CENTER = FIRST + 520;
  localparam [31:0] NATIVE_REQUEST = 32'h15005202;
  localparam [31:0] NATIVE_GENERATION = 32'h15000002;
  reg source_enable = 0;
  wire native_irq, native_injected;
  reg [31:0] native_coefficients [0:65], expired_registers [0:61];
  reg native_configured = 0, expired_issued = 0, expired_window = 0;
  reg expired_done = 0, expired_first_snapshot = 0;
  integer expired_public_submits = 0, expired_wrapper_handshakes = 0;
  integer expired_fifo_accepts = 0, expired_sample_handshakes = 0;
  integer expired_fast_cycles = 0, expired_fast_handshake_witness = 0;
  integer expired_pilot_accepts = 0, expired_empty_stop = 0, expired_register_reads = 0;
  reg [63:0] expired_submit_index = 0, expired_handshake_index = 0, expired_lead = 0;

  axi_starlink_pss_tracker #(.RATE_MSPS(15), .ENABLE_INJECTION(0), .USE_DSP_REDUCER(1)) native (
    .sample_clk(sample_clk), .sample_reset(!resetn),
    .sample_i(sample_data[15:0]), .sample_q(sample_data[31:16]),
    .sample_strobe(sample_strobe), .sample_enable(source_enable),
    .sample_index(sample_index), .sample_timestamp(sample_index),
    .selected_sample_i(), .selected_sample_q(), .selected_sample_strobe(),
    .selected_sample_enable(), .selected_sample_index(), .selected_sample_timestamp(),
    .selected_sample_injected(native_injected), .irq(native_irq),
    .s_axi_aclk(clk), .s_axi_aresetn(resetn),
    .s_axi_awaddr(awaddr[2]), .s_axi_awvalid(awvalid[2]), .s_axi_awready(awready[2]),
    .s_axi_wdata(wdata[2]), .s_axi_wstrb(4'hf), .s_axi_wvalid(wvalid[2]), .s_axi_wready(wready[2]),
    .s_axi_bvalid(bvalid[2]), .s_axi_bresp(bresp[2]), .s_axi_bready(bready[2]),
    .s_axi_araddr(araddr[2]), .s_axi_arvalid(arvalid[2]), .s_axi_arready(arready[2]),
    .s_axi_rvalid(rvalid[2]), .s_axi_rdata(rdata[2]), .s_axi_rresp(rresp[2]), .s_axi_rready(rready[2]),
    .s_axi_awprot(3'd0), .s_axi_arprot(3'd0)
  );

  task automatic native_empty;
    if (native_injected !== 0 || native_irq !== 0 || native.result_available !== 0 ||
        native.result_word_read !== 0 || native.result_release !== 0 ||
        native.candidate_command_overrun_count !== 0 || native.coefficient_write_overrun_count !== 0 ||
        native.queue_overrun_count !== 0 || native.engine_consumed_count !== 0 ||
        native.correlator_bound_error_count !== 0 || native.reducer_processed_job_count !== 0 ||
        native.reducer_emitted_result_count !== 0 || native.reducer_invalid_tuple_count !== 0 ||
        native.reducer_bound_error_count !== 0 || native.reducer_protocol_error_count !== 0 ||
        native.result_published_count !== 0 || native.result_overrun_count !== 0 ||
        native.result_consumed_count !== 0 || `EN_RAW.correlator_busy !== 0) begin
      // Diagnostic-only: retain the original predicate and fatal result.
      $display("BANK_EXPIRED_EMPTY_DIAGNOSTIC time=%0t injected=%b irq=%b available=%b word_read=%b release=%b command_overrun=%0d coefficient_overrun=%0d queue_overrun=%0d engine_consumed=%0d correlator_bound=%0d reducer_processed=%0d reducer_emitted=%0d reducer_invalid=%0d reducer_bound=%0d reducer_protocol=%0d result_published=%0d result_overrun=%0d result_consumed=%0d correlator_busy=%b",
        $time, native_injected, native_irq, native.result_available,
        native.result_word_read, native.result_release,
        native.candidate_command_overrun_count, native.coefficient_write_overrun_count,
        native.queue_overrun_count, native.engine_consumed_count,
        native.correlator_bound_error_count, native.reducer_processed_job_count,
        native.reducer_emitted_result_count, native.reducer_invalid_tuple_count,
        native.reducer_bound_error_count, native.reducer_protocol_error_count,
        native.result_published_count, native.result_overrun_count,
        native.result_consumed_count, `EN_RAW.correlator_busy);
      $display("BANK_EXPIRED_CONFIG_DIAGNOSTIC configured=%b source_enable=%b strobe=%b issued=%b state=%0d coefficient_commit=%b commit_ready=%b commit_accepted=%b commit_rejected=%b active_valid=%b active_generation=%08x active_energy=%0d shadow_count=%0d clear_pending=%b push_pending=%b commit_pending=%b generation_stage=%08x",
        native_configured, source_enable, sample_strobe, expired_issued,
        `EN_RAW.i_sliding_correlator.state, native.coefficient_commit,
        native.coefficient_commit_ready, native.coefficient_commit_accepted,
        native.coefficient_commit_rejected, native.active_coefficient_valid,
        native.active_coefficient_generation, native.active_coefficient_energy,
        native.shadow_coefficient_count, native.coefficient_clear_pending,
        native.coefficient_push_pending, native.coefficient_commit_pending,
        native.coefficient_generation_stage);
      fail("expired request unexpectedly produced work/result/IRQ or control fault");
    end
    if (native_configured && (native.active_coefficient_valid !== 1 ||
        native.active_coefficient_generation !== NATIVE_GENERATION ||
        native.active_coefficient_energy !== 48'd1073742825))
      fail("expired epoch coefficient identity changed");
  endtask

  always @(posedge sample_clk) if (resetn) begin
    if (`EN_SCHED.command_handshake) begin
      if (!expired_issued || !expired_window || !source_enable || !sample_strobe ||
          `EN_SCHED.sample_is_consecutive !== 1 || `EN_SCHED.command_late !== 1 ||
          `EN_SCHED.command_lead[63] !== 1 || `EN_SCHED.command_duplicate !== 0 ||
          `EN_SCHED.command_overlap !== 0 || `EN_SCHED.last_admitted_valid !== 0 ||
          `EN_SCHED.command_start_index != FIRST + 488 ||
          `EN_SCHED.command_center_index != NATIVE_CENTER ||
          `EN_SCHED.command_center_timestamp != NATIVE_CENTER ||
          `EN_SCHED.command_request_id != NATIVE_REQUEST ||
          sample_index < FIRST + 620 || sample_index > FIRST + 640)
        fail("expired actual sample handshake lacks first-request late predicate/identity");
      expired_sample_handshakes = expired_sample_handshakes + 1;
      expired_handshake_index = sample_index;
      expired_lead = `EN_SCHED.command_lead;
      if (expired_sample_handshakes != 1 || expired_lead != (FIRST + 488) - (sample_index + 1))
        fail("expired command repeated or lead arithmetic differs");
      $display("BANK_EXPIRED_REJECT index=%0d start=%0d lead_hex=%016x late=1 duplicate=0 overlap=0 request=15005202",
        sample_index, FIRST + 488, expired_lead);
    end
    #0.001; // Observe the scheduler's same-edge NBA branch, not a later duplicate.
    if (native.admitted_count !== 0 || native.completed_capture_count !== 0 ||
        native.rejected_count !== expired_sample_handshakes || native.late_count !== expired_sample_handshakes ||
        native.duplicate_count !== 0 || native.overlap_count !== 0 || native.aborted_count !== 0 ||
        native.valid_gap_abort_count !== 0 || native.index_jump_abort_count !== 0 || native.timestamp_abort_count !== 0 ||
        native.capture_published_count !== 0 || native.capture_abort_discard_count !== 0 ||
        native.capture_buffer_overrun_count !== 0 || native.capture_protocol_error_count !== 0 ||
        `EN_SCHED.o_capture_valid !== 0 || `EN_SCHED.o_capture_start !== 0 ||
        `EN_SCHED.o_capture_done !== 0 || `EN_SCHED.o_capture_abort !== 0 ||
        native.candidate_pending !== 0 || native.capture_active !== 0)
      fail("expired same-edge rejection counters or zero-capture ownership contract violated");
  end

  always @(posedge fft_clk) if (resetn) begin
    if (expired_window && `EN_BANK.state == `EN_BANK.RUN_JOB &&
        `EN_BANK.core_aresetn && !`EN_BANK.fast_fault)
      expired_fast_cycles = expired_fast_cycles + 1;
    if (expired_sample_handshakes == 1 && expired_fast_handshake_witness == 0) begin
      if (`EN_BANK.state != `EN_BANK.RUN_JOB || !`EN_BANK.core_aresetn || `EN_BANK.fast_fault)
        fail("actual FFT not RUN_JOB at first fast edge after native rejection");
      expired_fast_handshake_witness = 1;
    end
  end

  always @(posedge clk) if (resetn) begin
    native_empty();
    if (native.up_wreq && native.up_waddr == native.REG_CANDIDATE_CONTROL && native.up_wdata[0]) begin
      if (!expired_issued || !expired_window || native.up_wdata != 1 ||
          sample_index < FIRST + 620 || sample_index > FIRST + 624 ||
          !source_enable || !observed_pipeline_active || !pilot_enable)
        fail("expired public submission outside bounded active source epoch");
      expired_public_submits = expired_public_submits + 1;
      expired_submit_index = sample_index;
      if (expired_public_submits != 1) fail("expired public submit repeated");
      $display("BANK_EXPIRED_PUBLIC_SUBMIT index=%0d request=15005202 center=%0d", sample_index, NATIVE_CENTER);
    end
    if (native.candidate_command_handshake) begin
      if (expired_public_submits != 1 || native.candidate_pending_request != NATIVE_REQUEST ||
          native.candidate_pending_center != NATIVE_CENTER || native.candidate_pending_timestamp != NATIVE_CENTER)
        fail("expired wrapper command handshake identity differs");
      expired_wrapper_handshakes = expired_wrapper_handshakes + 1;
    end
    if (native.candidate_submit_accepted) expired_fifo_accepts = expired_fifo_accepts + 1;
    if (expired_window && observed_pipeline_active && pilot_enable && pilot.ddc.accept)
      expired_pilot_accepts = expired_pilot_accepts + 1;
    if (dut.stop_ack && dut.map_publish_count == 1) begin
      if (!expired_first_snapshot || expired_sample_handshakes != 1 || native_irq || native.result_available)
        fail("expired native emptiness not retained at healthy coarse stop");
      expired_empty_stop = expired_empty_stop + 1;
    end
  end

  task automatic configure_native;
    integer tap, timeout;
    reg [31:0] readback;
    $readmemh("native_coefficients_q15.mem", native_coefficients);
    $readmemh("native_expired_registers.mem", expired_registers);
    expect_reg(2, 8'h04, 32'h00010002); expect_reg(2, 8'h08, 15);
    expect_reg(2, 8'h0c, {8'd0,8'd61,8'd130,8'd66}); expect_reg(2, 8'h10, 32'h1d);
    write_reg(2, 8'h44, 1);
    for (tap = 0; tap < 66; tap = tap + 1)
      write_reg(2, 8'h40, {native_coefficients[tap][15:0], native_coefficients[tap][31:16]});
    write_reg(2, 8'h48, NATIVE_GENERATION); write_reg(2, 8'h44, 2);
    timeout = 0; readback = 0;
    while (readback != NATIVE_GENERATION && timeout < 2000) begin
      read_reg(2, 8'h4c, readback); timeout = timeout + 1;
    end
    if (timeout == 2000) fail("expired epoch coefficient commit timeout");
    expect_reg(2, 8'h60, 32'd1073742825); expect_reg(2, 8'h64, 0);
    expect_reg(2, 8'h5c, 32'h1a000000);
    native_configured = 1;
  endtask

  task automatic expired_snapshot(input integer generation);
    reg [31:0] actual, observed_generation;
    integer n, timeout;
    write_reg(2, 8'h68, 1);
    timeout = 0; actual = 0;
    while (actual != 1 && timeout < 2000) begin
      read_reg(2, 8'h6c, actual); timeout = timeout + 1;
    end
    if (timeout == 2000) fail("expired atomic telemetry timeout");
    read_reg(2, 8'h70, observed_generation);
    if (observed_generation != generation) fail("expired atomic snapshot generation differs");
    for (n = 0; n < 31; n = n + 1) begin
      if (expired_registers[2*n][31:8] != 0) fail("expired public register oracle malformed");
      read_reg(2, expired_registers[2*n][7:0], actual);
      if (actual !== expired_registers[2*n+1]) fail("expired public counter/empty result mismatch");
      $display("BANK_EXPIRED_REGISTER generation=%0d ordinal=%0d address=%02x value=%08x",
        generation, n, expired_registers[2*n][7:0], actual);
      expired_register_reads = expired_register_reads + 1;
    end
    expect_reg(2, 8'h70, observed_generation);
    read_reg(2, 8'h14, actual);
    if ((actual & 32'hc0) !== 0 || native_irq) fail("expired public status exposes a result/IRQ");
    $display("BANK_EXPIRED_EMPTY generation=%0d result_status=1a000000 available=0 irq=0 packet_data_reads=0", generation);
  endtask

  task automatic run_native_command;
    integer timeout;
    // Stage the immutable request early; the only submit strobe is near620.
    wait(source_enable && sample_strobe && sample_index >= FIRST + 16);
    write_reg(2, 8'h20, NATIVE_REQUEST); write_reg(2, 8'h24, NATIVE_CENTER[31:0]);
    write_reg(2, 8'h28, NATIVE_CENTER[63:32]); write_reg(2, 8'h2c, NATIVE_CENTER[31:0]);
    write_reg(2, 8'h30, NATIVE_CENTER[63:32]);
    wait(source_enable && sample_strobe && sample_index >= FIRST + 620);
    expired_issued = 1; expired_window = 1;
    write_reg(2, 8'h34, 1);
    timeout = 0;
    while (expired_sample_handshakes != 1 && timeout < 200) begin
      @(negedge clk); timeout = timeout + 1;
    end
    if (timeout == 200) fail("expired sample-domain rejection handshake timeout");
    repeat (4) @(negedge clk);
    expired_window = 0;
    expired_snapshot(1); expired_first_snapshot = 1;
    wait(ack_count == 2); repeat (10) @(negedge clk);
    if (!pilot_enable || delivered_count >= PILOT_COUNT) fail("pilot not independent at expired post-stop audit");
    expired_snapshot(2); expired_done = 1;
  endtask

  task automatic verify_native_terminal;
    native_empty();
    if (!expired_done || expired_public_submits != 1 || expired_wrapper_handshakes != 1 ||
        expired_fifo_accepts != 1 || expired_sample_handshakes != 1 || expired_register_reads != 62 ||
        expired_empty_stop != 1 || expired_fast_cycles < 1 || expired_fast_handshake_witness != 1 ||
        expired_pilot_accepts < 1 || native.rejected_count != 1 || native.late_count != 1)
      fail("expired terminal handshake/empty/concurrent inventory missing");
    $display("BANK_EXPIRED_CONCURRENCY fft_run_fast_cycles=%0d first_fast_after_reject=1 pilot_input_accepts=%0d", expired_fast_cycles, expired_pilot_accepts);
    $display("BANK_EXPIRED_EXACT_PASS public_submits=1 wrapper_handshakes=1 fifo_accepts=1 sample_handshakes=1 rejected=1 late=1 admitted=0 capture_words=0 completed=0 packets=0 irq=0 public_register_reads=62 empty_across_stop=1");
    $display("BANK_NATIVE_EXPIRED_PASS source_msps=15 fast_mhz=%0d profile=520-pss-expired source_words=4096 scores=894 map_words=447 pilot_bytes=2048 NATIVE_REQUEST_REJECTED_COARSE_PILOT_HEALTHY_NOT_CAUSAL", FAST_MHZ);
  endtask
`undef EN_BANK
`undef EN_RAW
`undef EN_SCHED
