// SPDX-License-Identifier: GPL-2.0
// Real generated XFFT required. Exact frozen forward/product/inverse vectors.
// Changed control latency is measured, not assumed equal to the old controller.
`timescale 1ns/1fs
module tb;
  reg clk=0,fft_clk=0,resetn=0,fft_resetn=0;
  always #2.857143 fft_clk=~fft_clk;
  initial begin #1.3;forever #5 clk=~clk;end
  reg input_valid=0,input_last=0,output_ready=0;
  reg [35:0] input_data=0;
  reg [8:0] input_position=0;
  reg [63:0] input_block_start=0;
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
  task automatic log_word(input string stream,input integer block_id,input integer position,
                input [47:0] data,input [9:0] exponent);
    $fdisplay(log_file,"%0d,%s,%0d,%0d,%012h,%03h",mode,stream,block_id,position,data,exponent);
  endtask
  always @(negedge clk) begin
    slow_cycles=slow_cycles+1;
    output_ready=mode==0 ? 1 : mode==1 ? slow_cycles%17<13 :
      (dut.retained_published && fast_cycles-publication_cycle>(mode==2 ? 2200 : 9000));
  end
  always @(posedge clk) begin
    if(resetn && fft_resetn) begin
      if(stalled && output_valid && held_output!=={output_data,output_position,output_last,output_metadata})
        $fatal(1,"stalled output changed");
      stalled=output_valid && !output_ready;held_output={output_data,output_position,output_last,output_metadata};
      if(output_valid && output_ready) begin
        if(reads>=1536 || output_position!==9'(reads%512) || output_last!==(reads%512==511) ||
           output_data!==inverses[reads] ||
           output_metadata!=={1'b1,64'(1000+(reads/512)*447),fe[reads/512],ie[reads/512]} ||
           !dut.output_lookup_found || !dut.output_lookup_committed)
          $fatal(1,"native numerical/metadata output mismatch read=%0d",reads);
        log_word("read",reads/512,reads%512,{12'b0,output_data},output_metadata[9:0]);
        if(!dut.routed_inverse && dut.cutover.owner_open) overlap_reads=overlap_reads+1;
        reads=reads+1;
      end
    end else stalled=0;
  end
  always @(posedge fft_clk) begin
    fast_cycles=fast_cycles+1;
    if(dut.fast_running) begin
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
        if(dut.engine_metadata[68:5]<1000 || (dut.engine_metadata[68:5]-1000)%447!=0)
          $fatal(1,"admission timestamp mismatch");
        fixture=(dut.engine_metadata[68:5]-1000)/447;phase=dut.next_inverse;
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
  integer block_index,word_index;
  initial begin
    $readmemh("samples_ci16.mem",samples);$readmemh("forward_q17.mem",forwards);
    $readmemh("product_q17.mem",products);$readmemh("inverse_q17.mem",inverses);
    $readmemh("forward_exponents.mem",fe);$readmemh("inverse_exponents.mem",ie);
    log_file=$fopen("staged_words.csv","w");
    $fdisplay(log_file,"context,stream,job,position,data,exponent");
    for(mode=0;mode<4;mode=mode+1) begin
      @(negedge fft_clk);resetn=0;fft_resetn=0;input_valid=0;
      repeat(10) @(negedge fft_clk);
      jobs=0;reads=0;publications=0;releases=0;inputs=0;raws=0;statuses=0;frames=0;
      forward_words=0;product_words=0;inverse_words=0;old_request=0;
      overlap_inputs=0;overlap_reads=0;last_forward=-1;max_service=0;
      resetn=1;fft_resetn=1;
      for(block_index=0;block_index<3;block_index=block_index+1) begin
        for(word_index=0;word_index<512;word_index=word_index+1) begin
          @(negedge clk);input_valid=1;input_position=word_index;input_last=word_index==511;
          input_block_start=1000+block_index*447;
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
      if(mode<=2 && max_service>5215) $fatal(1,"175 MHz coarse service deadline");
      $display("STAGED_FFT_CONTEXT_PASS mode=%0d reads=1536 inputs=3072 raw=3072 status=6 publications=3 releases=3 max_service=%0d overlap_inputs=%0d overlap_reads=%0d",mode,max_service,overlap_inputs,overlap_reads);
    end
    $fclose(log_file);$display("STAGED_FFT_PASS contexts=4 no_continuous_or_physical_claim");$finish;
  end
  initial begin #3000000;$fatal(1,"staged FFT absolute deadline");end
endmodule
