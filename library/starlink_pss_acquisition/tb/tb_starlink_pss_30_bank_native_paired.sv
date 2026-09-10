`timescale 1ns/1fs
// Explicit public StageA PSMA1.7 composition; ideal independent30/100/175 clocks.
// Healthy447x2 only. STATIC known center is not a causal coarse-guided command.
module tb_starlink_pss_30_bank_native_paired;
  localparam [63:0] FIRST=64'd8589934576, PRE_FIRST=64'd8589933808;
  localparam [63:0] RAW_FIRST=64'd17179867609, MAP_END=FIRST+894;
  localparam [31:0] VISIT=32'h30000052;
  reg clk=0,sample_clk=0,fft_clk=0,resetn=0;
  always #5 clk=!clk;
  initial begin #2.1; forever #(500.0/30) sample_clk=!sample_clk; end
  initial begin #1.3; forever #(500.0/175) fft_clk=!fft_clk; end
  reg source_enable=0,sample_strobe=0;
  reg [31:0] sample_data=0;
  reg [63:0] sample_index=0;
  wire canonical_valid,canonical_gap,canonical_flush,pilot_enable;
  wire signed [15:0] canonical_i,canonical_q;
  wire [63:0] canonical_index;
  wire pss_irq,pilot_irq,pilot_valid;
  wire [31:0] pilot_data;
  integer cycles=0,ack_count=0,map_reads=0,pilot_at_stop=-1,canonical_at_stop=-1;
  integer source_at_stop=-1,source_at_native_release=-1,source_at_map_release=-1;
  reg coarse_stopped=0,map_retained=0,map_released=0;
  wire pilot_ready=(cycles%97)>=8;
  reg [7:0] awaddr[0:2],araddr[0:2];
  reg [31:0] wdata[0:2];
  reg [2:0] awvalid=0,wvalid=0,bready=0,arvalid=0,rready=0;
  wire [2:0] awready,wready,bvalid,arready,rvalid;
  wire [1:0] bresp[0:2],rresp[0:2];
  wire [31:0] rdata[0:2];

  axi_starlink_pss_acquisition #(.INPUT_RATE_MSPS(30),.ENABLE_PILOT_TAP(1),
    .USE_SHARED_XFFT(1),.USE_REALTIME_XFFT(1),.ENABLE_BOUNDARY_STOP(1),.USE_BANK_OWNED_XFFT(1)) dut (
    .sample_clk(sample_clk),.sample_reset(!resetn),.fft_clk(fft_clk),.fft_resetn(resetn),
    .sample_strobe(sample_strobe),.sample_enable(source_enable),.sample_gap(1'b0),
    .sample_i(sample_data[15:0]),.sample_q(sample_data[31:16]),.sample_index(sample_index),
    .pilot_enable(pilot_enable),.canonical_valid(canonical_valid),.canonical_gap(canonical_gap),
    .canonical_flush(canonical_flush),.canonical_i(canonical_i),.canonical_q(canonical_q),
    .canonical_index(canonical_index),.irq(pss_irq),.s_axi_aclk(clk),.s_axi_aresetn(resetn),
    .s_axi_awaddr(awaddr[0]),.s_axi_awvalid(awvalid[0]),.s_axi_awready(awready[0]),
    .s_axi_wdata(wdata[0]),.s_axi_wstrb(4'hf),.s_axi_wvalid(wvalid[0]),.s_axi_wready(wready[0]),
    .s_axi_bvalid(bvalid[0]),.s_axi_bresp(bresp[0]),.s_axi_bready(bready[0]),
    .s_axi_araddr(araddr[0]),.s_axi_arvalid(arvalid[0]),.s_axi_arready(arready[0]),
    .s_axi_rvalid(rvalid[0]),.s_axi_rdata(rdata[0]),.s_axi_rresp(rresp[0]),.s_axi_rready(rready[0]),
    .s_axi_awprot(3'd0),.s_axi_arprot(3'd0));
  // Only map geometry is test-overridden. Bank/rate/STOP uses the public guard.
  defparam dut.acquisition.PHASE_BINS=447;
  defparam dut.acquisition.TILE_FRAMES=2;
  defparam dut.acquisition.MAP_SEGMENT_ADDRESS_WIDTH=9;
  defparam dut.acquisition.MAP_SEGMENT_COUNT=1;
  defparam dut.acquisition.MAP_SEGMENT_INDEX_WIDTH=1;
  defparam dut.phase_map_control.PHASE_BINS=447;
  defparam dut.phase_map_control.TILE_FRAMES=2;

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
    $display("HIGH_RATE30_FAIL %s cycles=%0d source=%0d canonical=%0d scores=%0d admitted=%0d pilot=%0d health=%08x",message,cycles,source_checked,canonical_count,score_count,dut.accepted_score_count,delivered_count,dut.detector_health_flags);
    $fatal(1,"%s",message); $finish;
  endtask
  `include "high_rate_paired_axi.svh"
  `include "bank_native30_checks.svh"
  `include "bank_native30_source_checks.svh"
  `include "bank_native30_fft_checks.svh"
  task automatic healthy;
    if ({dut.detector_health_flags, dut.ddc_discontinuity_count, dut.ddc_saturation_event_count,
        dut.discontinuity_abort_count, dut.discarded_score_count, dut.map_counter_fault,
        dut.map_overrun_count, dut.score_protocol_error_count, dut.map_arithmetic_overflow_count,
        dut.map_read_error_count, dut.map_release_error_count, dut.ingress_overflow_sticky,
        dut.ingress_dropped_sample_count, dut.phase_map_control.bridge_read_error_count,
        dut.phase_map_control.bridge_release_error_count, dut.phase_map_control.snapshot_request_overrun_count,
        canonical_flush, pilot.faults, pilot.ddc_fault, pilot.ddc_clips, pilot_irq} !== 0)
      fail("unexpected healthy public acquisition/PIL1 failure");
  endtask
  task automatic stop_word(input integer index,input [31:0] expected);
    write_reg(0,8'hfc,index); expect_reg(0,8'hfc,expected);
  endtask
  task automatic retained_terminal;
    stop_word(0,32'h50535354); stop_word(1,32'h0001000c); stop_word(2,32'h16); stop_word(3,2); stop_word(4,2); stop_word(5,1);
    stop_word(6,FIRST[31:0]); stop_word(7,FIRST[63:32]);
    stop_word(8,MAP_END[31:0]); stop_word(9,MAP_END[63:32]); stop_word(10,0);
  endtask
  always @(posedge clk) begin
    cycles=cycles+1;
    if (cycles>100000) fail("bounded1ms watchdog");
    if (resetn) begin
      healthy();
      if (dut.map_read_request && (dut.map_read_index[14:9]!==0 || dut.map_read_index>=447))
        fail("outer15-bit map index padding/geometry");
      if (map_retained && (dut.map_ready_mask!==1 || !pss_irq || dut.map_generation_0!==1 ||
          dut.map_start_index_0!==FIRST || dut.map_publish_count!==1 || dut.accepted_score_count!==894))
        fail("retained map ownership changed during independent native result lifetime");
      if (coarse_stopped && (dut.acquisition_enable || dut.accepted_score_count!==894 || dut.map_publish_count!==1))
        fail("coarse restarted or extra score entered map after STOP");
      if (dut.stop_ack) begin
        ack_count=ack_count+1;
        if (ack_count==2) begin
          if (!pilot_enable || native_done || dut.accepted_score_count!==894 || score_count<894)
            fail("STOP lacked selected prefix and independent pilot/native lifetime");
          coarse_stopped=1; pilot_at_stop=delivered_count; canonical_at_stop=canonical_count;
          source_at_stop=source_checked;
          $display("HIGH_RATE30_STOP selected=894 visible=%0d source=%0d canonical=%0d pilot=%0d native_capture=%0d native_busy=%0d",score_count,source_checked,canonical_count,delivered_count,native_capture_count,native.i_core.i_raw_tracking_core.correlator_busy);
        end else if (ack_count!=1) fail("duplicate STOP acknowledgement");
      end
    end
  end
  task automatic map_stop_read_release;
    wait(score_count>=200); write_reg(0,8'hf8,2);
    wait(dut.phase_map_control.stop_terminal_valid); @(negedge clk);
    retained_terminal();
    if (ack_count!=2 || dut.map_ready_mask!==1 || dut.map_generation_0!==1 || native_done)
      fail("complete map was not retained before native completion");
    map_retained=1;
    write_reg(0,8'h1c,0); write_reg(0,8'h20,0);
    for (integer p=0;p<447;p=p+1) begin
      expect_reg(0,8'h24,{16'd0,map_words[p]}); map_reads=map_reads+1;
    end
    wait(native_done); @(negedge clk);
    source_at_native_release=source_checked;
    if (!map_retained || !pss_irq || native_irq || native.result_available || !source_enable)
      fail("native public release did not preserve independent retained map/source");
    $display("HIGH_RATE30_RETENTION_PASS map_retained_through_native_release=1 native_result_released=1 map_words=447 source=%0d",source_checked);
    // Clear only bench ownership expectation immediately before PUBLIC release.
    map_retained=0; write_reg(0,8'h28,1); repeat(24) @(negedge clk);
    if (dut.map_ready_mask || pss_irq || dut.map_publish_count!=1) fail("public map release failed");
    map_released=1; source_at_map_release=source_checked;
  endtask

  reg [31:0] snapshot[0:25],generation;
  integer n;
  initial begin
    for(n=0;n<3;n=n+1) begin awaddr[n]=0; araddr[n]=0; wdata[n]=0; end
    load_source_vectors(); load_fft_vectors();
    if (dut.acquisition.PHASE_INDEX_WIDTH!=15 || dut.phase_map_control.PHASE_INDEX_WIDTH!=15 ||
        dut.acquisition.phase_map.i_map_bank_0.DEPTH!=447 || dut.acquisition.phase_map.i_map_bank_1.DEPTH!=447 ||
        dut.acquisition.COEFFICIENT_ENERGY!=1073744004 || !dut.acquisition.USE_BANK_OWNED_XFFT)
      fail("actual module geometry/conditioned kernel energy/bank identity");
    repeat(10) @(negedge clk); resetn=1;
    repeat(500) @(negedge clk); configure_native();
    source_range(0,2); wait(ingress_checked==2); repeat(30) @(negedge clk);
    if (canonical_count || canonical_valid || dut.ingress_sample_gap || dut.ingress_fifo_level || enabled_raw)
      fail("two disabled-DDC prime beats did not drain the real CDC startup gap");
    expect_reg(0,8'h00,32'h50534d41); expect_reg(0,8'h04,32'h10007);
    expect_reg(0,8'h08,447); expect_reg(0,8'h0c,32'h21002); expect_reg(0,8'h10,32'h7ff);
    expect_reg(0,8'hb0,30); expect_reg(0,8'hb4,32'h000f0203);
    expect_reg(0,8'hb8,7); expect_reg(0,8'hbc,1073744004);
    expect_reg(1,8'h00,32'h50494c31); expect_reg(1,8'h04,32'h10000);
    expect_reg(1,8'h14,30000000); expect_reg(1,8'h18,2500000); expect_reg(1,8'h1c,12);
    expect_reg(1,8'h24,1); expect_reg(1,8'h28,269); expect_reg(1,8'h2c,538);
    write_reg(0,8'h14,1); write_reg(1,8'h08,4); write_reg(1,8'h20,VISIT);
    write_reg(1,8'h9c,512); write_reg(1,8'h08,1); write_reg(0,8'hf8,1);
    wait(dut.phase_map_control.stop_terminal_valid); @(negedge clk);
    stop_word(2,6); stop_word(4,1); stop_word(5,0);
    if (ack_count!=1 || dut.acquisition_enable || !pilot_enable || score_count)
      fail("empty STOP disturbed independently armed pilot");
    source_range(2,1549); wait(canonical_count==768); repeat(2000) @(negedge clk);
    if (enabled_raw!=1549 || emitted_raw_model!=768 || !pilot_enable || admitted_count<1 ||
        dut.ingress_fifo_level || native_capture_count) fail("raw1549/canonical768 preroll inventory");
    $display("HIGH_RATE30_PREROLL_PASS disabled_prime=2 original_raw=1549 canonical=768 public_psma=00010007 caps=000007ff native_taps=132");
    write_reg(0,8'h14,1); repeat(20) @(negedge clk);
    fork
      begin
        // First offered beat is set before enabling the strict cadence check.
        @(negedge sample_clk); sample_strobe=1; sample_index=source_indexes[1551]; sample_data=source_words[1551];
        continuous_source=1;
        source_range(1552,12303-1552);
        source_finished=1; source_enable=0;
        if (source_checked!=12303 || native_capture_count!=260 || !native_done)
          fail("frozen source/tail exhausted before bounded native readout");
      end
      run_native_command();
      map_stop_read_release();
    join
    wait(ingress_checked==12303); wait(!pilot_enable && delivered_count==512);
    repeat(100) @(negedge clk);
    if (!map_released || ack_count!=2 || map_reads!=447 || score_count<894 || score_count>1341 ||
        forward_input_count<1024 || inverse_input_count<1024 || forward_count<1024 || product_count<1024 ||
        inverse_count<1024 || prepare_count<894 || ratio_count<894 || quiet_cycles<32 ||
        !native_capture_fft_overlap || !native_compute_overlap || !native_compute_after_stop ||
        pilot_at_stop<1 || pilot_at_stop>=512 || canonical_count<=canonical_at_stop+512 ||
        canonical_count>=4096 || canonical_count!=emitted_raw_model || dut.conditioner_enable ||
        admitted_count!=512 || stalled_cycles<1 || source_at_map_release>=12303 ||
        source_at_native_release<=source_at_stop)
      fail("paired overlap/continuation/quiescence/prefix inventory");
    retained_terminal();
    expect_reg(0,8'he0,enabled_raw); expect_reg(0,8'he4,emitted_raw_model);
    expect_reg(0,8'hf0,0); expect_reg(0,8'hf4,0); expect_reg(0,8'he8,0); expect_reg(0,8'hec,0);
    write_reg(1,8'h08,8); read_reg(1,8'h98,generation);
    if (generation!=1) fail("PIL1 snapshot generation identity");
    for(n=0;n<26;n=n+1) read_reg(1,8'h30+4*n,snapshot[n]);
    expect_reg(1,8'h98,generation);
    if ({snapshot[1],snapshot[0]}!==pilot_indexes[0] || {snapshot[3],snapshot[2]}!==pilot_indexes[511] ||
        {snapshot[5],snapshot[4]}!=512 || {snapshot[7],snapshot[6]}!=512 ||
        {snapshot[9],snapshot[8]}!=90 || {snapshot[11],snapshot[10]}!=0 ||
        {snapshot[13],snapshot[12]}!=pilot_accepted || {snapshot[15],snapshot[14]}!=pilot_all_count ||
        snapshot[16] || snapshot[17][7:0] || snapshot[18] || snapshot[19]!=24 || snapshot[20]!==VISIT ||
        snapshot[22] || snapshot[23] || snapshot[24] || snapshot[25]) fail("PIL1 coherent snapshot inventory/health");
    $write("HIGH_RATE30_PIL1_SNAPSHOT generation=%0d raw_words=",generation);
    for(n=0;n<26;n=n+1) $write(" %08x",snapshot[n]); $write("\n");
    healthy(); native_healthy(); $fclose(sink_fd);
    $display("HIGH_RATE30_PREFIX source=12303 ingress=12303 enabled_raw=%0d canonical=%0d pilot_accepted=%0d pilot_mixed=%0d pilot_half=%0d pilot_all=%0d forward_input=%0d forward=%0d product=%0d inverse_input=%0d inverse=%0d prepare=%0d ratio=%0d visible_scores=%0d admitted_scores=894",enabled_raw,canonical_count,pilot_accepted,pilot_mixed_count,pilot_half_count,pilot_all_count,forward_input_count,forward_count,product_count,inverse_input_count,inverse_count,prepare_count,ratio_count,score_count);
    $display("HIGH_RATE30_OVERLAP capture_actual_fft=%0d compute_coarse_pilot=%0d compute_after_stop=%0d bank_quiet_fast_cycles=%0d source_at_stop=%0d source_at_native_release=%0d source_at_map_release=%0d",native_capture_fft_overlap,native_compute_overlap,native_compute_after_stop,quiet_cycles,source_at_stop,source_at_native_release,source_at_map_release);
    $display("HIGH_RATE30_PASS profile=30-upper-bank175-native132-pil1-447x2-healthy-v1 admitted=894 map_words=447 capture=260 raw_tuples=129 qualified_tuples=121 packet_words=26 packet_reads=52 pilot_words=512 bytes=2048 source=12303 STATIC_NOT_CAUSAL_NO_RF_DMA_IIO_PHYSICAL_OR_PRODUCTION_MAP_CLAIM");
    $finish;
  end
endmodule
