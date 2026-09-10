// Independent raw-result/source actors through REAL guards and spectrum_product.
// No vendor FFT/controller model, no actual numerical FFT or physical claim.
`timescale 1ns/1ps
module tb_starlink_pss_product_sealed_adapter #(parameter integer ENABLED=1);
  reg clk=0,resetn=0,peer_resetn=0,private_resetn=0;
  always #5 clk=~clk;
  reg forward_phase=1,engine_reset_held=1,peer_epoch_idle=0;
  reg job_valid=0,input_beat=0,input_done=0,input_closed=0,frame=0;
  reg raw_valid=0,raw_last=0,status_valid=0;
  reg [47:0] raw_data=0;
  reg [23:0] raw_user=0;
  reg [7:0] status_data=0,injected_faults=0;
  reg [69:0] descriptor=70'h123456789abcd000;
  reg inverse_start=0,inverse_enable=0,physical_ready=0;
  wire job_ready,guard_busy,guard_fault,guard_commit,return_valid,return_private,return_commit,return_last;
  wire [35:0] return_data;
  wire [8:0] return_position;
  wire [74:0] return_metadata;
  wire product_input_ready,product_valid,product_ready,product_last,product_overflow;
  wire [17:0] product_i,product_q;
  wire [8:0] product_position;
  wire [4:0] product_exponent;
  wire [63:0] product_start;
  wire core_valid,core_last,core_take,reusable,reservation,epoch_active;
  wire [35:0] core_data;
  wire [8:0] core_position;
  wire [69:0] core_metadata;
  wire product_take,checked_seal,publication,handoff,lease_release,handoff_valid;
  wire [1:0] current_lease;
  wire [15:0] bank_reasons,reader_reasons;
  wire [7:0] issuer_reasons;
  wire adapter_fault,consumer_complete,consumer_fault,consumer_duplicate,consumer_beat;
  wire consumer_valid,consumer_last;
  wire [47:0] consumer_data;
  wire [7:0] current_faults=injected_faults |
    {product_overflow,guard.fault_now,guard_fault,consumer_duplicate,consumer_fault,3'b0};
  wire destination_ready=guard.awaiting_ack ? handoff_valid : product_input_ready && reservation;
  wire forward_completion=return_commit && destination_ready;
  wire [69:0] product_metadata={1'b1,product_start,product_exponent};
  wire [69:0] offered_metadata=kind==4 && product_position==target ?
    product_metadata ^ (70'b1<<bit_index) : product_metadata;
  wire [8:0] offered_position=kind==13 && bit_index==0 && product_position==target ? product_position+1'b1 : product_position;
  wire offered_last=kind==13 && bit_index==1 && product_position==target ? !product_last : product_last;
  integer kind=0,bit_index=0,target=37,cycle=0,job=0,received=0,takes=0,pubs=0,handoffs=0,releases=0;
  integer forward_final=-1,product_final=-1,seal_cycle=-1,pub_cycle=-1,head_cycle=-1,last_cycle=-1;
  reg score=0;
  reg injected_once=0;
  reg completion_gate=0;
  reg [74:0] corrupt_read;
  integer first_core=-1,prior_core=-1,core_holes=0;
  integer stalled_offer_edges=0,verdict_cycle=-1,corruption_cycle=-1;
  integer admission_cycle=-1,release_cycle=-1;
  starlink_pss_product_sealed_adapter #(.SEALED_PRODUCT_ADAPTER(ENABLED)) dut (
    .clk(clk),.resetn(resetn),.peer_resetn(peer_resetn),.engine_reset_held(engine_reset_held),
    .peer_epoch_idle(peer_epoch_idle),.forward_guard_busy(guard_busy),.forward_phase(forward_phase),
    .forward_job_accept(job_valid && job_ready),.forward_descriptor(descriptor),
    .forward_completion(forward_completion),.forward_exponent(return_metadata[4:0]),
    .product_valid(product_valid),.product_ready(product_ready),.product_data({product_q,product_i}),
    .product_position(offered_position),.product_last(offered_last),.product_metadata(offered_metadata),
    .forward_handoff_valid(handoff_valid),.forward_handoff_ready(!guard_fault),
    .inverse_job_start(inverse_start),.inverse_input_enable(inverse_enable),.core_ready(physical_ready),
    .consumer_complete(consumer_complete && (kind!=9 || completion_gate)),.core_valid(core_valid),.core_data(core_data),
    .core_position(core_position),.core_last(core_last),.core_metadata(core_metadata),
    .current_faults(current_faults),.reusable(reusable),.reservation(reservation),.epoch_active(epoch_active),
    .product_take(product_take),.checked_seal(checked_seal),.publication(publication),.handoff(handoff),
    .core_take(core_take),.lease_release(lease_release),.current_lease(current_lease),
    .bank_reasons(bank_reasons),.reader_reasons(reader_reasons),.issuer_reasons(issuer_reasons),.fault(adapter_fault)
  );
  starlink_pss_realtime_result_guard #(.USE_COMPLETED_INPUT_FAULT(1)) guard (
    .clk(clk),.resetn(resetn && peer_resetn),.job_valid(job_valid),.job_ready(job_ready),
    .job_descriptor(descriptor),.input_bank_reserved(1'b1),.output_bank_reserved(1'b1),
    .certified_input_beat(input_beat),.certified_input_complete(input_done),
    .final_fence_certified(input_closed),.external_fault_now(adapter_fault),.phase_input_fault_now(1'b0),
    .completed_input_certified(input_closed),.completed_input_fault_now(adapter_fault),
    .preflight_fault_evidence_now(1'b0),.core_event_frame_started(frame),
    .core_output_tdata(raw_data),.core_output_tuser(raw_user),.core_output_tvalid(raw_valid),.core_output_tlast(raw_last),
    .core_status_tdata(status_data),.core_status_tvalid(status_valid),
    .mailbox_input_valid(return_valid),.mailbox_private_valid(return_private),.mailbox_commit_valid(return_commit),
    .mailbox_input_ready(destination_ready),.mailbox_input_fault(1'b0),.inverse_phase(1'b0),
    .forward_mailbox_fault(1'b0),.forward_retirement_valid(),.mailbox_input_data(return_data),
    .mailbox_input_position(return_position),.mailbox_input_last(return_last),.mailbox_input_metadata(return_metadata),
    .busy(guard_busy),.commit_pulse(guard_commit),.protocol_fault(guard_fault),.fault_reasons()
  );
  starlink_pss_spectrum_product #(.DATA_WIDTH(18)) product (
    .clk(clk),.resetn(resetn && peer_resetn),.flush(1'b0),
    .input_valid(return_valid && !guard.awaiting_ack),.input_ready(product_input_ready),
    .input_i(return_data[17:0]),.input_q(return_data[35:18]),.kernel_i(18'h20000),
    .kernel_q(kind==1 && return_position==target ? 18'h20000 : 18'b0),
    .input_bin_index(return_position),.input_block_exponent(return_metadata[4:0]),.input_last(return_last),
    .input_block_start_index(return_metadata[73:10]),.output_valid(product_valid),.output_ready(product_ready),
    .output_i(product_i),.output_q(product_q),.output_bin_index(product_position),.output_block_exponent(product_exponent),
    .output_last(product_last),.output_block_start_index(product_start),.output_overflow(product_overflow),.overflow_pulse()
  );
  // This is the explicit checked-token seam; raw all75 checks live in reader.
  // No canonical guard source changes, and no source/forward identity exemption.
  starlink_pss_realtime_input_guard #(.CHECK_INPUT_BLOCK_IDENTITY(0)) consumer (
    .clk(clk),.resetn(resetn && peer_resetn && private_resetn),.job_start(inverse_start),
    .job_descriptor({1'b1,descriptor[68:5],5'd3}),.input_enable(inverse_enable),
    .input_valid(core_valid),.input_ready(),.input_transport_ready(),.input_data(core_data),
    .input_position(core_position),.input_last(core_last),.input_metadata(core_metadata),
    .core_input_tdata(consumer_data),.core_input_tvalid(consumer_valid),.core_input_tready(physical_ready),
    .core_input_tlast(consumer_last),.certified_input_beat(consumer_beat),.certified_input_complete(),
    .input_complete(consumer_complete),.fault_now(),.duplicate_start_fault_now(consumer_duplicate),
    .fault_events_now(),.protocol_fault(consumer_fault),.fault_reasons()
  );
  function [35:0] expected_word(input integer n);
    reg signed [17:0] ri,rq;
    begin ri=-(n+1);rq=-2*(n+1);expected_word={rq,ri};end
  endfunction
  task tick;begin @(posedge clk);#0.001;end endtask
  always @(posedge clk) begin
    cycle=cycle+1;
    if(cycle>30000) $fatal(1,"ADAPTER_WATCHDOG");
    if(resetn && peer_resetn && score) begin
      if(product_take !== (product_valid && product_ready)) $fatal(1,"PRODUCT_LOGICAL_TAKE_DIVERGED");
      if(job_valid && job_ready)admission_cycle=cycle;
      if(dut.reader.verdict_bad && verdict_cycle<0)verdict_cycle=cycle;
      if(core_take !== consumer_beat) $fatal(1,"ACTUAL_CORE_CERTIFICATE_DIVERGED");
      if(product_take) begin takes=takes+1;if(product_last)product_final=cycle;end
      if(forward_completion) forward_final=cycle;
      if(checked_seal) seal_cycle=cycle;
      if(publication) begin
        pubs=pubs+1;pub_cycle=cycle;
        if(takes!=512 || product_final<0 || cycle<product_final+3 || !dut.completion_reference || |current_faults)
          $fatal(1,"UNCHECKED_OR_CURRENT_FAULT_PUBLICATION");
      end
      if(handoff) begin
        if(dut.reader.errors_now!=0) $fatal(1,"POISONED_PREFETCH_HANDOFF");
        handoffs=handoffs+1;head_cycle=cycle;
      end
      if(consumer_beat) begin
        if((kind==5 && received>=target) || (kind==8 && received>=3)) $fatal(1,"CORRUPT_RAW_READ_REACHED_CORE");
        if(core_data!==expected_word(received) || core_position!==received[8:0] ||
           core_last!==(received==511) || core_metadata!=={1'b1,descriptor[68:5],5'd3})
          $fatal(1,"REAL_PRODUCT_ACCEPTED_TUPLE_MISMATCH pos=%d data=%h expected=%h meta=%h expectedmeta=%h",core_position,core_data,expected_word(received),core_metadata,{1'b1,descriptor[68:5],5'd3});
        received=received+1;last_cycle=cycle;
        if(first_core<0)first_core=cycle;
        if(prior_core>=0 && cycle!=prior_core+1)core_holes=core_holes+1;
        prior_core=cycle;
      end
      if(lease_release) begin
        releases=releases+1;release_cycle=cycle;
        if(!consumer_complete || received!=512 || !dut.reader.drained || !dut.queue_released || |current_faults)
          $fatal(1,"LEASE_RELEASE_BEFORE_CERTIFIED_FINAL_DRAIN");
      end
    end
  end
  // Faults are stable before the actual sampling edge, never posedge races.
  always @(negedge clk) begin
    if(score && kind==5 && dut.bank_valid && dut.bank_position==target && !injected_once) begin
      corrupt_read=dut.bank_metadata ^ (75'b1<<bit_index);
      force dut.bank_metadata=corrupt_read;
      injected_once=1;
    end
    if(score && kind==8 && dut.bank_valid && dut.bank_position==3 && !dut.bank_ready && !injected_once) begin
      if(stalled_offer_edges==target) begin
        corrupt_read=dut.bank_metadata ^ (75'b1<<bit_index);
        force dut.bank_metadata=corrupt_read;
        corruption_cycle=cycle;injected_once=1;
      end
      stalled_offer_edges=stalled_offer_edges+1;
    end
    if(score && kind==6 && !injected_once &&
       ((target==0 && checked_seal) || (target==1 && publication) ||
        (target==2 && handoff_valid) || (target==3 && lease_release))) begin
      injected_faults=8'b1<<bit_index;injected_once=1;
      #0.001;
      if(publication || handoff || lease_release || core_valid)
        $fatal(1,"CURRENT_BOUNDARY_VETO_MISSING");
    end
    if(score && kind==7 && dut.consumer_started && inverse_enable && received==target && !injected_once) begin
      inverse_start=1;injected_once=1;
      #0.001;if(core_valid || core_take || lease_release) $fatal(1,"DUPLICATE_START_CURRENT_ESCAPE");
    end
    if(score && kind==12 && lease_release && !injected_once) begin
      // Deliberately inconsistent stale internal verdict at the release edge.
      // Natural complete-token drain has observed==0; this tests its fence.
      force dut.reader.observed=2'b10;force dut.reader.taken=2'b10;force dut.reader.tag1=2'd3;
      injected_once=1;
      #0.001;if(lease_release || dut.reader.drained) $fatal(1,"PENDING_VERDICT_RELEASE_ESCAPE");
    end
  end
  task reset_epoch;
    begin
      @(negedge clk);resetn=0;peer_resetn=0;private_resetn=0;peer_epoch_idle=0;
      job_valid=0;raw_valid=0;status_valid=0;input_beat=0;input_done=0;frame=0;input_closed=0;
      inverse_start=0;inverse_enable=0;physical_ready=0;forward_phase=1;injected_faults=0;score=0;
      repeat(4)tick();@(negedge clk);resetn=1;peer_resetn=1;private_resetn=1;
      repeat(4)tick();if(epoch_active) $fatal(1,"REARM_WITHOUT_PEER_PURGE");
      @(negedge clk);peer_epoch_idle=1;repeat(4)tick();
    end
  endtask
  task one_sided_reset;
    begin
      if(!dut.any_reference || !epoch_active) $fatal(1,"RESET_BOUNDARY_NOT_REACHED");
      score=0;peer_epoch_idle=0;
      if(bit_index==0)resetn=0;else peer_resetn=0;
      #0.001;
      if(epoch_active || publication || handoff || core_valid || lease_release) $fatal(1,"RESET_DID_NOT_CLOSE_PUBLICATION");
      // Explicitly purge all fixture-owned references before attesting idle.
      raw_valid=0;status_valid=0;input_beat=0;input_done=0;input_closed=0;frame=0;job_valid=0;
      inverse_start=0;inverse_enable=0;physical_ready=0;forward_phase=1;
      repeat(3)tick();@(negedge clk);resetn=1;peer_resetn=1;
      repeat(8)tick();
      if(epoch_active || reusable || dut.any_reference) $fatal(1,"RESET_REOPENED_BEFORE_PURGE_ATTESTATION");
      @(negedge clk);peer_epoch_idle=1;repeat(8)tick();
      if(!reusable || adapter_fault || dut.any_reference) $fatal(1,"COMMON_EPOCH_RECOVERY_FAILED");
      $display("PRODUCT_ADAPTER_RESET_PASS side=%0d boundary=%0d",bit_index,target);$finish;
    end
  endtask
  initial begin
    if(!$value$plusargs("CASE=%d",kind))kind=0;
    if(!$value$plusargs("BIT=%d",bit_index))bit_index=0;
    if(!$value$plusargs("TARGET=%d",target))target=37;
    if(kind==10) begin
      reset_epoch();
      repeat(30)begin
        @(negedge clk);raw_valid=1;raw_data=48'bx;raw_user=24'bz;inverse_start=1;inverse_enable=1;
        injected_faults=8'hff;job_valid=1;tick();
        if({reusable,reservation,epoch_active,product_take,checked_seal,publication,handoff,core_valid,core_take,lease_release,adapter_fault}!==0)
          $fatal(1,"DEFAULT_INERT_INTERFACE_CHANGED");
      end
      $display("PRODUCT_ADAPTER_DEFAULT_INERT_PASS");$finish;
    end
    reset_epoch();
    repeat(kind==0 ? 8 : 1) begin
      takes=0;received=0;pubs=0;handoffs=0;releases=0;
      first_core=-1;prior_core=-1;core_holes=0;
      @(negedge clk);score=1;job_valid=1;
      if(!reusable || !job_ready) $fatal(1,"FORWARD_ADMISSION_MISSING");
      tick();@(negedge clk);job_valid=0;
      for(integer n=0;n<512;n=n+1) begin
        input_beat=1;input_done=n==511;frame=n==0;tick();@(negedge clk);
      end
      input_beat=0;input_done=0;frame=0;input_closed=1;
      for(integer n=0;n<512;n=n+1) begin
        reg [17:0] ri,rq;
        // The unchanged product has the frozen extra one-bit safety shift.
        ri=2*(n+1);rq=4*(n+1);
        if(kind==1 && n==target)begin ri=18'h20000;rq=18'h20000;end
        raw_data={6'b0,rq,6'b0,ri};raw_user={3'b0,5'd3,7'b0,n[8:0]};
        raw_valid=1;raw_last=n==511;status_valid=n==2;status_data=3;
        tick();@(negedge clk);
        if(kind==11 && target==0 && takes>=37)one_sided_reset();
      end
      raw_valid=0;raw_last=0;status_valid=0;
      begin : await_handoff
        repeat(100) begin
          tick();
          if(adapter_fault || guard_fault)disable await_handoff;
          if(handoffs==1)disable await_handoff;
        end
      end
      if(kind==1 || kind==4 || kind==13 || (kind==6 && target<3) || (kind==5 && target<4)) begin
        if(!adapter_fault || handoffs || releases) $fatal(1,"PREHANDOFF_FAULT_NOT_QUARANTINED");
        if((kind==1 || kind==4 || kind==13 || (kind==6 && target<2)) && pubs) $fatal(1,"POISONED_BANK_PUBLISHED");
        $display("PRODUCT_ADAPTER_NEGATIVE_PASS case=%0d target=%0d reasons=%h/%h/%h",kind,target,bank_reasons,reader_reasons,issuer_reasons);$finish;
      end
      if(kind==8 && adapter_fault) begin
        if(handoffs || releases || !reader_reasons[2]) $fatal(1,"EARLY_VERDICT_HANDOFF_ESCAPE");
        $display("PRODUCT_ADAPTER_ONSET_PASS delay=%0d handoffs=%0d corruption=%0d verdict=%0d head=%0d received=%0d",target,handoffs,corruption_cycle,verdict_cycle,head_cycle,received);$finish;
      end
      if(handoffs!=1 || pubs!=1 || guard_busy || adapter_fault) $fatal(1,"CERTIFIED_HANDOFF_MISSING");
      if(kind==11 && target==1)begin @(negedge clk);one_sided_reset();end
      @(negedge clk);forward_phase=0;inverse_start=1;tick();
      @(negedge clk);inverse_start=0;inverse_enable=1;physical_ready=1;
      begin : deliver
        repeat(1200) begin
          if(kind==2 && received==511)physical_ready=0;
          if(kind==3 && received==target)injected_faults=8'b1<<bit_index;
          tick();@(negedge clk);
          if(kind==11 && target==2 && received>=37)one_sided_reset();
          if(adapter_fault || consumer_fault)disable deliver;
          if(kind==2 && received==511)disable deliver;
          if(kind==9 && received==512)disable deliver;
          if(releases==1)disable deliver;
        end
      end
      if(kind==2) begin
        physical_ready=0;
        repeat(8)tick();
        if(reusable || releases || consumer_complete || dut.reader.issued!=512) $fatal(1,"PREFETCH_RELEASED_OLD_LEASE");
        @(negedge clk);physical_ready=1;repeat(6)tick();
      end
      if(kind==9) begin
        // Explicit delivery hold of the real consumer's completed certificate;
        // not a claim that the unchanged real guard naturally delays it.
        repeat(8)tick();
        if(releases || reusable || !consumer_complete || !dut.reader.final_consumed)
          $fatal(1,"RELEASE_WITHOUT_DELIVERED_COMPLETION");
        @(negedge clk);completion_gate=1;repeat(3)tick();
      end
      if(kind==3 || kind==5 || kind==7 || kind==8 || kind==12 || (kind==6 && target==3)) begin
        if(!adapter_fault || releases!=0) $fatal(1,"CURRENT_READER_FAULT_NOT_HELD");
        if(kind==5 && !reader_reasons[2]) $fatal(1,"REAL_RAW_BANK_READ_REASON_MISSING");
        if(kind==7 && (!consumer_fault || !issuer_reasons[5])) $fatal(1,"REAL_DUPLICATE_START_REASON_MISSING");
        if(kind==12 && (!reader_reasons[6] || !injected_once)) $fatal(1,"STALE_RELEASE_VERDICT_REASON_MISSING");
        if(kind==8) begin
          if(!reader_reasons[2] || received>3) $fatal(1,"LATER_PRIVATE_VERDICT_NOT_QUARANTINED");
          $display("PRODUCT_ADAPTER_ONSET_PASS delay=%0d handoffs=%0d corruption=%0d verdict=%0d head=%0d received=%0d",target,handoffs,corruption_cycle,verdict_cycle,head_cycle,received);$finish;
        end
        @(negedge clk);private_resetn=0;repeat(3)tick();
        if(!adapter_fault || reusable) $fatal(1,"PRIVATE_RESET_ERASED_EPOCH_POISON");
        $display("PRODUCT_ADAPTER_NEGATIVE_PASS case=%0d bit=%0d received=%0d",kind,bit_index,received);$finish;
      end
      if(received!=512 || releases!=1 || !reusable || adapter_fault) $fatal(1,"COMPLETE_PRODUCT_LIFETIME_MISSING");
      if(kind==0 && (last_cycle-first_core!=511 || core_holes)) $fatal(1,"REAL_CORE_CONTIGUOUS_SERVICE_FAILED");
      $display("PRODUCT_ADAPTER_JOB job=%0d take=%0d seal_delta=%0d publish_delta=%0d completion_to_publish=%0d head_delta=%0d release_after_core=%0d core_span=%0d holes=%0d",job,takes,seal_cycle-product_final,pub_cycle-product_final,pub_cycle-forward_final,head_cycle-pub_cycle,cycle-last_cycle,last_cycle-first_core,core_holes);
      $display("PRODUCT_ADAPTER_LATENCY job=%0d admission_to_release=%0d handoff_to_first_core=%0d last_core_to_release=%0d",job,release_cycle-admission_cycle,first_core-head_cycle,release_cycle-last_cycle);
      job=job+1;
      @(negedge clk);score=0;private_resetn=0;inverse_enable=0;physical_ready=0;input_closed=0;
      forward_phase=1;descriptor=descriptor+(70'd447<<5);repeat(3)tick();
      @(negedge clk);private_resetn=1;
    end
    $display("PRODUCT_ADAPTER_PASS case=%0d jobs=%0d",kind,job);$finish;
  end
endmodule
