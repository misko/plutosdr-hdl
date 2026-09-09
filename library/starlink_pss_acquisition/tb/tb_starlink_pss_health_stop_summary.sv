`timescale 1ns/1ps

// Proposed integrated-health simplification, not a generic counter/flag ABI.
// The five counters are nonzero exactly when their same-epoch sticky bits are
// set. Keep ingress loss independent and denominator-zero diagnostic only.
module tb_starlink_pss_health_stop_summary #(
  parameter integer COUNTER_WIDTH = 3,
  parameter integer USE_SHARED_XFFT = 1
);
  reg clk = 0;
  always #5 clk = ~clk;
  reg resetn = 0;
  reg [12:0] events = 0;
  reg ingress_overflow_sticky = 0;
  reg [31:0] ingress_dropped_sample_count = 0;
  wire [COUNTER_WIDTH-1:0] scheduler_gap_count, scheduler_index_error_count;
  wire [COUNTER_WIDTH-1:0] scheduler_overflow_count, detector_fault_count;
  wire [COUNTER_WIDTH-1:0] score_phase_index_discontinuity_count;
  wire [COUNTER_WIDTH-1:0] score_denominator_zero_count;
  wire [31:0] detector_health_flags;
  wire [31:0] snapshot_health_flags = detector_health_flags |
      (ingress_overflow_sticky ? 32'h1000 : 32'd0);

  starlink_pss_acquisition_health #(
    .COUNTER_WIDTH(COUNTER_WIDTH), .USE_SHARED_XFFT(USE_SHARED_XFFT)
  ) dut (
    .clk(clk), .resetn(resetn),
    .detector_fault(events[0]), .scheduler_gap_pulse(events[1]),
    .scheduler_index_error_pulse(events[2]), .scheduler_overflow_pulse(events[3]),
    .forward_fft_fault(events[4]), .kernel_join_fault(events[5]),
    .product_overflow_fault(events[6]), .inverse_fft_fault(events[7]),
    .forward_exponent_fault(events[8]), .candidate_path_fault(events[9]),
    .phase_index_discontinuity_pulse(events[10]),
    .score_valid(events[11]), .score_denominator_zero(events[12]),
    .scheduler_gap_count(scheduler_gap_count),
    .scheduler_index_error_count(scheduler_index_error_count),
    .scheduler_overflow_count(scheduler_overflow_count),
    .detector_fault_count(detector_fault_count),
    .score_phase_index_discontinuity_count(score_phase_index_discontinuity_count),
    .score_denominator_zero_count(score_denominator_zero_count),
    .detector_health_flags(detector_health_flags)
  );

  // The runner extracts legacy_expression from the pinned real PSMA consumer.
  // This new expression is a proposal tested under the real health producer,
  // never permission to ignore inconsistent independent public inputs.
  `include "health_stop_expressions.vh"

  integer checks = 0;
  task automatic tick(input [12:0] value, input reset_released,
                      input overflow, input [31:0] dropped);
    begin
      @(negedge clk);
      events = value;
      resetn = reset_released;
      ingress_overflow_sticky = overflow;
      ingress_dropped_sample_count = dropped;
      @(posedge clk);
      #1;
      checks = checks + 1;
      if ((|detector_fault_count) !== detector_health_flags[0] ||
          (|scheduler_gap_count) !== detector_health_flags[1] ||
          (|scheduler_index_error_count) !== detector_health_flags[2] ||
          (|scheduler_overflow_count) !== detector_health_flags[3] ||
          (|score_phase_index_discontinuity_count) !== detector_health_flags[10] ||
          (|score_denominator_zero_count) !== detector_health_flags[11])
        $fatal(1, "HEALTH_SUMMARY_INVARIANT count/flag mismatch check=%0d", checks);
      if (legacy_stop !== proposed_stop)
        $fatal(1, "HEALTH_SUMMARY_EQUIVALENCE stop decision mismatch check=%0d", checks);
    end
  endtask

  integer pattern, repetition;
  initial begin
    // All simultaneous producer-input combinations, each starting in a fresh
    // epoch, then held fault/score inputs, then no events. External loss stays
    // independently observable even when every detector flag is clear.
    for (pattern = 0; pattern < 8192; pattern = pattern + 1) begin
      tick(0, 0, 0, 0);
      tick(pattern[12:0], 1, 0, 0);
      tick(pattern[12:0], 1, 0, 0);
      tick(0, 1, 0, 0);
    end
    tick(0, 0, 0, 0);
    tick(0, 1, 0, 32'h8000_0000);
    tick(0, 1, 1, 0);
    tick(0, 1, 0, 0);
    // Repeated rising fault episodes and simultaneous pulse events exercise
    // saturation for widths 1/3, and positive increment/hold for width 32.
    for (repetition = 0; repetition < 20; repetition = repetition + 1) begin
      tick(13'h1fff, 1, 0, 0);
      tick(0, 1, 0, 0);
    end
    if (COUNTER_WIDTH <= 3 &&
        (detector_fault_count !== {COUNTER_WIDTH{1'b1}} ||
         scheduler_gap_count !== {COUNTER_WIDTH{1'b1}} ||
         scheduler_index_error_count !== {COUNTER_WIDTH{1'b1}} ||
         scheduler_overflow_count !== {COUNTER_WIDTH{1'b1}} ||
         score_phase_index_discontinuity_count !== {COUNTER_WIDTH{1'b1}} ||
         score_denominator_zero_count !== {COUNTER_WIDTH{1'b1}}))
      $fatal(1, "HEALTH_SUMMARY_SATURATION not reached");
    tick(13'h1fff, 0, 0, 0);
    tick(0, 1, 0, 0);
    $display("HEALTH_SUMMARY_PASS width=%0d shared=%0d input_combinations=8192 checks=%0d receiver_implemented=0",
             COUNTER_WIDTH, USE_SHARED_XFFT, checks);
    $finish;
  end
endmodule
