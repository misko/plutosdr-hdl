// Module-boundary composition, not whole-island reachability or actual FFT.
// Clock original inverse result guard to real awaiting-ACK; clock the real
// input guard for a later F. Actual owner state/request/ACK are never forced.
`timescale 1ns/1ps
module tb;
  parameter integer KIND=0;
  reg clk=0,resetn=0,input_resetn=0;
  reg job_start=0,input_enable=0,input_valid=0,core_input_tready=0;
  reg[69:0]job_descriptor=70'h12345,input_metadata=70'h12345;
  reg[35:0]input_data=0;reg[8:0]input_position=0;reg input_last=0;
  wire input_fault_now,input_transport_ready,certified_input_beat,certified_input_complete;
  wire summary_offer_beat=input_valid&&input_transport_ready;
  wire summary_offer_complete=summary_offer_beat&&input_last;
  starlink_pss_realtime_input_guard_local_admission #(.LOCAL_FIRST_ADMISSION(1),.BALANCED_IDENTITY_EQ(1)) input_guard(
    .clk(clk),.resetn(input_resetn),.job_start(job_start),.job_descriptor(job_descriptor),
    .input_enable(input_enable),.input_valid(input_valid),.core_input_tready(core_input_tready),
    .input_data(input_data),.input_position(input_position),.input_last(input_last),.input_metadata(input_metadata),
    .input_transport_ready(input_transport_ready),.fault_now(input_fault_now),
    .certified_input_beat(certified_input_beat),.certified_input_complete(certified_input_complete));
  reg inverse_job=0,inverse_beat=0,inverse_end=0,frame=0,raw_valid=0,raw_last=0,status_valid=0;
  reg[23:0]raw_user=0;reg mailbox_ready=1;
  wire inverse_ack,inverse_commit,inverse_fault;
  starlink_pss_result_guard_owner_view inverse_guard(
    .clk(clk),.resetn(resetn),.job_valid(inverse_job),.private_descriptor_offer(1'b0),.job_descriptor(70'h12345),
    .input_bank_reserved(1'b1),.output_bank_reserved(1'b1),.certified_input_beat(inverse_beat),
    .certified_input_complete(inverse_end),.offered_input_beat(1'b0),.offered_input_complete(1'b0),
    .final_fence_certified(1'b1),.external_fault_now(input_fault_now),.phase_input_fault_now(1'b0),
    .completed_input_certified(1'b1),.completed_input_fault_now(input_fault_now),.preflight_fault_evidence_now(1'b0),
    .core_event_frame_started(frame),.core_output_tdata(48'b0),.core_output_tuser(raw_user),
    .core_output_tvalid(raw_valid),.core_output_tlast(raw_last),.core_status_tdata(8'b0),
    .core_status_tvalid(status_valid),.mailbox_input_ready(mailbox_ready),.mailbox_input_fault(1'b0),
    .inverse_phase(1'b1),.forward_mailbox_fault(1'b0),.mailbox_commit_valid(inverse_commit),
    .owner_ack_accept(inverse_ack),.owner_fault_now(inverse_fault));
  reg bank_ready=1,bank_request=0,bank_ack=0,transfer=0,probe_publish=0;
  wire old_release,new_release,old_retained,new_retained,probe_retained;
  wire[7:0]old_reasons,new_reasons,probe_reasons;
  // Exactly the input-only projection of the actual top expressions: all
  // independent roots are zero, local old guard remains visible. Complete
  // root inventory/equivalence is checked separately against actual RTL text.
  wire original_common=input_fault_now||inverse_fault;
  wire offered_common=(input_fault_now!==1'b0);
  starlink_pss_retained_output_owner original_owner(
    .clk(clk),.resetn(resetn),.inverse_admit(inverse_job),.inverse_publication(inverse_commit&&mailbox_ready),
    .inverse_guard_ack(inverse_ack),.transfer_consumed(transfer),.bank_ready(bank_ready),
    .bank_request(bank_request),.bank_ack_sync(bank_ack),.common_current_fault(original_common),
    .reader_release(old_release),.retained(old_retained),.fault_reasons(old_reasons));
  starlink_pss_retained_output_owner summary_owner(
    .clk(clk),.resetn(resetn),.inverse_admit(inverse_job),.inverse_publication(inverse_commit&&mailbox_ready),
    .inverse_guard_ack(inverse_ack),.transfer_consumed(transfer),.bank_ready(bank_ready),
    .bank_request(bank_request),.bank_ack_sync(bank_ack),.common_current_fault(offered_common),
    .reader_release(new_release),.retained(new_retained),.fault_reasons(new_reasons));
  // Separate explicit public-input publication collision; this does not claim
  // two FFT phases can publish/ingest simultaneously in the single-core top.
  starlink_pss_retained_output_owner publication_probe(
    .clk(clk),.resetn(resetn),.inverse_admit(inverse_job),.inverse_publication(probe_publish),
    .inverse_guard_ack(1'b0),.transfer_consumed(1'b0),.bank_ready(1'b1),
    .bank_request(1'b0),.bank_ack_sync(1'b0),.common_current_fault(offered_common),
    .retained(probe_retained),.fault_reasons(probe_reasons));
  integer n;reg[7:0]fault_before;
  task tick;begin #5;clk=1;#0.001;#4.999;clk=0;end endtask
  initial begin
    tick();resetn=1;inverse_job=1;tick();inverse_job=0;
    for(n=0;n<512;n=n+1)begin inverse_beat=1;inverse_end=(n==511);frame=(n==0);tick();end
    inverse_beat=0;inverse_end=0;frame=0;
    for(n=0;n<512;n=n+1)begin raw_valid=1;raw_user=n;raw_last=(n==511);status_valid=(n==0);tick();end
    raw_valid=0;raw_last=0;status_valid=0;#0.001;
    if(inverse_commit!==1||inverse_fault!==0)$fatal(1,"real held-final setup");
    tick();mailbox_ready=0;bank_ready=0;bank_request=1;tick();
    transfer=1;tick();transfer=0;
    if(inverse_guard.awaiting_ack!==1||old_retained!==1||new_retained!==1||
       original_owner.busy_seen!==1||summary_owner.busy_seen!==1||old_reasons!==0||new_reasons!==0)
      $fatal(1,"real old owner/ACK setup");
    input_resetn=1;job_start=1;tick();job_start=0;
    input_enable=1;input_valid=1;core_input_tready=1;
    if(KIND==3)begin
      for(n=0;n<511;n=n+1)begin input_position=n;tick();end
      input_position=511;input_last=0;
    end else if(KIND==4)begin tick();input_position=1;input_valid=0;end
    else if(KIND==1)input_position=1;
    else if(KIND==2)input_last=1;
    else if(KIND==5)begin job_start=1;input_valid=0;core_input_tready=0;end
    else if(KIND==6)input_metadata=70'bx;
    else if(KIND==7)input_metadata=70'bz;
    #0.001;
    if(KIND==0)begin
      if(input_fault_now!==0||summary_offer_beat!==1||certified_input_beat!==1)$fatal(1,"healthy input premise");
    end else begin
      if(KIND<6 && input_fault_now!==1)$fatal(1,"missing direct input fault");
      if(KIND>=6 && input_fault_now!==1'bx)$fatal(1,"missing unknown input fault");
      if((KIND==4||KIND==5) && summary_offer_beat!==0)$fatal(1,"gap/duplicate must not need offered beat");
      if(KIND>=1&&KIND<=3 && (summary_offer_beat!==1||certified_input_beat!==0))
        $fatal(1,"malformed offer/certificate separation missing");
    end
    mailbox_ready=1;bank_ready=1;bank_ack=1;probe_publish=1;#0.001;
    if(KIND==0)begin
      if(inverse_ack!==1||old_release!==1||new_release!==1)$fatal(1,"healthy real ACK lost");
    end else begin
      if(offered_common!==1||new_release!==0||old_release!==0||inverse_ack===1)
        $fatal(1,"current malformed input permitted old real ACK/release");
    end
    $display("OFFER_ACK_PRE kind=%0d input_fault=%b offer=%b cert=%b guard_ack=%b old_release=%b new_release=%b publication_request=%b",
      KIND,input_fault_now,summary_offer_beat,certified_input_beat,inverse_ack,old_release,new_release,probe_publish);
    tick();
    if(old_reasons!==new_reasons||old_retained!==new_retained)$fatal(1,"old/current owner diagnostics diverged");
    if(KIND==0)begin
      if(new_retained!==0||probe_retained!==1||new_reasons!==0||probe_reasons!==0)$fatal(1,"healthy release/publication state");
    end else begin
      if(new_retained!==1||probe_retained!==0||new_reasons[6]!==1||probe_reasons[6:4]!==3'b101)
        $fatal(1,"current fault did not quarantine publication and retain ownership");
    end
    resetn=0;input_resetn=0;tick();
    if(old_reasons!==0||new_reasons!==0||probe_reasons!==0||new_retained!==0)$fatal(1,"fault epoch reset lost");
    $display("OFFLINE_PASS current-input/real-ACK/publication kind=%0d original_guard_and_owner_retained",KIND);$finish;
  end
endmodule
