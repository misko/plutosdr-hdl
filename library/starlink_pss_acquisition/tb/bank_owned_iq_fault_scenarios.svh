// Included only by the generated numeric bench. Fault injections test wrapper
// quarantine and independent qualifier contracts; arithmetic uses actual core.
integer gap_witnesses = 0, index_witnesses = 0;
always @(posedge clk) begin
  if (scheduler_gap_pulse) gap_witnesses = gap_witnesses + 1;
  if (scheduler_index_error_pulse) index_witnesses = index_witnesses + 1;
end
task automatic bank_recover;
  begin
    @(negedge clk); sample_valid = 0; sample_gap = 0; enable = 0;
    repeat (12) @(negedge clk);
    enable = 1;
    repeat (12) @(negedge clk);
    if (detector_fault || score_valid || dut.island_fault)
      fail("bank composition explicit recovery failed");
  end
endtask
task automatic require_bank_quarantine;
  begin
    repeat (12) @(negedge clk);
    if (!detector_fault || score_valid)
      fail("bank composition did not latch fault and close scores");
    repeat (20) @(negedge clk);
    if (!detector_fault || score_valid)
      fail("bank composition quarantine was not sticky");
  end
endtask
task automatic bank_drive_fixture(input integer count);
  integer n, phase;
  begin
    n = 0; phase = 0;
    while (n < count) begin
      @(negedge clk); sample_valid = 0;
      phase = phase + 15;
      if (phase >= 100) begin
        phase = phase - 100;
        sample_valid = 1;
        sample_i = input_samples[n][15:0];
        sample_q = input_samples[n][31:16];
        sample_index = FIRST_SAMPLE_INDEX + n;
        n = n + 1;
      end
    end
    @(negedge clk); sample_valid = 0;
  end
endtask
task automatic bank_bad_qualifier(input integer kind);
  begin
    @(negedge clk);
    force dut.island_valid = 1;
    force dut.inverse_output_position = 0;
    force dut.island_metadata = {1'b1, FIRST_SAMPLE_INDEX, 5'd4, 5'd2};
    force dut.inverse_output_last = 0;
    @(negedge clk);
    force dut.inverse_output_position = 1;
    case (kind)
      0: force dut.inverse_output_position = 2;
      1: force dut.island_metadata = {1'b1, FIRST_SAMPLE_INDEX, 5'd5, 5'd2};
      2: force dut.island_metadata = {1'b1, FIRST_SAMPLE_INDEX, 5'd4, 5'd3};
      3: force dut.island_metadata = {1'b1, FIRST_SAMPLE_INDEX + 64'd1, 5'd4, 5'd2};
      4: force dut.inverse_output_last = 1;
    endcase
    // Only two beats: a valid position zero and ONE malformed beat. Keeping
    // valid asserted here would let a later duplicate ordinal mask a broken
    // exponent/start/TLAST predicate.
    @(negedge clk); force dut.island_valid = 0;
    @(negedge clk);
    if (!dut.candidate_score_path.qualifier.protocol_fault ||
        ((kind == 0 || kind == 4) &&
         !dut.candidate_score_path.qualifier.sequence_error_pulse) ||
        ((kind == 1 || kind == 2 || kind == 3) &&
         !dut.candidate_score_path.qualifier.metadata_error_pulse))
      fail("single malformed result did not trip independent qualifier");
    require_bank_quarantine();
    release dut.island_valid;
    release dut.inverse_output_position;
    release dut.island_metadata;
    release dut.inverse_output_last;
    bank_recover();
  end
endtask
integer exact_replay_epochs = 1;
task automatic bank_exact_replay;
  begin
    driven_samples = 0; forward_count = 0; product_count = 0;
    inverse_count = 0; score_count = 0; score_stalled_last_cycle = 0;
    expected_fault_window = 0;
    bank_drive_fixture(SAMPLE_COUNT);
    wait (score_count == SCORE_COUNT);
    repeat (20) @(negedge clk);
    if (driven_samples != SAMPLE_COUNT || forward_count != 1536 ||
        product_count != 1536 || inverse_count != 1536 || score_count != 1341)
      fail("post-purge exact replay count mismatch");
    exact_replay_epochs = exact_replay_epochs + 1;
    $display("BANK_IQ_EXACT_REPLAY_PASS epoch=%0d scores=1341", exact_replay_epochs);
    expected_fault_window = 1;
  end
endtask
task automatic run_bank_fault_scenarios;
  integer k, gap_before, index_before;
  begin
    expected_fault_window = 1;
    force dut.island.input_guard.protocol_fault = 1;
    require_bank_quarantine();
    release dut.island.input_guard.protocol_fault;
    bank_recover();
    for (k = 0; k < 5; k = k + 1) bank_bad_qualifier(k);
    @(negedge clk);
    force dut.island_valid = 1;
    force dut.island_metadata = 0;
    @(negedge clk); force dut.island_valid = 0;
    require_bank_quarantine();
    release dut.island_valid;
    release dut.island_metadata;
    bank_recover();

    // Gap/index discontinuity during an actual forward job must discard the
    // old epoch, not turn its private prefix into a later accepted score.
    bank_drive_fixture(700);
    if (!dut.island.input_guard.input_complete)
      fail("gap test missed active captured transform");
    gap_before = gap_witnesses;
    sample_valid = 1; sample_gap = 1; sample_index = FIRST_SAMPLE_INDEX + 700;
    @(negedge clk); sample_valid = 0; sample_gap = 0;
    repeat (100) @(negedge clk);
    if (gap_witnesses != gap_before + 1 || detector_fault || score_valid)
      fail("source gap did not restart and purge the retained epoch");
    // No enable/flush/reset between the source gap and exact fresh segment.
    bank_exact_replay();
    bank_recover();
    bank_drive_fixture(700);
    index_before = index_witnesses;
    sample_valid = 1; sample_index = FIRST_SAMPLE_INDEX + 701;
    @(negedge clk); sample_valid = 0;
    repeat (100) @(negedge clk);
    if (index_witnesses != index_before + 1 || detector_fault || score_valid)
      fail("source index discontinuity did not purge retained epoch");
    bank_exact_replay();
    bank_recover();

    bank_drive_fixture(700);
    fft_resetn = 0;
    require_bank_quarantine();
    fft_resetn = 1;
    require_bank_quarantine();
    bank_recover();
    bank_drive_fixture(700);
    resetn = 0;
    repeat (12) @(negedge clk);
    resetn = 1;
    repeat (100) @(negedge clk);
    if (detector_fault || score_valid)
      fail("independent slow reset did not purge in-flight epoch");
    bank_recover();

    // Re-run the entire immutable numerical fixture after all purges, using
    // real continuous samples, actual FFTs, independent metadata and scores.
    bank_exact_replay();
    expected_fault_window = 0;
    if (exact_replay_epochs != 4) fail("missing autonomous or explicit exact replay");
    $display("BANK_IQ_FAULT_RESET_GAP_PASS qualifier_mutations=5 descriptor=1 core_fault=1 fft_reset=1 slow_reset=1 source_gap=1 source_index=1 exact_epochs=4 exact_scores=5364 autonomous_gap_index_recovery=1");
  end
endtask
