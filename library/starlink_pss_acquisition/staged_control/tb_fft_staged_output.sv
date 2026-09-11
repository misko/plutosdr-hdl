// SPDX-License-Identifier: GPL-2.0
// Real generated XFFT required. Exact frozen forward/product/inverse vectors.
// Changed control latency is measured, not assumed equal to the old controller.
`timescale 1ns/1fs
module tb;
  reg clk=0,fft_clk=0,resetn=0,fft_resetn=0,run_slow=1;
  always #2.857143 fft_clk=~fft_clk;
  initial begin #1.3;forever begin #5;if(run_slow)clk=~clk;end end
  reg input_valid=0,input_last=0,output_ready=0;
  reg [35:0] input_data=0;
  reg [8:0] input_position=0;
  reg [63:0] input_block_start=0;
  reg [63:0] context_start_base=1000;
  wire input_ready,output_valid,output_last,fault;
  wire [35:0] output_data;
  wire [8:0] output_position;
  wire [74:0] output_metadata;
  starlink_pss_fft_staged_output_impl #(.REGISTERED_SCHEDULING(1),
    .BOUNDARY_ROUND_SAT(1),.REGISTER_OPERANDS(1),.LOCAL_FIRST_ADMISSION(1),
    .PRIVATE_DESCRIPTOR_OFFER(1),.CLOSED_INPUT_CUTOVER(1),
    .INPUT_OFFER_FAULT_SUMMARY(1),.CONTEXTUAL_DESTINATION_SUMMARY(1)) dut(.*);
  reg [31:0] samples[0:1405];
  reg [35:0] forwards[0:1535],products[0:1535],inverses[0:1535];
  reg [4:0] fe[0:2],ie[0:2];
  integer mode=0,fast_cycles=0,slow_cycles=0,reads=0,jobs=0,publications=0,releases=0;
  integer forward_words=0,product_words=0,inverse_words=0,inputs=0,raws=0,statuses=0,frames=0;
  integer fixture=0,raw_position=0,input_count=0,last_forward=-1,max_service=0;
  integer overlap_inputs=0,overlap_reads=0,publication_cycle=0;
  reg phase=0,old_request=0,stalled=0;
  reg [120:0] held_output;
  reg [35:0] expected;
  integer log_file;
  reg stress=0,stress_drain=0,stress_fault_expected=0;
  integer stress_reads=0,stress_fixture=0,stress_prefix=0,stress_releases=0;
  integer handover_admissions=0,handover_completions=0,slow_edges=0;
  reg previous_admission=0,previous_completion=0;
  task automatic log_word(input string stream,input integer block_id,input integer position,
                input [47:0] data,input [9:0] exponent);
    $fdisplay(log_file,"%0d,%s,%0d,%0d,%012h,%03h",mode,stream,block_id,position,data,exponent);
  endtask
  always @(negedge clk) begin
    slow_cycles=slow_cycles+1;
    output_ready=stress ? stress_drain : mode==0 ? 1 : mode==1 ? slow_cycles%17<13 :
      mode==5 ? (!output_last || reads>=1024 || dut.forward_committed) :
      (dut.retained_published && fast_cycles-publication_cycle>(mode==2 ? 2200 : mode==4 ? 500 : 9000));
  end
  always @(posedge clk) begin
    slow_edges=slow_edges+1;
    if(resetn && fft_resetn && !stress) begin
      if(stalled && output_valid && held_output!=={output_data,output_position,output_last,output_metadata})
        $fatal(1,"stalled output changed");
      stalled=output_valid && !output_ready;held_output={output_data,output_position,output_last,output_metadata};
      if(output_valid && output_ready) begin
        if(reads>=1536 || output_position!==9'(reads%512) || output_last!==(reads%512==511) ||
           output_data!==inverses[reads] ||
           output_metadata!=={1'b1,64'(context_start_base+(reads/512)*447),fe[reads/512],ie[reads/512]} ||
           (^dut.output_control.committed===1'bx) || dut.output_control.committed==0 ||
           dut.reader_descriptor_tag!==dut.output_bank_metadata[36:5])
          $fatal(1,"native numerical/metadata output mismatch read=%0d",reads);
        log_word("read",reads/512,reads%512,{12'b0,output_data},output_metadata[9:0]);
        if(!dut.routed_inverse && dut.cutover.owner_open) overlap_reads=overlap_reads+1;
        reads=reads+1;
      end
    end else stalled=0;
    if(stress && resetn && fft_resetn && output_valid && output_ready) begin
      if(stress_reads>=512 || output_position!==9'(stress_reads) || output_last!==(stress_reads==511) ||
         output_data!==inverses[stress_fixture*512+stress_reads] ||
         output_metadata!=={1'b1,64'(1000+stress_fixture*447),fe[stress_fixture],ie[stress_fixture]})
        $fatal(1,"stress fresh output/descriptor mismatch");
      stress_reads=stress_reads+1;
    end
    if(output_valid && !dut.slow_metadata_valid) $fatal(1,"reader escaped metadata register boundary");
  end
  always @(posedge fft_clk) begin
    fast_cycles=fast_cycles+1;
    if(dut.fast_running && !stress) begin
      if(mode==0 && fast_cycles>=2748 && fast_cycles<=2760)
        $display("STAGED_TRACE cycle=%0d state=%0d known=%b job=%b config=%b close=%b common=%b ready=%b inverse_ready=%b live=%b pending=%b ctlphase=%0d ctlcmd=%0d guardfault=%b preflight=%h",
          fast_cycles,dut.state,dut.cutover.known,dut.job_accept,dut.cutover.config_accept,dut.completion_accept,
          dut.common_current_fault,dut.guard_ready,dut.inverse_guard_ready,dut.inverse_descriptor_live,
          dut.inverse_allocation_pending,dut.output_control.phase,dut.output_control.command_state,
          dut.guard_fault,dut.preflight_events_now);
      if(fault!==0 || dut.any_fast_fault!==0)
        $fatal(1,"FFT staged health mode=%0d cycle=%0d state=%0d cut=%h F=%h I=%h adapter=%b preflight=%h",
          mode,fast_cycles,dut.state,dut.cutover_reasons,dut.owners[0].result_guard.faults_now,
          dut.owners[1].result_guard.faults_now,dut.output_control_fault,dut.preflight_events_now);
      if(dut.job_accept) begin
        if(dut.engine_metadata[68:5]<context_start_base || (dut.engine_metadata[68:5]-context_start_base)%447!=0)
          $fatal(1,"admission timestamp mismatch");
        fixture=(dut.engine_metadata[68:5]-context_start_base)/447;phase=dut.next_inverse;
        if(fixture>2 || phase!==jobs[0]) $fatal(1,"job order mismatch");
        jobs=jobs+1;raw_position=0;input_count=0;
        if(!phase) begin
          if(last_forward>=0 && fast_cycles-last_forward>max_service) max_service=fast_cycles-last_forward;
          last_forward=fast_cycles;
        end
      end
      if(dut.core_input_valid && dut.core_input_ready) begin
        expected=phase ? products[fixture*512+input_count] :
          {samples[fixture*447+input_count][31:16],2'b0,samples[fixture*447+input_count][15:0],2'b0};
        if(input_count>=512 || dut.core_input_data!=={6'b0,expected[35:18],6'b0,expected[17:0]} ||
           dut.core_input_last!==(input_count==511)) $fatal(1,"core input mismatch");
        if(dut.retained_published && !phase) overlap_inputs=overlap_inputs+1;
        if(phase) log_word("inputI",fixture,input_count,dut.core_input_data,0);
        else log_word("inputF",fixture,input_count,dut.core_input_data,0);
        inputs=inputs+1;input_count=input_count+1;
      end
      if(dut.event_frame) frames=frames+1;
      if(dut.core_status_valid) begin
        if(raw_position!=2 || dut.core_status_data!=={3'b0,(phase?ie[fixture]:fe[fixture])})
          $fatal(1,"core status mismatch");
        statuses=statuses+1;
      end
      if(dut.core_output_valid) begin
        expected=phase?inverses[fixture*512+raw_position]:forwards[fixture*512+raw_position];
        if(raw_position>=512 || input_count!=512 ||
           dut.core_output_data!=={{6{expected[35]}},expected[35:18],{6{expected[17]}},expected[17:0]} ||
           dut.core_output_user!=={3'b0,(phase?ie[fixture]:fe[fixture]),7'b0,9'(raw_position)} ||
           dut.core_output_last!==(raw_position==511)) $fatal(1,"raw FFT numerical mismatch");
        if(phase) log_word("rawI",fixture,raw_position,dut.core_output_data,{5'b0,ie[fixture]});
        else log_word("rawF",fixture,raw_position,dut.core_output_data,{5'b0,fe[fixture]});
        raw_position=raw_position+1;raws=raws+1;
      end
      if(dut.forward_retirement_valid && dut.product_bank_ready) begin
        if(dut.return_data!==forwards[forward_words] || dut.return_position!==9'(forward_words%512))
          $fatal(1,"forward retirement mismatch");
        forward_words=forward_words+1;
      end
      if(dut.product_valid && dut.product_bank_ready) begin
        if({dut.product_q,dut.product_i}!==products[product_words] || dut.product_position!==9'(product_words%512))
          $fatal(1,"product mismatch");
        log_word("product",product_words/512,product_words%512,{12'b0,dut.product_q,dut.product_i},{5'b0,dut.product_exponent});
        product_words=product_words+1;
      end
      if(dut.guard_private_out[1] && dut.output_bank_ready) begin
        if(dut.guard_return_data[1]!==inverses[inverse_words] || dut.guard_return_position[1]!==9'(inverse_words%512))
          $fatal(1,"private inverse mismatch");
        log_word("privateI",inverse_words/512,inverse_words%512,{12'b0,dut.guard_return_data[1]},dut.guard_return_metadata[1][9:0]);
        inverse_words=inverse_words+1;
      end
      if(dut.output_request!==old_request) begin
        old_request=dut.output_request;publications=publications+1;publication_cycle=fast_cycles;
        if(dut.output_control.ledger.committed==0) $fatal(1,"publication without staged commit");
      end
      if(dut.reader_release) begin
        if(reads!=(releases+1)*512 || dut.output_request!==dut.output_ack_sync)
          $fatal(1,"early real-reader release");
        releases=releases+1;
      end
    end
  end
  // Receipt timing and physical core reset ordering, across all contexts.
  always @(posedge fft_clk) begin
    if(!dut.fast_running) begin previous_admission=0;previous_completion=0;end
    else begin
      if ((|dut.admission_reject)!==dut.common_current_fault)
        $fatal(1,"partitioned admission facts differ from full current predicate");
      if(dut.output_complete_accept && dut.inverse_descriptor_live!==1'b1)
        $fatal(1,"completion sampled private lookup without held ownership");
      if(dut.output_descriptor_pending && (dut.output_descriptor_valid || dut.output_replay_accept || dut.output_complete_accept))
        $fatal(1,"writer validation pending was overwritten or authorized output");
      if(dut.output_replay_accept!==(dut.output_replay_valid && dut.output_replay_private_ready && !dut.common_current_fault))
        $fatal(1,"private replay replaced current publication authorization");
      if(dut.completion_request && (((&dut.completion_good)===1'b1)!==(dut.legacy_completion_accept===1'b1)))
        $fatal(1,"completion facts differ from original close validation");
      if(dut.completion_accept && (!dut.completion_gate.snapshot_valid || !dut.completion_permit))
        $fatal(1,"producer close bypassed clocked facts");
      if(dut.job_accept && (!dut.admission_gate.snapshot_valid || !dut.admission_permit))
        $fatal(1,"private admission bypassed clocked certificate");
      if(dut.admission_receipt!==previous_admission || dut.completion_receipt!==previous_completion)
        $fatal(1,"handover receipt is not previous-edge validation");
      if(dut.cutover.job_accept!==(dut.admission_receipt && !dut.registered_quarantine) ||
         dut.cutover.producer_closed!==(dut.completion_receipt && !dut.registered_quarantine))
        $fatal(1,"raw validation bypassed registered handover");
      if(dut.cutover.job_accept) begin
        if(dut.core_aresetn!==0 || (!stress_fault_expected && dut.cutover_admission_allowed!==1))
          $fatal(1,"handover admitted before reset flush");
        handover_admissions=handover_admissions+1;
      end
      if(dut.cutover.producer_closed) begin
        if(dut.state!=7 || dut.core_aresetn!==1) $fatal(1,"handover closed outside owned producer");
        handover_completions=handover_completions+1;
      end
      previous_admission=dut.job_accept;previous_completion=dut.completion_accept;
      if(stress) begin
        if(!stress_fault_expected && (fault!==0 || dut.any_fast_fault!==0)) $fatal(1,"healthy reset stress fault");
        if(dut.core_input_valid && dut.core_input_ready && !dut.routed_inverse && dut.engine_metadata[68:5]==1447)
          stress_prefix=stress_prefix+1;
        if(dut.reader_release) stress_releases=stress_releases+1;
      end
    end
  end
  task automatic stress_reset;
    begin
      @(negedge fft_clk);resetn=0;fft_resetn=0;input_valid=0;stress_drain=0;
      repeat(10) @(negedge fft_clk);
      stress_reads=0;stress_prefix=0;stress_releases=0;stress_fault_expected=0;
      resetn=1;fft_resetn=1;
      while(!dut.fast_running) @(negedge fft_clk);
    end
  endtask
  task automatic admission_boundary(input integer boundary);
    reg request_before;
    begin
      stress_reset;stress_fixture=0;send_block(0);
      if(boundary==0) while(!dut.job_valid || dut.admission_gate.snapshot_valid) @(negedge fft_clk);
      else if(boundary==2) while(!dut.admission_receipt) @(negedge fft_clk);
      else while(!dut.admission_permit) @(negedge fft_clk);
      request_before=dut.output_request;stress_fault_expected=1;
      if(boundary==3) force dut.preflight_lease=1'b1;
      else if(boundary==4) resetn=0;
      else if(boundary==5) fft_resetn=0;
      else force dut.core_output_valid=1'b1;
      @(posedge fft_clk);#0.001;
      if(boundary<4 && (dut.input_job_start || dut.config_valid || dut.core_input_valid))
        $fatal(1,"admission fault escaped into FFT start/config/input");
      @(negedge fft_clk);release dut.core_output_valid;release dut.preflight_lease;
      if(boundary>=4) begin
        repeat(10) @(negedge fft_clk);
        resetn=1;fft_resetn=1;
      end
      repeat(100) begin
        @(negedge fft_clk);
        if(dut.input_job_start || dut.config_valid || dut.core_input_valid || dut.admission_permit ||
           dut.admission_receipt || dut.output_request!==request_before || dut.output_released_valid)
          $fatal(1,"stale admission certificate escaped cancellation boundary=%0d",boundary);
      end
      if(stress_reads!=0 || stress_releases!=0 || (boundary<4 && !fault))
        $fatal(1,"admission cancellation evidence missing");
      $display("STAGED_ADMISSION_CASE_PASS boundary=%0d starts_after_cancel=0 publications=0 releases=0",boundary);
    end
  endtask
  task automatic send_block(input integer number);
    integer position;
    begin
      for(position=0;position<512;position=position+1) begin
        @(negedge clk);input_valid=1;input_position=position;input_last=position==511;
        input_block_start=1000+number*447;
        input_data={samples[number*447+position][31:16],2'b0,samples[number*447+position][15:0],2'b0};
        @(posedge clk);while(input_ready!==1) @(posedge clk);
        #0.001;
      end
      @(negedge clk);input_valid=0;
    end
  endtask
  task automatic reset_stopped_reader(input integer side);
    integer resume_edge,prefix,purge_edges;
    begin
      stress_reset;stress_fixture=0;
      send_block(0);send_block(1);
      while(!dut.retained_published || dut.routed_inverse || stress_prefix<64) @(negedge fft_clk);
      @(negedge clk);run_slow=0;prefix=stress_prefix;
      if(stress_reads!=0 || output_valid!==1 || dut.source_valid!==1) $fatal(1,"paused-reader reset premise");
      @(negedge fft_clk);if(side==1) resetn=0;else fft_resetn=0;
      #0.001;
      if(dut.fast_running!==0 || output_valid!==0 || dut.cutover.job_accept!==0 || dut.cutover.producer_closed!==0)
        $fatal(1,"asynchronous reset did not fence queued handover");
      repeat(4) @(negedge fft_clk);resetn=1;fft_resetn=1;
      repeat(20) begin
        @(negedge fft_clk);
        if(dut.fast_running!==0 || dut.job_accept!==0 || output_valid!==0) $fatal(1,"stopped reader permitted stale restart");
      end
      resume_edge=slow_edges;run_slow=1;
      while(!dut.fast_running) @(negedge fft_clk);
      purge_edges=slow_edges-resume_edge;
      if(purge_edges<4 || dut.slow_metadata_valid!==0 || dut.source_valid!==0 ||
         output_valid!==0 || dut.output_control.occupied!==0) $fatal(1,"reset did not purge reader/descriptor state");
      stress_fixture=2;stress_reads=0;stress_drain=1;
      send_block(2);
      while(stress_reads!=512 || !dut.retained_reusable) @(negedge fft_clk);
      repeat(10) @(negedge fft_clk);
      if(stress_releases!=1) $fatal(1,"fresh reset result did not release once");
      $display("STAGED_RESET_PASS side=%0d old_unread=512 aborted_forward_prefix=%0d fresh_reads=512 slow_purge_edges=%0d",side,prefix,purge_edges);
    end
  endtask
  task automatic fault_boundary(input integer boundary);
    reg request_before;
    begin
      stress_reset;stress_fixture=0;send_block(0);
      case(boundary)
        0: while(!dut.admission_receipt) @(negedge fft_clk);
        1: while(!dut.completion_receipt) @(negedge fft_clk);
        2: while(!(dut.output_control.ledger.pending && dut.output_control.command_opcode==1)) @(negedge fft_clk);
        3: while(!dut.output_replay_valid) @(negedge fft_clk);
        4: while(!dut.slow_output_valid || dut.reader_descriptor_phase!=0) @(negedge fft_clk);
        5: begin
          stress_drain=1;
          while(!output_valid || output_position!=511) @(negedge clk);
        end
        6: while(!dut.output_complete_valid || !dut.output_complete_ready) @(negedge fft_clk);
      endcase
      request_before=dut.output_request;stress_fault_expected=1;
      if(boundary==0) force dut.core_output_valid=1'b1;
      else if(boundary==1) force dut.core_status_valid=1'b1;
      else if(boundary==4) begin
        force dut.output_descriptor_tag=32'hffffffff;stress_drain=1;
        @(posedge clk);#0.001;
        if(dut.reader_descriptor_phase!=1 || output_valid) $fatal(1,"descriptor capture was bypassed");
        release dut.output_descriptor_tag;
        @(posedge clk);#0.001;
        if(!dut.slow_lookup_fault || output_valid) $fatal(1,"missing metadata escaped first-word boundary");
      end else if(boundary==6) force dut.output_lookup_descriptor=70'b0;
      else force dut.event_last_missing=1'b1;
      @(posedge fft_clk);#0.001;
      if(boundary==6) begin
        if(!dut.output_descriptor_pending || dut.output_descriptor_valid || dut.output_request!==request_before)
          $fatal(1,"writer capture did not hold publication closed");
        @(negedge fft_clk);release dut.output_lookup_descriptor;
        @(posedge fft_clk);#0.001;
        if(!dut.output_descriptor_fault || dut.output_descriptor_valid)
          $fatal(1,"captured writer mismatch did not cancel publication authority");
      end
      @(negedge fft_clk);
      release dut.core_output_valid;release dut.core_status_valid;
      release dut.event_last_missing;release dut.output_lookup_descriptor;
      repeat(80) begin
        @(negedge fft_clk);
        if(dut.output_request!==request_before || dut.output_released_valid || dut.reader_release)
          $fatal(1,"fault allowed publication or descriptor release");
      end
      if(!fault || !dut.fast_fault || stress_releases!=0 ||
         (boundary!=5 && stress_reads!=0) || (boundary==5 && stress_reads!=512))
        $fatal(1,"fault quarantine/evidence mismatch boundary=%0d reads=%0d",boundary,stress_reads);
      $display("STAGED_FAULT_PASS boundary=%0d no_late_publication=1 releases=0 reads=%0d",boundary,stress_reads);
    end
  endtask
  integer block_index,word_index;
  task automatic writer_boundary(input integer boundary);
    reg request_before;
    begin
      stress_reset;stress_fixture=0;send_block(0);
      while(!dut.output_descriptor_pending) @(negedge fft_clk);
      request_before=dut.output_request;stress_fault_expected=1;
      if(boundary==0) force dut.event_last_missing=1'b1;
      else if(boundary==1) fft_resetn=0;
      else if(boundary==2) resetn=0;
      else force dut.output_descriptor_expected=70'b0;
      @(posedge fft_clk);#0.001;
      if(boundary==3 && (!dut.output_descriptor_fault || dut.output_descriptor_valid))
        $fatal(1,"held writer identity corruption was not rejected");
      @(negedge fft_clk);release dut.event_last_missing;release dut.output_descriptor_expected;
      if(boundary==1 || boundary==2) begin
        repeat(10) @(negedge fft_clk);
        resetn=1;fft_resetn=1;request_before=dut.output_request;
      end
      repeat(100) begin
        @(negedge fft_clk);
        if(dut.output_request!==request_before || dut.output_published_valid || dut.output_released_valid || dut.reader_release ||
           dut.output_replay_valid || dut.job_accept || dut.config_valid || dut.core_input_valid)
          $fatal(1,"pending writer validation escaped cancellation boundary=%0d",boundary);
      end
      if(stress_reads!=0 || stress_releases!=0 || ((boundary==0 || boundary==3) && !fault))
        $fatal(1,"writer cancellation evidence missing");
      $display("STAGED_WRITER_CASE_PASS boundary=%0d publications=0 releases=0",boundary);
    end
  endtask
  task automatic replay_boundary(input integer boundary);
    reg request_before;
    begin
      stress_reset;stress_fixture=0;send_block(0);
      while(!dut.output_replay_valid || !dut.output_replay_private_ready) @(negedge fft_clk);
      request_before=dut.output_request;stress_fault_expected=1;
      if(boundary==0) force dut.event_last_missing=1'b1;
      else if(boundary==1) force dut.product_bank_framing_fault_now=1'b1;
      else if(boundary==2) force dut.core_status_valid=1'b1;
      else if(boundary==3) fft_resetn=0;
      else resetn=0;
      #0.001;
      if(boundary<3 && (!dut.output_replay_valid || !dut.output_replay_private_ready || dut.output_replay_accept!==0))
        $fatal(1,"fault did not separate private replay from bank authorization");
      @(posedge fft_clk);#0.001;
      if(boundary<3 && (dut.output_control.phase!=4 || dut.output_request!==request_before || dut.output_published_valid))
        $fatal(1,"private replay step falsely became a publication");
      @(negedge fft_clk);
      release dut.event_last_missing;release dut.product_bank_framing_fault_now;release dut.core_status_valid;
      if(boundary>=3) begin
        repeat(10) @(negedge fft_clk);
        resetn=1;fft_resetn=1;request_before=dut.output_request;
      end
      repeat(100) begin
        @(negedge fft_clk);
        if(dut.output_request!==request_before || dut.output_published_valid || dut.output_released_valid || dut.reader_release ||
           dut.output_replay_valid || dut.job_accept || dut.config_valid || dut.core_input_valid)
          $fatal(1,"cancelled replay escaped to publication/release/reuse boundary=%0d",boundary);
      end
      if(stress_reads!=0 || stress_releases!=0 || (boundary<3 && !fault))
        $fatal(1,"replay cancellation evidence missing");
      $display("STAGED_REPLAY_CASE_PASS boundary=%0d private_step=%0d publications=0 releases=0",boundary,boundary<3);
    end
  endtask
  task automatic completion_boundary(input integer boundary);
    integer wanted_phase,stage;
    reg request_before;
    begin
      wanted_phase=(boundary<6 ? boundary/3 : boundary>=8 ? 1 : 0);
      stage=boundary<6 ? boundary%3 : 1;
      stress_reset;stress_fixture=0;send_block(0);
      if(stage==0)
        while(dut.next_inverse!=wanted_phase || !dut.completion_request || dut.completion_gate.snapshot_valid) @(negedge fft_clk);
      else if(stage==1)
        while(dut.next_inverse!=wanted_phase || !dut.completion_permit) @(negedge fft_clk);
      else
        while(dut.next_inverse!=wanted_phase || !dut.completion_receipt) @(negedge fft_clk);
      request_before=dut.output_request;stress_fault_expected=1;
      if(boundary==6) force dut.product_bank_metadata=70'b0;
      else if(boundary==7) force dut.product_bank_position=9'd1;
      else if(boundary==8) resetn=0;
      else if(boundary==9) fft_resetn=0;
      else force dut.core_status_valid=1'b1;
      @(posedge fft_clk);#0.001;
      @(negedge fft_clk);
      release dut.product_bank_metadata;release dut.product_bank_position;release dut.core_status_valid;
      if(boundary>=8) begin
        repeat(10) @(negedge fft_clk);
        resetn=1;fft_resetn=1;request_before=dut.output_request;
      end
      repeat(100) begin
        @(negedge fft_clk);
        if(dut.job_accept || dut.input_job_start || dut.config_valid || dut.core_input_valid ||
           dut.completion_permit || dut.completion_receipt || dut.output_request!==request_before ||
           dut.output_released_valid || dut.reader_release)
          $fatal(1,"cancelled completion escaped to core reuse/publication boundary=%0d",boundary);
      end
      if(stress_reads!=0 || stress_releases!=0 || (boundary<8 && !fault))
        $fatal(1,"completion cancellation evidence missing");
      $display("STAGED_COMPLETION_CASE_PASS boundary=%0d phase=%0d reuse_after_cancel=0 publications=0 releases=0",boundary,wanted_phase);
    end
  endtask
  initial begin
    $readmemh("samples_ci16.mem",samples);$readmemh("forward_q17.mem",forwards);
    $readmemh("product_q17.mem",products);$readmemh("inverse_q17.mem",inverses);
    $readmemh("forward_exponents.mem",fe);$readmemh("inverse_exponents.mem",ie);
    log_file=$fopen("staged_words.csv","w");
    $fdisplay(log_file,"context,stream,job,position,data,exponent");
    for(mode=0;mode<6;mode=mode+1) begin
      @(negedge fft_clk);resetn=0;fft_resetn=0;input_valid=0;
      repeat(10) @(negedge fft_clk);
      jobs=0;reads=0;publications=0;releases=0;inputs=0;raws=0;statuses=0;frames=0;
      forward_words=0;product_words=0;inverse_words=0;old_request=0;
      overlap_inputs=0;overlap_reads=0;last_forward=-1;max_service=0;
      context_start_base=mode==4 ? 64'ha5a5a5a5a5a5a000 : mode==5 ? 64'h5a5a5a5a5a5a5000 : 64'd1000;
      resetn=1;fft_resetn=1;
      for(block_index=0;block_index<3;block_index=block_index+1) begin
        for(word_index=0;word_index<512;word_index=word_index+1) begin
          @(negedge clk);input_valid=1;input_position=word_index;input_last=word_index==511;
          input_block_start=context_start_base+block_index*447;
          input_data={samples[block_index*447+word_index][31:16],2'b0,samples[block_index*447+word_index][15:0],2'b0};
          @(posedge clk);while(input_ready!==1) @(posedge clk);
          #0.001;
        end
        @(negedge clk);input_valid=0;
      end
      while(reads!=1536 || !dut.retained_reusable) @(negedge fft_clk);
      repeat(20) @(negedge fft_clk);
      if(jobs!=6 || inputs!=3072 || raws!=3072 || statuses!=6 || frames!=6 ||
         forward_words!=1536 || product_words!=1536 || inverse_words!=1536 ||
         publications!=3 || releases!=3 || overlap_inputs==0 || (mode<2 && overlap_reads==0))
        $fatal(1,"complete staged FFT inventory mismatch");
      if(mode!=3 && max_service>5215) $fatal(1,"175 MHz coarse service deadline");
      $display("STAGED_FFT_CONTEXT_PASS mode=%0d reads=1536 inputs=3072 raw=3072 status=6 publications=3 releases=3 max_service=%0d overlap_inputs=%0d overlap_reads=%0d",mode,max_service,overlap_inputs,overlap_reads);
      if(mode>=4) $display("STAGED_TIMESTAMP_PASS mode=%0d base=%016h words=1536",mode,context_start_base);
    end
    $fclose(log_file);$display("STAGED_FFT_PASS contexts=6 no_continuous_or_physical_claim");
    stress=1;reset_stopped_reader(1);reset_stopped_reader(2);
    for(mode=0;mode<7;mode=mode+1) fault_boundary(mode);
    for(mode=0;mode<6;mode=mode+1) admission_boundary(mode);
    $display("STAGED_ADMISSION_PASS cases=6 partition_checked=1");
    for(mode=0;mode<10;mode=mode+1) completion_boundary(mode);
    $display("STAGED_COMPLETION_PASS cases=10 partition_checked=1");
    for(mode=0;mode<5;mode=mode+1) replay_boundary(mode);
    $display("STAGED_REPLAY_PASS cases=5 actual_authorization_checked=1");
    for(mode=0;mode<4;mode=mode+1) writer_boundary(mode);
    $display("STAGED_WRITER_PASS cases=4 pending_fenced=1");
    if(handover_admissions<36 || handover_completions<36) $fatal(1,"missing registered handover coverage");
    $display("STAGED_HANDOVER_PASS admissions=%0d completions=%0d reset_cases=2 fault_cases=7",handover_admissions,handover_completions);
    $finish;
  end
  initial begin #3000000;$fatal(1,"staged FFT absolute deadline");end
endmodule
