// Exact8192 active-job deadline, distinct from inactive retained-reader wait.
`timescale 1ns/1ps
module tb;
  parameter integer KIND=0;
  reg clk=0,resetn=0,job_valid=0;always #5 clk=~clk;
  reg[69:0]job_descriptor={1'b1,64'd999,5'd6};
  reg certified_input_beat=0,certified_input_complete=0,core_event_frame_started=0;
  reg core_output_tvalid=0,core_output_tlast=0,core_status_tvalid=0;
  reg[47:0]core_output_tdata=0;reg[23:0]core_output_tuser=0;
  wire job_ready,busy,commit_pulse,protocol_fault,mailbox_input_valid,mailbox_commit_valid;
  wire[7:0]fault_reasons;
  starlink_pss_result_guard_owner_view #(.USE_COMPLETED_INPUT_FAULT(1),
    .USE_PREFLIGHT_REASON_ONLY(1),.USE_FORWARD_RETIREMENT(1)) dut(
    .clk(clk),.resetn(resetn),.job_valid(job_valid),.job_descriptor(job_descriptor),.job_ready(job_ready),
    .input_bank_reserved(1'b1),.output_bank_reserved(1'b1),
    .certified_input_beat(certified_input_beat),.certified_input_complete(certified_input_complete),
    .final_fence_certified(1'b1),.external_fault_now(1'b0),.phase_input_fault_now(1'b0),
    .completed_input_certified(1'b1),.completed_input_fault_now(1'b0),.preflight_fault_evidence_now(1'b0),
    .core_event_frame_started(core_event_frame_started),.core_output_tdata(core_output_tdata),
    .core_output_tuser(core_output_tuser),.core_output_tvalid(core_output_tvalid),.core_output_tlast(core_output_tlast),
    .core_status_tdata(8'd6),.core_status_tvalid(core_status_tvalid),
    .mailbox_input_ready(1'b1),.mailbox_input_fault(1'b0),.inverse_phase(1'b1),.forward_mailbox_fault(1'b0),
    .busy(busy),.commit_pulse(commit_pulse),.protocol_fault(protocol_fault),.fault_reasons(fault_reasons),
    .mailbox_input_valid(mailbox_input_valid),.mailbox_commit_valid(mailbox_commit_valid));
  integer elapsed,raw_count=0,inputs=0,nonfinal=0;
  initial begin
    repeat(2)@(negedge clk);resetn=1;job_valid=1;
    @(posedge clk);#0.001;if(!busy||dut.age!=0)$fatal(1,"active watchdog admission anchor");
    @(negedge clk);job_valid=0;
    for(elapsed=1;elapsed<=8192;elapsed=elapsed+1)begin
      certified_input_beat=elapsed<=512;certified_input_complete=elapsed==512;
      core_event_frame_started=elapsed==1;
      core_output_tvalid=KIND==1&&elapsed>=514&&elapsed<=1025;
      core_output_tlast=elapsed==1025;
      core_output_tuser={3'b0,5'd6,7'b0,9'(elapsed-514)};
      core_output_tdata={6'b0,18'(elapsed),6'b0,18'(elapsed*3)};
      core_status_tvalid=KIND==2&&elapsed==514;
      #0.001;
      if(protocol_fault!==0||dut.age!=elapsed-1||dut.watchdog_error!==(elapsed==8192)||mailbox_commit_valid!==0)
        $fatal(1,"exact watchdog preedge kind=%0d elapsed=%0d age=%0d reasons=%h",KIND,elapsed,dut.age,fault_reasons);
      if(certified_input_beat)inputs=inputs+1;
      if(core_output_tvalid)raw_count=raw_count+1;
      if(mailbox_input_valid)nonfinal=nonfinal+1;
      @(posedge clk);#0.001;
      if(elapsed<8192&&(protocol_fault!==0||busy!==1))$fatal(1,"early active deadline");
      if(elapsed==8192&&(fault_reasons!==8'h80||busy!==0||mailbox_commit_valid!==0))$fatal(1,"missing exact deadline quarantine");
      @(negedge clk);
    end
    if(inputs!=512||raw_count!=(KIND==1?512:0)||nonfinal!=(KIND==1?511:0))$fatal(1,"watchdog protocol inventory");
    repeat(10)@(negedge clk);
    if(fault_reasons!==8'h80||job_ready!==0)$fatal(1,"watchdog sticky until common reset");
    $display("OFFLINE_PASS active watchdog8192 kind=%0d input=%0d raw=%0d nonfinal=%0d no_publication=1",KIND,inputs,raw_count,nonfinal);$finish;
  end
  initial begin #90000;$fatal(1,"bounded watchdog test timeout");end
endmodule
