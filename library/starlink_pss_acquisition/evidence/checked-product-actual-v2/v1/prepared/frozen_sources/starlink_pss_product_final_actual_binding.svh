// Additive monitor only. Existing independent dec20 whole-bank/public state
// comparison remains literal, including every old forced malformed-state row.
  task product_final_verify_parameters;
    begin
      if (PRODUCER_LOCAL_FINAL_FENCE !== 0 && PRODUCER_LOCAL_FINAL_FENCE !== 1)
        $fatal(1,"PRODUCT_FINAL_ACTUAL_OPTION_INVALID");
      if (dut.PRODUCER_LOCAL_FINAL_FENCE !== PRODUCER_LOCAL_FINAL_FENCE ||
          dut.product_bank.USE_PRODUCER_FINAL_FENCE !== PRODUCER_LOCAL_FINAL_FENCE ||
          dut.product_bank.EXPLICIT_COMMIT !== 1 || dut.product_bank.ADDRESS_WIDTH !== 9 ||
          dut.product_bank.DATA_WIDTH !== 36 || dut.product_bank.METADATA_WIDTH !== 70 ||
          dut.product_bank.RESET_RELEASE_EXTERNAL !== 1)
        $fatal(1,"PRODUCT_FINAL_ACTUAL_PARAMETER_FORWARDING_MISMATCH");
    end
  endtask
  initial product_final_verify_parameters();
  starlink_pss_product_final_actual_observer product_final_observer (
    .clk(fft_clk), .in_running(dut.product_bank.in_running),
    .input_accept(dut.product_bank.input_accept),
    .input_framing_valid(dut.product_bank.input_framing_valid),
    .write_position(dut.product_bank.write_position),
    .old_authorized(dut.product_bank.input_commit_authorized),
    .new_authorized(dut.product_bank.input_final_seal_authorized),
    .forward_committed(dut.forward_committed), .slot_open(dut.input_guard.slot_open),
    .checked_complete(dut.checked_input_complete), .inverse_phase(dut.next_inverse),
    .guard_phase(dut.guard_phase), .input_fault_now(dut.input_fault_now),
    .duplicate_start(dut.duplicate_start_fault_now), .handoff_fault_now(dut.handoff_fault_now),
    .request_toggle(dut.product_bank.request_toggle),
    .acknowledge_stage1(dut.product_bank.acknowledge_sync[1]),
    .reading(dut.product_bank.reading), .read_valid(dut.product_bank.read_valid),
    .public_ready(dut.product_bank.input_ready), .public_valid(dut.product_bank.output_valid),
    .fast_running(dut.fast_running), .current_fault(dut.any_fast_fault),
    .core_resetn(dut.core_aresetn), .output_ready(dut.product_bank.output_ready)
  );
  task product_final_verify_terminal;
    begin
      product_final_verify_parameters();
      product_final_observer.verify_terminal(PRODUCER_LOCAL_FINAL_FENCE);
    end
  endtask
