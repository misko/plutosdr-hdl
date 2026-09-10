`timescale 1ns/1fs
// Actual generated175 MMCM and complete bank-owned coarse runtime. No RTL
// replacement/forced arithmetic; all visible provisional prefixes stay checked.
module tb_starlink_pss_bank_clock_traffic;
  localparam integer SAMPLE_COUNT=1406, SCORE_COUNT=1341, FFT_WORDS=1536;
  reg clk=0, resetn=0, clock_resetn=0, manual_fft_resetn=1;
  always #5 clk=!clk;
  wire fft_clk, locked;
  wire fft_resetn=resetn && manual_fft_resetn && locked;
  reg enable=0, flush=0, sample_valid=0, sample_gap=0, score_ready=1;
  reg signed [15:0] sample_i=0, sample_q=0;
  reg [63:0] sample_index=0, source_base=0;
  wire score_valid, score_denominator_zero, detector_fault;
  wire [7:0] score_value;
  wire [63:0] score_start_index;
  wire scheduler_gap_pulse, scheduler_index_error_pulse, scheduler_overflow_pulse;
  wire forward_fft_fault, kernel_join_fault, product_overflow_fault;
  wire inverse_fft_fault, forward_exponent_fault, candidate_path_fault;
  wire [9:0] candidate_fifo_stored_count, candidate_fifo_maximum_stored_count;
  reg [31:0] samples [0:SAMPLE_COUNT-1];
  reg [35:0] forward_words [0:FFT_WORDS-1], product_words [0:FFT_WORDS-1];
  reg [35:0] inverse_words [0:FFT_WORDS-1];
  reg [7:0] scores [0:SCORE_COUNT-1];
  reg [4:0] forward_exponents [0:2], inverse_exponents [0:2];
  integer cycle_count=0, epoch_cycle=0, epoch=0, source_count=0, source_phase=0;
  integer forward_count=0, product_count=0, inverse_count=0, score_count=0;
  integer total_forward=0, total_product=0, total_inverse=0, total_scores=0;
  integer healthy_epochs=0, fault_cases=0, measured_edges=0, closure_count=0;
  integer forward_starts=0, inverse_starts=0, fault_kind=-1;
  reg source_running=0, monitor_active=0, expected_fault=0, quarantine=0;
  reg closure_armed=0, manual_window=0, held_last=0;
  reg [72:0] held_score=0;
  realtime raw_reset_ns=-1, locked_drop_ns=-1, epoch_fall_ns=-1;
  realtime closure_observed_ns=-1, outer_fault_ns=-1, relock_ns=-1;
  realtime first_clock_edge, mean_clock_period;

  starlink_bank_clock175_candidate clock_source (
    .clk_in1(clk), .clk_out1(fft_clk), .resetn(clock_resetn), .locked(locked)
  );
  starlink_pss_iq_to_score_bank_owned dut (.*);

  task automatic fail(input string reason);
    $display("BANK_CLOCK_TRAFFIC_FAIL %s epoch=%0d kind=%0d time_ns=%0.3f source=%0d forward=%0d product=%0d inverse=%0d scores=%0d locked=%b fft_resetn=%b fault=%b",
      reason,epoch,fault_kind,$realtime,source_count,forward_count,product_count,
      inverse_count,score_count,locked,fft_resetn,detector_fault);
    $fatal(1,"bank clock active-traffic assertion failed");
  endtask
  task automatic healthy;
    if (detector_fault || scheduler_gap_pulse || scheduler_index_error_pulse ||
        scheduler_overflow_pulse || forward_fft_fault || kernel_join_fault ||
        product_overflow_fault || inverse_fft_fault || forward_exponent_fault ||
        candidate_path_fault || !locked || !fft_resetn)
      fail("unexpected healthy epoch fault/reset/lock loss");
  endtask

  always @(negedge clk) begin
    sample_valid=0;
    if (source_running && source_count<SAMPLE_COUNT) begin
      source_phase=source_phase+15;
      if (source_phase>=100) begin
        source_phase=source_phase-100;
        {sample_q,sample_i}=samples[source_count];
        sample_index=source_base+source_count;
        sample_valid=1; source_count=source_count+1;
      end
    end
  end
  integer fast_block,fast_position;
  always @(posedge fft_clk) begin
    if (resetn && (!monitor_active || !fft_resetn) && dut.island.core_input_valid)
      fail("stale fast-core input in reset or pre-source recovery interval");
    if (monitor_active) begin
      if (dut.island.core_input_valid && dut.island.core_input_ready &&
          dut.island.selected_position==0) begin
        if (dut.island.next_inverse) inverse_starts=inverse_starts+1;
        else forward_starts=forward_starts+1;
      end
      if (dut.island.joiner.input_valid && dut.island.joiner.input_ready) begin
        fast_block=forward_count/512; fast_position=forward_count%512;
        if (forward_count>=FFT_WORDS || dut.island.return_data!==forward_words[forward_count] ||
            dut.island.return_position!==fast_position ||
            dut.island.return_metadata[4:0]!==forward_exponents[fast_block] ||
            dut.island.return_metadata[73:10]!==source_base+447*fast_block ||
            dut.island.return_last!==(fast_position==511))
          fail("exact accepted forward data/position/identity/exponent/TLAST mismatch");
        forward_count=forward_count+1; total_forward=total_forward+1;
      end
      if (dut.island.product_valid && !dut.island.fast_fault && dut.island.product_bank_ready) begin
        fast_block=product_count/512; fast_position=product_count%512;
        if (product_count>=FFT_WORDS || {dut.island.product_q,dut.island.product_i}!==product_words[product_count] ||
            dut.island.product_position!==fast_position ||
            dut.island.product_exponent!==forward_exponents[fast_block] ||
            dut.island.product_start!==source_base+447*fast_block ||
            dut.island.product_last!==(fast_position==511) || dut.island.product_overflow)
          fail("exact accepted product data/position/identity/exponent/TLAST mismatch");
        product_count=product_count+1; total_product=total_product+1;
      end
      if (quarantine && (dut.island.core_input_valid || dut.island.output_valid ||
          dut.island.fast_running || dut.island.core_aresetn))
        fail("fast work or bank reopened before explicit recovery");
    end
  end
  integer slow_block,slow_position;
  always @(posedge clk) begin
    cycle_count=cycle_count+1;
    if (resetn && (!monitor_active || !fft_resetn) && (score_valid || dut.inverse_output_valid))
      fail("stale score/inverse output in reset or pre-source recovery interval");
    if (cycle_count>400000 || (monitor_active && cycle_count-epoch_cycle>30000))
      fail("bounded global/per-epoch watchdog");
    if (monitor_active) begin
      if (!expected_fault) healthy();
      if (dut.inverse_output_valid && dut.inverse_output_ready) begin
        slow_block=inverse_count/512; slow_position=inverse_count%512;
        if (inverse_count>=FFT_WORDS || {dut.inverse_output_q,dut.inverse_output_i}!==inverse_words[inverse_count] ||
            dut.inverse_output_position!==slow_position ||
            dut.inverse_forward_exponent!==forward_exponents[slow_block] ||
            dut.inverse_output_exponent!==inverse_exponents[slow_block] ||
            dut.inverse_output_block_start!==source_base+447*slow_block ||
            dut.inverse_output_last!==(slow_position==511))
          fail("exact visible inverse data/position/identity/exponents/TLAST mismatch");
        inverse_count=inverse_count+1; total_inverse=total_inverse+1;
      end
      // Never skip numerical checking just because an epoch is expected to fail.
      // A held VALID word is checked on every presentation; totals count accepts.
      if (score_valid) begin
        if (score_count>=SCORE_COUNT || score_value!==scores[score_count] ||
            score_start_index!==source_base+score_count || score_denominator_zero)
          fail("exact visible score/identity/denominator mismatch");
        if (score_ready) begin score_count=score_count+1; total_scores=total_scores+1; end
      end
      if (held_last && fft_resetn && !detector_fault &&
          (!score_valid || {score_start_index,score_value,score_denominator_zero}!==held_score))
        fail("score promise changed while retained in a healthy epoch");
      held_last=score_valid && !score_ready;
      held_score={score_start_index,score_value,score_denominator_zero};
      if (quarantine && (score_valid || dut.interfaces_open || dut.pipeline_active ||
          dut.inverse_output_valid || dut.scheduler_fft_ready || !detector_fault))
        fail("stale publication or missing sticky outer fault during quarantine");
    end
    #0.002;
    if (closure_armed && detector_fault && outer_fault_ns<0) outer_fault_ns=$realtime;
  end
  always @(negedge locked) begin
    if (closure_armed) locked_drop_ns=$realtime;
    if (manual_window) fail("manual FFT-only reset dropped MMCM lock");
  end
  always @(negedge fft_resetn) begin
    if (closure_armed) begin
      epoch_fall_ns=$realtime;
      #0.002;
      if (dut.fft_reset_release_sync!==0 || dut.interfaces_open!==0 || score_valid!==0 ||
          dut.island.fast_running!==0 || dut.island.slow_running!==0 ||
          dut.island.input_ready!==0 || dut.island.output_valid!==0 ||
          dut.island.core_input_valid!==0 || dut.island.core_aresetn!==0)
        fail("actual domain interfaces failed prompt epoch-reset closure");
      closure_observed_ns=$realtime; closure_count=closure_count+1;
    end
  end

  task automatic start_fresh;
    @(negedge clk); #0.002;
    source_running=0; monitor_active=0; enable=0;
    repeat (12) @(negedge clk);
    #0.002;
    if (detector_fault || dut.pipeline_active || score_valid || dut.island.core_aresetn)
      fail("explicit enable-cycle recovery did not purge/clear old epoch");
    quarantine=0; expected_fault=0; closure_armed=0; held_last=0;
    epoch=epoch+1; epoch_cycle=cycle_count;
    source_base=64'd1000000+epoch*65536;
    source_count=0; source_phase=0; score_count=0; forward_count=0;
    product_count=0; inverse_count=0; forward_starts=0; inverse_starts=0;
    score_ready=1; enable=1;
    repeat (12) @(negedge clk);
    #0.002; healthy(); monitor_active=1; source_running=1;
  endtask
  task automatic exact_replay;
    start_fresh();
    wait(score_count==SCORE_COUNT);
    repeat (100) @(negedge clk);
    if (source_count!=SAMPLE_COUNT || forward_count!=FFT_WORDS || product_count!=FFT_WORDS ||
        inverse_count!=FFT_WORDS || score_count!=SCORE_COUNT || forward_starts!=3 || inverse_starts!=3)
      fail("healthy full-fixture exact count/core-consumption inventory mismatch");
    healthy();
    @(posedge fft_clk); first_clock_edge=$realtime;
    repeat (1024) @(posedge fft_clk);
    mean_clock_period=($realtime-first_clock_edge)/1024.0;
    if (mean_clock_period<5.709285714 || mean_clock_period>5.719285714)
      fail("generated175 mean period outside frozen 5ps simulation tolerance");
    measured_edges=measured_edges+1024; healthy_epochs=healthy_epochs+1;
    $display("BANK_CLOCK_TRAFFIC_EXACT epoch=%0d scores=1341 forward=1536 product=1536 inverse=1536 source_base=%0d mean_period_ns=%0.9f",
      epoch,source_base,mean_clock_period);
  endtask
  task automatic wait_injection_point(input integer kind);
    if (kind==0 || kind==1) begin
      // Sample actual vendor acceptance in its own clock, not capture/offer.
      @(posedge fft_clk);
      while (!(dut.island.core_input_valid && dut.island.core_input_ready &&
          dut.island.selected_position==128 && dut.island.next_inverse==(kind==1) &&
          dut.island.engine_metadata[68:5]==source_base+447)) @(posedge fft_clk);
      #0.002;
      if (kind==0 && forward_starts<2) fail("missing second forward consumption witness");
      if (kind==1 && inverse_starts<2) fail("missing second inverse consumption witness");
    end else if (kind==2) begin
      @(posedge clk);
      while (!(dut.inverse_output_valid && dut.inverse_output_position==256 &&
               dut.inverse_output_block_start==source_base+447)) @(posedge clk);
      #0.002;
      if (inverse_count<769) fail("missing actual second inverse output prefix");
    end else begin
      wait(score_count>=100);
      @(negedge clk); #0.002; score_ready=0;
      wait(score_valid);
      repeat (3) @(negedge clk);
      #0.002;
      if (!score_valid || score_ready || candidate_fifo_stored_count==0)
        fail("manual reset did not target retained real score/candidates");
    end
    if (!locked || !fft_resetn || detector_fault || !dut.pipeline_active || score_count==0)
      fail("active reset lacks healthy clock/traffic/provisional-score support");
  endtask
  task automatic active_reset_case(input integer kind);
    integer before_reset_scores,before_reset_source;
    start_fresh(); fault_kind=kind;
    wait_injection_point(kind);
    expected_fault=1; closure_armed=1;
    raw_reset_ns=$realtime; locked_drop_ns=-1; epoch_fall_ns=-1;
    closure_observed_ns=-1; outer_fault_ns=-1; relock_ns=-1;
    before_reset_source=source_count; before_reset_scores=score_count;
    if (kind==3) begin manual_window=1; manual_fft_resetn=0; end
    else clock_resetn=0;
    // LOCKED is observed, never forced or assumed to fall at raw reset time.
    wait(epoch_fall_ns>=0 && closure_observed_ns>=0);
    repeat (3) @(negedge clk);
    if (!resetn || !enable || !detector_fault || score_valid || dut.pipeline_active ||
        outer_fault_ns<epoch_fall_ns || outer_fault_ns-epoch_fall_ns>10.0021)
      fail("outer enabled epoch failed bounded sticky fault after actual FFT reset fall");
    quarantine=1;
    repeat (20) @(negedge clk);
    if (kind==3) begin
      if (!locked || locked_drop_ns>=0) fail("manual reset was not FFT-only");
      manual_fft_resetn=1;
    end else begin
      if (locked_drop_ns<raw_reset_ns || locked!==0)
        fail("MMCM reset lacks actual observed LOCKED-drop witness");
      clock_resetn=1;
      wait(locked===1); relock_ns=$realtime;
    end
    repeat (100) @(negedge clk);
    if (!locked || !fft_resetn || !detector_fault || score_valid ||
        source_count<=before_reset_source+10 || score_count<before_reset_scores)
      fail("relock/reset release silently recovered or failed continuing-source quarantine");
    if (kind==3) manual_window=0;
    $display("BANK_CLOCK_TRAFFIC_RESET kind=%0d exact_score_prefix=%0d forward=%0d product=%0d inverse=%0d raw_reset_ns=%0.3f locked_drop_ns=%0.3f fft_epoch_fall_ns=%0.3f closure_observed_ns=%0.3f outer_fault_ns=%0.3f relock_ns=%0.3f retained_score=%0d sticky_enabled_epoch=1",
      kind,score_count,forward_count,product_count,inverse_count,raw_reset_ns,locked_drop_ns,
      epoch_fall_ns,closure_observed_ns,outer_fault_ns,relock_ns,kind==3);
    fault_cases=fault_cases+1;
    closure_armed=0;
    exact_replay();
  endtask
  initial begin
    $readmemh("samples_ci16.mem",samples);
    $readmemh("forward_q17.mem",forward_words);
    $readmemh("product_q17.mem",product_words);
    $readmemh("inverse_q17.mem",inverse_words);
    $readmemh("forward_exponents.mem",forward_exponents);
    $readmemh("inverse_exponents.mem",inverse_exponents);
    $readmemh("scores_u8.mem",scores);
    repeat (20) @(negedge clk);
    clock_resetn=1; wait(locked===1); @(negedge clk); resetn=1;
    repeat (12) @(negedge clk);
    exact_replay();
    active_reset_case(0); active_reset_case(1); active_reset_case(2); active_reset_case(3);
    if (healthy_epochs!=5 || fault_cases!=4 || closure_count!=4 || measured_edges!=5120)
      fail("incomplete active-clock lifecycle inventory");
    $display("BANK_CLOCK_TRAFFIC_TOTAL exact_scores=%0d forward=%0d product=%0d inverse=%0d",total_scores,total_forward,total_product,total_inverse);
    $display("BANK_CLOCK_TRAFFIC_PASS exact_epochs=5 exact_full_scores=6705 reset_cases=4 mmcm_active_resets=3 manual_fft_only_resets=1 measured_edges=5120 ACTUAL_IP_NO_INPUT_CLOCK_LOSS_RECEIVER_PHYSICAL_OR_RF_CLAIM");
    $finish;
  end
endmodule
