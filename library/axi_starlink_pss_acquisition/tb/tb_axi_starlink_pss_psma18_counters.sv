`timescale 1ns/1fs
// Actual wrapper/CDC/control. Acquisition core is explicitly INACTIVE.
// COUNTER_STAGE_SPECIMEN substitutes both DDC stage OUTPUT interfaces only;
// otherwise the unchanged real integer cascade is used. No FFT/STOP engine.
module tb_axi_starlink_pss_psma18_counters #(
  parameter integer NEW_MODE=1,
  parameter integer COUNTER_STAGE_SPECIMEN=0
);
  reg clk=0,sample_clk=0,resetn=0,sample_reset=1;
  always #5 clk=!clk;
  initial begin #2.1; forever #(500.0/60) sample_clk=!sample_clk; end
  reg sample_strobe=0,pilot_enable=0;
  reg [63:0] sample_index=0;
  reg signed [15:0] sample_i=0,sample_q=0;
  wire sample_enable=1,sample_gap=0;
  wire canonical_valid,canonical_gap,canonical_flush,irq;
  wire signed [15:0] canonical_i,canonical_q;
  wire [63:0] canonical_index;
  reg s_axi_awvalid=0,s_axi_wvalid=0,s_axi_bready=0;
  reg [7:0] s_axi_awaddr=0,s_axi_araddr=0;
  reg [31:0] s_axi_wdata=0;
  reg [3:0] s_axi_wstrb=0;
  wire s_axi_awready,s_axi_wready,s_axi_bvalid;
  wire [1:0] s_axi_bresp,s_axi_rresp;
  reg s_axi_arvalid=0,s_axi_rready=0;
  wire s_axi_arready,s_axi_rvalid;
  wire [31:0] s_axi_rdata;
  integer ingress=0,outputs=0;
  axi_starlink_pss_acquisition #(
    .INPUT_RATE_MSPS(60),.ENABLE_PILOT_TAP(1),.ENABLE_BANK60_PAIRED(NEW_MODE),
    .USE_SHARED_XFFT(NEW_MODE),.USE_REALTIME_XFFT(NEW_MODE),
    .USE_BANK_OWNED_XFFT(NEW_MODE),.ENABLE_BOUNDARY_STOP(NEW_MODE)
  ) dut (.sample_clk(sample_clk),.fft_clk(clk),.fft_resetn(resetn),
    .s_axi_aclk(clk),.s_axi_aresetn(resetn),.s_axi_awprot(3'd0),.s_axi_arprot(3'd0),.*);
  task automatic fail(input string message);
    $display("PSMA18_COUNTERS_FAIL %s new=%0d specimen=%0d ingress=%0d outputs=%0d stage1=%0d stage2=%0d public=%0d",
      message,NEW_MODE,COUNTER_STAGE_SPECIMEN,ingress,outputs,
      dut.g_rate_60.stage_60_discontinuity_count,dut.g_rate_60.stage_30_discontinuity_count,
      dut.ddc_discontinuity_count);
    $fatal(1);
  endtask
  task automatic idle(input integer count);
    repeat(count) @(negedge clk);
  endtask
  task automatic write_reg(input [7:0] address,input [31:0] value);
    integer timeout;
    @(negedge clk); s_axi_awaddr=address; s_axi_wdata=value; s_axi_wstrb=15;
    s_axi_awvalid=1; s_axi_wvalid=1; s_axi_bready=1; timeout=0;
    while (!(s_axi_awready===1 && s_axi_wready===1) && timeout<100) begin
      @(posedge clk); timeout=timeout+1;
    end
    if(timeout==100) fail("AXI write address timeout");
    @(negedge clk); s_axi_awvalid=0; s_axi_wvalid=0; timeout=0;
    while(s_axi_bvalid!==1 && timeout<100) begin @(posedge clk); timeout=timeout+1; end
    if(timeout==100 || s_axi_bresp!==0) fail("AXI write response");
    @(negedge clk); s_axi_bready=0;
  endtask
  task automatic expect_reg(input [7:0] address,input [31:0] expected);
    integer timeout;
    @(negedge clk); s_axi_araddr=address; s_axi_arvalid=1; s_axi_rready=1; timeout=0;
    while(s_axi_arready!==1 && timeout<100) begin @(posedge clk); timeout=timeout+1; end
    if(timeout==100) fail("AXI read address timeout");
    @(negedge clk); s_axi_arvalid=0; timeout=0;
    while(s_axi_rvalid!==1 && timeout<100) begin @(posedge clk); timeout=timeout+1; end
    if(timeout==100 || s_axi_rresp!==0 || s_axi_rdata!==expected) begin
      $display("PSMA18_COUNTERS_REG address=%02x actual=%08x expected=%08x",address,s_axi_rdata,expected);
      fail("AXI read response/value");
    end
    @(negedge clk); s_axi_rready=0;
  endtask
  task automatic epoch(input bit enabled);
    @(negedge clk); resetn=0; sample_reset=1; sample_strobe=0; pilot_enable=enabled;
    sample_i=0; sample_q=0; ingress=0; outputs=0;
    idle(10); resetn=1;
    @(negedge sample_clk); sample_reset=0;
    repeat(10) @(negedge sample_clk);
    expect_reg(8'he0,0); expect_reg(8'he4,0); expect_reg(8'he8,0); expect_reg(8'hec,0);
    if({dut.g_rate_60.stage_60_discontinuity_count,dut.g_rate_60.stage_30_discontinuity_count}!==0)
      fail("upstream reset did not clear both producers");
  endtask
  task automatic source_burst(input [63:0] first,input integer count);
    for(integer n=0;n<count;n=n+1) begin
      @(negedge sample_clk); sample_index=first+n; sample_strobe=1;
    end
    @(negedge sample_clk); sample_strobe=0; idle(80);
  endtask
  task automatic stage_counts(input [31:0] first,input [31:0] second);
    reg [32:0] wide;
    reg [31:0] expected;
    wide={1'b0,first}+{1'b0,second};
    expected=NEW_MODE ? (wide>33'h0ffffffff ? 32'hffffffff : wide[31:0]) : second;
    if(dut.g_rate_60.stage_60_discontinuity_count!==first ||
       dut.g_rate_60.stage_30_discontinuity_count!==second || dut.ddc_discontinuity_count!==expected)
      fail("stage-event sum or legacy second-stage-only semantics");
    expect_reg(8'he8,expected);
    if(NEW_MODE && expected!=0 && dut.phase_map_control.stop_conditioned_upstream_fault_now!==1)
      fail("visible stage-event fault absent at public STOP boundary");
  endtask
  task automatic specimen(input [31:0] first,input [31:0] second);
    epoch(1); source_burst({second,first},1); stage_counts(first,second);
    $display("PSMA18_STAGE_OUTPUT_SPECIMEN first=%08x second=%08x observed=%08x real_ddc=0 new=%0d",
      first,second,dut.ddc_discontinuity_count,NEW_MODE);
  endtask
  always @(posedge clk) if(resetn) begin
    if((^{dut.ingress_sample_valid,canonical_valid,canonical_gap,canonical_flush})===1'bx)
      fail("unknown public/cascade protocol");
    if(dut.ingress_sample_valid) ingress=ingress+1;
    if(canonical_valid) begin
      if(!COUNTER_STAGE_SPECIMEN && {canonical_i,canonical_q}!==0) fail("zero waveform arithmetic");
      outputs=outputs+1;
    end
  end
  initial begin
    epoch(1);
    expect_reg(8'h04,NEW_MODE ? 32'h10008 : 32'h10004);
    expect_reg(8'h10,NEW_MODE ? 32'h7ff : 32'hff);
    expect_reg(8'hb0,60); expect_reg(8'hb4,32'h020f0403);
    expect_reg(8'hb8,21); expect_reg(8'hbc,1073765335);
    if(COUNTER_STAGE_SPECIMEN) begin
      specimen(0,0); specimen(1,0); specimen(0,1); specimen(1,1);
      specimen(32'h7fffffff,32'h80000000); specimen(32'hffffffff,0);
      specimen(32'hffffffff,1); specimen(1,32'hffffffff);
      specimen(32'hffffffff,32'hffffffff);
      $display("PSMA18_COUNTER_SPECIMENS_PASS count=9 real_ddc=0 real_wrapper=1 new=%0d",NEW_MODE);
    end else begin
      // First real CDC reset marker reaches stage1 but no FIR output exists.
      source_burst(0,1); stage_counts(1,0);
      if(ingress!=1 || outputs!=0) fail("first-stage-only support");
      write_reg(8'h14,2); pilot_enable=0; idle(20); stage_counts(1,0);
      expect_reg(8'he0,1); expect_reg(8'he4,0);
      $display("PSMA18_REAL_FIRST_ONLY_PASS disable_before_propagation=1 new=%0d",NEW_MODE);
      epoch(1); source_burst(0,64); stage_counts(1,1);
      if(ingress!=64 || outputs!=5) fail("real propagated cascade counts");
      expect_reg(8'he0,64); expect_reg(8'he4,5);
      write_reg(8'h14,0); write_reg(8'h14,2); pilot_enable=0; idle(30); stage_counts(1,1);
      sample_reset=1; repeat(5) @(negedge sample_clk); sample_reset=0; idle(30);
      stage_counts(1,1); expect_reg(8'he0,64); expect_reg(8'he4,5);
      pilot_enable=1; idle(20); stage_counts(1,1);
      // Full upstream reset, separate two-beat disabled prelude, clean replay.
      epoch(0); source_burst(0,2); stage_counts(0,0);
      if(outputs!=0) fail("disabled prelude entered conditioner");
      pilot_enable=1; source_burst(2,64); stage_counts(0,0);
      if(ingress!=66 || outputs!=6 || dut.ingress_dropped_sample_count!==0)
        fail("clean real cascade replay counts");
      expect_reg(8'he0,64); expect_reg(8'he4,6); expect_reg(8'hec,0);
      expect_reg(8'hf0,0); expect_reg(8'hf4,0);
      epoch(0);
      $display("PSMA18_REAL_CASCADE_PASS checked_raw=131 canonical=11 first_only=1 propagated_both=1 disable_flush_retains=1 source_reset_retains=1 upstream_reset_clears=1 prime=2 new=%0d",NEW_MODE);
    end
    $display("PSMA18_COUNTERS_PASS inactive_core=1 fft=0 stop_engine=0 rf=0"); $finish;
  end
  initial begin #1000000; fail("bounded watchdog"); end
endmodule
