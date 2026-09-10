// Independent two-stage enabled-prefix ledger. No DUT filter_issue/history/valid
// creates expected tokens. Public programmed/STOP/pilot512 control mirrors are
// checked first; both integer stage outputs remain frozen cohort comparisons.
  reg [31:0] source_words[0:16424],canonical_words[0:4095],stage30_words[0:8204];
  reg [63:0] source_indexes[0:16424],canonical_indexes[0:4095],stage30_indexes[0:8204];
  reg [33:0] first_mixed[0:16422],second_mixed[0:8204];
  reg [31:0] pilot_words[0:511],pilot_mixed[0:4095],pilot_half[0:2047],pilot_all[0:682];
  reg [63:0] pilot_indexes[0:511],pilot_half_indexes[0:2047],pilot_all_indexes[0:682];
  reg pilot_support[0:682];
  integer source_checked=0,ingress_checked=0,canonical_count=0,stage30_count=0;
  integer enabled_raw=0,stage30_accepted=0,stage30_emitted_model=0,emitted_raw_model=0;
  integer first_history=0,second_history=0,continuous_checked=0;
  integer pilot_accepted=0,pilot_mixed_count=0,pilot_half_count=0,pilot_all_count=0;
  integer admitted_count=0,delivered_count=0,stalled_cycles=0;
  reg [5:0] first_pipe=0,second_pipe=0;
  reg checked_enable,first_output_now,first_issue,second_issue;
  reg [63:0] first_index_now;
  reg continuous_source=0,source_finished=0,prior_stalled=0;
  reg [31:0] held_data=0;
  realtime continuous_first_time=0,last_continuous_time=0;
  integer sink_fd,source_fd,prime_fd;
  task automatic load_source_vectors;
    $readmemh("paired_source_ci16.mem",source_words);
    $readmemh("paired_source_index_u64.mem",source_indexes);
    $readmemh("canonical_ci16.mem",canonical_words); $readmemh("canonical_index_u64.mem",canonical_indexes);
    $readmemh("ddc60_to30_ci16.mem",stage30_words); $readmemh("ddc60_to30_index_u64.mem",stage30_indexes);
    $readmemh("ddc60_to30_mixed_s17.mem",first_mixed); $readmemh("ddc30_to15_mixed_s17.mem",second_mixed);
    $readmemh("pilot_expected_ci16.mem",pilot_words); $readmemh("pilot_expected_index_u64.mem",pilot_indexes);
    $readmemh("pilot_mixed_ci16.mem",pilot_mixed); $readmemh("pilot_half_ci16.mem",pilot_half);
    $readmemh("pilot_half_index_u64.mem",pilot_half_indexes); $readmemh("pilot_all_ci16.mem",pilot_all);
    $readmemh("pilot_all_index_u64.mem",pilot_all_indexes); $readmemh("pilot_all_support_u1.mem",pilot_support);
    sink_fd=$fopen("paired_pilot_actual.ci16","wb"); source_fd=$fopen("native60_actual_source.txt","w");
    prime_fd=$fopen("paired60_actual_prime.txt","w");
    if(!sink_fd || !source_fd || !prime_fd) fail("source/pilot evidence sink unavailable");
  endtask
  task automatic source_range(input integer first,input integer count);
    for(integer s=first;s<first+count;s=s+1) begin
      @(negedge sample_clk); source_enable=1; sample_strobe=1;
      sample_index=source_indexes[s]; sample_data=source_words[s];
    end
    @(negedge sample_clk); sample_strobe=0;
  endtask
  always @(posedge sample_clk) if(resetn) begin
    if((^{source_enable,sample_strobe})===1'bx) fail("unknown original source protocol");
    if(continuous_source && !source_finished && {source_enable,sample_strobe}!==2'b11)
      fail("unplanned source gap in13312-sample continuous segment");
    if(source_enable===1'b1 && sample_strobe===1'b1) begin
      if(source_checked>=16425 || sample_index!==RAW_FIRST-2+source_checked ||
          sample_index!==source_indexes[source_checked] || sample_data!==source_words[source_checked])
        fail("every original raw source/index/CI16 mismatch");
      if(source_checked<2) $fdisplay(prime_fd,"%016x %08x",sample_index,sample_data);
      else $fdisplay(source_fd,"%016x %08x",sample_index,sample_data);
      if(continuous_source) begin
        if(continuous_checked==0) continuous_first_time=$realtime;
        close_time($realtime-continuous_first_time,continuous_checked*16.666666);
        if(sample_index!==64'd34359738322+continuous_checked || source_checked!=3113+continuous_checked)
          fail("continuous segment index/edge relation");
        continuous_checked=continuous_checked+1; last_continuous_time=$realtime;
      end
      source_checked=source_checked+1;
    end
  end
  always @(negedge source_enable) if(resetn && source_finished) begin
    if(continuous_checked!=13312 || source_checked!=16425) fail("finite source exhausted early");
    close_time($realtime-last_continuous_time,8.333333);
    $display("HIGH_RATE60_CONTINUOUS count=13312 first=34359738322 stop=34359751634 first_rise_fs=%0.0f last_rise_fs=%0.0f off_fs=%0.0f startup_pause_outside_segment=1",
      continuous_first_time*1000000.0,last_continuous_time*1000000.0,$realtime*1000000.0);
  end
  always @(posedge clk) if(resetn) begin
    checked_enable=expected_coarse_enable || expected_pilot_enable;
    if(!control_transition && (dut.conditioner_enable!==checked_enable || pilot_enable!==expected_pilot_enable))
      fail("conditioner/pilot enable differs from independent public control mirrors");
    if(control_transition && dut.conditioner_enable!==checked_enable &&
        ({dut.ingress_sample_valid,first_pipe,second_pipe}!==0))
      fail("ambiguous control transition during valid conditioner work");
    if((^{dut.ingress_sample_valid,dut.g_rate_60.stage_30_valid,canonical_valid})===1'bx)
      fail("unknown real CDC/cascade valid protocol");
    if((^{pilot.ddc.accept,pilot.ddc.mixed_valid,pilot.ddc.hb_valid,pilot.ddc_valid,
          pilot.push,pilot_valid,pilot_ready})===1'bx)
      fail("unknown pilot intermediate/admission/AXIS protocol");
    if(dut.ingress_sample_valid) begin
      if(ingress_checked>=source_checked || ingress_checked>=16425 ||
         dut.ingress_sample_index!==source_indexes[ingress_checked] ||
         {dut.ingress_sample_q,dut.ingress_sample_i}!==source_words[ingress_checked] ||
         dut.ingress_sample_gap!==(ingress_checked==0)) fail("CDC delivery data/order/gap mismatch");
      if(ingress_checked<2 && checked_enable) fail("prime entered enabled conditioner");
      ingress_checked=ingress_checked+1;
    end
    // Compare pre-edge outputs even when this edge will cancel later work.
    first_output_now=first_pipe[5]; first_index_now=64'd17179867609+stage30_count;
    if(dut.g_rate_60.stage_30_valid!==first_output_now || canonical_valid!==second_pipe[5])
      fail("independent two-stage enabled-prefix VALID mismatch");
    if(first_output_now) begin
      if(stage30_count>=8205 || dut.g_rate_60.stage_30_gap!==0 ||
         dut.g_rate_60.stage_30_index!==stage30_indexes[stage30_count] ||
         {dut.g_rate_60.stage_30_q,dut.g_rate_60.stage_30_i}!==stage30_words[stage30_count])
        fail("first integer x2 word/index/gap mismatch");
      stage30_count=stage30_count+1;
    end
    if(canonical_valid) begin
      if(canonical_count>=4096 || {canonical_gap,canonical_flush}!==0 ||
         canonical_index!==canonical_indexes[canonical_count] ||
         {canonical_q,canonical_i}!==canonical_words[canonical_count])
        fail("second integer x2/canonical word/index/gap mismatch");
      canonical_count=canonical_count+1;
    end
    first_issue=0; second_issue=0;
    if(!checked_enable || canonical_flush) begin
      first_history=0; second_history=0; first_pipe=0; second_pipe=0;
    end else begin
      if(dut.ingress_sample_valid) begin
        if(dut.ingress_sample_gap!==0 || dut.ingress_sample_index!==RAW_FIRST+enabled_raw ||
           enabled_raw>=16423 || {dut.g_rate_60.acquisition_ddc_60_to_30.mixed_q,
           dut.g_rate_60.acquisition_ddc_60_to_30.mixed_i}!==first_mixed[enabled_raw])
          fail("first stage accepted raw/mixer/phase mismatch");
        first_issue=(first_history==14 && dut.ingress_sample_index[0]);
        if(first_history<14) first_history=first_history+1;
        enabled_raw=enabled_raw+1;
      end
      if(first_output_now) begin
        if(first_index_now!==64'd17179867609+stage30_accepted || stage30_accepted>=8205 ||
           {dut.g_rate_60.acquisition_ddc_30_to_15.mixed_q,
           dut.g_rate_60.acquisition_ddc_30_to_15.mixed_i}!==second_mixed[stage30_accepted])
          fail("second stage accepted model output/mixer/phase mismatch");
        second_issue=(second_history==14 && first_index_now[0]);
        if(second_history<14) second_history=second_history+1;
        stage30_accepted=stage30_accepted+1;
      end
      first_pipe={first_pipe[4:0],first_issue}; second_pipe={second_pipe[4:0],second_issue};
      if(first_pipe[5]) stage30_emitted_model=stage30_emitted_model+1;
      if(second_pipe[5]) emitted_raw_model=emitted_raw_model+1;
    end
    // All visible filter intermediate prefixes remain exact even at auto-stop.
    if (pilot.ddc.accept) pilot_accepted=pilot_accepted+1;
    if (pilot.ddc.mixed_valid) begin
      if (pilot_mixed_count>=4096 || {pilot.ddc.mixed_q,pilot.ddc.mixed_i}!==pilot_mixed[pilot_mixed_count] ||
          pilot.ddc.mixed_index!==PRE_FIRST+pilot_mixed_count || pilot.ddc.mixed_saturations!==0)
        fail("pilot mixed word/index/saturation mismatch");
      pilot_mixed_count=pilot_mixed_count+1;
    end
    if (pilot.ddc.hb_valid) begin
      if (pilot_half_count>=2048 || {pilot.ddc.hb_q,pilot.ddc.hb_i}!==pilot_half[pilot_half_count] ||
          pilot.ddc.hb_index!==pilot_half_indexes[pilot_half_count] || pilot.ddc.hb_saturations!==0)
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
          pilot.capture_index!==pilot_indexes[admitted_count] || pilot.capture_support!==1 || pilot.capture_visit!==VISIT)
        fail("selected pilot word/index/support/visit mismatch");
      admitted_count=admitted_count+1;
      if(admitted_count==512) expected_pilot_enable=0;
    end
    if (prior_stalled && (!pilot_valid || pilot_data!==held_data)) fail("pilot AXIS stalled promise changed");
    prior_stalled=pilot_valid && !pilot_ready; held_data=pilot_data;
    if (prior_stalled) stalled_cycles=stalled_cycles+1;
    if (pilot_valid && pilot_ready) begin
      if (delivered_count>=512 || pilot_data!==pilot_words[delivered_count]) fail("pilot AXIS bytes mismatch");
      $fwrite(sink_fd,"%c%c%c%c",pilot_data[7:0],pilot_data[15:8],pilot_data[23:16],pilot_data[31:24]);
      $display("HIGH_RATE60_PILOT_WORD ordinal=%0d newest=%016x word=%08x",delivered_count,pilot_indexes[delivered_count],pilot_data);
      delivered_count=delivered_count+1;
    end
    #0.001;
    if(dut.ddc_accepted_sample_count!==enabled_raw || dut.ddc_emitted_sample_count!==emitted_raw_model ||
       dut.g_rate_60.stage_60_emitted_count!==stage30_emitted_model ||
       dut.g_rate_60.stage_30_accepted_count!==stage30_accepted || pilot.admitted!==admitted_count)
      fail("independent two-stage/pilot cumulative counter mismatch");
    if(!control_transition && (pilot_enable!==expected_pilot_enable ||
        dut.conditioner_enable!==(expected_coarse_enable || expected_pilot_enable)))
      fail("public512-pilot/STOP transition did not match enable mirrors");
  end
