`timescale 1ns/1ps
module tb;
  reg clk=0,resetn=0,inverse_admit=0,inverse_publication=0,inverse_guard_ack=0,transfer_consumed=0;
  reg bank_ready=1,bank_request=0,bank_ack_sync=0,common_current_fault=0;
  wire a_reusable,a_reservation,a_retained,a_fault,a_receipt,a_release;
  wire b_reusable,b_reservation,b_retained,b_fault,b_receipt,b_release,known;
  wire [7:0] a_reasons,b_reasons;
  wire [1:0] a_lease,a_held,b_lease,b_held;
  starlink_pss_retained_output_owner a(.*,.reusable(a_reusable),.reservation(a_reservation),
    .retained(a_retained),.fault_now(a_fault),.transfer_receipt(a_receipt),.reader_release(a_release),
    .fault_reasons(a_reasons),.current_lease(a_lease),.admitted_lease(a_held));
  starlink_pss_retained_destination_owner b(.*,.reusable(b_reusable),.reservation(b_reservation),
    .retained(b_retained),.fault_now(b_fault),.transfer_receipt(b_receipt),.reader_release(b_release),
    .fault_reasons(b_reasons),.current_lease(b_lease),.admitted_lease(b_held),.reserved_state_known(known));
  integer checks=0,cases=0,releases=0,unknowns=0,n,phase,k,j;
  function val(input integer v);
    case(v)0:val=0;1:val=1;2:val=1'bx;3:val=1'bz;endcase
  endfunction
  task check;
    begin
      checks=checks+1;
      if({a.reserved,a.published,a.busy_seen,a.expected_request,a.lease,a.held_lease,a_receipt,a_reasons} !==
         {b.reserved,b.published,b.busy_seen,b.expected_request,b.lease,b.held_lease,b_receipt,b_reasons})
        $fatal(1,"DESTINATION_OWNER_STATE17");
      if({a_reusable,a_reservation,a_retained,a_fault,a_receipt,a_release,a_reasons,a_lease,a_held} !==
         {b_reusable,b_reservation,b_retained,b_fault,b_receipt,b_release,b_reasons,b_lease,b_held})
        $fatal(1,"DESTINATION_OWNER_ALL_OUTPUTS");
      if(known!==(a.reserved===1'b0 || a.reserved===1'b1))$fatal(1,"DESTINATION_OWNER_KNOWNNESS");
    end
  endtask
  task tick;
    begin #1;check();if(a_release)releases=releases+1;clk=1;#1;check();clk=0;#1;end
  endtask
  task reset;
    begin
      resetn=0;inverse_admit=0;inverse_publication=0;inverse_guard_ack=0;transfer_consumed=0;
      bank_ready=1;bank_request=0;bank_ack_sync=0;common_current_fault=0;
      tick();resetn=1;tick();
    end
  endtask
  task prepare(input integer state_kind);
    begin
      reset();
      if(state_kind>0)begin inverse_admit=1;tick();inverse_admit=0;end
      if(state_kind>1)begin
        inverse_publication=1;tick();inverse_publication=0;
        bank_request=1;bank_ready=0;tick();
      end
      if(state_kind>2)begin bank_ack_sync=1;bank_ready=1;tick();end
    end
  endtask
  initial begin
    // Every four-state combination of eight public controls, at four natural
    // ownership phases. Bank controls may be invalid caller inputs by design.
    for(phase=0;phase<4;phase=phase+1)for(n=0;n<65536;n=n+1)begin
      prepare(phase);
      inverse_admit=val(n%4);inverse_publication=val((n/4)%4);
      inverse_guard_ack=val((n/16)%4);transfer_consumed=val((n/64)%4);
      bank_ready=val((n/256)%4);bank_request=val((n/1024)%4);
      bank_ack_sync=val((n/4096)%4);common_current_fault=val((n/16384)%4);
      tick();tick();cases=cases+1;
    end
    // Explicit ready-high actual ACK with every current common value. Only
    // known-zero common health may release before the same edge's reason Q.
    for(k=0;k<4;k=k+1)begin
      prepare(3);inverse_guard_ack=1;common_current_fault=val(k);#1;check();
      if(a_release!==(k==0))$fatal(1,"DESTINATION_OWNER_CURRENT_ACK");
      tick();
    end
    // Observation X/Z is checked without changing either original recurrence.
    for(k=2;k<4;k=k+1)begin
      reset();a.reserved=val(k);b.reserved=val(k);#1;check();
      if(known!==0)$fatal(1,"DESTINATION_OWNER_UNKNOWN_Q");unknowns=unknowns+1;
      for(j=0;j<4;j=j+1)begin resetn=val(j);tick();end
    end
    if(cases!=262144||releases==0||unknowns!=2)$fatal(1,"DESTINATION_OWNER_COVERAGE");
    $display("DESTINATION_OWNER_PASS cases=%0d checks=%0d releases=%0d unknowns=%0d",cases,checks,releases,unknowns);
    $finish;
  end
endmodule
