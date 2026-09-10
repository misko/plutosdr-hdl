// Additive expected-expiry context. Hierarchy is observation only; all writes AXI.
  localparam [63:0] LATE_TRIGGER=64'd34359740288,LATE_LAST=64'd34359740448;
  integer late_public_submits=0,late_wrapper_handshakes=0,late_fifo_accepts=0,late_handshakes=0;
  integer late_config_seen=0,late_handshake_cycle=-1,late_observation_cycle=-1;
  integer late_register_reads=0,late_snapshots=0,late_fft_after=0,late_pilot_after=0;
  integer late_sample_checks=0,late_control_checks=0;
  reg late_observation_done=0;
  reg [63:0] late_handshake_index=0;
  reg signed [63:0] late_signed_lead=0;
  reg [31:0] late_registers[0:61];

  task automatic native_configuration_guard;
    if(native_configured===1'b0) begin
      if({source_enable,sample_strobe}!==0) fail("late coefficient preparation source not disabled");
      case (`N60_RAW.i_sliding_correlator.state)
        `N60_RAW.i_sliding_correlator.STATE_IDLE:
          if(`N60_RAW.correlator_busy!==0) fail("late coefficient idle unexpectedly busy");
        `N60_RAW.i_sliding_correlator.STATE_COEFFICIENT_ENERGY,
        `N60_RAW.i_sliding_correlator.STATE_COEFFICIENT_ENERGY_FLUSH,
        `N60_RAW.i_sliding_correlator.STATE_COEFFICIENT_CHECK,
        `N60_RAW.i_sliding_correlator.STATE_COEFFICIENT_COPY,
        `N60_RAW.i_sliding_correlator.STATE_COEFFICIENT_COPY_FINISH:
          if(`N60_RAW.correlator_busy!==1) fail("late coefficient preparation lacks exact busy");
        default: fail("late coefficient preparation entered job or unknown state");
      endcase
    end else if(native_configured===1'b1) begin
      if(`N60_RAW.i_sliding_correlator.state!==`N60_RAW.i_sliding_correlator.STATE_IDLE ||
          `N60_RAW.correlator_busy!==0) fail("late post-ready native engine not exactly idle");
    end else fail("late unknown configuration flag");
  endtask
  task automatic native_healthy;
    native_configuration_guard();
    if({native_injected,native_irq,native.result_available,native.result_word_read,native.result_release,
        native.candidate_command_overrun_count,native.coefficient_write_overrun_count,native.queue_overrun_count,
        native.engine_consumed_count,native.correlator_bound_error_count,native.reducer_processed_job_count,
        native.reducer_emitted_result_count,native.reducer_invalid_tuple_count,native.reducer_bound_error_count,
        native.reducer_protocol_error_count,native.result_published_count,native.result_overrun_count,
        native.result_consumed_count,native_admissions,native_capture_count,native_raw_count,
        native_qualified_count,native_packet_reads,native_released}!==0)
      fail("late forbidden native work/result/packet access/release/IRQ or control fault");
    if(native_configured===1'b1) begin
      if(native_engine_idle!==1 || {native.candidate_pending,native.candidate_pending_sync,
          `N60_CORE.raw_result_valid,`N60_CORE.reduced_result_valid}!==0 ||
          (^{`N60_CORE.raw_result_valid,`N60_CORE.raw_result_ready})===1'bx)
        fail("late post-ready native pending/raw/reducer/bridge state unknown or nonempty");
      if(native.active_coefficient_valid!==1 || native.active_coefficient_generation!==NATIVE_GENERATION ||
          native.active_coefficient_energy!==48'd1073758594)
        fail("late prepared264-tap coefficient identity changed");
    end
  endtask
  task automatic native_quiet;
    native_healthy();
    if({source_enable,sample_strobe}!==0 || late_observation_done!==1 || late_handshakes!=1 ||
        late_snapshots!=2 || late_register_reads!=62) fail("late final no-stale source/audit inventory");
  endtask
  always @(posedge sample_clk) if(resetn) begin
    if(native_configured) begin
      late_sample_checks=late_sample_checks+1;
      if((^{`N60_SCHED.command_handshake,`N60_SCHED.command_read_valid,`N60_SCHED.command_read_ready,
          `N60_SCHED.o_capture_valid,`N60_SCHED.o_capture_start,`N60_SCHED.o_capture_done,
          `N60_SCHED.o_capture_abort,`N60_SCHED.o_candidate_pending,`N60_SCHED.o_capture_active})===1'bx)
        fail("late unknown sample-domain command/capture protocol");
    end
    if(`N60_SCHED.command_handshake===1'b1) begin
      if(native_configured!==1 || late_config_seen!=1 || native_command_issued!==1 || late_handshakes!=0 ||
          {source_enable,sample_strobe,continuous_source}!==3'b111 ||
          `N60_SCHED.sample_is_consecutive!==1 || `N60_SCHED.command_late!==1 ||
          {`N60_SCHED.command_duplicate,`N60_SCHED.command_overlap,`N60_SCHED.last_admitted_valid}!==0 ||
          `N60_SCHED.command_request_id!==NATIVE_REQUEST || `N60_SCHED.command_center_index!==NATIVE_CENTER ||
          `N60_SCHED.command_center_timestamp!==NATIVE_CENTER || `N60_SCHED.command_start_index!==NATIVE_CAPTURE_FIRST ||
          (^sample_index)===1'bx || sample_index<LATE_TRIGGER || sample_index>LATE_LAST ||
          native_trigger_cycle<0 || cycles-native_trigger_cycle>256)
        fail("late actual first-request handshake identity/source/coordinate/deadline");
      late_signed_lead=$signed(`N60_SCHED.command_lead);
      if(`N60_SCHED.command_lead!==NATIVE_CAPTURE_FIRST-sample_index-1 ||
          late_signed_lead < -193 || late_signed_lead > -33)
        fail("late actual signed lead differs from fixed expired start");
      late_handshakes=1; late_handshake_index=sample_index; late_handshake_cycle=cycles;
      $display("NATIVE60_LATE_HANDSHAKE index=%0d center=%0d capture_first=%0d lead=%0d trigger_cycle=%0d handshake_cycle=%0d request=%08x generation=%08x consecutive=1 late=1 duplicate=0 overlap=0 last_admitted=0",
        sample_index,NATIVE_CENTER,NATIVE_CAPTURE_FIRST,late_signed_lead,native_trigger_cycle,cycles,NATIVE_REQUEST,NATIVE_GENERATION);
    end
    #0.001;
    if({native.admitted_count,native.completed_capture_count,native.duplicate_count,native.overlap_count,
        native.aborted_count,native.valid_gap_abort_count,native.index_jump_abort_count,native.timestamp_abort_count,
        native.capture_published_count,native.capture_abort_discard_count,native.capture_buffer_overrun_count,
        native.capture_protocol_error_count,`N60_SCHED.o_capture_valid,`N60_SCHED.o_capture_start,
        `N60_SCHED.o_capture_done,`N60_SCHED.o_capture_abort,native.candidate_pending,native.capture_active,
        `N60_SCHED.last_admitted_valid}!==0 || native.rejected_count!==late_handshakes || native.late_count!==late_handshakes)
      fail("late physical same-edge rejection/zero-capture counters violated");
    if(late_handshake_cycle==cycles && late_handshakes==1)
      $display("NATIVE60_LATE_LOCAL_REJECT cycle=%0d index=%0d rejected=1 late=1 admitted=0 pending=0 capture=0 last_admitted=0",cycles,late_handshake_index);
  end
  always @(posedge clk) if(resetn) begin
    native_healthy();
    if(native_configured===1'b1) begin
      late_control_checks=late_control_checks+1;
      if(late_config_seen==0) begin
        late_config_seen=1;
        $display("NATIVE60_LATE_READY cycle=%0d taps=264 generation=60000001 energy=1073758594 engine_idle=1 no_job=1",cycles);
      end
      if((^{native.up_wreq,native.candidate_command_handshake,native.candidate_submit_accepted})===1'bx ||
          (native.up_wreq===1'b1 && (^{native.up_waddr,native.up_wdata})===1'bx))
        fail("late unknown public submission/queue protocol");
    end
    if(native.up_wreq===1'b1 && native.up_waddr==native.REG_CANDIDATE_CONTROL && native.up_wdata[0]) begin
      if(native.up_wdata!==1 || native_command_issued!==1 || native_configured!==1 ||
          {source_enable,sample_strobe,continuous_source}!==3'b111 || late_public_submits!=0 ||
          native.candidate_request_stage!==NATIVE_REQUEST || native.candidate_center_stage!==NATIVE_CENTER ||
          native.candidate_timestamp_stage!==NATIVE_CENTER || sample_index<LATE_TRIGGER || sample_index>LATE_LAST)
        fail("late public submit identity/source/window/repetition");
      late_public_submits=1;
      $display("NATIVE60_LATE_SUBMIT cycle=%0d index=%0d request=%08x center=%0d timestamp=%0d",cycles,sample_index,NATIVE_REQUEST,NATIVE_CENTER,NATIVE_CENTER);
    end
    if(native.candidate_command_handshake===1'b1) begin
      if(late_public_submits!=1 || late_wrapper_handshakes!=0 ||
          native.candidate_pending_request!==NATIVE_REQUEST || native.candidate_pending_center!==NATIVE_CENTER ||
          native.candidate_pending_timestamp!==NATIVE_CENTER) fail("late wrapper command identity/repetition");
      late_wrapper_handshakes=1;
    end
    if(native.candidate_submit_accepted===1'b1) begin
      if(late_wrapper_handshakes!=1 || late_fifo_accepts!=0) fail("late FIFO acceptance order/repetition");
      late_fifo_accepts=1;
    end
    if(late_handshakes==1 && pilot.ddc.accept===1'b1) late_pilot_after=late_pilot_after+1;
    if(native_trigger_cycle>=0 && late_handshakes==0 && cycles-native_trigger_cycle>256)
      fail("late actual sample command handshake exceeded256 cycles");
    if(source_off_cycle>=0 && !late_observation_done && cycles-source_off_cycle>2048)
      fail("late final audit exceeded2048 post-source controls");
  end
  always @(posedge fft_clk) if(resetn && late_handshakes==1 &&
      dut.acquisition.bank_transform.iq_to_score.island.core_input_valid===1'b1 &&
      dut.acquisition.bank_transform.iq_to_score.island.core_input_ready===1'b1 &&
      dut.acquisition.bank_transform.iq_to_score.island.next_inverse===1'b0)
    late_fft_after=late_fft_after+1;

  task automatic late_snapshot(input integer expected_generation);
    reg [31:0] actual,observed_generation;
    integer begin_cycle,generation_cycle;
    begin_cycle=cycles; write_reg(2,8'h68,1); observed_generation=0;
    while(observed_generation!==expected_generation && cycles-begin_cycle<=512)
      read_reg(2,8'h70,observed_generation);
    if(observed_generation!==expected_generation || cycles-begin_cycle>512)
      fail("late public snapshot generation exceeded512 controls");
    generation_cycle=cycles; expect_reg(2,8'h6c,1);
    for(integer word_index=0;word_index<31;word_index=word_index+1) begin
      if(late_registers[2*word_index][31:8]!==0) fail("late register oracle packing");
      read_reg(2,late_registers[2*word_index][7:0],actual);
      if(actual!==late_registers[2*word_index+1]) fail("late exact public counter/empty result mismatch");
      late_register_reads=late_register_reads+1;
      $display("NATIVE60_LATE_REGISTER generation=%0d ordinal=%0d address=%02x data=%08x",expected_generation,word_index,late_registers[2*word_index][7:0],actual);
    end
    expect_reg(2,8'h70,expected_generation); read_reg(2,8'h14,actual);
    if((^actual)===1'bx || actual[7:6]!==0 || cycles-begin_cycle>1328 ||
        late_snapshots!=expected_generation-1 || late_handshakes!=1 ||
        native.candidate_request_stage!==NATIVE_REQUEST || native.candidate_center_stage!==NATIVE_CENTER ||
        native.candidate_timestamp_stage!==NATIVE_CENTER || `N60_SCHED.last_admitted_valid!==0)
      fail("late public audit identity/no-admission/IRQ/state/deadline");
    if(expected_generation==2 && (source_enable!==0 || !source_finished || !coarse_stopped || !map_retained))
      fail("late second audit requires complete source-off and retained coarse map");
    late_snapshots=late_snapshots+1;
    $display("NATIVE60_LATE_AUDIT generation=%0d begin_cycle=%0d generation_cycle=%0d end_cycle=%0d request=%08x center=%0d timestamp=%0d last_admitted=0 rejected=1 late=1 admitted=0 register_reads=31 source=%0d source_off=%0d map_retained=%0d status=%08x",
      expected_generation,begin_cycle,generation_cycle,cycles,NATIVE_REQUEST,NATIVE_CENTER,NATIVE_CENTER,
      source_checked,source_finished,map_retained,actual);
  endtask
  task automatic run_native_command;
    reg [63:0] current_index;
    $readmemh("native60_late_registers.mem",late_registers);
    wait(source_enable===1'b1 && sample_strobe===1'b1 && sample_index>=LATE_TRIGGER);
    if(sample_index!==LATE_TRIGGER || late_config_seen!=1) fail("late trigger/config-ready witness absent");
    native_trigger_cycle=cycles;
    read_reg(2,8'h18,current_index[31:0]); read_reg(2,8'h1c,current_index[63:32]);
    check_native_snapshot(current_index);
    write_reg(2,8'h20,NATIVE_REQUEST); write_reg(2,8'h24,NATIVE_CENTER[31:0]);
    write_reg(2,8'h28,NATIVE_CENTER[63:32]); write_reg(2,8'h2c,NATIVE_CENTER[31:0]);
    write_reg(2,8'h30,NATIVE_CENTER[63:32]);
    native_command_issued=1; write_reg(2,8'h34,1);
    wait(late_handshakes==1); repeat(8) @(negedge clk);
    // Eight falling edges can span only seven labels after a sample-domain
    // event. Preserve those edges, then meet the ORIGINAL >=8-label bound.
    while(cycles-late_handshake_cycle<8) @(negedge clk);
    late_snapshot(1);
    wait(source_finished && coarse_stopped && map_retained); repeat(8) @(negedge clk);
    while(cycles-source_off_cycle<8) @(negedge clk);
    late_snapshot(2);
    native_healthy();
    if(late_public_submits!=1 || late_wrapper_handshakes!=1 || late_fifo_accepts!=1 ||
        late_handshakes!=1 || late_register_reads!=62 || late_snapshots!=2 ||
        !late_fft_after || !late_pilot_after || source_checked!=16425 || cycles-source_off_cycle>2048)
      fail("late full-source rejection/independent FFT/pilot/audit inventory");
    late_observation_cycle=cycles; late_observation_done=1;
    $display("NATIVE60_LATE_OBSERVATION cycle=%0d public_submit=1 wrapper_handshake=1 fifo_accept=1 sample_handshake=1 rejected=1 late=1 admitted=0 capture=0 raw=0 qualified=0 packet_reads=0 result=0 irq=0 register_reads=62 snapshots=2 source=16425",cycles);
  endtask
