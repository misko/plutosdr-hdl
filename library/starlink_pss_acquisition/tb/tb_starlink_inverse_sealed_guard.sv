// Independent nonzero raw-result stimulus through the REAL unchanged guards.
// Not an FFT model, FFT arithmetic reference, service-capacity or RF evidence.
`timescale 1ns/1ps
module tb_starlink_inverse_sealed_guard;
  parameter integer CASE=0, PHASE_PS=0, BIT=0, SIDE=0;
  reg clk=0, fft_clk=0, slow_enable=1;
  always #2.857 fft_clk=~fft_clk;
  initial begin
    #(PHASE_PS*0.001);
    forever begin #5; if(slow_enable) clk=~clk; else clk=0; end
  end
  reg resetn=0, fft_resetn=0;
  reg [1:0] slow_reset_fast=0, fast_reset_fast=0, slow_reset_slow=0, fast_reset_slow=0;
  always @(posedge fft_clk or negedge resetn)
    if(!resetn) slow_reset_fast<=0; else slow_reset_fast<={slow_reset_fast[0],1'b1};
  always @(posedge fft_clk or negedge fft_resetn)
    if(!fft_resetn) fast_reset_fast<=0; else fast_reset_fast<={fast_reset_fast[0],1'b1};
  always @(posedge clk or negedge resetn)
    if(!resetn) slow_reset_slow<=0; else slow_reset_slow<={slow_reset_slow[0],1'b1};
  always @(posedge clk or negedge fft_resetn)
    if(!fft_resetn) fast_reset_slow<=0; else fast_reset_slow<={fast_reset_slow[0],1'b1};
  wire fast_running=slow_reset_fast[1] && fast_reset_fast[1];
  wire slow_running=slow_reset_slow[1] && fast_reset_slow[1];
  reg job_valid=0, input_beat=0, input_complete=0, input_closed=0, frame=0;
  reg core_valid=0, core_last=0, status_valid=0, external_fault=0, core_held=1;
  reg [47:0] core_data=0;
  reg [23:0] core_user=0;
  reg [7:0] status_data=0;
  reg [69:0] descriptor=0;
  wire [74:0] transport_mask=(CASE>=7 && CASE<=9 && private_valid[1] &&
    return_position[1]==(CASE==7?0:CASE==8?17:511)) ? (75'b1<<BIT) : 75'b0;
  reg output_ready=0;
  wire [1:0] job_ready, busy, guard_fault, guard_commit, private_valid, commit_valid, return_last;
  wire [1:0] destination_ready, bank_fault, framing_now, out_valid, out_last;
  wire [35:0] return_data[0:1], out_data[0:1];
  wire [8:0] return_position[0:1], out_position[0:1];
  wire [74:0] return_metadata[0:1], out_metadata[0:1];
  wire [7:0] guard_reasons[0:1];
  wire epoch_active, reusable, reservation, take, cert_take, publication, reader_ack, lease_release;
  wire [15:0] bank_reasons;
  reg fast_fault=0;
  (* ASYNC_REG="TRUE" *) reg [1:0] fast_fault_slow=0;
  always @(posedge fft_clk)
    if(!fast_running) fast_fault<=0;
    else if(external_fault || guard_fault[1] || bank_fault[1]) fast_fault<=1;
  always @(posedge clk)
    if(!slow_running) fast_fault_slow<=0;
    else fast_fault_slow<={fast_fault_slow[0],fast_fault};
  wire slow_fault=fast_fault_slow[1];
  for(genvar mode=0;mode<2;mode=mode+1) begin : pair
    starlink_pss_realtime_result_guard #(.USE_COMPLETED_INPUT_FAULT(1)) guard (
      .clk(fft_clk), .resetn(fast_running), .job_valid(job_valid), .job_ready(job_ready[mode]),
      .job_descriptor(descriptor), .input_bank_reserved(1'b1), .output_bank_reserved(1'b1),
      .certified_input_beat(input_beat), .certified_input_complete(input_complete),
      .final_fence_certified(input_closed), .external_fault_now(external_fault),
      .phase_input_fault_now(1'b0), .completed_input_certified(input_closed),
      .completed_input_fault_now(external_fault), .preflight_fault_evidence_now(1'b0),
      .core_event_frame_started(frame), .core_output_tdata(core_data), .core_output_tuser(core_user),
      .core_output_tvalid(core_valid), .core_output_tlast(core_last),
      .core_status_tdata(status_data), .core_status_tvalid(status_valid),
      .mailbox_input_valid(), .mailbox_private_valid(private_valid[mode]),
      .mailbox_commit_valid(commit_valid[mode]), .mailbox_input_ready(destination_ready[mode]),
      .mailbox_input_fault(bank_fault[mode] || framing_now[mode]), .inverse_phase(1'b1),
      .forward_mailbox_fault(bank_fault[mode]), .forward_retirement_valid(),
      .mailbox_input_data(return_data[mode]), .mailbox_input_position(return_position[mode]),
      .mailbox_input_last(return_last[mode]), .mailbox_input_metadata(return_metadata[mode]),
      .busy(busy[mode]), .commit_pulse(guard_commit[mode]), .protocol_fault(guard_fault[mode]),
      .fault_reasons(guard_reasons[mode])
    );
    if(mode==0) begin : original
      starlink_pss_block_mailbox #(.METADATA_WIDTH(75), .RESET_RELEASE_EXTERNAL(1), .EXPLICIT_COMMIT(1)) bank (
        .input_clk(fft_clk), .input_resetn(fast_running), .input_valid(private_valid[mode]),
        .input_commit_authorized(commit_valid[mode]), .input_ready(destination_ready[mode]),
        .input_data(return_data[mode]), .input_position(return_position[mode]), .input_last(return_last[mode]),
        .input_metadata(return_metadata[mode]), .input_fault(bank_fault[mode]),
        .input_framing_fault_now(framing_now[mode]), .output_clk(clk), .output_resetn(slow_running),
        .output_valid(out_valid[mode]), .output_ready(output_ready && !slow_fault),
        .output_data(out_data[mode]), .output_position(out_position[mode]), .output_last(out_last[mode]),
        .output_metadata(out_metadata[mode])
      );
    end
  end
  starlink_pss_inverse_sealed_issuer issuer (
    .input_clk(fft_clk), .input_resetn(fast_running), .output_clk(clk), .output_resetn(slow_running),
    .core_reset_held(core_held), .inverse_phase(1'b1), .guard_busy(busy[1]),
    .inverse_job_accept(job_valid && job_ready[1]), .guard_private_valid(private_valid[1]),
    .guard_commit_valid(commit_valid[1]), .guard_data(return_data[1]),
    .guard_position(return_position[1]), .guard_last(return_last[1]),
    .guard_metadata(return_metadata[1] ^ transport_mask), .core_output_event(core_valid),
    .external_fault_now(external_fault || guard_fault[1] || fast_fault), .output_fault(slow_fault),
    .guard_destination_ready(destination_ready[1]), .reusable(reusable), .reservation(reservation),
    .epoch_active(epoch_active), .input_fault(bank_fault[1]), .input_framing_fault_now(framing_now[1]),
    .output_valid(out_valid[1]), .output_ready(output_ready && !slow_fault), .output_data(out_data[1]),
    .output_position(out_position[1]), .output_last(out_last[1]), .output_metadata(out_metadata[1]),
    .private_take(take), .certificate_take(cert_take), .publication(publication),
    .reader_ack(reader_ack), .lease_release(lease_release), .fault_reasons(bank_reasons)
  );
  integer fast_cycle=0, slow_cycle=0, epoch=0, job=0, pos=0, mode_index=0;
  integer output_limit=512, reset_trigger=0;
  integer takes=0, certs=0, pubs=0, releases=0, reads[0:1], admission_cycle=0;
  integer first_qualified=-1, original_publish=-1, candidate_publish=-1, ack_cycle=-1;
  integer release_cycle=-1, original_reuse=-1, candidate_reuse=-1;
  integer last_slow_read=-1, slow_fault_sample=-1;
  reg ack_seen=0;
  reg [1:0] stalled=0;
  reg [120:0] stalled_tuple[0:1];
  reg [15:0] previous_reasons=0;
  function [35:0] word_for(input integer j, input integer p);
    word_for=((j+1)*36'h123450001+p*36'h10203)^(p<<19);
  endfunction
  function [69:0] descriptor_for(input integer j);
    reg [63:0] start;
    begin start=64'h200000001+j*447; descriptor_for={1'b1,start,5'd7}; end
  endfunction
  function [74:0] metadata_for(input integer j);
    metadata_for={descriptor_for(j),5'd9};
  endfunction
  always @(posedge fft_clk) begin
    fast_cycle=fast_cycle+1;
    if(fast_cycle>40000) $fatal(1,"INVERSE_GUARD_WATCHDOG");
    if(fast_running) begin
      if(job_valid && job_ready[1]) begin
        admission_cycle=fast_cycle;
        $display("ADMIT %0d %0d %0d lease=%0d",fast_cycle,epoch,job,issuer.bank_lease);
      end
      if((busy[1] || pair[1].guard.awaiting_ack) && job_ready[1]) $fatal(1,"ACTIVE_GUARD_ADMISSION");
      if(issuer.producer_reference && !reservation) $fatal(1,"ADMISSION_LOST_RESERVATION");
      if(take) begin takes=takes+1; $display("TAKE %0d %0d %0d %0d %h %h lease=%0d",fast_cycle,epoch,job,return_position[1],return_data[1],return_metadata[1]^transport_mask,issuer.lease_reference); end
      if(cert_take) begin certs=certs+1; $display("CERT %0d %0d %0d",fast_cycle,epoch,job); end
      if(commit_valid[1] && first_qualified<0) first_qualified=fast_cycle;
      if(commit_valid[0] && destination_ready[0]) original_publish=fast_cycle;
      if(publication) begin
        pubs=pubs+1; candidate_publish=fast_cycle;
        if(!commit_valid[1] || !destination_ready[1]) $fatal(1,"PUBLICATION_WITHOUT_REAL_GUARD_COMMIT");
        $display("PUB %0d %0d %0d original=%0d first_qualified=%0d",fast_cycle,epoch,job,original_publish,first_qualified);
      end
      if(reader_ack && !ack_seen) begin
        if(reads[1]!=512) $fatal(1,"ACK_BEFORE_FINAL_SLOW_READ");
        ack_seen=1; ack_cycle=fast_cycle; $display("ACK %0d %0d %0d",fast_cycle,epoch,job);
      end
      if(original_publish>=0 && !busy[0] && job_ready[0] && original_reuse<0)
        original_reuse=fast_cycle;
      if(candidate_publish>=0 && reusable && candidate_reuse<0)
        candidate_reuse=fast_cycle;
      if(lease_release) begin
        releases=releases+1; release_cycle=fast_cycle;
        if(busy[1] || !reader_ack || reads[1]!=512) $fatal(1,"RELEASE_BEFORE_GUARD_READER_ACK");
        $display("RELEASE %0d %0d %0d ack=%0d final_slow=%0d",fast_cycle,epoch,job,ack_cycle,last_slow_read);
      end
      if(bank_reasons!==previous_reasons) begin previous_reasons=bank_reasons; $display("CAUSE %0d %0d %h",fast_cycle,epoch,bank_reasons); end
    end
  end
  always @(posedge clk) begin
    slow_cycle=slow_cycle+1;
    if(slow_running) begin
      if(fast_fault && slow_fault_sample<0) begin slow_fault_sample=slow_cycle; $display("S1 %0d reads=%0d",slow_cycle,reads[1]); end
      for(mode_index=0;mode_index<2;mode_index=mode_index+1) begin
        if(stalled[mode_index] && !slow_fault &&
          (!out_valid[mode_index] || {out_data[mode_index],out_position[mode_index],out_last[mode_index],out_metadata[mode_index]}!==stalled_tuple[mode_index]))
          $fatal(1,"SLOW_STALL_VALID_OR_TUPLE_WITHDRAWAL");
        stalled[mode_index]=out_valid[mode_index] && !output_ready && !slow_fault;
        stalled_tuple[mode_index]={out_data[mode_index],out_position[mode_index],out_last[mode_index],out_metadata[mode_index]};
        if(out_valid[mode_index] && output_ready && !slow_fault) begin
          if(out_position[mode_index]!==reads[mode_index][8:0] || out_last[mode_index] !== (reads[mode_index]==511) ||
             out_data[mode_index]!==word_for(job,reads[mode_index]) || out_metadata[mode_index]!==metadata_for(job))
            $fatal(1,"NONZERO_DATA_METADATA_ORDER mode=%0d ordinal=%0d",mode_index,reads[mode_index]);
          $display("OUT %0d %0d %0d mode=%0d pos=%0d data=%h metadata=%h",slow_cycle,epoch,job,mode_index,out_position[mode_index],out_data[mode_index],out_metadata[mode_index]);
          reads[mode_index]=reads[mode_index]+1;
          if(mode_index==1 && reads[1]==512) last_slow_read=slow_cycle;
        end
      end
      if(slow_fault_sample>=0 && slow_cycle>=slow_fault_sample+2 && out_valid[1])
        $fatal(1,"S3_CURRENT_SLOW_FAULT_NOT_BLOCKED");
    end else stalled=0;
  end
  task clear_counts;
    takes=0; certs=0; pubs=0; releases=0; reads[0]=0; reads[1]=0;
    first_qualified=-1; original_publish=-1; candidate_publish=-1; ack_cycle=-1;
    release_cycle=-1; original_reuse=-1; candidate_reuse=-1;
    last_slow_read=-1; slow_fault_sample=-1; ack_seen=0;
  endtask
  task start_job;
    @(negedge fft_clk); clear_counts(); descriptor=descriptor_for(job); job_valid=1;
    if(!job_ready[0] || !job_ready[1] || !reusable) $fatal(1,"JOB_NOT_ADMISSIBLE");
    @(posedge fft_clk); @(negedge fft_clk); job_valid=0; core_held=0;
    repeat(2) begin @(negedge fft_clk); if(!reservation || reusable) $fatal(1,"ADMISSION_RECEIPT_RESERVATION"); end
    for(pos=0;pos<512;pos=pos+1) begin
      @(negedge fft_clk); input_beat=1; frame=(pos==0); input_complete=(pos==511);
      @(posedge fft_clk);
    end
    @(negedge fft_clk); input_beat=0; frame=0; input_complete=0; input_closed=1;
    descriptor=descriptor_for(job+1); // independent legal N+1 metadata movement
    for(pos=0;pos<output_limit;pos=pos+1) begin
      @(negedge fft_clk); core_valid=1; core_last=(pos==511);
      core_data={6'b0,18'(word_for(job,pos)>>18),6'b0,18'(word_for(job,pos))};
      core_user={3'b0,5'd9,7'b0,9'(pos)};
      @(posedge fft_clk);
    end
    @(negedge fft_clk); core_valid=0; core_last=0;
  endtask
  task send_status;
    @(negedge fft_clk); status_valid=1; status_data=9;
    @(posedge fft_clk); @(negedge fft_clk); status_valid=0;
  endtask
  task drain_job;
    output_ready=1;
    wait(reads[0]==512 && reads[1]==512 && reusable && !busy[1]);
    repeat(2) @(negedge fft_clk);
    if(takes!=512 || certs!=1 || pubs!=1 || releases!=1 || bank_fault[1] || guard_fault[1])
      $fatal(1,"NONZERO_LIFECYCLE_COUNTS");
    $display("LIFECYCLE job=%0d publication_delta=%0d ack_to_release=%0d reuse_delta=%0d takes=%0d",job,candidate_publish-original_publish,release_cycle-ack_cycle,candidate_reuse-original_reuse,takes);
    output_ready=0; input_closed=0;
  endtask
  task common_reset;
    job_valid=0; input_beat=0; input_complete=0; frame=0; core_valid=0;
    core_last=0; status_valid=0; input_closed=0; output_ready=0; core_held=1;
    #0.001; if(SIDE==0) resetn=0; else fft_resetn=0;
    #0.001;
    if(epoch_active || publication || out_valid[1] || reusable)
      $fatal(1,"COMMON_RESET_DID_NOT_CLOSE_OWNERSHIP");
    repeat(5) @(negedge clk);
    if(SIDE==0) resetn=1; else fft_resetn=1;
    epoch=epoch+1;
    wait(epoch_active); repeat(3) @(negedge fft_clk);
    if(issuer.bank_lease!==0 || !reusable || bank_fault[1] || guard_fault[1])
      $fatal(1,"COMMON_RESET_REARM_WITH_STALE_REFERENCE");
    $display("RESET_REARM epoch=%0d phase=%0d side=%0d",epoch,BIT,SIDE);
  endtask
  initial begin
    clear_counts(); #1; resetn=1; fft_resetn=1; epoch=1;
    wait(epoch_active); repeat(3) @(negedge fft_clk);
    if(CASE==0 || CASE==1) begin
      for(job=0;job<2;job=job+1) begin
        start_job();
        if(CASE==1) begin
          repeat(300) @(negedge fft_clk);
          if(takes!=512 || pubs || certs || bank_fault[1] || guard_fault[1])
            $fatal(1,"HELD_FINAL_REWRITE_OR_EARLY_CERTIFICATE");
        end
        send_status(); drain_job();
      end
    end else if(CASE==2) begin
      start_job();
      while(fast_cycle<admission_cycle+8188) @(negedge fft_clk);
      status_valid=1; status_data=9;
      @(posedge fft_clk); @(negedge fft_clk); status_valid=0;
      while(fast_cycle<admission_cycle+8191) @(negedge fft_clk);
      if(!issuer.bank.staged.seal_q || !issuer.bank.staged.certificate_seen || !issuer.certificate_reference ||
         !pair[1].guard.watchdog_error)
        $fatal(1,"DEADLINE_PUBLICATION_EDGE_NOT_EXERCISED age=%0d",pair[1].guard.age);
      if(commit_valid[1] || publication)
        $fatal(1,"DEADLINE_PUBLICATION_NOT_VETOED commit=%0b publication=%0b",commit_valid[1],publication);
      repeat(5) @(negedge fft_clk);
      if(pubs || reads[1] || !guard_reasons[1][7] || !bank_fault[1]) $fatal(1,"DEADLINE_ESCAPED");
      $display("DEADLINE_VETO qualified_certificate_held=1 original_publications=%0d",original_publish>=0);
    end else if(CASE==3) begin
      start_job(); send_status();
      wait(issuer.bank.staged.certificate_seen && issuer.bank.staged.seal_q);
      @(negedge fft_clk); external_fault=1;
      #0.001; if(publication || commit_valid[1]) $fatal(1,"CURRENT_CERTIFICATE_LOSS_NOT_DIRECT");
      repeat(5) @(negedge fft_clk);
      if(pubs || reads[1] || !bank_fault[1]) $fatal(1,"CURRENT_FAULT_PUBLISHED");
    end else if(CASE==4 || CASE==5) begin
      start_job(); send_status(); output_ready=1;
      wait(reads[1]==(CASE==4?17:510)); @(negedge clk); slow_enable=0;
      @(negedge fft_clk); external_fault=1;
      wait(fast_fault); repeat(3) @(negedge fft_clk); slow_enable=1;
      wait(slow_fault); repeat(4) @(negedge clk);
      if(reads[1]!=(CASE==4?19:512) || releases || reusable || !guard_fault[1] || !bank_fault[1])
        $fatal(1,"PAUSED_PREFIX_ACK_QUARANTINE reads=%0d",reads[1]);
      $display("PROVISIONAL_PREFIX count=%0d healthy=0 releases=0",reads[1]);
    end else if(CASE==6) begin
      @(negedge clk); slow_enable=0;
      start_job(); send_status(); wait(pubs==1);
      @(negedge fft_clk); external_fault=1;
      wait(fast_fault); repeat(3) @(negedge fft_clk); output_ready=1; slow_enable=1;
      wait(slow_fault); repeat(5) @(negedge clk);
      if(reads[1] || releases || reusable || !bank_fault[1]) $fatal(1,"UNOBSERVED_REQUEST_FAULT_LEAKED_OUTPUT");
      $display("PENDING_REQUEST_FAULT_PREFIX count=0");
    end else if(CASE>=7 && CASE<=9) begin
      // A single corrupted first token needs a later unchanged token to
      // expose local inconsistency. Stop raw offers before other causes can
      // mask the required tagged metadata failure.
      output_limit=CASE==7?2:CASE==8?18:512;
      start_job(); repeat(5) @(negedge fft_clk);
      if(!bank_reasons[3] || !issuer.bank.staged.fault_token_q ||
         issuer.bank.staged.fault_position_q!==(CASE==7?9'd1:CASE==8?9'd17:9'd511) ||
         issuer.bank.staged.fault_lease_q!==0 || pubs || reads[1])
        $fatal(1,"TAGGED_SINGLE_METADATA_CORRUPTION_NOT_REJECTED");
      $display("METADATA_REJECT bit=%0d offered=%0d fault_position=%0d lease=%0d",BIT,CASE==7?0:CASE==8?17:511,issuer.bank.staged.fault_position_q,issuer.bank.staged.fault_lease_q);
    end else if(CASE==10) begin
      fork : reset_stage
        begin start_job(); send_status(); output_ready=(BIT>=5); forever @(negedge fft_clk); end
        begin
          case(BIT)
            0: wait(issuer.producer_reference);
            1: wait(takes==17);
            2: wait(takes==512 && !issuer.certificate_reference);
            3: wait(cert_take);
            4: wait(out_valid[1]);
            5: wait(reads[1]==17);
            6: wait(reader_ack);
            default: $fatal(1,"UNKNOWN_RESET_STAGE");
          endcase
          reset_trigger=1;
        end
      join_any
      disable reset_stage;
      if(!reset_trigger) $fatal(1,"RESET_STAGE_NOT_REACHED");
      $display("RESET_STAGE phase=%0d takes=%0d certs=%0d pubs=%0d reads=%0d ack=%0d",BIT,takes,certs,pubs,reads[1],reader_ack);
      common_reset(); job=1; start_job(); send_status(); drain_job();
    end else if(CASE==11) begin
      start_job(); send_status(); wait(out_valid[1]);
      repeat(23) @(negedge clk);
      if(reads[1] || releases || reusable) $fatal(1,"FIRST_READ_STALL_NOT_RETAINED");
      output_ready=1; wait(reads[1]==511); @(negedge clk); output_ready=0;
      repeat(29) @(negedge clk);
      if(reads[1]!=511 || !out_valid[1] || !out_last[1] || reader_ack || releases || reusable)
        $fatal(1,"FINAL_READ_STALL_NOT_RETAINED");
      $display("FIRST_FINAL_SLOW_STALL first_cycles=23 final_cycles=29");
      drain_job();
    end else if(CASE==12) begin
      start_job(); send_status(); output_ready=1;
      wait(lease_release); @(negedge fft_clk);
      if(reads[1]!=512 || !reader_ack || busy[1] || releases)
        $fatal(1,"RELEASE_EDGE_PREMISE_NOT_REACHED");
      external_fault=1; #0.001;
      if(lease_release || reusable) $fatal(1,"RELEASE_EDGE_CURRENT_FAULT_NOT_VETOED");
      repeat(8) @(negedge fft_clk);
      if(releases || reusable || !bank_fault[1] || !guard_fault[1])
        $fatal(1,"LATE_RELEASE_FAULT_OWNERSHIP_ESCAPED");
      $display("RELEASE_EDGE_CURRENT_VETO reads=512 release=0 reusable=0");
    end else $fatal(1,"UNKNOWN_NONZERO_CASE");
    $display("INVERSE_GUARD_OFFLINE_PASS case=%0d phase_ps=%0d synthetic_not_fft=1",CASE,PHASE_PS);
    $finish(0);
  end
endmodule
