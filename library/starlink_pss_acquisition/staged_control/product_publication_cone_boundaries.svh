  integer publication_boundary_index;
  reg [69:0] publication_bad_metadata;
  task automatic publication_cone_boundary(input integer boundary);
    reg request_before;
    integer bad_bit;
    begin
      aux_reset;aux_ready=0;aux_send;
      while(!(dut.product_bank_valid && dut.forward_committed && !dut.next_inverse &&
              dut.forward_handoff_identity))@(negedge fft_clk);
      if(dut.product_bank_position!==0 || dut.product_bank_last!==0 || dut.output_request!==0)
        $fatal(1,"missing clean initial handoff");
      request_before=dut.product_bank.request_toggle;
      aux_fault_expected=1;
      if(boundary<6)begin
        bad_bit=boundary==5?69:15*boundary;
        publication_bad_metadata=dut.product_bank_metadata ^ (70'b1<<bad_bit);
        force dut.product_bank_metadata=publication_bad_metadata;
      end else if(boundary==6)force dut.product_bank_position=9'd1;
      else force dut.product_bank_last=1'b1;
      #0.001;
      if(dut.handoff_fault_now!==1 || dut.forward_handoff_ack!==0 || dut.job_accept!==0 ||
         dut.completion_accept!==0 || dut.product_commit_authorized!==0 || dut.output_replay_accept!==0)
        $fatal(1,"bad handoff did not fence current progress");
      if(boundary<6 && dut.handoff_identity_fault !== (5'b1<<(boundary==5?4:boundary)))
        $fatal(1,"bad metadata did not select exact comparison group");
      repeat(12)@(negedge fft_clk);
      release dut.product_bank_metadata;release dut.product_bank_position;release dut.product_bank_last;
      repeat(100)begin
        @(negedge fft_clk);
        if(fault!==1 || output_valid || aux_reads || aux_releases || dut.job_accept ||
           dut.completion_accept || dut.output_request!==0 ||
           dut.product_bank.request_toggle!==request_before)
          $fatal(1,"bad handoff escaped quarantine or republished");
      end
      aux_recover;
      $display("PUBLICATION_CONE_BOUNDARY_PASS boundary=%0d fresh_reads=512 fresh_releases=1",boundary);
    end
  endtask
  task automatic run_publication_cone_boundaries;
    begin
      for(publication_boundary_index=0;publication_boundary_index<8;publication_boundary_index=publication_boundary_index+1)
        publication_cone_boundary(publication_boundary_index);
      $display("PUBLICATION_CONE_BOUNDARIES_PASS cases=8 metadata_groups=5 tail_bit=1 position=1 last=1");
    end
  endtask
