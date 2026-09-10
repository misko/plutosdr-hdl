// Real unchanged input guard, no core model and no hierarchical state writes.
`timescale 1ns/1ps
module tb;
  reg clk=0,resetn=0,job_start=0,input_enable=0,input_valid=0,core_input_tready=0;
  reg[69:0]job_descriptor=70'h12345,input_metadata=70'h12345;
  reg[35:0]input_data=0;reg[8:0]input_position=0;reg input_last=0;
  wire[47:0]core_input_tdata;wire core_input_tvalid,core_input_tlast;
  wire certified_input_beat,certified_input_complete,input_complete,duplicate_start_fault_now;
  wire input_ready,input_transport_ready,fault_now,protocol_fault;
  wire[2:0]fault_events_now,fault_reasons;
  starlink_pss_realtime_input_guard_local_admission #(.LOCAL_FIRST_ADMISSION(1),.BALANCED_IDENTITY_EQ(1)) dut(.*);
  integer n,k,checks=0;reg[83:0]controls;
  task tick;begin #5;clk=1;#0.001;#4.999;clk=0;end endtask
  task check_closed;
    begin
      #0.001;
      if(input_complete!==1 || dut.slot_open!==0 || core_input_tvalid!==0 ||
         {certified_input_beat,certified_input_complete}!==2'b0)
        $fatal(1,"closed real input guard certified a strobe controls=%h",controls);
      checks=checks+1;
    end
  endtask
  initial begin
    tick();resetn=1;job_start=1;tick();job_start=0;
    input_enable=1;input_valid=1;core_input_tready=1;
    for(n=0;n<512;n=n+1)begin
      input_position=n;input_last=(n==511);#0.001;
      if(input_complete!==0 || certified_input_beat!==1 || certified_input_complete!==(n==511))
        $fatal(1,"pre-final current input authority n=%0d",n);
      tick();
    end
    check_closed();
    // Binary controls plus single X/Z in all metadata, position, LAST and
    // enable/valid/READY/start positions; no sampling-edge race is used.
    for(k=0;k<84;k=k+1)begin
      controls=84'b1<<k;
      {input_metadata,input_position,input_last,input_enable,input_valid,core_input_tready,job_start}=controls;check_closed();
      controls=0;controls[k]=1'bx;
      {input_metadata,input_position,input_last,input_enable,input_valid,core_input_tready,job_start}=controls;check_closed();
      controls[k]=1'bz;
      {input_metadata,input_position,input_last,input_enable,input_valid,core_input_tready,job_start}=controls;check_closed();
    end
    job_descriptor=70'bx;check_closed();job_descriptor=70'bz;check_closed();
    job_start=1;#0.001;
    if(duplicate_start_fault_now!==1)$fatal(1,"duplicate-start veto lost in closed phase");
    resetn=0;#0.001;
    if(input_complete!==0 || certified_input_beat!==0 || certified_input_complete!==0)
      $fatal(1,"reset did not purge closed epoch");
    if(checks!=255)$fatal(1,"closed real guard inventory");
    $display("OFFLINE_PASS real guard final_input_pre0_post1 checks=%0d duplicate1 reset0",checks);$finish;
  end
endmodule
