// Port the historical completion cancellation boundaries to the buffered top.
  integer local_boundary;
  task automatic local_completion_boundary(input integer boundary);
    integer wanted_phase,stage;
    reg request_before;
    begin
      wanted_phase=(boundary<6 ? boundary/3 : boundary>=8 ? 1 : 0);
      stage=boundary<6 ? boundary%3 : 1;
      aux_reset;aux_ready=0;aux_send;
      if(stage==0)
        while(dut.next_inverse!=wanted_phase || !dut.completion_request || dut.completion_gate.snapshot_valid)@(negedge fft_clk);
      else if(stage==1)
        while(dut.next_inverse!=wanted_phase || !dut.completion_permit)@(negedge fft_clk);
      else
        while(dut.next_inverse!=wanted_phase || !dut.completion_receipt)@(negedge fft_clk);
      request_before=dut.output_request;aux_fault_expected=1;
      if(boundary==6)force dut.product_bank_metadata=70'b0;
      else if(boundary==7)force dut.product_bank_position=9'd1;
      else if(boundary==8)resetn=0;
      else if(boundary==9)fft_resetn=0;
      else force dut.core_status_valid=1'b1;
      @(posedge fft_clk);#0.001;
      @(negedge fft_clk);
      release dut.product_bank_metadata;release dut.product_bank_position;release dut.core_status_valid;
      if(boundary>=8)begin
        repeat(10)@(negedge fft_clk);
        resetn=1;fft_resetn=1;request_before=dut.output_request;
      end
      repeat(100)begin
        @(negedge fft_clk);
        if(dut.job_accept || dut.input_job_start || dut.config_valid || dut.core_input_valid ||
           dut.completion_permit || dut.completion_receipt || dut.output_request!==request_before ||
           dut.output_released_valid || dut.reader_release)
          $fatal(1,"local completion cancellation escaped boundary=%0d",boundary);
      end
      if(aux_reads!=0 || aux_releases!=0 || (boundary<8 && !fault))
        $fatal(1,"local completion cancellation missing boundary=%0d",boundary);
      aux_recover;
      $display("LOCAL_COMPLETION_BOUNDARY_PASS boundary=%0d phase=%0d cancelled_reuse=0 fresh_reads=512 fresh_releases=1",boundary,wanted_phase);
    end
  endtask
  task automatic run_local_completion_boundaries;
    begin
      for(local_boundary=0;local_boundary<10;local_boundary=local_boundary+1)local_completion_boundary(local_boundary);
      $display("LOCAL_COMPLETION_BOUNDARIES_PASS cases=10 current_fault_fenced=1 fresh_recovery=1");
    end
  endtask
