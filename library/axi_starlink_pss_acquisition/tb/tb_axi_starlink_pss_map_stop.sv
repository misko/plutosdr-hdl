`timescale 1ns/1ps

// Actual synchronous PSMA + actual map RAM/core, with score/health stimuli.
// No kernel, FFT throughput, pilot capture, or RF qualification is implied.
module tb_axi_starlink_pss_map_stop #(
  parameter integer ENABLE_BOUNDARY_STOP = 1,
  parameter integer USE_SHARED_XFFT = 1,
  parameter integer INPUT_RATE_MSPS = 15
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
  wire stop_request, stop_pending, stop_ack, stop_done, stop_complete, stop_failed, stop_has_map;
  wire [5:0] stop_failure_reason;
  wire [31:0] stop_generation;
  wire [63:0] stop_start_index, stop_end_index;
  wire stop_ready = ENABLE_BOUNDARY_STOP && core_enable && !stop_pending && !stop_done;
  reg [31:0] detector_health_flags = 0, ingress_dropped_sample_count = 0;
  reg ingress_overflow_sticky = 0;
  wire [15:0] ingress_fifo_level = 0, ingress_maximum_fifo_level = 0;
  wire [31:0] scheduler_gap_count = 0, scheduler_index_error_count = 0;
  wire [31:0] scheduler_overflow_count = 0, detector_fault_count = 0;
  wire [31:0] score_phase_index_discontinuity_count = 0;
  reg [31:0] score_denominator_zero_count = 0;
  wire [9:0] candidate_fifo_stored_count = 0, candidate_fifo_maximum_stored_count = 0;
  wire [63:0] ddc_accepted_sample_count = 0, ddc_emitted_sample_count = 0;
  wire [31:0] ddc_discontinuity_count = 0, ddc_saturation_event_count = 0;
  reg s_axi_awvalid = 0, s_axi_wvalid = 0, s_axi_bready = 0;
  reg [7:0] s_axi_awaddr = 0, s_axi_araddr = 0;
  reg [31:0] s_axi_wdata = 0;
  reg [3:0] s_axi_wstrb = 0;
  wire s_axi_awready, s_axi_wready, s_axi_bvalid;
  wire [1:0] s_axi_bresp, s_axi_rresp;
  reg s_axi_arvalid = 0, s_axi_rready = 0;
  wire s_axi_arready, s_axi_rvalid;
  wire [31:0] s_axi_rdata;

  starlink_pss_phase_map #(
    .PHASE_BINS(BINS), .PHASE_INDEX_WIDTH(3), .TILE_FRAMES(FRAMES), .TILE_FRAME_WIDTH(2),
    .MAP_SEGMENT_ADDRESS_WIDTH(3), .MAP_SEGMENT_COUNT(1), .MAP_SEGMENT_INDEX_WIDTH(1),
    .ENABLE_BOUNDARY_STOP(ENABLE_BOUNDARY_STOP)
  ) engine (.acquisition_enable(core_enable), .*);
  axi_starlink_pss_phase_map_sync #(
    .PHASE_BINS(BINS), .PHASE_INDEX_WIDTH(3), .TILE_FRAMES(FRAMES),
    .INPUT_RATE_MSPS(INPUT_RATE_MSPS), .USE_SHARED_XFFT(USE_SHARED_XFFT),
    .ENABLE_BOUNDARY_STOP(ENABLE_BOUNDARY_STOP)
  ) control (.map_clk(clk), .map_reset(!resetn), .s_axi_aclk(clk),
             .s_axi_aresetn(resetn), .s_axi_awprot(3'd0), .s_axi_arprot(3'd0), .*);

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
    resetn = 0; score_valid = 0; stream_discontinuity = 0; core_gate = 1;
    detector_health_flags = 0; ingress_overflow_sticky = 0;
    ingress_dropped_sample_count = 0; score_denominator_zero_count = 0;
    idle(5); resetn = 1; idle(5);
    axi_write(8'h14, 1, 4'hf); idle(BINS + 4);
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

  integer before_count, before_flush, kind;
  reg [31:0] value;
  initial begin
    boot();
    if (!ENABLE_BOUNDARY_STOP) begin
      expect_register(8'h04, USE_SHARED_XFFT ? 32'h10005 :
                      INPUT_RATE_MSPS == 15 ? 32'h10001 : INPUT_RATE_MSPS == 30 ? 32'h10002 : 32'h10004);
      expect_register(8'hf8, 0); expect_register(8'hfc, 0);
      axi_write(8'hf8, 1, 4'hf); axi_write(8'hfc, 11, 4'hf);
      force control.stop_ready = 1'bx; force control.stop_ack = 1'b1;
      force control.stop_done = 1'bx; force control.stop_failed = 1'b1;
      idle(3);
      expect_register(8'hf8, 0); expect_register(8'hfc, 0);
      if (stop_request !== 0 || !acquisition_enable) fail("disabled feature reacted to X/Z/control inputs");
      release control.stop_ready; release control.stop_ack;
      release control.stop_done; release control.stop_failed;
    end else begin
      expect_register(8'h04, 32'h10006); expect_register(8'h10, 32'h33f);
      expect_word(0, 32'h50535354); expect_word(1, 32'h1000c);
      expect_word(2, 32'h20); expect_word(3, 0); expect_word(4, 0);
      expect_word(5, 0); expect_word(6, 0); expect_word(7, 0);
      expect_word(8, 0); expect_word(9, 0); expect_word(10, 0);
      axi_write(8'hf8, 0, 4'hf); expect_word(11, 2);
      axi_write(8'hf8, 2, 4'hf); expect_word(11, 2);
      axi_write(8'hf8, 1, 4'h1); expect_word(11, 1);
      axi_write(8'hfc, 0, 4'hf);
      axi_write(8'hfc, 12, 4'hf); expect_register(8'hfc, 32'h50535354);
      expect_word(11, 1);
      axi_write(8'hfc, 1, 4'h1); expect_word(11, 1);
      expect_register(8'hf8, 0);

      // Same ticket retry while filling is harmless; a different one is busy.
      score(BASE, 0); axi_write(8'hf8, 1, 4'hf);
      expect_register(8'hf8, 1); expect_word(2, 32'h21);
      before_count = acceptance_edges;
      axi_write(8'hf8, 1, 4'hf); expect_word(11, 0);
      axi_write(8'hf8, 2, 4'hf); expect_word(11, 3);
      if (acceptance_edges != before_count) fail("busy/replay command repeated a core request");
      for (integer j = 1; j < TOTAL; j = j + 1) score(BASE + j, j % BINS);
      expect_terminal(1, 1, BASE, 32'h16);
      if (!irq || acquisition_enable) fail("successful stop did not preserve ready IRQ");
      read_release(0);
      if (irq || map_ready_mask != 0) fail("released stopped bank still asserts IRQ");
      expect_terminal(1, 1, BASE, 32'h16);
      axi_write(8'hf8, 1, 4'hf); expect_word(11, 0);
      axi_write(8'hf8, 2, 4'hf); expect_word(11, 4);

      // Invalidated history is retained across restart. Earliest accepted
      // next ticket depends on actual core readiness, not CONTROL readback.
      core_gate = 0;
      axi_write(8'h14, 1, 4'hf);
      expect_word(2, 32'h20); expect_word(4, 1); expect_word(5, 1);
      expect_word(6, BASE[31:0]); expect_word(8, 32'h10);
      axi_write(8'hf8, 2, 4'hf); expect_word(11, 4);
      expect_register(8'hf8, 1);
      core_gate = 1;
      wait(stop_ready);
      before_count = acceptance_edges;
      axi_write(8'hf8, 1, 4'hf); expect_word(11, 0);
      expect_word(2, 32'h20); expect_register(8'hf8, 1);
      if (stop_pending || stop_done || acceptance_edges != before_count)
        fail("old accepted-ticket replay stopped a new acquisition epoch");
      axi_write(8'hf8, 2, 4'hf);
      expect_terminal(2, 1, BASE, 32'h16);

      // Both complete banks remain readable/releasable after production stops.
      boot(); tile(BASE, 0); tile(BASE + TOTAL, 1);
      expect_terminal(1, 2, BASE + TOTAL, 32'h16);
      if (map_ready_mask != 3 || !irq || map_overrun_count != 0)
        fail("two-ready-bank stop discarded data or invented an overrun");
      read_release(0);
      if (!irq) fail("IRQ dropped before second bank drained");
      read_release(1);
      expect_terminal(1, 2, BASE + TOTAL, 32'h16);

      // A single-cycle fault between staging and engine acceptance rejects
      // the attempted request; no accepted ticket/fence or pending residue.
      boot(); before_count = acceptance_edges;
      fork
        axi_write(8'hf8, 1, 4'hf);
        begin wait(control.stop_staged); @(negedge clk); detector_health_flags = 32'h4000;
          @(negedge clk); detector_health_flags = 0; end
      join
      expect_register(8'hf8, 0); expect_word(11, 5); expect_word(2, 32'h20);
      if (stop_pending || acceptance_edges != before_count) fail("rejected stage applied a fence");
      axi_write(8'hf8, 1, 4'hf); expect_terminal(1, 0, 0, 32'h06);

      // Core enable loss at that same staging boundary is also unaccepted.
      boot(); before_count = acceptance_edges;
      fork
        axi_write(8'hf8, 1, 4'hf);
        begin wait(control.stop_staged); @(negedge clk); core_gate = 0; end
      join
      expect_register(8'hf8, 0); expect_word(11, 4); expect_word(2, 32'h20);
      if (stop_pending || acceptance_edges != before_count) fail("disabled stage advanced ticket");

      // The actual AXI engine serializes writes. Inject only the decoder
      // signals to exercise hypothetical same-clock staged CONTROL0/2 races;
      // normal command/control tests above/below use the real AXI interface.
      for (kind = 0; kind < 2; kind = kind + 1) begin
        boot(); before_count = acceptance_edges;
        fork
          axi_write(8'hf8, 1, 4'hf);
          begin
            wait(control.stop_staged); @(negedge clk);
            force control.up_wreq = 1'b1; force control.up_waddr = 6'h05;
            if (kind == 0) force control.up_wdata = 32'd0;
            else force control.up_wdata = 32'd2;
            force control.up_wstrb = 4'hf;
            @(negedge clk);
            release control.up_wreq; release control.up_waddr;
            release control.up_wdata; release control.up_wstrb;
          end
        join
        expect_register(8'hf8, 0); expect_word(11, 4); expect_word(2, 0);
        if (stop_pending || acceptance_edges != before_count) fail("CONTROL stage race fabricated acceptance");
      end

      // Same-clock retries at the decoder cannot mask a staged rejection.
      // Native AXI serializes these writes, so only this otherwise unreachable
      // coincidence uses decoder injection (the initial write is native AXI).
      for (kind = 0; kind < 2; kind = kind + 1) begin
        boot(); before_count = acceptance_edges;
        fork
          axi_write(8'hf8, 1, 4'hf);
          begin
            wait(control.stop_staged); @(negedge clk);
            force control.up_wreq = 1'b1; force control.up_waddr = 6'h3e;
            force control.up_wdata = 32'd1; force control.up_wstrb = 4'hf;
            if (kind == 0) detector_health_flags = 32'h4000;
            else core_gate = 0;
            @(negedge clk);
            release control.up_wreq; release control.up_waddr;
            release control.up_wdata; release control.up_wstrb;
            detector_health_flags = 0;
          end
        join
        expect_register(8'hf8, 0); expect_word(11, kind == 0 ? 5 : 4);
        expect_word(2, 32'h20);
        if (stop_pending || acceptance_edges != before_count)
          fail("same-edge retry concealed a staged rejection");
      end

      // CONTROL0/2/3 after acceptance are explicit failures, not graceful
      // receipts. Partial FILL must execute its existing real abort counter.
      for (kind = 0; kind < 3; kind = kind + 1) begin
        boot(); score(BASE, 0); axi_write(8'hf8, 1, 4'hf);
        axi_write(8'h14, kind == 0 ? 0 : kind == 1 ? 2 : 3, 4'hf);
        expect_terminal(1, 0, 0, 32'h0a);
        axi_write(8'hfc, 10, 4'hf); axi_read(8'hfc, value);
        if (!value[3] || discontinuity_abort_count != 1)
          fail("explicit abort lost its receipt/counter");
      end

      // Known health blocks new admission; diagnostic denominator-zero does not.
      boot(); detector_health_flags = 32'h4000;
      axi_write(8'hf8, 1, 4'hf); expect_word(11, 5); expect_register(8'hf8, 0);
      boot(); detector_health_flags = 32'h800; score_denominator_zero_count = 9;
      axi_write(8'hf8, 1, 4'hf); expect_terminal(1, 0, 0, 32'h06);

      // Pulse-only faults on controller retirement or afterwards stay sticky
      // without changing the terminal coordinate tuple.
      for (kind = 0; kind < 2; kind = kind + 1) begin
        boot();
        fork
          tile(BASE, 1);
          begin
            if (kind == 0) wait(stop_ack); else wait(control.stop_terminal_valid);
            @(negedge clk); detector_health_flags = 32'h4000;
            @(negedge clk); detector_health_flags = 0;
          end
        join
        expect_terminal(1, 1, BASE, 32'h1e); expect_word(10, 1);
        read_release(0); expect_terminal(1, 1, BASE, 32'h1e);
      end

      // CONTROL0/1/2/3 coincident with controller retirement must not
      // immediately restart the just-fenced producer. Requested flushes
      // still occur and disable/flush commands record explicit aborts.
      for (kind = 0; kind < 4; kind = kind + 1) begin
        boot(); before_flush = flush_edges;
        fork
          tile(BASE, 1);
          begin
            wait(stop_ack); @(negedge clk);
            force control.up_wreq = 1'b1; force control.up_waddr = 6'h05;
            case (kind)
              0: force control.up_wdata = 32'd0;
              1: force control.up_wdata = 32'd1;
              2: force control.up_wdata = 32'd2;
              3: force control.up_wdata = 32'd3;
            endcase
            force control.up_wstrb = 4'hf;
            @(negedge clk);
            release control.up_wreq; release control.up_waddr;
            release control.up_wdata; release control.up_wstrb;
          end
        join
        expect_terminal(1, 1, BASE, kind == 1 ? 32'h16 : 32'h1e);
        expect_word(10, kind == 1 ? 0 : 8);
        if (acquisition_enable || flush_edges != before_flush + (kind >= 2 ? 1 : 0))
          fail("coincident terminal/CONTROL enable priority changed");
        axi_write(8'h14, 1, 4'hf);
        if (!acquisition_enable) fail("subsequent explicit rearm did not enable");
        expect_word(2, kind == 1 ? 32'h20 : 32'h28);
      end

      // A true active fault aborts unfinished work, preserving original counters.
      boot(); score(BASE, 0); axi_write(8'hf8, 1, 4'hf);
      @(negedge clk); ingress_overflow_sticky = 1;
      @(negedge clk); ingress_overflow_sticky = 0;
      expect_terminal(1, 0, 0, 32'h0a);
      if (discontinuity_abort_count != 1) fail("fault-driven partial abort was erased");

      // Read/release still execute real bridge checks after a healthy fence.
      boot(); tile(BASE, 1); expect_terminal(1, 1, BASE, 32'h16);
      read_release(0); axi_write(8'h28, 1, 4'hf);
      expect_terminal(1, 1, BASE, 32'h1e);
      axi_write(8'hfc, 10, 4'hf); axi_read(8'hfc, value);
      if (!value[2]) fail("late bridge error disappeared");

      // The core's unrepresentable source end and generation exhaustion
      // survive the controller window as failed, stable historical tuples.
      boot(); tile(64'hfffffffffffffff0, 1);
      expect_word(2, 32'h1e); expect_word(5, 1);
      expect_word(6, 32'hfffffff0); expect_word(7, 32'hffffffff);
      expect_word(8, 0); expect_word(9, 0); expect_word(10, 32'h10);
      read_release(0);
      expect_word(6, 32'hfffffff0); expect_word(8, 0); expect_word(10, 32'h10);
      boot(); @(negedge clk); engine.map_publish_count = 32'hfffffffe;
      tile(BASE, 1);
      expect_terminal(1, 32'hffffffff, BASE, 32'h1e); expect_word(10, 32'h20);

      // Seed only the monotonic counter boundary, not billions of fake maps.
      boot(); @(negedge clk); control.stop_accepted_ticket = 32'hfffffffe;
      axi_write(8'hf8, 32'hffffffff, 4'hf);
      expect_terminal(32'hffffffff, 0, 0, 32'h06);
      axi_write(8'h14, 1, 4'hf); axi_write(8'hf8, 1, 4'hf); expect_word(11, 2);
      axi_write(8'hf8, 0, 4'hf); expect_word(11, 2);
      axi_write(8'hf8, 32'hffffffff, 4'hf); expect_word(11, 0);

      // Reset during pending clears the old epoch instead of manufacturing a
      // terminal receipt for an interrupted request.
      boot(); score(BASE, 0); axi_write(8'hf8, 1, 4'hf); boot();
      expect_register(8'hf8, 0); expect_word(4, 0); expect_word(2, 32'h20);
    end

    // Legacy enable/flush bits are unchanged with no stop operation active.
    boot(); before_flush = flush_edges;
    axi_write(8'h14, 0, 4'hf); if (acquisition_enable) fail("CONTROL0 did not disable");
    axi_write(8'h14, 1, 4'hf); if (!acquisition_enable) fail("CONTROL1 did not enable");
    axi_write(8'h14, 2, 4'hf); if (acquisition_enable) fail("CONTROL2 did not disable");
    axi_write(8'h14, 3, 4'hf); if (!acquisition_enable) fail("CONTROL3 did not enable");
    if (flush_edges != before_flush + 2) fail("CONTROL2/3 flush pulses changed");
    axi_write(8'h14, 0, 4'h2); if (!acquisition_enable) fail("CONTROL ignored byte strobe semantics");
    $display("PSMA_STOP_PASS enabled=%0d shared=%0d rate=%0d actual_core=1 actual_axi=1 no_radio_claim=1",
             ENABLE_BOUNDARY_STOP, USE_SHARED_XFFT, INPUT_RATE_MSPS);
    $finish;
  end
  initial begin #3000000; fail("bounded PSMA stop simulation timeout"); end
endmodule
