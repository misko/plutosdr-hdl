  integer private_status_checks=0,private_status_edges=0,private_status_completions=0,private_status_guard_delays=0;
  reg private_status_pending=0,private_status_running,private_status_current,private_status_old;
  reg private_status_output_before,private_status_product_before;
  always @(posedge fft_clk)begin
    private_status_running=dut.fast_running;
    private_status_current=dut.forward_buffer_fault===1'b1;
    private_status_old=dut.forward_buffer_private_fault===1'b1;
    private_status_output_before=dut.output_request;
    private_status_product_before=dut.product_bank.owner_request;
    if(!dut.fast_running)private_status_pending=0;
    else begin
      private_status_checks=private_status_checks+1;
      if(private_status_current)begin
        if(dut.forward_buffer_valid!==0 || dut.product_commit_authorized!==0 || dut.output_replay_accept!==0)
          $fatal(1,"private bank status lost current publication veto");
        if(!private_status_old)begin
          private_status_edges=private_status_edges+1;
          if(dut.completion_accept)private_status_completions=private_status_completions+1;
        end
      end
      if(private_status_old && (dut.registered_quarantine!==1 || dut.job_accept || dut.completion_accept))
        $fatal(1,"private bank status allowed reuse after capture");
    end
    #0.001;
    if(private_status_running && dut.fast_running)begin
      if(private_status_current)begin
        if(dut.forward_buffer_private_fault!==1 || dut.registered_quarantine!==1 ||
           dut.output_request!==private_status_output_before ||
           dut.product_bank.owner_request!==private_status_product_before)
          $fatal(1,"private bank status capture/ownership failure");
        if(!private_status_old && dut.result_fault===0)private_status_guard_delays=private_status_guard_delays+1;
      end
      if(private_status_pending && dut.fast_fault!==1)$fatal(1,"private status global fault bound");
      private_status_pending=private_status_old;
    end else private_status_pending=0;
  end
  task automatic report_forward_private_status;
    begin
      if(private_status_checks<10000)$fatal(1,"vacuous private status observer");
      $display("FORWARD_PRIVATE_STATUS_PASS checks=%0d new_fault_edges=%0d private_completions=%0d guard_delays=%0d current_publication_fenced=1 registered_reuse_fenced=1 bounded_global_fault=1",
        private_status_checks,private_status_edges,private_status_completions,private_status_guard_delays);
    end
  endtask
