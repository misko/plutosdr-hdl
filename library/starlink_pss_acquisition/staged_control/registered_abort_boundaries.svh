  integer abort_boundary;
  task automatic registered_abort_boundary(input integer boundary);
    reg old_request;
    begin
      aux_reset;aux_ready=0;aux_send;
      if(boundary==0)while(!dut.core_output_valid || dut.core_output_user[8:0]!=100)@(negedge fft_clk);
      else if(boundary==1)while(!dut.forward_buffer_valid || dut.forward_buffer_position!=100)@(negedge fft_clk);
      else if(boundary==2)while(!dut.output_stage_valid || dut.output_stage_position!=100)@(negedge fft_clk);
      else if(boundary==3)while(!dut.output_replay_accept)@(negedge fft_clk);
      else while(dut.next_inverse!=(boundary==5) || !dut.completion_permit)@(negedge fft_clk);
      if(dut.fast_fault || dut.result_fault)$fatal(1,"direct guard fault premise");
      old_request=dut.output_request;aux_fault_expected=1;
      if(boundary<2 || boundary==4)force dut.owners[0].result_guard.fault_reasons=8'h04;
      else force dut.owners[1].result_guard.fault_reasons=8'h04;
      #0.001;
      if(dut.result_fault!==1 || dut.fast_fault!==0 || dut.product_commit_authorized!==0 || dut.output_replay_accept!==0)
        $fatal(1,"direct guard fault current-edge veto missing");
      @(posedge fft_clk);#0.001;
      if(dut.fast_fault!==1 || dut.output_request!==old_request)$fatal(1,"direct fault latch/publication boundary");
      @(negedge fft_clk);
      release dut.owners[0].result_guard.fault_reasons;release dut.owners[1].result_guard.fault_reasons;
      // A previously published good block can remain visible until the
      // existing fast-to-slow fault synchronizer propagates. Reader is held.
      repeat(8)begin
        @(negedge fft_clk);
        if(dut.output_request!==old_request || dut.job_accept || dut.completion_accept || aux_reads)
          $fatal(1,"new work escaped during fault CDC propagation");
      end
      repeat(100)begin
        @(negedge fft_clk);
        if(dut.output_request!==old_request || output_valid || dut.job_accept || dut.completion_accept ||
           dut.reader_release || dut.output_released_valid)$fatal(1,"guard fault leaked cancelled work");
      end
      if(fault!==1 || aux_reads!=0 || aux_releases!=0)$fatal(1,"guard fault quarantine evidence missing");
      aux_recover;
      $display("REGISTERED_ABORT_BOUNDARY_PASS boundary=%0d new_publications=0 fresh_reads=512 fresh_releases=1",boundary);
    end
  endtask
  task automatic run_registered_abort_boundaries;
    begin
      for(abort_boundary=0;abort_boundary<6;abort_boundary=abort_boundary+1)registered_abort_boundary(abort_boundary);
      if(abort_private_captures<1 || abort_private_writes<1)$fatal(1,"private fault-edge allowance not exercised");
      $display("REGISTERED_ABORT_BOUNDARIES_PASS cases=6 private_delta_exercised=1 fresh_recovery=1");
    end
  endtask
