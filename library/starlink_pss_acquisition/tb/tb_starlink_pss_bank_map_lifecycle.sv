`timescale 1ns/1fs

// Actual bank-owned XFFT, unchanged numeric fixture, reduced 447x2 map and PSMA.
// Lifecycle fault witnesses only: not RF, paired pilot/fine, production geometry,
// capacity or physical timing qualification. Faults never relax exact-prefix checks.
module tb_starlink_pss_bank_map_lifecycle #(parameter integer FAST_MHZ = 175);
  localparam integer SAMPLE_COUNT = 1406, BINS = 447, TILE_SCORES = 894;
  localparam integer FIXTURE_SCORES = 1341;
  localparam [63:0] FIRST = 64'h00000001fffffff0;
  reg clk = 0, fft_clk = 0, resetn = 0, fft_resetn = 0;
  always #5 clk = !clk;
  initial begin #1.3; forever #(500.0 / FAST_MHZ) fft_clk = !fft_clk; end
  reg source_running = 0, sample_valid = 0;
  wire sample_gap = 1'b0;
  reg signed [15:0] sample_i = 0, sample_q = 0;
  reg [63:0] sample_index = 0;
  reg [31:0] samples [0:SAMPLE_COUNT-1];
  reg [7:0] scores [0:FIXTURE_SCORES-1];
  integer source_count = 0, source_phase = 0, checked_scores = 0, cycles = 0;
  integer epoch = 0, hardware_resets = 0, map_words = 0, case_count = 0;
  integer total_exact_scores = 0, epoch_accepted_origin = 0;
  reg [63:0] source_base = FIRST;
  reg expected_fault = 0, final_accepted = 0;
  real raw_event_ns = -1, local_fault_ns = -1, final_accept_ns = -1, publish_ns = -1;
  reg [1:0] prior_ready = 0;
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
    .USE_BANK_OWNED_XFFT(1),
    .PHASE_BINS(BINS), .PHASE_INDEX_WIDTH(9), .TILE_FRAMES(2), .TILE_FRAME_WIDTH(1),
    .MAP_SEGMENT_ADDRESS_WIDTH(9), .MAP_SEGMENT_COUNT(1), .MAP_SEGMENT_INDEX_WIDTH(1)
  ) dut (.fft_resetn(fft_resetn), .enable(acquisition_enable), .flush(acquisition_flush), .*);
  axi_starlink_pss_phase_map_sync #(
    .PHASE_BINS(BINS), .PHASE_INDEX_WIDTH(9), .TILE_FRAMES(2),
    .INPUT_RATE_MSPS(15), .USE_SHARED_XFFT(1), .ENABLE_BOUNDARY_STOP(1),
    .HEALTH_COUNTERS_FROM_FLAGS(1), .MAP_COUNTERS_FROM_FLAG(1)
  ) control (.map_clk(clk), .map_reset(!resetn), .s_axi_aclk(clk),
             .s_axi_aresetn(resetn), .s_axi_awprot(3'd0), .s_axi_arprot(3'd0), .*);


  wire observed_core_live = dut.bank_transform.iq_to_score.island.core_aresetn;
  wire observed_input_enabled = dut.bank_transform.iq_to_score.island.engine_input_enable;
  wire observed_pipeline_active = dut.bank_transform.iq_to_score.pipeline_active;
  task automatic fail(input string message);
    $display("BANK_MAP_LIFECYCLE_FAIL %s epoch=%0d cycle=%0d source=%0d exact=%0d accepted=%0d ready=%b health=%08h abort=%0d state=%0d",
      message, epoch, cycles, source_count, checked_scores, accepted_score_count,
      map_ready_mask, detector_health_flags, discontinuity_abort_count, dut.phase_map.state);
    $fatal(1, "bank map lifecycle assertion failed");
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
      $display("BANK_MAP_LIFECYCLE_REGISTER address=%02h got=%08h expected=%08h", address, value, expected);
      fail("register mismatch");
    end
  endtask
  task automatic expect_word(input integer index, input [31:0] expected);
    axi_write(8'hfc, index); expect_register(8'hfc, expected);
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


  // The fixture is bounded to three complete overlap blocks. No fourth block or
  // unknown zero tail is needed to make a fault case terminate.
  always @(negedge clk) begin
    sample_valid = 0;
    if (!resetn) begin source_count = 0; source_phase = 0; end
    else if (source_running && source_count < SAMPLE_COUNT) begin
      source_phase = source_phase + 15;
      if (source_phase >= 100) begin
        source_phase = source_phase - 100;
        {sample_q, sample_i} = samples[source_count];
        sample_index = source_base + source_count;
        sample_valid = 1;
        source_count = source_count + 1;
      end
    end
  end
  always @(posedge clk) begin
    cycles = cycles + 1;
    if (cycles > 500000) fail("bounded simulation watchdog");
    if (resetn) begin
      if (!expected_fault) healthy();
      // Check EVERY visible score even in failed epochs: valid prefixes are
      // provisional, not arbitrary; no forced FFT output or forced scores.
      if (score_valid) begin
        if (checked_scores >= FIXTURE_SCORES ||
            score_value !== scores[checked_scores] ||
            score_start_index !== source_base + checked_scores ||
            score_phase !== checked_scores % BINS || score_denominator_zero)
          fail("exact frozen score/index/phase/denominator mismatch");
        checked_scores = checked_scores + 1;
        total_exact_scores = total_exact_scores + 1;
      end
      if (dut.phase_map.state == 2 && dut.phase_map.frame_index == 1 &&
          dut.map_score_valid && dut.map_score_phase == BINS-1 && dut.map_enable) begin
        final_accepted = 1; final_accept_ns = $realtime;
      end
      if (detector_fault && local_fault_ns < 0) local_fault_ns = $realtime;
      if (map_ready_mask != prior_ready && map_ready_mask != 0) publish_ns = $realtime;
      prior_ready = map_ready_mask;
      if (acquisition_flush) fail("lifecycle operation issued global flush");
    end
  end

  task automatic new_source_epoch;
    // Called with the source stopped and coarse disabled, away from its edge.
    @(negedge clk); #1;
    epoch = epoch + 1;
    source_base = FIRST + epoch * 65536;
    source_count = 0; source_phase = 0; checked_scores = 0;
    epoch_accepted_origin = accepted_score_count;
    final_accepted = 0; prior_ready = map_ready_mask;
    raw_event_ns = -1; local_fault_ns = -1; final_accept_ns = -1; publish_ns = -1;
  endtask
  task automatic boot;
    @(negedge clk); #1;
    source_running = 0; resetn = 0; fft_resetn = 0;
    repeat (8) @(negedge clk);
    #1; expected_fault = 0; hardware_resets = hardware_resets + 1;
    checked_scores = 0; resetn = 1; fft_resetn = 1;
    repeat (BINS + 20) @(negedge clk);
    new_source_epoch();
    axi_write(8'h14, 1);
    repeat (20) @(negedge clk);
    #1; source_running = 1;
  endtask
  task automatic request_stop(input [31:0] ticket);
    wait(checked_scores >= 200);
    axi_write(8'hf8, ticket);
    expect_register(8'hf8, ticket);
    if (!stop_pending) fail("stop request not actually pending");
  endtask
  task automatic terminal_tuple(input [31:0] flags, input [31:0] ticket,
                                input [31:0] generation, input [63:0] first);
    reg [63:0] last;
    last = generation == 0 ? 0 : first + TILE_SCORES;
    expect_word(2, flags); expect_word(3, ticket); expect_word(4, ticket);
    expect_word(5, generation);
    expect_word(6, first[31:0]); expect_word(7, first[63:32]);
    expect_word(8, last[31:0]); expect_word(9, last[63:32]);
  endtask
  task automatic read_complete_map(input integer generation, input [63:0] first);
    integer p, bank;
    bank = map_ready_mask[0] ? 0 : 1;
    if (map_ready_mask == 0 || !irq) fail("completed map not retained/readable");
    if (bank == 0 && (map_generation_0 != generation || map_start_index_0 != first))
      fail("bank0 complete map metadata changed");
    if (bank == 1 && (map_generation_1 != generation || map_start_index_1 != first))
      fail("bank1 complete map metadata changed");
    axi_write(8'h1c, bank); axi_write(8'h20, 0);
    for (p = 0; p < BINS; p = p + 1) begin
      expect_register(8'h24, {24'd0, scores[p]} + {24'd0, scores[p+BINS]});
      map_words = map_words + 1;
    end
    axi_write(8'h28, 1);
    repeat (BINS + 20) @(negedge clk);
    if (map_ready_mask || irq || map_read_error_count || map_release_error_count ||
        control.bridge_read_error_count || control.bridge_release_error_count)
      fail("valid completed-map read/release failed");
  endtask
  task automatic healthy_terminal(input [31:0] ticket, input [31:0] generation);
    wait(control.stop_terminal_valid);
    @(negedge clk);
    terminal_tuple(32'h16, ticket, generation, source_base); expect_word(10, 0);
    if (checked_scores != TILE_SCORES ||
        accepted_score_count - epoch_accepted_origin != TILE_SCORES ||
        map_publish_count != generation || acquisition_enable)
      fail("healthy exact terminal count or enable mismatch");
    read_complete_map(generation, source_base);
    repeat (100) @(negedge clk);
    if (observed_pipeline_active) fail("coarse pipeline did not shut down locally");
    healthy();
  endtask
  task automatic inject_vendor_fault;
    @(negedge fft_clk);
    if (!observed_core_live || !acquisition_enable || !stop_pending)
      fail("raw vendor-event injection not in a live pending-stop core epoch");
    expected_fault = 1; raw_event_ns = $realtime;
    force dut.bank_transform.iq_to_score.island.event_last_missing = 1'b1;
    repeat (4) @(negedge fft_clk);
    release dut.bank_transform.iq_to_score.island.event_last_missing;
  endtask
  task automatic fault_terminal(input integer completed, input integer history,
                                input integer service_cause);
    reg [31:0] reason;
    wait(control.stop_terminal_valid);
    repeat (100) @(negedge clk);
    terminal_tuple(32'ha | (completed ? 4 : 0) | (history ? 16 : 0),
                   1, history ? 1 : 0, history ? source_base : 64'd0);
    axi_write(8'hfc, 10); axi_read(8'hfc, reason);
    if (!reason[0] || !detector_health_flags || acquisition_enable ||
        map_publish_count != history || discontinuity_abort_count != (completed ? 0 : 1) ||
        (service_cause && !detector_health_flags[14]))
      fail("fault receipt/health/publication/partial-abort mismatch");
    if (history) read_complete_map(1, source_base);
    else if (map_ready_mask) fail("fault published a partial tile");
    // Map read/release is legal even after fault; it must not rewrite receipt.
    terminal_tuple(32'ha | (completed ? 4 : 0) | (history ? 16 : 0),
                   1, history ? 1 : 0, history ? source_base : 64'd0);
  endtask
  task automatic local_boundary(input integer boundary);
    boot(); request_stop(1);
    if (boundary == 0) begin
      @(negedge clk);
      while (!(dut.phase_map.state == 2 && dut.phase_map.frame_index == 1 &&
               dut.map_score_valid && dut.map_score_phase == BINS-1)) @(negedge clk);
    end else if (boundary == 1) begin
      @(negedge clk);
      while (dut.phase_map.state != 3) @(negedge clk);
    end else begin
      @(negedge clk);
      while (!dut.phase_map.publish_pending) @(negedge clk);
    end
    if (!stop_pending || !acquisition_enable || map_ready_mask)
      fail("local boundary precondition not present");
    // This is an ALREADY VISIBLE slow-domain service fault, not a remote raw
    // event latency test. It does not alter arithmetic or any valid FFT result.
    expected_fault = 1;
    force dut.bank_transform.iq_to_score.detector_fault = 1'b1;
    force dut.bank_transform.iq_to_score.island_fault = 1'b1;
    fault_terminal(boundary != 0, boundary != 0, 1);
    release dut.bank_transform.iq_to_score.detector_fault;
    release dut.bank_transform.iq_to_score.island_fault;
    if (final_accepted != (boundary != 0))
      fail("local boundary final-score acceptance classification mismatch");
    $display("BANK_MAP_LIFECYCLE_CASE local_boundary=%0d completed=%0d exact_scores=%0d current_domain_fault=1 remote_latency_claim=0",
      boundary, boundary != 0, checked_scores);
    case_count = case_count + 1;
  endtask

  integer saved_resets, before_reset_scores;
  reg [31:0] saved_health;
  initial begin
    $readmemh("samples_ci16.mem", samples);
    $readmemh("scores_u8.mem", scores);
    boot(); request_stop(1); healthy_terminal(1, 1);
    saved_resets = hardware_resets;
    @(negedge clk); #1; source_running = 0;
    new_source_epoch();
    axi_write(8'h14, 1);
    expect_word(2, 32'h20); expect_register(8'hf8, 1);
    repeat (20) @(negedge clk); #1; source_running = 1;
    request_stop(2); healthy_terminal(2, 2);
    if (hardware_resets != saved_resets) fail("healthy re-enable used external reset");
    $display("BANK_MAP_LIFECYCLE_CASE healthy_reenable=1 external_reset_between=0 tickets=2 exact_scores=1788 exact_map_words=894");
    case_count = case_count + 1;

    boot();
    wait(accepted_score_count >= 1000);
    request_stop(1);
    // At this later score threshold the finite fixture need not leave the
    // vendor core active. Model current-domain fault visibility explicitly;
    // do not wait for nonexistent fourth-block work or inject on a reset core.
    @(negedge clk);
    if (dut.phase_map.state != 2 || map_ready_mask != 1)
      fail("retained complete map and later partial tile not simultaneous");
    expected_fault = 1;
    force dut.bank_transform.iq_to_score.detector_fault = 1'b1;
    force dut.bank_transform.iq_to_score.island_fault = 1'b1;
    fault_terminal(0, 1, 1);
    release dut.bank_transform.iq_to_score.detector_fault;
    release dut.bank_transform.iq_to_score.island_fault;
    if (checked_scores < 1000 || checked_scores >= FIXTURE_SCORES)
      fail("retained-map fault did not interrupt the later partial tile");
    $display("BANK_MAP_LIFECYCLE_CASE retained_map_partial_fault=1 exact_map_words=447 exact_prefix=%0d current_domain_fault=1 remote_latency_claim=0",
      checked_scores);
    case_count = case_count + 1;

    boot(); request_stop(1);
    wait(checked_scores >= 300);
    @(negedge fft_clk);
    expected_fault = 1; before_reset_scores = accepted_score_count;
    fft_resetn = 0;
    repeat (8) @(negedge fft_clk);
    fft_resetn = 1;
    fault_terminal(0, 0, 0);
    saved_health = detector_health_flags;
    if (!resetn || accepted_score_count < before_reset_scores)
      fail("independent fast reset incorrectly reset slow PSMA evidence");
    repeat (200) @(negedge clk);
    if (detector_health_flags != saved_health || observed_pipeline_active)
      fail("fast reset release erased sticky fault or restarted work");
    $display("BANK_MAP_LIFECYCLE_CASE independent_fft_reset=1 slow_epoch_preserved=1 exact_prefix=%0d sticky_health=%08h", checked_scores, saved_health);
    case_count = case_count + 1;
    boot(); request_stop(1); healthy_terminal(1, 1);
    $display("BANK_MAP_LIFECYCLE_CASE post_fault_epoch_reset_replay=1 exact_scores=894 exact_map_words=447");
    case_count = case_count + 1;

    local_boundary(0);
    local_boundary(1);
    local_boundary(2);

    boot(); request_stop(1);
    @(negedge clk);
    while (!(dut.phase_map.state == 2 && dut.phase_map.frame_index == 1 &&
             dut.map_score_valid && dut.map_score_phase == BINS-1)) @(negedge clk);
    inject_vendor_fault();
    wait(control.stop_terminal_valid);
    // Frozen contract: classify at the actual final score acceptance, not at
    // the remote fault timestamp. Completed healthy work is never undone.
    fault_terminal(final_accepted, final_accepted, 1);
    if (local_fault_ns <= raw_event_ns)
      fail("raw/local CDC timestamp witness is missing or mislabeled");
    $display("BANK_MAP_LIFECYCLE_CASE remote_boundary=1 completed=%0d exact_scores=%0d raw_event_ns=%0.3f local_fault_ns=%0.3f final_accept_ns=%0.3f publish_ns=%0.3f",
      final_accepted, checked_scores, raw_event_ns, local_fault_ns, final_accept_ns, publish_ns);
    case_count = case_count + 1;

    if (case_count != 8) fail("incomplete lifecycle case inventory");
    $display("BANK_MAP_LIFECYCLE_TOTAL exact_scores=%0d exact_map_words=%0d hardware_resets=%0d", total_exact_scores, map_words, hardware_resets);
    $display("BANK_MAP_LIFECYCLE_PASS cases=8 actual_core=1 source_mhz=15 slow_mhz=100 fft_mhz=%0d REDUCED_GEOMETRY_NO_PAIRED_FINE_CAPACITY_OR_RF_CLAIM", FAST_MHZ);
    $finish;
  end
endmodule
