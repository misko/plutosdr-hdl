`timescale 1ns/1fs
// Actual native30 public wrapper and complete native engine, no FFT/PSMA/PIL1.
// Fixed original golden source only; this run precedes continuation freezing.
module tb_starlink_native30_budget #(parameter integer EARLY_OFF = 0);
  localparam [63:0] RAW_FIRST = 64'd17179867609;
  localparam integer SOURCE_COUNT = EARLY_OFF ? 3179 : 8205;
  reg clk = 0, sample_clk = 0, resetn = 0;
  wire fft_clk = clk;
  always #5 clk = !clk;
  initial begin #2.1; forever #(500.0/30) sample_clk = !sample_clk; end
  integer cycles = 0, source_checked = 0, source_off_compute_cycles = 0;
  always @(posedge clk) cycles = cycles + 1;
  reg source_enable = 0, sample_strobe = 0;
  reg [31:0] sample_data = 0, source_words [0:8204];
  reg [63:0] sample_index = 0;
  wire native_fft_active = 0, native_coarse_pilot_active = 0, coarse_stopped = 0;
  reg [7:0] awaddr [0:2], araddr [0:2];
  reg [31:0] wdata [0:2];
  reg [2:0] awvalid = 0, wvalid = 0, bready = 0, arvalid = 0, rready = 0;
  wire [2:0] awready, wready, bvalid, arready, rvalid;
  wire [1:0] bresp [0:2], rresp [0:2];
  wire [31:0] rdata [0:2];
  assign awready[1:0] = 0; assign wready[1:0] = 0; assign bvalid[1:0] = 0;
  assign arready[1:0] = 0; assign rvalid[1:0] = 0;
  task automatic fail(input string message);
    $display("NATIVE30_BUDGET_FAIL %s cycles=%0d source=%0d", message, cycles, source_checked);
    $fatal(1, "%s", message); $finish;
  endtask
  `include "high_rate_paired_axi.svh"
  `include "bank_native30_checks.svh"
  always @(posedge sample_clk) if (resetn && source_enable && sample_strobe) begin
    if (source_checked >= SOURCE_COUNT || sample_index !== RAW_FIRST + source_checked ||
        sample_data !== source_words[source_checked]) fail("native budget original-source mismatch");
    source_checked = source_checked + 1;
  end
  always @(posedge clk) if (resetn && !source_enable && native.i_core.i_raw_tracking_core.correlator_busy)
    source_off_compute_cycles = source_off_compute_cycles + 1;
  initial begin
    if (EARLY_OFF !== 0 && EARLY_OFF !== 1) fail("invalid budget profile");
    for (integer p = 0; p < 3; p = p + 1) begin awaddr[p] = 0; araddr[p] = 0; wdata[p] = 0; end
    $readmemh("source_ci16.mem", source_words);
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
        if (native_capture_count != 260 || !native.i_core.i_raw_tracking_core.correlator_busy)
          fail("source-off lacked complete capture and ongoing native compute witness");
      end
    join
    if (!native_done || source_checked != SOURCE_COUNT || source_off_compute_cycles < 1)
      fail("budget endpoint/inventory missing");
    $display("NATIVE30_SOURCE_OFF_PASS early=%0d source=%0d compute_without_source_cycles=%0d no_capture_abort=1", EARLY_OFF, source_checked, source_off_compute_cycles);
    $display("NATIVE30_ONLY_PASS actual_native30=1 actual_fft=0 actual_psma=0 actual_pil1=0 static_source=1");
    $finish;
  end
  initial begin #1000000; fail("native30 bounded watchdog"); end
endmodule
