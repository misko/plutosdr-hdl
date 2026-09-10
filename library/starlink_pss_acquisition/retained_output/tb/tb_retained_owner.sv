`timescale 1ns/1ps
module tb;
  parameter integer KIND=0;
  reg clk=0,resetn=0;always #5 clk=~clk;
  reg inverse_admit=0,inverse_publication=0,inverse_guard_ack=0,transfer_consumed=0;
  reg bank_ready=1,bank_request=0,bank_ack_sync=0,common_current_fault=0;
  wire reusable,reservation,retained,fault_now,transfer_receipt,reader_release;
  wire[7:0]fault_reasons;wire[1:0]current_lease,admitted_lease;
  starlink_pss_retained_output_owner dut(.*);
  task tick;begin @(posedge clk);#0.001;@(negedge clk);end endtask
  task clean;begin if(fault_reasons!==0||fault_now!==0)$fatal(1,"unexpected owner fault %h",fault_reasons);end endtask
  integer job;
  initial begin
    repeat(2)tick;resetn=1;tick;
    for(job=0;job<6;job=job+1)begin
      if(reusable!==1||current_lease!==job%4)$fatal(1,"empty lease wrap");
      inverse_admit=1;tick;inverse_admit=0;
      if(reusable!==0||reservation!==1||admitted_lease!==job%4)$fatal(1,"admission binding");
      if(KIND==1)inverse_admit=1;
      if(KIND==2)inverse_guard_ack=1;
      if(KIND==3)bank_ready=1'bx;
      if(KIND==4)bank_request=1'bz;
      if(KIND==5)inverse_publication=1'bx;
      if(KIND==6)transfer_consumed=1;
      if(KIND>=1&&KIND<=6)begin
        tick;if(fault_reasons===0)$fatal(1,"invalid pre-publication event escaped");
        $display("OFFLINE_PASS owner expected rejection kind=%0d",KIND);$finish;
      end
      repeat(3)tick;clean;
      inverse_publication=1;@(posedge clk);#0.001;bank_request=~bank_request;bank_ready=0;
      @(negedge clk);inverse_publication=0;
      if(transfer_receipt!==1||retained!==1)$fatal(1,"real publication receipt");
      repeat(3)tick;clean;
      if(transfer_receipt!==1)$fatal(1,"lost unconsumed transfer");
      if(KIND!=16)begin transfer_consumed=1;tick;transfer_consumed=0;end
      if(transfer_receipt!==(KIND==16)||retained!==1||reusable!==0)$fatal(1,"transfer faked ACK");
      // Reader can remain parked beyond the active guard watchdog.
      repeat(8200)tick;clean;
      if(KIND==7)inverse_publication=1;
      if(KIND==8)begin bank_ready=1;inverse_guard_ack=1;end
      if(KIND==9)bank_request=~bank_request;
      if(KIND==10)begin bank_ack_sync=bank_request;bank_ready=1;inverse_guard_ack=1;common_current_fault=1;end
      if(KIND==11)begin bank_ack_sync=bank_request;bank_ready=1;inverse_guard_ack=1;common_current_fault=1'bx;end
      if(KIND>=12)begin
        bank_ack_sync=bank_request;bank_ready=1;inverse_guard_ack=1;
        case(KIND)
          12:inverse_publication=1;13:inverse_publication=1'bx;
          14:inverse_admit=1'bz;15:transfer_consumed=1;
          16:transfer_consumed=1;17:transfer_consumed=1'bx;18:transfer_consumed=1'bz;
          19:inverse_guard_ack=1'bx;20:inverse_publication=1'bz;
          21:inverse_admit=1;22:inverse_admit=1'bx;23:inverse_guard_ack=1'bz;
        endcase
      end
      if(KIND==16)begin
        #0.001;if(reader_release!==1||transfer_receipt!==1)$fatal(1,"legitimate pending transfer plus ACK stalled");
        tick;transfer_consumed=0;inverse_guard_ack=0;clean;
        if(retained!==0||transfer_receipt!==0||reusable!==1||current_lease!==1)$fatal(1,"coincident obligations did not retire once");
        $display("OFFLINE_PASS owner legitimate pending transfer and real ACK retire together");$finish;
      end
      if(KIND>=7)begin
        #0.001;if(reader_release!==0)$fatal(1,"bad event released retained owner");
        tick;if(fault_reasons===0||reusable!==0||retained!==1)$fatal(1,"expected retained quarantine");
        $display("OFFLINE_PASS owner expected rejection kind=%0d",KIND);$finish;
      end
      bank_ack_sync=bank_request;bank_ready=1;inverse_guard_ack=1;#0.001;
      if(reader_release!==1)$fatal(1,"actual ACK not released");tick;inverse_guard_ack=0;clean;
      if(retained!==0||reusable!==1)$fatal(1,"real ACK retention");
    end
    $display("OFFLINE_PASS owner six leases real ACK including wrap and >8192 wait");$finish;
  end
  initial begin #600000;$fatal(1,"bounded owner timeout");end
endmodule
