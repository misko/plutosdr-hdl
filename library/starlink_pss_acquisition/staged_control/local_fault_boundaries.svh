  integer local_boundary;
  task automatic local_fault_boundary(input integer boundary);
    reg output_before,product_before;
    begin
      aux_reset;aux_ready=0;aux_send;
      if(boundary<2)while(!dut.staged_product_valid || !dut.staged_product_last ||
          !dut.staged_product_ready)@(negedge fft_clk);
      else if(boundary==2 || boundary==5)while(!dut.output_replay_accept)@(negedge fft_clk);
      else while(dut.next_inverse!=(boundary==4) || !dut.completion_permit)@(negedge fft_clk);
      if(dut.fast_fault || dut.result_fault || (|dut.local_fault_snapshot))$fatal(1,"local fault boundary premise");
      output_before=dut.output_request;product_before=dut.product_bank.owner_request;
      aux_fault_expected=1;
      if(boundary==1)begin force dut.core_status_valid=1'b1;force dut.core_status_data=8'h80;end
      else if(boundary==5)force dut.retained_fault_now=1'b1;
      else force dut.input_fault_now=1'b1;
      #0.001;
      if(dut.fast_fault!==0 || (|dut.sticky_fault_sources)!==1 || dut.output_replay_accept!==0 ||
         dut.product_commit_authorized!==0)$fatal(1,"local fault immediate veto");
      @(posedge fft_clk);#0.001;
      if(dut.fast_fault!==0 || (|dut.local_fault_snapshot)!==1)$fatal(1,"local fault latency not exercised");
      @(negedge fft_clk);
      release dut.input_fault_now;release dut.retained_fault_now;
      release dut.core_status_valid;release dut.core_status_data;
      repeat(8)begin
        @(negedge fft_clk);
        if(dut.output_request!==output_before || dut.product_bank.owner_request!==product_before ||
           dut.job_accept || dut.completion_accept || aux_reads || aux_releases)
          $fatal(1,"local fault boundary allowed new ownership or reuse");
      end
      repeat(100)begin
        @(negedge fft_clk);
        if(fault!==1 || output_valid || aux_reads || aux_releases)$fatal(1,"local fault quarantine missing");
      end
      aux_recover;
      $display("LOCAL_FAULT_BOUNDARY_PASS boundary=%0d new_publications=0 fresh_reads=512 fresh_releases=1",boundary);
    end
  endtask
  task automatic run_local_fault_boundaries;
    begin
      for(local_boundary=0;local_boundary<6;local_boundary=local_boundary+1)local_fault_boundary(local_boundary);
      $display("LOCAL_FAULT_BOUNDARIES_PASS cases=6 delayed_fault_exercised=1 fresh_recovery=1");
    end
  endtask
