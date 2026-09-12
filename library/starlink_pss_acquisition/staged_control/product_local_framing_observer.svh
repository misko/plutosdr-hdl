  integer local_framing_checks=0,local_framing_publications=0,local_framing_rejections=0;
  reg local_expected_request,local_previous_request;
  // Execute the original bank's nested procedural publication predicate.
  // Compare the actual request register, not the candidate's permit alone.
  always @(posedge fft_clk) begin
    local_previous_request=dut.product_bank.request_toggle;
    local_expected_request=local_previous_request;
    if(!dut.product_bank.in_running) local_expected_request=0;
    else if(dut.product_bank.input_accept) begin
      if(!dut.product_bank.input_framing_valid) begin end
      else if(dut.product_bank.write_position==9'd511) begin
        if(dut.product_commit_authorized) local_expected_request=!local_previous_request;
      end
    end
    if(dut.fast_running) begin
      if(dut.external_fault_now !== (dut.product_nonlocal_fault_now || dut.product_bank_framing_fault_now))
        $fatal(1,"local framing changed global fault identity");
      if(dut.product_bank.input_accept===1 && dut.product_bank.input_framing_valid!==1)
        local_framing_rejections=local_framing_rejections+1;
    end
    #0.001;
    if(dut.product_bank.request_toggle!==local_expected_request)
      $fatal(1,"local framing changed actual bank publication");
    if(dut.fast_running)begin
      local_framing_checks=local_framing_checks+1;
      if(local_expected_request!==local_previous_request)
        local_framing_publications=local_framing_publications+1;
    end
  end
  task automatic report_product_local_framing;
    $display("PRODUCT_LOCAL_FRAMING_PASS checks=%0d publications=%0d local_rejections=%0d actual_request_exact=1",
      local_framing_checks,local_framing_publications,local_framing_rejections);
  endtask

