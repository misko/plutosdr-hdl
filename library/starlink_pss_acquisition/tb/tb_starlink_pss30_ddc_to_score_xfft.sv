`timescale 1ns/1ps

module tb_starlink_pss30_ddc_to_score_xfft #(
  parameter integer SOURCE_RATE_MSPS = 30
);

  localparam integer SOURCE_SAMPLE_COUNT =
      (SOURCE_RATE_MSPS == 60) ? 5666 : 2826;
  localparam integer ACQUISITION_SAMPLE_COUNT = 1406;
  localparam integer BLOCK_COUNT = 3;
  localparam integer FFT_SAMPLES = 512;
  localparam integer DATA_WIDTH = 18;
  localparam integer SCORE_COUNT = 1341;
  localparam [63:0] FIRST_SOURCE_INDEX =
      (SOURCE_RATE_MSPS == 60) ? 64'd4000000 : 64'd2000000;
  localparam [63:0] FIRST_ACQUISITION_INDEX =
      (SOURCE_RATE_MSPS == 60) ? 64'd1000006 : 64'd1000004;
  localparam [30:0] COEFFICIENT_ENERGY =
      (SOURCE_RATE_MSPS == 60) ? 31'd1073765335 : 31'd1073744004;
  localparam KERNEL_ROM_FILE = (SOURCE_RATE_MSPS == 60) ?
      "upper_edge_pss60_x4_ddc_kernel_q17.mem" :
      "upper_edge_pss30_x2_ddc_kernel_q17.mem";

  reg clk = 1'b0;
  always #5 clk = ~clk;
  reg resetn = 1'b0;
  reg enable = 1'b0;
  reg flush = 1'b0;
  reg source_valid = 1'b0;
  reg source_gap = 1'b0;
  reg signed [15:0] source_i = 16'sd0;
  reg signed [15:0] source_q = 16'sd0;
  reg [63:0] source_index = 64'd0;
  reg score_ready = 1'b1;

  wire ddc_enable;
  wire ddc_valid;
  wire ddc_gap;
  wire signed [15:0] ddc_i;
  wire signed [15:0] ddc_q;
  wire [63:0] ddc_index;
  wire [31:0] ddc_accepted_count;
  wire [31:0] ddc_emitted_count;
  wire [31:0] ddc_discontinuity_count;
  wire [31:0] ddc_saturation_count;

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

  reg [31:0] source_samples [0:SOURCE_SAMPLE_COUNT-1];
  reg [31:0] expected_ddc [0:ACQUISITION_SAMPLE_COUNT-1];
  reg [2*DATA_WIDTH-1:0] expected_forward [0:BLOCK_COUNT*FFT_SAMPLES-1];
  reg [2*DATA_WIDTH-1:0] expected_product [0:BLOCK_COUNT*FFT_SAMPLES-1];
  reg [2*DATA_WIDTH-1:0] expected_inverse [0:BLOCK_COUNT*FFT_SAMPLES-1];
  reg [4:0] expected_forward_exponents [0:BLOCK_COUNT-1];
  reg [4:0] expected_inverse_exponents [0:BLOCK_COUNT-1];
  reg [7:0] expected_scores [0:SCORE_COUNT-1];

  wire stage_30_enable;
  wire stage_30_valid;
  wire stage_30_gap;
  wire signed [15:0] stage_30_i;
  wire signed [15:0] stage_30_q;
  wire [63:0] stage_30_index;
  wire [31:0] stage_60_accepted_count;
  wire [31:0] stage_60_emitted_count;
  wire [31:0] stage_60_discontinuity_count;
  wire [31:0] stage_60_saturation_count;

  starlink_pss_x2_ddc #(
    .EDGE_UPPER(1)
  ) first_ddc_stage (
    .clk                    (clk),
    .resetn                 (resetn),
    .enable                 (enable),
    .flush                  (flush),
    .input_valid            (source_valid),
    .input_gap              (source_gap),
    .input_i                (source_i),
    .input_q                (source_q),
    .input_index            (source_index),
    .output_enable          (stage_30_enable),
    .output_valid           (stage_30_valid),
    .output_gap             (stage_30_gap),
    .output_i               (stage_30_i),
    .output_q               (stage_30_q),
    .output_index           (stage_30_index),
    .accepted_sample_count  (stage_60_accepted_count),
    .emitted_sample_count   (stage_60_emitted_count),
    .discontinuity_count    (stage_60_discontinuity_count),
    .saturation_event_count (stage_60_saturation_count)
  );

  generate
    if (SOURCE_RATE_MSPS == 30) begin : g_rate_30
      assign ddc_enable = stage_30_enable;
      assign ddc_valid = stage_30_valid;
      assign ddc_gap = stage_30_gap;
      assign ddc_i = stage_30_i;
      assign ddc_q = stage_30_q;
      assign ddc_index = stage_30_index;
      assign ddc_accepted_count = stage_60_accepted_count;
      assign ddc_emitted_count = stage_60_emitted_count;
      assign ddc_discontinuity_count = stage_60_discontinuity_count;
      assign ddc_saturation_count = stage_60_saturation_count;
    end else begin : g_rate_60
      wire [31:0] final_accepted_count;
      wire [31:0] final_saturation_count;
      wire [32:0] saturation_sum =
          {1'b0, stage_60_saturation_count} +
          {1'b0, final_saturation_count};
      starlink_pss_x2_ddc #(
        .EDGE_UPPER(1)
      ) second_ddc_stage (
        .clk                    (clk),
        .resetn                 (resetn),
        .enable                 (enable),
        .flush                  (flush),
        .input_valid            (stage_30_valid),
        .input_gap              (stage_30_gap),
        .input_i                (stage_30_i),
        .input_q                (stage_30_q),
        .input_index            (stage_30_index),
        .output_enable          (ddc_enable),
        .output_valid           (ddc_valid),
        .output_gap             (ddc_gap),
        .output_i               (ddc_i),
        .output_q               (ddc_q),
        .output_index           (ddc_index),
        .accepted_sample_count  (final_accepted_count),
        .emitted_sample_count   (ddc_emitted_count),
        .discontinuity_count    (ddc_discontinuity_count),
        .saturation_event_count (final_saturation_count)
      );
      assign ddc_accepted_count = stage_60_accepted_count;
      assign ddc_saturation_count = saturation_sum[32] ?
          32'hffff_ffff : saturation_sum[31:0];
      wire unused_stage_evidence = ^{
        stage_60_emitted_count, stage_60_discontinuity_count,
        final_accepted_count
      };
    end
  endgenerate

  starlink_pss_iq_to_score #(
    .KERNEL_ROM_FILE   (KERNEL_ROM_FILE),
    .COEFFICIENT_ENERGY(COEFFICIENT_ENERGY),
    .DATA_WIDTH        (DATA_WIDTH)
  ) scorer (
    .clk                                  (clk),
    .resetn                               (resetn),
    .enable                               (enable),
    .flush                                (flush),
    .sample_valid                         (ddc_valid),
    .sample_gap                           (ddc_gap),
    .sample_i                             (ddc_i),
    .sample_q                             (ddc_q),
    .sample_index                         (ddc_index),
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

  integer cycle_count = 0;
  integer driven_sources = 0;
  integer ddc_count = 0;
  integer forward_count = 0;
  integer product_count = 0;
  integer inverse_count = 0;
  integer score_count = 0;
  integer scheduler_gap_count = 0;
  integer drive_index;
  integer cadence_phase = 0;
  integer block_number;
  integer block_position;
  reg score_stalled_last_cycle = 1'b0;
  reg [72:0] stalled_score_payload = 73'd0;

  task automatic fail(input string message);
    begin
      $display("PSS_DDC_XFFT_FAIL rate=%0d %0s cycle=%0d source=%0d ddc=%0d forward=%0d product=%0d inverse=%0d scores=%0d faults=%0b%0b%0b%0b%0b%0b",
               SOURCE_RATE_MSPS, message, cycle_count, driven_sources, ddc_count, forward_count,
               product_count, inverse_count, score_count, forward_fft_fault,
               kernel_join_fault, product_overflow_fault, inverse_fft_fault,
               forward_exponent_fault, candidate_path_fault);
      $fatal(1);
      $finish;
    end
  endtask

  always @(negedge clk) begin
    if (resetn && enable)
      score_ready = (cycle_count % 17) != 5 && (cycle_count % 29) != 13;
  end

  always @(posedge clk) begin
    cycle_count = cycle_count + 1;
    if (cycle_count > 250000)
      fail("simulation watchdog expired");

    if (resetn && enable) begin
      if (detector_fault || scheduler_index_error_pulse ||
          scheduler_overflow_pulse || forward_fft_fault ||
          kernel_join_fault || product_overflow_fault || inverse_fft_fault ||
          forward_exponent_fault || candidate_path_fault)
        fail("unexpected fail-closed event");
      if (scheduler_gap_pulse)
        scheduler_gap_count = scheduler_gap_count + 1;
      if (source_valid)
        driven_sources = driven_sources + 1;

      if (ddc_valid) begin
        if (ddc_count >= ACQUISITION_SAMPLE_COUNT)
          fail("too many DDC outputs");
        if ({ddc_q, ddc_i} !== expected_ddc[ddc_count])
          fail("DDC value mismatch");
        if (ddc_index !== FIRST_ACQUISITION_INDEX + ddc_count ||
            ddc_gap !== (ddc_count == 0))
          fail("DDC index/gap mismatch");
        ddc_count = ddc_count + 1;
      end

      if (scorer.forward_output_valid && scorer.forward_output_ready) begin
        if (forward_count >= BLOCK_COUNT * FFT_SAMPLES)
          fail("too many forward-XFFT outputs");
        block_number = forward_count / FFT_SAMPLES;
        block_position = forward_count % FFT_SAMPLES;
        if ({scorer.forward_output_q, scorer.forward_output_i} !==
            expected_forward[forward_count])
          fail("forward-XFFT value mismatch");
        if (scorer.forward_output_position !== block_position[8:0] ||
            scorer.forward_output_exponent !== expected_forward_exponents[block_number] ||
            scorer.forward_output_last !== (block_position == FFT_SAMPLES - 1) ||
            scorer.forward_output_block_start !==
              FIRST_ACQUISITION_INDEX + block_number * 447)
          fail("forward-XFFT metadata mismatch");
        forward_count = forward_count + 1;
      end

      if (scorer.product_output_valid && scorer.product_output_ready) begin
        if (product_count >= BLOCK_COUNT * FFT_SAMPLES)
          fail("too many spectrum-product outputs");
        block_number = product_count / FFT_SAMPLES;
        block_position = product_count % FFT_SAMPLES;
        if ({scorer.product_output_q, scorer.product_output_i} !==
            expected_product[product_count])
          fail("spectrum-product value mismatch");
        if (scorer.product_output_bin_index !== block_position[8:0] ||
            scorer.product_output_exponent !== expected_forward_exponents[block_number] ||
            scorer.product_output_last !== (block_position == FFT_SAMPLES - 1) ||
            scorer.product_output_block_start !==
              FIRST_ACQUISITION_INDEX + block_number * 447 ||
            scorer.product_output_overflow)
          fail("spectrum-product metadata or overflow mismatch");
        product_count = product_count + 1;
      end

      if (scorer.inverse_output_valid && scorer.inverse_output_ready) begin
        if (inverse_count >= BLOCK_COUNT * FFT_SAMPLES)
          fail("too many inverse-XFFT outputs");
        block_number = inverse_count / FFT_SAMPLES;
        block_position = inverse_count % FFT_SAMPLES;
        if ({scorer.inverse_output_q, scorer.inverse_output_i} !==
            expected_inverse[inverse_count])
          fail("inverse-XFFT value mismatch");
        if (scorer.inverse_output_position !== block_position[8:0] ||
            scorer.inverse_output_exponent !== expected_inverse_exponents[block_number] ||
            scorer.inverse_output_last !== (block_position == FFT_SAMPLES - 1) ||
            scorer.inverse_output_block_start !==
              FIRST_ACQUISITION_INDEX + block_number * 447)
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
        if (score_start_index !== FIRST_ACQUISITION_INDEX + score_count ||
            score_denominator_zero)
          fail("normalized score metadata mismatch");
        score_count = score_count + 1;
      end
    end
  end

  initial begin
    $readmemh("source_ci16.mem", source_samples);
    $readmemh("ddc_ci16.mem", expected_ddc);
    $readmemh("forward_q17.mem", expected_forward);
    $readmemh("product_q17.mem", expected_product);
    $readmemh("inverse_q17.mem", expected_inverse);
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
    #1;
    if (!ddc_enable)
      fail("DDC did not advertise enable");

    for (drive_index = 0; drive_index < SOURCE_SAMPLE_COUNT;) begin
      @(negedge clk);
      source_valid = 1'b0;
      source_gap = 1'b0;
      cadence_phase = cadence_phase + SOURCE_RATE_MSPS;
      if (cadence_phase >= 100) begin
        cadence_phase = cadence_phase - 100;
        source_i = source_samples[drive_index][15:0];
        source_q = source_samples[drive_index][31:16];
        source_index = FIRST_SOURCE_INDEX + drive_index;
        source_gap = drive_index == 0;
        source_valid = 1'b1;
        drive_index = drive_index + 1;
      end
    end
    @(negedge clk);
    source_valid = 1'b0;
    source_gap = 1'b0;

    begin : wait_for_all_scores
      forever begin
        @(negedge clk);
        if (score_count == SCORE_COUNT)
          disable wait_for_all_scores;
      end
    end
    repeat (20) @(posedge clk);
    @(negedge clk);

    if (driven_sources != SOURCE_SAMPLE_COUNT ||
        ddc_count != ACQUISITION_SAMPLE_COUNT ||
        forward_count != BLOCK_COUNT * FFT_SAMPLES ||
        product_count != BLOCK_COUNT * FFT_SAMPLES ||
        inverse_count != BLOCK_COUNT * FFT_SAMPLES || score_count != SCORE_COUNT)
      fail("end-to-end count mismatch");
    if (scheduler_gap_count != 1)
      fail("startup discontinuity did not produce exactly one scheduler gap");
    if (ddc_accepted_count != SOURCE_SAMPLE_COUNT ||
        ddc_emitted_count != ACQUISITION_SAMPLE_COUNT ||
        ddc_discontinuity_count != 1 || ddc_saturation_count != 0)
      fail("DDC telemetry mismatch");
    if (candidate_fifo_maximum_stored_count >= 512)
      fail("candidate FIFO exhausted its declared capacity");

    $display("PSS_DDC_XFFT_PASS rate=%0d source=%0d ddc=%0d blocks=%0d scores=%0d pss255=3 first_source=%0d first_score=%0d scheduler_gaps=1 max_fifo=%0d",
             SOURCE_RATE_MSPS, driven_sources, ddc_count, BLOCK_COUNT, score_count,
             FIRST_SOURCE_INDEX, FIRST_ACQUISITION_INDEX,
             candidate_fifo_maximum_stored_count);
    $finish;
  end

endmodule
