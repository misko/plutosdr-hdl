// Persistent health telemetry for the Starlink PSS acquisition pipeline.
//
// Pulse counters and detector-fault episodes saturate at 32 bits.  Cause bits
// are sticky for the reset epoch so a short-lived quarantining fault remains
// diagnosable after the internal pipeline has drained or been flushed.

`timescale 1ns/1ps

module starlink_pss_acquisition_health #(
  parameter integer COUNTER_WIDTH = 32
) (
  input  wire          clk,
  input  wire          resetn,
  input  wire          detector_fault,
  input  wire          scheduler_gap_pulse,
  input  wire          scheduler_index_error_pulse,
  input  wire          scheduler_overflow_pulse,
  input  wire          forward_fft_fault,
  input  wire          kernel_join_fault,
  input  wire          product_overflow_fault,
  input  wire          inverse_fft_fault,
  input  wire          forward_exponent_fault,
  input  wire          candidate_path_fault,
  input  wire          phase_index_discontinuity_pulse,
  input  wire          score_valid,
  input  wire          score_denominator_zero,

  output reg [COUNTER_WIDTH-1:0] scheduler_gap_count,
  output reg [COUNTER_WIDTH-1:0] scheduler_index_error_count,
  output reg [COUNTER_WIDTH-1:0] scheduler_overflow_count,
  output reg [COUNTER_WIDTH-1:0] detector_fault_count,
  output reg [COUNTER_WIDTH-1:0] score_phase_index_discontinuity_count,
  output reg [COUNTER_WIDTH-1:0] score_denominator_zero_count,
  output reg [31:0]    detector_health_flags
);

  localparam integer HEALTH_DETECTOR_FAULT = 0;
  localparam integer HEALTH_SCHEDULER_GAP = 1;
  localparam integer HEALTH_SCHEDULER_INDEX_ERROR = 2;
  localparam integer HEALTH_SCHEDULER_OVERFLOW = 3;
  localparam integer HEALTH_FORWARD_FFT = 4;
  localparam integer HEALTH_KERNEL_JOIN = 5;
  localparam integer HEALTH_PRODUCT_OVERFLOW = 6;
  localparam integer HEALTH_INVERSE_FFT = 7;
  localparam integer HEALTH_FORWARD_EXPONENT = 8;
  localparam integer HEALTH_CANDIDATE_PATH = 9;
  localparam integer HEALTH_PHASE_INDEX_DISCONTINUITY = 10;
  localparam integer HEALTH_DENOMINATOR_ZERO = 11;

  reg detector_fault_previous;

  function automatic [COUNTER_WIDTH-1:0] increment_saturating;
    input [COUNTER_WIDTH-1:0] value;
    begin
      increment_saturating = (&value) ? value : value + 1'b1;
    end
  endfunction

  initial begin
    if (COUNTER_WIDTH < 1)
      $fatal(1, "COUNTER_WIDTH must be positive");
  end

  always @(posedge clk) begin
    if (!resetn) begin
      scheduler_gap_count <= {COUNTER_WIDTH{1'b0}};
      scheduler_index_error_count <= {COUNTER_WIDTH{1'b0}};
      scheduler_overflow_count <= {COUNTER_WIDTH{1'b0}};
      detector_fault_count <= {COUNTER_WIDTH{1'b0}};
      score_phase_index_discontinuity_count <= {COUNTER_WIDTH{1'b0}};
      score_denominator_zero_count <= {COUNTER_WIDTH{1'b0}};
      detector_health_flags <= 32'd0;
      detector_fault_previous <= 1'b0;
    end else begin
      detector_fault_previous <= detector_fault;

      if (scheduler_gap_pulse) begin
        scheduler_gap_count <= increment_saturating(scheduler_gap_count);
        detector_health_flags[HEALTH_SCHEDULER_GAP] <= 1'b1;
      end
      if (scheduler_index_error_pulse) begin
        scheduler_index_error_count <= increment_saturating(
            scheduler_index_error_count);
        detector_health_flags[HEALTH_SCHEDULER_INDEX_ERROR] <= 1'b1;
      end
      if (scheduler_overflow_pulse) begin
        scheduler_overflow_count <= increment_saturating(
            scheduler_overflow_count);
        detector_health_flags[HEALTH_SCHEDULER_OVERFLOW] <= 1'b1;
      end
      if (detector_fault && !detector_fault_previous) begin
        detector_fault_count <= increment_saturating(
            detector_fault_count);
        detector_health_flags[HEALTH_DETECTOR_FAULT] <= 1'b1;
      end
      if (phase_index_discontinuity_pulse) begin
        score_phase_index_discontinuity_count <= increment_saturating(
            score_phase_index_discontinuity_count);
        detector_health_flags[HEALTH_PHASE_INDEX_DISCONTINUITY] <= 1'b1;
      end
      if (score_valid && score_denominator_zero) begin
        score_denominator_zero_count <= increment_saturating(
            score_denominator_zero_count);
        detector_health_flags[HEALTH_DENOMINATOR_ZERO] <= 1'b1;
      end

      if (forward_fft_fault)
        detector_health_flags[HEALTH_FORWARD_FFT] <= 1'b1;
      if (kernel_join_fault)
        detector_health_flags[HEALTH_KERNEL_JOIN] <= 1'b1;
      if (product_overflow_fault)
        detector_health_flags[HEALTH_PRODUCT_OVERFLOW] <= 1'b1;
      if (inverse_fft_fault)
        detector_health_flags[HEALTH_INVERSE_FFT] <= 1'b1;
      if (forward_exponent_fault)
        detector_health_flags[HEALTH_FORWARD_EXPONENT] <= 1'b1;
      if (candidate_path_fault)
        detector_health_flags[HEALTH_CANDIDATE_PATH] <= 1'b1;
    end
  end

endmodule
