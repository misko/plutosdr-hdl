// Additive static-anchor smoke only. All native control/results use public AXI.
// Hierarchical signals below are read-only observations, never forced/driven.
`define BN_BANK dut.acquisition.bank_transform.iq_to_score.island
`define BN_RAW native.i_core.i_raw_tracking_core
`define BN_SCHED native.i_core.i_raw_tracking_core.i_candidate_scheduler
  parameter integer NATIVE_OFFSET = 447;
  initial if (NATIVE_OFFSET != 447 && NATIVE_OFFSET != 520)
    fail("native static anchor must be literal447 or520");
  localparam [63:0] NATIVE_CENTER = FIRST + NATIVE_OFFSET;
  localparam [63:0] NATIVE_DEADLINE = FIRST + 128;
  localparam [31:0] NATIVE_REQUEST = (NATIVE_OFFSET == 520) ? 32'h15005200 : 32'h15004470;
  localparam [31:0] NATIVE_GENERATION = 32'h15000001;
  reg source_enable = 0;
  wire native_irq, native_injected;
  reg [31:0] native_coefficients [0:65], native_packet [0:25];
  integer native_admissions = 0, native_capture_words = 0;
  integer native_capture_fft_overlap = 0, native_compute_overlap = 0;
  integer native_packet_reads = 0, native_retained_at_stop = 0;
  reg native_configured = 0, native_command_issued = 0, native_done = 0;
  reg native_first_read = 0;
  reg [63:0] native_admission_index = 0, native_admission_lead = 0;
  realtime native_capture_first_ns = 0, native_capture_last_ns = 0, first_fft_input_ns = 0;
  reg [63:0] first_fft_source_index = 0;

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

  task automatic native_healthy;
    if (native_injected || native.candidate_command_overrun_count ||
        native.coefficient_write_overrun_count || native.queue_overrun_count ||
        native.rejected_count || native.late_count || native.duplicate_count ||
        native.overlap_count || native.aborted_count || native.valid_gap_abort_count ||
        native.index_jump_abort_count || native.timestamp_abort_count ||
        native.capture_abort_discard_count || native.capture_buffer_overrun_count ||
        native.capture_protocol_error_count || native.correlator_bound_error_count ||
        native.reducer_invalid_tuple_count || native.reducer_bound_error_count ||
        native.reducer_protocol_error_count || native.result_overrun_count)
      fail("native healthy epoch counter/identity failure");
    if (native_configured && (!native.active_coefficient_valid ||
        native.active_coefficient_generation != NATIVE_GENERATION ||
        native.active_coefficient_energy != {native_packet[18][15:0], native_packet[17]}))
      fail("native committed coefficient identity changed");
  endtask

  always @(posedge sample_clk) if (resetn) begin
    if (`BN_SCHED.command_handshake && source_enable) begin
      if (!native_command_issued || `BN_SCHED.command_late ||
          `BN_SCHED.command_lead < 64 || `BN_SCHED.command_center_index != NATIVE_CENTER ||
          `BN_SCHED.command_center_timestamp != NATIVE_CENTER ||
          `BN_SCHED.command_request_id != NATIVE_REQUEST || sample_index > NATIVE_DEADLINE)
        fail("native actual admission missed identity/lead/deadline");
      native_admissions = native_admissions + 1;
      native_admission_index = sample_index;
      native_admission_lead = `BN_SCHED.command_lead;
      $display("BANK_NATIVE_ADMISSION index=%0d capture_start=%0d lead=%0d deadline=%0d",
        sample_index, NATIVE_CENTER - 32, native_admission_lead, NATIVE_DEADLINE);
    end
    #0.001;
    if (`BN_SCHED.o_capture_valid) begin
      if (native_capture_words == 0) native_capture_first_ns = $realtime;
      native_capture_last_ns = $realtime;
      if (native_admissions != 1 || `BN_SCHED.o_capture_slot != native_capture_words ||
          `BN_SCHED.o_capture_sample_index != NATIVE_CENTER - 32 + native_capture_words ||
          `BN_SCHED.o_capture_sample_timestamp != NATIVE_CENTER - 32 + native_capture_words ||
          {`BN_SCHED.o_capture_sample_q, `BN_SCHED.o_capture_sample_i} !==
            source_words[768 + NATIVE_OFFSET - 32 + native_capture_words])
        fail("native raw capture differs from exact same-source aperture");
      native_capture_words = native_capture_words + 1;
    end
  end

  // Sample each observed action in its owning domain. No fake slow FFT probe.
  always @(posedge fft_clk) if (resetn && `BN_BANK.state == `BN_BANK.RUN_JOB &&
      `BN_BANK.core_aresetn && !`BN_BANK.fast_fault) begin
    if (native.capture_active) native_capture_fft_overlap = native_capture_fft_overlap + 1;
    if (first_fft_input_ns == 0 && `BN_BANK.core_input_valid && `BN_BANK.core_input_ready &&
        !`BN_BANK.next_inverse && `BN_BANK.selected_position == 0) begin
      first_fft_input_ns = $realtime;
      first_fft_source_index = sample_index;
    end
  end
  always @(posedge clk) if (resetn) begin
    native_healthy();
    if (native_configured && `BN_RAW.correlator_busy && observed_pipeline_active &&
        pilot_enable && pilot.ddc.accept)
      native_compute_overlap = native_compute_overlap + 1;
    if (dut.stop_ack && dut.map_publish_count == 1) begin
      if (!native_first_read || !native.result_available || !native_irq)
        fail("native complete packet not retained across coarse stop");
      native_retained_at_stop = native_retained_at_stop + 1;
    end
  end

  task automatic configure_native;
    integer tap, timeout;
    reg [31:0] readback;
    $readmemh("native_coefficients_q15.mem", native_coefficients);
    $readmemh("native_expected_packet.mem", native_packet);
    if (native_packet[0] != 32'h31535350 || native_packet[1] != 32'h1a010001 ||
        native_packet[2] != NATIVE_REQUEST || native_packet[10] != NATIVE_GENERATION ||
        {native_packet[4], native_packet[3]} != NATIVE_CENTER ||
        {native_packet[6], native_packet[5]} != NATIVE_CENTER ||
        native_packet[7] != ((NATIVE_OFFSET == 520) ? -32'sd17 : 32'd0))
      fail("native independent packet identity mismatch");
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
    if (timeout == 2000) fail("native coefficient commit timeout");
    expect_reg(2, 8'h60, native_packet[17]); expect_reg(2, 8'h64, native_packet[18]);
    native_configured = 1;
  endtask

  task automatic read_native_packet(input integer pass);
    integer word_index;
    reg [31:0] actual;
    if (!native_irq) fail("native packet unavailable before public read");
    for (word_index = 0; word_index < 26; word_index = word_index + 1) begin
      write_reg(2, 8'h50, word_index); read_reg(2, 8'h54, actual);
      if (actual !== native_packet[word_index]) begin
        $display("BANK_NATIVE_WORD_MISMATCH pass=%0d word=%0d actual=%08x expected=%08x",
          pass, word_index, actual, native_packet[word_index]);
        fail("native public packet numerical mismatch");
      end
      $display("BANK_NATIVE_PACKET_WORD pass=%0d word=%0d data=%08x", pass, word_index, actual);
      native_packet_reads = native_packet_reads + 1;
    end
  endtask

  task automatic run_native_command;
    reg [63:0] current_index;
    reg [31:0] telemetry_generation;
    integer n;
    wait(source_enable && sample_strobe && sample_index >= FIRST + 16);
    read_reg(2, 8'h18, current_index[31:0]); read_reg(2, 8'h1c, current_index[63:32]);
    if (current_index < FIRST || current_index > NATIVE_DEADLINE ||
        NATIVE_CENTER - 32 - (current_index + 1) < 64)
      fail("native Gray snapshot outside conservative command schedule");
    write_reg(2, 8'h20, NATIVE_REQUEST); write_reg(2, 8'h24, NATIVE_CENTER[31:0]);
    write_reg(2, 8'h28, NATIVE_CENTER[63:32]); write_reg(2, 8'h2c, NATIVE_CENTER[31:0]);
    write_reg(2, 8'h30, NATIVE_CENTER[63:32]);
    if (!source_enable || sample_index > NATIVE_DEADLINE) fail("native AXI command deadline expired");
    native_command_issued = 1; write_reg(2, 8'h34, 1);
    wait(native_irq); read_native_packet(0); native_first_read = 1;
    wait(ack_count == 2); repeat (10) @(negedge clk);
    if (!pilot_enable || delivered_count >= PILOT_COUNT) fail("pilot absent during retained native read");
    read_native_packet(1); write_reg(2, 8'h58, 1);
    repeat (20) @(negedge clk);
    if (native_irq || native.result_available) fail("native release did not retire packet");
    write_reg(2, 8'h68, 1); wait(native.telemetry_valid && !native.telemetry_busy);
    read_reg(2, 8'h70, telemetry_generation);
    if (telemetry_generation != 1) fail("native telemetry not a fresh complete generation");
    for (n = 0; n < 14; n = n + 1)
      expect_reg(2, 8'h84 + 4*n, (n == 0 || n == 1 || n == 10) ? 1 : 0);
    expect_reg(2, 8'h70, telemetry_generation);
    expect_reg(2, 8'hbc, 1); expect_reg(2, 8'hc0, 0);
    expect_reg(2, 8'hc4, 1); expect_reg(2, 8'hc8, 1);
    expect_reg(2, 8'hcc, 0); expect_reg(2, 8'hd0, 0); expect_reg(2, 8'hd4, 0);
    expect_reg(2, 8'hd8, 1); expect_reg(2, 8'hdc, 0); expect_reg(2, 8'he0, 1);
    native_done = 1;
  endtask

  task automatic verify_native_terminal;
    native_healthy();
    $display("BANK_NATIVE_DIAGNOSTIC done=%0d admissions=%0d capture_words=%0d public_reads=%0d retained_stop=%0d capture_fft=%0d compute_coarse_pilot=%0d capture_first_ns=%0.3f capture_last_ns=%0.3f first_fft_input_ns=%0.3f first_fft_source_index=%0d",
      native_done, native_admissions, native_capture_words, native_packet_reads, native_retained_at_stop,
      native_capture_fft_overlap, native_compute_overlap, native_capture_first_ns, native_capture_last_ns,
      first_fft_input_ns, first_fft_source_index);
    if (!native_done || native_admissions != 1 || native_capture_words != 130 ||
        native_packet_reads != 52 || native_retained_at_stop != 1 ||
        native_capture_fft_overlap < 1 || native_compute_overlap < 1)
      fail("native concurrent smoke inventory or positive overlap missing");
    $display("BANK_NATIVE_OVERLAP capture_fft_fast_cycles=%0d compute_coarse_pilot_accepts=%0d",
      native_capture_fft_overlap, native_compute_overlap);
    $display("BANK_NATIVE_EXACT_PASS packets=1 public_reads=52 capture_words=130 taps=66 qualified_lags=61 retained_across_stop=1 injection=0 timestamp_equals_index=1");
    $display("BANK_NATIVE_PAIRED_PASS source_msps=15 fast_mhz=%0d anchor=%0d source_words=4096 scores=894 map_words=447 pilot_bytes=2048 STATIC_ANCHOR_NOT_CAUSAL_NO_RF_PHYSICAL", FAST_MHZ, NATIVE_OFFSET);
  endtask
`undef BN_BANK
`undef BN_RAW
`undef BN_SCHED
