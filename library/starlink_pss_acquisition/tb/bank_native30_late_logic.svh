// Included only by the strictly derived late-command fixture. Public132-tap
// setup is unchanged. This expected rejection never qualifies a healthy job.
  localparam [63:0] LATE_TRIGGER=64'd17179870160,LATE_LAST=64'd17179870240;
  localparam [63:0] LATE_OBSERVE=64'd17179875609;
  integer late_handshakes=0,late_trigger_cycle=-1,late_handshake_cycle=-1;
  integer late_config_seen=0,late_observation_source=-1;
  reg [63:0] late_handshake_index=0;
  reg signed [63:0] late_signed_lead=0;

  task automatic native_healthy;
    if ({native_injected,native.candidate_command_overrun_count,native.coefficient_write_overrun_count,
        native.queue_overrun_count,native.admitted_count,native.completed_capture_count,
        native.duplicate_count,native.overlap_count,native.aborted_count,native.valid_gap_abort_count,
        native.index_jump_abort_count,native.timestamp_abort_count,native.capture_published_count,
        native.capture_abort_discard_count,native.capture_buffer_overrun_count,native.capture_protocol_error_count,
        native.correlator_bound_error_count,native.reducer_invalid_tuple_count,native.reducer_bound_error_count,
        native.reducer_protocol_error_count,native.result_overrun_count} !== 0)
      fail("late case unexpected counter or non-late failure");
    if (native_configured) begin
      if ({native_irq,native.result_available,native.candidate_pending_sync[1],native.capture_active,
          `HN_RAW.correlator_busy,`HN_CORE.raw_result_valid,native.engine_consumed_count,
          native.reducer_processed_job_count,native.reducer_emitted_result_count,native.result_published_count,
          native.result_consumed_count,native_capture_count,native_raw_count,native_qualified_count,native_packet_reads} !== 0)
        fail("late case produced forbidden native capture/compute/tuple/result/IRQ");
      if (native.active_coefficient_valid!==1 || native.active_coefficient_generation!==NATIVE_GENERATION ||
          native.active_coefficient_energy!==48'd1073746351)
        fail("late case lost independently prepared132-tap coefficient identity");
      if (native.rejected_count!==late_handshakes || native.late_count!==late_handshakes)
        fail("late case rejection count differs from actual handshake");
    end
  endtask
  always @(posedge sample_clk) if (resetn) begin
    if (`HN_SCHED.command_handshake) begin
      if (!native_configured || !late_config_seen || !native_command_issued || late_handshakes ||
          source_enable!==1 || sample_strobe!==1 || `HN_SCHED.command_late!==1 ||
          {`HN_SCHED.command_duplicate,`HN_SCHED.command_overlap}!==0 ||
          `HN_SCHED.command_center_index!==NATIVE_CENTER || `HN_SCHED.command_center_timestamp!==NATIVE_CENTER ||
          `HN_SCHED.command_request_id!==NATIVE_REQUEST || sample_index<LATE_TRIGGER || sample_index>LATE_LAST ||
          cycles-late_trigger_cycle>256)
        fail("late actual handshake coordinate/identity/deadline mismatch");
      late_signed_lead=$signed(`HN_SCHED.command_lead);
      if (`HN_SCHED.command_lead!==NATIVE_CAPTURE_FIRST-sample_index-1 ||
          late_signed_lead < -113 || late_signed_lead > -33)
        fail("late actual signed lead does not match fixed capture coordinate");
      late_handshakes=late_handshakes+1; late_handshake_index=sample_index; late_handshake_cycle=cycles;
      $display("NATIVE30_LATE_HANDSHAKE trigger=%0d index=%0d capture_start=%0d signed_lead=%0d elapsed_cycles=%0d",
        LATE_TRIGGER,sample_index,NATIVE_CAPTURE_FIRST,late_signed_lead,cycles-late_trigger_cycle);
    end
    #0.001;
    if (native_configured && {`HN_SCHED.o_capture_valid,`HN_SCHED.o_capture_start,`HN_SCHED.o_capture_done,
        `HN_SCHED.o_capture_abort,`HN_SCHED.o_candidate_pending,`HN_SCHED.o_capture_active}!==0)
      fail("late case emitted source-domain capture event");
  end
  always @(posedge clk) if (resetn) begin
    native_healthy();
    if (native_configured && !late_config_seen) begin
      late_config_seen=1;
      $display("NATIVE30_LATE_CONFIG_READY taps=132 generation=30000001 energy=1073746351 no_job=1");
    end
    if (late_trigger_cycle>=0 && !late_handshakes && cycles-late_trigger_cycle>256)
      fail("late command never reached actual scheduler within frozen256 clocks");
  end
  task automatic run_native_command;
    reg [63:0] current_index;
    reg [31:0] telemetry_generation;
    integer snapshot_cycle;
    wait(source_enable && sample_strobe && sample_index>=LATE_TRIGGER);
    late_trigger_cycle=cycles;
    if (sample_index!==LATE_TRIGGER || !late_config_seen) fail("late trigger/config witness missing");
    read_reg(2,8'h18,current_index[31:0]); read_reg(2,8'h1c,current_index[63:32]);
    if (current_index<NATIVE_CAPTURE_FIRST || current_index>LATE_LAST)
      fail("late public telemetry does not prove already-passed capture start");
    write_reg(2,8'h20,NATIVE_REQUEST); write_reg(2,8'h24,NATIVE_CENTER[31:0]);
    write_reg(2,8'h28,NATIVE_CENTER[63:32]); write_reg(2,8'h2c,NATIVE_CENTER[31:0]);
    write_reg(2,8'h30,NATIVE_CENTER[63:32]);
    native_command_issued=1; write_reg(2,8'h34,1);
    wait(late_handshakes==1); repeat(8) @(negedge clk);
    snapshot_cycle=cycles; write_reg(2,8'h68,1); telemetry_generation=0;
    while(telemetry_generation==0 && cycles-snapshot_cycle<=512) read_reg(2,8'h70,telemetry_generation);
    if (telemetry_generation!==1 || cycles-snapshot_cycle>512) fail("late telemetry snapshot deadline");
    expect_reg(2,8'h6c,1);
    for(integer word=0;word<14;word=word+1)
      expect_reg(2,8'h84+4*word,(word==2 || word==3) ? 1 : 0);
    expect_reg(2,8'h70,1); expect_reg(2,8'h5c,32'h1a000000);
    expect_reg(2,8'hbc,0); expect_reg(2,8'hc4,0); expect_reg(2,8'hc8,0);
    expect_reg(2,8'hd8,0); expect_reg(2,8'he0,0);
    wait(source_enable && sample_strobe && sample_index>=LATE_OBSERVE);
    @(negedge clk); native_healthy();
    late_observation_source=sample_index;
    if (native_admissions || native_capture_count || native_raw_count || native_qualified_count ||
        native_packet_reads || late_handshakes!=1 || !late_config_seen)
      fail("late negative terminal inventory");
    native_done=1; $fclose(native_raw_fd);
    $display("NATIVE30_LATE_REJECT_PASS rejected=1 late=1 admitted=0 capture=0 compute=0 raw=0 qualified=0 packet_reads=0 result=0 irq=0 observation_index=%0d",sample_index);
  endtask
