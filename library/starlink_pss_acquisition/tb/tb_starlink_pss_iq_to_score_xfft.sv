`timescale 1ns/1ps

module tb_starlink_pss_iq_to_score_xfft;

  localparam integer SAMPLE_COUNT = 1406;
  localparam integer BLOCK_COUNT = 3;
  localparam integer FFT_SAMPLES = 512;
  localparam integer SCORE_COUNT = 1341;
  localparam [63:0] FIRST_SAMPLE_INDEX = 64'd1000000;

  reg clk = 1'b0;
  reg resetn = 1'b0;
  reg enable = 1'b0;
  reg flush = 1'b0;
  reg sample_valid = 1'b0;
  reg sample_gap = 1'b0;
  reg signed [15:0] sample_i = 0;
  reg signed [15:0] sample_q = 0;
  reg [63:0] sample_index = 0;
  reg score_ready = 1'b1;

  wire score_valid;
  wire [7:0] score_value;
  wire [63:0] score_start_index;
  wire score_denominator_zero;
  wire detector_fault;
  wire scheduler_gap_pulse;
  wire scheduler_index_error_pulse;
  wire scheduler_overflow_pulse;
  wire forward_fft_fault;
  wire kernel_join_fault;
  wire product_overflow_fault;
  wire inverse_fft_fault;
  wire forward_exponent_fault;
  wire candidate_path_fault;
  wire [9:0] candidate_fifo_stored_count;
  wire [9:0] candidate_fifo_maximum_stored_count;

  reg [31:0] input_samples [0:SAMPLE_COUNT-1];
  reg [47:0] expected_forward [0:BLOCK_COUNT*FFT_SAMPLES-1];
  reg [47:0] expected_product [0:BLOCK_COUNT*FFT_SAMPLES-1];
  reg [47:0] expected_inverse [0:BLOCK_COUNT*FFT_SAMPLES-1];
  reg [4:0] expected_forward_exponents [0:BLOCK_COUNT-1];
  reg [4:0] expected_inverse_exponents [0:BLOCK_COUNT-1];
  reg [7:0] expected_scores [0:SCORE_COUNT-1];

  integer cycle_count = 0;
  integer driven_samples = 0;
  integer forward_count = 0;
  integer product_count = 0;
  integer inverse_count = 0;
  integer score_count = 0;
  integer drive_index;
  integer cadence_phase = 0;
  integer block_number;
  integer block_position;
  integer observed_max_fifo;
  reg score_stalled_last_cycle = 1'b0;
  reg [72:0] stalled_score_payload = 0;
  reg expected_fault_window = 1'b0;

  always #5 clk = ~clk;

  starlink_pss_iq_to_score dut (
    .clk                                  (clk),
    .resetn                               (resetn),
    .enable                               (enable),
    .flush                                (flush),
    .sample_valid                         (sample_valid),
    .sample_gap                           (sample_gap),
    .sample_i                             (sample_i),
    .sample_q                             (sample_q),
    .sample_index                         (sample_index),
    .score_valid                          (score_valid),
    .score_ready                          (score_ready),
    .score_value                          (score_value),
    .score_start_index                    (score_start_index),
    .score_denominator_zero               (score_denominator_zero),
    .detector_fault                       (detector_fault),
    .scheduler_gap_pulse                  (scheduler_gap_pulse),
    .scheduler_index_error_pulse          (scheduler_index_error_pulse),
    .scheduler_overflow_pulse             (scheduler_overflow_pulse),
    .forward_fft_fault                    (forward_fft_fault),
    .kernel_join_fault                    (kernel_join_fault),
    .product_overflow_fault               (product_overflow_fault),
    .inverse_fft_fault                    (inverse_fft_fault),
    .forward_exponent_fault               (forward_exponent_fault),
    .candidate_path_fault                 (candidate_path_fault),
    .candidate_fifo_stored_count          (candidate_fifo_stored_count),
    .candidate_fifo_maximum_stored_count  (candidate_fifo_maximum_stored_count)
  );

  task automatic fail(input string message);
    begin
      $display("IQ_TO_SCORE_XFFT_FAIL %0s cycle=%0d samples=%0d forward=%0d product=%0d inverse=%0d scores=%0d faults=%0b%0b%0b%0b%0b%0b",
               message, cycle_count, driven_samples, forward_count,
               product_count, inverse_count, score_count, forward_fft_fault,
               kernel_join_fault, product_overflow_fault, inverse_fft_fault,
               forward_exponent_fault, candidate_path_fault);
      $fatal(1);
    end
  endtask

  always @(negedge clk) begin
    if (resetn && enable)
      score_ready = (cycle_count % 17) != 5 && (cycle_count % 29) != 13;
  end

  always @(posedge clk) begin
    cycle_count = cycle_count + 1;
    if (cycle_count > 200000)
      fail("simulation watchdog expired");

    if (resetn && enable) begin
      if (!expected_fault_window &&
          (detector_fault || scheduler_gap_pulse ||
          scheduler_index_error_pulse || scheduler_overflow_pulse ||
          forward_fft_fault || kernel_join_fault ||
          product_overflow_fault || inverse_fft_fault ||
          forward_exponent_fault || candidate_path_fault))
        fail("unexpected fail-closed event");

      if (sample_valid)
        driven_samples = driven_samples + 1;

      if (dut.forward_output_valid && dut.forward_output_ready) begin
        if (forward_count >= BLOCK_COUNT * FFT_SAMPLES)
          fail("too many forward-XFFT outputs");
        block_number = forward_count / FFT_SAMPLES;
        block_position = forward_count % FFT_SAMPLES;
        if ({dut.forward_output_q, dut.forward_output_i} !==
            expected_forward[forward_count])
          fail("forward-XFFT value mismatch");
        if (dut.forward_output_position !== block_position[8:0] ||
            dut.forward_output_exponent !==
              expected_forward_exponents[block_number] ||
            dut.forward_output_last !== (block_position == FFT_SAMPLES - 1) ||
            dut.forward_output_block_start !==
              FIRST_SAMPLE_INDEX + block_number * 447)
          fail("forward-XFFT metadata mismatch");
        forward_count = forward_count + 1;
      end

      if (dut.product_output_valid && dut.product_output_ready) begin
        if (product_count >= BLOCK_COUNT * FFT_SAMPLES)
          fail("too many spectrum-product outputs");
        block_number = product_count / FFT_SAMPLES;
        block_position = product_count % FFT_SAMPLES;
        if ({dut.product_output_q, dut.product_output_i} !==
            expected_product[product_count])
          fail("spectrum-product value mismatch");
        if (dut.product_output_bin_index !== block_position[8:0] ||
            dut.product_output_exponent !==
              expected_forward_exponents[block_number] ||
            dut.product_output_last !== (block_position == FFT_SAMPLES - 1) ||
            dut.product_output_block_start !==
              FIRST_SAMPLE_INDEX + block_number * 447 ||
            dut.product_output_overflow)
          fail("spectrum-product metadata or overflow mismatch");
        product_count = product_count + 1;
      end

      if (dut.inverse_output_valid && dut.inverse_output_ready) begin
        if (inverse_count >= BLOCK_COUNT * FFT_SAMPLES)
          fail("too many inverse-XFFT outputs");
        block_number = inverse_count / FFT_SAMPLES;
        block_position = inverse_count % FFT_SAMPLES;
        if ({dut.inverse_output_q, dut.inverse_output_i} !==
            expected_inverse[inverse_count])
          fail("inverse-XFFT value mismatch");
        if (dut.inverse_output_position !== block_position[8:0] ||
            dut.inverse_output_exponent !==
              expected_inverse_exponents[block_number] ||
            dut.inverse_output_last !== (block_position == FFT_SAMPLES - 1) ||
            dut.inverse_output_block_start !==
              FIRST_SAMPLE_INDEX + block_number * 447)
          fail("inverse-XFFT metadata mismatch");
        inverse_count = inverse_count + 1;
      end

      if (score_stalled_last_cycle &&
          {score_denominator_zero, score_value, score_start_index} !==
          stalled_score_payload)
        fail("score payload changed while stalled");
      score_stalled_last_cycle = score_valid && !score_ready;
      stalled_score_payload = {
        score_denominator_zero, score_value, score_start_index
      };

      if (score_valid && score_ready) begin
        if (score_count >= SCORE_COUNT)
          fail("too many normalized scores");
        if (score_value !== expected_scores[score_count])
          fail("normalized score mismatch");
        if (score_start_index !== FIRST_SAMPLE_INDEX + score_count ||
            score_denominator_zero)
          fail("normalized score metadata mismatch");
        score_count = score_count + 1;
      end
    end
  end

  initial begin
    $readmemh("samples_ci16.mem", input_samples);
    $readmemh("forward_q23.mem", expected_forward);
    $readmemh("product_q23.mem", expected_product);
    $readmemh("inverse_q23.mem", expected_inverse);
    $readmemh("forward_exponents.mem", expected_forward_exponents);
    $readmemh("inverse_exponents.mem", expected_inverse_exponents);
    $readmemh("scores_u8.mem", expected_scores);

    if (expected_scores[100] !== 8'hff ||
        expected_scores[447] !== 8'hff ||
        expected_scores[1000] !== 8'hff)
      fail("vector set does not contain all three full-scale PSS controls");

    repeat (8) @(posedge clk);
    @(negedge clk);
    resetn = 1'b1;
    enable = 1'b1;

    for (drive_index = 0; drive_index < SAMPLE_COUNT;) begin
      @(negedge clk);
      sample_valid = 1'b0;
      cadence_phase = cadence_phase + 15;
      if (cadence_phase >= 100) begin
        cadence_phase = cadence_phase - 100;
        sample_i = input_samples[drive_index][15:0];
        sample_q = input_samples[drive_index][31:16];
        sample_index = FIRST_SAMPLE_INDEX + drive_index;
        sample_valid = 1'b1;
        drive_index = drive_index + 1;
      end
    end
    @(negedge clk);
    sample_valid = 1'b0;

    begin : wait_for_all_scores
      forever begin
        @(negedge clk);
        if (score_count == SCORE_COUNT)
          disable wait_for_all_scores;
      end
    end
    repeat (20) @(posedge clk);
    @(negedge clk);

    if (driven_samples != SAMPLE_COUNT ||
        forward_count != BLOCK_COUNT * FFT_SAMPLES ||
        product_count != BLOCK_COUNT * FFT_SAMPLES ||
        inverse_count != BLOCK_COUNT * FFT_SAMPLES ||
        score_count != SCORE_COUNT)
      fail("end-to-end count mismatch");
    if (candidate_fifo_maximum_stored_count >= 512)
      fail("candidate FIFO exhausted its declared capacity");
    observed_max_fifo = candidate_fifo_maximum_stored_count;

    // Prove that a real generated-core event reaches the registered global
    // quarantine, suppresses publication, and can be recovered only through
    // the declared disable/re-enable lifecycle.
    expected_fault_window = 1'b1;
    force dut.forward_adapter.protocol_fault = 1'b1;
    @(posedge clk);
    @(negedge clk);
    repeat (2) @(posedge clk);
    @(negedge clk);
    if (!forward_fft_fault || !detector_fault || score_valid)
      fail("global fault quarantine did not close publication");
    release dut.forward_adapter.protocol_fault;
    enable = 1'b0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    if (detector_fault || forward_fft_fault || score_valid)
      fail("disable did not clear the global quarantine");
    enable = 1'b1;
    repeat (8) @(posedge clk);
    @(negedge clk);
    expected_fault_window = 1'b0;
    if (detector_fault || forward_fft_fault || score_valid)
      fail("detector did not return to an idle configured state");

    $display("IQ_TO_SCORE_XFFT_PASS samples=%0d blocks=%0d forward=%0d product=%0d inverse=%0d scores=%0d pss255=3 max_fifo=%0d score_stalls=1 global_fault_recovery=1",
             driven_samples, BLOCK_COUNT, forward_count, product_count,
             inverse_count, score_count, observed_max_fifo);
    $finish;
  end

endmodule
