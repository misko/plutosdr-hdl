// Unchanged input guard, real state transitions. Probes never clock bad/XZ controls.
`timescale 1ns/1ps
module tb;
  reg clk=0,resetn=0,job_start=0,input_enable=0,input_valid=0,core_input_tready=0;
  reg[69:0]job_descriptor=70'h12345,input_metadata=70'h12345;
  reg[35:0]input_data=0;reg[8:0]input_position=0;reg input_last=0;
  wire[47:0]core_input_tdata;wire core_input_tvalid,core_input_tlast;
  wire certified_input_beat,certified_input_complete,input_complete,duplicate_start_fault_now;
  wire input_ready,input_transport_ready,fault_now,protocol_fault;
  wire[2:0]fault_events_now,fault_reasons;
  wire offered_beat=input_valid&&input_transport_ready;
  wire offered_end=offered_beat&&input_last;
  starlink_pss_realtime_input_guard_local_admission #(.LOCAL_FIRST_ADMISSION(1),.BALANCED_IDENTITY_EQ(1)) dut(.*);
  integer n,v,r,j,checks=0,zero_checks=0,unknown_offer=0,mask_checks=0,masked_identity=0;
  reg route;
  function automatic q(input integer x);
    case(x%4)0:q=0;1:q=1;2:q=1'bx;3:q=1'bz;endcase
  endfunction
  task tick;begin #5;clk=1;#0.001;#4.999;clk=0;end endtask
  task check;
    begin
      #0.001;
      if(fault_now===1'b0)begin
        if({offered_beat,offered_end}!=={certified_input_beat,certified_input_complete})
          $fatal(1,"real input offered premise mismatch pos=%d enable=%b valid=%b ready=%b last=%b metadata=%h",n,input_enable,input_valid,core_input_tready,input_last,input_metadata);
        zero_checks=zero_checks+1;
        if(offered_beat===1'bx)unknown_offer=unknown_offer+1;
        if(^input_metadata===1'bx)masked_identity=masked_identity+1;
        for(r=0;r<4;r=r+1)begin
          route=q(r);
          if({offered_beat&&route,offered_end&&route}!==
             {certified_input_beat&&route,certified_input_complete&&route})
            $fatal(1,"per-owner summary route mismatch");
          mask_checks=mask_checks+1;
        end
      end
      checks=checks+1;
    end
  endtask
  task perturb;
    begin
      // Seven four-state controls. Ordinal/identity are correct, wrong, X, Z.
      for(v=0;v<16384;v=v+1)begin
        input_enable=q(v);input_valid=q(v/4);core_input_tready=q(v/16);input_last=q(v/64);
        input_position=n;case((v/256)%4)1:input_position=n^1;2:input_position=9'bx;3:input_position=9'bz;endcase
        input_metadata=job_descriptor;
        case((v/1024)%4)1:input_metadata=job_descriptor^1;2:input_metadata=70'bx;3:input_metadata=70'bz;endcase
        job_start=q(v/4096);check();
      end
      job_start=0;input_enable=1;input_valid=1;core_input_tready=1;
      input_position=n;input_last=(n==511);input_metadata=job_descriptor;
    end
  endtask
  initial begin
    tick();resetn=1;job_start=1;tick();job_start=0;
    input_enable=1;input_valid=1;core_input_tready=1;
    for(n=0;n<512;n=n+1)begin
      if(n==0||n==1||n==511)perturb();
      input_position=n;input_last=(n==511);#0.001;
      if(certified_input_beat!==1||certified_input_complete!==(n==511))$fatal(1,"healthy physical input certificate");
      tick();
    end
    n=511;perturb();
    if(input_complete!==1||dut.slot_open!==0)$fatal(1,"closed input state lost");
    job_start=1;#0.001;if(fault_now!==1||offered_beat!==0)$fatal(1,"closed duplicate not independent of offered beat");
    resetn=0;#0.001;
    if(certified_input_beat!==0||certified_input_complete!==0)$fatal(1,"reset certificate leak");
    if(checks!=65536||zero_checks<1000||unknown_offer==0||masked_identity==0||mask_checks!=4*zero_checks)
      $fatal(1,"real input premise inventory");
    $display("OFFLINE_PASS real_input512 probes=%0d known_zero=%0d unknown_offer=%0d masked_identity=%0d owner_masks=%0d",checks,zero_checks,unknown_offer,masked_identity,mask_checks);$finish;
  end
endmodule
