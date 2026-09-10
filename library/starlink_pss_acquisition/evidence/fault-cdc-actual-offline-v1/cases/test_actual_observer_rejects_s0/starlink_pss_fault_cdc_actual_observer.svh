// Observation only: no DUT drives or changes to the original 217-field gate.
  reg [1:0] fault_cdc_scalar;
  integer fault_cdc_checks=0, fault_cdc_stage0_high=0, fault_cdc_stage1_high=0;
  integer fault_cdc_reset_samples=0, fault_cdc_current_edges=0;
  integer fault_cdc_final_edges=0, fault_cdc_private_reset_samples=0;
  initial begin
    if (PER_CAUSE_FAULT_CDC !== 0 && PER_CAUSE_FAULT_CDC !== 1)
      $fatal(1,"FAULT_CDC_ACTUAL_OPTION_INVALID");
    if (dut.PER_CAUSE_FAULT_CDC !== PER_CAUSE_FAULT_CDC ||
        dut.REGISTERED_SCHEDULING !== 1 || dut.DISTRIBUTED_FAST_FAULT !== 1 ||
        dut.PRIVATE_NEXT_START_SCRATCH !== 1)
      $fatal(1,"FAULT_CDC_ACTUAL_PARAMETER_FORWARDING_MISMATCH");
  end
  always @(posedge clk) begin
    if (!dut.slow_running) fault_cdc_scalar <= 0;
    else fault_cdc_scalar <= {dut.fast_fault, dut.fast_fault};
  end
  always @(posedge clk or negedge clk) begin
    // The existing independent stimulus/checkers remain unmodified. Observe
    // after their1ps settlement, exactly as the original full-field observer.
    #0.002;
    if (dut.fast_fault_slow !== fault_cdc_scalar)
      $fatal(1,"FAULT_CDC_ACTUAL_STAGE_MISMATCH actual=%b scalar=%b",dut.fast_fault_slow,fault_cdc_scalar);
    fault_cdc_checks=fault_cdc_checks+1;
    if (dut.fast_fault_slow[0] === 1'b1) fault_cdc_stage0_high=fault_cdc_stage0_high+1;
    if (dut.fast_fault_slow[1] === 1'b1) fault_cdc_stage1_high=fault_cdc_stage1_high+1;
    if (dut.slow_running === 1'b0) fault_cdc_reset_samples=fault_cdc_reset_samples+1;
    if (dut.fast_running === 1'b1 && dut.core_aresetn === 1'b0 && dut.fast_fault === 1'b1)
      fault_cdc_private_reset_samples=fault_cdc_private_reset_samples+1;
  end
  always @(posedge fft_clk) begin
    if (dut.fast_running && dut.any_fast_fault) begin
      fault_cdc_current_edges=fault_cdc_current_edges+1;
      if (dut.joiner.kernel_rom.expected_bin_index == 511)
        fault_cdc_final_edges=fault_cdc_final_edges+1;
    end
  end
  task fault_cdc_verify_terminal;
    begin
      if (dut.PER_CAUSE_FAULT_CDC !== PER_CAUSE_FAULT_CDC ||
          dut.REGISTERED_SCHEDULING !== 1 || dut.DISTRIBUTED_FAST_FAULT !== 1 ||
          dut.PRIVATE_NEXT_START_SCRATCH !== 1)
        $fatal(1,"FAULT_CDC_ACTUAL_PARAMETER_FORWARDING_MISMATCH");
      if (!fault_cdc_checks || !fault_cdc_stage0_high || !fault_cdc_stage1_high ||
          !fault_cdc_reset_samples || !fault_cdc_current_edges || fault_cdc_final_edges < 2)
        $fatal(1,"FAULT_CDC_ACTUAL_COVERAGE_INCOMPLETE");
      $display("FAULT_CDC_ACTUAL_PASS enabled=%0d checks=%0d stage0_high=%0d stage1_high=%0d reset_samples=%0d current_fault_edges=%0d final_fault_edges=%0d private_core_reset_samples=%0d scalar_source=actual_fast_fault reference_reset=slow_running",
        PER_CAUSE_FAULT_CDC,fault_cdc_checks,fault_cdc_stage0_high,fault_cdc_stage1_high,
        fault_cdc_reset_samples,fault_cdc_current_edges,fault_cdc_final_edges,fault_cdc_private_reset_samples);
    end
  endtask
