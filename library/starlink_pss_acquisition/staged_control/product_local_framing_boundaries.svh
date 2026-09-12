  integer local_framing_boundary_index;
  task automatic product_local_framing_boundary(input integer boundary);
    reg product_before,output_before;
    begin
      aux_reset;aux_ready=0;aux_send;
      while(!(dut.staged_product_valid && dut.staged_product_last && dut.staged_product_ready))
        @(negedge fft_clk);
      product_before=dut.product_bank.owner_request;output_before=dut.output_request;
      aux_fault_expected=1;
      if(boundary==1)force dut.product_bank.input_metadata_certified=1'b0;
      else if(boundary==2)force dut.product_bank.input_last=1'b0;
      else force dut.product_bank.input_position=9'd510;
      #0.001;
      if(dut.product_bank.input_framing_valid!==0 || dut.product_bank_framing_fault_now!==1 ||
         dut.product_commit_authorized!==0 || dut.output_replay_accept!==0)
        $fatal(1,"local framing boundary lacks immediate original fence");
      @(posedge fft_clk);#0.001;
      if(dut.product_bank.owner_request!==product_before || dut.output_request!==output_before ||
         dut.product_bank.input_fault!==1)
        $fatal(1,"local framing rejection changed ownership");
      @(negedge fft_clk);
      release dut.product_bank.input_position;
      release dut.product_bank.input_last;
      release dut.product_bank.input_metadata_certified;
      if(boundary>=4)begin
        if(boundary==4)resetn=0;else fft_resetn=0;
        repeat(12)@(negedge fft_clk);
        if(dut.product_bank.owner_request!==0 || dut.output_request!==0 || output_valid)
          $fatal(1,"local framing reset retained ownership");
      end else begin
        repeat(12)begin
          @(negedge fft_clk);
          if(dut.product_bank.owner_request!==product_before || dut.output_request!==output_before ||
             output_valid || aux_reads || aux_releases || dut.job_accept || dut.completion_accept)
            $fatal(1,"local framing early quarantine failure");
        end
        repeat(100)begin
          @(negedge fft_clk);
          if(fault!==1 || output_valid || aux_reads || aux_releases)
            $fatal(1,"local framing quarantine missing");
        end
      end
      aux_recover;
      $display("PRODUCT_LOCAL_FRAMING_BOUNDARY_PASS boundary=%0d fresh_reads=512 fresh_releases=1",boundary);
    end
  endtask
  task automatic run_product_local_framing_boundaries;
    begin
      for(local_framing_boundary_index=0;local_framing_boundary_index<6;local_framing_boundary_index=local_framing_boundary_index+1)
        product_local_framing_boundary(local_framing_boundary_index);
      $display("PRODUCT_LOCAL_FRAMING_BOUNDARIES_PASS cases=6 local_checks=1 both_resets=1");
    end
  endtask

