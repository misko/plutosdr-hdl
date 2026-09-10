// OFFLINE control-only stimulus, not a vendor FFT model or timing guarantee.
`timescale 1ns/1ps
module tb;
  parameter integer KIND=0, OFFSET=0;
  reg clk=0, resetn=0, core_resetn=0;
  always #5 clk=~clk;
  reg job_accept=0, job_inverse=0, producer_closed=0, config_accept=0;
  reg input_beat=0, input_complete=0, raw_frame=0, raw_output=0, raw_status=0;
  reg [2:0] raw_vendor_faults=0;
  wire admission_allowed, configuration_allowed, fault_now, routed_inverse;
  wire [7:0] fault_reasons;
  starlink_pss_core_job_cutover dut(.*);
  task tick;
    begin @(posedge clk); #0.001; @(negedge clk); end
  endtask
  task clean;
    begin if (fault_now !== 0 || fault_reasons !== 0) $fatal(1,"unexpected cutover fault %h",fault_reasons); end
  endtask
  task inject;
    begin
      case(KIND)
        1:raw_frame=1; 2:raw_output=1; 3:raw_status=1;
        4:raw_vendor_faults=1; 5:raw_vendor_faults=2; 6:raw_vendor_faults=4;
        7:raw_frame=1'bx; 8:raw_output=1'bx; 9:raw_status=1'bx;
        10:raw_frame=1'bz; 11:raw_output=1'bz; 12:raw_status=1'bz;
        13:core_resetn=1'bx; 14:core_resetn=1'bz;
      endcase
      #0.001;
      // These events belong to a configured guard; the exact guard retains
      // ordinal/frame/duplicate checks. The firewall must not relabel them.
      if ((OFFSET==0 && KIND<=3) || (KIND==1 && OFFSET>=7)) begin
        if(fault_now!==0 || routed_inverse !== (OFFSET==0))
          $fatal(1,"configured raw routing changed");
        $display("OFFLINE_PASS configured raw event delegated to exact owner guard kind=%0d offset=%0d",KIND,OFFSET);
        $finish;
      end
      if (fault_now !== 1) $fatal(1,"raw cutover missed kind%0d offset%0d",KIND,OFFSET);
      tick;
      if (fault_reasons === 0 || (^fault_reasons === 1'bx)) $fatal(1,"not sticky");
      raw_frame=0;raw_output=0;raw_status=0;raw_vendor_faults=0;core_resetn=0;
      repeat(4)tick;
      if (admission_allowed !== 0) $fatal(1,"local reset erased epoch fault");
    end
  endtask
  integer n;
  initial begin
    repeat(2)tick; resetn=1; repeat(2)tick;
    if(admission_allowed !== 1) $fatal(1,"reset minimum");
    job_accept=1; job_inverse=1;tick;job_accept=0;core_resetn=1;tick;
    if(configuration_allowed !== 1) $fatal(1,"quiet release");
    config_accept=1;tick;config_accept=0; input_beat=1;raw_frame=1;tick;
    raw_frame=0;input_complete=1;tick;input_beat=0;input_complete=0;
    raw_output=1;raw_status=1;tick;raw_output=0;raw_status=0;clean;
    // n=0 is producer closure; n=1..2 reset, n=3 private admission,
    // n=4 release, n=5 quiet, n=6 config; no fresh full input through n=13.
    for(n=0;n<=13;n=n+1)begin
      producer_closed=(n==0); job_accept=(n==3); job_inverse=0;
      core_resetn=(n==0 || n>=4);config_accept=(n==6);
      if(KIND!=0 && n==OFFSET)begin inject; $display("OFFLINE_PASS cutover kind=%0d offset=%0d",KIND,OFFSET);$finish;end
      tick; clean;
    end
    if(routed_inverse !== 0 || admission_allowed !== 0) $fatal(1,"owner routing");
    // New matching status before fresh frame/full input is not old-proof evidence.
    raw_status=1;#0.001;if(fault_now!==1)$fatal(1,"early status accepted");tick;
    if(fault_reasons[3]!==1)$fatal(1,"early status reason");
    $display("OFFLINE_PASS cutover healthy closure then expected early-status rejection");$finish;
  end
  initial begin #10000; $fatal(1,"bounded cutover timeout");end
endmodule
