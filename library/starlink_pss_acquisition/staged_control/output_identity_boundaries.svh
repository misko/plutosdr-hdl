// Actual-FFT faults at the new capture/certificate/publication boundary.
  integer output_boundary;
  reg [36:0] output_bad_metadata;
  task automatic output_identity_boundary(input integer boundary);
    begin
      aux_reset;aux_ready=0;aux_send;
      if(boundary==0)
        while(!dut.output_stage_offer_valid || dut.output_publication_busy ||
              dut.guard_return_position[1]!=100 || !dut.output_stage_ready)@(negedge fft_clk);
      else if(boundary==1)
        while(!dut.output_replay_valid || !dut.output_stage_ready)@(negedge fft_clk);
      else if(boundary==2)
        while(!dut.output_stage_valid || dut.output_stage_position!=100)@(negedge fft_clk);
      else if(boundary<7)
        while(!dut.output_stage_final_valid || !dut.output_replay_accept)@(negedge fft_clk);
      else
        while(dut.output_request!==1'b1)@(negedge fft_clk);
      aux_fault_expected=1;
      if(boundary<2)begin
        output_bad_metadata=dut.output_stage_offer_metadata^37'h10000;
        force dut.output_stage_offer_metadata=output_bad_metadata;
      end else if(boundary==2)force dut.output_stage_position=9'd1;
      else if(boundary==3)force dut.output_stage_last=1'b0;
      else if(boundary==4)force dut.core_status_valid=1'b1;
      else if(boundary==5 || boundary==7)resetn=0;
      else fft_resetn=0;
      #0.001;
      if(boundary>=5 && (dut.fast_running!==0 || output_valid!==0))
        $fatal(1,"output stage reset did not fence current output");
      @(posedge fft_clk);#0.001;@(negedge fft_clk);
      release dut.output_stage_offer_metadata;release dut.output_stage_position;
      release dut.output_stage_last;release dut.core_status_valid;
      if(boundary>=5)begin
        repeat(12)@(negedge fft_clk);resetn=1;fft_resetn=1;
      end
      repeat(100)begin
        @(negedge fft_clk);
        if(dut.output_request!==0 || output_valid || dut.job_accept || dut.output_released_valid || dut.reader_release)
          $fatal(1,"output identity cancellation escaped boundary=%0d",boundary);
      end
      if(aux_reads!=0 || aux_releases!=0 || (boundary<5 && fault!==1))
        $fatal(1,"output identity cancellation missing boundary=%0d",boundary);
      aux_recover;
      $display("OUTPUT_IDENTITY_BOUNDARY_PASS boundary=%0d cancelled_outputs=0 fresh_reads=512 fresh_releases=1",boundary);
    end
  endtask
  task automatic run_output_identity_boundaries;
    begin
      for(output_boundary=0;output_boundary<9;output_boundary=output_boundary+1)output_identity_boundary(output_boundary);
      $display("OUTPUT_IDENTITY_BOUNDARIES_PASS cases=9 current_publication_fenced=1 fresh_recovery=1");
    end
  endtask
