  // Same-input original guards: every output and all private state stay exact.
  generate for(genvar owner=0;owner<2;owner=owner+1)begin : shared_guard_reference
  starlink_pss_result_guard_owner_view #(
    .CERTIFIED_PRIVATE_ADMISSION(1),
    .PRIVATE_ACK_RETIREMENT(owner==1),
    .PRIVATE_QUARANTINE_OFFER(owner==1),
    .USE_PRIVATE_DESCRIPTOR_OFFER(1),
    .ENABLE_OFFERED_FAULT_SUMMARY(1),
    .REQUIRE_KNOWN_COMPLETED_INPUT(1),
    .USE_PHASE_INPUT_FAULT(0),
    .USE_COMPLETED_INPUT_FAULT(1),
    .USE_PREFLIGHT_REASON_ONLY(1),
    .USE_FORWARD_RETIREMENT(1)
  ) original (
    .clk(dut.owners[owner].result_guard.clk),
    .resetn(dut.owners[owner].result_guard.resetn),
    .job_valid(dut.owners[owner].result_guard.job_valid),
    .private_descriptor_offer(dut.owners[owner].result_guard.private_descriptor_offer),
    .job_ready(),
    .admission_capacity(),
    .job_descriptor(dut.owners[owner].result_guard.job_descriptor),
    .input_bank_reserved(dut.owners[owner].result_guard.input_bank_reserved),
    .output_bank_reserved(dut.owners[owner].result_guard.output_bank_reserved),
    .certified_input_beat(dut.owners[owner].result_guard.certified_input_beat),
    .certified_input_complete(dut.owners[owner].result_guard.certified_input_complete),
    .offered_input_beat(dut.owners[owner].result_guard.offered_input_beat),
    .offered_input_complete(dut.owners[owner].result_guard.offered_input_complete),
    .offered_local_fault_now(),
    .offered_local_faults_now(),
    .final_fence_certified(dut.owners[owner].result_guard.final_fence_certified),
    .external_fault_now(dut.owners[owner].result_guard.external_fault_now),
    .phase_input_fault_now(dut.owners[owner].result_guard.phase_input_fault_now),
    .completed_input_certified(dut.owners[owner].result_guard.completed_input_certified),
    .completed_input_fault_now(dut.owners[owner].result_guard.completed_input_fault_now),
    .preflight_fault_evidence_now(dut.owners[owner].result_guard.preflight_fault_evidence_now),
    .core_event_frame_started(dut.owners[owner].result_guard.core_event_frame_started),
    .core_output_tdata(dut.owners[owner].result_guard.core_output_tdata),
    .core_output_tuser(dut.owners[owner].result_guard.core_output_tuser),
    .core_output_tvalid(dut.owners[owner].result_guard.core_output_tvalid),
    .core_output_tlast(dut.owners[owner].result_guard.core_output_tlast),
    .core_status_tdata(dut.owners[owner].result_guard.core_status_tdata),
    .core_status_tvalid(dut.owners[owner].result_guard.core_status_tvalid),
    .mailbox_input_valid(),
    .mailbox_private_valid(),
    .mailbox_commit_valid(),
    .mailbox_input_ready(dut.owners[owner].result_guard.mailbox_input_ready),
    .mailbox_input_fault(dut.owners[owner].result_guard.mailbox_input_fault),
    .inverse_phase(dut.owners[owner].result_guard.inverse_phase),
    .forward_mailbox_fault(dut.owners[owner].result_guard.forward_mailbox_fault),
    .forward_retirement_valid(),
    .forward_private_offer(),
    .mailbox_input_data(),
    .mailbox_input_position(),
    .mailbox_input_last(),
    .mailbox_input_metadata(),
    .busy(),
    .commit_pulse(),
    .protocol_fault(),
    .fault_reasons(),
    .owner_active(),
    .owner_awaiting_ack(),
    .owner_fault_now(),
    .owner_ack_accept()
  );
  integer checks=0,preflight_edges=0;
  task automatic compare_guard;
    begin
      if(dut.owners[owner].result_guard.job_ready !== original.job_ready)$fatal(1,"shared preflight guard %0d differs: job_ready",owner);
      if(dut.owners[owner].result_guard.admission_capacity !== original.admission_capacity)$fatal(1,"shared preflight guard %0d differs: admission_capacity",owner);
      if(dut.owners[owner].result_guard.offered_local_fault_now !== original.offered_local_fault_now)$fatal(1,"shared preflight guard %0d differs: offered_local_fault_now",owner);
      if(dut.owners[owner].result_guard.offered_local_faults_now !== original.offered_local_faults_now)$fatal(1,"shared preflight guard %0d differs: offered_local_faults_now",owner);
      if(dut.owners[owner].result_guard.mailbox_input_valid !== original.mailbox_input_valid)$fatal(1,"shared preflight guard %0d differs: mailbox_input_valid",owner);
      if(dut.owners[owner].result_guard.mailbox_private_valid !== original.mailbox_private_valid)$fatal(1,"shared preflight guard %0d differs: mailbox_private_valid",owner);
      if(dut.owners[owner].result_guard.mailbox_commit_valid !== original.mailbox_commit_valid)$fatal(1,"shared preflight guard %0d differs: mailbox_commit_valid",owner);
      if(dut.owners[owner].result_guard.forward_retirement_valid !== original.forward_retirement_valid)$fatal(1,"shared preflight guard %0d differs: forward_retirement_valid",owner);
      if(dut.owners[owner].result_guard.forward_private_offer !== original.forward_private_offer)$fatal(1,"shared preflight guard %0d differs: forward_private_offer",owner);
      if(dut.owners[owner].result_guard.mailbox_input_data !== original.mailbox_input_data)$fatal(1,"shared preflight guard %0d differs: mailbox_input_data",owner);
      if(dut.owners[owner].result_guard.mailbox_input_position !== original.mailbox_input_position)$fatal(1,"shared preflight guard %0d differs: mailbox_input_position",owner);
      if(dut.owners[owner].result_guard.mailbox_input_last !== original.mailbox_input_last)$fatal(1,"shared preflight guard %0d differs: mailbox_input_last",owner);
      if(dut.owners[owner].result_guard.mailbox_input_metadata !== original.mailbox_input_metadata)$fatal(1,"shared preflight guard %0d differs: mailbox_input_metadata",owner);
      if(dut.owners[owner].result_guard.busy !== original.busy)$fatal(1,"shared preflight guard %0d differs: busy",owner);
      if(dut.owners[owner].result_guard.commit_pulse !== original.commit_pulse)$fatal(1,"shared preflight guard %0d differs: commit_pulse",owner);
      if(dut.owners[owner].result_guard.protocol_fault !== original.protocol_fault)$fatal(1,"shared preflight guard %0d differs: protocol_fault",owner);
      if(dut.owners[owner].result_guard.fault_reasons !== original.fault_reasons)$fatal(1,"shared preflight guard %0d differs: fault_reasons",owner);
      if(dut.owners[owner].result_guard.owner_active !== original.owner_active)$fatal(1,"shared preflight guard %0d differs: owner_active",owner);
      if(dut.owners[owner].result_guard.owner_awaiting_ack !== original.owner_awaiting_ack)$fatal(1,"shared preflight guard %0d differs: owner_awaiting_ack",owner);
      if(dut.owners[owner].result_guard.owner_fault_now !== original.owner_fault_now)$fatal(1,"shared preflight guard %0d differs: owner_fault_now",owner);
      if(dut.owners[owner].result_guard.owner_ack_accept !== original.owner_ack_accept)$fatal(1,"shared preflight guard %0d differs: owner_ack_accept",owner);
      if(dut.owners[owner].result_guard.active_private !== original.active_private)$fatal(1,"shared preflight guard %0d differs: active_private",owner);
      if(dut.owners[owner].result_guard.awaiting_ack !== original.awaiting_ack)$fatal(1,"shared preflight guard %0d differs: awaiting_ack",owner);
      if(dut.owners[owner].result_guard.descriptor !== original.descriptor)$fatal(1,"shared preflight guard %0d differs: descriptor",owner);
      if(dut.owners[owner].result_guard.input_count !== original.input_count)$fatal(1,"shared preflight guard %0d differs: input_count",owner);
      if(dut.owners[owner].result_guard.output_count !== original.output_count)$fatal(1,"shared preflight guard %0d differs: output_count",owner);
      if(dut.owners[owner].result_guard.input_complete_seen !== original.input_complete_seen)$fatal(1,"shared preflight guard %0d differs: input_complete_seen",owner);
      if(dut.owners[owner].result_guard.frame_seen !== original.frame_seen)$fatal(1,"shared preflight guard %0d differs: frame_seen",owner);
      if(dut.owners[owner].result_guard.status_seen !== original.status_seen)$fatal(1,"shared preflight guard %0d differs: status_seen",owner);
      if(dut.owners[owner].result_guard.exponent_seen !== original.exponent_seen)$fatal(1,"shared preflight guard %0d differs: exponent_seen",owner);
      if(dut.owners[owner].result_guard.status_exponent !== original.status_exponent)$fatal(1,"shared preflight guard %0d differs: status_exponent",owner);
      if(dut.owners[owner].result_guard.output_exponent !== original.output_exponent)$fatal(1,"shared preflight guard %0d differs: output_exponent",owner);
      if(dut.owners[owner].result_guard.age !== original.age)$fatal(1,"shared preflight guard %0d differs: age",owner);
      if(dut.owners[owner].result_guard.return_occupied !== original.return_occupied)$fatal(1,"shared preflight guard %0d differs: return_occupied",owner);
      if(dut.owners[owner].result_guard.return_last !== original.return_last)$fatal(1,"shared preflight guard %0d differs: return_last",owner);
      if(dut.owners[owner].result_guard.return_data !== original.return_data)$fatal(1,"shared preflight guard %0d differs: return_data",owner);
      if(dut.owners[owner].result_guard.return_position !== original.return_position)$fatal(1,"shared preflight guard %0d differs: return_position",owner);
      if(dut.owners[owner].result_guard.return_exponent !== original.return_exponent)$fatal(1,"shared preflight guard %0d differs: return_exponent",owner);
      if(dut.owners[owner].result_guard.CERTIFIED_PRIVATE_ADMISSION !== (1))$fatal(1,"reference parameter mismatch CERTIFIED_PRIVATE_ADMISSION");
      if(dut.owners[owner].result_guard.PRIVATE_ACK_RETIREMENT !== (owner==1))$fatal(1,"reference parameter mismatch PRIVATE_ACK_RETIREMENT");
      if(dut.owners[owner].result_guard.PRIVATE_QUARANTINE_OFFER !== (owner==1))$fatal(1,"reference parameter mismatch PRIVATE_QUARANTINE_OFFER");
      if(dut.owners[owner].result_guard.USE_PRIVATE_DESCRIPTOR_OFFER !== (1))$fatal(1,"reference parameter mismatch USE_PRIVATE_DESCRIPTOR_OFFER");
      if(dut.owners[owner].result_guard.ENABLE_OFFERED_FAULT_SUMMARY !== (1))$fatal(1,"reference parameter mismatch ENABLE_OFFERED_FAULT_SUMMARY");
      if(dut.owners[owner].result_guard.REQUIRE_KNOWN_COMPLETED_INPUT !== (1))$fatal(1,"reference parameter mismatch REQUIRE_KNOWN_COMPLETED_INPUT");
      if(dut.owners[owner].result_guard.USE_PHASE_INPUT_FAULT !== (0))$fatal(1,"reference parameter mismatch USE_PHASE_INPUT_FAULT");
      if(dut.owners[owner].result_guard.USE_COMPLETED_INPUT_FAULT !== (1))$fatal(1,"reference parameter mismatch USE_COMPLETED_INPUT_FAULT");
      if(dut.owners[owner].result_guard.USE_PREFLIGHT_REASON_ONLY !== (1))$fatal(1,"reference parameter mismatch USE_PREFLIGHT_REASON_ONLY");
      if(dut.owners[owner].result_guard.USE_FORWARD_RETIREMENT !== (1))$fatal(1,"reference parameter mismatch USE_FORWARD_RETIREMENT");
      checks=checks+1;
    end
  endtask
  always @(posedge fft_clk)begin
    compare_guard;
    if(dut.fast_running && dut.preparation_fault_now===1)preflight_edges=preflight_edges+1;
    #0.001;compare_guard;
  end
  task automatic report_one;
    $display("SHARED_PREFLIGHT_GUARD_PASS owner=%0d checks=%0d preflight_edges=%0d outputs_exact=1 private_state_exact=1",owner,checks,preflight_edges);
  endtask
  end endgenerate
  task automatic report_shared_preflight_guards;
    begin shared_guard_reference[0].report_one;shared_guard_reference[1].report_one;end
  endtask
