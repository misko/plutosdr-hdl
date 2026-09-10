`timescale 1ns/1fs
// Native60 only. No PSMA, FFT, PIL1, overrides, injected tuples or hierarchy writes.
// Static known-center source/limits were committed before service evaluation.
module tb_starlink_native60_budget;
  localparam [63:0] RAW_FIRST = 64'd34359735211;
  localparam integer SOURCE_COUNT = 16423;
  reg clk = 0, sample_clk = 0, resetn = 0;
  always #5 clk = !clk;
  initial begin #2.1; forever #(500.0/60) sample_clk = !sample_clk; end
  integer cycles = 0, source_checked = 0, source_off_cycle = -1;
  integer source_off_compute_cycles = 0, source_edges = 0, source_off_edge = -1;
  integer quiet_start = -1, quiet_end = -1, quiet_edges = -1;
  integer source_fd, source_started = 0;
  realtime previous_edge = 0, first_edge = 0, first_fall = 0, previous_rise = 0, previous_control = 0;
  realtime observed_half = 0, observed_period = 0, observed_control = 0;
  reg source_enable = 0, sample_strobe = 0;
  reg [31:0] sample_data = 0, source_words [0:16422];
  reg [63:0] sample_index = 0, source_indexes [0:16422];
  reg [7:0] awaddr [0:2], araddr [0:2];
  reg [31:0] wdata [0:2];
  reg [2:0] awvalid = 0, wvalid = 0, bready = 0, arvalid = 0, rready = 0;
  wire [2:0] awready, wready, bvalid, arready, rvalid;
  wire [1:0] bresp [0:2], rresp [0:2];
  wire [31:0] rdata [0:2];
  assign awready[1:0] = 0; assign wready[1:0] = 0; assign bvalid[1:0] = 0;
  assign arready[1:0] = 0; assign rvalid[1:0] = 0;
  task automatic fail(input string message);
    $display("NATIVE60_FAIL %s cycles=%0d source=%0d", message, cycles, source_checked);
    $fatal(1, "%s", message);
  endtask
  task automatic close_time(input realtime actual, input realtime expected);
    if (actual < expected - 0.000001 || actual > expected + 0.000001)
      fail($sformatf("clock mismatch actual_ns=%0.9f expected_ns=%0.9f", actual, expected));
  endtask
  always @(sample_clk) if ($realtime > 0) begin
    if (previous_edge == 0) begin
      first_edge = $realtime; close_time(first_edge, 10.433333);
    end else begin
      observed_half = $realtime - previous_edge; close_time(observed_half, 8.333333);
    end
    previous_edge = $realtime;
  end
  always @(posedge sample_clk) begin
    source_edges = source_edges + 1;
    if (previous_rise != 0) begin
      observed_period = $realtime - previous_rise; close_time(observed_period, 16.666666);
    end
    previous_rise = $realtime;
  end
  always @(negedge sample_clk) if ($realtime > 0 && first_fall == 0) begin
    first_fall = $realtime; close_time(first_fall, 18.766666);
  end
  always @(posedge clk) begin
    cycles = cycles + 1;
    if (previous_control != 0) begin
      observed_control = $realtime - previous_control; close_time(observed_control, 10.0);
    end
    previous_control = $realtime;
    if (cycles >= 160000) fail("frozen global control-cycle watchdog");
  end
  `include "high_rate_paired_axi.svh"
  `include "native60_budget_checks.svh"
  always @(posedge sample_clk) if (resetn && native_configured) begin
    if ({source_enable, sample_strobe} !== 2'b00 &&
        {source_enable, sample_strobe} !== 2'b11) fail("unknown/unequal source flags");
    if (source_started && source_checked < SOURCE_COUNT &&
        {source_enable, sample_strobe} !== 2'b11) fail("source cadence gap");
    if (source_enable === 1'b1) begin
      source_started = 1;
      if (source_checked >= SOURCE_COUNT || sample_index !== RAW_FIRST + source_checked ||
          sample_index !== source_indexes[source_checked] || sample_data !== source_words[source_checked])
        fail("original raw source/index/packing mismatch");
      $fdisplay(source_fd, "%016x %08x", sample_index, sample_data);
      source_checked = source_checked + 1;
    end
  end
  always @(posedge clk) if (resetn && native_configured && source_off_cycle >= 0 &&
      native.i_core.i_raw_tracking_core.correlator_busy === 1'b1)
    source_off_compute_cycles = source_off_compute_cycles + 1;
  initial begin
    for (integer p = 0; p < 3; p = p + 1) begin awaddr[p] = 0; araddr[p] = 0; wdata[p] = 0; end
    $readmemh("source_ci16.mem", source_words); $readmemh("source_index_u64.mem", source_indexes);
    source_fd = $fopen("native60_actual_source.txt", "w");
    if (!source_fd) fail("source log unavailable");
    repeat (10) @(negedge clk); resetn = 1;
    repeat (500) @(negedge clk); configure_native();
    fork
      run_native_command();
      begin
        for (integer n = 0; n < SOURCE_COUNT; n = n + 1) begin
          @(negedge sample_clk); source_enable = 1; sample_strobe = 1;
          sample_data = source_words[n]; sample_index = RAW_FIRST + n;
        end
        @(negedge sample_clk); source_enable = 0; sample_strobe = 0;
        source_off_cycle = cycles; source_off_edge = source_edges;
        if (source_checked != SOURCE_COUNT || native_capture_count != 520 ||
            native.i_core.i_raw_tracking_core.correlator_busy !== 1'b1)
          fail("source-off lacks full source/capture and ongoing compute");
        $display("NATIVE60_SOURCE_OFF cycle=%0d source=16423 first=34359735211 stop=34359751634 capture=520 busy=1", cycles);
      end
    join
    wait(native_drain_cycle >= 0); @(negedge clk);
    if (native_released !== 1'b1 || source_checked != SOURCE_COUNT ||
        source_off_compute_cycles < 1 || native_raw_count != 257 || native_qualified_count != 241 ||
        native_capture_count != 520 || native_admissions != 1 || native_packet_reads != 52)
      fail("final exact inventory incomplete");
    quiet_start = cycles; quiet_edges = source_edges;
    repeat (256) begin @(negedge clk); native_quiet(); end
    quiet_end = cycles; quiet_edges = source_edges - quiet_edges;
    if (quiet_end - quiet_start != 256 || quiet_edges < 152 || quiet_edges > 155)
      fail("no-stale duration or continuing sample clock mismatch");
    native_healthy();
    $fclose(source_fd); $fclose(native_raw_fd); $fclose(native_capture_fd); $fclose(native_hold_fd);
    $display("NATIVE60_BUDGET capture_end=%0d publish=%0d drain=%0d release=%0d source_off=%0d quiet_start=%0d quiet_end=%0d raw_at_publish=%0d raw_after_publish=%0d maximum_axi=%0d readout_transactions=%0d source_off_compute=%0d maximum_tuple_hold=%0d",
      native_capture_end_cycle, native_publish_cycle, native_drain_cycle, native_release_cycle,
      source_off_cycle, quiet_start, quiet_end, native_raw_at_publish, native_raw_after_publish,
      maximum_axi_cycles, native_readout_transactions, source_off_compute_cycles, native_maximum_hold);
    $display("NATIVE60_CLOCK first_edge_fs=%0.0f first_fall_fs=%0.0f half_fs=%0.0f period_fs=%0.0f control_period_fs=%0.0f source_edges=%0d after_off_edges=%0d quiet_edges=%0d",
      first_edge*1000000.0, first_fall*1000000.0, observed_half*1000000.0, observed_period*1000000.0,
      observed_control*1000000.0, source_edges, source_edges-source_off_edge, quiet_edges);
    $display("NATIVE60_PASS source=16423 capture=520 raw=257 qualified=241 packet_reads=52 admissions=1 health=0 source_stopped=1 clock_running=1 idle=1 irq=0 available=0 actual_native=1 actual_fft=0 actual_psma=0 actual_pil1=0 static_center=1");
    $finish;
  end
endmodule
