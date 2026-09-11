// Fault injection on the actual FFT integration, not a substitute FFT model.
  integer aux_reads=0,aux_releases=0,aux_case=0,aux_side=0;
  integer aux_products=0,aux_replays=0,aux_stalls=0;
  reg aux_fault_expected=0,aux_ready=1;
  reg [35:0] aux_held_data;
  reg [8:0] aux_held_position;
  always @(posedge clk)if(auxiliary_active && resetn && fft_resetn)begin
    if(output_valid && output_ready)begin
      if(aux_fault_expected || aux_reads>=512 || output_data!==inverses[aux_reads] ||
         output_position!==9'(aux_reads) || output_last!==(aux_reads==511) ||
         output_metadata!=={1'b1,64'd1000,fe[0],ie[0]})$fatal(1,"auxiliary stale/numerically wrong output");
      aux_reads=aux_reads+1;
    end
  end
  always @(posedge fft_clk)if(auxiliary_active && dut.fast_running)begin
    if(!aux_fault_expected && (dut.any_fast_fault!==0 || fault!==0))
      $fatal(1,"auxiliary healthy fault case=%0d state=%0d guard=%h bank=%b",aux_case,dut.state,dut.owners[0].result_guard.faults_now,dut.forward_buffer_fault);
    if(dut.reader_release)begin
      if(aux_fault_expected || aux_reads!=512)$fatal(1,"auxiliary early reader release");
      aux_releases=aux_releases+1;
    end
    if(!aux_fault_expected && dut.forward_buffer_valid && dut.forward_buffer_read_ready)begin
      if(aux_replays>=512 || dut.forward_buffer_data!==forwards[aux_replays] ||
         dut.forward_buffer_position!==9'(aux_replays))$fatal(1,"auxiliary replay arithmetic");
      aux_replays=aux_replays+1;
    end
    if(!aux_fault_expected && dut.product_valid && dut.product_stage_ready)begin
      if(aux_products>=512 || {dut.product_q,dut.product_i}!==products[aux_products])$fatal(1,"auxiliary product arithmetic");
      aux_products=aux_products+1;
    end
  end
  task automatic aux_reset;
    begin
      @(negedge fft_clk);resetn=0;fft_resetn=0;input_valid=0;
      release dut.core_output_user;release dut.core_output_valid;release dut.core_status_valid;
      release dut.core_status_data;release dut.input_fault_now;release dut.forward_buffer_position;
      release dut.final_fence;release dut.kernel_ready;
      repeat(12)@(negedge fft_clk);
      aux_reads=0;aux_releases=0;aux_products=0;aux_replays=0;aux_fault_expected=0;aux_ready=1;
      resetn=1;fft_resetn=1;
      while(!dut.fast_running || !dut.slow_running)@(negedge fft_clk);
    end
  endtask
  task automatic aux_send;
    integer n;
    begin
      for(n=0;n<512;n=n+1)begin
        @(negedge clk);input_valid=1;input_position=n;input_last=n==511;input_block_start=1000;
        input_data={samples[n][31:16],2'b0,samples[n][15:0],2'b0};
        @(posedge clk);while(input_ready!==1)@(posedge clk);#0.001;
      end
      @(negedge clk);input_valid=0;
    end
  endtask
  task automatic aux_finish;
    begin
      while(aux_reads!=512 || !dut.retained_reusable)@(negedge fft_clk);
      repeat(30)@(negedge fft_clk);
      if(aux_releases!=1 || aux_products!=512 || aux_replays!=512 || fault!==0)
        $fatal(1,"auxiliary fresh inventory");
    end
  endtask
  task automatic aux_recover;
    begin aux_reset;aux_send;aux_finish;end
  endtask
  task automatic aux_fault(input integer which);
    begin
      aux_reset;aux_ready=0;aux_send;
      if(which<2)while(!dut.core_output_valid || dut.core_output_user[8:0]!=100)@(negedge fft_clk);
      else if(which==2)while(!dut.guard_commit[0])@(negedge fft_clk);
      else if(which==4)begin
        while(!dut.core_output_valid || !dut.core_output_last)@(negedge fft_clk);
        @(negedge fft_clk);
      end else while(!dut.forward_buffer_valid || dut.forward_buffer_position!=100)@(negedge fft_clk);
      aux_fault_expected=1;
      case(which)
        0:force dut.core_output_user[8:0]=9'd0;
        1:force dut.core_output_user[20:16]=5'd31;
        2:force dut.input_fault_now=1'b1;
        3:force dut.forward_buffer_position=9'd0;
        4:force dut.core_output_valid=1'b1;
        5:force dut.core_status_valid=1'b1;
      endcase
      @(negedge fft_clk);
      release dut.core_output_user;release dut.input_fault_now;release dut.forward_buffer_position;
      release dut.core_output_valid;release dut.core_status_valid;
      repeat(100)begin
        @(negedge fft_clk);
        if(dut.output_request!==0 || dut.product_bank_valid || dut.job_accept || dut.completion_accept || output_valid)
          $fatal(1,"fault allowed publication/reuse case=%0d",which);
      end
      if(fault!==1 || aux_reads!=0 || aux_releases!=0)$fatal(1,"fault not quarantined case=%0d",which);
      aux_recover;
      $display("BUFFERED_FAULT_PASS case=%0d rejected_publications=0 fresh_reads=512 fresh_releases=1",which);
    end
  endtask
  task automatic aux_reset_boundary(input integer boundary,side);
    begin
      aux_reset;aux_ready=0;
      if(boundary==1)force dut.final_fence=1'b0;
      aux_send;
      if(boundary==0)while(!dut.core_output_valid || dut.core_output_user[8:0]!=100)@(negedge fft_clk);
      else if(boundary==1)while(dut.forward_buffer.write_count!=512)@(negedge fft_clk);
      else begin
        while(!dut.forward_buffer_valid || dut.forward_buffer_position!=(boundary==2?100:511))@(negedge fft_clk);
        force dut.kernel_ready=1'b0;
        repeat(7)@(negedge fft_clk);
      end
      if(side==0)resetn=0;else fft_resetn=0;
      #0.001;
      if(dut.fast_running!==0 || output_valid!==0)$fatal(1,"reset did not immediately fence output");
      repeat(12)@(negedge fft_clk);
      release dut.final_fence;release dut.kernel_ready;
      aux_reads=0;aux_releases=0;aux_products=0;aux_replays=0;
      resetn=1;fft_resetn=1;
      repeat(100)begin
        @(negedge fft_clk);
        if(output_valid || dut.output_request!==0 || dut.job_accept || dut.forward_buffer_valid || dut.forward_buffer_owned)
          $fatal(1,"reset retained stale ownership boundary=%0d side=%0d",boundary,side);
      end
      aux_recover;
      $display("BUFFERED_RESET_PASS boundary=%0d side=%0d stale_outputs=0 fresh_reads=512 fresh_releases=1",boundary,side);
    end
  endtask
  task automatic aux_delay(input integer which);
    integer n;
    begin
      aux_reset;
      if(which==0)force dut.core_status_valid=1'b0;
      aux_send;
      if(which==0)begin
        while(dut.forward_buffer.write_count!=512)@(negedge fft_clk);
        repeat(17)begin
          @(negedge fft_clk);
          if(dut.forward_buffer_valid || dut.forward_committed || dut.product_bank_valid)
            $fatal(1,"unqualified status allowed replay");
        end
        force dut.core_status_data={3'b0,fe[0]};force dut.core_status_valid=1'b1;
        @(negedge fft_clk);release dut.core_status_valid;release dut.core_status_data;
      end else begin
        while(!dut.forward_buffer_valid || dut.forward_buffer_position!=100)@(negedge fft_clk);
        force dut.kernel_ready=1'b0;
        aux_held_data=dut.forward_buffer_data;aux_held_position=dut.forward_buffer_position;
        for(n=0;n<128;n=n+1)begin
          @(negedge fft_clk);
          if(!dut.forward_buffer_valid || dut.forward_buffer_data!==aux_held_data ||
             dut.forward_buffer_position!==aux_held_position || dut.product_bank_valid)
            $fatal(1,"elastic replay changed while stalled");
        end
        release dut.kernel_ready;
      end
      aux_finish;
      $display("BUFFERED_DELAY_PASS case=%0d fresh_reads=512 replay=512 products=512",which);
    end
  endtask
  task automatic run_buffered_auxiliary;
    begin
      auxiliary_active=1;
      for(aux_case=0;aux_case<6;aux_case=aux_case+1)aux_fault(aux_case);
      for(aux_case=0;aux_case<4;aux_case=aux_case+1)
        for(aux_side=0;aux_side<2;aux_side=aux_side+1)aux_reset_boundary(aux_case,aux_side);
      for(aux_case=0;aux_case<2;aux_case=aux_case+1)aux_delay(aux_case);
      $display("BUFFERED_AUX_PASS faults=6 resets=8 delays=2 fresh_recovery=1 actual_fft=1");
    end
  endtask
