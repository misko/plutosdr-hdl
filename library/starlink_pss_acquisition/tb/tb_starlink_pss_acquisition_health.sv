`timescale 1ns/1ps

module tb_starlink_pss_acquisition_health;

  localparam integer COUNTER_WIDTH = 3;

  reg clk = 1'b0;
  reg resetn = 1'b0;
  reg detector_fault = 1'b0;
  reg scheduler_gap_pulse = 1'b0;
  reg scheduler_index_error_pulse = 1'b0;
  reg scheduler_overflow_pulse = 1'b0;
  reg forward_fft_fault = 1'b0;
  reg kernel_join_fault = 1'b0;
  reg product_overflow_fault = 1'b0;
  reg inverse_fft_fault = 1'b0;
  reg forward_exponent_fault = 1'b0;
  reg candidate_path_fault = 1'b0;
  reg phase_index_discontinuity_pulse = 1'b0;
  reg score_valid = 1'b0;
  reg score_denominator_zero = 1'b0;

  wire [COUNTER_WIDTH-1:0] scheduler_gap_count;
  wire [COUNTER_WIDTH-1:0] scheduler_index_error_count;
  wire [COUNTER_WIDTH-1:0] scheduler_overflow_count;
  wire [COUNTER_WIDTH-1:0] detector_fault_count;
  wire [COUNTER_WIDTH-1:0] score_phase_index_discontinuity_count;
  wire [COUNTER_WIDTH-1:0] score_denominator_zero_count;
  wire [31:0] detector_health_flags;

  integer iteration;

  always #5 clk = ~clk;

  starlink_pss_acquisition_health #(
    .COUNTER_WIDTH(COUNTER_WIDTH)
  ) dut (
    .clk                                  (clk),
    .resetn                               (resetn),
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
    .phase_index_discontinuity_pulse      (phase_index_discontinuity_pulse),
    .score_valid                          (score_valid),
    .score_denominator_zero               (score_denominator_zero),
    .scheduler_gap_count                  (scheduler_gap_count),
    .scheduler_index_error_count          (scheduler_index_error_count),
    .scheduler_overflow_count             (scheduler_overflow_count),
    .detector_fault_count                 (detector_fault_count),
    .score_phase_index_discontinuity_count(score_phase_index_discontinuity_count),
    .score_denominator_zero_count         (score_denominator_zero_count),
    .detector_health_flags                (detector_health_flags)
  );

  task automatic fail(input string message);
    begin
      $display("ACQUISITION_HEALTH_FAIL %0s", message);
      $fatal(1);
    end
  endtask

  task automatic pulse_gap;
    begin
      @(negedge clk);
      scheduler_gap_pulse = 1'b1;
      @(negedge clk);
      scheduler_gap_pulse = 1'b0;
    end
  endtask

  task automatic pulse_index_error;
    begin
      @(negedge clk);
      scheduler_index_error_pulse = 1'b1;
      @(negedge clk);
      scheduler_index_error_pulse = 1'b0;
    end
  endtask

  task automatic pulse_overflow;
    begin
      @(negedge clk);
      scheduler_overflow_pulse = 1'b1;
      @(negedge clk);
      scheduler_overflow_pulse = 1'b0;
    end
  endtask

  initial begin
    $dumpfile("build/tb_starlink_pss_acquisition_health.vcd");
    $dumpvars(0, tb_starlink_pss_acquisition_health);

    repeat (3) @(negedge clk);
    resetn = 1'b1;

    // Ten pulses prove three-bit saturation at seven.
    for (iteration = 0; iteration < 10; iteration = iteration + 1)
      pulse_gap();
    repeat (2) pulse_index_error();
    repeat (3) pulse_overflow();

    // A detector fault held high is one episode, not one event per clock.
    @(negedge clk);
    detector_fault = 1'b1;
    repeat (3) @(negedge clk);
    detector_fault = 1'b0;
    @(negedge clk);
    detector_fault = 1'b1;
    @(negedge clk);
    detector_fault = 1'b0;

    repeat (2) begin
      @(negedge clk);
      phase_index_discontinuity_pulse = 1'b1;
      @(negedge clk);
      phase_index_discontinuity_pulse = 1'b0;
    end
    repeat (4) begin
      @(negedge clk);
      score_valid = 1'b1;
      score_denominator_zero = 1'b1;
      @(negedge clk);
      score_valid = 1'b0;
      score_denominator_zero = 1'b0;
    end
    // A denominator indication without a valid score is not counted.
    @(negedge clk);
    score_denominator_zero = 1'b1;
    @(negedge clk);
    score_denominator_zero = 1'b0;

    // All component cause flags may occur in the same quarantining cycle.
    @(negedge clk);
    forward_fft_fault = 1'b1;
    kernel_join_fault = 1'b1;
    product_overflow_fault = 1'b1;
    inverse_fft_fault = 1'b1;
    forward_exponent_fault = 1'b1;
    candidate_path_fault = 1'b1;
    @(negedge clk);
    forward_fft_fault = 1'b0;
    kernel_join_fault = 1'b0;
    product_overflow_fault = 1'b0;
    inverse_fft_fault = 1'b0;
    forward_exponent_fault = 1'b0;
    candidate_path_fault = 1'b0;
    repeat (2) @(negedge clk);

    if (scheduler_gap_count != 3'b111)
      fail("gap count did not saturate");
    if (scheduler_index_error_count != 2 || scheduler_overflow_count != 3)
      fail("scheduler pulse counts are wrong");
    if (detector_fault_count != 2)
      fail("detector fault level was not counted by episode");
    if (score_phase_index_discontinuity_count != 2 ||
        score_denominator_zero_count != 4)
      fail("score health counts are wrong");
    if (detector_health_flags != 32'h0000_0fff)
      fail("sticky cause flags are incomplete");

    @(negedge clk);
    resetn = 1'b0;
    repeat (2) @(negedge clk);
    if (scheduler_gap_count != 0 || scheduler_index_error_count != 0 ||
        scheduler_overflow_count != 0 || detector_fault_count != 0 ||
        score_phase_index_discontinuity_count != 0 ||
        score_denominator_zero_count != 0 || detector_health_flags != 0)
      fail("reset did not clear the health epoch");

    $display("ACQUISITION_HEALTH_PASS saturation=1 detector_episodes=2 sticky_causes=12 reset_epoch=1");
    $finish;
  end

endmodule
