`timescale 1ns/1ps

// Stage A: actual public shell/CDC/DDC, INACTIVE acquisition-core interface.
// No score, STOP-engine, native, PIL1, transform, or physical rate claim.
module tb_axi_starlink_pss_psma17_startup;
  reg sample_clk = 0, clk = 0, resetn = 0, sample_reset = 1;
  always #16.667 sample_clk = !sample_clk;
  always #5 clk = !clk;
  reg sample_strobe = 0, pilot_enable = 0;
  wire sample_enable = 1, sample_gap = 0;
  wire signed [15:0] sample_i = 0, sample_q = 0;
  reg [63:0] sample_index = 0;
  wire canonical_valid, canonical_gap, canonical_flush, irq;
  wire signed [15:0] canonical_i, canonical_q;
  wire [63:0] canonical_index;
  reg s_axi_awvalid = 0, s_axi_wvalid = 0, s_axi_bready = 0;
  reg [7:0] s_axi_awaddr = 0, s_axi_araddr = 0;
  reg [31:0] s_axi_wdata = 0;
  reg [3:0] s_axi_wstrb = 0;
  wire s_axi_awready, s_axi_wready, s_axi_bvalid;
  wire [1:0] s_axi_bresp, s_axi_rresp;
  reg s_axi_arvalid = 0, s_axi_rready = 0;
  wire s_axi_arready, s_axi_rvalid;
  wire [31:0] s_axi_rdata;
  integer observed = 0, ingress_observed = 0, ingress_gaps = 0;
  reg expect_gap = 0;
  reg [63:0] expected_first = 4;

  axi_starlink_pss_acquisition #(
    .INPUT_RATE_MSPS(30), .ENABLE_PILOT_TAP(1), .USE_SHARED_XFFT(1),
    .USE_REALTIME_XFFT(1), .USE_BANK_OWNED_XFFT(1), .ENABLE_BOUNDARY_STOP(1)
  ) dut (.sample_clk(sample_clk), .fft_clk(clk), .fft_resetn(resetn),
         .s_axi_aclk(clk), .s_axi_aresetn(resetn), .s_axi_awprot(3'd0),
         .s_axi_arprot(3'd0), .*);
  task automatic fail(input string message);
    $display("PSMA17_STARTUP_FAIL %s observed=%0d ingress=%0d gaps=%0d", message,
             observed, ingress_observed, ingress_gaps);
    $fatal(1);
  endtask
  always @(posedge clk) begin
    if (resetn && dut.ingress_sample_valid) begin
      if (dut.ingress_sample_index !== ingress_observed ||
          dut.ingress_sample_gap !== (ingress_observed == 0)) fail("CDC input identity/gap");
      ingress_observed = ingress_observed + 1;
      if (dut.ingress_sample_gap) ingress_gaps = ingress_gaps + 1;
    end
    if (resetn && canonical_valid) begin
      if ({canonical_i, canonical_q} !== 32'd0 ||
          canonical_index !== expected_first + observed ||
          canonical_gap !== (expect_gap && observed == 0)) fail("canonical identity/gap");
      observed = observed + 1;
    end
  end
  task automatic idle(input integer cycles);
    repeat (cycles) @(negedge clk);
  endtask
  task automatic axi_write(input [7:0] address, input [31:0] value);
    integer timeout;
    @(negedge clk); s_axi_awaddr = address; s_axi_wdata = value; s_axi_wstrb = 15;
    s_axi_awvalid = 1; s_axi_wvalid = 1; s_axi_bready = 1;
    timeout = 0;
    while (!(s_axi_awready && s_axi_wready) && timeout < 100) begin
      @(posedge clk); timeout = timeout + 1;
    end
    if (timeout == 100) fail("AXI write address timeout");
    @(negedge clk); s_axi_awvalid = 0; s_axi_wvalid = 0;
    timeout = 0;
    while (!s_axi_bvalid && timeout < 100) begin @(posedge clk); timeout = timeout + 1; end
    if (timeout == 100 || s_axi_bresp !== 0) fail("AXI write response");
    @(negedge clk); s_axi_bready = 0;
  endtask
  task automatic expect_register(input [7:0] address, input [31:0] expected);
    integer timeout;
    @(negedge clk); s_axi_araddr = address; s_axi_arvalid = 1; s_axi_rready = 1;
    timeout = 0;
    while (!s_axi_arready && timeout < 100) begin @(posedge clk); timeout = timeout + 1; end
    if (timeout == 100) fail("AXI read address timeout");
    @(negedge clk); s_axi_arvalid = 0;
    timeout = 0;
    while (!s_axi_rvalid && timeout < 100) begin @(posedge clk); timeout = timeout + 1; end
    if (timeout == 100 || s_axi_rresp !== 0 || s_axi_rdata !== expected) begin
      $display("PSMA17_STARTUP_REGISTER addr=%h got=%h expected=%h", address, s_axi_rdata, expected);
      fail("AXI read response/value");
    end
    @(negedge clk); s_axi_rready = 0;
  endtask
  task automatic epoch(input bit enabled, input bit gap, input integer first);
    @(negedge clk); resetn = 0; sample_reset = 1; sample_strobe = 0;
    pilot_enable = enabled; observed = 0; ingress_observed = 0; ingress_gaps = 0;
    expect_gap = gap; expected_first = first;
    idle(10); resetn = 1;
    @(negedge sample_clk); sample_reset = 0;
    repeat (10) @(negedge sample_clk);
  endtask
  task automatic source_burst(input integer first, input integer count);
    for (integer n = first; n < first + count; n = n + 1) begin
      @(negedge sample_clk); sample_index = n; sample_strobe = 1;
    end
    @(negedge sample_clk); sample_strobe = 0;
    idle(60);
  endtask
  initial begin
    // An immediately enabled DDC faithfully counts the CDC reset marker.
    epoch(1, 1, 4); source_burst(0, 32);
    if (observed !== 9 || ingress_observed !== 32 || ingress_gaps !== 1) fail("naive counts");
    expect_register(8'he0, 32); expect_register(8'he4, 9); expect_register(8'he8, 1);
    axi_write(8'h14, 2); pilot_enable = 0; idle(20);
    expect_register(8'he0, 32); expect_register(8'he4, 9); expect_register(8'he8, 1);
    // Source-only reset is not a DDC/PSMA counter reset.
    sample_reset = 1; repeat (5) @(negedge sample_clk); sample_reset = 0; idle(30);
    expect_register(8'he0, 32); expect_register(8'he4, 9); expect_register(8'he8, 1);

    // Reset all upstream state. Consume the first marker AND a clean beat
    // with both map and pilot disabled; only then enable the conditioner.
    epoch(0, 0, 5); source_burst(0, 2);
    if (observed !== 0 || ingress_observed !== 2 || ingress_gaps !== 1) fail("disabled priming");
    expect_register(8'he0, 0); expect_register(8'he4, 0); expect_register(8'he8, 0);
    @(negedge clk); pilot_enable = 1;
    source_burst(2, 32);
    if (observed !== 9 || ingress_observed !== 34 || ingress_gaps !== 1 ||
        dut.acquisition_enable || dut.ingress_dropped_sample_count !== 0)
      fail("primed pilot-only continuous counts");
    expect_register(8'he0, 32); expect_register(8'he4, 9); expect_register(8'he8, 0);
    expect_register(8'hec, 0); expect_register(8'hf0, 0); expect_register(8'hf4, 0);
    epoch(0, 0, 4);
    expect_register(8'he0, 0); expect_register(8'he4, 0); expect_register(8'he8, 0);
    $display("PSMA17_STARTUP_PASS real_shell=1 real_cdc=1 real_ddc=1 checked_raw=66 checked_canonical=18 prime=2 sample_only_reset_retains=1 upstream_reset_clears=1 inactive_core=1 fft=0");
    $finish;
  end
  initial begin #1000000; fail("bounded watchdog"); end
endmodule
