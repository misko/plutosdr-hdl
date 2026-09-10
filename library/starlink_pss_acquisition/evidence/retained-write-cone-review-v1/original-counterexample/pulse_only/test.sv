// OFFLINE_NOT_FFT: real unchanged arithmetic/mailboxes, scripted FFT ports.
`timescale 1ns/1fs
module tb;
  parameter integer STALL=0;
  parameter integer FAULT_KIND=0,FAULT_OFFSET=0,FAULT_BOUNDARY=0;
  parameter integer RESET_SIDE=0,BLOCKS=3;
  parameter real SLOW_PHASE=1.3;
  reg clk=0,fft_clk=0,resetn=0,fft_resetn=0,run_slow=1,new_epoch=0;
  always #2.857143 fft_clk=~fft_clk;
  initial begin #(SLOW_PHASE);forever begin #5;if(run_slow)clk=~clk;end end
  retained_clock_witness #(.SLOW_PHASE(SLOW_PHASE)) clocks(.fast_clk(fft_clk),.slow_clk(clk),.slow_clock_enabled(run_slow));
  reg input_valid=0;wire input_ready;reg[35:0]input_data=0;
  reg[8:0]input_position=0;reg input_last=0;reg[63:0]input_block_start=0;
  wire output_valid,output_last,fault;reg output_ready=1;
  wire[35:0]output_data;wire[8:0]output_position;wire[74:0]output_metadata;
  starlink_pss_fft_bank_owned_retained_output_probe #(.ENABLE_RETAINED_OUTPUT(1),
    .REGISTERED_SCHEDULING(1),.BOUNDARY_ROUND_SAT(1),.REGISTER_OPERANDS(1),
    .LOCAL_FIRST_ADMISSION(1)) dut(.*);
  `define D dut.retained.island
  reg[31:0]samples[0:1405];reg[35:0]forwards[0:1535],products[0:1535],inverses[0:1535];
  reg[4:0]fe[0:2],ie[0:2];
  integer fast_cycles=0,slow_cycles=0,forward_jobs=0,inverse_jobs=0,read_count=0;
  integer source_count=0,forward_words=0,product_words=0,inverse_words=0,status_count=0;
  integer slow_edges=0,resume_edge=0,output_fixture_base=0,last_forward_admit=-1,max_forward_interval=0;
  integer max_retained_wait=0,max_inverse_publication_interval=0;
  integer ack_f_input=0,ack_f_output=0,ack_f_handoff=0,held_final_prefetch=0,parked_full_source=0;
  integer ack_zero_controls=0;
  integer overlap_inputs=0,overlap_reads=0,retained_finals=0,parked_wait_i=0;
  integer last_inverse_publish=-1,last_real_release=-1,first_dispatch=-1;
  integer selected_fixture=0,raw_words=0,raw_phase=0;
  reg inject_frame=0,inject_output=0,inject_status=0,inject_vendor=0,fault_injected=0,collision_done=0;
  integer inverse_publications=0,publication_anchor=0,fault_anchor=0,boundary_edge=0;
  reg stalled=0;reg[120:0]held_output;
  always @(posedge fft_clk)begin
    fast_cycles=fast_cycles+1;
    if(`D.fast_running)begin
      if(!fault_injected&&(fault!==0||`D.any_fast_fault!==0))$fatal(1,"composition health cycle=%0d state=%0d fault=%b cut=%h owner=%h f=%h i=%h",fast_cycles,`D.state,`D.any_fast_fault,`D.cutover_reasons,`D.retained_reasons,`D.owners[0].result_guard.faults_now,`D.owners[1].result_guard.faults_now);
      if(`D.job_accept)begin
        if(`D.next_inverse)begin
          if(inverse_jobs>0&&last_real_release<0&&!(RESET_SIDE!=0&&new_epoch&&inverse_jobs==1))$fatal(1,"next inverse before real read release");
          if(last_real_release>=0&&fast_cycles<=last_real_release)$fatal(1,"next inverse requires registered actual release");
          if(`D.retained_published!==0)$fatal(1,"next inverse retained old owner");
          inverse_jobs=inverse_jobs+1;
        end else begin
          if(forward_jobs>0&&!(RESET_SIDE!=0&&new_epoch&&forward_jobs==2))begin
            if(last_inverse_publish<0||`D.retained_published!==1)$fatal(1,"no retained overlap at next F");
            if(first_dispatch<0)first_dispatch=fast_cycles-last_inverse_publish;
            $display("OFFLINE_DISPATCH block=%0d clocks=%0d",forward_jobs,fast_cycles-last_inverse_publish);
            if(fast_cycles-last_forward_admit>max_forward_interval)max_forward_interval=fast_cycles-last_forward_admit;
          end
          last_forward_admit=fast_cycles;
          forward_jobs=forward_jobs+1;
        end
        selected_fixture=(forward_jobs-1)%3;raw_words=0;raw_phase=`D.next_inverse;
        $display("OFFLINE_JOB phase=%0d fixture=%0d admit_cycle=%0d",raw_phase,selected_fixture,fast_cycles);
      end
      if(`D.core_status_valid&&inject_status===0)begin
        if(raw_words!=2||`D.core_status_data!=={3'b0,(raw_phase?ie[selected_fixture]:fe[selected_fixture])})$fatal(1,"third raw status");
        status_count=status_count+1;
      end
      if(`D.core_output_valid&&inject_output===0)begin
        if(`D.core_output_user[8:0]!==9'(raw_words)||`D.core_output_last!==(raw_words==511))$fatal(1,"raw ordinal");
        raw_words=raw_words+1;
      end
      if(`D.forward_retirement_valid&&`D.product_bank_ready)begin
        if(`D.return_position!==9'(forward_words%512)||`D.return_data!==forwards[selected_fixture*512+`D.return_position]||`D.return_metadata[4:0]!==fe[selected_fixture])$fatal(1,"forward exact word");
        forward_words=forward_words+1;
      end
      if(`D.product_valid&&`D.product_bank_ready)begin
        if(`D.product_position!==9'(product_words%512)||{`D.product_q,`D.product_i}!==products[selected_fixture*512+`D.product_position]||`D.product_exponent!==fe[selected_fixture])$fatal(1,"product exact word");
        product_words=product_words+1;
      end
      if(`D.guard_private_out[1]&&`D.output_bank_ready)begin
        if(`D.guard_return_position[1]!==9'(inverse_words%512)||`D.guard_return_data[1]!==inverses[selected_fixture*512+`D.guard_return_position[1]])$fatal(1,"private inverse exact word");
        inverse_words=inverse_words+1;
      end
      if(`D.guard_commit_out[1]&&`D.output_bank_ready)begin
        inverse_publications=inverse_publications+1;
        if(fault_injected)$fatal(1,"new inverse publication after current fault");
        if(last_inverse_publish>=0&&fast_cycles-last_inverse_publish>max_inverse_publication_interval)
          max_inverse_publication_interval=fast_cycles-last_inverse_publish;
        last_inverse_publish=fast_cycles;last_real_release=-1;
        $display("OFFLINE_PUBLICATION block=%0d cycle=%0d",inverse_jobs-1,fast_cycles);
      end
      if(`D.guard_ack[1]&&!fault_injected)begin
        if({`D.retained_owner.inverse_admit,`D.retained_owner.inverse_publication,`D.retained_owner.transfer_consumed}!==3'b000)
          $fatal(1,"healthy actual guard ACK controls must be independently known zero");
        ack_zero_controls=ack_zero_controls+1;
        $display("OFFLINE_ACK_CONTROLS cycle=%0d admit=0 publication=0 transfer=0",fast_cycles);
      end
      if(`D.reader_release)begin
        if(fast_cycles-last_inverse_publish>max_retained_wait)max_retained_wait=fast_cycles-last_inverse_publish;
        last_real_release=fast_cycles;$display("OFFLINE_REAL_ACK cycle=%0d",fast_cycles);
        if(!`D.routed_inverse&&`D.core_input_valid&&`D.core_input_ready)ack_f_input=ack_f_input+1;
        if(!`D.routed_inverse&&`D.core_output_valid)ack_f_output=ack_f_output+1;
        if(`D.forward_committed&&`D.owners[0].result_guard.awaiting_ack)ack_f_handoff=ack_f_handoff+1;
      end
      if(`D.retained_published&&`D.core_input_valid&&`D.core_input_ready&&!`D.routed_inverse)
        overlap_inputs=overlap_inputs+1;
      if(`D.retained_published&&!`D.core_aresetn&&output_valid)retained_finals=retained_finals+1;
      if(`D.retained_published&&`D.product_bank_valid&&`D.next_inverse&&`D.state==2)
        parked_wait_i=parked_wait_i+1;
      if(`D.retained_published&&`D.product_bank_valid&&`D.source_valid&&`D.next_inverse&&`D.state==2)
        parked_full_source=parked_full_source+1;
      if(output_valid&&output_last&&!output_ready&&`D.retained_published)held_final_prefetch=held_final_prefetch+1;
      if(fast_cycles>1500000)$fatal(1,"whole-bench fast deadline");
    end
  end
  always @(negedge clk)begin
    slow_cycles=slow_cycles+1;
    output_ready=(RESET_SIDE!=0&&!new_epoch)||STALL==6 ? 0 : STALL==0 ? 1 : STALL==1 ? (slow_cycles%17<13) :
      STALL==5 ? (!output_last||inverse_jobs==BLOCKS||`D.forward_committed) :
      (`D.retained_published&&fast_cycles-last_inverse_publish>(STALL==2?2200:STALL==4?500:9000));
  end
  always @(posedge clk)begin
    slow_edges=slow_edges+1;
    if(input_valid&&input_ready)source_count=source_count+1;
    if(resetn&&fft_resetn)begin
      if(stalled&&output_valid&&{output_data,output_position,output_last,output_metadata}!==held_output)$fatal(1,"retained read payload changed");
      stalled=output_valid&&!output_ready;held_output={output_data,output_position,output_last,output_metadata};
      if(output_valid&&output_ready)begin
        if(output_data!==inverses[(output_fixture_base+read_count/512)%3*512+read_count%512]||
          output_position!==9'(read_count%512)||output_last!==(read_count%512==511)||
          output_metadata!=={1'b1,64'(1000+(output_fixture_base+read_count/512)*447),fe[(output_fixture_base+read_count/512)%3],ie[(output_fixture_base+read_count/512)%3]})
          $fatal(1,"old reader exact identity/payload count=%0d",read_count);
        if(!`D.routed_inverse&&`D.cutover.owner_open)overlap_reads=overlap_reads+1;
        read_count=read_count+1;
      end
    end else stalled=0;
  end
  integer block_index,word_index,drain_anchor;
  initial begin
    $readmemh("samples_ci16.mem",samples);$readmemh("forward_q17.mem",forwards);
    $readmemh("product_q17.mem",products);$readmemh("inverse_q17.mem",inverses);
    $readmemh("forward_exponents.mem",fe);$readmemh("inverse_exponents.mem",ie);
    repeat(10)@(negedge fft_clk);resetn=1;fft_resetn=1;
    for(block_index=0;block_index<BLOCKS;block_index=block_index+1)begin
      if(RESET_SIDE!=0&&block_index==2)begin
        wait(`D.retained_published&&!`D.routed_inverse&&`D.shared_xfft.input_count>=64);
        @(negedge clk);run_slow=0;
        if(`D.source_valid!==1||output_valid!==1||read_count!=0)$fatal(1,"old full source/retained reader reset premise");
        @(negedge fft_clk);if(RESET_SIDE==1)resetn=0;else fft_resetn=0;
        #0.001;if(`D.fast_running!==0||output_valid!==0)$fatal(1,"common reset did not close outputs");
        repeat(4)@(negedge fft_clk);resetn=1;fft_resetn=1;
        repeat(20)begin @(negedge fft_clk);if(`D.fast_running!==0||`D.job_accept!==0)$fatal(1,"paused clock stale rearm");end
        resume_edge=slow_edges;run_slow=1;wait(`D.fast_running);
        if(slow_edges-resume_edge<4||output_valid!==0||`D.source_valid!==0||`D.retained_published!==0)
          $fatal(1,"fresh common reset barrier failed");
        new_epoch=1;output_fixture_base=2;last_inverse_publish=-1;last_real_release=-1;
        $display("OFFLINE_RESET side=%0d old_output_unread=512 aborted_F_input_prefix_at_least64 fresh_purge_slow_edges=%0d",RESET_SIDE,slow_edges-resume_edge);
      end
      for(word_index=0;word_index<512;word_index=word_index+1)begin
        @(negedge clk);input_valid=1;input_position=9'(word_index);input_last=word_index==511;
        input_block_start=1000+block_index*447;
        input_data={samples[block_index*447+word_index][31:16],2'b0,samples[block_index*447+word_index][15:0],2'b0};
        do begin @(posedge clk);end while(input_ready!==1'b1);
        #0.001;
      end
      @(negedge clk);input_valid=0;
    end
    if(FAULT_KIND!=0)wait(collision_done);
    drain_anchor=fast_cycles;
    while(read_count!=(RESET_SIDE!=0?512:BLOCKS*512)||!`D.retained_reusable)begin
      @(negedge fft_clk);
      if(fast_cycles-drain_anchor>=25000)begin
        if(STALL==6)begin
          if(`D.retained_published!==1||`D.retained_reusable!==0||read_count!=0||
            `D.owners[0].result_guard.active!==0||`D.owners[1].result_guard.active!==0||
            `D.any_fast_fault!==0)$fatal(1,"stopped-reader protocol classification");
          $display("OFFLINE_DRAIN_TIMEOUT anchor=%0d cycle=%0d elapsed=%0d retained=1 guard_active=0/0 read=0",drain_anchor,fast_cycles,fast_cycles-drain_anchor);
        end
        $fatal(1,"25000-fast bounded result drain");
      end
    end
    repeat(20)@(negedge fft_clk);
    if(source_count!=BLOCKS*512||forward_jobs!=BLOCKS||inverse_jobs!=(RESET_SIDE!=0?2:BLOCKS)||
      forward_words!=(RESET_SIDE!=0?1024:BLOCKS*512)||product_words!=forward_words||inverse_words!=forward_words||
      status_count!=(RESET_SIDE!=0?4:BLOCKS*2)||overlap_inputs==0||
      (RESET_SIDE==0&&STALL<2&&overlap_reads==0)||((STALL==2||STALL==3)&&parked_wait_i==0)||retained_finals==0)
      $fatal(1,"inventory source%0d F%0d I%0d fw%0d p%0d iw%0d status%0d overlap%0d/%0d reset%0d",source_count,forward_jobs,inverse_jobs,forward_words,product_words,inverse_words,status_count,overlap_inputs,overlap_reads,retained_finals);
    if(RESET_SIDE==0&&STALL<=2&&max_forward_interval>5215)$fatal(1,"175 fast service cap");
    if(STALL==3&&max_retained_wait<=8192)$fatal(1,"long reader did not outlive active watchdog");
    if(ack_f_input!=0)$fatal(1,"unexpected unreachable175/100 early sampled ACK");
    if(STALL==4&&ack_f_output==0)$fatal(1,"missing real ACK during F raw output");
    if(STALL==5&&(ack_f_handoff==0||held_final_prefetch==0))$fatal(1,"missing held final/real ACK handoff");
    if(STALL==2&&parked_full_source==0)$fatal(1,"next complete source not retained behind full product");
    if(ack_zero_controls!=(RESET_SIDE!=0?1:BLOCKS))$fatal(1,"complete healthy ACK zero-control witnesses");
    $display("OFFLINE_ACK_PHASE input=%0d output=%0d handoff=%0d held_final_prefetch=%0d parked_full_source=%0d",ack_f_input,ack_f_output,ack_f_handoff,held_final_prefetch,parked_full_source);
    $display("OFFLINE_SERVICE max_forward_interval=%0d max_inverse_publication_interval=%0d max_retained_wait=%0d capacity_claim=%0d",max_forward_interval,max_inverse_publication_interval,max_retained_wait,RESET_SIDE==0&&STALL<=2);
    $display("OFFLINE_PASS composition SCRIPTED_NOT_FFT source=%0d forward=%0d product=%0d inverse=%0d read=%0d overlap_input=%0d overlap_read=%0d first_dispatch=%0d",source_count,forward_words,product_words,inverse_words,read_count,overlap_inputs,overlap_reads,first_dispatch);$finish;
  end
  initial begin #9000000;$fatal(1,"absolute offline timeout");end
  initial if(FAULT_KIND!=0)begin : fault_stimulus
    if(FAULT_BOUNDARY==0)wait(`D.guard_commit_out[1]&&`D.output_bank_ready);
    else if(FAULT_BOUNDARY==1)wait(`D.forward_handoff_ack);
    else if(FAULT_BOUNDARY==2)begin
      wait(`D.forward_handoff_ack);wait(!`D.owners[0].result_guard.awaiting_ack);
    end else if(FAULT_BOUNDARY==3)wait(read_count==128);
    else wait(`D.reader_release);
    // Observe each target before its actual sampled edge; no posedge drive race.
    boundary_edge=fast_cycles+1;
    if(FAULT_OFFSET>0)begin repeat(FAULT_OFFSET)@(posedge fft_clk);@(negedge fft_clk);end
    publication_anchor=inverse_publications;fault_anchor=fast_cycles;
    if(`D.shared_xfft.base_raw_valid!==0)$fatal(1,"injection would mask an actual scripted raw word");
    if(FAULT_BOUNDARY==0&&FAULT_OFFSET==13&&FAULT_KIND==1)begin
      // At precisely the next F's first input, frame is already one. An OR
      // offer of the same value is not an independently observable extra event.
      if(`D.event_frame!==1||`D.core_input_valid!==1||`D.core_input_ready!==1||
        `D.shared_xfft.input_count!=0)$fatal(1,"same-level frame collision premise");
      inject_frame=1;#0.001;if(`D.common_current_fault!==0)$fatal(1,"legal natural frame rejected");
      @(posedge fft_clk);#0.001;
      if(fast_cycles!=boundary_edge+FAULT_OFFSET)$fatal(1,"collision sampled-edge offset");
      @(negedge fft_clk);inject_frame=0;collision_done=1;
      $display("OFFLINE_UNOBSERVABLE same-level frame offer equals natural first-input frame at offset13; full healthy replay required");
      disable fault_stimulus;
    end
    fault_injected=1;
    case(FAULT_KIND)
      1:inject_frame=1;2:inject_status=1;3:inject_output=1;4:inject_vendor=1;
      5:inject_status=1'bx;6:inject_output=1'bz;7:inject_frame=1'bx;8:inject_vendor=1'bz;
    endcase
    #0.001;
    if(`D.common_current_fault!==1||`D.guard_commit_out[1]!==0)
      $fatal(1,"same-edge full-composition raw fault fence");
    if(FAULT_BOUNDARY==4&&(`D.guard_ack[1]!==1||`D.reader_release!==0||
      `D.output_bank_ready!==1||`D.output_request!==`D.output_ack_sync))
      $fatal(1,"actual old ACK/current F fault attribution");
    @(posedge fft_clk);#0.001;
    if(fast_cycles!=boundary_edge+FAULT_OFFSET)$fatal(1,"actual raw fault sampled-edge offset");
    $display("OFFLINE_RAW_SAMPLE boundary_edge=%0d sample_edge=%0d offset=%0d",boundary_edge,fast_cycles,FAULT_OFFSET);
    @(negedge fft_clk);
    inject_frame=0;inject_status=0;inject_output=0;inject_vendor=0;
    repeat(24)@(negedge fft_clk);
    if(fault!==1||`D.fast_fault!==1||inverse_publications!=publication_anchor||`D.job_accept!==0||
      `D.retained_reusable!==0||output_valid!==0)$fatal(1,"24-fast quarantine/retained inventory");
    if(FAULT_BOUNDARY==3&&(read_count<128||read_count>132||forward_jobs!=2))
      $fatal(1,"preserved 128..132 provisional prefix with legitimate next F");
    $display("OFFLINE_PASS expected raw fault boundary=%0d kind=%0d offset=%0d Fjobs=%0d Ijobs=%0d Fwords=%0d Pwords=%0d Iwords=%0d reads=%0d retained=%0d",FAULT_BOUNDARY,FAULT_KIND,FAULT_OFFSET,forward_jobs,inverse_jobs,forward_words,product_words,inverse_words,read_count,`D.retained_published);$finish;
  end
  `undef D

  // Test-only unconditionally sampled baseline guards; no DUT feedback.
  starlink_pss_realtime_result_guard #(.USE_COMPLETED_INPUT_FAULT(1),
    .USE_PREFLIGHT_REASON_ONLY(1),.USE_FORWARD_RETIREMENT(1)) baseline_guard_0(.clk(dut.retained.island.owners[0].result_guard.clk),
.resetn(dut.retained.island.owners[0].result_guard.resetn),
.job_valid(dut.retained.island.owners[0].result_guard.job_valid),
.job_descriptor(dut.retained.island.owners[0].result_guard.job_descriptor),
.input_bank_reserved(dut.retained.island.owners[0].result_guard.input_bank_reserved),
.output_bank_reserved(dut.retained.island.owners[0].result_guard.output_bank_reserved),
.certified_input_beat(dut.retained.island.owners[0].result_guard.certified_input_beat),
.certified_input_complete(dut.retained.island.owners[0].result_guard.certified_input_complete),
.final_fence_certified(dut.retained.island.owners[0].result_guard.final_fence_certified),
.external_fault_now(dut.retained.island.owners[0].result_guard.external_fault_now),
.phase_input_fault_now(dut.retained.island.owners[0].result_guard.phase_input_fault_now),
.completed_input_certified(dut.retained.island.owners[0].result_guard.completed_input_certified),
.completed_input_fault_now(dut.retained.island.owners[0].result_guard.completed_input_fault_now),
.preflight_fault_evidence_now(dut.retained.island.owners[0].result_guard.preflight_fault_evidence_now),
.core_event_frame_started(dut.retained.island.owners[0].result_guard.core_event_frame_started),
.core_output_tdata(dut.retained.island.owners[0].result_guard.core_output_tdata),
.core_output_tuser(dut.retained.island.owners[0].result_guard.core_output_tuser),
.core_output_tvalid(dut.retained.island.owners[0].result_guard.core_output_tvalid),
.core_output_tlast(dut.retained.island.owners[0].result_guard.core_output_tlast),
.core_status_tdata(dut.retained.island.owners[0].result_guard.core_status_tdata),
.core_status_tvalid(dut.retained.island.owners[0].result_guard.core_status_tvalid),
.mailbox_input_ready(dut.retained.island.owners[0].result_guard.mailbox_input_ready),
.mailbox_input_fault(dut.retained.island.owners[0].result_guard.mailbox_input_fault),
.inverse_phase(dut.retained.island.owners[0].result_guard.inverse_phase),
.forward_mailbox_fault(dut.retained.island.owners[0].result_guard.forward_mailbox_fault));
  always @(posedge fft_clk or negedge fft_clk)begin #0.001;if(baseline_guard_0.job_ready !== dut.retained.island.owners[0].result_guard.job_ready) $fatal(1,"unconditional owner0 job_ready");
if(baseline_guard_0.mailbox_input_valid !== dut.retained.island.owners[0].result_guard.mailbox_input_valid) $fatal(1,"unconditional owner0 mailbox_input_valid");
if(baseline_guard_0.mailbox_private_valid !== dut.retained.island.owners[0].result_guard.mailbox_private_valid) $fatal(1,"unconditional owner0 mailbox_private_valid");
if(baseline_guard_0.mailbox_commit_valid !== dut.retained.island.owners[0].result_guard.mailbox_commit_valid) $fatal(1,"unconditional owner0 mailbox_commit_valid");
if(baseline_guard_0.forward_retirement_valid !== dut.retained.island.owners[0].result_guard.forward_retirement_valid) $fatal(1,"unconditional owner0 forward_retirement_valid");
if(baseline_guard_0.mailbox_input_data !== dut.retained.island.owners[0].result_guard.mailbox_input_data) $fatal(1,"unconditional owner0 mailbox_input_data");
if(baseline_guard_0.mailbox_input_position !== dut.retained.island.owners[0].result_guard.mailbox_input_position) $fatal(1,"unconditional owner0 mailbox_input_position");
if(baseline_guard_0.mailbox_input_last !== dut.retained.island.owners[0].result_guard.mailbox_input_last) $fatal(1,"unconditional owner0 mailbox_input_last");
if(baseline_guard_0.mailbox_input_metadata !== dut.retained.island.owners[0].result_guard.mailbox_input_metadata) $fatal(1,"unconditional owner0 mailbox_input_metadata");
if(baseline_guard_0.busy !== dut.retained.island.owners[0].result_guard.busy) $fatal(1,"unconditional owner0 busy");
if(baseline_guard_0.commit_pulse !== dut.retained.island.owners[0].result_guard.commit_pulse) $fatal(1,"unconditional owner0 commit_pulse");
if(baseline_guard_0.protocol_fault !== dut.retained.island.owners[0].result_guard.protocol_fault) $fatal(1,"unconditional owner0 protocol_fault");
if(baseline_guard_0.fault_reasons !== dut.retained.island.owners[0].result_guard.fault_reasons) $fatal(1,"unconditional owner0 fault_reasons");
if(baseline_guard_0.active_private !== dut.retained.island.owners[0].result_guard.active_private) $fatal(1,"unconditional owner0 active_private");
if(baseline_guard_0.awaiting_ack !== dut.retained.island.owners[0].result_guard.awaiting_ack) $fatal(1,"unconditional owner0 awaiting_ack");
if(baseline_guard_0.descriptor !== dut.retained.island.owners[0].result_guard.descriptor) $fatal(1,"unconditional owner0 descriptor");
if(baseline_guard_0.input_count !== dut.retained.island.owners[0].result_guard.input_count) $fatal(1,"unconditional owner0 input_count");
if(baseline_guard_0.output_count !== dut.retained.island.owners[0].result_guard.output_count) $fatal(1,"unconditional owner0 output_count");
if(baseline_guard_0.input_complete_seen !== dut.retained.island.owners[0].result_guard.input_complete_seen) $fatal(1,"unconditional owner0 input_complete_seen");
if(baseline_guard_0.frame_seen !== dut.retained.island.owners[0].result_guard.frame_seen) $fatal(1,"unconditional owner0 frame_seen");
if(baseline_guard_0.status_seen !== dut.retained.island.owners[0].result_guard.status_seen) $fatal(1,"unconditional owner0 status_seen");
if(baseline_guard_0.exponent_seen !== dut.retained.island.owners[0].result_guard.exponent_seen) $fatal(1,"unconditional owner0 exponent_seen");
if(baseline_guard_0.status_exponent !== dut.retained.island.owners[0].result_guard.status_exponent) $fatal(1,"unconditional owner0 status_exponent");
if(baseline_guard_0.output_exponent !== dut.retained.island.owners[0].result_guard.output_exponent) $fatal(1,"unconditional owner0 output_exponent");
if(baseline_guard_0.age !== dut.retained.island.owners[0].result_guard.age) $fatal(1,"unconditional owner0 age");
if(baseline_guard_0.return_occupied !== dut.retained.island.owners[0].result_guard.return_occupied) $fatal(1,"unconditional owner0 return_occupied");
if(baseline_guard_0.return_last !== dut.retained.island.owners[0].result_guard.return_last) $fatal(1,"unconditional owner0 return_last");
if(baseline_guard_0.return_data !== dut.retained.island.owners[0].result_guard.return_data) $fatal(1,"unconditional owner0 return_data");
if(baseline_guard_0.return_position !== dut.retained.island.owners[0].result_guard.return_position) $fatal(1,"unconditional owner0 return_position");
if(baseline_guard_0.return_exponent !== dut.retained.island.owners[0].result_guard.return_exponent) $fatal(1,"unconditional owner0 return_exponent"); end
  starlink_pss_realtime_result_guard #(.USE_COMPLETED_INPUT_FAULT(1),
    .USE_PREFLIGHT_REASON_ONLY(1),.USE_FORWARD_RETIREMENT(1)) baseline_guard_1(.clk(dut.retained.island.owners[1].result_guard.clk),
.resetn(dut.retained.island.owners[1].result_guard.resetn),
.job_valid(dut.retained.island.owners[1].result_guard.job_valid),
.job_descriptor(dut.retained.island.owners[1].result_guard.job_descriptor),
.input_bank_reserved(dut.retained.island.owners[1].result_guard.input_bank_reserved),
.output_bank_reserved(dut.retained.island.owners[1].result_guard.output_bank_reserved),
.certified_input_beat(dut.retained.island.owners[1].result_guard.certified_input_beat),
.certified_input_complete(dut.retained.island.owners[1].result_guard.certified_input_complete),
.final_fence_certified(dut.retained.island.owners[1].result_guard.final_fence_certified),
.external_fault_now(dut.retained.island.owners[1].result_guard.external_fault_now),
.phase_input_fault_now(dut.retained.island.owners[1].result_guard.phase_input_fault_now),
.completed_input_certified(dut.retained.island.owners[1].result_guard.completed_input_certified),
.completed_input_fault_now(dut.retained.island.owners[1].result_guard.completed_input_fault_now),
.preflight_fault_evidence_now(dut.retained.island.owners[1].result_guard.preflight_fault_evidence_now),
.core_event_frame_started(dut.retained.island.owners[1].result_guard.core_event_frame_started),
.core_output_tdata(dut.retained.island.owners[1].result_guard.core_output_tdata),
.core_output_tuser(dut.retained.island.owners[1].result_guard.core_output_tuser),
.core_output_tvalid(dut.retained.island.owners[1].result_guard.core_output_tvalid),
.core_output_tlast(dut.retained.island.owners[1].result_guard.core_output_tlast),
.core_status_tdata(dut.retained.island.owners[1].result_guard.core_status_tdata),
.core_status_tvalid(dut.retained.island.owners[1].result_guard.core_status_tvalid),
.mailbox_input_ready(dut.retained.island.owners[1].result_guard.mailbox_input_ready),
.mailbox_input_fault(dut.retained.island.owners[1].result_guard.mailbox_input_fault),
.inverse_phase(dut.retained.island.owners[1].result_guard.inverse_phase),
.forward_mailbox_fault(dut.retained.island.owners[1].result_guard.forward_mailbox_fault));
  always @(posedge fft_clk or negedge fft_clk)begin #0.001;if(baseline_guard_1.job_ready !== dut.retained.island.owners[1].result_guard.job_ready) $fatal(1,"unconditional owner1 job_ready");
if(baseline_guard_1.mailbox_input_valid !== dut.retained.island.owners[1].result_guard.mailbox_input_valid) $fatal(1,"unconditional owner1 mailbox_input_valid");
if(baseline_guard_1.mailbox_private_valid !== dut.retained.island.owners[1].result_guard.mailbox_private_valid) $fatal(1,"unconditional owner1 mailbox_private_valid");
if(baseline_guard_1.mailbox_commit_valid !== dut.retained.island.owners[1].result_guard.mailbox_commit_valid) $fatal(1,"unconditional owner1 mailbox_commit_valid");
if(baseline_guard_1.forward_retirement_valid !== dut.retained.island.owners[1].result_guard.forward_retirement_valid) $fatal(1,"unconditional owner1 forward_retirement_valid");
if(baseline_guard_1.mailbox_input_data !== dut.retained.island.owners[1].result_guard.mailbox_input_data) $fatal(1,"unconditional owner1 mailbox_input_data");
if(baseline_guard_1.mailbox_input_position !== dut.retained.island.owners[1].result_guard.mailbox_input_position) $fatal(1,"unconditional owner1 mailbox_input_position");
if(baseline_guard_1.mailbox_input_last !== dut.retained.island.owners[1].result_guard.mailbox_input_last) $fatal(1,"unconditional owner1 mailbox_input_last");
if(baseline_guard_1.mailbox_input_metadata !== dut.retained.island.owners[1].result_guard.mailbox_input_metadata) $fatal(1,"unconditional owner1 mailbox_input_metadata");
if(baseline_guard_1.busy !== dut.retained.island.owners[1].result_guard.busy) $fatal(1,"unconditional owner1 busy");
if(baseline_guard_1.commit_pulse !== dut.retained.island.owners[1].result_guard.commit_pulse) $fatal(1,"unconditional owner1 commit_pulse");
if(baseline_guard_1.protocol_fault !== dut.retained.island.owners[1].result_guard.protocol_fault) $fatal(1,"unconditional owner1 protocol_fault");
if(baseline_guard_1.fault_reasons !== dut.retained.island.owners[1].result_guard.fault_reasons) $fatal(1,"unconditional owner1 fault_reasons");
if(baseline_guard_1.active_private !== dut.retained.island.owners[1].result_guard.active_private) $fatal(1,"unconditional owner1 active_private");
if(baseline_guard_1.awaiting_ack !== dut.retained.island.owners[1].result_guard.awaiting_ack) $fatal(1,"unconditional owner1 awaiting_ack");
if(baseline_guard_1.descriptor !== dut.retained.island.owners[1].result_guard.descriptor) $fatal(1,"unconditional owner1 descriptor");
if(baseline_guard_1.input_count !== dut.retained.island.owners[1].result_guard.input_count) $fatal(1,"unconditional owner1 input_count");
if(baseline_guard_1.output_count !== dut.retained.island.owners[1].result_guard.output_count) $fatal(1,"unconditional owner1 output_count");
if(baseline_guard_1.input_complete_seen !== dut.retained.island.owners[1].result_guard.input_complete_seen) $fatal(1,"unconditional owner1 input_complete_seen");
if(baseline_guard_1.frame_seen !== dut.retained.island.owners[1].result_guard.frame_seen) $fatal(1,"unconditional owner1 frame_seen");
if(baseline_guard_1.status_seen !== dut.retained.island.owners[1].result_guard.status_seen) $fatal(1,"unconditional owner1 status_seen");
if(baseline_guard_1.exponent_seen !== dut.retained.island.owners[1].result_guard.exponent_seen) $fatal(1,"unconditional owner1 exponent_seen");
if(baseline_guard_1.status_exponent !== dut.retained.island.owners[1].result_guard.status_exponent) $fatal(1,"unconditional owner1 status_exponent");
if(baseline_guard_1.output_exponent !== dut.retained.island.owners[1].result_guard.output_exponent) $fatal(1,"unconditional owner1 output_exponent");
if(baseline_guard_1.age !== dut.retained.island.owners[1].result_guard.age) $fatal(1,"unconditional owner1 age");
if(baseline_guard_1.return_occupied !== dut.retained.island.owners[1].result_guard.return_occupied) $fatal(1,"unconditional owner1 return_occupied");
if(baseline_guard_1.return_last !== dut.retained.island.owners[1].result_guard.return_last) $fatal(1,"unconditional owner1 return_last");
if(baseline_guard_1.return_data !== dut.retained.island.owners[1].result_guard.return_data) $fatal(1,"unconditional owner1 return_data");
if(baseline_guard_1.return_position !== dut.retained.island.owners[1].result_guard.return_position) $fatal(1,"unconditional owner1 return_position");
if(baseline_guard_1.return_exponent !== dut.retained.island.owners[1].result_guard.return_exponent) $fatal(1,"unconditional owner1 return_exponent"); end
  defparam dut.PRIVATE_DESCRIPTOR_OFFER=1;

  reg [69:0] saved_descriptor_0;
  reg owned_before_0,accepted_before_0,running_before_0;
  reg [69:0] offered_descriptor_0;
  integer accepted_checks_0=0,held_checks_0=0,ack_checks_0=0;
  always @(posedge fft_clk)begin
    running_before_0=dut.retained.island.fast_running;
    owned_before_0=dut.retained.island.owners[0].result_guard.active || dut.retained.island.owners[0].result_guard.awaiting_ack;
    accepted_before_0=dut.retained.island.owners[0].result_guard.job_accept;
    offered_descriptor_0=dut.retained.island.owners[0].result_guard.job_descriptor;
    saved_descriptor_0=dut.retained.island.owners[0].result_guard.descriptor;
    if(running_before_0 && accepted_before_0)begin
      if(dut.retained.island.owners[0].result_guard.private_descriptor_offer!==1'b1)$fatal(1,"accepted job missing private offer");
      accepted_checks_0=accepted_checks_0+1;
    end
    if(running_before_0 && dut.retained.island.owners[0].result_guard.owner_ack_accept)ack_checks_0=ack_checks_0+1;
    #0.000001;
    if(running_before_0 && dut.retained.island.fast_running)begin
      if(owned_before_0)begin
        if(dut.retained.island.owners[0].result_guard.descriptor!==saved_descriptor_0)$fatal(1,"active/parked/ACK descriptor overwrite");
        held_checks_0=held_checks_0+1;
      end
      if(accepted_before_0 && dut.retained.island.owners[0].result_guard.descriptor!==offered_descriptor_0)
        $fatal(1,"accepted descriptor same-edge mismatch");
    end
  end
  final begin
    if(accepted_checks_0<3 || held_checks_0<1000 || ack_checks_0<3)
      $fatal(1,"private descriptor witness inventory");
    $display("PRIVATE_OFFER_WITNESS owner=0 accepted=%0d held=%0d real_ack=%0d",accepted_checks_0,held_checks_0,ack_checks_0);
  end

  reg [69:0] saved_descriptor_1;
  reg owned_before_1,accepted_before_1,running_before_1;
  reg [69:0] offered_descriptor_1;
  integer accepted_checks_1=0,held_checks_1=0,ack_checks_1=0;
  always @(posedge fft_clk)begin
    running_before_1=dut.retained.island.fast_running;
    owned_before_1=dut.retained.island.owners[1].result_guard.active || dut.retained.island.owners[1].result_guard.awaiting_ack;
    accepted_before_1=dut.retained.island.owners[1].result_guard.job_accept;
    offered_descriptor_1=dut.retained.island.owners[1].result_guard.job_descriptor;
    saved_descriptor_1=dut.retained.island.owners[1].result_guard.descriptor;
    if(running_before_1 && accepted_before_1)begin
      if(dut.retained.island.owners[1].result_guard.private_descriptor_offer!==1'b1)$fatal(1,"accepted job missing private offer");
      accepted_checks_1=accepted_checks_1+1;
    end
    if(running_before_1 && dut.retained.island.owners[1].result_guard.owner_ack_accept)ack_checks_1=ack_checks_1+1;
    #0.000001;
    if(running_before_1 && dut.retained.island.fast_running)begin
      if(owned_before_1)begin
        if(dut.retained.island.owners[1].result_guard.descriptor!==saved_descriptor_1)$fatal(1,"active/parked/ACK descriptor overwrite");
        held_checks_1=held_checks_1+1;
      end
      if(accepted_before_1 && dut.retained.island.owners[1].result_guard.descriptor!==offered_descriptor_1)
        $fatal(1,"accepted descriptor same-edge mismatch");
    end
  end
  final begin
    if(accepted_checks_1<3 || held_checks_1<1000 || ack_checks_1<3)
      $fatal(1,"private descriptor witness inventory");
    $display("PRIVATE_OFFER_WITNESS owner=1 accepted=%0d held=%0d real_ack=%0d",accepted_checks_1,held_checks_1,ack_checks_1);
  end
  defparam dut.CLOSED_INPUT_CUTOVER=1;

  integer closed_checks=0,final_edges=0;
  always @(posedge fft_clk)begin
    if(dut.retained.island.fast_running && dut.retained.island.certified_input_complete===1'b1)begin
      if(dut.retained.island.checked_input_complete!==1'b0)$fatal(1,"final input premature closed certificate");
      if(dut.retained.island.guard_valid_out!==2'b0 || dut.retained.island.guard_commit_out!==2'b0 || dut.retained.island.forward_retirement_valid!==0)
        $fatal(1,"final input used closed public-return phase");
      final_edges=final_edges+1;
    end
    #0.001;
    if(dut.retained.island.fast_running && dut.retained.island.checked_input_complete===1'b1)begin
      if({dut.retained.island.certified_input_beat,dut.retained.island.certified_input_complete}!==2'b0)
        $fatal(1,"registered closed input has live certified strobe");
      if(dut.retained.island.cutover.closed_input_fault_now!==dut.retained.island.cutover.fault_now && 1)
        $fatal(1,"closed cutover predicate differs on use");
      closed_checks=closed_checks+1;
    end
  end
  final begin
    if(closed_checks<1000||final_edges<6)$fatal(1,"closed input composition inventory");
    $display("CLOSED_INPUT_WITNESS closed=%0d final_edges=%0d",closed_checks,final_edges);
  end

  integer parent_forward_ack_checks=0;
  always @(posedge fft_clk)begin
    if(dut.retained.island.fast_running && dut.retained.island.guard_ack[0])begin
      if(dut.retained.island.product_bank_valid!==1'b1)
        $fatal(1,"parent forward guard ACK before actual product bank publication cycle=%0d committed=%b commit_pulse=%b bank_valid=%b awaiting=%b ready=%b",fast_cycles,
          dut.retained.island.forward_committed,dut.retained.island.guard_commit[0],
          dut.retained.island.product_bank_valid,dut.retained.island.owners[0].result_guard.awaiting_ack,
          dut.retained.island.owners[0].result_guard.mailbox_input_ready);
      parent_forward_ack_checks=parent_forward_ack_checks+1;
    end
  end
  final $display("PARENT_FORWARD_ACK checks=%0d",parent_forward_ack_checks);
endmodule
