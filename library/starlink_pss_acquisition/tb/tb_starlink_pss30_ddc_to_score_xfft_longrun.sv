`timescale 1ns/1ps

// Long-horizon protocol/capacity test for the complete 30 -> 15 MS/s DDC and
// generated dual-XFFT path.  The three-block bit-exact replay covers numeric
// accuracy; this test deliberately extends a clean cold-start stream far
// enough to expose faults that accumulate only after several blocks.
module tb_starlink_pss30_ddc_to_score_xfft_longrun;

  localparam integer BLOCK_COUNT = 64;
  localparam integer FFT_SAMPLES = 512;
  localparam integer VALID_RESULTS_PER_BLOCK = 447;
  localparam integer ACQUISITION_SAMPLE_COUNT = FFT_SAMPLES +
      (BLOCK_COUNT - 1) * VALID_RESULTS_PER_BLOCK;
  localparam integer SOURCE_SAMPLE_COUNT =
      2 * ACQUISITION_SAMPLE_COUNT + 14;
  localparam integer SCORE_COUNT = BLOCK_COUNT * VALID_RESULTS_PER_BLOCK;
  localparam [63:0] FIRST_SOURCE_INDEX = 64'd2000000;
  localparam [63:0] FIRST_ACQUISITION_INDEX = 64'd1000004;

  reg clk = 1'b0;
  reg resetn = 1'b0;
  reg enable = 1'b0;
  reg flush = 1'b0;
  reg source_valid = 1'b0;
  reg source_gap = 1'b0;
  reg signed [15:0] source_i = 0;
  reg signed [15:0] source_q = 0;
  reg [63:0] source_index = 0;

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
  integer observed_max_fifo = 0;
  reg fault_seen = 1'b0;

  always #5 clk = ~clk;

  starlink_pss_x2_ddc #(
    .EDGE_UPPER(1)
  ) ddc (
    .clk                    (clk),
    .resetn                 (resetn),
    .enable                 (enable),
    .flush                  (flush),
    .input_valid            (source_valid),
    .input_gap              (source_gap),
    .input_i                (source_i),
    .input_q                (source_q),
    .input_index            (source_index),
    .output_enable          (),
    .output_valid           (ddc_valid),
    .output_gap             (ddc_gap),
    .output_i               (ddc_i),
    .output_q               (ddc_q),
    .output_index           (ddc_index),
    .accepted_sample_count  (ddc_accepted_count),
    .emitted_sample_count   (ddc_emitted_count),
    .discontinuity_count    (ddc_discontinuity_count),
    .saturation_event_count (ddc_saturation_count)
  );

  starlink_pss_iq_to_score #(
    .KERNEL_ROM_FILE   ("upper_edge_pss30_x2_ddc_kernel_q17.mem"),
    .COEFFICIENT_ENERGY(31'd1073744004),
    .DATA_WIDTH        (18)
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
    .score_ready                          (1'b1),
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

  task automatic report_and_fail(input string cause);
    begin
      if (!fault_seen) begin
        fault_seen = 1'b1;
        $display("PSS30_DDC_XFFT_LONGRUN_FAULT cause=%0s cycle=%0d source=%0d ddc=%0d forward=%0d product=%0d inverse=%0d scores=%0d fifo=%0d fifo_max=%0d cache_count=%0d cache_oldest=%0d cache_newest=%0d next_score=%0d gaps=%0d",
                 cause, cycle_count, driven_sources, ddc_count,
                 forward_count, product_count, inverse_count, score_count,
                 candidate_fifo_stored_count,
                 candidate_fifo_maximum_stored_count,
                 scorer.energy_cache.stored_energy_count,
                 scorer.energy_cache.oldest_energy_start_index,
                 scorer.energy_cache.newest_energy_start_index,
                 FIRST_ACQUISITION_INDEX + score_count,
                 scheduler_gap_count);
        $finish;
      end
    end
  endtask

  // Preserve the first leaf cause after nonblocking updates.  The source is
  // contiguous from its first sample, so any scheduler gap is a fault.
  always @(negedge clk) begin
    if (resetn && enable) begin
      if (scorer.candidate_score_path.ifft_protocol_fault)
        report_and_fail("ifft_qualifier");
      if (scorer.candidate_score_path.fifo_overflow_fault)
        report_and_fail("raw_result_fifo_overflow");
      if (scorer.candidate_score_path.energy_join.cache_miss_pulse)
        report_and_fail("energy_cache_miss");
      if (scorer.candidate_score_path.energy_join.index_mismatch_pulse)
        report_and_fail("energy_index_mismatch");
      if (scorer.candidate_score_path.energy_join.orphan_response_pulse)
        report_and_fail("energy_orphan_response");
      if (scorer.candidate_score_path.energy_join_fault)
        report_and_fail("energy_join_unspecified");
      if (scorer.candidate_backpressure_fault)
        report_and_fail("inverse_elastic_boundary_backpressure");
      if (forward_fft_fault)
        report_and_fail("forward_fft");
      if (kernel_join_fault)
        report_and_fail("kernel_join");
      if (product_overflow_fault)
        report_and_fail("spectrum_product_overflow");
      if (inverse_fft_fault)
        report_and_fail("inverse_fft");
      if (forward_exponent_fault)
        report_and_fail("forward_exponent_metadata");
      if (scheduler_gap_count > 0)
        report_and_fail("scheduler_gap");
      if (scheduler_index_error_pulse)
        report_and_fail("scheduler_index");
      if (scheduler_overflow_pulse)
        report_and_fail("scheduler_overflow");
      if (detector_fault || candidate_path_fault)
        report_and_fail("global_or_candidate_unspecified");
    end
  end

  always @(posedge clk) begin
    cycle_count = cycle_count + 1;
    if (cycle_count > 2000000)
      report_and_fail("simulation_watchdog");
    if (resetn && enable) begin
      if (source_valid)
        driven_sources = driven_sources + 1;
      if (ddc_valid)
        ddc_count = ddc_count + 1;
      if (scorer.forward_output_valid && scorer.forward_output_ready)
        forward_count = forward_count + 1;
      if (scorer.product_output_valid && scorer.product_output_ready)
        product_count = product_count + 1;
      if (scorer.inverse_output_valid && scorer.inverse_output_ready)
        inverse_count = inverse_count + 1;
      if (scheduler_gap_pulse)
        scheduler_gap_count = scheduler_gap_count + 1;
      if (candidate_fifo_stored_count > observed_max_fifo)
        observed_max_fifo = candidate_fifo_stored_count;
      if (score_valid) begin
        if (score_start_index !== FIRST_ACQUISITION_INDEX + score_count)
          report_and_fail("score_index_order");
        if (score_denominator_zero)
          report_and_fail("zero_denominator");
        score_count = score_count + 1;
        if (score_count % VALID_RESULTS_PER_BLOCK == 0)
          $display("PSS30_DDC_XFFT_LONGRUN_PROGRESS block=%0d scores=%0d cycle=%0d fifo_max=%0d",
                   score_count / VALID_RESULTS_PER_BLOCK, score_count,
                   cycle_count, observed_max_fifo);
      end
    end
  end

  initial begin
    repeat (8) @(posedge clk);
    @(negedge clk);
    resetn = 1'b1;
    enable = 1'b1;

    for (drive_index = 0; drive_index < SOURCE_SAMPLE_COUNT;) begin
      @(negedge clk);
      source_valid = 1'b0;
      source_gap = 1'b0;
      cadence_phase = cadence_phase + 30;
      if (cadence_phase >= 100) begin
        cadence_phase = cadence_phase - 100;
        source_i = 16'sd1000 + (drive_index % 251);
        source_q = -16'sd700 + (drive_index % 199);
        source_index = FIRST_SOURCE_INDEX + drive_index;
        source_gap = 1'b0;
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

    if (driven_sources != SOURCE_SAMPLE_COUNT ||
        ddc_count != ACQUISITION_SAMPLE_COUNT ||
        forward_count != BLOCK_COUNT * FFT_SAMPLES ||
        product_count != BLOCK_COUNT * FFT_SAMPLES ||
        inverse_count != BLOCK_COUNT * FFT_SAMPLES ||
        score_count != SCORE_COUNT)
      report_and_fail("end_to_end_count");
    if (scheduler_gap_count != 0)
      report_and_fail("clean_startup_gap");
    if (ddc_accepted_count != SOURCE_SAMPLE_COUNT ||
        ddc_emitted_count != ACQUISITION_SAMPLE_COUNT ||
        ddc_discontinuity_count != 0 || ddc_saturation_count != 0)
      report_and_fail("ddc_telemetry");
    if (observed_max_fifo >= 512)
      report_and_fail("fifo_capacity_exhausted");

    $display("PSS30_DDC_XFFT_LONGRUN_PASS source=%0d ddc=%0d blocks=%0d scores=%0d gaps=%0d fifo_max=%0d",
             driven_sources, ddc_count, BLOCK_COUNT, score_count,
             scheduler_gap_count, observed_max_fifo);
    $finish;
  end

endmodule
