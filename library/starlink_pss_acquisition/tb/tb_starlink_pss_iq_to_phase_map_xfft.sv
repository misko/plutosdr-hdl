`timescale 1ns/1ps

module tb_starlink_pss_iq_to_phase_map_xfft;

  localparam integer SAMPLE_COUNT = 1406;
  localparam integer BLOCK_COUNT = 3;
  localparam integer PHASE_BINS = 447;
  localparam integer PHASE_INDEX_WIDTH = 9;
  localparam integer SCORE_COUNT = BLOCK_COUNT * PHASE_BINS;
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
  reg map_read_request = 1'b0;
  reg map_read_bank = 1'b0;
  reg [PHASE_INDEX_WIDTH-1:0] map_read_index = 0;
  reg map_release = 1'b0;
  reg map_release_bank = 1'b0;

  wire [1:0] map_ready_mask;
  wire [31:0] map_generation_0;
  wire [31:0] map_generation_1;
  wire [63:0] map_start_index_0;
  wire [63:0] map_start_index_1;
  wire map_read_valid;
  wire [15:0] map_read_data;
  wire map_read_error;
  wire score_valid;
  wire [7:0] score_value;
  wire [63:0] score_start_index;
  wire [PHASE_INDEX_WIDTH-1:0] score_phase;
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
  wire [31:0] score_phase_index_discontinuity_count;
  wire [31:0] scheduler_gap_count;
  wire [31:0] scheduler_index_error_count;
  wire [31:0] scheduler_overflow_count;
  wire [31:0] detector_fault_count;
  wire [31:0] score_denominator_zero_count;
  wire [31:0] detector_health_flags;
  wire [31:0] accepted_score_count;
  wire [31:0] discarded_score_count;
  wire [31:0] discontinuity_abort_count;
  wire [31:0] map_publish_count;
  wire [31:0] map_overrun_count;
  wire [31:0] score_protocol_error_count;
  wire [31:0] map_arithmetic_overflow_count;
  wire [31:0] map_read_error_count;
  wire [31:0] map_release_error_count;

  reg [31:0] input_samples [0:SAMPLE_COUNT-1];
  reg [7:0] expected_scores [0:SCORE_COUNT-1];

  integer cycle_count = 0;
  integer driven_samples = 0;
  integer score_count = 0;
  integer drive_index;
  integer cadence_phase = 0;
  integer phase_index;
  integer expected_map_value;
  integer largest_map_value = 0;
  integer largest_map_phase = 0;

  always #5 clk = ~clk;

  starlink_pss_iq_to_phase_map #(
    .PHASE_BINS              (PHASE_BINS),
    .PHASE_INDEX_WIDTH       (PHASE_INDEX_WIDTH),
    .TILE_FRAMES             (BLOCK_COUNT),
    .TILE_FRAME_WIDTH        (2),
    .MAP_WIDTH               (16),
    .MAP_SEGMENT_ADDRESS_WIDTH(9),
    .MAP_SEGMENT_COUNT       (1),
    .MAP_SEGMENT_INDEX_WIDTH (1)
  ) dut (
    .clk                                  (clk),
    .resetn                               (resetn),
    .enable                               (enable),
    .flush                                (flush),
    .sample_valid                         (sample_valid),
    .sample_gap                           (sample_gap),
    .sample_i                             (sample_i),
    .sample_q                             (sample_q),
    .sample_index                         (sample_index),
    .map_ready_mask                       (map_ready_mask),
    .map_generation_0                     (map_generation_0),
    .map_generation_1                     (map_generation_1),
    .map_start_index_0                    (map_start_index_0),
    .map_start_index_1                    (map_start_index_1),
    .map_read_request                     (map_read_request),
    .map_read_bank                        (map_read_bank),
    .map_read_index                       (map_read_index),
    .map_read_valid                       (map_read_valid),
    .map_read_data                        (map_read_data),
    .map_read_error                       (map_read_error),
    .map_release                          (map_release),
    .map_release_bank                     (map_release_bank),
    .score_valid                          (score_valid),
    .score_value                          (score_value),
    .score_start_index                    (score_start_index),
    .score_phase                          (score_phase),
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
    .candidate_fifo_maximum_stored_count  (candidate_fifo_maximum_stored_count),
    .score_phase_index_discontinuity_count(score_phase_index_discontinuity_count),
    .scheduler_gap_count                  (scheduler_gap_count),
    .scheduler_index_error_count          (scheduler_index_error_count),
    .scheduler_overflow_count             (scheduler_overflow_count),
    .detector_fault_count                 (detector_fault_count),
    .score_denominator_zero_count         (score_denominator_zero_count),
    .detector_health_flags                (detector_health_flags),
    .accepted_score_count                 (accepted_score_count),
    .discarded_score_count                (discarded_score_count),
    .discontinuity_abort_count            (discontinuity_abort_count),
    .map_publish_count                    (map_publish_count),
    .map_overrun_count                    (map_overrun_count),
    .score_protocol_error_count           (score_protocol_error_count),
    .map_arithmetic_overflow_count        (map_arithmetic_overflow_count),
    .map_read_error_count                 (map_read_error_count),
    .map_release_error_count              (map_release_error_count)
  );

  task automatic fail(input string message);
    begin
      $display("IQ_TO_PHASE_MAP_XFFT_FAIL %0s cycle=%0d samples=%0d scores=%0d ready=%0b accepted=%0d discarded=%0d aborts=%0d",
               message, cycle_count, driven_samples, score_count,
               map_ready_mask, accepted_score_count, discarded_score_count,
               discontinuity_abort_count);
      $fatal(1);
    end
  endtask

  task automatic read_map_and_expect(
    input [PHASE_INDEX_WIDTH-1:0] index,
    input [15:0] expected
  );
    begin
      @(negedge clk);
      map_read_bank = 1'b0;
      map_read_index = index;
      map_read_request = 1'b1;
      @(negedge clk);
      map_read_request = 1'b0;
      @(negedge clk);
      if (!map_read_valid || map_read_error)
        fail("published map read was rejected");
      if (map_read_data !== expected) begin
        $display("IQ_TO_PHASE_MAP_XFFT_MISMATCH phase=%0d got=%0d expected=%0d",
                 index, map_read_data, expected);
        fail("phase-map data mismatch");
      end
    end
  endtask

  always @(posedge clk) begin
    cycle_count = cycle_count + 1;
    if (cycle_count > 200000)
      fail("simulation watchdog expired");

    if (resetn && enable) begin
      if (detector_fault || scheduler_gap_pulse ||
          scheduler_index_error_pulse || scheduler_overflow_pulse ||
          forward_fft_fault || kernel_join_fault ||
          product_overflow_fault || inverse_fft_fault ||
          forward_exponent_fault || candidate_path_fault)
        fail("unexpected fail-closed event");

      if (sample_valid)
        driven_samples = driven_samples + 1;

      if (score_valid) begin
        if (score_count >= SCORE_COUNT)
          fail("too many normalized scores");
        if (score_value !== expected_scores[score_count])
          fail("normalized score mismatch");
        if (score_start_index !== FIRST_SAMPLE_INDEX + score_count ||
            score_phase !== score_count % PHASE_BINS ||
            score_denominator_zero)
          fail("score index, phase, or denominator metadata mismatch");
        score_count = score_count + 1;
      end
    end
  end

  initial begin
    $readmemh("samples_ci16.mem", input_samples);
    $readmemh("scores_u8.mem", expected_scores);

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

    begin : wait_for_map
      forever begin
        @(negedge clk);
        if (score_count == SCORE_COUNT && map_ready_mask == 2'b01)
          disable wait_for_map;
      end
    end

    if (driven_samples != SAMPLE_COUNT || score_count != SCORE_COUNT)
      fail("end-to-end count mismatch");
    if (map_generation_0 != 1 || map_generation_1 != 0 ||
        map_start_index_0 != FIRST_SAMPLE_INDEX ||
        map_start_index_1 != 0)
      fail("published map identity mismatch");
    if (accepted_score_count != SCORE_COUNT || discarded_score_count != 0 ||
        discontinuity_abort_count != 0 || map_publish_count != 1 ||
        map_overrun_count != 0 || score_protocol_error_count != 0 ||
        map_arithmetic_overflow_count != 0 || map_read_error_count != 0 ||
        map_release_error_count != 0 ||
        score_phase_index_discontinuity_count != 0 ||
        scheduler_gap_count != 0 || scheduler_index_error_count != 0 ||
        scheduler_overflow_count != 0 || detector_fault_count != 0 ||
        score_denominator_zero_count != 0 || detector_health_flags != 0)
      fail("unexpected phase-map telemetry");
    if (candidate_fifo_stored_count != 0 ||
        candidate_fifo_maximum_stored_count == 0 ||
        candidate_fifo_maximum_stored_count > 512)
      fail("unexpected candidate FIFO occupancy telemetry");

    for (phase_index = 0; phase_index < PHASE_BINS;
         phase_index = phase_index + 1) begin
      expected_map_value = expected_scores[phase_index] +
          expected_scores[phase_index + PHASE_BINS] +
          expected_scores[phase_index + 2 * PHASE_BINS];
      read_map_and_expect(phase_index[PHASE_INDEX_WIDTH-1:0],
                          expected_map_value[15:0]);
      if (expected_map_value > largest_map_value) begin
        largest_map_value = expected_map_value;
        largest_map_phase = phase_index;
      end
    end

    if (map_read_error_count != 0 || map_release_error_count != 0)
      fail("map read changed error telemetry");

    $display("IQ_TO_PHASE_MAP_XFFT_PASS samples=%0d scores=%0d phases=%0d frames=%0d exact_map_reads=%0d map_peak_phase=%0d map_peak_value=%0d bounded_handoff_bytes=%0d candidate_fifo_peak=%0d health_flags=0x%08x",
             driven_samples, score_count, PHASE_BINS, BLOCK_COUNT,
             PHASE_BINS, largest_map_phase, largest_map_value,
             PHASE_BINS * 2, candidate_fifo_maximum_stored_count,
             detector_health_flags);
    $finish;
  end

endmodule
