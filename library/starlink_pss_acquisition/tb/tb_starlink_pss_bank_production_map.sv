`timescale 1ns/1fs
// Periodic synthetic geometry/arithmetic stress, not RF/accuracy or timing closure.
// Actual bank-owned 18-bit XFFT and unchanged phase-map runtime; ideal 100/175 clocks.
`define IQ dut.bank_transform.iq_to_score
`define ISLAND dut.bank_transform.iq_to_score.island
`define PREP dut.bank_transform.iq_to_score.candidate_score_path.score_prepare
module tb_starlink_pss_bank_production_map #(parameter integer PRODUCTION=0);
  localparam integer BINS=PRODUCTION ? 20000 : 343, FRAMES=PRODUCTION ? 64 : 2;
  localparam integer SELECTED=BINS*FRAMES, BLOCKS=(SELECTED+446)/447;
  localparam integer SUPPORT=(BLOCKS-1)*447+512, FULL_SCORES=BLOCKS*447;
  localparam integer COMPLETE_EPOCHS=PRODUCTION ? 1 : 2;
  localparam [63:0] FIRST=64'h00000001fff80000;
  reg clk=0, fft_clk=0, resetn=0, fft_resetn=0, enable=0, flush=0;
  always #5 clk=!clk;
  initial begin #1.3; forever #(500.0/175) fft_clk=!fft_clk; end
  reg sample_valid=0, sample_gap=0, source_running=0;
  reg signed [15:0] sample_i=0, sample_q=0;
  reg [63:0] sample_index=0, source_base=FIRST, last_complete_base=0;
  reg [31:0] period_words [0:446];
  reg [35:0] forwards [0:511], products [0:511], inverses [0:511];
  reg [4:0] ef [0:0], ei [0:0];
  reg [6:0] shifts [0:0];
  reg [37:0] energies [0:446];
  reg [68:0] numerators [0:446], denominators [0:446];
  reg saturated [0:446];
  reg [7:0] scores [0:446];
  reg [15:0] expected_map [0:BINS-1];
  reg map_read_request=0, map_read_bank=0, map_release=0, map_release_bank=0;
  reg [14:0] map_read_index=0;
  wire [1:0] map_ready_mask;
  wire [31:0] map_generation_0, map_generation_1;
  wire [63:0] map_start_index_0, map_start_index_1;
  wire map_read_valid, map_read_error;
  wire [15:0] map_read_data;
  wire score_valid, score_denominator_zero, detector_fault;
  wire [7:0] score_value;
  wire [63:0] score_start_index;
  wire [14:0] score_phase;
  wire scheduler_gap_pulse, scheduler_index_error_pulse, scheduler_overflow_pulse;
  wire forward_fft_fault, kernel_join_fault, product_overflow_fault, inverse_fft_fault;
  wire forward_exponent_fault, candidate_path_fault;
  wire [9:0] candidate_fifo_stored_count, candidate_fifo_maximum_stored_count;
  wire [31:0] accepted_score_count, discarded_score_count, discontinuity_abort_count;
  wire [31:0] map_publish_count, map_overrun_count, score_protocol_error_count;
  wire [31:0] map_arithmetic_overflow_count, map_read_error_count, map_release_error_count;
  wire map_counter_fault;
  wire [31:0] detector_health_flags, scheduler_gap_count, scheduler_index_error_count;
  wire [31:0] scheduler_overflow_count, detector_fault_count;
  wire [31:0] score_phase_index_discontinuity_count, score_denominator_zero_count;
  reg stop_request=0;
  wire stop_ready, stop_pending, stop_ack, stop_done, stop_complete, stop_failed, stop_has_map;
  wire [5:0] stop_failure_reason;
  wire [31:0] stop_generation;
  wire [63:0] stop_start_index, stop_end_index;
  integer cycles=0, epoch=0, source_count=0, source_phase=0, source_checked=0;
  integer forward_input_count=0, inverse_input_count=0, forward_count=0, product_count=0;
  integer inverse_count=0, prepare_count=0, ratio_count=0, score_count=0;
  integer total_scores=0, total_source=0, total_forward=0, total_product=0, total_inverse=0;
  integer total_forward_input=0, total_inverse_input=0, total_prepare=0, total_ratio=0;
  integer complete_visible_sum=0, partial_visible=0;
  integer accepted_origin=0, published=0, map_words=0, terminal_count=0;
  integer stop_source_count=0, retained_source_count=0, observed_residue=-1;
  integer progress=0, pending_read=0, read_index_expected=0;
  reg monitor_active=0, expected_abort=0, auto_disable=1, read_outstanding=0;
  reg final_score_accepted=0;
  realtime epoch_begin_ns=0, final_accept_ns=0, publish_ns=0, terminal_ns=0;

  starlink_pss_iq_to_phase_map #(
    .USE_SHARED_XFFT(1), .USE_REALTIME_XFFT(1), .USE_BANK_OWNED_XFFT(1),
    .ENABLE_BOUNDARY_STOP(1), .PHASE_BINS(BINS), .PHASE_INDEX_WIDTH(15),
    .TILE_FRAMES(FRAMES), .TILE_FRAME_WIDTH(PRODUCTION ? 6 : 1),
    .MAP_SEGMENT_ADDRESS_WIDTH(PRODUCTION ? 11 : 9),
    .MAP_SEGMENT_COUNT(PRODUCTION ? 10 : 1), .MAP_SEGMENT_INDEX_WIDTH(PRODUCTION ? 4 : 1)
  ) dut (.*);

  task automatic fail(input string reason);
    $display("BANK_PRODUCTION_MAP_FAIL %s production=%0d epoch=%0d time_ns=%0.3f source=%0d score=%0d accepted=%0d forward=%0d inverse=%0d ready=%b health=%08h abort=%0d",
      reason,PRODUCTION,epoch,$realtime,source_count,score_count,accepted_score_count,
      forward_count,inverse_count,map_ready_mask,detector_health_flags,discontinuity_abort_count);
    $fatal(1,"bank production-map assertion failed");
  endtask
  task automatic healthy;
    if (detector_fault || scheduler_gap_pulse || scheduler_index_error_pulse || scheduler_overflow_pulse ||
        forward_fft_fault || kernel_join_fault || product_overflow_fault || inverse_fft_fault ||
        forward_exponent_fault || candidate_path_fault || scheduler_gap_count || scheduler_index_error_count ||
        scheduler_overflow_count || detector_fault_count || score_phase_index_discontinuity_count ||
        score_denominator_zero_count || discarded_score_count || map_overrun_count || score_protocol_error_count ||
        map_arithmetic_overflow_count || map_read_error_count || map_release_error_count)
      fail("unexpected pipeline or map health failure");
    if (!expected_abort && (map_counter_fault || detector_health_flags || discontinuity_abort_count))
      fail("unexpected persistent health/abort");
    if (flush || !fft_resetn) fail("unrequested flush/FFT reset after initial boot");
  endtask

  // Source never observes downstream ready/enable/stop/map ownership. It keeps
  // its contiguous index/data at 15/100 during stop, retention, reads and release.
  always @(negedge clk) begin
    sample_valid=0;
    if (source_running) begin
      source_phase=source_phase+15;
      if (source_phase>=100) begin
        source_phase=source_phase-100;
        {sample_q,sample_i}=period_words[source_count%447];
        sample_index=source_base+source_count;
        sample_valid=1; source_count=source_count+1;
      end
    end
    if (auto_disable && stop_ack) enable=0;
  end

  integer fast_position,fast_block;
  reg [35:0] expected_input;
  always @(posedge fft_clk) begin
    if (resetn && !monitor_active && `ISLAND.core_input_valid)
      fail("stale core input between explicitly separated source epochs");
    if (monitor_active) begin
      if (`ISLAND.core_input_valid && `ISLAND.core_input_ready) begin
        if (`ISLAND.next_inverse) begin
          fast_position=inverse_input_count%512; fast_block=inverse_input_count/512;
          expected_input=products[fast_position];
          inverse_input_count=inverse_input_count+1; total_inverse_input=total_inverse_input+1;
        end else begin
          fast_position=forward_input_count%512; fast_block=forward_input_count/512;
          expected_input={period_words[fast_position%447][31:16],2'b00,
                          period_words[fast_position%447][15:0],2'b00};
          forward_input_count=forward_input_count+1; total_forward_input=total_forward_input+1;
        end
        if (`ISLAND.selected_data!==expected_input || `ISLAND.selected_position!==fast_position ||
            `ISLAND.core_input_data!=={6'b0,expected_input[35:18],6'b0,expected_input[17:0]} ||
            `ISLAND.engine_metadata[68:5]!==source_base+447*fast_block ||
            `ISLAND.core_input_last!==(fast_position==511)) begin
          $display("BANK_PRODUCTION_MAP_CORE_DETAIL inverse=%b actual_selected=%09h expected_selected=%09h actual_wire=%012h expected_wire=%012h actual_position=%0d expected_position=%0d actual_start=%0d expected_start=%0d actual_last=%b expected_last=%b",
            `ISLAND.next_inverse,`ISLAND.selected_data,expected_input,`ISLAND.core_input_data,
            {6'b0,expected_input[35:18],6'b0,expected_input[17:0]},`ISLAND.selected_position,
            fast_position,`ISLAND.engine_metadata[68:5],source_base+447*fast_block,
            `ISLAND.core_input_last,(fast_position==511));
          fail("actual own-clock core input data/position/identity/TLAST mismatch");
        end
      end
      if (`ISLAND.joiner.input_valid && `ISLAND.joiner.input_ready) begin
        fast_position=forward_count%512; fast_block=forward_count/512;
        if (`ISLAND.return_data!==forwards[fast_position] || `ISLAND.return_position!==fast_position ||
            `ISLAND.return_metadata[4:0]!==ef[0] ||
            `ISLAND.return_metadata[73:10]!==source_base+447*fast_block ||
            `ISLAND.return_last!==(fast_position==511))
          fail("forward word/position/identity/BFP exponent/TLAST mismatch");
        forward_count=forward_count+1; total_forward=total_forward+1;
      end
      if (`ISLAND.product_valid && !`ISLAND.fast_fault && `ISLAND.product_bank_ready) begin
        fast_position=product_count%512; fast_block=product_count/512;
        if ({`ISLAND.product_q,`ISLAND.product_i}!==products[fast_position] ||
            `ISLAND.product_position!==fast_position || `ISLAND.product_exponent!==ef[0] ||
            `ISLAND.product_start!==source_base+447*fast_block ||
            `ISLAND.product_last!==(fast_position==511) || `ISLAND.product_overflow)
          fail("product word/position/identity/BFP exponent/TLAST mismatch");
        product_count=product_count+1; total_product=total_product+1;
      end
    end
  end
  integer slow_position,slow_block,phase;
  always @(posedge clk) begin
    cycles=cycles+1;
    if (cycles>SELECTED*8+BINS*32+300000) fail("bounded simulation watchdog");
    if (resetn) begin
      if (sample_valid) begin
        if (sample_index!==source_base+source_checked ||
            {sample_q,sample_i}!==period_words[source_checked%447]) fail("continuous source mismatch");
        source_checked=source_checked+1; total_source=total_source+1;
      end
      if (!monitor_active && (score_valid || `IQ.inverse_output_valid)) fail("stale score/inverse between epochs");
      if (monitor_active) begin
        healthy();
        if (`IQ.inverse_output_valid && `IQ.inverse_output_ready) begin
          slow_position=inverse_count%512; slow_block=inverse_count/512;
          if ({`IQ.inverse_output_q,`IQ.inverse_output_i}!==inverses[slow_position] ||
              `IQ.inverse_output_position!==slow_position || `IQ.inverse_forward_exponent!==ef[0] ||
              `IQ.inverse_output_exponent!==ei[0] ||
              `IQ.inverse_output_block_start!==source_base+447*slow_block ||
              `IQ.inverse_output_last!==(slow_position==511))
            fail("inverse word/position/identity/BFP exponents/TLAST mismatch");
          inverse_count=inverse_count+1; total_inverse=total_inverse+1;
        end
        if (`PREP.input_valid && `PREP.input_ready) begin
          phase=prepare_count%447;
          if (`PREP.input_sample_energy!==energies[phase] ||
              {`PREP.input_correlation_q,`PREP.input_correlation_i}!==inverses[phase+65] ||
              `PREP.input_forward_exponent!==ef[0] || `PREP.input_inverse_exponent!==ei[0] ||
              `PREP.input_start_index!==source_base+prepare_count)
            fail("exact66 sample energy/correlation/exponents/index mismatch");
          prepare_count=prepare_count+1; total_prepare=total_prepare+1;
        end
        if (`PREP.output_valid && `PREP.output_ready) begin
          phase=ratio_count%447;
          if (`PREP.output_numerator!==numerators[phase] || `PREP.output_denominator!==denominators[phase] ||
              `PREP.output_power_shift!==shifts[0] || `PREP.output_numerator_saturated!==saturated[phase] ||
              `PREP.output_denominator_zero || `PREP.output_start_index!==source_base+ratio_count)
            fail("exact69 bit ratio/normalization flags/index mismatch");
          ratio_count=ratio_count+1; total_ratio=total_ratio+1;
        end
        // Includes every visible post-map tail/provisional prefix; never waive
        // numeric checks in the explicitly classified final partial abort.
        if (score_valid) begin
          if (score_value!==scores[score_count%447] || score_start_index!==source_base+score_count ||
              score_phase!==score_count%BINS || score_denominator_zero) fail("exact score/index/phase mismatch");
          score_count=score_count+1; total_scores=total_scores+1;
          if (PRODUCTION && epoch==1 && score_count%200000==0) begin
            progress=progress+1;
            $display("BANK_PRODUCTION_MAP_PROGRESS selected_prefix=%0d time_ns=%0.3f",score_count,$realtime);
          end
        end
        if (dut.phase_map.state==2 && dut.phase_map.frame_index==FRAMES-1 &&
            dut.map_score_valid && dut.map_score_phase==BINS-1 && dut.map_enable) begin
          final_score_accepted=1; final_accept_ns=$realtime;
          observed_residue=(dut.map_score_start_index-source_base)%447+1;
        end
        if (stop_ack) begin terminal_count=terminal_count+1; terminal_ns=$realtime; end
        if (map_publish_count>published) begin
          if (!final_score_accepted || accepted_score_count-accepted_origin!=SELECTED)
            fail("publication before exact final-score admission");
          published=map_publish_count; publish_ns=$realtime;
        end
        if (accepted_score_count-accepted_origin>SELECTED) fail("potential FFT tail entered a second map");
      end
      if (map_read_valid) begin
        if (!read_outstanding || map_read_error || map_read_data!==expected_map[read_index_expected])
          fail("unsolicited/duplicate/error/incorrect complete-map response");
        read_outstanding=0; map_words=map_words+1;
      end
      if (map_read_error) fail("native read error");
    end
  end

  task automatic start_epoch;
    @(negedge clk); #0.002;
    source_running=0; enable=0;
    repeat (32) @(negedge clk);
    #0.002;
    if (`IQ.pipeline_active || `ISLAND.core_aresetn || score_valid || detector_fault)
      fail("enable-cycle did not purge old epoch before fresh source");
    monitor_active=0;
    epoch=epoch+1; source_base=FIRST+(epoch-1)*4194304;
    source_count=0; source_checked=0; source_phase=0;
    forward_input_count=0; inverse_input_count=0; forward_count=0; product_count=0;
    inverse_count=0; prepare_count=0; ratio_count=0; score_count=0;
    accepted_origin=accepted_score_count; final_score_accepted=0;
    auto_disable=1; enable=1;
    repeat (32) @(negedge clk);
    #0.002;
    if (!stop_ready || stop_done || map_ready_mask) fail("fresh enable did not rearm released map");
    monitor_active=1; source_running=1; epoch_begin_ns=$realtime;
  endtask
  task automatic request_stop;
    @(negedge clk); #0.002;
    if (!stop_ready) fail("stop request not admitted while ready");
    stop_request=1;
    @(negedge clk); #0.002; stop_request=0;
    if (!stop_pending) fail("stop not actually pending");
  endtask
  task automatic check_tuple(input integer generation,input [63:0] first);
    if (!stop_done || !stop_complete || stop_failed || stop_failure_reason || !stop_has_map ||
        stop_generation!=generation || stop_start_index!==first || stop_end_index!==first+SELECTED)
      fail("healthy immutable stop tuple mismatch");
  endtask
  task automatic read_all_release;
    integer p,bank,deadline,source_before;
    bank=map_ready_mask[0] ? 0 : 1;
    if (map_ready_mask==0 || (bank==0 && (map_generation_0!=epoch || map_start_index_0!==source_base)) ||
        (bank==1 && (map_generation_1!=epoch || map_start_index_1!==source_base)))
      fail("retained complete-map ownership/identity mismatch");
    source_before=source_count;
    repeat (97) @(negedge clk);
    for (p=0;p<BINS;p=p+1) begin
      @(negedge clk); #0.002;
      read_index_expected=p; read_outstanding=1;
      map_read_bank=bank; map_read_index=p; map_read_request=1;
      @(negedge clk); #0.002; map_read_request=0;
      deadline=0;
      while (read_outstanding && deadline<12) begin @(negedge clk); deadline=deadline+1; end
      if (read_outstanding) fail("bounded map read timeout");
      // Deterministic consumer bubbles, including every physical segment boundary.
      repeat (p%4) @(negedge clk);
      check_tuple(epoch,source_base);
      if (accepted_score_count-accepted_origin!=SELECTED || map_publish_count!=epoch)
        fail("admission/publication advanced while complete map retained");
    end
    @(negedge clk); #0.002; map_release_bank=bank; map_release=1;
    @(negedge clk); #0.002; map_release=0;
    repeat (BINS+32) @(negedge clk);
    // Reconcile the offered sample at the actual consuming slow edge, not at
    // negedge+settle when a valid offer may still await its positive edge.
    @(posedge clk); #0.002;
    if (map_ready_mask || map_read_error_count || map_release_error_count ||
        accepted_score_count-accepted_origin!=SELECTED || map_publish_count!=epoch ||
        source_count<=source_before+100 || source_checked!=source_count)
      fail("release/continued source/post-terminal fence mismatch");
    retained_source_count=source_count-source_before;
    check_tuple(epoch,source_base); healthy();
  endtask
  task automatic full_map;
    start_epoch();
    wait(score_count>=SELECTED/2+13); request_stop();
    // stop_done/ACK are registered together. Observe ACK at its next real
    // receiving positive edge before testing that edge's timestamp/inventory.
    wait(stop_done); repeat (2) @(negedge clk); #0.002;
    if (enable || !final_score_accepted || observed_residue!=239 ||
        accepted_score_count-accepted_origin!=SELECTED || map_publish_count!=epoch ||
        source_checked<SUPPORT || inverse_count<BLOCKS*512 ||
        score_count<SELECTED || score_count>FULL_SCORES ||
        terminal_ns<=publish_ns || publish_ns<final_accept_ns ||
        dut.phase_map.write_pending || dut.phase_map.update_pending || dut.phase_map.publish_pending) begin
      $display("BANK_PRODUCTION_MAP_TERMINAL_DETAIL enable=%b final=%b residue=%0d selected=%0d published=%0d source_checked=%0d support=%0d inverse=%0d required_inverse=%0d visible=%0d upper_visible=%0d terminal_ns=%0.3f publish_ns=%0.3f final_accept_ns=%0.3f write=%b update=%b publish=%b",
        enable,final_score_accepted,observed_residue,accepted_score_count-accepted_origin,map_publish_count,
        source_checked,SUPPORT,inverse_count,BLOCKS*512,score_count,FULL_SCORES,
        terminal_ns,publish_ns,final_accept_ns,dut.phase_map.write_pending,
        dut.phase_map.update_pending,dut.phase_map.publish_pending);
      fail("full-map count/support/residue/atomic-publication/terminal inventory mismatch");
    end
    stop_source_count=source_count;
    check_tuple(epoch,source_base);
    last_complete_base=source_base;
    read_all_release();
    if (`IQ.pipeline_active || `ISLAND.core_aresetn || `ISLAND.core_input_valid || score_valid)
      fail("coarse not quiescent after boundary disable/release");
    complete_visible_sum=complete_visible_sum+score_count;
    $display("BANK_PRODUCTION_MAP_COMPLETE epoch=%0d bins=%0d frames=%0d selected=%0d residue=%0d fft_support=%0d source_at_stop=%0d potential_tail=%0d visible_scores=%0d visible_tail=%0d forward_input=%0d inverse_input=%0d forward=%0d product=%0d inverse=%0d energies=%0d ratios=%0d retained_source=%0d map_words=%0d elapsed_ns=%0.3f",
      epoch,BINS,FRAMES,SELECTED,observed_residue,SUPPORT,stop_source_count,FULL_SCORES-SELECTED,
      score_count,score_count-SELECTED,forward_input_count,inverse_input_count,forward_count,product_count,inverse_count,
      prepare_count,ratio_count,retained_source_count,BINS,terminal_ns-epoch_begin_ns);
  endtask
  task automatic partial_recovery;
    start_epoch();
    wait(score_count>=400); request_stop();
    wait(accepted_score_count-accepted_origin==447);
    @(negedge clk); #0.002; expected_abort=1; auto_disable=0; enable=0;
    wait(stop_done); repeat (40) @(negedge clk);
    #0.002;
    if (stop_complete || !stop_failed || !stop_failure_reason[3] || !stop_failure_reason[1] ||
        !stop_has_map || stop_generation!=COMPLETE_EPOCHS || stop_start_index!==last_complete_base ||
        stop_end_index!==last_complete_base+SELECTED || discontinuity_abort_count!=1 ||
        !map_counter_fault || detector_health_flags!=0 ||
        accepted_score_count-accepted_origin!=447 || score_count!=447 || map_ready_mask ||
        map_publish_count!=COMPLETE_EPOCHS || `IQ.pipeline_active || `ISLAND.core_aresetn) begin
      $display("BANK_PRODUCTION_MAP_ABORT_DETAIL complete=%b failed=%b reason=%0d has_map=%b generation=%0d start=%0d expected_start=%0d end=%0d abort_count=%0d native_map_fault=%b detector_flags=%08h admitted=%0d visible=%0d ready=%b publish_count=%0d pipeline_active=%b core_resetn=%b",
        stop_complete,stop_failed,stop_failure_reason,stop_has_map,stop_generation,stop_start_index,
        last_complete_base,stop_end_index,discontinuity_abort_count,map_counter_fault,
        detector_health_flags,accepted_score_count-accepted_origin,score_count,map_ready_mask,
        map_publish_count,`IQ.pipeline_active,`ISLAND.core_aresetn);
      fail("fresh447 exact recovery prefix/explicit partial-abort/historical publication classification mismatch");
    end
    healthy();
    partial_visible=score_count;
    $display("BANK_PRODUCTION_MAP_PARTIAL fresh_scores=447 accepted=447 aborts=1 failed=1 historical_generation=%0d reason=%0d full_production_map_recovery=0",
      stop_generation,stop_failure_reason);
  endtask
  integer iteration;
  initial begin
    if (PRODUCTION!=0 && PRODUCTION!=1) fail("invalid opt-in geometry");
    $readmemh("period_ci16.mem",period_words); $readmemh("forward_q17.mem",forwards);
    $readmemh("product_q17.mem",products); $readmemh("inverse_q17.mem",inverses);
    $readmemh("forward_exponents.mem",ef); $readmemh("inverse_exponents.mem",ei);
    $readmemh("power_shift_u7.mem",shifts); $readmemh("energies_u38.mem",energies);
    $readmemh("numerators_u69.mem",numerators); $readmemh("denominators_u69.mem",denominators);
    $readmemh("saturated_u1.mem",saturated); $readmemh("scores_u8.mem",scores);
    if (PRODUCTION) $readmemh("map_production_u16.mem",expected_map);
    else $readmemh("map_smoke_u16.mem",expected_map);
    repeat (8) @(negedge clk); #0.002; resetn=1; fft_resetn=1;
    repeat (BINS+32) @(negedge clk);
    for (iteration=0;iteration<COMPLETE_EPOCHS;iteration=iteration+1) full_map();
    partial_recovery();
    repeat (100) @(negedge clk);
    if (terminal_count!=COMPLETE_EPOCHS+1 || map_words!=COMPLETE_EPOCHS*BINS ||
        accepted_score_count!=COMPLETE_EPOCHS*SELECTED+447 ||
        total_scores!=complete_visible_sum+partial_visible ||
        progress!=(PRODUCTION ? 6 : 0) || read_outstanding || map_ready_mask)
      fail("final exact inventory mismatch");
    $display("BANK_PRODUCTION_MAP_TOTAL exact_scores=%0d admitted_scores=%0d visible_tail_scores=%0d exact_source=%0d exact_forward_input=%0d exact_inverse_input=%0d exact_forward=%0d exact_product=%0d exact_inverse=%0d exact_energies=%0d exact_ratios=%0d exact_map_words=%0d terminals=%0d",
      total_scores,accepted_score_count,total_scores-accepted_score_count,total_source,total_forward_input,total_inverse_input,total_forward,total_product,
      total_inverse,total_prepare,total_ratio,map_words,terminal_count);
    $display("BANK_PRODUCTION_MAP_PASS production=%0d complete_maps=%0d fresh_partial=447 actual_core=1 slow_mhz=100 fft_mhz=175 PERIODIC_GEOMETRY_ARITHMETIC_NOT_RF_OR_PHYSICAL_TIMING",PRODUCTION,COMPLETE_EPOCHS);
    $finish;
  end
endmodule
`undef IQ
`undef ISLAND
`undef PREP
