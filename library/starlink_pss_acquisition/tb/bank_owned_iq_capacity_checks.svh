// Independent frame identities/exponents at actual domain handshakes. The
// 64-block capacity stimulus is NOT a numerical reference for FFT or scores.
integer cap_forward_words = 0, cap_product_words = 0, cap_inverse_words = 0;
integer cap_fast_block, cap_fast_position, cap_slow_block, cap_slow_position;
integer cap_fast_cycle = 0, cap_prior_admission = -1;
integer cap_min_interval = 2147483647, cap_max_interval = 0;
integer cap_overlap_capture = 0, cap_three_epoch_overlap = 0;
reg [4:0] cap_forward_exponents [0:BLOCK_COUNT-1];
reg [4:0] cap_inverse_exponent;
always @(posedge fft_clk) begin
  cap_fast_cycle = cap_fast_cycle + 1;
  if (resetn && enable) begin
    if (dut.island.input_job_start && !dut.island.next_inverse) begin
      if (cap_prior_admission >= 0) begin
        if (cap_fast_cycle - cap_prior_admission < cap_min_interval)
          cap_min_interval = cap_fast_cycle - cap_prior_admission;
        if (cap_fast_cycle - cap_prior_admission > cap_max_interval)
          cap_max_interval = cap_fast_cycle - cap_prior_admission;
      end
      cap_prior_admission = cap_fast_cycle;
    end
    if (dut.island.joiner.input_valid && dut.island.joiner.input_ready) begin
      cap_fast_block = cap_forward_words / 512;
      cap_fast_position = cap_forward_words % 512;
      if (cap_fast_block >= BLOCK_COUNT ||
          dut.island.return_position !== cap_fast_position[8:0] ||
          dut.island.return_last !== (cap_fast_position == 511) ||
          dut.island.return_metadata[74] !== 1'b0 ||
          dut.island.return_metadata[73:10] !== FIRST_SAMPLE_INDEX + cap_fast_block * 447)
        report_and_fail("independent_forward_frame_metadata");
      if (cap_fast_position == 0)
        cap_forward_exponents[cap_fast_block] = dut.island.return_metadata[4:0];
      else if (dut.island.return_metadata[4:0] !== cap_forward_exponents[cap_fast_block])
        report_and_fail("independent_forward_exponent_drift");
      cap_forward_words = cap_forward_words + 1;
    end
    if (dut.island.product_valid && !dut.island.fast_fault && dut.island.product_bank_ready) begin
      cap_fast_block = cap_product_words / 512;
      cap_fast_position = cap_product_words % 512;
      if (cap_fast_block >= BLOCK_COUNT ||
          dut.island.product_position !== cap_fast_position[8:0] ||
          dut.island.product_last !== (cap_fast_position == 511) ||
          dut.island.product_start !== FIRST_SAMPLE_INDEX + cap_fast_block * 447 ||
          dut.island.product_exponent !== cap_forward_exponents[cap_fast_block] ||
          dut.island.product_overflow)
        report_and_fail("independent_product_frame_metadata");
      cap_product_words = cap_product_words + 1;
    end
  end
end
always @(posedge clk) begin
  if (resetn && enable) begin
    if (dut.inverse_output_valid && dut.inverse_output_ready) begin
      cap_slow_block = cap_inverse_words / 512;
      cap_slow_position = cap_inverse_words % 512;
      if (cap_slow_block >= BLOCK_COUNT ||
          dut.inverse_output_position !== cap_slow_position[8:0] ||
          dut.inverse_output_last !== (cap_slow_position == 511) ||
          dut.inverse_output_block_start !== FIRST_SAMPLE_INDEX + cap_slow_block * 447 ||
          dut.inverse_forward_exponent !== cap_forward_exponents[cap_slow_block])
        report_and_fail("independent_inverse_frame_metadata");
      if (cap_slow_position == 0) cap_inverse_exponent = dut.inverse_output_exponent;
      else if (dut.inverse_output_exponent !== cap_inverse_exponent)
        report_and_fail("independent_inverse_exponent_drift");
      cap_inverse_words = cap_inverse_words + 1;
    end
    if (dut.scheduler_fft_valid && dut.scheduler_fft_ready &&
        dut.island.state == 6 &&
        dut.scheduler_fft_block_start == dut.island.engine_metadata[68:5] + 447) begin
      cap_overlap_capture = cap_overlap_capture + 1;
      if (score_valid && score_ready &&
          (score_start_index - FIRST_SAMPLE_INDEX) / 447 + 1 ==
          (dut.island.engine_metadata[68:5] - FIRST_SAMPLE_INDEX) / 447)
        cap_three_epoch_overlap = cap_three_epoch_overlap + 1;
    end
  end
end
