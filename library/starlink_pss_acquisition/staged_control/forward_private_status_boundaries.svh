  integer private_status_boundary;
  task automatic forward_private_status_boundary(input integer boundary);
    reg output_before,product_before;
    begin
      aux_reset;aux_ready=0;aux_send;
      if(boundary<3 || boundary>=9)begin
        while(!dut.core_output_valid || dut.core_output_user[8:0]!=(boundary==0?0:boundary==2?511:100))@(negedge fft_clk);
      end else if(boundary==3)while(!dut.guard_commit[0])@(negedge fft_clk);
      else if(boundary==4)while(!dut.forward_buffer_valid || dut.forward_buffer_position!=100)@(negedge fft_clk);
      else if(boundary==5)while(!dut.staged_product_valid || !dut.staged_product_last || !dut.staged_product_ready)@(negedge fft_clk);
      else if(boundary==6)while(!dut.output_replay_accept)@(negedge fft_clk);
      else while(dut.next_inverse!=(boundary==8) || !dut.completion_permit)@(negedge fft_clk);
      if(dut.fast_fault || dut.forward_buffer_fault || dut.forward_buffer_private_fault)$fatal(1,"private status boundary premise");
      output_before=dut.output_request;product_before=dut.product_bank.owner_request;aux_fault_expected=1;
      if(boundary<3 || boundary>=9)force dut.forward_buffer.capture_descriptor=70'h1;
      else if(boundary==3)force dut.forward_buffer.reserve_valid=1'bx;
      else if(boundary==5)force dut.forward_buffer.capture_valid=1'b1;
      else force dut.forward_buffer.seal_valid=1'b1;
      #0.001;
      if(dut.forward_buffer_fault!==1 || dut.forward_buffer_private_fault!==0 ||
         dut.forward_buffer_valid!==0 || dut.product_commit_authorized!==0 || dut.output_replay_accept!==0)
        $fatal(1,"private status current boundary veto case=%0d",boundary);
      @(posedge fft_clk);#0.001;
      if(dut.forward_buffer_private_fault!==1 || dut.registered_quarantine!==1 ||
         dut.output_request!==output_before || dut.product_bank.owner_request!==product_before)
        $fatal(1,"private status boundary capture case=%0d",boundary);
      @(negedge fft_clk);
      release dut.forward_buffer.capture_descriptor;release dut.forward_buffer.reserve_valid;
      release dut.forward_buffer.capture_valid;release dut.forward_buffer.seal_valid;
      if(boundary>=9)begin
        if(boundary==9)resetn=0;else fft_resetn=0;
        repeat(12)@(negedge fft_clk);
        if(dut.forward_buffer_private_fault!==0 || dut.output_request!==0 || dut.product_bank.owner_request!==0 || output_valid)
          $fatal(1,"private status pending reset leaked");
      end else begin
        repeat(12)begin
          @(negedge fft_clk);
          if(dut.output_request!==output_before || dut.product_bank.owner_request!==product_before ||
             dut.job_accept || dut.completion_accept || aux_reads || aux_releases)
            $fatal(1,"private status delay leaked ownership/reuse");
        end
        repeat(100)begin
          @(negedge fft_clk);
          if(fault!==1 || output_valid || aux_reads || aux_releases)$fatal(1,"private status quarantine missing");
        end
      end
      aux_recover;
      $display("FORWARD_PRIVATE_STATUS_BOUNDARY_PASS boundary=%0d new_publications=0 fresh_reads=512 fresh_releases=1",boundary);
    end
  endtask
  task automatic run_forward_private_status_boundaries;
    begin
      for(private_status_boundary=0;private_status_boundary<11;private_status_boundary=private_status_boundary+1)
        forward_private_status_boundary(private_status_boundary);
      $display("FORWARD_PRIVATE_STATUS_BOUNDARIES_PASS cases=11 private_delta_exercised=1 fresh_recovery=1");
    end
  endtask
