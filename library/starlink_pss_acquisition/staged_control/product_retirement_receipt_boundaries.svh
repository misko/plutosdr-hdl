  integer retirement_boundary;
  task automatic product_retirement_boundary(input integer boundary);
    reg request_before;
    reg [115:0] held_word;
    begin
      aux_reset;aux_ready=boundary==0;aux_send;
      if(boundary==0 || boundary==4)begin
        while(!dut.staged_product_valid || !dut.staged_product_last || !dut.staged_product_ready)@(negedge fft_clk);
      end else begin
        while(!dut.product_published_receipt)@(negedge fft_clk);
        if(!dut.product_identity_stage.full || !dut.staged_product_last)$fatal(1,"missing private receipt boundary");
      end
      request_before=dut.product_owner_request;
      if(boundary==0)begin
        force dut.product_commit_authorized=1'b0;
        held_word={dut.staged_product_data,dut.staged_product_position,dut.staged_product_last,dut.staged_product_metadata};
        repeat(128)begin
          @(negedge fft_clk);
          if(!dut.product_identity_stage.full || dut.product_retire_ready || dut.product_published_receipt ||
             dut.product_owner_request!==request_before || aux_reads ||
             {dut.staged_product_data,dut.staged_product_position,dut.staged_product_last,dut.staged_product_metadata}!==held_word)
            $fatal(1,"unpublished final was lost while permission delayed");
        end
        release dut.product_commit_authorized;aux_finish;
      end else if(boundary<3)begin
        aux_fault_expected=1;
        if(boundary==1)resetn=0;else fft_resetn=0;
        repeat(12)@(negedge fft_clk);
        if(dut.product_identity_stage.full!==0 || dut.product_owner_request!==0 || dut.product_owner_ack_sync!==0 || output_valid)
          $fatal(1,"reset retained private final/ownership");
        aux_recover;
      end else begin
        aux_fault_expected=1;
        if(boundary==3)begin force dut.core_status_valid=1'b1;force dut.core_status_data=8'h00;end
        else force dut.product_bank.input_metadata_certified=1'b0;
        #0.001;
        if(boundary==4 && dut.product_bank_framing_fault_now!==1)$fatal(1,"bad certificate not detected");
        @(posedge fft_clk);#0.001;
        if(dut.product_owner_request!==request_before || dut.output_request!==0)
          $fatal(1,"retirement boundary created publication");
        @(negedge fft_clk);
        release dut.core_status_valid;release dut.core_status_data;release dut.product_bank.input_metadata_certified;
        repeat(12)@(negedge fft_clk);
        repeat(100)begin
          @(negedge fft_clk);
          if(fault!==1 || output_valid || aux_reads || aux_releases || dut.job_accept || dut.completion_accept)
            $fatal(1,"retirement boundary quarantine failed");
        end
        aux_recover;
      end
      $display("PRODUCT_RETIREMENT_BOUNDARY_PASS boundary=%0d fresh_reads=512 fresh_releases=1",boundary);
    end
  endtask
  task automatic run_product_retirement_boundaries;
    begin
      for(retirement_boundary=0;retirement_boundary<5;retirement_boundary=retirement_boundary+1)
        product_retirement_boundary(retirement_boundary);
      $display("PRODUCT_RETIREMENT_BOUNDARIES_PASS cases=5 delayed_publication=1 pending_reset=1 checked_receipt=1");
    end
  endtask
