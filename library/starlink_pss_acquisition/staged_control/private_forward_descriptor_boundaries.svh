  integer descriptor_boundary;
  task automatic private_forward_descriptor_boundary(input integer boundary);
    reg [69:0] offered_descriptor;
    begin
      aux_reset;aux_ready=0;aux_send;
      while(!dut.forward_buffer.reserve_valid || !dut.forward_buffer.reserve_ready)@(negedge fft_clk);
      if(dut.forward_buffer.fault || dut.forward_buffer.descriptor!==descriptor_reference.descriptor)
        $fatal(1,"descriptor boundary premise");
      aux_fault_expected=1;
      if(boundary==1)force dut.forward_buffer.seal_valid=1'b1;
      else if(boundary==2)force dut.forward_buffer.capture_valid=1'bx;
      else if(boundary==3)begin
        force dut.forward_buffer.seal_valid=1'bz;
        force dut.forward_buffer.reserve_descriptor={70{1'bx}};
      end else force dut.forward_buffer.capture_valid=1'b1;
      #0.001;
      offered_descriptor=dut.forward_buffer.reserve_descriptor;
      if(dut.forward_buffer.fault!==1 || dut.forward_buffer.reserve_ready!==1 ||
         dut.forward_buffer.output_valid!==0 || dut.product_commit_authorized!==0 || dut.output_replay_accept!==0)
        $fatal(1,"descriptor rejection/publication fence missing");
      @(posedge fft_clk);#0.001;
      if(dut.forward_buffer.descriptor!==offered_descriptor ||
         dut.forward_buffer.descriptor===descriptor_reference.descriptor ||
         dut.forward_buffer.fault_q!==1 || descriptor_reference.fault_q!==1 ||
         dut.product_owner_request!==0 || dut.output_request!==0)
        $fatal(1,"private descriptor delta not safely captured");
      @(negedge fft_clk);
      release dut.forward_buffer.capture_valid;release dut.forward_buffer.seal_valid;
      release dut.forward_buffer.reserve_descriptor;
      if(boundary>=4)begin
        if(boundary==4)resetn=0;else fft_resetn=0;
        repeat(12)@(negedge fft_clk);
        if(dut.forward_buffer.descriptor!==0 || descriptor_reference.descriptor!==0 ||
           dut.product_owner_request!==0 || dut.output_request!==0 || output_valid)
          $fatal(1,"private descriptor reset retained stale authority");
      end else begin
        repeat(12)@(negedge fft_clk);
        repeat(100)begin
          @(negedge fft_clk);
          if(fault!==1 || output_valid || aux_reads || aux_releases || dut.job_accept || dut.completion_accept ||
             dut.forward_buffer.reserve_ready || dut.forward_buffer.capture_ready)
            $fatal(1,"private descriptor quarantine escaped");
        end
      end
      aux_recover;
      $display("PRIVATE_DESCRIPTOR_BOUNDARY_PASS boundary=%0d fresh_reads=512 fresh_releases=1",boundary);
    end
  endtask
  task automatic run_private_descriptor_boundaries;
    begin
      for(descriptor_boundary=0;descriptor_boundary<6;descriptor_boundary=descriptor_boundary+1)
        private_forward_descriptor_boundary(descriptor_boundary);
      $display("PRIVATE_DESCRIPTOR_BOUNDARIES_PASS cases=6 rejected_reservation=1 private_delta=1 fresh_recovery=1");
    end
  endtask
