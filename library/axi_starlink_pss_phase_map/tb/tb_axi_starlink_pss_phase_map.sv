`timescale 1ns/1ps

module tb_axi_starlink_pss_phase_map #(
  parameter integer MAP_HALF_PERIOD_NS = 7,
  parameter integer AXI_HALF_PERIOD_NS = 5,
  parameter integer MAP_INITIAL_DELAY_NS = 0,
  parameter integer AXI_INITIAL_DELAY_NS = 0
);

  localparam integer PHASE_BINS = 8;
  localparam integer PHASE_INDEX_WIDTH = 3;
  localparam integer TILE_FRAMES = 4;
  localparam integer TILE_FRAME_WIDTH = 2;

  reg map_clk = 1'b0;
  reg s_axi_aclk = 1'b0;
  initial begin
    #(MAP_INITIAL_DELAY_NS);
    forever #(MAP_HALF_PERIOD_NS) map_clk = ~map_clk;
  end
  initial begin
    #(AXI_INITIAL_DELAY_NS);
    forever #(AXI_HALF_PERIOD_NS) s_axi_aclk = ~s_axi_aclk;
  end

  reg map_reset = 1'b1;
  reg score_valid = 1'b0;
  reg [63:0] score_start_index = 64'd0;
  reg [PHASE_INDEX_WIDTH-1:0] score_phase = 0;
  reg [7:0] score_value = 8'd0;
  reg stream_discontinuity = 1'b0;

  wire [1:0] map_ready_mask;
  wire [31:0] map_generation_0;
  wire [31:0] map_generation_1;
  wire [63:0] map_start_index_0;
  wire [63:0] map_start_index_1;
  wire map_read_request;
  wire map_read_bank;
  wire [PHASE_INDEX_WIDTH-1:0] map_read_index;
  wire map_read_valid;
  wire [15:0] map_read_data;
  wire map_read_error;
  wire map_release;
  wire map_release_bank;
  wire [31:0] accepted_score_count;
  wire [31:0] discarded_score_count;
  wire [31:0] discontinuity_abort_count;
  wire [31:0] map_publish_count;
  wire [31:0] map_overrun_count;
  wire [31:0] score_protocol_error_count;
  wire [31:0] map_arithmetic_overflow_count;
  wire [31:0] map_read_error_count;
  wire [31:0] map_release_error_count;
  wire acquisition_enable;
  wire acquisition_flush;
  wire irq;

  reg s_axi_aresetn = 1'b0;
  reg s_axi_awvalid = 1'b0;
  reg [7:0] s_axi_awaddr = 8'd0;
  wire s_axi_awready;
  reg s_axi_wvalid = 1'b0;
  reg [31:0] s_axi_wdata = 32'd0;
  reg [3:0] s_axi_wstrb = 4'hf;
  wire s_axi_wready;
  wire s_axi_bvalid;
  wire [1:0] s_axi_bresp;
  reg s_axi_bready = 1'b0;
  reg s_axi_arvalid = 1'b0;
  reg [7:0] s_axi_araddr = 8'd0;
  wire s_axi_arready;
  wire s_axi_rvalid;
  wire [1:0] s_axi_rresp;
  wire [31:0] s_axi_rdata;
  reg s_axi_rready = 1'b0;

  reg [31:0] read_value;
  reg [31:0] concurrent_read_value;
  integer flush_pulse_count = 0;
  integer axi_cycle_count = 0;
  integer map_read_start_cycle = 0;
  integer map_read_latency_cycles = 0;
  integer max_map_read_latency_cycles = 0;

  always @(posedge s_axi_aclk)
    axi_cycle_count <= axi_cycle_count + 1;

  starlink_pss_phase_map #(
    .PHASE_BINS               (PHASE_BINS),
    .PHASE_INDEX_WIDTH        (PHASE_INDEX_WIDTH),
    .TILE_FRAMES              (TILE_FRAMES),
    .TILE_FRAME_WIDTH         (TILE_FRAME_WIDTH),
    .SCORE_WIDTH              (8),
    .MAP_WIDTH                (16),
    .MAP_SEGMENT_ADDRESS_WIDTH(2),
    .MAP_SEGMENT_COUNT        (2),
    .MAP_SEGMENT_INDEX_WIDTH  (1)
  ) phase_map (
    .clk                          (map_clk),
    .resetn                       (!map_reset),
    .acquisition_enable           (acquisition_enable && !acquisition_flush),
    .score_valid                  (score_valid),
    .score_start_index            (score_start_index),
    .score_phase                  (score_phase),
    .score_value                  (score_value),
    .stream_discontinuity         (stream_discontinuity || acquisition_flush),
    .map_ready_mask               (map_ready_mask),
    .map_generation_0             (map_generation_0),
    .map_generation_1             (map_generation_1),
    .map_start_index_0            (map_start_index_0),
    .map_start_index_1            (map_start_index_1),
    .map_read_request             (map_read_request),
    .map_read_bank                (map_read_bank),
    .map_read_index               (map_read_index),
    .map_read_valid               (map_read_valid),
    .map_read_data                (map_read_data),
    .map_read_error               (map_read_error),
    .map_release                  (map_release),
    .map_release_bank             (map_release_bank),
    .accepted_score_count         (accepted_score_count),
    .discarded_score_count        (discarded_score_count),
    .discontinuity_abort_count    (discontinuity_abort_count),
    .map_publish_count            (map_publish_count),
    .map_overrun_count            (map_overrun_count),
    .score_protocol_error_count   (score_protocol_error_count),
    .map_arithmetic_overflow_count(map_arithmetic_overflow_count),
    .map_read_error_count         (map_read_error_count),
    .map_release_error_count      (map_release_error_count)
  );

  axi_starlink_pss_phase_map #(
    .PHASE_BINS      (PHASE_BINS),
    .PHASE_INDEX_WIDTH(PHASE_INDEX_WIDTH),
    .TILE_FRAMES     (TILE_FRAMES),
    .MAP_WIDTH       (16)
  ) dut (
    .map_clk                       (map_clk),
    .map_reset                     (map_reset),
    .map_ready_mask                (map_ready_mask),
    .map_generation_0              (map_generation_0),
    .map_generation_1              (map_generation_1),
    .map_start_index_0             (map_start_index_0),
    .map_start_index_1             (map_start_index_1),
    .map_read_request              (map_read_request),
    .map_read_bank                 (map_read_bank),
    .map_read_index                (map_read_index),
    .map_read_valid                (map_read_valid),
    .map_read_data                 (map_read_data),
    .map_read_error                (map_read_error),
    .map_release                   (map_release),
    .map_release_bank              (map_release_bank),
    .accepted_score_count          (accepted_score_count),
    .discarded_score_count         (discarded_score_count),
    .discontinuity_abort_count     (discontinuity_abort_count),
    .map_publish_count             (map_publish_count),
    .map_overrun_count             (map_overrun_count),
    .score_protocol_error_count    (score_protocol_error_count),
    .map_arithmetic_overflow_count (map_arithmetic_overflow_count),
    .map_read_error_count          (map_read_error_count),
    .map_release_error_count       (map_release_error_count),
    .detector_health_flags         (32'd0),
    .ingress_overflow_sticky       (1'b0),
    .ingress_dropped_sample_count  (32'd0),
    .ingress_fifo_level            (16'd0),
    .ingress_maximum_fifo_level    (16'd0),
    .scheduler_gap_count           (32'd0),
    .scheduler_index_error_count   (32'd0),
    .scheduler_overflow_count      (32'd0),
    .detector_fault_count          (32'd0),
    .score_phase_index_discontinuity_count(32'd0),
    .score_denominator_zero_count  (32'd0),
    .candidate_fifo_stored_count   (10'd0),
    .candidate_fifo_maximum_stored_count(10'd0),
    .acquisition_enable            (acquisition_enable),
    .acquisition_flush             (acquisition_flush),
    .irq                           (irq),
    .s_axi_aclk                    (s_axi_aclk),
    .s_axi_aresetn                 (s_axi_aresetn),
    .s_axi_awvalid                 (s_axi_awvalid),
    .s_axi_awaddr                  (s_axi_awaddr),
    .s_axi_awready                 (s_axi_awready),
    .s_axi_wvalid                  (s_axi_wvalid),
    .s_axi_wdata                   (s_axi_wdata),
    .s_axi_wstrb                   (s_axi_wstrb),
    .s_axi_wready                  (s_axi_wready),
    .s_axi_bvalid                  (s_axi_bvalid),
    .s_axi_bresp                   (s_axi_bresp),
    .s_axi_bready                  (s_axi_bready),
    .s_axi_arvalid                 (s_axi_arvalid),
    .s_axi_araddr                  (s_axi_araddr),
    .s_axi_arready                 (s_axi_arready),
    .s_axi_rvalid                  (s_axi_rvalid),
    .s_axi_rresp                   (s_axi_rresp),
    .s_axi_rdata                   (s_axi_rdata),
    .s_axi_rready                  (s_axi_rready),
    .s_axi_awprot                  (3'd0),
    .s_axi_arprot                  (3'd0)
  );

  task automatic fail;
    input [1023:0] message;
    begin
      $display("AXI_PHASE_MAP_FAIL %0s", message);
      $fatal(1);
    end
  endtask

  task automatic axi_read;
    input [7:0] address;
    output [31:0] data;
    integer timeout;
    begin
      @(negedge s_axi_aclk);
      s_axi_araddr = address;
      s_axi_arvalid = 1'b1;
      s_axi_rready = 1'b1;
      if (address == 8'h24)
        map_read_start_cycle = axi_cycle_count;
      timeout = 0;
      while (!s_axi_arready && timeout < 100) begin
        @(posedge s_axi_aclk);
        timeout = timeout + 1;
      end
      if (timeout == 100)
        fail("AXI read address timeout");
      @(negedge s_axi_aclk);
      s_axi_arvalid = 1'b0;
      timeout = 0;
      while (!s_axi_rvalid && timeout < 100) begin
        @(posedge s_axi_aclk);
        timeout = timeout + 1;
      end
      if (timeout == 100 || s_axi_rresp != 2'b00)
        fail("AXI read response timeout/error");
      data = s_axi_rdata;
      if (address == 8'h24) begin
        map_read_latency_cycles = axi_cycle_count - map_read_start_cycle;
        if (map_read_latency_cycles > max_map_read_latency_cycles)
          max_map_read_latency_cycles = map_read_latency_cycles;
        if (map_read_latency_cycles > 50)
          fail("MAP_DATA CDC round trip exceeded 50 AXI clocks");
      end
      @(negedge s_axi_aclk);
      s_axi_rready = 1'b0;
    end
  endtask

  task automatic axi_write;
    input [7:0] address;
    input [31:0] data;
    integer timeout;
    begin
      @(negedge s_axi_aclk);
      s_axi_awaddr = address;
      s_axi_wdata = data;
      s_axi_wstrb = 4'hf;
      s_axi_awvalid = 1'b1;
      s_axi_wvalid = 1'b1;
      s_axi_bready = 1'b1;
      timeout = 0;
      while (!(s_axi_awready && s_axi_wready) && timeout < 100) begin
        @(posedge s_axi_aclk);
        timeout = timeout + 1;
      end
      if (timeout == 100)
        fail("AXI write address/data timeout");
      @(negedge s_axi_aclk);
      s_axi_awvalid = 1'b0;
      s_axi_wvalid = 1'b0;
      timeout = 0;
      while (!s_axi_bvalid && timeout < 100) begin
        @(posedge s_axi_aclk);
        timeout = timeout + 1;
      end
      if (timeout == 100 || s_axi_bresp != 2'b00)
        fail("AXI write response timeout/error");
      @(negedge s_axi_aclk);
      s_axi_bready = 1'b0;
    end
  endtask

  task automatic axi_write_split;
    input [7:0] address;
    input [31:0] data;
    input [3:0] strobe;
    input address_first;
    integer split_timeout;
    begin
      @(negedge s_axi_aclk);
      s_axi_awaddr = address;
      s_axi_wdata = data;
      s_axi_wstrb = strobe;
      s_axi_bready = 1'b0;

      if (address_first) begin
        s_axi_awvalid = 1'b1;
        split_timeout = 0;
        while (!s_axi_awready && split_timeout < 100) begin
          @(posedge s_axi_aclk);
          split_timeout = split_timeout + 1;
        end
        if (split_timeout == 100)
          fail("split AXI write-address timeout");
        @(negedge s_axi_aclk);
        s_axi_awvalid = 1'b0;
        repeat (3) @(posedge s_axi_aclk);
        @(negedge s_axi_aclk);
        s_axi_wvalid = 1'b1;
        split_timeout = 0;
        while (!s_axi_wready && split_timeout < 100) begin
          @(posedge s_axi_aclk);
          split_timeout = split_timeout + 1;
        end
        if (split_timeout == 100)
          fail("split AXI write-data timeout");
        @(negedge s_axi_aclk);
        s_axi_wvalid = 1'b0;
      end else begin
        s_axi_wvalid = 1'b1;
        split_timeout = 0;
        while (!s_axi_wready && split_timeout < 100) begin
          @(posedge s_axi_aclk);
          split_timeout = split_timeout + 1;
        end
        if (split_timeout == 100)
          fail("split AXI write-data timeout");
        @(negedge s_axi_aclk);
        s_axi_wvalid = 1'b0;
        repeat (3) @(posedge s_axi_aclk);
        @(negedge s_axi_aclk);
        s_axi_awvalid = 1'b1;
        split_timeout = 0;
        while (!s_axi_awready && split_timeout < 100) begin
          @(posedge s_axi_aclk);
          split_timeout = split_timeout + 1;
        end
        if (split_timeout == 100)
          fail("split AXI write-address timeout");
        @(negedge s_axi_aclk);
        s_axi_awvalid = 1'b0;
      end

      split_timeout = 0;
      while (!s_axi_bvalid && split_timeout < 100) begin
        @(posedge s_axi_aclk);
        split_timeout = split_timeout + 1;
      end
      if (split_timeout == 100 || s_axi_bresp != 2'b00)
        fail("split AXI write response timeout/error");
      repeat (3) begin
        @(posedge s_axi_aclk);
        if (!s_axi_bvalid || s_axi_bresp != 2'b00)
          fail("AXI write response was not held under backpressure");
      end
      @(negedge s_axi_aclk);
      s_axi_bready = 1'b1;
      @(negedge s_axi_aclk);
      s_axi_bready = 1'b0;
      s_axi_wstrb = 4'hf;
    end
  endtask

  task automatic axi_read_backpressured;
    input [7:0] address;
    input [31:0] expected;
    integer read_timeout;
    begin
      @(negedge s_axi_aclk);
      s_axi_araddr = address;
      s_axi_arvalid = 1'b1;
      s_axi_rready = 1'b0;
      read_timeout = 0;
      while (!s_axi_arready && read_timeout < 100) begin
        @(posedge s_axi_aclk);
        read_timeout = read_timeout + 1;
      end
      if (read_timeout == 100)
        fail("backpressured AXI read-address timeout");
      @(negedge s_axi_aclk);
      s_axi_arvalid = 1'b0;
      read_timeout = 0;
      while (!s_axi_rvalid && read_timeout < 100) begin
        @(posedge s_axi_aclk);
        read_timeout = read_timeout + 1;
      end
      if (read_timeout == 100 || s_axi_rresp != 2'b00 ||
          s_axi_rdata !== expected)
        fail("backpressured AXI read response mismatch");
      repeat (5) begin
        @(posedge s_axi_aclk);
        if (!s_axi_rvalid || s_axi_rresp != 2'b00 ||
            s_axi_rdata !== expected)
          fail("AXI read response was not held stable under backpressure");
      end
      @(negedge s_axi_aclk);
      s_axi_rready = 1'b1;
      @(negedge s_axi_aclk);
      s_axi_rready = 1'b0;
    end
  endtask

  task automatic wait_snapshot;
    integer timeout;
    begin
      timeout = 0;
      read_value = 0;
      while (!read_value[0] && timeout < 100) begin
        axi_read(8'h34, read_value);
        timeout = timeout + 1;
      end
      if (timeout == 100 || read_value[1])
        fail("snapshot did not complete");
    end
  endtask

  task automatic feed_tile;
    input [63:0] first_index;
    integer frame;
    integer phase;
    begin
      for (frame = 0; frame < TILE_FRAMES; frame = frame + 1) begin
        for (phase = 0; phase < PHASE_BINS; phase = phase + 1) begin
          @(negedge map_clk);
          score_valid = 1'b1;
          score_start_index = first_index + frame * PHASE_BINS + phase;
          score_phase = phase;
          score_value = phase + frame + 1;
        end
      end
      @(negedge map_clk);
      score_valid = 1'b0;
      score_phase = 0;
      score_value = 0;
    end
  endtask

  always @(posedge map_clk) begin
    if (acquisition_flush)
      flush_pulse_count <= flush_pulse_count + 1;
  end

  integer phase;
  integer timeout;
  integer ready_bank;
  integer expected_value;
  reg [31:0] snapshot_generation_before;
  initial begin
    $dumpfile("build/tb_axi_starlink_pss_phase_map.vcd");
    $dumpvars(0, tb_axi_starlink_pss_phase_map);

    repeat (6) @(posedge map_clk);
    @(negedge map_clk);
    map_reset = 1'b0;
    @(negedge s_axi_aclk);
    s_axi_aresetn = 1'b1;
    repeat (10) @(posedge s_axi_aclk);

    axi_read(8'h00, read_value);
    if (read_value !== 32'h5053_4d41)
      fail("identification mismatch");
    axi_read(8'h04, read_value);
    if (read_value !== 32'h0001_0001)
      fail("version mismatch");
    axi_read(8'h08, read_value);
    if (read_value !== PHASE_BINS)
      fail("phase-bin geometry mismatch");
    axi_read(8'h0c, read_value);
    if (read_value !== 32'h0004_1002)
      fail("tile geometry mismatch");
    axi_read(8'h10, read_value);
    if (read_value !== 32'h0000_003f)
      fail("capabilities mismatch");

    axi_read_backpressured(8'h00, 32'h5053_4d41);
    axi_write_split(8'h20, 32'd5, 4'b0001, 1'b1);
    axi_read(8'h20, read_value);
    if (read_value !== 5)
      fail("address-first partial-strobe write mismatch");
    axi_write_split(8'h20, 32'hffff_ffff, 4'b0000, 1'b0);
    axi_read(8'h20, read_value);
    if (read_value !== 5)
      fail("zero-strobe write changed a register");
    axi_write(8'h20, 32'd0);

    axi_write(8'h14, 32'h0000_0001);
    timeout = 0;
    while (!acquisition_enable && timeout < 30) begin
      @(posedge map_clk);
      timeout = timeout + 1;
    end
    if (timeout == 30)
      fail("enable did not cross into map clock");

    // Both small test banks clear before the first complete tile begins.
    repeat (PHASE_BINS + 5) @(posedge map_clk);
    feed_tile(64'd1000);
    timeout = 0;
    while (!irq && timeout < 40) begin
      @(posedge s_axi_aclk);
      timeout = timeout + 1;
    end
    if (timeout == 40 || map_ready_mask !== 2'b01)
      fail("first immutable map was not published");

    axi_write(8'h30, 32'h0000_0001);
    wait_snapshot();
    axi_read(8'h38, snapshot_generation_before);
    if (snapshot_generation_before !== 1)
      fail("snapshot generation mismatch");
    axi_read(8'h3c, read_value);
    if (read_value[1:0] !== 2'b01)
      fail("snapshot ready mask mismatch");
    axi_read(8'h40, read_value);
    if (read_value !== 1)
      fail("map generation zero mismatch");
    axi_read(8'h48, read_value);
    if (read_value !== 1000)
      fail("map start index low mismatch");
    axi_read(8'h4c, read_value);
    if (read_value !== 0)
      fail("map start index high mismatch");
    axi_read(8'h58, read_value);
    if (read_value !== TILE_FRAMES * PHASE_BINS)
      fail("atomic accepted-score counter mismatch");
    axi_read(8'h64, read_value);
    if (read_value !== 1)
      fail("atomic publication counter mismatch");

    // One index write followed by sequential MAP_DATA reads exercises the
    // blocking CDC response and successful auto-increment contract.
    axi_write(8'h1c, 32'd0);
    axi_write(8'h20, 32'd0);
    for (phase = 0; phase < PHASE_BINS; phase = phase + 1) begin
      axi_read(8'h24, read_value);
      expected_value = 4 * phase + 10;
      if (read_value !== expected_value) begin
        $display("AXI_PHASE_MAP_DATA phase=%0d expected=%0d actual=%0d",
                 phase, expected_value, read_value);
        fail("map data or auto-increment mismatch");
      end
    end
    axi_read(8'h20, read_value);
    if (read_value !== PHASE_BINS - 1)
      fail("map index did not saturate at the final bin");

    // AXI-Lite permits independent read and write progress.  A retarget made
    // while MAP_DATA is in flight must survive the older read's completion.
    axi_write(8'h20, 32'd2);
    fork
      begin
        axi_read(8'h24, concurrent_read_value);
      end
      begin
        repeat (2) @(posedge s_axi_aclk);
        axi_write(8'h20, 32'd5);
      end
    join
    if (concurrent_read_value !== 18)
      fail("concurrent MAP_DATA read returned the wrong request index");
    axi_read(8'h20, read_value);
    if (read_value !== 5)
      fail("completed MAP_DATA read overwrote a newer map selection");

    // An unreadied bank is rejected in the source domain and still returns a
    // bounded AXI response rather than hanging the bus.
    axi_write(8'h1c, 32'd1);
    axi_write(8'h20, 32'd0);
    axi_read(8'h24, read_value);
    if (read_value !== 0) begin
      $display("AXI_PHASE_MAP_INVALID_READ actual=0x%08x", read_value);
      fail("invalid map read did not return zero");
    end
    axi_read(8'h2c, read_value);
    if (!read_value[2])
      fail("invalid map read was not reported");
    axi_read(8'h7c, read_value);
    if (read_value !== 1)
      fail("bridge read-error counter mismatch");

    axi_write(8'h30, 32'h0000_0001);
    wait_snapshot();
    axi_read(8'h38, read_value);
    if (read_value !== snapshot_generation_before + 1)
      fail("second snapshot generation mismatch");
    axi_read(8'h74, read_value);
    if (read_value !== 1)
      fail("source map-read error was not captured atomically");

    // Release bank zero, then prove that repeating the command is rejected by
    // the bridge before it can perturb the map core's own release counter.
    axi_write(8'h1c, 32'd0);
    axi_write(8'h28, 32'h0000_0001);
    timeout = 0;
    read_value = 32'hffff_ffff;
    while ((read_value[1] || irq) && timeout < 100) begin
      axi_read(8'h2c, read_value);
      timeout = timeout + 1;
    end
    if (timeout == 100 || read_value[3])
      fail("valid map release did not complete cleanly");
    axi_write(8'h28, 32'h0000_0001);
    timeout = 0;
    read_value = 0;
    while (!read_value[3] && timeout < 100) begin
      axi_read(8'h2c, read_value);
      timeout = timeout + 1;
    end
    if (timeout == 100)
      fail("invalid map release was not reported");
    axi_read(8'h80, read_value);
    if (read_value !== 1)
      fail("bridge release-error counter mismatch");

    // Flush crosses exactly once and does not alter the programmed enable.
    axi_write(8'h14, 32'h0000_0003);
    repeat (10) @(posedge map_clk);
    if (flush_pulse_count !== 1 || !acquisition_enable)
      fail("flush toggle or enable level contract failed");

    // A local map reset is an epoch boundary, but it is not the AXI bus reset.
    // Abort an in-flight MAP_DATA read with a bounded zero response, then
    // prove that enable, commands, snapshots, ready state, and IRQ cleared.
    @(negedge s_axi_aclk);
    s_axi_araddr = 8'h24;
    s_axi_arvalid = 1'b1;
    s_axi_rready = 1'b0;
    timeout = 0;
    while (!s_axi_arready && timeout < 100) begin
      @(posedge s_axi_aclk);
      timeout = timeout + 1;
    end
    if (timeout == 100)
      fail("reset-abort AXI read-address timeout");
    @(negedge s_axi_aclk);
    s_axi_arvalid = 1'b0;
    @(negedge map_clk);
    map_reset = 1'b1;
    timeout = 0;
    while (!s_axi_rvalid && timeout < 100) begin
      @(posedge s_axi_aclk);
      timeout = timeout + 1;
    end
    if (timeout == 100 || s_axi_rresp != 2'b00 || s_axi_rdata !== 0)
      fail("map reset did not abort an in-flight AXI read cleanly");
    @(negedge s_axi_aclk);
    s_axi_rready = 1'b1;
    @(negedge s_axi_aclk);
    s_axi_rready = 1'b0;
    repeat (8) @(posedge s_axi_aclk);
    @(negedge map_clk);
    map_reset = 1'b0;
    repeat (10) @(posedge s_axi_aclk);
    axi_read(8'h14, read_value);
    if (read_value !== 0 || acquisition_enable || irq)
      fail("map reset did not establish a clean control epoch");

    $display(
      "AXI_PHASE_MAP_PASS map_half_ns=%0d axi_half_ns=%0d map_phase_ns=%0d axi_phase_ns=%0d bins=%0d frames=%0d map_data_requests=%0d max_map_read_axi_cycles=%0d snapshots=2 split_writes=2 concurrent_rw=1 read_backpressure=1 reset_abort=1 read_errors=1 release_errors=1 flushes=%0d",
      MAP_HALF_PERIOD_NS, AXI_HALF_PERIOD_NS, MAP_INITIAL_DELAY_NS,
      AXI_INITIAL_DELAY_NS, PHASE_BINS, TILE_FRAMES, PHASE_BINS + 3,
      max_map_read_latency_cycles, flush_pulse_count
    );
    $finish;
  end

endmodule
