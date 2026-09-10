// Observation only. The independent old ROM receives ONLY actual ROM inputs;
// it does not reconstruct retirement, share new predicates, or drive DUT nets.
  starlink_pss_kernel_rom #(
    .ROM_FILE("upper_edge_pss_kernel_q17.mem"), .DATA_WIDTH(18),
    .BALANCED_BLOCK_IDENTITY_EQ(1), .PRIVATE_NEXT_START_SCRATCH(1)
  ) rom_input_reference (
    .clk(dut.joiner.kernel_rom.clk),
    .resetn(dut.joiner.kernel_rom.resetn),
    .flush(dut.joiner.kernel_rom.flush),
    .input_valid(dut.joiner.kernel_rom.input_valid),
    .input_bin_index(dut.joiner.kernel_rom.input_bin_index),
    .input_block_exponent(dut.joiner.kernel_rom.input_block_exponent),
    .input_last(dut.joiner.kernel_rom.input_last),
    .input_block_start_index(dut.joiner.kernel_rom.input_block_start_index),
    .output_ready(dut.joiner.kernel_rom.output_ready)
  );
`define ROM_ACTUAL_VIEW(g) {g.input_ready,g.output_valid,g.output_kernel_i,g.output_kernel_q, \
    g.output_kernel_word,g.output_bin_index,g.output_block_exponent,g.output_last, \
    g.output_block_start_index,g.accepted_pulse,g.emitted_pulse, \
    g.input_block_complete_pulse,g.sequence_error_pulse,g.metadata_error_pulse, \
    g.protocol_fault,g.expected_bin_index,g.block_exponent,g.block_start_index, \
    g.expected_next_block_start,g.have_previous_block,g.output_stage_ready, \
    g.input_accept,g.at_block_start,g.sequence_error_now,g.metadata_error_now, \
    g.protocol_error_now,g.block_identity_equal}
  integer rom_pre_checks=0, rom_post_checks=0, rom_accepts=0;
  integer rom_first_accepts=0, rom_last_accepts=0, rom_stalls=0, rom_resets=0;
  integer rom_current_fault_edges=0, rom_final_fault_edges=0, rom_private_reset_edges=0;
  task rom_verify_parameters;
    begin
      if ((PRIVATE_ROM_READ_AHEAD !== 0 && PRIVATE_ROM_READ_AHEAD !== 1) ||
          (PRIVATE_BLOCK_METADATA_READ_AHEAD !== 0 && PRIVATE_BLOCK_METADATA_READ_AHEAD !== 1))
        $fatal(1,"ROM_ACTUAL_OPTIONS_INVALID");
      if (dut.PRIVATE_ROM_READ_AHEAD !== PRIVATE_ROM_READ_AHEAD ||
          dut.PRIVATE_BLOCK_METADATA_READ_AHEAD !== PRIVATE_BLOCK_METADATA_READ_AHEAD ||
          dut.joiner.PRIVATE_ROM_READ_AHEAD !== PRIVATE_ROM_READ_AHEAD ||
          dut.joiner.PRIVATE_BLOCK_METADATA_READ_AHEAD !== PRIVATE_BLOCK_METADATA_READ_AHEAD ||
          dut.joiner.kernel_rom.PRIVATE_ROM_READ_AHEAD !== PRIVATE_ROM_READ_AHEAD ||
          dut.joiner.kernel_rom.PRIVATE_BLOCK_METADATA_READ_AHEAD !== PRIVATE_BLOCK_METADATA_READ_AHEAD ||
          dut.joiner.kernel_rom.DATA_WIDTH !== 18 ||
          dut.joiner.kernel_rom.BALANCED_BLOCK_IDENTITY_EQ !== 1 ||
          dut.joiner.kernel_rom.PRIVATE_NEXT_START_SCRATCH !== 1 ||
          dut.joiner.kernel_rom.ROM_FILE !== "upper_edge_pss_kernel_q17.mem" ||
          dut.REGISTERED_SCHEDULING !== 1 || dut.DISTRIBUTED_FAST_FAULT !== 1 ||
          dut.PER_CAUSE_FAULT_CDC !== 1 || dut.PRIVATE_NEXT_START_SCRATCH !== 1)
        $fatal(1,"ROM_ACTUAL_PARAMETER_FORWARDING_MISMATCH");
    end
  endtask
  initial rom_verify_parameters();
  task rom_compare(input integer post_edge);
    begin
      // Evaluate the complete concatenations now, not a potentially stale
      // continuous-assignment equality bit. There is NO invalid-cycle mask.
      if (`ROM_ACTUAL_VIEW(dut.joiner.kernel_rom) !== `ROM_ACTUAL_VIEW(rom_input_reference))
        $fatal(1,"ROM_ACTUAL_UNCONDITIONAL_MISMATCH post=%0d time=%0t actual=%h old=%h",
          post_edge,$time,`ROM_ACTUAL_VIEW(dut.joiner.kernel_rom),`ROM_ACTUAL_VIEW(rom_input_reference));
    end
  endtask
  always @(posedge fft_clk) begin
    // Inactive-region observation drains same-time active blocking/force and
    // port propagation before NBA; then repeat after NBA at +1ps, again after
    // same-time active propagation. No stimulus drive or DUT wait is added.
    #0;
    rom_compare(0); rom_pre_checks=rom_pre_checks+1;
    if (dut.joiner.kernel_rom.resetn === 1'b0) rom_resets=rom_resets+1;
    if (dut.joiner.kernel_rom.input_accept === 1'b1) begin
      rom_accepts=rom_accepts+1;
      if (dut.joiner.kernel_rom.input_bin_index === 0) rom_first_accepts=rom_first_accepts+1;
      if (dut.joiner.kernel_rom.input_last === 1'b1) rom_last_accepts=rom_last_accepts+1;
    end
    if (dut.joiner.kernel_rom.output_valid === 1'b1 &&
        dut.joiner.kernel_rom.output_ready === 1'b0) rom_stalls=rom_stalls+1;
    if (dut.fast_running === 1'b1 && dut.any_fast_fault === 1'b1) begin
      rom_current_fault_edges=rom_current_fault_edges+1;
      if (dut.joiner.kernel_rom.expected_bin_index === 511)
        rom_final_fault_edges=rom_final_fault_edges+1;
    end
    if (dut.fast_running === 1'b1 && dut.core_aresetn === 1'b0)
      rom_private_reset_edges=rom_private_reset_edges+1;
    #0.001; #0;
    rom_compare(1); rom_post_checks=rom_post_checks+1;
  end
  task rom_verify_terminal;
    begin
      rom_verify_parameters();
      if (rom_pre_checks <= 0 || rom_pre_checks != rom_post_checks ||
          rom_accepts < 512 || rom_first_accepts <= 0 || rom_last_accepts <= 0 ||
          rom_stalls <= 0 || rom_resets <= 0 || rom_current_fault_edges <= 0 ||
          rom_final_fault_edges < 2 || rom_private_reset_edges <= 0)
        $fatal(1,"ROM_ACTUAL_COVERAGE_INCOMPLETE");
      $display("ROM_READ_AHEAD_ACTUAL_PASS word=%0d metadata=%0d pre=%0d post=%0d accepts=%0d first=%0d last=%0d stalls=%0d resets=%0d current_fault_edges=%0d final_fault_edges=%0d private_reset_edges=%0d old_source=C1 input_ports_only=1 unconditional_old_state=1",
        PRIVATE_ROM_READ_AHEAD,PRIVATE_BLOCK_METADATA_READ_AHEAD,rom_pre_checks,rom_post_checks,
        rom_accepts,rom_first_accepts,rom_last_accepts,rom_stalls,rom_resets,
        rom_current_fault_edges,rom_final_fault_edges,rom_private_reset_edges);
    end
  endtask
`undef ROM_ACTUAL_VIEW
