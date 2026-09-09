`timescale 1ns/1ps

// Long-horizon diagnostic for the real generated XFFT pipeline.  Unlike the
// exact three-block replay, this test deliberately checks protocol, ordering,
// capacity, and liveness rather than numerical values.  Its purpose is to
// expose faults which accumulate only after many overlap-save blocks.
module tb_starlink_pss_iq_to_score_xfft_longrun;
  parameter integer SOURCE_BURST_MODE = 0;
  parameter integer SCORE_STALL_MODE = 0;

  localparam integer BLOCK_COUNT = 64;
  localparam integer FFT_SAMPLES = 512;
  localparam integer VALID_RESULTS_PER_BLOCK = 447;
  localparam integer SAMPLE_COUNT = FFT_SAMPLES +
                                    (BLOCK_COUNT - 1) *
                                    VALID_RESULTS_PER_BLOCK;
  localparam integer SCORE_COUNT = BLOCK_COUNT * VALID_RESULTS_PER_BLOCK;
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
  integer driven_samples = 0;
  integer forward_count = 0;
  integer product_count = 0;
  integer inverse_count = 0;
  integer score_count = 0;
  integer drive_index;
  integer cadence_phase = 0;
  integer observed_max_fifo = 0;
  integer maximum_overlap_queue = 0, maximum_transform_fifo = 0;
  integer forward_stall_cycles = 0, maximum_forward_stall_cycles = 0;
  reg [63:0] maximum_ring_retention_age = 0;
  reg [63:0] maximum_energy_lookup_age = 0;
  reg [63:0] maximum_score_age = 0;
  reg [63:0] ring_retention_age, energy_lookup_age;
  wire score_ready = !SCORE_STALL_MODE || cycle_count % 97 >= 3;
  reg fault_seen = 1'b0;

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
    .candidate_fifo_maximum_stored_count  (
      candidate_fifo_maximum_stored_count
    )
  );

  task automatic report_and_fail(input string cause);
    begin
      if (!fault_seen) begin
        fault_seen = 1'b1;
        $display("IQ_TO_SCORE_XFFT_LONGRUN_FAULT cause=%0s cycle=%0d samples=%0d forward=%0d product=%0d inverse=%0d scores=%0d fifo=%0d fifo_max=%0d cache_count=%0d cache_oldest=%0d cache_newest=%0d next_score=%0d",
                 cause, cycle_count, driven_samples, forward_count,
                 product_count, inverse_count, score_count,
                 candidate_fifo_stored_count,
                 candidate_fifo_maximum_stored_count,
                 dut.energy_cache.stored_energy_count,
                 dut.energy_cache.oldest_energy_start_index,
                 dut.energy_cache.newest_energy_start_index,
                 FIRST_SAMPLE_INDEX + score_count);
        $finish;
      end
    end
  endtask

  // Sample the registered leaf causes after nonblocking updates.  This is
  // intentionally separate from the positive-edge counters so the global
  // fail-closed reset cannot erase the first useful evidence.
  always @(negedge clk) begin
    if (resetn && enable) begin
      if (dut.candidate_score_path.ifft_protocol_fault)
        report_and_fail("ifft_qualifier");
      if (dut.candidate_score_path.fifo_overflow_fault)
        report_and_fail("raw_result_fifo_overflow");
      if (dut.candidate_score_path.energy_join.cache_miss_pulse)
        report_and_fail("energy_cache_miss");
      if (dut.candidate_score_path.energy_join.index_mismatch_pulse)
        report_and_fail("energy_index_mismatch");
      if (dut.candidate_score_path.energy_join.orphan_response_pulse)
        report_and_fail("energy_orphan_response");
      if (dut.candidate_score_path.energy_join_fault)
        report_and_fail("energy_join_unspecified");
      if (dut.candidate_backpressure_fault)
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
      if (scheduler_gap_pulse)
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
    if (cycle_count > 1000000)
      report_and_fail("simulation_watchdog");

    if (resetn && enable) begin
      if (sample_valid)
        driven_samples = driven_samples + 1;

      if (dut.forward_output_valid && dut.forward_output_ready)
        forward_count = forward_count + 1;
      if (dut.product_output_valid && dut.product_output_ready)
        product_count = product_count + 1;
      if (dut.inverse_output_valid && dut.inverse_output_ready)
        inverse_count = inverse_count + 1;

      if (candidate_fifo_stored_count > observed_max_fifo)
        observed_max_fifo = candidate_fifo_stored_count;
      if (dut.scheduler.queued_block_count > maximum_overlap_queue)
        maximum_overlap_queue = dut.scheduler.queued_block_count;
      if (dut.transform_fifo.stored_count > maximum_transform_fifo)
        maximum_transform_fifo = dut.transform_fifo.stored_count;
      if (dut.scheduler.required_block_present) begin
        ring_retention_age = dut.scheduler.expected_sample_index -
          (dut.scheduler.active_block ? dut.scheduler.active_start_index :
                                        dut.scheduler.queue_head_start_index);
        if (ring_retention_age > maximum_ring_retention_age)
          maximum_ring_retention_age = ring_retention_age;
      end
      if (dut.cache_lookup_valid_from_path && dut.cache_lookup_ready_to_path &&
          dut.cache_lookup_start_from_path <= dut.energy_cache.newest_energy_start_index) begin
        energy_lookup_age = dut.energy_cache.newest_energy_start_index -
                            dut.cache_lookup_start_from_path;
        if (energy_lookup_age > maximum_energy_lookup_age)
          maximum_energy_lookup_age = energy_lookup_age;
      end
      if (dut.scheduler_fft_valid && !dut.scheduler_fft_ready) begin
        forward_stall_cycles = forward_stall_cycles + 1;
        if (forward_stall_cycles > maximum_forward_stall_cycles)
          maximum_forward_stall_cycles = forward_stall_cycles;
      end else forward_stall_cycles = 0;

      if (score_valid && score_ready) begin
        if (score_start_index !== FIRST_SAMPLE_INDEX + score_count)
          report_and_fail("score_index_order");
        if (score_denominator_zero)
          report_and_fail("zero_denominator");
        if (sample_index >= score_start_index &&
            sample_index - score_start_index > maximum_score_age)
          maximum_score_age = sample_index - score_start_index;
        score_count = score_count + 1;
        if (score_count % VALID_RESULTS_PER_BLOCK == 0)
          $display("IQ_TO_SCORE_XFFT_LONGRUN_PROGRESS block=%0d scores=%0d cycle=%0d fifo_max=%0d cache_oldest=%0d cache_newest=%0d",
                   score_count / VALID_RESULTS_PER_BLOCK, score_count,
                   cycle_count, observed_max_fifo,
                   dut.energy_cache.oldest_energy_start_index,
                   dut.energy_cache.newest_energy_start_index);
      end
    end
  end

  initial begin
    repeat (8) @(posedge clk);
    @(negedge clk);
    resetn = 1'b1;
    enable = 1'b1;

    for (drive_index = 0; drive_index < SAMPLE_COUNT;) begin
      @(negedge clk);
      sample_valid = 1'b0;
      cadence_phase = cadence_phase + 15;
      // Stress only delivery cadence, not source-index continuity or the
      // average 15 MS/s rate: accumulate arrivals through a bounded pause,
      // then deliver the pending samples on consecutive processing clocks.
      if (cadence_phase >= 100 && (!SOURCE_BURST_MODE || cycle_count % 40 >= 12)) begin
        cadence_phase = cadence_phase - 100;
        // Bounded nonzero deterministic CI16 stimulus.  Numerical score
        // accuracy remains covered by the independent exact-vector replay.
        sample_i = 16'sd1000 + (drive_index % 251);
        sample_q = -16'sd700 + (drive_index % 199);
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

    if (driven_samples != SAMPLE_COUNT ||
        forward_count != BLOCK_COUNT * FFT_SAMPLES ||
        product_count != BLOCK_COUNT * FFT_SAMPLES ||
        inverse_count != BLOCK_COUNT * FFT_SAMPLES ||
        score_count != SCORE_COUNT)
      report_and_fail("end_to_end_count");
    if (observed_max_fifo >= 512)
      report_and_fail("fifo_capacity_exhausted");
    if (maximum_overlap_queue > dut.scheduler.BLOCK_QUEUE_DEPTH ||
        maximum_ring_retention_age > dut.scheduler.RING_SAMPLES ||
        maximum_transform_fifo > dut.transform_fifo.FIFO_DEPTH ||
        maximum_energy_lookup_age >= dut.energy_cache.CACHE_ENTRIES)
      report_and_fail("observed_backlog_outside_retention_bounds");

    $display("IQ_TO_SCORE_XFFT_LONGRUN_PASS samples=%0d blocks=%0d forward=%0d product=%0d inverse=%0d scores=%0d fifo_max=%0d",
             driven_samples, BLOCK_COUNT, forward_count, product_count,
             inverse_count, score_count, observed_max_fifo);
    $display("IQ_TO_SCORE_XFFT_BACKLOG_PASS blocks=%0d overlap_queue_max=%0d ring_retention_age_max=%0d transform_fifo_max=%0d energy_lookup_age_max=%0d score_age_max=%0d forward_stall_cycles_max=%0d source_burst_mode=%0d score_stall_mode=%0d",
             BLOCK_COUNT, maximum_overlap_queue, maximum_ring_retention_age,
             maximum_transform_fifo, maximum_energy_lookup_age, maximum_score_age,
             maximum_forward_stall_cycles, SOURCE_BURST_MODE, SCORE_STALL_MODE);
    $finish;
  end

endmodule
