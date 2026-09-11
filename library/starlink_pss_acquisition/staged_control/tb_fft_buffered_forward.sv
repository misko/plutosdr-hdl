// Actual generated FFT + sealed forward RAM + real kernel/product/inverse path.
// Separate from reference-topology equivalence campaigns. No RF/board claim.
`timescale 1ns/1ps
`default_nettype none
module tb;
  reg clk=0,fft_clk=0,resetn=0,fft_resetn=0;
  always #2.857143 fft_clk=~fft_clk;
  initial begin #1.3;forever #5 clk=~clk;end
  reg input_valid=0,input_last=0,output_ready=0;
  reg [35:0] input_data=0;
  reg [8:0] input_position=0;
  reg [63:0] input_block_start=0,context_start_base=1000;
  wire input_ready,output_valid,output_last,fault;
  wire [35:0] output_data;
  wire [8:0] output_position;
  wire [74:0] output_metadata;
  starlink_pss_fft_buffered_forward_impl #(.REGISTERED_SCHEDULING(1),
    .BOUNDARY_ROUND_SAT(1),.REGISTER_OPERANDS(1),.LOCAL_FIRST_ADMISSION(1),
    .PRIVATE_DESCRIPTOR_OFFER(1),.CLOSED_INPUT_CUTOVER(1),
    .INPUT_OFFER_FAULT_SUMMARY(1),.CONTEXTUAL_DESTINATION_SUMMARY(1),
    .REPLAY_QUIET_PUBLICATION(1),.SPLIT_PREFLIGHT_IDENTITY(1),
    .MONOTONIC_OUTER_RESET(1),.PARALLEL_KERNEL_READY(1),.PRIVATE_QUARANTINE_OFFER(1)) dut(.*);
  reg [31:0] samples[0:1405];
  reg [35:0] forwards[0:1535],products[0:1535],inverses[0:1535];
  reg [4:0] fe[0:2],ie[0:2];
  integer mode=0,fast_cycles=0,slow_cycles=0,log_file;
  integer jobs=0,reads=0,inputs=0,raws=0,statuses=0,frames=0;
  integer fixture=0,phase=0,input_count=0,raw_position=0;
  integer product_words=0,inverse_words=0,replay_words=0;
  integer reservations=0,seals=0,done_count=0,forward_closes=0;
  integer publications=0,releases=0,captured=0,replayed=0;
  integer last_forward=-1,max_service=0,stall_cycles=0;
  integer block_index,word_index;
  reg sealed=0,old_request=0,stalled=0;
  reg [120:0] held_output;
  reg [35:0] expected;
  task automatic log_word(input string stream,input integer job,position,
                          input [47:0] data,input [9:0] exponent);
    $fdisplay(log_file,"%0d,%s,%0d,%0d,%012h,%03h",mode,stream,job,position,data,exponent);
  endtask
  always @(negedge clk) begin
    slow_cycles=slow_cycles+1;
    output_ready=mode%2==0 || slow_cycles%17<9;
  end
  always @(posedge clk) begin
    if(resetn && fft_resetn) begin
      if(stalled && (!output_valid || held_output!=={output_data,output_position,output_last,output_metadata}))
        $fatal(1,"buffered stalled output changed");
      stalled=output_valid && !output_ready;
      held_output={output_data,output_position,output_last,output_metadata};
      if(stalled)stall_cycles=stall_cycles+1;
      if(output_valid && output_ready) begin
        if(reads>=1536 || output_position!==9'(reads%512) || output_last!==(reads%512==511) ||
           output_data!==inverses[reads] ||
           output_metadata!=={1'b1,64'(context_start_base+(reads/512)*447),fe[reads/512],ie[reads/512]})
          $fatal(1,"buffered native output mismatch read=%0d",reads);
        log_word("read",reads/512,reads%512,{12'b0,output_data},output_metadata[9:0]);
        reads=reads+1;
      end
    end else stalled=0;
  end
  always @(posedge fft_clk) begin
    fast_cycles=fast_cycles+1;
    if(dut.fast_running) begin
      if(fault!==0 || dut.any_fast_fault!==0)
        $fatal(1,"buffered health cycle=%0d state=%0d F=%h I=%h bank=%b preflight=%h captured=%0d sealed=%b replay=%0d",
          fast_cycles,dut.state,dut.owners[0].result_guard.faults_now,
          dut.owners[1].result_guard.faults_now,dut.forward_buffer_fault,dut.preflight_events_now,captured,sealed,replayed);
      if(dut.forward_buffer_reserve && dut.forward_buffer_reserve_ready) begin
        if(dut.forward_buffer_owned || reservations!=forward_closes)
          $fatal(1,"buffer reservation before previous product ownership closed");
        reservations=reservations+1;captured=0;replayed=0;sealed=0;
      end
      if(dut.job_accept) begin
        if(dut.engine_metadata[68:5]<context_start_base || (dut.engine_metadata[68:5]-context_start_base)%447!=0)
          $fatal(1,"buffered admission timestamp");
        fixture=(dut.engine_metadata[68:5]-context_start_base)/447;phase=dut.next_inverse;
        if(fixture>2 || phase!==jobs[0])$fatal(1,"buffered job order");
        if(!phase && (!dut.forward_buffer_owned || reservations!=forward_closes+1))
          $fatal(1,"forward starts without reserved RAM");
        if(phase && (forward_closes!=fixture+1 || replayed!=512))
          $fatal(1,"inverse starts before real product acknowledgment");
        jobs=jobs+1;raw_position=0;input_count=0;
        if(!phase) begin
          if(last_forward>=0 && fast_cycles-last_forward>max_service)max_service=fast_cycles-last_forward;
          last_forward=fast_cycles;
        end
      end
      if(dut.core_input_valid && dut.core_input_ready) begin
        expected=phase ? products[fixture*512+input_count] :
          {samples[fixture*447+input_count][31:16],2'b0,samples[fixture*447+input_count][15:0],2'b0};
        if(input_count>=512 || dut.core_input_data!=={6'b0,expected[35:18],6'b0,expected[17:0]} ||
           dut.core_input_last!==(input_count==511))$fatal(1,"buffered core input");
        if(phase)log_word("inputI",fixture,input_count,dut.core_input_data,0);
        else log_word("inputF",fixture,input_count,dut.core_input_data,0);
        inputs=inputs+1;input_count=input_count+1;
      end
      if(dut.event_frame)frames=frames+1;
      if(dut.core_status_valid) begin
        if(raw_position!=2 || dut.core_status_data!=={3'b0,(phase?ie[fixture]:fe[fixture])})
          $fatal(1,"buffered core status");
        statuses=statuses+1;
      end
      if(dut.core_output_valid) begin
        expected=phase?inverses[fixture*512+raw_position]:forwards[fixture*512+raw_position];
        if(raw_position>=512 || input_count!=512 ||
           dut.core_output_data!=={{6{expected[35]}},expected[35:18],{6{expected[17]}},expected[17:0]} ||
           dut.core_output_user!=={3'b0,(phase?ie[fixture]:fe[fixture]),7'b0,9'(raw_position)} ||
           dut.core_output_last!==(raw_position==511))$fatal(1,"buffered raw FFT");
        if(phase)log_word("rawI",fixture,raw_position,dut.core_output_data,{5'b0,ie[fixture]});
        else begin
          log_word("rawF",fixture,raw_position,dut.core_output_data,{5'b0,fe[fixture]});
          if(!dut.forward_buffer_capture_ready || !dut.forward_buffer_owned || sealed)
            $fatal(1,"realtime forward output not captured");
          captured=captured+1;
        end
        raw_position=raw_position+1;raws=raws+1;
      end
      if(dut.guard_commit[0]) begin
        if(captured!=512 || sealed || !dut.forward_buffer_owned)
          $fatal(1,"seal without exactly one full owned capture");
        sealed=1;seals=seals+1;
      end
      if(dut.forward_buffer_valid) begin
        if(!sealed || captured!=512 || !dut.forward_buffer_owned)
          $fatal(1,"unsealed or unowned replay");
        if(dut.forward_buffer_data!==forwards[replay_words] ||
           dut.forward_buffer_position!==9'(replayed) || dut.forward_buffer_last!==(replayed==511) ||
           dut.forward_buffer_exponent!==fe[replay_words/512] ||
           dut.forward_buffer_descriptor!=={1'b0,64'(context_start_base+(replay_words/512)*447),5'b0})
          $fatal(1,"forward replay numerical/identity");
        if(dut.forward_buffer_read_ready)begin replay_words=replay_words+1;replayed=replayed+1;end
      end
      if(dut.forward_buffer_done) begin
        if(replayed!=512)$fatal(1,"buffer completion before final consume");
        done_count=done_count+1;
      end
      if(dut.completion_accept && !dut.held_phase) begin
        if(replayed!=512 || !dut.product_bank_valid || !dut.forward_buffer_owned || done_count!=forward_closes+1)
          $fatal(1,"forward close before sealed replay and product ownership");
        forward_closes=forward_closes+1;
      end
      if(dut.product_valid && dut.product_stage_ready) begin
        if(product_words>=1536 || {dut.product_q,dut.product_i}!==products[product_words] ||
           dut.product_position!==9'(product_words%512))$fatal(1,"buffered product");
        log_word("product",product_words/512,product_words%512,{12'b0,dut.product_q,dut.product_i},{5'b0,dut.product_exponent});
        product_words=product_words+1;
      end
      if(dut.guard_private_out[1] && dut.output_bank_ready) begin
        if(inverse_words>=1536 || dut.guard_return_data[1]!==inverses[inverse_words] ||
           dut.guard_return_position[1]!==9'(inverse_words%512))$fatal(1,"buffered private inverse");
        log_word("privateI",inverse_words/512,inverse_words%512,{12'b0,dut.guard_return_data[1]},dut.guard_return_metadata[1][9:0]);
        inverse_words=inverse_words+1;
      end
      if(dut.output_request!==old_request)begin old_request=dut.output_request;publications=publications+1;end
      if(dut.reader_release)begin
        if(reads!=(releases+1)*512 || dut.output_request!==dut.output_ack_sync)$fatal(1,"early reader release");
        releases=releases+1;
      end
    end
  end
  initial begin
    $readmemh("samples_ci16.mem",samples);$readmemh("forward_q17.mem",forwards);
    $readmemh("product_q17.mem",products);$readmemh("inverse_q17.mem",inverses);
    $readmemh("forward_exponents.mem",fe);$readmemh("inverse_exponents.mem",ie);
    log_file=$fopen("buffered_words.csv","w");
    $fdisplay(log_file,"context,stream,job,position,data,exponent");
    for(mode=0;mode<6;mode=mode+1)begin
      @(negedge fft_clk);resetn=0;fft_resetn=0;input_valid=0;
      repeat(10)@(negedge fft_clk);
      jobs=0;reads=0;inputs=0;raws=0;statuses=0;frames=0;
      product_words=0;inverse_words=0;replay_words=0;reservations=0;seals=0;
      done_count=0;forward_closes=0;publications=0;releases=0;old_request=0;
      captured=0;replayed=0;sealed=0;last_forward=-1;max_service=0;stall_cycles=0;
      context_start_base=mode>=4 ? 64'h5a5a5a5a5a5a5000 : mode>=2 ? 64'ha5a5a5a5a5a5a000 : 64'd1000;
      resetn=1;fft_resetn=1;
      for(block_index=0;block_index<3;block_index=block_index+1)begin
        for(word_index=0;word_index<512;word_index=word_index+1)begin
          @(negedge clk);input_valid=1;input_position=word_index;input_last=word_index==511;
          input_block_start=context_start_base+block_index*447;
          input_data={samples[block_index*447+word_index][31:16],2'b0,samples[block_index*447+word_index][15:0],2'b0};
          @(posedge clk);while(input_ready!==1)@(posedge clk);
          #0.001;
        end
        @(negedge clk);input_valid=0;
      end
      while(reads!=1536 || !dut.retained_reusable)@(negedge fft_clk);
      repeat(20)@(negedge fft_clk);
      if(jobs!=6 || inputs!=3072 || raws!=3072 || statuses!=6 || frames!=6 ||
         product_words!=1536 || inverse_words!=1536 || replay_words!=1536 ||
         reservations!=3 || seals!=3 || done_count!=3 || forward_closes!=3 || publications!=3 || releases!=3)
        $fatal(1,"buffered complete inventory");
      if(max_service>5215)$fatal(1,"buffered coarse service deadline cycles=%0d",max_service);
      if(mode%2==1 && stall_cycles<500)$fatal(1,"buffered output stall coverage");
      $display("BUFFERED_CONTEXT_PASS mode=%0d reads=1536 replay=1536 reservations=3 seals=3 closes=3 max_service=%0d stalls=%0d base=%016h",
        mode,max_service,stall_cycles,context_start_base);
    end
    $fclose(log_file);
    $display("BUFFERED_FFT_PASS contexts=6 seven_stream_words=64512 no_board_or_continuous_claim");$finish;
  end
  initial begin #3000000;$fatal(1,"buffered actual FFT timeout state=%0d capture=%0d replay=%0d seals=%0d fault=%b",dut.state,captured,replayed,seals,fault);end
endmodule
`default_nettype wire
