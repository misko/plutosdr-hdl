  integer local_checks=0,local_delays=0,local_pending_checks=0;
  reg local_pending=0,local_sample_running,local_expected_fault;
  reg [32:0] local_expected_snapshot;
  reg local_output_before,local_product_before;
  always @(posedge fft_clk)begin
    local_sample_running=dut.fast_running;
    local_expected_snapshot=dut.admission_reject_expanded;
    local_expected_fault=dut.fast_fault || dut.result_fault || (|dut.local_fault_snapshot);
    local_output_before=dut.output_request;local_product_before=dut.product_bank.owner_request;
    if(!dut.fast_running)local_pending=0;
    else begin
      local_checks=local_checks+1;
      if(dut.local_fault_profile!==1)$fatal(1,"local fault profile not selected");
      if((|dut.admission_reject_expanded)!==(|dut.sticky_fault_sources))
        $fatal(1,"local fault source reduction differs from original");
      if(local_pending)begin
        local_pending_checks=local_pending_checks+1;
        if(dut.product_commit_authorized!==0 || dut.output_replay_accept!==0 ||
           dut.job_accept || dut.completion_accept)$fatal(1,"local fault latency escaped public fence");
      end
      if((|dut.sticky_fault_sources)===1 && dut.fast_fault===0 && dut.result_fault===0 &&
         (|dut.local_fault_snapshot)===0)local_delays=local_delays+1;
    end
    #0.001;
    if(local_sample_running && dut.fast_running)begin
      if(dut.local_fault_snapshot!==local_expected_snapshot || dut.fast_fault!==local_expected_fault)
        $fatal(1,"local fault pipeline is not exact sampled arithmetic");
      if(local_pending && (dut.fast_fault!==1 || dut.output_request!==local_output_before ||
         dut.product_bank.owner_request!==local_product_before))
        $fatal(1,"local fault bound or ownership failure");
      local_pending=(|local_expected_snapshot)===1;
    end else local_pending=0;
  end
  task automatic report_local_fault;
    begin
      if(local_checks<10000)$fatal(1,"vacuous local fault observer");
      $display("LOCAL_FAULT_PASS checks=%0d delayed_edges=%0d pending_checks=%0d exact_sources=1 bounded_abort=1 publication_fenced=1",
        local_checks,local_delays,local_pending_checks);
    end
  endtask
