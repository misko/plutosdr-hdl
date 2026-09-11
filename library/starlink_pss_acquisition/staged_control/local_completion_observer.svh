// Read-only certificate reference, clocked with the actual integrated DUT.
  wire completion_reference_permit,completion_reference_valid;
  wire [41:0] completion_reference_good;
  starlink_pss_admission_certificate #(.CHECKS(42)) completion_reference (
    .clk(fft_clk),.resetn(dut.fast_running),.request(dut.completion_request),
    .quarantine(dut.registered_quarantine),.consume(dut.completion_accept),
    .checks_good(dut.completion_checks),.permit(completion_reference_permit),
    .snapshot_valid(completion_reference_valid),.snapshot_good(completion_reference_good)
  );
  wire [41:0] completion_candidate_expanded = {
    dut.completion_gate.snapshot_good[35:26],6'b111111,dut.completion_gate.snapshot_good[25:0]};
  integer local_completion_checks=0,local_completion_owned=0,local_completion_permits=0;
  integer local_completion_private_differences=0;
  always @(negedge fft_clk)begin
    if(dut.fast_running)begin
      if({dut.completion_permit,dut.completion_gate.snapshot_valid,dut.completion_gate.consumed} !==
         {completion_reference_permit,completion_reference_valid,completion_reference.consumed})
        $fatal(1,"local completion changed original authority");
      if(dut.completion_request===1'b1 &&
         (dut.state!==4'd7 || dut.completion_checks[31:26]!==6'b111111))
        $fatal(1,"completion preflight exclusion premise violated");
      if(dut.completion_gate.snapshot_valid===1'b1)begin
        if(completion_candidate_expanded!==completion_reference_good)
          $fatal(1,"local valid completion facts differ");
        local_completion_owned=local_completion_owned+1;
      end else if(completion_candidate_expanded!==completion_reference_good)
        local_completion_private_differences=local_completion_private_differences+1;
      if(dut.completion_permit)local_completion_permits=local_completion_permits+1;
      local_completion_checks=local_completion_checks+1;
    end
  end
  task automatic report_local_completion;
    begin
      if(local_completion_checks<10000 || local_completion_owned<36 ||
         local_completion_permits<36 || local_completion_private_differences<100)
        $fatal(1,"vacuous local completion authority comparison");
      $display("LOCAL_COMPLETION_PASS checks=%0d owned=%0d permits=%0d private_differences=%0d original_authority_exact=1 public_veto_unchanged=1",
        local_completion_checks,local_completion_owned,local_completion_permits,local_completion_private_differences);
    end
  endtask
