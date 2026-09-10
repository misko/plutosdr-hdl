// Read-only internal witnesses, public coefficient/command/result transactions.
`define N60_CORE native.i_core
`define N60_RAW native.i_core.i_raw_tracking_core
`define N60_SCHED native.i_core.i_raw_tracking_core.i_candidate_scheduler
  localparam [63:0] NATIVE_CENTER = 64'd34359740384;
  localparam [63:0] NATIVE_CAPTURE_FIRST = 64'd34359740256;
  localparam [31:0] NATIVE_REQUEST = 32'h60000520, NATIVE_GENERATION = 32'h60000001;
  wire native_irq, native_injected;
  reg [31:0] native_coefficients [0:263], native_packet [0:25], native_capture [0:519];
  reg [31:0] native_raw_lag [0:256]; // Frozen signed32 memory, actual signed9 wire.
  reg [63:0] native_raw_index [0:256];
  reg [47:0] native_raw_real [0:256], native_raw_imag [0:256];
  reg [47:0] native_raw_ex [0:256], native_raw_eh [0:256];
  reg [95:0] native_raw_power [0:256];
  reg [11:0] native_raw_saturation [0:256]; // Validate high3 before wire9 comparison.
  reg native_raw_qualified [0:256];
  integer native_admissions = 0, native_capture_count = 0, native_raw_count = 0;
  integer native_qualified_count = 0, native_packet_reads = 0, native_readout_transactions = 0;
  integer native_capture_end_cycle = -1, native_publish_cycle = -1, native_release_cycle = -1;
  integer native_drain_cycle = -1, native_trigger_cycle = -1, native_raw_at_publish = -1;
  integer native_raw_after_publish = 0, native_raw_fd, native_capture_fd;
  integer native_hold_cycles = 0, native_maximum_hold = 0, native_hold_fd;
  reg native_configured = 0, native_command_issued = 0, native_released = 0;
  reg [95:0] native_square_re, native_square_im;
  reg [466:0] native_held_payload;
  wire [466:0] native_raw_payload = {`N60_CORE.raw_result_request_id,
      `N60_CORE.raw_result_center_index, `N60_CORE.raw_result_center_timestamp,
      `N60_CORE.raw_result_coefficient_generation, `N60_CORE.raw_result_lag,
      `N60_CORE.raw_result_timestamp, `N60_CORE.raw_result_c_re, `N60_CORE.raw_result_c_im,
      `N60_CORE.raw_result_ex, `N60_CORE.raw_result_eh,
      `N60_CORE.raw_result_saturation_events, `N60_CORE.raw_result_in_track_aperture};
  wire native_engine_idle = (`N60_RAW.correlator_busy === 1'b0) &&
      (`N60_CORE.g_dsp_exact_reducer.i_exact_reducer.state === 4'd0) &&
      (`N60_CORE.reduced_result_valid === 1'b0) &&
      (`N60_RAW.i_capture_bridge.engine_state === 3'd0) &&
      (`N60_RAW.i_capture_bridge.descriptor_read_valid === 1'b0) &&
      (`N60_RAW.bridge_engine_sample_valid === 1'b0) &&
      (`N60_RAW.bridge_engine_job_start === 1'b0) &&
      (`N60_RAW.bridge_engine_job_done === 1'b0) &&
      (`N60_CORE.raw_result_valid === 1'b0) && (native.capture_active === 1'b0) &&
      (`N60_SCHED.o_capture_valid === 1'b0);
  axi_starlink_pss_tracker #(.RATE_MSPS(60), .ENABLE_INJECTION(0), .USE_DSP_REDUCER(1)) native (
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
      fail("native60 health not known zero");
    if (native_configured && (native.active_coefficient_valid !== 1'b1 ||
        native.active_coefficient_generation !== NATIVE_GENERATION ||
        native.active_coefficient_energy !== 48'd1073758594))
      fail("native60 configured coefficient identity changed");
  endtask
  task automatic native_quiet;
    native_healthy();
    if (native_engine_idle !== 1'b1 || {native_irq, native.result_available,
        `N60_SCHED.command_handshake, source_enable, sample_strobe} !== 0 ||
        native_raw_count != 257 || native_qualified_count != 241 || native_admissions != 1)
      fail("native60 stale work/result/command after release and full drain");
  endtask
  always @(posedge sample_clk) if (resetn) begin
    if (native_configured && (^{`N60_SCHED.command_handshake, `N60_SCHED.command_read_valid,
        `N60_SCHED.command_read_ready, `N60_SCHED.o_capture_valid, `N60_SCHED.o_capture_start,
        `N60_SCHED.o_capture_done, native.capture_active}) === 1'bx)
      fail("native60 unknown sample-domain command/capture protocol flag");
    if (`N60_SCHED.command_handshake === 1'b1) begin
      if (native_command_issued !== 1'b1 || {source_enable, sample_strobe} !== 2'b11 ||
          `N60_SCHED.command_late !== 1'b0 ||
          `N60_SCHED.command_center_index !== NATIVE_CENTER ||
          `N60_SCHED.command_center_timestamp !== NATIVE_CENTER ||
          `N60_SCHED.command_request_id !== NATIVE_REQUEST ||
          sample_index < 64'd34359738560 || sample_index > 64'd34359738720 ||
          $signed(`N60_SCHED.command_lead) < 1535 || $signed(`N60_SCHED.command_lead) > 1695 ||
          `N60_SCHED.command_lead !== NATIVE_CAPTURE_FIRST - sample_index - 1 ||
          native_trigger_cycle < 0 || cycles - native_trigger_cycle > 256 || native_admissions != 0)
        fail("native60 actual handshake identity/coordinate/lead/control deadline");
      native_admissions = native_admissions + 1;
      $display("NATIVE60_ADMISSION index=%0d center=%0d capture_first=%0d lead=%0d trigger_cycle=%0d handshake_cycle=%0d request=%08x generation=%08x",
        sample_index, NATIVE_CENTER, NATIVE_CAPTURE_FIRST, $signed(`N60_SCHED.command_lead),
        native_trigger_cycle, cycles, NATIVE_REQUEST, NATIVE_GENERATION);
    end
    #0.001;
    if (native_configured && (^{`N60_SCHED.o_capture_valid, `N60_SCHED.o_capture_start,
        `N60_SCHED.o_capture_done, native.capture_active}) === 1'bx)
      fail("native60 unknown settled capture protocol flag");
    if (`N60_SCHED.o_capture_valid === 1'b1) begin
      if (native_capture_count >= 520 || native_admissions != 1 ||
          `N60_SCHED.o_capture_slot !== native_capture_count ||
          `N60_SCHED.o_capture_sample_index !== NATIVE_CAPTURE_FIRST + native_capture_count ||
          `N60_SCHED.o_capture_sample_timestamp !== NATIVE_CAPTURE_FIRST + native_capture_count ||
          {`N60_SCHED.o_capture_sample_q, `N60_SCHED.o_capture_sample_i} !== native_capture[native_capture_count])
        fail($sformatf("capture slot=%0d actual_index=%0d expected_index=%0d actual_iq=%08x expected_iq=%08x",
          native_capture_count, `N60_SCHED.o_capture_sample_index, NATIVE_CAPTURE_FIRST+native_capture_count,
          {`N60_SCHED.o_capture_sample_q, `N60_SCHED.o_capture_sample_i}, native_capture[native_capture_count]));
      $fdisplay(native_capture_fd, "%0d %016x %016x %08x", native_capture_count,
        `N60_SCHED.o_capture_sample_index, `N60_SCHED.o_capture_sample_timestamp,
        {`N60_SCHED.o_capture_sample_q, `N60_SCHED.o_capture_sample_i});
      native_capture_count = native_capture_count + 1;
      if (native_capture_count == 520) native_capture_end_cycle = cycles;
    end
  end
  always @(posedge clk) if (resetn) begin
    native_healthy();
    if (native_configured && (^{`N60_CORE.raw_result_valid, `N60_CORE.raw_result_ready,
        native_irq, native.result_available, `N60_RAW.correlator_busy,
        `N60_RAW.bridge_engine_sample_valid, `N60_RAW.bridge_engine_job_start,
        `N60_RAW.bridge_engine_job_done, `N60_CORE.reduced_result_valid}) === 1'bx)
      fail("native60 unknown control-domain raw/engine protocol flag");
    if (native_hold_cycles > 0 && (`N60_CORE.raw_result_valid !== 1'b1 ||
        native_raw_payload !== native_held_payload))
      fail("native60 held raw tuple dropped/changed before handshake");
    if (`N60_CORE.raw_result_valid === 1'b1 && `N60_CORE.raw_result_ready === 1'b0) begin
      native_hold_cycles = native_hold_cycles + 1;
      native_held_payload = native_raw_payload;
      if (native_hold_cycles > native_maximum_hold) native_maximum_hold = native_hold_cycles;
      if (native_hold_cycles > 16) fail("native60 per-tuple reducer hold exceeds16-cycle allowance");
    end
    if (`N60_CORE.raw_result_valid === 1'b1 && `N60_CORE.raw_result_ready === 1'b1) begin
      if (native_raw_count >= 257 || `N60_CORE.raw_result_request_id !== NATIVE_REQUEST ||
          `N60_CORE.raw_result_center_index !== NATIVE_CENTER ||
          `N60_CORE.raw_result_center_timestamp !== NATIVE_CENTER ||
          `N60_CORE.raw_result_coefficient_generation !== NATIVE_GENERATION ||
          `N60_CORE.raw_result_lag !== native_raw_lag[native_raw_count][8:0] ||
          `N60_CORE.raw_result_timestamp !== native_raw_index[native_raw_count] ||
          `N60_CORE.raw_result_c_re !== native_raw_real[native_raw_count] ||
          `N60_CORE.raw_result_c_im !== native_raw_imag[native_raw_count] ||
          `N60_CORE.raw_result_ex !== native_raw_ex[native_raw_count] ||
          `N60_CORE.raw_result_eh !== native_raw_eh[native_raw_count] ||
          `N60_CORE.raw_result_saturation_events !== native_raw_saturation[native_raw_count][8:0] ||
          `N60_CORE.raw_result_in_track_aperture !== native_raw_qualified[native_raw_count])
        fail($sformatf("native60 exact raw tuple mismatch row=%0d lag=%0d index=%0d",
          native_raw_count, $signed(`N60_CORE.raw_result_lag), `N60_CORE.raw_result_timestamp));
      native_square_re = $signed(`N60_CORE.raw_result_c_re) * $signed(`N60_CORE.raw_result_c_re);
      native_square_im = $signed(`N60_CORE.raw_result_c_im) * $signed(`N60_CORE.raw_result_c_im);
      if (native_square_re + native_square_im !== native_raw_power[native_raw_count])
        fail("native60 exact raw power mismatch");
      $fdisplay(native_raw_fd, "%0d %016x %012x %012x %012x %012x %024x %03x %0d",
        $signed(`N60_CORE.raw_result_lag), `N60_CORE.raw_result_timestamp,
        `N60_CORE.raw_result_c_re, `N60_CORE.raw_result_c_im, `N60_CORE.raw_result_ex,
        `N60_CORE.raw_result_eh, native_square_re + native_square_im,
        `N60_CORE.raw_result_saturation_events, `N60_CORE.raw_result_in_track_aperture);
      $fdisplay(native_hold_fd, "%0d %0d", $signed(`N60_CORE.raw_result_lag), native_hold_cycles);
      native_hold_cycles = 0;
      native_raw_count = native_raw_count + 1;
      if (`N60_CORE.raw_result_in_track_aperture === 1'b1) native_qualified_count = native_qualified_count + 1;
      if (native_publish_cycle >= 0) native_raw_after_publish = native_raw_after_publish + 1;
    end
    if (native_irq === 1'b1 && native_publish_cycle < 0) begin
      native_publish_cycle = cycles; native_raw_at_publish = native_raw_count;
      if (native_capture_end_cycle < 0 || cycles - native_capture_end_cycle > 84000 ||
          native_qualified_count != 241 || native_raw_count < 249 || native_raw_count > 257)
        fail("native60 publication bound/qualified inventory");
    end
    if (native_trigger_cycle >= 0 && native_admissions == 0 && cycles-native_trigger_cycle > 256)
      fail("native60 actual handshake timeout");
    if (native_capture_end_cycle >= 0) begin
      if ((native_publish_cycle < 0 || native_drain_cycle < 0) && cycles-native_capture_end_cycle > 84000)
        fail("native60 publication or complete257 drain exceeded bound");
      if (!native_released && cycles-native_capture_end_cycle > 88000)
        fail("native60 read/release exceeded post-capture bound");
    end
    #0.001;
    if (native_raw_count == 257 && native_engine_idle === 1'b1 && native_drain_cycle < 0) begin
      native_drain_cycle = cycles;
      if (native_capture_end_cycle < 0 || cycles-native_capture_end_cycle > 84000)
        fail("native60 full drain/idle bound");
      $display("NATIVE60_DRAIN cycle=%0d raw=257 qualified=%0d engine_idle=1 bridge_idle=1", cycles, native_qualified_count);
    end
  end
  task automatic configure_native;
    integer tap, timeout;
    reg [31:0] readback;
    $readmemh("native_coefficients_q15.mem", native_coefficients);
    $readmemh("native_expected_packet.mem", native_packet);
    $readmemh("native_capture_ci16.mem", native_capture);
    $readmemh("native_raw_lags_s32.mem", native_raw_lag);
    $readmemh("native_raw_start_u64.mem", native_raw_index);
    $readmemh("native_raw_real_s48.mem", native_raw_real); $readmemh("native_raw_imag_s48.mem", native_raw_imag);
    $readmemh("native_raw_ex_u48.mem", native_raw_ex); $readmemh("native_raw_eh_u48.mem", native_raw_eh);
    $readmemh("native_raw_power_u96.mem", native_raw_power);
    $readmemh("native_raw_saturation_u12.mem", native_raw_saturation);
    $readmemh("native_raw_qualified_u1.mem", native_raw_qualified);
    for (integer n = 0; n < 257; n = n + 1) begin
      if (native_raw_lag[n] !== n-128 ||
          native_raw_lag[n] !== {{23{native_raw_lag[n][8]}}, native_raw_lag[n][8:0]} ||
          native_raw_saturation[n][11:9] !== 3'b0)
        fail("frozen signed32-to-wire9 lag or saturation padding invalid");
    end
    native_raw_fd = $fopen("native60_actual_raw_tuples.txt", "w");
    native_capture_fd = $fopen("native60_actual_capture.txt", "w");
    native_hold_fd = $fopen("native60_actual_holds.txt", "w");
    if (!native_raw_fd || !native_capture_fd || !native_hold_fd) fail("native60 tuple/capture/hold log unavailable");
    expect_reg(2, 8'h00, 32'h50535354); expect_reg(2, 8'h04, 32'h00010003);
    expect_reg(2, 8'h08, 60); expect_reg(2, 8'h0c, 32'h0f8c1108); expect_reg(2, 8'h10, 32'h1d);
    write_reg(2, 8'h44, 1);
    for (tap = 0; tap < 264; tap = tap + 1)
      write_reg(2, 8'h40, {native_coefficients[tap][15:0], native_coefficients[tap][31:16]});
    write_reg(2, 8'h48, NATIVE_GENERATION); write_reg(2, 8'h44, 2);
    timeout = 0; readback = 0;
    while (readback !== NATIVE_GENERATION && timeout < 2000) begin
      read_reg(2, 8'h4c, readback); timeout = timeout + 1;
    end
    if (readback !== NATIVE_GENERATION) fail("native60 coefficient commit timeout");
    expect_reg(2, 8'h60, 1073758594); expect_reg(2, 8'h64, 0);
    native_configured = 1; native_healthy();
    $display("NATIVE60_CONFIG cycle=%0d id=50535354 abi=00010003 rate=60 geometry=0f8c1108 caps=0000001d generation=60000001 eh=1073758594", cycles);
  endtask
  task automatic read_native_packet(input integer pass);
    reg [31:0] actual;
    for (integer word_index = 0; word_index < 26; word_index = word_index + 1) begin
      write_reg(2, 8'h50, word_index); read_reg(2, 8'h54, actual);
      if (actual !== native_packet[word_index])
        fail($sformatf("packet pass=%0d word=%0d actual=%08x expected=%08x", pass, word_index, actual, native_packet[word_index]));
      $display("NATIVE60_PACKET_WORD pass=%0d word=%0d data=%08x", pass, word_index, actual);
      native_packet_reads = native_packet_reads + 1;
    end
  endtask
  task automatic run_native_command;
    reg [63:0] current_index;
    wait(source_enable === 1'b1 && sample_strobe === 1'b1 && sample_index >= 64'd34359738560);
    if (sample_index !== 64'd34359738560) fail("fixed command trigger skipped");
    native_trigger_cycle = cycles;
    read_reg(2, 8'h18, current_index[31:0]); read_reg(2, 8'h1c, current_index[63:32]);
    check_native_snapshot(current_index);
    write_reg(2, 8'h20, NATIVE_REQUEST); write_reg(2, 8'h24, NATIVE_CENTER[31:0]);
    write_reg(2, 8'h28, NATIVE_CENTER[63:32]); write_reg(2, 8'h2c, NATIVE_CENTER[31:0]);
    write_reg(2, 8'h30, NATIVE_CENTER[63:32]);
    native_command_issued = 1; write_reg(2, 8'h34, 1);
    wait(native_irq === 1'b1); @(negedge clk);
    read_native_packet(0);
    repeat (32) begin
      @(negedge clk);
      if ({native_irq, native.result_available} !== 2'b11) fail("native60 result retention lost");
    end
    read_native_packet(1); write_reg(2, 8'h58, 1);
    repeat (24) @(negedge clk);
    if ({native_irq, native.result_available} !== 2'b00) fail("native60 public result release failed");
    native_release_cycle = cycles; native_released = 1;
    if (native_capture_end_cycle < 0 || cycles-native_capture_end_cycle > 88000)
      fail("native60 public release bound");
    $display("NATIVE60_RELEASE cycle=%0d raw=%0d qualified=%0d packet_reads=52 retained_cycles=32 settle_cycles=24 irq=0 available=0",
      cycles, native_raw_count, native_qualified_count);
  endtask
`undef N60_CORE
`undef N60_RAW
`undef N60_SCHED
