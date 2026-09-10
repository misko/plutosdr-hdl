// Native30 common-source checks. Shared by non-FFT budget probe and future
// paired harness. Every hierarchical reference is an observation, never force.
`define HN_CORE native.i_core
`define HN_RAW native.i_core.i_raw_tracking_core
`define HN_SCHED native.i_core.i_raw_tracking_core.i_candidate_scheduler
  localparam [63:0] NATIVE_CENTER = 64'd17179870192;
  localparam [63:0] NATIVE_CAPTURE_FIRST = NATIVE_CENTER - 64;
  localparam [63:0] NATIVE_DEADLINE = 64'd17179869408;
  localparam [31:0] NATIVE_REQUEST = 32'h30000520;
  localparam [31:0] NATIVE_GENERATION = 32'h30000001;
  wire native_irq, native_injected;
  reg [31:0] native_coefficients [0:131], native_packet [0:25], native_capture [0:259];
  reg [7:0] native_raw_lag [0:128];
  reg [63:0] native_raw_index [0:128];
  reg [47:0] native_raw_real [0:128], native_raw_imag [0:128];
  reg [47:0] native_raw_ex [0:128], native_raw_eh [0:128];
  reg [95:0] native_raw_power [0:128];
  reg [8:0] native_raw_saturation [0:128];
  reg native_raw_qualified [0:128];
  integer native_admissions = 0, native_capture_count = 0, native_raw_count = 0;
  integer native_qualified_count = 0, native_packet_reads = 0, native_readout_transactions = 0;
  integer native_capture_fft_overlap = 0, native_compute_overlap = 0, native_compute_after_stop = 0;
  integer native_capture_end_cycle = -1, native_publish_cycle = -1, native_release_cycle = -1;
  integer native_raw_fd, native_configured = 0;
  reg native_command_issued = 0, native_done = 0;
  reg [63:0] native_admission_index = 0, native_admission_lead = 0;
  reg [95:0] native_square_re, native_square_im;

  axi_starlink_pss_tracker #(.RATE_MSPS(30), .ENABLE_INJECTION(0), .USE_DSP_REDUCER(1)) native (
    .sample_clk(sample_clk), .sample_reset(!resetn), .sample_i(sample_data[15:0]),
    .sample_q(sample_data[31:16]), .sample_strobe(sample_strobe), .sample_enable(source_enable),
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
  task automatic native_healthy;
    if ({native_injected, native.candidate_command_overrun_count,
        native.coefficient_write_overrun_count, native.queue_overrun_count,
        native.rejected_count, native.late_count, native.duplicate_count,
        native.overlap_count, native.aborted_count, native.valid_gap_abort_count,
        native.index_jump_abort_count, native.timestamp_abort_count,
        native.capture_abort_discard_count, native.capture_buffer_overrun_count,
        native.capture_protocol_error_count, native.correlator_bound_error_count,
        native.reducer_invalid_tuple_count, native.reducer_bound_error_count,
        native.reducer_protocol_error_count, native.result_overrun_count} !== 0)
      fail("native30 healthy counter/identity failure");
    if (native_configured && (!native.active_coefficient_valid ||
        native.active_coefficient_generation !== NATIVE_GENERATION ||
        native.active_coefficient_energy !== 48'd1073746351))
      fail("native30 coefficient identity changed");
  endtask
  always @(posedge sample_clk) if (resetn) begin
    if (`HN_SCHED.command_handshake && source_enable) begin
      if (!native_command_issued || `HN_SCHED.command_late ||
          `HN_SCHED.command_lead < 128 || `HN_SCHED.command_center_index !== NATIVE_CENTER ||
          `HN_SCHED.command_center_timestamp !== NATIVE_CENTER ||
          `HN_SCHED.command_request_id !== NATIVE_REQUEST || sample_index > NATIVE_DEADLINE)
        fail("native30 actual admission identity/lead/deadline");
      native_admissions = native_admissions + 1;
      native_admission_index = sample_index; native_admission_lead = `HN_SCHED.command_lead;
      if (native_admission_lead !== NATIVE_CAPTURE_FIRST - sample_index - 1)
        fail("native30 admission lead coordinate mismatch");
      $display("NATIVE30_ADMISSION index=%0d capture_start=%0d lead=%0d deadline=%0d",
        sample_index, NATIVE_CAPTURE_FIRST, native_admission_lead, NATIVE_DEADLINE);
    end
    #0.001;
    if (`HN_SCHED.o_capture_valid) begin
      if (native_capture_count >= 260 || native_admissions != 1 ||
          `HN_SCHED.o_capture_slot !== native_capture_count ||
          `HN_SCHED.o_capture_sample_index !== NATIVE_CAPTURE_FIRST + native_capture_count ||
          `HN_SCHED.o_capture_sample_timestamp !== NATIVE_CAPTURE_FIRST + native_capture_count ||
          {`HN_SCHED.o_capture_sample_q, `HN_SCHED.o_capture_sample_i} !== native_capture[native_capture_count])
        fail("native30 capture source/index/slot mismatch");
      native_capture_count = native_capture_count + 1;
      if (native_capture_count == 260) native_capture_end_cycle = cycles;
    end
  end
  always @(posedge fft_clk) if (resetn && native.capture_active && native_fft_active)
    native_capture_fft_overlap = native_capture_fft_overlap + 1;
  always @(posedge clk) if (resetn) begin
    native_healthy();
    if (`HN_RAW.correlator_busy && native_coarse_pilot_active) native_compute_overlap = native_compute_overlap + 1;
    if (`HN_RAW.correlator_busy && coarse_stopped) native_compute_after_stop = native_compute_after_stop + 1;
    if (`HN_CORE.raw_result_valid && `HN_CORE.raw_result_ready) begin
      if (native_raw_count >= 129 || `HN_CORE.raw_result_request_id !== NATIVE_REQUEST ||
          `HN_CORE.raw_result_center_index !== NATIVE_CENTER ||
          `HN_CORE.raw_result_center_timestamp !== NATIVE_CENTER ||
          `HN_CORE.raw_result_coefficient_generation !== NATIVE_GENERATION ||
          `HN_CORE.raw_result_lag !== native_raw_lag[native_raw_count] ||
          `HN_CORE.raw_result_timestamp !== native_raw_index[native_raw_count] ||
          `HN_CORE.raw_result_c_re !== native_raw_real[native_raw_count] ||
          `HN_CORE.raw_result_c_im !== native_raw_imag[native_raw_count] ||
          `HN_CORE.raw_result_ex !== native_raw_ex[native_raw_count] ||
          `HN_CORE.raw_result_eh !== native_raw_eh[native_raw_count] ||
          `HN_CORE.raw_result_saturation_events !== native_raw_saturation[native_raw_count] ||
          `HN_CORE.raw_result_in_track_aperture !== native_raw_qualified[native_raw_count])
        fail("native30 all-raw tuple exact mismatch");
      native_square_re = $signed(`HN_CORE.raw_result_c_re) * $signed(`HN_CORE.raw_result_c_re);
      native_square_im = $signed(`HN_CORE.raw_result_c_im) * $signed(`HN_CORE.raw_result_c_im);
      if (native_square_re + native_square_im !== native_raw_power[native_raw_count])
        fail("native30 raw tuple power mismatch");
      $fdisplay(native_raw_fd, "%0d %016x %012x %012x %012x %012x %024x %03x %0d",
        $signed(`HN_CORE.raw_result_lag), `HN_CORE.raw_result_timestamp,
        `HN_CORE.raw_result_c_re, `HN_CORE.raw_result_c_im, `HN_CORE.raw_result_ex,
        `HN_CORE.raw_result_eh, native_square_re + native_square_im,
        `HN_CORE.raw_result_saturation_events, `HN_CORE.raw_result_in_track_aperture);
      native_raw_count = native_raw_count + 1;
      if (`HN_CORE.raw_result_in_track_aperture) native_qualified_count = native_qualified_count + 1;
    end
    if (native_irq && native_publish_cycle < 0) begin
      native_publish_cycle = cycles;
      if (native_capture_end_cycle < 0 || cycles - native_capture_end_cycle > 24000)
        fail("native30 publication exceeded predeclared engine bound");
    end
    if (native_capture_end_cycle >= 0 && !native_done && cycles - native_capture_end_cycle > 28000)
      fail("native30 read/release exceeded predeclared post-capture bound");
  end
  task automatic configure_native;
    integer tap, timeout;
    reg [31:0] readback;
    $readmemh("native_coefficients_q15.mem", native_coefficients);
    $readmemh("native_expected_packet.mem", native_packet);
    $readmemh("native_capture_ci16.mem", native_capture);
    $readmemh("native_raw_lag.mem", native_raw_lag);
    $readmemh("native_raw_index.mem", native_raw_index);
    $readmemh("native_raw_real.mem", native_raw_real); $readmemh("native_raw_imag.mem", native_raw_imag);
    $readmemh("native_raw_ex.mem", native_raw_ex); $readmemh("native_raw_eh.mem", native_raw_eh);
    $readmemh("native_raw_power.mem", native_raw_power);
    $readmemh("native_raw_saturation.mem", native_raw_saturation);
    $readmemh("native_raw_qualified.mem", native_raw_qualified);
    native_raw_fd = $fopen("native30_actual_raw_tuples.txt", "w");
    if (!native_raw_fd) fail("native30 raw tuple log unavailable");
    expect_reg(2, 8'h00, 32'h50535354); expect_reg(2, 8'h04, 32'h00010003);
    expect_reg(2, 8'h08, 30); expect_reg(2, 8'h0c, 32'h0bca0884); expect_reg(2, 8'h10, 32'h1d);
    write_reg(2, 8'h44, 1);
    for (tap = 0; tap < 132; tap = tap + 1)
      write_reg(2, 8'h40, {native_coefficients[tap][15:0], native_coefficients[tap][31:16]});
    write_reg(2, 8'h48, NATIVE_GENERATION); write_reg(2, 8'h44, 2);
    timeout = 0; readback = 0;
    while (readback != NATIVE_GENERATION && timeout < 2000) begin
      read_reg(2, 8'h4c, readback); timeout = timeout + 1;
    end
    if (timeout == 2000) fail("native30 coefficient commit timeout");
    expect_reg(2, 8'h60, 1073746351); expect_reg(2, 8'h64, 0);
    native_configured = 1;
  endtask
  task automatic read_native_packet(input integer pass);
    reg [31:0] actual;
    for (integer word_index = 0; word_index < 26; word_index = word_index + 1) begin
      write_reg(2, 8'h50, word_index); read_reg(2, 8'h54, actual);
      if (actual !== native_packet[word_index]) fail("native30 public packet mismatch");
      $display("NATIVE30_PACKET_WORD pass=%0d word=%0d data=%08x", pass, word_index, actual);
      native_packet_reads = native_packet_reads + 1;
    end
  endtask
  task automatic run_native_command;
    reg [63:0] current_index;
    wait(source_enable && sample_strobe && sample_index >= 64'd17179869184);
    read_reg(2, 8'h18, current_index[31:0]); read_reg(2, 8'h1c, current_index[63:32]);
    if (current_index > NATIVE_DEADLINE || NATIVE_CAPTURE_FIRST - current_index - 1 < 128)
      fail("native30 telemetry schedule lacks lead");
    write_reg(2, 8'h20, NATIVE_REQUEST); write_reg(2, 8'h24, NATIVE_CENTER[31:0]);
    write_reg(2, 8'h28, NATIVE_CENTER[63:32]); write_reg(2, 8'h2c, NATIVE_CENTER[31:0]);
    write_reg(2, 8'h30, NATIVE_CENTER[63:32]);
    native_command_issued = 1; write_reg(2, 8'h34, 1);
    wait(native_irq); @(negedge clk);
    read_native_packet(0); repeat (32) @(negedge clk);
    if (!native_irq || !native.result_available) fail("native30 result not retained");
    read_native_packet(1); write_reg(2, 8'h58, 1);
    repeat (24) @(negedge clk);
    if (native_irq || native.result_available) fail("native30 result release failed");
    native_release_cycle = cycles;
    if (native_capture_count != 260 || native_raw_count != 129 || native_qualified_count != 121 ||
        native_packet_reads != 52 || native_admissions != 1)
      fail("native30 exact terminal inventory");
    native_done = 1; native_healthy(); $fclose(native_raw_fd);
    $display("NATIVE30_BUDGET_PASS capture_end_cycle=%0d publish_cycle=%0d release_cycle=%0d engine_cycles=%0d post_capture_cycles=%0d maximum_axi_cycles=%0d raw=129 qualified=121 capture=260 packet_reads=52",
      native_capture_end_cycle, native_publish_cycle, native_release_cycle,
      native_publish_cycle - native_capture_end_cycle, native_release_cycle - native_capture_end_cycle,
      maximum_axi_cycles);
  endtask
`undef HN_CORE
`undef HN_RAW
`undef HN_SCHED
