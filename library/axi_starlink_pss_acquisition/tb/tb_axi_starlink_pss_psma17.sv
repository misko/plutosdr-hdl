`timescale 1ns/1ps

// Actual synchronous PSMA + actual map RAM/core, with score/health stimuli.
// No kernel, FFT throughput, pilot capture, or RF qualification is implied.
module tb_axi_starlink_pss_psma17 #(
  parameter integer ENABLE_BOUNDARY_STOP = 1,
  parameter integer USE_SHARED_XFFT = 1,
  parameter integer INPUT_RATE_MSPS = 30,
  parameter integer USE_BANK_OWNED_XFFT = 1,
  parameter integer USE_REALTIME_XFFT = 1,
  parameter integer ENABLE_PILOT_TAP = 1,
  parameter [30:0] COEFFICIENT_ENERGY = 31'd1073744004,
  parameter integer HEALTH_COUNTERS_FROM_FLAGS = 0,
  parameter integer MAP_COUNTERS_FROM_FLAG = 0
);
  localparam integer BINS = 8, FRAMES = 4, TOTAL = BINS * FRAMES;
  localparam [63:0] BASE = 64'h00000001fffffff0;
  reg clk = 0, resetn = 0;
  always #5 clk = !clk;
  reg score_valid = 0, stream_discontinuity = 0, core_gate = 1;
  reg [63:0] score_start_index = 0;
  reg [2:0] score_phase = 0;
  reg [7:0] score_value = 0;
  wire acquisition_enable, acquisition_flush, irq;
  wire core_enable = acquisition_enable && !acquisition_flush && core_gate;
  wire [1:0] map_ready_mask;
  wire [31:0] map_generation_0, map_generation_1;
  wire [63:0] map_start_index_0, map_start_index_1;
  wire map_read_request, map_read_bank, map_read_valid, map_read_error;
  wire [2:0] map_read_index;
  wire [15:0] map_read_data;
  wire map_release, map_release_bank;
  wire [31:0] accepted_score_count, discarded_score_count, discontinuity_abort_count;
  wire [31:0] map_publish_count, map_overrun_count, score_protocol_error_count;
  wire [31:0] map_arithmetic_overflow_count, map_read_error_count, map_release_error_count;
  wire map_counter_fault;
  reg [31:0] independent_map_counts [0:6];
  reg independent_map_summary = 0;
  wire controller_map_counter_fault = MAP_COUNTERS_FROM_FLAG ? map_counter_fault : independent_map_summary;
  wire stop_request, stop_pending, stop_ack, stop_done, stop_complete, stop_failed, stop_has_map;
  wire [5:0] stop_failure_reason;
  wire [31:0] stop_generation;
  wire [63:0] stop_start_index, stop_end_index;
  wire stop_ready = ENABLE_BOUNDARY_STOP && core_enable && !stop_pending && !stop_done;
  reg [31:0] detector_health_flags = 0, ingress_dropped_sample_count = 0;
  reg ingress_overflow_sticky = 0;
  wire [15:0] ingress_fifo_level = 0, ingress_maximum_fifo_level = 0;
  reg [12:0] health_events = 0;
  reg [31:0] independent_counts [0:4];
  wire [31:0] producer_counts [0:4];
  wire [31:0] produced_health_flags;
  wire [31:0] controller_health_flags = detector_health_flags | produced_health_flags;
  wire [31:0] detector_fault_count = producer_counts[0] | independent_counts[0];
  wire [31:0] scheduler_gap_count = producer_counts[1] | independent_counts[1];
  wire [31:0] scheduler_index_error_count = producer_counts[2] | independent_counts[2];
  wire [31:0] scheduler_overflow_count = producer_counts[3] | independent_counts[3];
  wire [31:0] score_phase_index_discontinuity_count = producer_counts[4] | independent_counts[4];
  reg [31:0] score_denominator_zero_count = 0;
  wire [9:0] candidate_fifo_stored_count = 0, candidate_fifo_maximum_stored_count = 0;
  // Mock counters are ONLY for public-register carry/held-response tests.
  // All lifecycle fault cases below select the real, unchanged integer DDC.
  reg mock_counters = 0;
  reg [63:0] mock_accepted = 0, mock_emitted = 0;
  reg ddc_enable = 1, raw_valid = 0, raw_gap = 0;
  reg signed [15:0] raw_i = 0, raw_q = 0;
  reg [63:0] raw_index = 0;
  wire [63:0] real_accepted, real_emitted;
  wire [31:0] ddc_discontinuity_count, ddc_saturation_event_count;
  wire [63:0] ddc_accepted_sample_count = mock_counters ? mock_accepted : real_accepted;
  wire [63:0] ddc_emitted_sample_count = mock_counters ? mock_emitted : real_emitted;
  wire ddc_output_valid, ddc_output_gap;
  wire signed [15:0] ddc_output_i, ddc_output_q;
  wire [63:0] ddc_output_index;
  starlink_pss_x2_ddc #(.EDGE_UPPER(1), .WIDE_OBSERVATION_COUNTERS(1)) ddc (
    .clk(clk), .resetn(resetn), .enable(ddc_enable), .flush(acquisition_flush),
    .input_valid(raw_valid), .input_gap(raw_gap), .input_i(raw_i), .input_q(raw_q),
    .input_index(raw_index), .output_enable(), .output_valid(ddc_output_valid),
    .output_gap(ddc_output_gap), .output_i(ddc_output_i), .output_q(ddc_output_q),
    .output_index(ddc_output_index), .accepted_sample_count(real_accepted),
    .emitted_sample_count(real_emitted), .discontinuity_count(ddc_discontinuity_count),
    .saturation_event_count(ddc_saturation_event_count)
  );
  reg s_axi_awvalid = 0, s_axi_wvalid = 0, s_axi_bready = 0;
  reg [7:0] s_axi_awaddr = 0, s_axi_araddr = 0;
  reg [31:0] s_axi_wdata = 0;
  reg [3:0] s_axi_wstrb = 0;
  wire s_axi_awready, s_axi_wready, s_axi_bvalid;
  wire [1:0] s_axi_bresp, s_axi_rresp;
  reg s_axi_arvalid = 0, s_axi_rready = 0;
  wire s_axi_arready, s_axi_rvalid;
  wire [31:0] s_axi_rdata;

`ifdef PSMA_STOP_PUBLIC_TRACE
  integer trace_file;
  initial begin
    trace_file = $fopen("psma-public-trace.txt", "w");
    if (!trace_file) $fatal(1, "cannot open public-interface trace");
  end
  always @(posedge clk) begin
    #2;
    $fdisplay(trace_file, "%0t %b", $time,
      {map_read_request, map_read_bank, map_read_index, map_release,
       map_release_bank, acquisition_enable, acquisition_flush, irq,
       s_axi_awready, s_axi_wready, s_axi_bvalid, s_axi_bresp,
       s_axi_arready, s_axi_rvalid, s_axi_rresp, s_axi_rdata, stop_request});
  end
