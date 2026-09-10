// Optional extra epochs, copied into BOTH independently driven benches.
// Called only after every immutable original stimulus/assertion/receipt.
integer exact_extra_kind;
integer exact_extra_faults = 0, exact_extra_resets = 0, exact_extra_stalls = 0;
task automatic exact_control_extra_epochs;
  for (exact_extra_kind = 0; exact_extra_kind < 4; exact_extra_kind = exact_extra_kind + 1) begin
    reset_epoch(0); expected_results = 0; send_words(0, 512);
    wait(!dut.next_inverse && dut.return_commit_valid &&
         dut.joiner.kernel_rom.expected_bin_index == 511);
    // This is a real vendor-completed, qualified FINAL slot, not a force of
    // guard occupancy/counts or a quiescent cause snapshot.
    if (!dut.result_guard.active || !dut.result_guard.final_qualified ||
        !dut.product_bank_ready || dut.forward_committed || inverse_jobs)
      $fatal(1, "EXACT_EXTRA_FINAL_BOUNDARY_MISSING");
    if (exact_extra_kind != 0) begin
      force dut.product_bank_ready = 0;
      repeat (3) tick(); exact_extra_stalls = exact_extra_stalls + 1;
      if (dut.joiner.input_valid || dut.forward_committed || dut.product_bank_valid || inverse_jobs)
        $fatal(1, "EXACT_EXTRA_STALLED_FINAL_PUBLISHED");
    end
    if (exact_extra_kind < 2) begin
      expected_fault = 1;
      force dut.event_last_missing = 1;
      if (exact_extra_kind == 1) release dut.product_bank_ready;
      #0.001;
      if (dut.return_commit_valid || dut.joiner.input_valid || dut.forward_handoff_ack ||
          dut.product_commit_authorized)
        $fatal(1, "EXACT_EXTRA_CURRENT_FINAL_VETO_MISSING");
      tick();
      if (!dut.fast_fault || !dut.result_guard.fault_reasons[0])
        $fatal(1, "EXACT_EXTRA_FINAL_REASON_MISSING");
      @(negedge fft_clk); release dut.event_last_missing;
      await_fault(); exact_extra_faults = exact_extra_faults + 1;
      if (dut.product_bank_valid || inverse_jobs || dut.forward_handoff_ack)
        $fatal(1, "EXACT_EXTRA_POISONED_OWNERSHIP_ESCAPED");
    end else begin
      reset_epoch(exact_extra_kind - 1);
      @(negedge fft_clk); release dut.product_bank_ready;
      exact_extra_resets = exact_extra_resets + 1;
    end
    reset_epoch(0); send_words(0, 512); await_results(1);
  end
  if (exact_extra_faults != 2 || exact_extra_resets != 2 || exact_extra_stalls != 3)
    $fatal(1, "EXACT_EXTRA_COVERAGE_MISSING");
  $display("EXACT_CONTROL_EXTRA_EPOCHS_PASS final_faults=2 held_final_stalls=3 one_sided_resets=2 healthy_recoveries=4");
endtask
