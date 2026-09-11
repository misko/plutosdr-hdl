  integer abort_checks=0,abort_fault_edges=0,abort_private_captures=0,abort_private_writes=0;
  reg abort_request_before,abort_product_before,abort_expected_latch;
  always @(posedge fft_clk)begin
    abort_expected_latch=dut.fast_running && dut.result_fault===1'b1;
    abort_request_before=dut.output_request;abort_product_before=dut.product_bank.owner_request;
    if(dut.fast_running)begin
      abort_checks=abort_checks+1;
      if(abort_expected_latch)begin
        if(dut.product_commit_authorized!==0 || dut.output_replay_accept!==0 ||
           dut.job_accept || dut.completion_accept)
          $fatal(1,"guard fault did not fence current publication/reuse");
        abort_fault_edges=abort_fault_edges+1;
        if(!dut.fast_fault && dut.forward_buffer.capture_take)abort_private_captures=abort_private_captures+1;
        if(!dut.fast_fault && dut.output_bank.input_accept)abort_private_writes=abort_private_writes+1;
      end
    end
    #0.001;
    if(abort_expected_latch && dut.fast_running)begin
      if(dut.fast_fault!==1 || dut.output_request!==abort_request_before ||
         dut.product_bank.owner_request!==abort_product_before)
        $fatal(1,"guard fault escaped global latch or changed ownership");
    end
  end
  task automatic report_registered_abort;
    begin
      if(abort_checks<10000)$fatal(1,"vacuous abort observer");
      $display("REGISTERED_ABORT_PASS checks=%0d fault_edges=%0d private_captures=%0d private_writes=%0d current_publication_fenced=1 next_edge_global_abort=1",
        abort_checks,abort_fault_edges,abort_private_captures,abort_private_writes);
    end
  endtask
