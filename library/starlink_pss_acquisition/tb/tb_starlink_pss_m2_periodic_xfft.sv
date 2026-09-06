`timescale 1ns/1ps

module tb_starlink_pss_m2_periodic_xfft;

  localparam integer SAMPLE_COUNT = 20180;
  localparam integer PERIOD_SCORE_COUNT = 20000;
  localparam integer SCORE_COUNT = 20115;
  localparam [63:0] FIRST_SAMPLE_INDEX = 64'd7000000;

  reg clk = 1'b0;
  always #5 clk = ~clk;
  reg resetn = 1'b0;
  reg enable = 1'b0;
  reg flush = 1'b0;
  reg sample_valid = 1'b0;
  reg sample_gap = 1'b0;
  reg signed [15:0] sample_i = 16'sd0;
  reg signed [15:0] sample_q = 16'sd0;
  reg [63:0] sample_index = 64'd0;

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
  reg [7:0] expected_scores [0:PERIOD_SCORE_COUNT-1];
  integer cycle_count = 0;
  integer driven_samples = 0;
  integer observed_scores = 0;
  integer drive_index;
  integer cadence_phase = 0;
  integer peak_count = 0;
  integer peak_phase = -1;

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
    .score_ready                          (1'b1),
    .score_value                          (score_value),
    .score_start_index                    (score_start_index),
    .score_denominator_zero              (score_denominator_zero),
    .detector_fault                      (detector_fault),
    .scheduler_gap_pulse                 (scheduler_gap_pulse),
    .scheduler_index_error_pulse         (scheduler_index_error_pulse),
    .scheduler_overflow_pulse            (scheduler_overflow_pulse),
    .forward_fft_fault                   (forward_fft_fault),
    .kernel_join_fault                   (kernel_join_fault),
    .product_overflow_fault              (product_overflow_fault),
    .inverse_fft_fault                   (inverse_fft_fault),
    .forward_exponent_fault              (forward_exponent_fault),
    .candidate_path_fault                (candidate_path_fault),
    .candidate_fifo_stored_count         (candidate_fifo_stored_count),
    .candidate_fifo_maximum_stored_count (candidate_fifo_maximum_stored_count)
  );

  task automatic fail(input string message);
    begin
      $display("M2_PERIODIC_XFFT_FAIL %0s cycle=%0d samples=%0d scores=%0d faults=%0b%0b%0b%0b%0b%0b",
               message, cycle_count, driven_samples, observed_scores,
               forward_fft_fault, kernel_join_fault, product_overflow_fault,
               inverse_fft_fault, forward_exponent_fault, candidate_path_fault);
      $fatal(1);
    end
  endtask

  always @(posedge clk) begin
    cycle_count = cycle_count + 1;
    if (cycle_count > 500000)
      fail("simulation watchdog expired");
    if (resetn && enable) begin
      if (detector_fault || scheduler_gap_pulse ||
          scheduler_index_error_pulse || scheduler_overflow_pulse ||
          forward_fft_fault || kernel_join_fault || product_overflow_fault ||
          inverse_fft_fault || forward_exponent_fault || candidate_path_fault)
        fail("unexpected fail-closed event");
      if (sample_valid)
        driven_samples = driven_samples + 1;
      if (score_valid) begin
        if (observed_scores >= SCORE_COUNT)
          fail("too many scores");
        if (observed_scores < PERIOD_SCORE_COUNT &&
            score_value !== expected_scores[observed_scores])
          fail("bit-exact score mismatch");
        if (score_start_index !== FIRST_SAMPLE_INDEX + observed_scores ||
            score_denominator_zero)
          fail("score metadata or denominator mismatch");
        if (observed_scores < PERIOD_SCORE_COUNT && score_value == 8'hff) begin
          peak_count = peak_count + 1;
          peak_phase = observed_scores;
        end
        observed_scores = observed_scores + 1;
      end
    end
  end

  initial begin
    $readmemh("m2_period_samples_ci16.mem", input_samples);
    $readmemh("m2_period_scores_u8.mem", expected_scores);
    if (expected_scores[32] != 8'hff)
      fail("periodic score control peak is absent");

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

    begin : wait_for_scores
      forever begin
        @(negedge clk);
        if (observed_scores == SCORE_COUNT)
          disable wait_for_scores;
      end
    end
    if (driven_samples != SAMPLE_COUNT || observed_scores != SCORE_COUNT ||
        peak_count != 1 || peak_phase != 32 ||
        candidate_fifo_stored_count != 0 ||
        candidate_fifo_maximum_stored_count == 0 ||
        candidate_fifo_maximum_stored_count > 512)
      fail("periodic end-to-end summary mismatch");

    $display("M2_PERIODIC_XFFT_PASS samples=%0d period_scores=%0d scheduled_scores=%0d unique_peak=%0d peak_value=255 fifo_peak=%0d zero_denominators=0",
             driven_samples, PERIOD_SCORE_COUNT, observed_scores, peak_phase,
             candidate_fifo_maximum_stored_count);
    $finish;
  end

endmodule
