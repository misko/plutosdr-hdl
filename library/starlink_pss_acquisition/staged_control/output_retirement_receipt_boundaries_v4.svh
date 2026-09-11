  integer out_retirement_boundary;
  task automatic output_retirement_boundary(input integer boundary);
    reg request_before;
    reg [115:0] held_word;
    begin
      aux_reset;aux_ready=boundary==0;aux_send;
      if(boundary==0 || boundary==4 || boundary==5)begin
        while(!dut.output_stage_valid || !dut.output_stage_last || !dut.output_stage_consume)@(negedge fft_clk);
      end else begin
        while(!dut.output_published_receipt)@(negedge fft_clk);
        if(!dut.output_identity_stage.full || !dut.output_stage_last)$fatal(1,"missing private receipt boundary");
      end
      request_before=dut.output_request;
      if(boundary==0)begin
        force dut.output_stage_final_valid=1'b0;
        held_word={dut.output_stage_data,dut.output_stage_position,dut.output_stage_last,dut.output_stage_metadata};
        repeat(128)begin
          @(negedge fft_clk);
          if(!dut.output_identity_stage.full || dut.output_retire_ready || dut.output_published_receipt ||
             dut.output_request!==request_before || aux_reads ||
             {dut.output_stage_data,dut.output_stage_position,dut.output_stage_last,dut.output_stage_metadata}!==held_word)
            $fatal(1,"unpublished final was lost while permission delayed");
        end
        release dut.output_stage_final_valid;aux_finish;
      end else if(boundary<3)begin
        aux_fault_expected=1;
        if(boundary==1)resetn=0;else fft_resetn=0;
        repeat(12)@(negedge fft_clk);
        if(dut.output_identity_stage.full!==0 || dut.output_request!==0 || dut.output_ack_sync!==0 || output_valid)
          $fatal(1,"reset retained private final/ownership");
        aux_recover;
      end else begin
        aux_fault_expected=1;
        if(boundary==3)begin force dut.core_status_valid=1'b1;force dut.core_status_data=8'h00;end
        else if(boundary==4)force dut.output_bank.input_metadata_certified=1'b0;
        else force dut.output_replay_accept=1'b0;
        #0.001;
        if(boundary==4 && dut.output_bank_framing_fault_now!==1)$fatal(1,"bad certificate not detected");
        @(posedge fft_clk);#0.001;
        if(dut.output_request!==request_before)
          $fatal(1,"retirement boundary created publication");
        @(negedge fft_clk);
        release dut.core_status_valid;release dut.core_status_data;release dut.output_bank.input_metadata_certified;release dut.output_replay_accept;
        repeat(12)@(negedge fft_clk);
        repeat(100)begin
          @(negedge fft_clk);
          if(fault!==1 || output_valid || aux_reads || aux_releases || dut.job_accept || dut.completion_accept)
            $fatal(1,"retirement boundary quarantine failed");
        end
        aux_recover;
      end
      $display("OUTPUT_RETIREMENT_BOUNDARY_PASS boundary=%0d fresh_reads=512 fresh_releases=1",boundary);
    end
  endtask
  task automatic run_output_retirement_boundaries;
    begin
      for(out_retirement_boundary=0;out_retirement_boundary<6;out_retirement_boundary=out_retirement_boundary+1)
        output_retirement_boundary(out_retirement_boundary);
      $display("OUTPUT_RETIREMENT_BOUNDARIES_PASS cases=6 delayed_publication=1 pending_reset=1 checked_receipt=1");
    end
  endtask
