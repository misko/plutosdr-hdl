  integer private_replay_boundary_index;
  task automatic private_replay_sequence_boundary(input integer boundary);
    integer position_target,kind,expected_index;
    reg product_before,output_before;
    begin
      aux_reset;aux_ready=0;aux_send;
      position_target=boundary>=9?511:boundary/3==0?0:boundary/3==1?100:511;
      kind=boundary>=9?0:boundary%3;
      while(!(dut.forward_buffer_valid && dut.kernel_ready && dut.forward_buffer_position==position_target))
        @(negedge fft_clk);
      product_before=dut.product_bank.owner_request;output_before=dut.output_request;
      expected_index=dut.joiner.kernel_rom.expected_bin_index;
      if(expected_index!=position_target)$fatal(1,"private replay boundary ordinal");
      aux_fault_expected=1;
      if(kind==0)force dut.forward_buffer.capture_valid=1'b1;
      else if(kind==1)force dut.forward_buffer.seal_valid=1'b1;
      else force dut.forward_buffer.reserve_valid=1'bx;
      #0.001;
      if(dut.forward_buffer_fault!==1 || dut.joiner.kernel_rom.input_accept!==0 ||
         dut.joiner.kernel_rom.private_sequence_accept!==1 ||
         dut.product_commit_authorized!==0 || dut.output_replay_accept!==0)
        $fatal(1,"private replay boundary did not separate private progress/public veto");
      @(posedge fft_clk);#0.001;
      if(dut.joiner.kernel_rom.expected_bin_index!==9'((expected_index+1)%512) ||
         dut.forward_buffer_private_fault!==1 || dut.forward_buffer_private_replay_valid!==0 ||
         dut.product_bank.owner_request!==product_before || dut.output_request!==output_before)
        $fatal(1,"private replay boundary post-edge quarantine");
      if(position_target==511 &&
         (dut.joiner.kernel_rom.have_previous_block!==1 ||
          dut.joiner.kernel_rom.expected_next_block_start!==64'd1447 ||
          dut.joiner.kernel_rom.input_block_complete_pulse!==0))
        $fatal(1,"private final bookkeeping became public completion");
      @(negedge fft_clk);
      release dut.forward_buffer.capture_valid;release dut.forward_buffer.seal_valid;release dut.forward_buffer.reserve_valid;
      if(boundary>=9)begin
        if(boundary==9)resetn=0;else fft_resetn=0;
        repeat(12)@(negedge fft_clk);
        if(dut.joiner.kernel_rom.expected_bin_index!==0 || dut.joiner.kernel_rom.have_previous_block!==0 ||
           dut.joiner.kernel_rom.expected_next_block_start!==0 || output_valid)
          $fatal(1,"reset retained private replay history");
      end else begin
        $display("PRIVATE_REPLAY_PENDING_FAULT boundary=%0d slow_fault=%b local_fault=%b quarantine=%b",boundary,fault,dut.forward_buffer_private_fault,dut.registered_quarantine);
        // Fault reporting crosses two slow-clock flops. Ownership/progress
        // must already be fenced during that reporting interval.
        repeat(12)begin
          @(negedge fft_clk);
          if(dut.forward_buffer_private_fault!==1 || dut.registered_quarantine!==1 ||
             output_valid || aux_reads || aux_releases || dut.job_accept || dut.completion_accept ||
             dut.product_bank.owner_request!==product_before || dut.output_request!==output_before)
            $fatal(1,"private replay early quarantine failed");
        end
        repeat(100)begin
          @(negedge fft_clk);
          if(fault!==1 || output_valid || aux_reads || aux_releases || dut.job_accept || dut.completion_accept ||
             dut.product_bank.owner_request!==product_before || dut.output_request!==output_before)
            $fatal(1,"private replay boundary escaped quarantine");
        end
      end
      aux_recover;
      $display("PRIVATE_REPLAY_SEQUENCE_BOUNDARY_PASS boundary=%0d fresh_reads=512 fresh_releases=1",boundary);
    end
  endtask
  task automatic run_private_replay_sequence_boundaries;
    begin
      for(private_replay_boundary_index=0;private_replay_boundary_index<11;private_replay_boundary_index=private_replay_boundary_index+1)
        private_replay_sequence_boundary(private_replay_boundary_index);
      $display("PRIVATE_REPLAY_SEQUENCE_BOUNDARIES_PASS cases=11 first_mid_last=1 current_veto=1 both_resets=1");
    end
  endtask
