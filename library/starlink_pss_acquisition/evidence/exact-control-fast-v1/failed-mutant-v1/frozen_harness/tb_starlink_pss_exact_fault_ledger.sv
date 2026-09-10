// Whole wrapper transitions against independently frozen seven-module RTL.
// Vendor core is a quiescent stub: this proves no FFT numerical behavior.
`timescale 1ns/1ps
module tb_starlink_pss_exact_fault_ledger;
  parameter integer DISTRIBUTED = 0;
  parameter integer SCRATCH = 0;
  parameter integer REGISTERED = 0;
  reg clk = 0, fft_clk = 0, resetn = 0, fft_resetn = 0;
  always #5 clk = !clk;
  always #3 fft_clk = !fft_clk;
  reg input_valid = 0, output_ready = 1;
  reg [35:0] input_data = 0;
  reg [8:0] input_position = 0;
  reg input_last = 0;
  reg [63:0] input_block_start = 0;
  reg [11:0] causes = 0;
  reg old_scalar, before_fault;
  integer mask, bit_index, second_index, checks = 0, mask_rows = 0, x_rows = 0;
  integer trace_file;
  starlink_pss_fft_bank_owned_slice #(.REGISTERED_SCHEDULING(REGISTERED),
    .DISTRIBUTED_FAST_FAULT(DISTRIBUTED), .PRIVATE_NEXT_START_SCRATCH(SCRATCH)) dut
    (.clk(clk), .fft_clk(fft_clk), .resetn(resetn), .fft_resetn(fft_resetn),
     .input_valid(input_valid), .input_data(input_data), .input_position(input_position),
     .input_last(input_last), .input_block_start(input_block_start), .output_ready(output_ready));
  starlink_pss_fft_bank_owned_slice_dec20d63_golden #(.REGISTERED_SCHEDULING(REGISTERED)) old
    (.clk(clk), .fft_clk(fft_clk), .resetn(resetn), .fft_resetn(fft_resetn),
     .input_valid(input_valid), .input_data(input_data), .input_position(input_position),
     .input_last(input_last), .input_block_start(input_block_start), .output_ready(output_ready));

  task automatic drive_causes;
    // Individually override actual constituent wires, NEVER any_fast_fault or
    // external_fault_now. This includes deliberately simultaneous/inconsistent
    // snapshots; no healthy-interface assumption makes the recurrence pass.
    force dut.input_fault_now = causes[0]; force old.input_fault_now = causes[0];
    force dut.input_guard_fault = causes[1]; force old.input_guard_fault = causes[1];
    force dut.source_fault_fast[1] = causes[2]; force old.source_fault_fast[1] = causes[2];
    force dut.vendor_fault_now = causes[3]; force old.vendor_fault_now = causes[3];
    force dut.kernel_fault = causes[4]; force old.kernel_fault = causes[4];
    force dut.product_overflow = causes[5]; force old.product_overflow = causes[5];
    force dut.product_bank_fault = causes[6]; force old.product_bank_fault = causes[6];
    force dut.product_bank_framing_fault_now = causes[7]; force old.product_bank_framing_fault_now = causes[7];
    force dut.handoff_fault_now = causes[8]; force old.handoff_fault_now = causes[8];
    force dut.result_fault = causes[9]; force old.result_fault = causes[9];
    force dut.output_bank_fault = causes[10]; force old.output_bank_fault = causes[10];
    force dut.preparation_fault_now = causes[11]; force old.preparation_fault_now = causes[11];
  endtask
  task automatic compare;
    if (dut.fast_fault !== old.fast_fault || dut.fast_fault !== old_scalar)
      $fatal(1, "EXACT_LEDGER_MISMATCH causes=%h before=%b new=%b old=%b scalar=%b", causes,
        before_fault, dut.fast_fault, old.fast_fault, old_scalar);
    if ({dut.fault, dut.input_ready, dut.output_valid, dut.output_data, dut.output_position,
         dut.output_last, dut.output_metadata, dut.state, dut.core_release, dut.next_inverse,
         dut.input_job_start, dut.core_input_valid, dut.source_read_ready, dut.product_bank_read_ready,
         dut.result_guard.fault_reasons, dut.input_guard.fault_reasons, dut.epoch_input_reasons,
         dut.epoch_preflight_reasons, dut.return_valid, dut.forward_retirement_valid,
         dut.return_commit_valid, dut.forward_handoff_ack, dut.product_commit_authorized,
         dut.product_bank.request_toggle, dut.output_bank.request_toggle} !==
        {old.fault, old.input_ready, old.output_valid, old.output_data, old.output_position,
         old.output_last, old.output_metadata, old.state, old.core_release, old.next_inverse,
         old.input_job_start, old.core_input_valid, old.source_read_ready, old.product_bank_read_ready,
         old.result_guard.fault_reasons, old.input_guard.fault_reasons, old.epoch_input_reasons,
         old.epoch_preflight_reasons, old.return_valid, old.forward_retirement_valid,
         old.return_commit_valid, old.forward_handoff_ack, old.product_commit_authorized,
         old.product_bank.request_toggle, old.output_bank.request_toggle})
      $fatal(1, "EXACT_LEDGER_PUBLIC_REASON_STATE_MISMATCH causes=%h check=%0d", causes, checks);
    checks = checks + 1;
  endtask
  task automatic step;
    @(negedge fft_clk); drive_causes(); #1;
    before_fault = old.fast_fault;
    old_scalar = old.fast_fault;
    if (!old.fast_running) old_scalar = 0;
    else if (old.any_fast_fault) old_scalar = 1;
    if (dut.any_fast_fault !== old.any_fast_fault ||
        dut.external_fault_now !== old.external_fault_now ||
        dut.result_guard.faults_now !== old.result_guard.faults_now)
      $fatal(1, "EXACT_LEDGER_RAW_FENCE_MISMATCH");
    @(posedge fft_clk); #1; compare();
    $fdisplay(trace_file, "%0d,%h,%b,%b,%b,%b,%h,%h", checks, causes, dut.fast_running,
      before_fault, dut.fast_fault, old.fast_fault, dut.result_guard.fault_reasons,
      old.result_guard.fault_reasons);
  endtask
  task automatic epoch_reset;
    causes = 0; resetn = 0; fft_resetn = 0; repeat (3) step();
    resetn = 1; fft_resetn = 1; repeat (6) step();
    if (dut.fast_fault !== 0 || !dut.fast_running) $fatal(1, "ledger reset failed");
  endtask
  initial begin
    trace_file = $fopen("ledger_transitions.csv", "w");
    $fdisplay(trace_file, "check,causes,fast_running,before,new,old,new_reasons,old_reasons");
    drive_causes();
    for (mask = 0; mask < 4096; mask = mask + 1) begin
      epoch_reset(); causes = mask; step(); mask_rows = mask_rows + 1;
      causes = 0; step();
      causes = (~mask) & 12'hfff; step(); // every simultaneous sticky/current combination
      causes = 0; step();
      if (dut.fast_fault !== 1) $fatal(1, "lost sticky cause");
    end
    for (bit_index = 0; bit_index < 12; bit_index = bit_index + 1) begin
      epoch_reset(); causes[bit_index] = 1'bx; step(); x_rows = x_rows + 1;
      if (dut.fast_fault !== 0) $fatal(1, "unknown-only cause changed scalar if semantics");
      causes = 0; causes[bit_index] = 1'bz; step(); x_rows = x_rows + 1;
      if (dut.fast_fault !== 0) $fatal(1, "high-impedance-only cause changed scalar if semantics");
      for (second_index = 0; second_index < 12; second_index = second_index + 1)
        if (second_index != bit_index) begin
          causes = 0; causes[bit_index] = 1'bx; causes[second_index] = 1; step();
          x_rows = x_rows + 1;
        end
    end
    causes = 12'hfff; resetn = 0; repeat (5) step(); resetn = 1; repeat (6) step();
    fft_resetn = 0; repeat (5) step(); fft_resetn = 1; repeat (6) step();
    epoch_reset();
    // Prove wrapper -> joiner -> ROM knob plumbing, including combined mode.
    force dut.joiner.kernel_rom.expected_bin_index = 9'd511;
    force old.joiner.kernel_rom.expected_bin_index = 9'd511;
    force dut.return_metadata = {1'b0, 64'hffffffffffffff00, 10'b0};
    force old.return_metadata = {1'b0, 64'hffffffffffffff00, 10'b0};
    repeat (3) step();
    if (dut.joiner.kernel_rom.expected_next_block_start !== (SCRATCH ? 64'd191 : 64'd0))
      $fatal(1, "EXACT_SCRATCH_WRAPPER_WIRING_MISMATCH");
    if (old.joiner.kernel_rom.expected_next_block_start !== 0)
      $fatal(1, "frozen scratch reference changed on invalid input");
    release dut.joiner.kernel_rom.expected_bin_index; release old.joiner.kernel_rom.expected_bin_index;
    release dut.return_metadata; release old.return_metadata;
    epoch_reset(); $fclose(trace_file);
    $display("EXACT_LEDGER_PASS distributed=%0d scratch=%0d registered=%0d checks=%0d masks=%0d x_rows=%0d whole_frozen_wrapper=1 quiescent_stub_not_fft=1", DISTRIBUTED, SCRATCH, REGISTERED, checks, mask_rows, x_rows);
    $finish;
  end
endmodule
