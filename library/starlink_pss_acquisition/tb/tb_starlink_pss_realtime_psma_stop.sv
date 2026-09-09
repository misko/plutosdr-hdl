`timescale 1ns/1ps

// Actual shared realtime XFFT, score/phase-map pipeline and synchronous PSMA.
// Reduced 447x2 geometry only. The independently driven source is NOT a PIL1
// capture, canonical-tap proof, production map, RF signal or routed timing.
module tb_starlink_pss_realtime_psma_stop;
  localparam integer SAMPLE_COUNT = 1406, BINS = 447, TILE_SCORES = 894;
  localparam integer FIXTURE_SCORES = 1341;
  localparam [63:0] FIRST = 64'h00000001fffffff0;
  reg clk = 0, fft_clk = 0, resetn = 0;
  always #5 clk = !clk;
  initial begin #1.3; forever #2.5 fft_clk = !fft_clk; end
  reg source_running = 0, sample_valid = 0;
  wire sample_gap = 1'b0;
  reg signed [15:0] sample_i = 0, sample_q = 0;
  reg [63:0] sample_index = 0;
  reg [31:0] samples [0:SAMPLE_COUNT-1];
  reg [7:0] scores [0:FIXTURE_SCORES-1];
  integer source_count = 0, source_phase = 0, checked_scores = 0, cycles = 0;
  integer stop_source_count = -1, stop_score_count = -1;
  integer acceptance_edges = 0, ack_edges = 0, map_words = 0;
  reg expected_fault = 0, third_started = 0, third_inverse_returned = 0;
  reg third_in_flight_at_ack = 0, prior_enable = 0, prior_fence = 0;
  reg [31:0] prior_ticket = 0;
  wire acquisition_enable, acquisition_flush, irq;
  wire [1:0] map_ready_mask;
  wire [31:0] map_generation_0, map_generation_1;
  wire [63:0] map_start_index_0, map_start_index_1;
  wire map_read_request, map_read_bank, map_read_valid, map_read_error;
  wire [8:0] map_read_index;
  wire [15:0] map_read_data;
  wire map_release, map_release_bank;
  wire score_valid, score_denominator_zero, detector_fault;
  wire [7:0] score_value;
  wire [63:0] score_start_index;
  wire [8:0] score_phase;
  wire scheduler_gap_pulse, scheduler_index_error_pulse, scheduler_overflow_pulse;
  wire forward_fft_fault, kernel_join_fault, product_overflow_fault, inverse_fft_fault;
  wire forward_exponent_fault, candidate_path_fault;
  wire [9:0] candidate_fifo_stored_count, candidate_fifo_maximum_stored_count;
  wire [31:0] accepted_score_count, discarded_score_count, discontinuity_abort_count;
  wire [31:0] map_publish_count, map_overrun_count, score_protocol_error_count;
  wire [31:0] map_arithmetic_overflow_count, map_read_error_count, map_release_error_count;
  wire map_counter_fault;
  wire [31:0] detector_health_flags, scheduler_gap_count, scheduler_index_error_count;
  wire [31:0] scheduler_overflow_count, detector_fault_count;
  wire [31:0] score_phase_index_discontinuity_count, score_denominator_zero_count;
  wire ingress_overflow_sticky = 0;
  wire [31:0] ingress_dropped_sample_count = 0;
  wire [15:0] ingress_fifo_level = 0, ingress_maximum_fifo_level = 0;
  wire [63:0] ddc_accepted_sample_count = 0, ddc_emitted_sample_count = 0;
  wire [31:0] ddc_discontinuity_count = 0, ddc_saturation_event_count = 0;
  wire stop_request, stop_ready, stop_pending, stop_ack, stop_done, stop_complete;
  wire stop_failed, stop_has_map;
  wire [5:0] stop_failure_reason;
  wire [31:0] stop_generation;
  wire [63:0] stop_start_index, stop_end_index;
  reg s_axi_awvalid = 0, s_axi_wvalid = 0, s_axi_bready = 0;
  reg [7:0] s_axi_awaddr = 0, s_axi_araddr = 0;
  reg [31:0] s_axi_wdata = 0;
  reg [3:0] s_axi_wstrb = 0;
  wire s_axi_awready, s_axi_wready, s_axi_bvalid;
  wire [1:0] s_axi_bresp, s_axi_rresp;
  reg s_axi_arvalid = 0, s_axi_rready = 0;
  wire s_axi_arready, s_axi_rvalid;
  wire [31:0] s_axi_rdata;

  starlink_pss_iq_to_phase_map #(
    .USE_SHARED_XFFT(1), .USE_REALTIME_XFFT(1), .ENABLE_BOUNDARY_STOP(1),
    .PHASE_BINS(BINS), .PHASE_INDEX_WIDTH(9), .TILE_FRAMES(2), .TILE_FRAME_WIDTH(1),
    .MAP_SEGMENT_ADDRESS_WIDTH(9), .MAP_SEGMENT_COUNT(1), .MAP_SEGMENT_INDEX_WIDTH(1)
  ) dut (.fft_resetn(resetn), .enable(acquisition_enable), .flush(acquisition_flush), .*);
  axi_starlink_pss_phase_map_sync #(
    .PHASE_BINS(BINS), .PHASE_INDEX_WIDTH(9), .TILE_FRAMES(2),
    .INPUT_RATE_MSPS(15), .USE_SHARED_XFFT(1), .ENABLE_BOUNDARY_STOP(1),
    .HEALTH_COUNTERS_FROM_FLAGS(1), .MAP_COUNTERS_FROM_FLAG(1)
  ) control (.map_clk(clk), .map_reset(!resetn), .s_axi_aclk(clk),
             .s_axi_aresetn(resetn), .s_axi_awprot(3'd0), .s_axi_arprot(3'd0), .*);

  task automatic fail(input string message);
    $display("REALTIME_PSMA_STOP_FAIL %s cycle=%0d source=%0d scores=%0d accepted=%0d ready=%b health=%08h abort=%0d",
             message, cycles, source_count, checked_scores, accepted_score_count,
             map_ready_mask, detector_health_flags, discontinuity_abort_count);
    $fatal(1);
  endtask
  task automatic axi_write(input [7:0] address, input [31:0] value);
    integer timeout;
    @(negedge clk);
    s_axi_awaddr = address; s_axi_wdata = value; s_axi_wstrb = 4'hf;
    s_axi_awvalid = 1; s_axi_wvalid = 1; s_axi_bready = 1;
    timeout = 0;
    while (!(s_axi_awready && s_axi_wready) && timeout < 100) begin
      @(posedge clk); timeout = timeout + 1;
    end
    if (timeout == 100) fail("AXI write address/data timeout");
    @(negedge clk); s_axi_awvalid = 0; s_axi_wvalid = 0;
    timeout = 0;
    while (!s_axi_bvalid && timeout < 100) begin @(posedge clk); timeout = timeout + 1; end
    if (timeout == 100 || s_axi_bresp != 0) fail("AXI write response failure");
    @(negedge clk); s_axi_bready = 0;
  endtask
  task automatic axi_read(input [7:0] address, output [31:0] value);
    integer timeout;
    @(negedge clk); s_axi_araddr = address; s_axi_arvalid = 1; s_axi_rready = 1;
    timeout = 0;
    while (!s_axi_arready && timeout < 100) begin @(posedge clk); timeout = timeout + 1; end
    if (timeout == 100) fail("AXI read address timeout");
    @(negedge clk); s_axi_arvalid = 0;
    timeout = 0;
    while (!s_axi_rvalid && timeout < 100) begin @(posedge clk); timeout = timeout + 1; end
    if (timeout == 100 || s_axi_rresp != 0) fail("AXI read response failure");
    value = s_axi_rdata;
    @(negedge clk); s_axi_rready = 0;
  endtask
  task automatic expect_register(input [7:0] address, input [31:0] expected);
    reg [31:0] value;
    axi_read(address, value);
    if (value !== expected) begin
      $display("REALTIME_PSMA_STOP_REGISTER address=%02h got=%08h expected=%08h", address, value, expected);
      fail("register mismatch");
    end
  endtask
  task automatic expect_word(input integer index, input [31:0] expected);
    axi_write(8'hfc, index); expect_register(8'hfc, expected);
  endtask
  task automatic terminal_tuple(input [31:0] flags);
    expect_word(0, 32'h50535354); expect_word(1, 32'h1000c);
    expect_word(2, flags); expect_word(3, 1); expect_word(4, 1); expect_word(5, 1);
    expect_word(6, FIRST[31:0]); expect_word(7, FIRST[63:32]);
    expect_word(8, 32'h36e); expect_word(9, 2);
  endtask
  task automatic healthy;
    if (detector_fault || scheduler_gap_pulse || scheduler_index_error_pulse ||
        scheduler_overflow_pulse || forward_fft_fault || kernel_join_fault ||
        product_overflow_fault || inverse_fft_fault || forward_exponent_fault ||
        candidate_path_fault || detector_health_flags || scheduler_gap_count ||
        scheduler_index_error_count || scheduler_overflow_count || detector_fault_count ||
        score_phase_index_discontinuity_count || score_denominator_zero_count ||
        discarded_score_count || discontinuity_abort_count || map_overrun_count ||
        score_protocol_error_count || map_arithmetic_overflow_count || map_read_error_count ||
        map_release_error_count || control.bridge_read_error_count ||
        control.bridge_release_error_count || control.snapshot_request_overrun_count)
      fail("unexpected live or persistent pipeline/map/bridge health error");
    if (acquisition_flush) fail("boundary stop issued a legacy global flush");
  endtask

  // Independent 15/100 source cadence continues while coarse enable is low.
  // Only the first 1406 samples belong to the frozen numeric fixture; zeros
  // afterwards are unqualified continuing source stimuli, never oracle data.
  always @(negedge clk) begin
    sample_valid = 0;
    if (!resetn) begin source_count = 0; source_phase = 0; end
    else if (source_running) begin
      source_phase = source_phase + 15;
      if (source_phase >= 100) begin
        source_phase = source_phase - 100;
        {sample_q, sample_i} = source_count < SAMPLE_COUNT ? samples[source_count] : 32'd0;
        sample_index = FIRST + source_count;
        sample_valid = 1;
        source_count = source_count + 1;
      end
    end
  end
  always @(posedge clk) begin
    cycles = cycles + 1;
    if (cycles > 120000) fail("bounded simulation watchdog");
    if (!resetn) begin
      checked_scores = 0; third_started = 0; third_inverse_returned = 0;
      third_in_flight_at_ack = 0; prior_enable = 0; prior_ticket = 0;
      acceptance_edges = 0; ack_edges = 0;
    end else begin
      if (!expected_fault) healthy();
      if (score_valid && !expected_fault) begin
        if (checked_scores >= TILE_SCORES || score_value !== scores[checked_scores] ||
            score_start_index !== FIRST + checked_scores ||
            score_phase !== checked_scores % BINS || score_denominator_zero)
          fail("exact frozen score/index/phase/denominator mismatch or post-fence score");
        checked_scores = checked_scores + 1;
      end
      if (dut.shared_transform.iq_to_score.shared_input_accept &&
          !dut.shared_transform.iq_to_score.choose_inverse &&
          dut.shared_transform.iq_to_score.scheduler_fft_position == 0 &&
          dut.shared_transform.iq_to_score.scheduler_fft_block_start == FIRST + TILE_SCORES)
        third_started = 1;
      if (dut.shared_transform.iq_to_score.inverse_output_accept &&
          dut.shared_transform.iq_to_score.inverse_output_last &&
          dut.shared_transform.iq_to_score.inverse_output_block_start == FIRST + TILE_SCORES)
        third_inverse_returned = 1;
      if (stop_ack) begin
        ack_edges = ack_edges + 1;
        stop_source_count = source_count; stop_score_count = checked_scores;
        third_in_flight_at_ack = third_started && !third_inverse_returned;
        if (!expected_fault && (!third_in_flight_at_ack || !acquisition_enable ||
            !stop_done || !stop_complete || stop_failed || !map_ready_mask[0]))
          fail("missing actual third-block work or publication/ACK ordering witness");
        $display("REALTIME_PSMA_STOP_ACK negative=%0d third_started=%0d third_inverse_returned=%0d service_state=%0d forward_busy=%0d inverse_busy=%0d samples=%0d scores=%0d",
          expected_fault, third_started, third_inverse_returned,
          dut.shared_transform.iq_to_score.realtime_transform.transform_service.state,
          dut.shared_transform.iq_to_score.forward_busy,
          dut.shared_transform.iq_to_score.inverse_busy, source_count, checked_scores);
      end
      if (!expected_fault && prior_enable && !acquisition_enable && !control.stop_terminal_valid)
        fail("coarse disabled before a terminal boundary receipt");
      prior_enable = acquisition_enable;
      prior_fence = dut.phase_map.stop_accept_now;
      prior_ticket = control.stop_accepted_ticket;
      #1;
      if (control.stop_accepted_ticket != prior_ticket) begin
        if (!prior_fence || !stop_pending) fail("ticket acceptance preceded actual core fence");
        acceptance_edges = acceptance_edges + 1;
      end
    end
  end

  task automatic boot;
    @(negedge clk); source_running = 0; resetn = 0;
    repeat (8) @(negedge clk);
    resetn = 1;
    repeat (BINS + 20) @(negedge clk);
    axi_write(8'h14, 1);
    repeat (20) @(negedge clk);
    source_running = 1;
  endtask
  integer p, source_before, accepted_before_fault;
  reg [31:0] value;
  initial begin
    $readmemh("samples_ci16.mem", samples);
    $readmemh("scores_u8.mem", scores);
    boot();
    expect_register(8'h04, 32'h10006); expect_register(8'h08, BINS);
    expect_register(8'h0c, 32'h21002); expect_register(8'h10, 32'h33f);
    wait(accepted_score_count >= 200);
    axi_write(8'hf8, 1);
    expect_register(8'hf8, 1); expect_word(2, 32'h21);
    wait(control.stop_terminal_valid);
    @(negedge clk);
    terminal_tuple(32'h16); expect_word(10, 0);
    if (acceptance_edges != 1 || ack_edges != 1 || checked_scores != TILE_SCORES ||
        stop_score_count != TILE_SCORES || !third_in_flight_at_ack ||
        accepted_score_count != TILE_SCORES || map_publish_count != 1 ||
        map_ready_mask != 1 || map_generation_0 != 1 || map_generation_1 != 0 ||
        map_start_index_0 != FIRST || !irq || acquisition_enable)
      fail("healthy terminal map/fence count mismatch");
    source_before = source_count;
    axi_write(8'h1c, 0); axi_write(8'h20, 0);
    for (p = 0; p < BINS; p = p + 1) begin
      expect_register(8'h24, {24'd0, scores[p]} + {24'd0, scores[p + BINS]});
      map_words = map_words + 1;
    end
    axi_write(8'h28, 1);
    repeat (BINS + 3000) @(negedge clk);
    if (map_ready_mask || irq || map_publish_count != 1 || accepted_score_count != TILE_SCORES ||
        source_count < source_before + 500 || source_count < SAMPLE_COUNT ||
        dut.shared_transform.iq_to_score.pipeline_active)
      fail("post-stop tail created work, lost source continuation, or failed local shutdown");
    terminal_tuple(32'h16); expect_word(10, 0);
    axi_write(8'h30, 1); repeat (5) @(negedge clk);
    expect_register(8'h58, TILE_SCORES); expect_register(8'h64, 1);
    expect_register(8'h88, 0); healthy();
    $display("REALTIME_PSMA_STOP_HEALTHY_PASS exact_scores=894 exact_map_words=447 actual_third_block_pending=1 source_continues=1 coarse_flush=0 tail_health_clean=1 reduced_geometry_only=1");

    // A real invalid bridge release AFTER the healthy terminal must change
    // health, never the terminal map tuple; no vendor event on a reset core.
    expected_fault = 1;
    axi_write(8'h28, 1);
    terminal_tuple(32'h1e);
    axi_write(8'hfc, 10); axi_read(8'hfc, value);
    if (!value[2] || control.bridge_release_error_count != 1)
      fail("real post-terminal invalid release did not retain late bridge fault");
    $display("REALTIME_PSMA_STOP_LATE_BRIDGE_PASS actual_invalid_release=1 stable_terminal_tuple=1 failed_receipt=1");

    // Separate reset/replay: inject a real vendor cause while stop is pending
    // and the service reset epoch is LIVE. Never call injection on a reset
    // vendor instance evidence of detecting a physical late FFT event.
    boot(); expected_fault = 0;
    wait(accepted_score_count >= 200); axi_write(8'hf8, 1);
    wait(accepted_score_count >= 800);
    wait(dut.shared_transform.iq_to_score.realtime_transform.transform_service.core_aresetn &&
         dut.shared_transform.iq_to_score.realtime_transform.transform_service.engine_input_enable);
    @(negedge fft_clk);
    if (!stop_pending || !acquisition_enable ||
        !dut.shared_transform.iq_to_score.realtime_transform.transform_service.fast_running ||
        !dut.shared_transform.iq_to_score.realtime_transform.transform_service.core_aresetn ||
        accepted_score_count >= TILE_SCORES)
      fail("vendor-fault injection lacks a live pending-stop service epoch");
    expected_fault = 1; accepted_before_fault = accepted_score_count;
    force dut.shared_transform.iq_to_score.realtime_transform.transform_service.event_last_missing = 1'b1;
    repeat (4) @(negedge fft_clk);
    release dut.shared_transform.iq_to_score.realtime_transform.transform_service.event_last_missing;
    wait(control.stop_terminal_valid);
    repeat (100) @(negedge clk);
    expect_word(2, 32'ha); expect_word(3, 1); expect_word(4, 1); expect_word(5, 0);
    expect_word(6, 0); expect_word(7, 0); expect_word(8, 0); expect_word(9, 0);
    axi_write(8'hfc, 10); axi_read(8'hfc, value);
    if (!value[0] || !detector_health_flags[14] || map_publish_count || map_ready_mask ||
        acquisition_enable || discontinuity_abort_count != 1 ||
        accepted_score_count < accepted_before_fault || accepted_score_count >= TILE_SCORES)
      fail("live vendor late-pending fault was forgiven or published a partial map");
    $display("REALTIME_PSMA_STOP_LIVE_FAULT_PASS pending_stop=1 vendor_event_in_live_epoch=1 partial_abort=1 no_partial_publication=1 service_health_bit=14");
    $display("REALTIME_PSMA_STOP_PASS healthy_maps=1 exact_map_words=447 fault_cases=2 source_mhz=15 slow_mhz=100 fft_mhz=200 NO_PILOT_DMA_PRODUCTION_CAPACITY_OR_PHYSICAL_CLAIM");
    $finish;
  end
endmodule
