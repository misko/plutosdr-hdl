`timescale 1ns/1ps

// Recorded samples: no planted-PSS or detection assertion. Input origin is
// supplied by the strictly validated fixture manifest, never silently1M.
module tb_starlink_pss_recorded_iq_to_score_shared #(
  parameter [63:0] FIRST_SAMPLE_INDEX = 64'd0
);

  localparam integer SAMPLE_COUNT = 1406;
  localparam integer BLOCK_COUNT = 3;
  localparam integer FFT_SAMPLES = 512;
  localparam integer DATA_WIDTH = 18;
  localparam integer SCORE_COUNT = 1341;

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
  reg [2*DATA_WIDTH-1:0] expected_forward [0:BLOCK_COUNT*FFT_SAMPLES-1];
  reg [2*DATA_WIDTH-1:0] expected_product [0:BLOCK_COUNT*FFT_SAMPLES-1];
  reg [2*DATA_WIDTH-1:0] expected_inverse [0:BLOCK_COUNT*FFT_SAMPLES-1];
  reg [4:0] expected_forward_exponents [0:BLOCK_COUNT-1];
  reg [4:0] expected_inverse_exponents [0:BLOCK_COUNT-1];
  reg [7:0] expected_scores [0:SCORE_COUNT-1];
  reg expected_zero [0:SCORE_COUNT-1];
  integer energy_index, energy_tap, energy_i, energy_q;
  reg [63:0] energy_sum;
  integer stalled_cycles = 0;

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
  reg fft_clk = 0;
  reg fft_resetn = 1;
  initial begin #1.3; forever #2.5 fft_clk = !fft_clk; end

  starlink_pss_iq_to_score_shared #(.USE_REALTIME_XFFT(1)) dut (
    .fft_clk(fft_clk), .fft_resetn(fft_resetn),
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
      $display("RECORDED_SCORE_FAIL %0s cycle=%0d samples=%0d forward=%0d product=%0d inverse=%0d scores=%0d faults=%0b%0b%0b%0b%0b%0b",
               message, cycle_count, driven_samples, forward_count,
               product_count, inverse_count, score_count, forward_fft_fault,
               kernel_join_fault, product_overflow_fault, inverse_fft_fault,
               forward_exponent_fault, candidate_path_fault);
      $fatal(1, "RECORDED_SCORE_FAIL");
      $finish; // Explicit fallback for simulator modes that do not halt at $fatal.
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

      if (score_stalled_last_cycle && (!score_valid ||
          {score_denominator_zero, score_value, score_start_index} !==
          stalled_score_payload))
        fail("score payload changed while stalled");
      if (score_valid && !score_ready) stalled_cycles = stalled_cycles + 1;
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
            score_denominator_zero !== expected_zero[score_count])
          fail("normalized score metadata mismatch");
        score_count = score_count + 1;
      end
    end
  end

  initial begin
    $readmemh("samples_ci16.mem", input_samples);
    $readmemh("forward_q17.mem", expected_forward);
    $readmemh("product_q17.mem", expected_product);
    $readmemh("inverse_q17.mem", expected_inverse);
    $readmemh("forward_exponents.mem", expected_forward_exponents);
    $readmemh("inverse_exponents.mem", expected_inverse_exponents);
    $readmemh("scores_u8.mem", expected_scores);

    if (FIRST_SAMPLE_INDEX > 64'hffffffffffffffff - (SAMPLE_COUNT - 1))
      fail("recorded source index would wrap");
    for (energy_index = 0; energy_index < SCORE_COUNT; energy_index = energy_index + 1) begin
      energy_sum = 0;
      for (energy_tap = 0; energy_tap < 66; energy_tap = energy_tap + 1) begin
        energy_i = $signed(input_samples[energy_index + energy_tap][15:0]);
        energy_q = $signed(input_samples[energy_index + energy_tap][31:16]);
        energy_sum = energy_sum + energy_i * energy_i;
        energy_sum = energy_sum + energy_q * energy_q;
      end
      expected_zero[energy_index] = energy_sum == 0;
    end
    $display("RECORDED_SCORE_ORIGIN first_canonical_index=%016h sample_count=1406", FIRST_SAMPLE_INDEX);

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

    // Inject a checker diagnostic after the real-core numerical replay. This
    // tests global quarantine/recovery, NOT vendor event generation or latency.
    expected_fault_window = 1'b1;
    force dut.realtime_transform.transform_service.input_guard.protocol_fault = 1'b1;
    @(posedge clk);
    @(negedge clk);
    repeat (12) @(posedge clk);
    @(negedge clk);
    if (!detector_fault || score_valid)
      fail("global fault quarantine did not close publication");
    release dut.realtime_transform.transform_service.input_guard.protocol_fault;
    enable = 1'b0;
    repeat (12) @(posedge clk);
    @(negedge clk);
    if (detector_fault || forward_fft_fault || score_valid)
      fail("disable did not clear the global quarantine");
    enable = 1'b1;
    repeat (8) @(posedge clk);
    @(negedge clk);
    expected_fault_window = 1'b0;
    if (detector_fault || forward_fft_fault || score_valid)
      fail("detector did not return to an idle configured state");

    $display("RECORDED_SCORE_FAULT_RECOVERY_PASS injected_checker_fault=1 explicit_recovery=1");
    expected_fault_window = 1;
    fft_resetn = 0;
    repeat (12) @(negedge clk);
    if (!detector_fault || score_valid)
      fail("independent FFT reset did not quarantine acquisition");
    fft_resetn = 1;
    repeat (12) @(negedge clk);
    if (!detector_fault || score_valid)
      fail("FFT reset quarantine cleared without explicit recovery");
    enable = 0;
    repeat (12) @(negedge clk);
    enable = 1;
    repeat (12) @(negedge clk);
    expected_fault_window = 0;
    if (detector_fault || score_valid)
      fail("FFT reset recovery failed");
    if (stalled_cycles == 0)
      fail("no actual score backpressure observed");
    $display("RECORDED_SCORE_FFT_RESET_PASS sticky_quarantine=1 explicit_recovery=1");
    $display("RECORDED_SCORE_REPLAY_PASS samples=1406 blocks=3 forward=1536 product=1536 inverse=1536 scores=1341 exact_metadata=1 score_stalls=1 NO_PSS_DETECTION_OR_CAPACITY_CLAIM");
    $display("RECORDED_SCORE_COUNTS first_canonical_index=%016h stalled_cycles=%0d max_fifo=%0d",
             FIRST_SAMPLE_INDEX, stalled_cycles, observed_max_fifo);
    $finish;
  end

endmodule