`endif

  starlink_pss_acquisition_health #(.USE_SHARED_XFFT(USE_SHARED_XFFT)) health (
    .clk(clk), .resetn(resetn), .detector_fault(health_events[0]),
    .scheduler_gap_pulse(health_events[1]), .scheduler_index_error_pulse(health_events[2]),
    .scheduler_overflow_pulse(health_events[3]), .forward_fft_fault(health_events[4]),
    .kernel_join_fault(health_events[5]), .product_overflow_fault(health_events[6]),
    .inverse_fft_fault(health_events[7]), .forward_exponent_fault(health_events[8]),
    .candidate_path_fault(health_events[9]), .phase_index_discontinuity_pulse(health_events[10]),
    .score_valid(health_events[11]), .score_denominator_zero(health_events[12]),
    .detector_fault_count(producer_counts[0]), .scheduler_gap_count(producer_counts[1]),
    .scheduler_index_error_count(producer_counts[2]), .scheduler_overflow_count(producer_counts[3]),
    .score_phase_index_discontinuity_count(producer_counts[4]),
    .score_denominator_zero_count(), .detector_health_flags(produced_health_flags)
  );

  starlink_pss_phase_map #(
    .PHASE_BINS(BINS), .PHASE_INDEX_WIDTH(3), .TILE_FRAMES(FRAMES), .TILE_FRAME_WIDTH(2),
    .MAP_SEGMENT_ADDRESS_WIDTH(3), .MAP_SEGMENT_COUNT(1), .MAP_SEGMENT_INDEX_WIDTH(1),
    .ENABLE_BOUNDARY_STOP(ENABLE_BOUNDARY_STOP)
  ) engine (.acquisition_enable(core_enable), .*);
  axi_starlink_pss_phase_map_sync #(
    .PHASE_BINS(BINS), .PHASE_INDEX_WIDTH(3), .TILE_FRAMES(FRAMES),
    .INPUT_RATE_MSPS(INPUT_RATE_MSPS), .USE_SHARED_XFFT(USE_SHARED_XFFT),
    .USE_BANK_OWNED_XFFT(USE_BANK_OWNED_XFFT), .USE_REALTIME_XFFT(USE_REALTIME_XFFT),
    .ENABLE_PILOT_TAP(ENABLE_PILOT_TAP), .COEFFICIENT_ENERGY(COEFFICIENT_ENERGY),
    .ENABLE_BOUNDARY_STOP(ENABLE_BOUNDARY_STOP),
    .HEALTH_COUNTERS_FROM_FLAGS(HEALTH_COUNTERS_FROM_FLAGS),
    .MAP_COUNTERS_FROM_FLAG(MAP_COUNTERS_FROM_FLAG)
  ) control (.map_clk(clk), .map_reset(!resetn), .s_axi_aclk(clk),
             .s_axi_aresetn(resetn), .s_axi_awprot(3'd0), .s_axi_arprot(3'd0),
             .map_counter_fault(controller_map_counter_fault),
             .discarded_score_count(discarded_score_count | independent_map_counts[0]),
             .discontinuity_abort_count(discontinuity_abort_count | independent_map_counts[1]),
             .map_overrun_count(map_overrun_count | independent_map_counts[2]),
             .score_protocol_error_count(score_protocol_error_count | independent_map_counts[3]),
             .map_arithmetic_overflow_count(map_arithmetic_overflow_count | independent_map_counts[4]),
             .map_read_error_count(map_read_error_count | independent_map_counts[5]),
             .map_release_error_count(map_release_error_count | independent_map_counts[6]),
             .detector_health_flags(controller_health_flags), .*);

  task automatic fail(input string message);
    $display("PSMA_STOP_FAIL %s", message);
    $fatal(1);
  endtask
  task automatic idle(input integer cycles);
    repeat (cycles) @(negedge clk);
  endtask
  task automatic axi_write(input [7:0] address, input [31:0] value, input [3:0] strobes);
    integer timeout;
    @(negedge clk);
    s_axi_awaddr = address;
    s_axi_wdata = value;
    s_axi_wstrb = strobes;
    s_axi_awvalid = 1;
    s_axi_wvalid = 1;
    s_axi_bready = 1;
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
      $display("PSMA_STOP_REGISTER address=%02h got=%08h expected=%08h", address, value, expected);
      fail("register mismatch");
    end
  endtask
  task automatic expect_word(input integer index, input [31:0] expected);
    axi_write(8'hfc, index, 4'hf);
    expect_register(8'hfc, expected);
  endtask
  task automatic boot;
    @(negedge clk);
    mock_counters = 0; mock_accepted = 0; mock_emitted = 0;
    raw_valid = 0; raw_gap = 0; ddc_enable = 1;
    resetn = 0; score_valid = 0; stream_discontinuity = 0; core_gate = 1;
    detector_health_flags = 0; ingress_overflow_sticky = 0;
    ingress_dropped_sample_count = 0; score_denominator_zero_count = 0;
    health_events = 0;
    independent_map_summary = 0;
    for (integer counter = 0; counter < 7; counter = counter + 1)
      independent_map_counts[counter] = 0;
    for (integer counter = 0; counter < 5; counter = counter + 1)
      independent_counts[counter] = 0;
    idle(5); resetn = 1; idle(5);
    axi_write(8'h14, 1, 4'hf); idle(BINS + 4);
  endtask
  task automatic health_pulse(input integer cause);
    @(negedge clk); health_events = 13'd1 << (cause == 4 ? 10 : cause);
    @(negedge clk); health_events = 0;
  endtask
  task automatic score(input [63:0] index, input integer phase);
    @(negedge clk); score_valid = 1; score_start_index = index;
    score_phase = phase; score_value = phase + 1;
    @(negedge clk); score_valid = 0;
  endtask
  task automatic tile(input [63:0] first, input bit request);
    for (integer j = 0; j < TOTAL; j = j + 1) begin
      score(first + j, j % BINS);
      if (request && j == 7) axi_write(8'hf8, control.stop_accepted_ticket + 1, 4'hf);
    end
    idle(6);
  endtask
  task automatic expect_terminal(input [31:0] ticket, input [31:0] generation,
                                 input [63:0] first, input [31:0] flags);
    reg [63:0] ending;
    ending = generation == 0 ? 64'd0 : first + TOTAL;
    idle(6);
    expect_register(8'hf8, ticket);
    expect_word(2, flags);
    expect_word(3, ticket); expect_word(4, ticket); expect_word(5, generation);
    expect_word(6, first[31:0]); expect_word(7, first[63:32]);
    expect_word(8, ending[31:0]); expect_word(9, ending[63:32]);
  endtask
  task automatic read_release(input bit bank);
    axi_write(8'h1c, bank, 4'hf);
    axi_write(8'h20, 0, 4'hf);
    for (integer j = 0; j < BINS; j = j + 1) expect_register(8'h24, FRAMES * (j + 1));
    axi_write(8'h28, 1, 4'hf);
    idle(BINS + 4);
  endtask

  // Exact edge scoreboard: accepted-ticket changes require a simultaneous
  // core fence, not an earlier successful AXI write or a software prediction.
  integer acceptance_edges = 0, flush_edges = 0;
  reg [31:0] old_ticket;
  reg accepting_edge;
  always @(posedge clk) begin
    old_ticket = control.stop_accepted_ticket;
    accepting_edge = engine.stop_accept_now;
    if (resetn && acquisition_flush) flush_edges = flush_edges + 1;
    #1;
    if (resetn && control.stop_accepted_ticket != old_ticket) begin
      if (!accepting_edge || !stop_pending) fail("ticket advanced without an actual core fence");
      acceptance_edges = acceptance_edges + 1;
    end
  end


  // Signed test waveform is the inverse Fs/4 rotation of a real baseband FIR
  // sign pattern. This creates one real CI16 clipping event, no forced state.
  task automatic raw_sample(input integer n, input integer mixed, input bit gap);
    @(negedge clk); raw_index = n; raw_valid = 1; raw_gap = gap;
    case (n % 4)
      0: begin raw_i = mixed; raw_q = 0; end
      1: begin raw_i = 0; raw_q = mixed; end
      2: begin raw_i = -mixed; raw_q = 0; end
      3: begin raw_i = 0; raw_q = -mixed; end
    endcase
    @(negedge clk); raw_valid = 0; raw_gap = 0;
  endtask
  task automatic real_ddc_fault(input integer kind);
    integer sign_value;
    if (kind == 0) begin
      for (integer n = 0; n < 16; n = n + 1) begin
        case (n)
          1,5,11,15: sign_value = -30000;
          3,7,8,9,13: sign_value = 30000;
          default: sign_value = 0;
        endcase
        raw_sample(n, sign_value, 0);
      end
      idle(10);
      if (real_accepted !== 16 || real_emitted !== 1 ||
          ddc_saturation_event_count !== 1 || ddc_discontinuity_count !== 0 ||
          ddc_output_i !== 32767 || ddc_output_q !== 0 || ddc_output_index !== 4)
        fail("real DDC clipping waveform/counters/index mismatch");
    end else begin
      for (integer n = 0; n < 32; n = n + 1) raw_sample(n, 0, 0);
      idle(10); raw_sample(32, 0, 1); idle(10);
      if (real_accepted !== 33 || real_emitted !== 9 ||
          ddc_discontinuity_count !== 1 || ddc_saturation_event_count !== 0)
        fail("real DDC explicit-gap waveform/counters mismatch");
    end
  endtask

  task automatic high_low_high(input bit emitted);
    reg [31:0] high1, low1, high2;
    reg [7:0] hi_addr, lo_addr;
    reg [63:0] expected;
    hi_addr = emitted ? 8'hf4 : 8'hf0;
    lo_addr = emitted ? 8'he4 : 8'he0;
    mock_counters = 1;
    mock_accepted = 64'h00000007ffffffff;
    mock_emitted = 64'h00000013ffffffff;
    axi_read(hi_addr, high1);
    // Public input changes across the low-word carry, not a forced real
    // counter. A driver must reject the first mismatched high/low/high set.
    @(negedge clk);
    mock_accepted = mock_accepted + 1; mock_emitted = mock_emitted + 1;
    axi_read(lo_addr, low1); axi_read(hi_addr, high2);
    if (high1 === high2 || low1 !== 0) fail("carry did not require retry");
    axi_read(hi_addr, high1); axi_read(lo_addr, low1); axi_read(hi_addr, high2);
    expected = emitted ? mock_emitted : mock_accepted;
    if (high1 !== high2 || {high2, low1} !== expected)
      fail("high/low/high retry did not reconstruct one coherent counter");
  endtask

  task automatic held_read(input [7:0] address);
    integer timeout;
    reg [31:0] held;
    @(negedge clk); s_axi_araddr = address; s_axi_arvalid = 1; s_axi_rready = 0;
    timeout = 0;
    while (!s_axi_arready && timeout < 100) begin @(posedge clk); timeout = timeout + 1; end
    if (timeout == 100) fail("held read address timeout");
    @(negedge clk); s_axi_arvalid = 0;
    timeout = 0;
    while (!s_axi_rvalid && timeout < 100) begin @(negedge clk); timeout = timeout + 1; end
    if (timeout == 100 || s_axi_rresp !== 0) fail("held read response timeout/error");
    held = s_axi_rdata;
    repeat (8) begin
      @(negedge clk);
      mock_accepted = mock_accepted + 64'h100000001;
      mock_emitted = mock_emitted + 64'h200000003;
      #1;
      if (s_axi_rvalid !== 1 || s_axi_rdata !== held || s_axi_rresp !== 0)
        fail("AXI response changed while stalled");
    end
    @(negedge clk); s_axi_rready = 1;
    @(negedge clk); s_axi_rready = 0;
  endtask

  // This witnesses AXI-domain visibility, not instantaneous propagation of
  // a remote source event. DDC counters change on this clock; public CDC
  // arrival is tested separately in the startup bench.
  reg was_active, was_ddc_fault;
  always @(posedge clk) begin
    was_active = control.stop_active;
    was_ddc_fault = |ddc_saturation_event_count || |ddc_discontinuity_count;
    #1;
    if (resetn && (|ddc_saturation_event_count || |ddc_discontinuity_count) &&
        (control.stop_conditioned_upstream_fault_now !== 1 || stop_request !== 0))
      fail("visible DDC fault did not close same-domain STOP admission");
    if (resetn && was_active && was_ddc_fault && acquisition_enable !== 0)
      fail("visible active DDC fault did not disable at next control edge");
  end

  integer kind, before_count;
  reg [63:0] accepted_before, emitted_before;
  initial begin
    boot();
    expect_register(8'h00, 32'h50534d41);
    expect_register(8'h04, 32'h10007); expect_register(8'h10, 32'h7ff);
    expect_register(8'hb0, 30); expect_register(8'hb4, 32'h000f0203);
    expect_register(8'hb8, 7); expect_register(8'hbc, 1073744004);
    expect_register(8'hc0, 32'h73142604); expect_register(8'hc4, 32'h7077b036);
    expect_register(8'hc8, 32'hf9213db3); expect_register(8'hcc, 32'h574e4a55);
    expect_register(8'hd0, 32'h6fd424b9); expect_register(8'hd4, 32'h7a293843);
    expect_register(8'hd8, 32'hbd6ee085); expect_register(8'hdc, 32'hc2bf33af);
    expect_word(0, 32'h50535354); expect_word(1, 32'h1000c);
    high_low_high(0); high_low_high(1);
    held_read(8'he0); held_read(8'he4); held_read(8'hf0); held_read(8'hf4);
    $display("PSMA17_COUNTER_INTERFACE_PASS carry_retries=2 stalled_reads=4 directly_driven_public_counters=1 atomic_pair_claim=0");

    // Fatal-bit policy includes every bit in 0x77ff; denominator zero is
    // still diagnostic. The complete old-mode test suite remains separate.
    for (integer bit_number = 0; bit_number < 32; bit_number = bit_number + 1) begin
      boot(); detector_health_flags = 32'd1 << bit_number;
      axi_write(8'hf8, 1, 4'hf);
      if (bit_number == 11 || bit_number >= 15) expect_terminal(1, 0, 0, 32'h06);
      else begin expect_register(8'hf8, 0); expect_word(11, 5); end
    end

    for (kind = 0; kind < 2; kind = kind + 1) begin
      // Real conditioner fault before any STOP admission.
      boot(); real_ddc_fault(kind);
      expect_register(kind == 0 ? 8'hec : 8'he8, 1);
      axi_write(8'hf8, 1, 4'hf); expect_register(8'hf8, 0); expect_word(11, 5);
      if (stop_pending || map_ready_mask != 0) fail("pre-admission fault fabricated work");

      // Cumulative counts survive coarse disable, flush and DDC disable.
      accepted_before = real_accepted; emitted_before = real_emitted;
      axi_write(8'h14, 0, 4'hf); axi_write(8'h14, 2, 4'hf);
      ddc_enable = 0; idle(20); ddc_enable = 1;
      axi_write(8'h14, 1, 4'hf); idle(20);
      if (real_accepted !== accepted_before || real_emitted !== emitted_before)
        fail("disable/flush cleared observation counts");
      expect_register(kind == 0 ? 8'hec : 8'he8, 1);
      axi_write(8'hf8, 1, 4'hf); expect_word(11, 5);

      // Pending partial tile: failure aborts only the unfinished map.
      boot(); score(BASE, 0); axi_write(8'hf8, 1, 4'hf); real_ddc_fault(kind);
      // Existing engine adds disable/abort (bit 3), and the resulting real
      // partial-map abort counter adds map-health (bit 1), to upstream bit 0.
      expect_terminal(1, 0, 0, 32'h0a); expect_word(10, 32'h0b);
      if (discontinuity_abort_count != 1 || map_ready_mask != 0 || accepted_score_count != 1)
        fail("pending DDC failure did not preserve exact partial counts");

      // Complete publication first, then a fault while still enabled.
      // Retained complete data is never undone by a later health failure.
      boot(); tile(BASE, 0);
      if (map_ready_mask !== 1 || map_publish_count !== 1) fail("publication missing");
      real_ddc_fault(kind);
      axi_write(8'hf8, 1, 4'hf); expect_register(8'hf8, 0); expect_word(11, 5);
      read_release(0);
      if (accepted_score_count !== TOTAL || map_publish_count !== 1 ||
          map_ready_mask !== 0 || map_counter_fault) fail("failed admission corrupted retained map");

      // Healthy boundary STOP, then actual DDC traffic/fault while retained.
      boot(); tile(BASE, 1); expect_terminal(1, 1, BASE, 32'h16);
      if (acquisition_enable || !ddc_enable) fail("test pilot continuity contract invalid");
      before_count = acceptance_edges;
      real_ddc_fault(kind);
      expect_terminal(1, 1, BASE, 32'h1e); expect_word(10, 1);
      if (map_ready_mask !== 1 || map_publish_count !== 1 || accepted_score_count !== TOTAL ||
          acceptance_edges != before_count || map_counter_fault)
        fail("late DDC fault retroactively altered accepted map");
      read_release(0); expect_terminal(1, 1, BASE, 32'h1e);
      if (map_ready_mask !== 0 || irq) fail("failed-health retained map did not release");

      // A true common upstream reset, not a CONTROL command, clears counts
      // and allows a complete fresh map. Production geometry is not claimed.
      boot();
      if (real_accepted !== 0 || real_emitted !== 0 || ddc_discontinuity_count !== 0 ||
          ddc_saturation_event_count !== 0) fail("upstream reset did not clear real counts");
      tile(BASE, 1); expect_terminal(1, 1, BASE, 32'h16); read_release(0);
      $display("PSMA17_REAL_DDC_LIFETIME_PASS kind=%0d pre_admission=1 pending_partial=1 retained_before_stop=1 retained_after_stop=1 cumulative_disable_flush=1 reset_fresh_map=1", kind);
    end
    $display("PSMA17_STAGE_A_PASS real_axi=1 real_map=1 real_ddc=1 synthetic_scores=1 fft=0 source_cdc=0 rf=0");
    $finish;
  end
  initial begin #2000000; fail("bounded watchdog"); end
endmodule
