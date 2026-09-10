`timescale 1ns/1fs
// OFFLINE SCHEDULING MODEL, not an actual vendor FFT replay. The transparent
// active-region ready copy explicitly models an input alias delta that Icarus
// may otherwise collapse; it adds no simulated time and no hardware behavior.
module tb_starlink_pss_local_admission_schedule;
  parameter integer ORIGINAL_DUT=0, ACTIVE_COPY=1, FAULT=0;
  reg clk, resetn, ready;
  reg job_start,input_enable,input_valid,input_last;
  reg [69:0] job_descriptor,input_metadata;
  reg [35:0] input_data;
  reg [8:0] input_position;
`ifdef ORIGINAL_GUARD_DUT
  local_admission_original_guard #(.BALANCED_IDENTITY_EQ(1)) dut (
`else
  starlink_pss_realtime_input_guard_local_admission #(.BALANCED_IDENTITY_EQ(1),.LOCAL_FIRST_ADMISSION(1)) dut (
`endif
    .clk(clk),.resetn(resetn),.job_start(job_start),.job_descriptor(job_descriptor),
    .input_enable(input_enable),.input_valid(input_valid),.input_data(input_data),
    .input_position(input_position),.input_last(input_last),.input_metadata(input_metadata),.core_input_tready(ready));
  wire observed_ready;
  generate if(ACTIVE_COPY) begin : explicit_active_copy
    reg copy;
    always @(dut.core_input_tready) copy=dut.core_input_tready;
    assign observed_ready=copy;
  end else begin : direct_port
    assign observed_ready=dut.core_input_tready;
  end endgenerate
  starlink_pss_local_admission_actual_observer #(.L(1)) observer (
    .clk(dut.clk),.resetn(dut.resetn),.job_start(dut.job_start),.job_descriptor(dut.job_descriptor),
    .input_enable(dut.input_enable),.input_valid(dut.input_valid),.input_data(dut.input_data),
    .input_position(dut.input_position),.input_last(dut.input_last),.input_metadata(dut.input_metadata),.core_input_tready(observed_ready),
    .actual_view({dut.input_ready,dut.input_transport_ready,dut.core_input_tdata,
      dut.core_input_tvalid,dut.core_input_tlast,dut.certified_input_beat,dut.certified_input_complete,
      dut.input_complete,dut.fault_now,dut.duplicate_start_fault_now,dut.fault_events_now,
      dut.protocol_fault,dut.fault_reasons,dut.job_started,dut.input_started,dut.descriptor,dut.expected_position,
      dut.slot_open,dut.eligible,dut.metadata_valid,dut.identity_matches,dut.errors_now,
      dut.framing_error,dut.delivery_error,dut.duplicate_start}));
  integer clock_events=0, reset_events=0, nba_checks=0, healthy_words=0, unknown_resets=0;
  always @(posedge clk or negedge clk) clock_events=clock_events+1;
  always @(negedge resetn) reset_events=reset_events+1;
  reg nba_tag=0, old_nba_tag;
  always @(posedge clk) begin
    old_nba_tag=nba_tag;
    nba_tag<=!nba_tag;
    #0;
    if(nba_tag!==old_nba_tag) $fatal(1,"INACTIVE_CHECK_CONSUMED_NBA");
    nba_checks=nba_checks+1;
    #0.001;
    if(nba_tag!==!old_nba_tag) $fatal(1,"POST_CHECK_PRECEDED_NBA");
  end
  task counts;
    begin
      if(observer.pre_checks!==clock_events || observer.post_checks!==clock_events || observer.reset_checks!==reset_events)
        $fatal(1,"CLOCK_OR_RESET_EVENT_WAS_DROPPED");
    end
  endtask
  task tick;
    begin #1;clk=1;#1;clk=0;#0.003;counts();end
  endtask
  task purge;
    begin
      job_start=0;input_enable=0;input_valid=0;input_last=0;ready=0;
      input_data=0;input_metadata=0;input_position=0;job_descriptor=0;
      resetn=0;#1;counts();resetn=1;tick();
    end
  endtask
  reg [69:0] saved_descriptor;
  reg fault_overlay=0;
  reg [47:0] data_overlay;
  integer position;
  initial begin
`ifdef ORIGINAL_GUARD_DUT
    if(ORIGINAL_DUT!==1) $fatal(1,"WRONG_ORIGINAL_CONTROL_BINDING");
`else
    if(ORIGINAL_DUT!==0 || dut.LOCAL_FIRST_ADMISSION!==1) $fatal(1,"WRONG_CANDIDATE_BINDING");
`endif
    // Explicit time-zero initialization event after processes are installed.
    // All other inputs remain X here, as in the observed failing context.
    #0;ready=0;clk=0;
    #1;counts();purge();
    resetn=1'bx;#1;resetn=0;#1;counts();unknown_resets=unknown_resets+1;
    resetn=1'bz;#1;resetn=0;#1;counts();unknown_resets=unknown_resets+1;
    resetn=1;tick();
    job_descriptor=70'h2123456789abcdef01;input_metadata=job_descriptor;
    job_start=1;tick();job_start=0;input_enable=1;
    for(position=0;position<512;position=position+1) begin
      input_position=position;input_last=(position==511);input_data={18'(position),18'(~position)};
      if(position%17==0) begin
        ready=0;input_valid=0;input_metadata=70'bx;tick();
        input_metadata=70'bz;tick();input_metadata=job_descriptor;
      end
      ready=1;input_valid=1;tick();healthy_words=healthy_words+1;
    end
    if(dut.input_complete!==1 || dut.protocol_fault!==0) $fatal(1,"HEALTHY_GUARD_MODEL_INCOMPLETE");
    purge();
    // Each corruption exists before an edge and is removed only by its NBA.
    // Post-only or +1ps-pre mutants must miss it; the #0 pre check must fail.
    if(FAULT==1 || FAULT==4) begin
      saved_descriptor=dut.descriptor;
      dut.descriptor=saved_descriptor^70'b1;
      dut.descriptor<=saved_descriptor;
    end
    if(FAULT==2) begin
      force dut.fault_now=fault_overlay;
      fault_overlay=1;fault_overlay<=0;
    end
    if(FAULT==3) begin
      data_overlay=dut.core_input_tdata;
      force dut.core_input_tdata=data_overlay;
      data_overlay=data_overlay^48'b1;data_overlay<=0;
    end
    if(FAULT==4) resetn=0;
    else clk=1;
    #1;
    if(FAULT==2) release dut.fault_now;
    if(FAULT==3) release dut.core_input_tdata;
    clk=0;#0.003;counts();
    if(nba_checks<512 || healthy_words!=512 || unknown_resets!=2) $fatal(1,"SCHEDULE_MODEL_COVERAGE_MISSING");
    $display("LOCAL_SCHEDULE_MODEL_PASS original=%0d active_copy=%0d fault=%0d clock_events=%0d reset_events=%0d pre_checks=%0d post_checks=%0d nba_checks=%0d healthy_words=512 unknown_resets=2 no_vendor_replay=1",
      ORIGINAL_DUT,ACTIVE_COPY,FAULT,clock_events,reset_events,observer.pre_checks,observer.post_checks,nba_checks);
    $finish(0);
  end
  initial begin #10000;$fatal(1,"SCHEDULE_MODEL_TIMEOUT");end
endmodule
