// Independent enabled-input/history/issue-delay ledger. Never uses the DUT's
// filter_issue, history_count or emitted counter to manufacture expected VALID.
  reg [31:0] source_words [0:12302], canonical_words [0:4095];
  reg [63:0] source_indexes [0:12302], canonical_indexes [0:4095];
  reg [31:0] pilot_words [0:511], pilot_mixed [0:4095], pilot_half [0:2047], pilot_all [0:682];
  reg [63:0] pilot_indexes [0:511], pilot_half_indexes [0:2047], pilot_all_indexes [0:682];
  reg pilot_support [0:682];
  integer source_checked=0, ingress_checked=0, canonical_count=0;
  integer enabled_raw=0, emitted_raw_model=0, ddc_history=0;
  integer pilot_accepted=0, pilot_mixed_count=0, pilot_half_count=0, pilot_all_count=0;
  integer admitted_count=0, delivered_count=0, stalled_cycles=0;
  reg [5:0] ddc_issue_pipe=0;
  reg issue_now, continuous_source=0, source_finished=0;
  reg prior_stalled=0;
  reg [31:0] held_data=0;
  reg [63:0] ddc_next_raw=RAW_FIRST;
  integer sink_fd;
  task automatic load_source_vectors;
    $readmemh("paired_source_ci16.mem",source_words);
    $readmemh("paired_source_index_u64.mem",source_indexes);
    $readmemh("canonical_ci16.mem",canonical_words);
    $readmemh("canonical_index_u64.mem",canonical_indexes);
    $readmemh("pilot_expected_ci16.mem",pilot_words);
    $readmemh("pilot_expected_index_u64.mem",pilot_indexes);
    $readmemh("pilot_mixed_ci16.mem",pilot_mixed);
    $readmemh("pilot_half_ci16.mem",pilot_half);
    $readmemh("pilot_half_index_u64.mem",pilot_half_indexes);
    $readmemh("pilot_all_ci16.mem",pilot_all);
    $readmemh("pilot_all_index_u64.mem",pilot_all_indexes);
    $readmemh("pilot_all_support_u1.mem",pilot_support);
    sink_fd=$fopen("paired_pilot_actual.ci16","wb");
    if (!sink_fd) fail("pilot binary sink unavailable");
  endtask
  task automatic source_range(input integer first,input integer count);
    for (integer s=first;s<first+count;s=s+1) begin
      @(negedge sample_clk); source_enable=1; sample_strobe=1;
      sample_index=source_indexes[s]; sample_data=source_words[s];
      if (s==8207 && (dut.conditioner_enable || native_capture_count!=260))
        fail("continuation began before disabled conditioner/complete native capture");
    end
    @(negedge sample_clk); sample_strobe=0;
  endtask
  always @(posedge sample_clk) if (resetn) begin
    if (continuous_source && !source_finished && (!source_enable || !sample_strobe))
      fail("unplanned original-source strobe gap during continuous region");
    if (source_enable && sample_strobe) begin
      if (source_checked>=12303 || sample_index!==RAW_FIRST-2+source_checked ||
          sample_index!==source_indexes[source_checked] || sample_data!==source_words[source_checked])
        fail("every original raw source index/CI16 mismatch");
      source_checked=source_checked+1;
    end
  end
  always @(posedge clk) if (resetn) begin
    if (dut.ingress_sample_valid) begin
      if (ingress_checked>=source_checked || ingress_checked>=12303 ||
          dut.ingress_sample_index!==source_indexes[ingress_checked] ||
          {dut.ingress_sample_q,dut.ingress_sample_i}!==source_words[ingress_checked] ||
          dut.ingress_sample_gap!==(ingress_checked==0)) fail("CDC delivery data/order/gap mismatch");
      if (ingress_checked<2 && dut.conditioner_enable) fail("prime beat entered enabled conditioner");
      ingress_checked=ingress_checked+1;
    end
    if (canonical_valid!==ddc_issue_pipe[5]) fail("independent enabled-prefix canonical VALID mismatch");
    if (canonical_valid) begin
      if (canonical_count>=4096 || canonical_gap || canonical_flush ||
          canonical_index!==canonical_indexes[canonical_count] ||
          {canonical_q,canonical_i}!==canonical_words[canonical_count])
        fail("canonical integer value/index/prefix mismatch");
      canonical_count=canonical_count+1;
    end
    issue_now=0;
    if (!dut.conditioner_enable || canonical_flush) begin ddc_history=0; ddc_issue_pipe=0; end
    else begin
      if (dut.ingress_sample_valid) begin
        if (dut.ingress_sample_gap || dut.ingress_sample_index!==ddc_next_raw)
          fail("enabled conditioner discontinuity in healthy source");
        issue_now=(ddc_history==14 && dut.ingress_sample_index[0]);
        if (ddc_history<14) ddc_history=ddc_history+1;
        ddc_next_raw=ddc_next_raw+1; enabled_raw=enabled_raw+1;
      end
      ddc_issue_pipe={ddc_issue_pipe[4:0],issue_now};
      if (ddc_issue_pipe[5]) emitted_raw_model=emitted_raw_model+1;
    end
    // All visible filter intermediate prefixes remain exact even at auto-stop.
    if (pilot.ddc.accept) pilot_accepted=pilot_accepted+1;
    if (pilot.ddc.mixed_valid) begin
      if (pilot_mixed_count>=4096 || {pilot.ddc.mixed_q,pilot.ddc.mixed_i}!==pilot_mixed[pilot_mixed_count] ||
          pilot.ddc.mixed_index!==PRE_FIRST+pilot_mixed_count || pilot.ddc.mixed_saturations)
        fail("pilot mixed word/index/saturation mismatch");
      pilot_mixed_count=pilot_mixed_count+1;
    end
    if (pilot.ddc.hb_valid) begin
      if (pilot_half_count>=2048 || {pilot.ddc.hb_q,pilot.ddc.hb_i}!==pilot_half[pilot_half_count] ||
          pilot.ddc.hb_index!==pilot_half_indexes[pilot_half_count] || pilot.ddc.hb_saturations)
        fail("pilot halfband word/index/saturation mismatch");
      pilot_half_count=pilot_half_count+1;
    end
    if (pilot.ddc_valid) begin
      if (pilot_all_count>=683 || {pilot.ddc_q,pilot.ddc_i}!==pilot_all[pilot_all_count] ||
          pilot.ddc_index!==pilot_all_indexes[pilot_all_count] ||
          pilot.ddc_support!==pilot_support[pilot_all_count] || pilot.ddc_visit!==VISIT)
        fail("pilot all-output word/index/support/visit mismatch");
      pilot_all_count=pilot_all_count+1;
    end
    if (pilot.push) begin
      if (admitted_count>=512 || pilot.capture_data!==pilot_words[admitted_count] ||
          pilot.capture_index!==pilot_indexes[admitted_count] || !pilot.capture_support || pilot.capture_visit!==VISIT)
        fail("selected pilot word/index/support/visit mismatch");
      admitted_count=admitted_count+1;
    end
    if (prior_stalled && (!pilot_valid || pilot_data!==held_data)) fail("pilot AXIS stalled promise changed");
    prior_stalled=pilot_valid && !pilot_ready; held_data=pilot_data;
    if (prior_stalled) stalled_cycles=stalled_cycles+1;
    if (pilot_valid && pilot_ready) begin
      if (delivered_count>=512 || pilot_data!==pilot_words[delivered_count]) fail("pilot AXIS bytes mismatch");
      $fwrite(sink_fd,"%c%c%c%c",pilot_data[7:0],pilot_data[15:8],pilot_data[23:16],pilot_data[31:24]);
      $display("HIGH_RATE30_PILOT_WORD ordinal=%0d newest=%016x word=%08x",delivered_count,pilot_indexes[delivered_count],pilot_data);
      delivered_count=delivered_count+1;
    end
    #0.001;
    if (dut.ddc_accepted_sample_count!==enabled_raw || dut.ddc_emitted_sample_count!==emitted_raw_model)
      fail("DDC independent accepted/emitted cumulative counter mismatch");
  end
