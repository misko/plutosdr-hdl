  integer product_fence_boundary;
  task automatic product_current_fence_boundary(input integer boundary);
    reg output_before,product_before;
    begin
      aux_reset;aux_ready=0;aux_send;
      while(!dut.staged_product_valid || !dut.staged_product_last || !dut.staged_product_ready)@(negedge fft_clk);
      if(dut.fast_fault || dut.result_fault || (|dut.local_fault_snapshot))$fatal(1,"product current fence premise");
      output_before=dut.output_request;product_before=dut.product_bank.owner_request;
      aux_fault_expected=1;
      if(boundary==1)force dut.core_output_valid=1'b1;
      else if(boundary==2)force dut.event_frame=1'b1;
      else if(boundary==3)force dut.input_job_start=1'b1;
      else begin force dut.core_status_valid=1'b1;force dut.core_status_data=8'h00;end
      #0.001;
      if(dut.fast_fault!==0 || dut.result_fault!==0 || dut.common_current_fault!==1 ||
         dut.product_commit_authorized!==0 || dut.output_replay_accept!==0)
        $fatal(1,"product current fault not fenced boundary=%0d",boundary);
      @(posedge fft_clk);#0.001;
      if(dut.output_request!==output_before || dut.product_bank.owner_request!==product_before ||
         dut.fast_fault!==0 || (|dut.local_fault_snapshot)!==1)
        $fatal(1,"product fault-edge ownership/latency boundary=%0d",boundary);
      @(negedge fft_clk);
      release dut.core_output_valid;release dut.event_frame;release dut.input_job_start;
      release dut.core_status_valid;release dut.core_status_data;
      if(boundary>=4)begin
        if(boundary==4)resetn=0;else fft_resetn=0;
        repeat(12)@(negedge fft_clk);
        if(dut.product_bank.owner_request!==0 || dut.output_request!==0 || output_valid)
          $fatal(1,"product pending-fault reset failed");
      end else begin
        repeat(8)begin
          @(negedge fft_clk);
          if(dut.output_request!==output_before || dut.product_bank.owner_request!==product_before ||
             dut.job_accept || dut.completion_accept || aux_reads || aux_releases)
            $fatal(1,"product cancellation ownership/reuse failure");
        end
        repeat(100)begin
          @(negedge fft_clk);
          if(fault!==1 || output_valid || aux_reads || aux_releases)$fatal(1,"product cancellation quarantine missing");
        end
      end
      aux_recover;
      $display("PRODUCT_CURRENT_FENCE_BOUNDARY_PASS boundary=%0d new_publications=0 fresh_reads=512 fresh_releases=1",boundary);
    end
  endtask
  task automatic run_product_current_fence_boundaries;
    begin
      for(product_fence_boundary=0;product_fence_boundary<6;product_fence_boundary=product_fence_boundary+1)
        product_current_fence_boundary(product_fence_boundary);
      $display("PRODUCT_CURRENT_FENCE_BOUNDARIES_PASS cases=6 current_fault_fenced=1 pending_reset=1 fresh_recovery=1");
    end
  endtask
