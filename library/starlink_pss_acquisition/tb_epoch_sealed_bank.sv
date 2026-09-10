`timescale 1ns/1ps
module tb_epoch_sealed_bank;
  reg clk=0;
  always #5 clk=~clk;
  reg input_resetn=0, output_resetn=0, input_valid=0, output_ready=0;
  reg input_offer_new=0, certificate_offer_new=0;
  reg [35:0] input_data=0;
  reg [8:0] input_position=0;
  reg input_last=0;
  reg [74:0] input_metadata=0;
  reg rearm_valid=0, engine_reset_held=1;
  // Three finite one-entry actor ownership flags, not DUT-ready-derived grants.
  reg producer_refs=0, certificate_refs=0, consumer_refs=0;
  reg [1:0] input_lease=0, certificate_lease=0, lease_release_tag=0;
  reg certificate_valid=0, certificate_good=1, lease_release_valid=0;
  reg [74:0] certificate_metadata=0;
  reg [7:0] live_faults=0;
  wire input_ready, input_fault, input_framing_fault_now, output_valid, output_last;
  wire [35:0] output_data;
  wire [8:0] output_position;
  wire [74:0] output_metadata;
  wire rearm_ready, epoch_active, certificate_ready, lease_release_ready;
  wire [1:0] current_lease;
  wire [15:0] fault_reasons;
  wire private_take, checked_seal, publish, lease_release, sealed, published;
  integer cycle=0, epoch=0, takes=0, reads=0, seals=0, pubs=0, releases=0, certs=0;
  integer scenario=0, bit_index=0, phase=0, token=0, jobs=0;
  reg [13:0] issuer_age=0;
  integer rearm_receipts=0;
  reg saw_active=0;
  reg timeout_enabled=0;
  reg [74:0] descriptor=0;
  reg stalled=0;
  reg [120:0] stalled_tuple;
  reg [15:0] previous_reasons=0;
  // Independent interface-level current veto qualification for stall checks.
  wire current_public_veto = live_faults !== 8'b0 ||
    (input_valid !== 1'b0 && input_valid !== 1'b1) ||
    (certificate_valid !== 1'b0 && certificate_valid !== 1'b1) ||
    (input_valid === 1'b1 && input_offer_new !== 1'b0 && input_offer_new !== 1'b1) ||
    (certificate_valid === 1'b1 && certificate_offer_new !== 1'b0 && certificate_offer_new !== 1'b1) ||
    (published && input_valid === 1'b1 && input_offer_new !== 1'b0 && input_lease !== (current_lease+2'b01)) ||
    (published && certificate_valid === 1'b1 && certificate_offer_new !== 1'b0 && certificate_lease !== (current_lease+2'b01));
  starlink_pss_epoch_sealed_bank #(.SEALED_PUBLICATION(1)) dut (
    .clk(clk), .input_resetn(input_resetn), .output_resetn(output_resetn),
    .input_valid(input_valid), .input_offer_new(input_offer_new), .input_ready(input_ready), .input_data(input_data),
    .input_position(input_position), .input_last(input_last), .input_metadata(input_metadata),
    .input_commit_authorized(1'b0), .input_fault(input_fault),
    .input_framing_fault_now(input_framing_fault_now), .output_valid(output_valid),
    .output_ready(output_ready), .output_data(output_data), .output_position(output_position),
    .output_last(output_last), .output_metadata(output_metadata),
    .rearm_valid(rearm_valid), .engine_reset_held(engine_reset_held),
    .producer_epoch_idle(producer_refs==0), .certificate_epoch_idle(certificate_refs==0),
    .consumer_epoch_idle(consumer_refs==0), .rearm_ready(rearm_ready), .epoch_active(epoch_active),
    .input_lease(input_lease), .current_lease(current_lease),
    .certificate_valid(certificate_valid), .certificate_offer_new(certificate_offer_new), .certificate_ready(certificate_ready),
    .certificate_lease(certificate_lease), .certificate_metadata(certificate_metadata),
    .certificate_good(certificate_good), .lease_release_valid(lease_release_valid),
    .lease_release_ready(lease_release_ready), .lease_release_tag(lease_release_tag),
    .live_faults(live_faults), .fault_reasons(fault_reasons), .private_take(private_take),
    .checked_seal(checked_seal), .publish(publish), .lease_release(lease_release),
    .sealed(sealed), .published(published)
  );
  function [35:0] word_for(input integer job, input integer pos);
    word_for = ((job+1)*36'h123450001 + pos*36'h10203) ^ (pos << 19);
  endfunction
  function [74:0] meta_for(input integer job);
    reg [63:0] start_index;
    begin
      start_index=64'h200000001 + job*447;
      meta_for = {1'b1, start_index, 5'd7, 5'd9};
    end
  endfunction
  always @(posedge clk) begin
    cycle=cycle+1;
    if(!input_resetn || !output_resetn) begin rearm_receipts=0; saw_active=0; end
    else begin
      if(rearm_valid && rearm_ready) rearm_receipts=rearm_receipts+1;
      if(epoch_active && !saw_active && rearm_receipts!=1) $fatal(1,"armed without finite-peer rearm receipt");
      if(epoch_active) saw_active=1;
    end
    if(timeout_enabled && !engine_reset_held && issuer_age<8192) issuer_age=issuer_age+1;
    if (private_take) begin
      takes=takes+1;
      $display("TAKE %0d %0d %0d %0d %h %h %0d",cycle,epoch,input_lease,input_position,input_data,input_metadata,input_last);
    end
    if (certificate_valid && certificate_offer_new && certificate_ready) begin
      certs=certs+1;
      $display("CERT %0d %0d %0d %h %0d",cycle,epoch,certificate_lease,certificate_metadata,certificate_good);
    end
    if (checked_seal) begin
      seals=seals+1; $display("SEAL %0d %0d %0d",cycle,epoch,current_lease);
    end
    if (publish) begin
      pubs=pubs+1; consumer_refs=1;
      $display("PUB %0d %0d %0d",cycle,epoch,current_lease);
    end
    if (output_valid && output_ready) begin
      reads=reads+1;
      $display("OUT %0d %0d %0d %0d %h %h %0d",cycle,epoch,current_lease,output_position,output_data,output_metadata,output_last);
    end
    if (lease_release) begin
      releases=releases+1; $display("REL %0d %0d %0d",cycle,epoch,current_lease);
    end
    if (fault_reasons !== previous_reasons) begin
      $display("FAULT %0d %0d %h",cycle,epoch,fault_reasons);
      previous_reasons=fault_reasons;
    end
    if (stalled && input_resetn && output_resetn && !current_public_veto && !input_fault &&
        (output_valid !== 1'b1 || {output_data,output_position,output_last,output_metadata} !== stalled_tuple))
      $fatal(1,"stalled output VALID/tuple changed");
    stalled=output_valid && !output_ready;
    stalled_tuple={output_data,output_position,output_last,output_metadata};
    if ((live_faults!=0 || input_fault) && (publish || output_valid || lease_release))
      $fatal(1,"current/sticky fault leaked public action");
    if (cycle>50000) $fatal(1,"watchdog");
  end
  always @(negedge clk) if(timeout_enabled && issuer_age>=8192) live_faults[7]=1;
  task tick(input integer count);
    repeat(count) @(negedge clk);
  endtask
  task reset_now_and_arm(input integer which);
    if (which!=2) input_resetn=0;
    if (which!=1) output_resetn=0;
    #0.001;
    if (output_valid || private_take || publish || lease_release || epoch_active)
      $fatal(1,"asynchronous reset did not invalidate ownership immediately");
    epoch=epoch+1;
    $display("RESET %0d %0d",cycle,epoch);
    rearm_valid=1; engine_reset_held=1; output_ready=0; live_faults=0;
    // Finite peer queues are flushed independently of DUT readiness, at
    // different fixed delays. Held certificates remain live until issuer flush.
    tick(2); input_resetn=1; output_resetn=1;
    tick(2);
    if (epoch_active) $fatal(1,"armed before explicit peer drain");
    producer_refs=0; input_valid=0; input_offer_new=0;
    tick(2); certificate_refs=0; certificate_valid=0; certificate_offer_new=0; lease_release_valid=0;
    tick(2); consumer_refs=0;
    tick(3);
    if (!epoch_active) $fatal(1,"failed explicit rearm");
    rearm_valid=0;
    takes=0; reads=0; pubs=0; seals=0; releases=0; certs=0;
  endtask
  task reset_and_arm(input integer which);
    @(negedge clk); reset_now_and_arm(which);
  endtask
  task begin_job(input integer job);
    @(negedge clk);
    descriptor=meta_for(job); input_metadata=descriptor;
    input_lease=current_lease; certificate_lease=current_lease;
    certificate_metadata=descriptor; certificate_good=1;
    producer_refs=1; engine_reset_held=0;
    $display("JOB %0d %0d %0d %0d %h",cycle,epoch,current_lease,job,descriptor);
  endtask
  task send_word(input integer job, input integer pos, input integer corrupt);
    @(negedge clk);
    input_valid=1; input_offer_new=1; input_data=word_for(job,pos); input_position=pos; input_last=(pos==511);
    if(scenario==3 && phase==0 && pos==511) live_faults=8'b1<<bit_index;
    input_metadata=descriptor;
    if (corrupt) input_metadata[bit_index]=!input_metadata[bit_index];
    if(scenario==15) begin
      if(bit_index==0 && pos==255) input_position=254;
      if(bit_index==1 && pos==255) input_lease=current_lease+1'b1;
      if(bit_index==2 && pos==255) input_last=1;
      if(bit_index==3 && pos==511) input_last=0;
    end
    @(posedge clk);
    if (!input_ready) $fatal(1,"unexpected input backpressure");
    @(negedge clk); input_valid=0; input_offer_new=0;
  endtask
  task issue_certificate(input integer corrupt);
    @(negedge clk);
    certificate_refs=1; certificate_valid=1; certificate_offer_new=1;
    certificate_metadata=descriptor;
    if (corrupt) certificate_metadata[bit_index]=!certificate_metadata[bit_index];
    @(posedge clk);
    if (!certificate_ready) $fatal(1,"unexpected certificate backpressure");
    @(negedge clk); certificate_valid=0; certificate_offer_new=0;
  endtask
  task finish_input;
    input_valid=0; input_offer_new=0; producer_refs=0;
  endtask
  task quarantine(input integer mask);
    tick(5);
    if (!input_fault || (fault_reasons & mask)!=mask) $fatal(1,"missing expected quarantine %h",fault_reasons);
    if (pubs!=0 || reads!=0) $fatal(1,"faulted unpublished block escaped");
    tick(8);
  endtask
  task check_two_edge_fault(input integer pos, input integer tag);
    if(input_fault) $fatal(1,"private fault not delayed to check edge");
    tick(1); if(input_fault) $fatal(1,"private fault arrived one edge early");
    tick(1);
    if(!input_fault || !dut.fault_token_valid || dut.fault_token_position!==pos[8:0] ||
        dut.fault_token_lease!==tag[1:0]) $fatal(1,"lost two-edge fault token/lease/index");
    $display("TWO_EDGE_FAULT cycle=%0d pos=%0d lease=%0d",cycle,dut.fault_token_position,dut.fault_token_lease);
  endtask
  task drain_and_release(input integer mistag);
    output_ready=0;
    wait(output_valid); tick(4); // first-read stable backpressure
    output_ready=1;
    wait(reads==511); @(negedge clk); output_ready=0;
    tick(5); output_ready=1; // final-read stable backpressure
    wait(reads==512); @(negedge clk); output_ready=0;
    // Reader actor completes independently after7 clocks; issuer retains its
    // reference meanwhile. Valid cannot be fabricated from DUT release_ready.
    tick(7); consumer_refs=0; certificate_refs=0;
    tick(12);
    if (input_ready || releases!=0) $fatal(1,"lease reused without issuer release");
    lease_release_valid=1; lease_release_tag=current_lease ^ (mistag?2'b01:2'b00);
    @(posedge clk);
    if (!lease_release_ready) $fatal(1,"release did not accept drained issuer");
    @(negedge clk); lease_release_valid=0;
    tick(2);
    if (mistag) begin
      if (!input_fault || releases!=0) $fatal(1,"mistagged release accepted");
    end else if (releases!=1 || !input_ready) $fatal(1,"drained lease not reusable");
  endtask
  initial begin
    if (!$value$plusargs("CASE=%d",scenario)) scenario=0;
    if (!$value$plusargs("BIT=%d",bit_index)) bit_index=0;
    if (!$value$plusargs("PHASE=%d",phase)) phase=0;
    // Start with a real queued issuer reference so reset cannot auto-rearm.
    certificate_refs=1;
    reset_and_arm(0);
    if (scenario==0) begin
      for (jobs=0;jobs<8;jobs=jobs+1) begin
        takes=0; reads=0; pubs=0; seals=0; releases=0; certs=0;
        begin_job(jobs);
        for(token=0;token<512;token=token+1) begin
          send_word(jobs,token,0);
          if (token==31 && jobs%2==0) issue_certificate(0);
          if (token%101==0) begin
            input_data='x; input_metadata='x; input_position='x; input_last='x;
            tick(3); // invalid unknown bubbles must not contaminate checks
          end
        end
        // Deliberately hold the already-taken final while status is absent.
        input_valid=1; input_data=word_for(jobs,511); input_position=511; input_last=1; input_metadata=descriptor;
        tick(200);
        if(takes!=512 || seals!=1) $fatal(1,"held final duplicated or seal missing");
        if(jobs%2!=0) begin
          if(pubs!=0) $fatal(1,"published without certificate");
          issue_certificate(0);
        end
        finish_input();
        // Legal N+1 metadata movement must not replace this job's snapshot.
        input_metadata=meta_for(jobs+1); certificate_metadata=meta_for(jobs+1);
        drain_and_release(0);
        if(pubs!=1 || certs!=1) $fatal(1,"authority used more than once");
      end
    end else if (scenario==1) begin
      begin_job(0);
      if(phase==0) descriptor[bit_index]=!descriptor[bit_index];
      for(token=0;token<512;token=token+1) begin
        send_word(0,token,phase!=0 && token==(phase==1?255:511));
        if(phase!=0 && token==(phase==1?255:511)) begin
          token=512;
        end
      end
      finish_input();
      if(phase==0) begin
        tick(5);
        if(seals!=1 || pubs!=0) $fatal(1,"locally consistent wrong descriptor must seal but not publish");
        descriptor=meta_for(0); issue_certificate(0); quarantine(4);
      end else quarantine(8);
    end else if (scenario==2) begin
      begin_job(0);
      for(token=0;token<512;token=token+1) send_word(0,token,0);
      finish_input(); tick(phase?100:1); issue_certificate(1); quarantine(4);
    end else if (scenario==3) begin
      begin_job(0);
      for(token=0;token<511;token=token+1) send_word(0,token,0);
      issue_certificate(0);
      send_word(0,511,0); finish_input();
      if(phase!=0) begin
        tick(phase-1); live_faults=8'b1<<bit_index;
      end
      quarantine(16'h100<<bit_index);
    end else if (scenario==4) begin
      begin_job(0);
      for(token=0;token<512;token=token+1) send_word(0,token,0);
      finish_input(); tick(100);
      @(negedge clk); live_faults=8'hff; certificate_refs=1;
      certificate_valid=1; certificate_offer_new=1; certificate_metadata=descriptor;
      @(posedge clk);
      if(!certificate_ready) $fatal(1,"late certificate was not concurrently offered");
      @(negedge clk); certificate_valid=0; certificate_offer_new=0;
      quarantine(16'hff00);
    end else if (scenario==5) begin
      begin_job(0);
      for(token=0;token<512;token=token+1) send_word(0,token,0);
      finish_input(); issue_certificate(0); drain_and_release(1);
    end else if (scenario==6) begin
      begin_job(0);
      for(token=0;token<(phase==0?17:512);token=token+1) send_word(0,token,0);
      if(phase==1) tick(1);
      if(phase==2) tick(100);
      if(phase>=3) begin
        issue_certificate(0); wait(output_valid);
        if(phase==4) begin output_ready=1; wait(reads==17); @(negedge clk); output_ready=0; end
      end
      certificate_valid=1; certificate_refs=1; // certificate held across reset
      reset_and_arm(bit_index%2+1);
      if(published || output_valid || sealed || input_fault) $fatal(1,"reset retained publication");
      begin_job(1);
      for(token=0;token<512;token=token+1) send_word(1,token,0);
      finish_input(); issue_certificate(0); drain_and_release(0);
    end else if (scenario==7 || scenario==8 || scenario==11) begin
      begin_job(0);
      for(token=0;token<511;token=token+1) send_word(0,token,0);
      issue_certificate(0); send_word(0,511,0); finish_input();
      tick(2); // exactly the eventual n+3 publication edge is next
      if(scenario==7) begin
        input_valid=1; input_offer_new=1; input_lease=current_lease;
        input_position=0; input_last=0; input_metadata=descriptor;
      end else if(scenario==8) begin
        certificate_valid=1; certificate_offer_new=1; certificate_lease=current_lease;
      end else begin
        case(bit_index)
          0: input_valid=1'bx;
          1: input_valid=1'bz;
          2: certificate_valid=1'bx;
          3: certificate_valid=1'bz;
          4: begin input_valid=1; input_offer_new=1'bx; end
          5: begin certificate_valid=1; certificate_offer_new=1'bz; end
        endcase
      end
      quarantine(scenario==7?32:(scenario==8?64:128));
    end else if (scenario==9) begin
      begin_job(0);
      for(token=0;token<512;token=token+1) send_word(0,token,0);
      finish_input(); issue_certificate(0);
      wait(output_valid); @(negedge clk);
      // Independent one-entry future queues hold through old lease release.
      input_lease=current_lease+1'b1; input_valid=1; input_offer_new=1;
      input_position=0; input_last=0; input_data=word_for(1,0); input_metadata=meta_for(1);
      certificate_lease=current_lease+1'b1; certificate_valid=1; certificate_offer_new=1;
      certificate_metadata=meta_for(1); producer_refs=1; certificate_refs=1;
      output_ready=1; wait(reads==512); @(negedge clk); output_ready=0;
      tick(7); consumer_refs=0; // old issuer reference drained; future queue remains
      lease_release_valid=1; lease_release_tag=current_lease;
      @(posedge clk); if(!lease_release_ready) $fatal(1,"future-offer deadlock");
      @(negedge clk); lease_release_valid=0;
      takes=0; reads=0; pubs=0; seals=0; certs=0; releases=0;
      descriptor=meta_for(1);
      $display("JOB %0d %0d %0d %0d %h",cycle,epoch,current_lease,1,descriptor);
      @(posedge clk); if(!private_take) $fatal(1,"future first token not consumed");
      @(negedge clk); input_valid=0; input_offer_new=0;
      @(posedge clk); if(!certificate_ready) $fatal(1,"future certificate not admitted");
      @(negedge clk); certificate_valid=0; certificate_offer_new=0;
      for(token=1;token<512;token=token+1) send_word(1,token,0);
      finish_input(); drain_and_release(0);
    end else if (scenario==10) begin
      begin_job(0);
      for(token=0;token<512;token=token+1) send_word(0,token,0);
      finish_input(); issue_certificate(0); wait(output_valid);
      @(negedge clk); output_ready=1;
      wait(reads==(phase==0?17:511)); @(negedge clk);
      live_faults=8'h80; tick(5);
      if(reads!=(phase==0?17:511) || releases || !input_fault) $fatal(1,"late prefix/final-read quarantine failed");
      live_faults=0; tick(5);
      if(reads!=(phase==0?17:511) || releases || !input_fault || output_valid)
        $fatal(1,"late pulse lost sticky quarantine");
    end else if (scenario==12) begin
      begin_job(0); timeout_enabled=1; issuer_age=0;
      for(token=0;token<512;token=token+1) send_word(0,token,0);
      finish_input(); certificate_refs=1; // real issuer stays pending, never delivers status
      wait(issuer_age==8192); tick(2);
      if(live_faults!==8'h80) $fatal(1,"bounded issuer deadline absent");
      quarantine(16'h8000);
      $display("ISSUER_TIMEOUT age=%0d",issuer_age);
    end else if (scenario==13) begin
      begin_job(0);
      for(token=0;token<512;token=token+1) begin
        @(negedge clk); input_valid=1; input_offer_new=1;
        input_data=word_for(0,token); input_position=token; input_last=(token==511);
        @(posedge clk); if(!private_take) $fatal(1,"continuous private throughput failed");
      end
      @(negedge clk); finish_input(); issue_certificate(0); drain_and_release(0);
    end else if(scenario==14) begin
      begin_job(0); send_word(0,0,1); send_word(0,1,0); finish_input();
      check_two_edge_fault(1,0); quarantine(8);
    end else if(scenario==15) begin
      begin_job(0);
      for(token=0;token<=(bit_index==3?511:255);token=token+1) send_word(0,token,0);
      finish_input();
      check_two_edge_fault(bit_index==0?254:(bit_index==3?511:255),bit_index==1?1:0);
      quarantine(bit_index==1?2:1);
    end else if(scenario==16) begin
      begin_job(0);
      for(token=0;token<512;token=token+1) send_word(0,token,0);
      finish_input();
      if(bit_index==0) certificate_lease=current_lease+1'b1;
      else certificate_good=0;
      issue_certificate(0); quarantine(4);
    end else if(scenario==17) begin
      begin_job(0);
      for(token=0;token<512;token=token+1) send_word(0,token,0);
      finish_input();
      // Certificate takes at final n+1, seal n+2, n+3, or n+201.
      tick(phase==3?200:phase);
      certificate_refs=1; certificate_valid=1; certificate_offer_new=1;
      @(posedge clk); if(!certificate_ready) $fatal(1,"join-order certificate not accepted");
      @(negedge clk); certificate_valid=0; certificate_offer_new=0;
      drain_and_release(0);
    end else if(scenario==18) begin
      begin_job(0);
      for(token=0;token<(phase==0?17:512);token=token+1) send_word(0,token,0);
      finish_input();
      if(phase==0) issue_certificate(0); // certificate-first, payload incomplete
      if(phase==1) tick(1); // next edge would seal
      if(phase==2) begin
        certificate_refs=1; certificate_valid=1; certificate_offer_new=1;
        @(posedge clk); if(!certificate_ready) $fatal(1,"pre-reset certificate missing");
        @(negedge clk); certificate_valid=0; certificate_offer_new=0;
        tick(1); // next edge would publish
      end
      if(phase>=3) begin
        issue_certificate(0); wait(output_valid); @(negedge clk); output_ready=1;
        wait(reads==512); @(negedge clk); output_ready=0;
        if(phase==4) tick(7); // ACK is visible; release still explicitly withheld
      end
      // Assert between physical clock edges, including final read/ACK phases.
      #2; reset_now_and_arm(bit_index%2+1);
      begin_job(1);
      for(token=0;token<512;token=token+1) send_word(1,token,0);
      finish_input(); issue_certificate(0); drain_and_release(0);
    end else if(scenario==19) begin
      begin_job(0);
      for(token=0;token<512;token=token+1) send_word(0,token,0);
      finish_input(); issue_certificate(0); wait(output_valid);
      @(negedge clk); output_ready=1;
      wait(reads==512); @(negedge clk); output_ready=0;
      tick(phase?7:0); live_faults=8'h04; // actual new raw orphan, independently of READY
      input_valid=1; input_offer_new=1; input_lease=current_lease+1'b1;
      input_position=0; input_last=0; input_metadata=meta_for(1); input_data=word_for(1,0);
      lease_release_valid=1; lease_release_tag=current_lease;
      tick(6); live_faults=0; tick(6);
      if(takes!=512 || reads!=512 || releases || !input_fault || input_ready || output_valid)
        $fatal(1,"fault at final ACK allowed new admission/release");
    end else $fatal(1,"unknown case");
    $display("SEALED_BANK_PASS case=%0d bit=%0d phase=%0d cycles=%0d",scenario,bit_index,phase,cycle);
    $finish(0);
  end
endmodule
