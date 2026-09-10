// Full ROM interface transitions, not FFT numerics or legal-only snapshots.
`timescale 1ns/1ps
module tb_starlink_pss_next_start_scratch;
  parameter integer SCRATCH = 0;
  parameter integer BALANCED = 0;
  reg clk = 0, resetn = 0, flush = 0;
  reg input_valid = 0, output_ready = 1, input_last = 0;
  reg [8:0] input_bin_index = 0;
  reg [4:0] input_block_exponent = 0;
  reg [63:0] input_block_start_index = 0;
  reg [63:0] block_start, before_scratch;
  reg held_scratch;
  integer checks = 0, differences = 0, consulted = 0, bit_rows = 0, stall_rows = 0;
  integer bit_index, family, bin, trace_file;
  starlink_pss_kernel_rom #(.DATA_WIDTH(18), .ROM_FILE("upper_edge_pss_kernel_q17.mem"),
    .BALANCED_BLOCK_IDENTITY_EQ(BALANCED), .PRIVATE_NEXT_START_SCRATCH(SCRATCH)) dut
    (.clk(clk), .resetn(resetn), .flush(flush), .input_valid(input_valid),
     .output_ready(output_ready), .input_bin_index(input_bin_index), .input_last(input_last),
     .input_block_exponent(input_block_exponent), .input_block_start_index(input_block_start_index));
  starlink_pss_kernel_rom_dec20d63_golden #(.DATA_WIDTH(18), .ROM_FILE("upper_edge_pss_kernel_q17.mem"),
    .BALANCED_BLOCK_IDENTITY_EQ(BALANCED)) old
    (.clk(clk), .resetn(resetn), .flush(flush), .input_valid(input_valid),
     .output_ready(output_ready), .input_bin_index(input_bin_index), .input_last(input_last),
     .input_block_exponent(input_block_exponent), .input_block_start_index(input_block_start_index));

  task automatic compare;
    if ({dut.input_ready, dut.output_valid, dut.output_kernel_i, dut.output_kernel_q,
         dut.output_bin_index, dut.output_block_exponent, dut.output_last, dut.output_block_start_index,
         dut.accepted_pulse, dut.emitted_pulse, dut.input_block_complete_pulse,
         dut.sequence_error_pulse, dut.metadata_error_pulse, dut.protocol_fault,
         dut.expected_bin_index, dut.block_exponent, dut.block_start_index, dut.have_previous_block} !==
        {old.input_ready, old.output_valid, old.output_kernel_i, old.output_kernel_q,
         old.output_bin_index, old.output_block_exponent, old.output_last, old.output_block_start_index,
         old.accepted_pulse, old.emitted_pulse, old.input_block_complete_pulse,
         old.sequence_error_pulse, old.metadata_error_pulse, old.protocol_fault,
         old.expected_bin_index, old.block_exponent, old.block_start_index, old.have_previous_block})
      $fatal(1, "NEXT_SCRATCH_PUBLIC_STATE_MISMATCH family=%0d bit=%0d bin=%0d check=%0d", family,
        bit_index, input_bin_index, checks);
    if (!SCRATCH && dut.expected_next_block_start !== old.expected_next_block_start)
      $fatal(1, "default scratch changed");
    if (dut.expected_next_block_start !== old.expected_next_block_start) differences = differences + 1;
    checks = checks + 1;
  endtask
  task automatic step;
    #1;
    if (dut.input_accept !== old.input_accept) $fatal(1, "NEXT_SCRATCH_ACCEPT_MISMATCH");
    // Compare the actual consuming predicate BEFORE its edge, including bad
    // identity/ordinal/TLAST. No assumption that the incoming word is healthy.
    if (old.input_accept && old.at_block_start && old.have_previous_block) begin
      consulted = consulted + 1;
      if (dut.expected_next_block_start !== old.expected_next_block_start ||
          dut.metadata_error_now !== old.metadata_error_now)
        $fatal(1, "NEXT_SCRATCH_CONSUMED_IDENTITY_MISMATCH bit=%0d", bit_index);
    end
    before_scratch = dut.expected_next_block_start;
    held_scratch = resetn && !flush && !dut.input_ready;
    clk = 1; #1;
    if (held_scratch && dut.expected_next_block_start !== before_scratch)
      $fatal(1, "NEXT_SCRATCH_OCCUPIED_HOLD_MISMATCH");
    compare();
    $fdisplay(trace_file, "%0d,%b,%b,%b,%0d,%h,%h,%b,%b,%b,%b", checks, input_valid,
      output_ready, input_last, input_bin_index, dut.expected_next_block_start,
      old.expected_next_block_start, dut.output_valid, old.output_valid,
      dut.protocol_fault, old.protocol_fault);
    clk = 0; #1;
  endtask
  task automatic restart;
    resetn = 0; flush = 0; input_valid = 0; output_ready = 1;
    input_bin_index = 0; input_last = 0; input_block_exponent = 7; input_block_start_index = 0;
    step(); resetn = 1; step();
  endtask
  task automatic prefix;
    for (bin = 0; bin < 511; bin = bin + 1) begin
      input_valid = 1; input_bin_index = bin; input_last = 0;
      input_block_exponent = 7; input_block_start_index = block_start; output_ready = 1; step();
    end
    if (old.expected_bin_index !== 511 || old.protocol_fault) $fatal(1, "prefix failed");
  endtask
  task automatic final_bubbles;
    // Occupied/stalled bin510 output: even hostile invalid input cannot write.
    input_valid = 0; input_bin_index = 9'bx; input_last = 1'bx;
    input_block_exponent = 5'bx; input_block_start_index = 64'bx; output_ready = 0;
    step(); step(); stall_rows = stall_rows + 2;
    // The occupied output drains, then invalid scratch writes may differ.
    output_ready = 1; step();
    input_block_start_index = ~block_start; input_bin_index = 511; input_last = 1; step();
    input_block_start_index = 64'bz; step();
  endtask
  task automatic good_final;
    input_valid = 1; input_bin_index = 511; input_last = 1;
    input_block_exponent = 7; input_block_start_index = block_start; output_ready = 1; step();
    if (old.protocol_fault || !old.input_block_complete_pulse)
      $fatal(1, "healthy final failed");
  endtask
  initial begin
    trace_file = $fopen("scratch_transitions.csv", "w");
    $fdisplay(trace_file, "check,valid,ready,last,bin,new_scratch,old_scratch,new_valid,old_valid,new_fault,old_fault");
    for (family = 0; family < 2; family = family + 1)
    for (bit_index = 0; bit_index < 64; bit_index = bit_index + 1) begin
      restart(); block_start = 64'hfedcba9876543000; prefix(); final_bubbles();
      if (family == 0) begin
        good_final();
        // Between last and next start, arbitrary invalid inputs must NOT alter
        // the completed identity. This includes an asserted invalid TLAST.
        input_valid = 0; input_block_start_index = 64'bx; input_last = 1; step();
        input_block_start_index = 64'h123456789abcdef0; step();
        input_valid = 1; input_bin_index = 0; input_last = 0;
        input_block_start_index = (block_start + 64'd447) ^ (64'b1 << bit_index); step();
      end else begin
        input_valid = 1; input_bin_index = 511; input_last = 1; input_block_exponent = 7;
        input_block_start_index = block_start ^ (64'b1 << bit_index); step();
      end
      if (!old.protocol_fault || !old.metadata_error_pulse)
        $fatal(1, "all-bit corrupt input was not rejected family=%0d bit=%0d", family, bit_index);
      bit_rows = bit_rows + 1;
      input_valid = 1; input_block_start_index = block_start + 447; input_bin_index = 0; input_last = 0;
      repeat (3) step(); // Sticky quarantine forbids late recovery/publication.
      flush = 1; step(); flush = 0; input_valid = 0; step();
    end
    // Natural healthy last->next transactions across 64-bit wrap.
    restart(); block_start = 64'hffffffffffffff00; prefix(); final_bubbles(); good_final();
    block_start = block_start + 64'd447; prefix(); good_final();
    block_start = block_start + 64'd447; prefix(); good_final();
    // Bad ordinal, TLAST and exponent at the final boundary, independently.
    for (family = 2; family < 5; family = family + 1) begin
      restart(); block_start = 64'h8000000000000000; prefix(); final_bubbles();
      input_valid = 1; input_bin_index = family == 2 ? 9'd510 : 9'd511;
      input_last = family != 3; input_block_exponent = family == 4 ? 5'd6 : 5'd7;
      input_block_start_index = block_start; step();
      if (!old.protocol_fault) $fatal(1, "malformed final escaped");
      resetn = 0; step(); resetn = 1; input_valid = 0; step();
    end
    // Flush/reset dominate a pending scratch capture, including unknown input.
    restart(); block_start = 123; prefix(); final_bubbles(); flush = 1; step();
    if (dut.expected_next_block_start !== 0) $fatal(1, "flush failed to purge scratch");
    flush = 0; input_valid = 0; step();
    if (bit_rows != 128 || consulted < 66 || (SCRATCH && differences == 0))
      $fatal(1, "NEXT_SCRATCH_COVERAGE_MISSING consulted=%0d", consulted);
    $fclose(trace_file);
    $display("NEXT_SCRATCH_PASS scratch=%0d balanced=%0d checks=%0d differences=%0d consulted=%0d bit_rows=%0d stall_rows=%0d frozen_all_public_and_other_state=1 fft_proof=0",
      SCRATCH, BALANCED, checks, differences, consulted, bit_rows, stall_rows);
    $finish;
  end
endmodule
