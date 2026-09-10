`timescale 1ns/1fs
// Non-FFT MODULE probe validating the independent enabled-prefix ledger and
// real PIL1 auto-stop with real native30 on the original source. No PSMA/bank
// module is substituted: neither is instantiated or claimed in this probe.
module tb_starlink_native30_conditioner_prefix;
  localparam [63:0] RAW_FIRST=64'd17179867609,PRE_FIRST=64'd8589933808;
  localparam [31:0] VISIT=32'h30000052;
  reg clk=0,sample_clk=0,resetn=0;
  wire fft_clk=clk;
  always #5 clk=!clk;
  initial begin #2.1; forever #(500.0/30) sample_clk=!sample_clk; end
  integer cycles=0;
  always @(posedge clk) cycles=cycles+1;
  reg source_enable=0,sample_strobe=0;
  reg [31:0] sample_data=0;
  reg [63:0] sample_index=0;
  wire canonical_valid,canonical_gap,pilot_enable,pilot_valid,pilot_irq;
  wire canonical_flush=0;
  wire signed [15:0] canonical_i,canonical_q;
  wire [63:0] canonical_index;
  wire [31:0] pilot_data;
  wire pilot_ready=(cycles%97)>=8;
  wire native_fft_active=0,native_coarse_pilot_active=0,coarse_stopped=0;
  reg [7:0] awaddr[0:2],araddr[0:2];
  reg [31:0] wdata[0:2];
  reg [2:0] awvalid=0,wvalid=0,bready=0,arvalid=0,rready=0;
  wire [2:0] awready,wready,bvalid,arready,rvalid;
  wire [1:0] bresp[0:2],rresp[0:2];
  wire [31:0] rdata[0:2];
  assign awready[0]=0; assign wready[0]=0; assign bvalid[0]=0;
  assign arready[0]=0; assign rvalid[0]=0;
  native30_conditioner_only dut(.*);
  axi_starlink_pilot_capture #(.INPUT_RATE_MSPS(30)) pilot (
    .canonical_valid(canonical_valid),.canonical_gap(canonical_gap),.canonical_flush(canonical_flush),
    .canonical_i(canonical_i),.canonical_q(canonical_q),.canonical_index(canonical_index),
    .pilot_enable(pilot_enable),.m_axis_tvalid(pilot_valid),.m_axis_tdata(pilot_data),
    .m_axis_tready(pilot_ready),.irq(pilot_irq),.s_axi_aclk(clk),.s_axi_aresetn(resetn),
    .s_axi_awaddr(awaddr[1]),.s_axi_awvalid(awvalid[1]),.s_axi_awready(awready[1]),
    .s_axi_wdata(wdata[1]),.s_axi_wstrb(4'hf),.s_axi_wvalid(wvalid[1]),.s_axi_wready(wready[1]),
    .s_axi_bvalid(bvalid[1]),.s_axi_bresp(bresp[1]),.s_axi_bready(bready[1]),
    .s_axi_araddr(araddr[1]),.s_axi_arvalid(arvalid[1]),.s_axi_arready(arready[1]),
    .s_axi_rvalid(rvalid[1]),.s_axi_rdata(rdata[1]),.s_axi_rresp(rresp[1]),.s_axi_rready(rready[1]),
    .s_axi_awprot(3'd0),.s_axi_arprot(3'd0));
  task automatic fail(input string message);
    $display("NATIVE30_CONDITIONER_FAIL %s cycle=%0d source=%0d ingress=%0d canonical=%0d model=%0d",message,cycles,source_checked,ingress_checked,canonical_count,emitted_raw_model);
    $fatal(1,"%s",message); $finish;
  endtask
  `include "high_rate_paired_axi.svh"
  `include "bank_native30_checks.svh"
  `include "bank_native30_source_checks.svh"
  always @(posedge clk) if (resetn && ({pilot.faults, pilot.ddc_fault, pilot.ddc_clips, pilot_irq,
      dut.ddc_discontinuity_count, dut.ddc_saturation_event_count, dut.ingress_overflow_sticky, dut.ingress_dropped_sample_count} !== 0))
    fail("real module health failure");
  initial begin
    for(integer p=0;p<3;p=p+1) begin awaddr[p]=0; araddr[p]=0; wdata[p]=0; end
    load_source_vectors();
    repeat(10) @(negedge clk); resetn=1;
    repeat(500) @(negedge clk); configure_native();
    source_range(0,2); wait(ingress_checked==2); repeat(30) @(negedge clk);
    if (canonical_count || enabled_raw || dut.ingress_sample_gap) fail("disabled prime failed");
    write_reg(1,8'h08,4); write_reg(1,8'h20,VISIT); write_reg(1,8'h9c,512); write_reg(1,8'h08,1);
    source_range(2,1549); wait(canonical_count==768); repeat(2000) @(negedge clk);
    if (enabled_raw!=1549 || emitted_raw_model!=768) fail("1549 raw preroll failed");
    fork
      run_native_command();
      begin
        @(negedge sample_clk); sample_strobe=1; sample_index=source_indexes[1551]; sample_data=source_words[1551];
        continuous_source=1;
        source_range(1552,12303-1552); source_finished=1; source_enable=0;
        if (!native_done || native_capture_count!=260) fail("source budget exhausted");
      end
    join
    wait(ingress_checked==12303); repeat(100) @(negedge clk);
    if (canonical_count>=4096 || canonical_count!=emitted_raw_model || admitted_count!=512 || delivered_count!=512 ||
        pilot_enable || !stalled_cycles || source_checked!=12303 || !native_done)
      fail("conditioner/native endpoint inventory");
    $fclose(sink_fd);
    $display("NATIVE30_CONDITIONER_PREFIX_PASS source=12303 ingress=12303 enabled_raw=%0d canonical=%0d pilot_accepted=%0d pilot_mixed=%0d pilot_half=%0d pilot_all=%0d pilot=512 native_raw=129 actual_fft=0 actual_psma=0",enabled_raw,canonical_count,pilot_accepted,pilot_mixed_count,pilot_half_count,pilot_all_count);
    $finish;
  end
  initial begin #1000000; fail("bounded module watchdog"); end
