  wire old_admission_request=dut.CERTIFIED_ADMISSION && dut.job_valid &&
    dut.guard_capacity[dut.next_inverse] && dut.cutover_admission_capacity &&
    (!dut.next_inverse || dut.inverse_descriptor_live);
  wire old_admission_permit;
  starlink_pss_admission_certificate #(.CHECKS(36),.PRIVATE_FACT_CAPTURE(1)) old_admission (
    .clk(fft_clk),.resetn(dut.fast_running),.request(old_admission_request),
    .quarantine(dut.registered_quarantine),.consume(dut.job_accept),
    .checks_good(dut.admission_checks),.permit(old_admission_permit),
    .snapshot_valid(),.snapshot_good()
  );
  integer retry_checks=0,retry_bad=0,retry_grants=0,retry_waits=0;
  integer retry_request_grants=0;
  reg retry_holding=0;
  reg [71:0] retry_identity;
  wire old_job_accept=dut.job_valid && old_admission_permit && dut.guard_ready[dut.next_inverse];
  task automatic check_retry_admission;
    begin
      if(dut.fast_running===1)begin
        retry_checks=retry_checks+1;
        if(dut.job_accept!==old_job_accept)$fatal(1,"retry admission differs from original current-capacity certificate");
        if(dut.admission_request===1 && dut.admission_gate.snapshot_valid===1 &&
           dut.admission_gate.sampled_good===0)retry_bad=retry_bad+1;
        if(dut.job_accept===1 && (dut.guard_capacity[dut.next_inverse]!==1 ||
           dut.cutover_admission_capacity!==1 ||
           (dut.next_inverse===1 && dut.inverse_descriptor_live!==1)))
          $fatal(1,"accepted job lacks current owned capacity");
      end
    end
  endtask
  always @(posedge fft_clk)begin
    check_retry_admission;
    if(!dut.fast_running || !dut.admission_request)begin
      retry_holding=0;retry_request_grants=0;
    end else begin
      if(!retry_holding)begin
        retry_holding=1;retry_identity={dut.engine_metadata,dut.held_phase,dut.held_lease};
      end else if(retry_identity!=={dut.engine_metadata,dut.held_phase,dut.held_lease})
        if(dut.preparation_fault_now!==1 && dut.registered_quarantine!==1)
          $fatal(1,"held request changed identity without current fault");
      if(dut.job_accept)begin
        retry_grants=retry_grants+1;retry_request_grants=retry_request_grants+1;
        if(retry_request_grants!=1)$fatal(1,"held job admitted twice");
      end
      if(!old_admission_request)retry_waits=retry_waits+1;
    end
    #0.001;check_retry_admission;
  end
  task automatic report_retry_admission;
    begin
      if(retry_checks<10000 || retry_grants<36)$fatal(1,"vacuous retry admission proof");
      $display("RETRY_ADMISSION_PASS checks=%0d grants=%0d rejected_snapshots=%0d capacity_waits=%0d original_accept_exact=1 held_identity=1 once_per_request=1",retry_checks,retry_grants,retry_bad,retry_waits);
    end
  endtask