endmodule

// Explicit module composition, not a substitute acquisition wrapper or guard.
module native30_conditioner_only(
  input wire clk,sample_clk,resetn,source_enable,sample_strobe,pilot_enable,
  input wire [31:0] sample_data,input wire [63:0] sample_index,
  output wire canonical_valid,canonical_gap,
  output wire signed [15:0] canonical_i,canonical_q,output wire [63:0] canonical_index
);
  wire conditioner_enable=pilot_enable;
  wire ingress_sample_valid,ingress_sample_gap,ingress_overflow_sticky;
  wire signed [15:0] ingress_sample_i,ingress_sample_q;
  wire [63:0] ingress_sample_index,ddc_accepted_sample_count,ddc_emitted_sample_count;
  wire [31:0] ingress_dropped_sample_count,ddc_discontinuity_count,ddc_saturation_event_count;
  wire [7:0] ingress_fifo_level;
  starlink_pss_sample_cdc sample_cdc(
    .source_clk(sample_clk),.source_resetn(resetn),.source_sample_valid(source_enable&&sample_strobe),
    .source_sample_gap(1'b0),.source_sample_i(sample_data[15:0]),.source_sample_q(sample_data[31:16]),
    .source_sample_index(sample_index),.source_fifo_full(),.acquisition_clk(clk),.acquisition_resetn(resetn),
    .acquisition_sample_valid(ingress_sample_valid),.acquisition_sample_gap(ingress_sample_gap),
    .acquisition_sample_i(ingress_sample_i),.acquisition_sample_q(ingress_sample_q),
    .acquisition_sample_index(ingress_sample_index),.dropped_sample_count(ingress_dropped_sample_count),
    .overflow_sticky(ingress_overflow_sticky),.fifo_level(ingress_fifo_level),.maximum_fifo_level());
  starlink_pss_x2_ddc #(.EDGE_UPPER(1),.WIDE_OBSERVATION_COUNTERS(1)) conditioner(
    .clk(clk),.resetn(resetn),.enable(conditioner_enable),.flush(1'b0),
    .input_valid(ingress_sample_valid),.input_gap(ingress_sample_gap),.input_i(ingress_sample_i),
    .input_q(ingress_sample_q),.input_index(ingress_sample_index),.output_enable(),
    .output_valid(canonical_valid),.output_gap(canonical_gap),.output_i(canonical_i),.output_q(canonical_q),
    .output_index(canonical_index),.accepted_sample_count(ddc_accepted_sample_count),
    .emitted_sample_count(ddc_emitted_sample_count),.discontinuity_count(ddc_discontinuity_count),
    .saturation_event_count(ddc_saturation_event_count));
endmodule
