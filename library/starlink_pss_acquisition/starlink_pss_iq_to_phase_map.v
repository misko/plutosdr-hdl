// Complete continuous CI16-to-bounded-phase-map acquisition pipeline.
//
// The normalized score stream is always consumed locally, tagged with a
// modulo-frame phase, and accumulated into the independently qualified
// ping-pong phase map.  The full-rate RX sample source is never backpressured.
// Only immutable, complete maps cross the eventual processor boundary.

`timescale 1ns/1ps

module starlink_pss_iq_to_phase_map #(
  parameter KERNEL_ROM_FILE = "upper_edge_pss_kernel_q17.mem",
  parameter [30:0] COEFFICIENT_ENERGY = 31'd1073742825,
  parameter integer PHASE_BINS = 20000,
  parameter integer PHASE_INDEX_WIDTH = 15,
  parameter integer TILE_FRAMES = 64,
  parameter integer TILE_FRAME_WIDTH = 6,
  parameter integer MAP_WIDTH = 16,
  parameter integer MAP_SEGMENT_ADDRESS_WIDTH = 11,
  parameter integer MAP_SEGMENT_COUNT = 10,
  parameter integer MAP_SEGMENT_INDEX_WIDTH = 4,
  parameter integer USE_SHARED_XFFT = 0,
  parameter integer USE_REALTIME_XFFT = 0,
  parameter integer ENABLE_BOUNDARY_STOP = 0,
  parameter integer USE_BANK_OWNED_XFFT = 0
) (
  input  wire                          clk,
  input  wire                          resetn,
  input  wire                          fft_clk,
  input  wire                          fft_resetn,
  input  wire                          enable,
  input  wire                          flush,

  input  wire                          sample_valid,
  input  wire                          sample_gap,
  input  wire signed [15:0]            sample_i,
  input  wire signed [15:0]            sample_q,
  input  wire [63:0]                   sample_index,

  output wire [1:0]                    map_ready_mask,
  output wire [31:0]                   map_generation_0,
  output wire [31:0]                   map_generation_1,
  output wire [63:0]                   map_start_index_0,
  output wire [63:0]                   map_start_index_1,

  input  wire                          map_read_request,
  input  wire                          map_read_bank,
  input  wire [PHASE_INDEX_WIDTH-1:0]  map_read_index,
  output wire                          map_read_valid,
  output wire [MAP_WIDTH-1:0]          map_read_data,
  output wire                          map_read_error,

  input  wire                          map_release,
  input  wire                          map_release_bank,

  output wire                          score_valid,
  output wire [7:0]                    score_value,
  output wire [63:0]                   score_start_index,
  output wire [PHASE_INDEX_WIDTH-1:0]  score_phase,
  output wire                          score_denominator_zero,

  output wire                          detector_fault,
  output wire                          scheduler_gap_pulse,
  output wire                          scheduler_index_error_pulse,
  output wire                          scheduler_overflow_pulse,
  output wire                          forward_fft_fault,
  output wire                          kernel_join_fault,
  output wire                          product_overflow_fault,
  output wire                          inverse_fft_fault,
  output wire                          forward_exponent_fault,
  output wire                          candidate_path_fault,
  output wire [9:0]                    candidate_fifo_stored_count,
  output wire [9:0]                    candidate_fifo_maximum_stored_count,
  output wire [31:0]                   score_phase_index_discontinuity_count,
  output wire [31:0]                   scheduler_gap_count,
  output wire [31:0]                   scheduler_index_error_count,
  output wire [31:0]                   scheduler_overflow_count,
  output wire [31:0]                   detector_fault_count,
  output wire [31:0]                   score_denominator_zero_count,
  output wire [31:0]                   detector_health_flags,

  output wire [31:0]                   accepted_score_count,
  output wire [31:0]                   discarded_score_count,
  output wire [31:0]                   discontinuity_abort_count,
  output wire [31:0]                   map_publish_count,
  output wire [31:0]                   map_overrun_count,
  output wire [31:0]                   score_protocol_error_count,
  output wire [31:0]                   map_arithmetic_overflow_count,
  output wire [31:0]                   map_read_error_count,
  output wire [31:0]                   map_release_error_count,
  output wire                          map_counter_fault,

  input  wire                          stop_request,
  output wire                          stop_ready,
  output wire                          stop_pending,
  output wire                          stop_ack,
  output wire                          stop_done,
  output wire                          stop_complete,
  output wire                          stop_failed,
  output wire [5:0]                    stop_failure_reason,
  output wire                          stop_has_map,
  output wire [31:0]                   stop_generation,
  output wire [63:0]                   stop_start_index,
  output wire [63:0]                   stop_end_index
);

  wire raw_score_valid;
  wire [7:0] raw_score_value;
  wire [63:0] raw_score_start_index;
  wire raw_score_denominator_zero;
  wire source_discontinuity;
  wire tagged_stream_discontinuity;
  wire phase_index_discontinuity_pulse;
  wire map_enable;
  reg map_score_valid;
  reg [63:0] map_score_start_index;
  reg [PHASE_INDEX_WIDTH-1:0] map_score_phase;
  reg [7:0] map_score_value;
  reg map_stream_discontinuity;

  initial begin
    if (USE_BANK_OWNED_XFFT != 0 && USE_BANK_OWNED_XFFT != 1)
      $fatal(1, "USE_BANK_OWNED_XFFT must be zero or one");
    if (USE_BANK_OWNED_XFFT && (!USE_SHARED_XFFT || !USE_REALTIME_XFFT))
      $fatal(1, "bank-owned phase map requires explicit shared realtime composition");
    if (ENABLE_BOUNDARY_STOP != 0 && ENABLE_BOUNDARY_STOP != 1)
      $fatal(1, "ENABLE_BOUNDARY_STOP must be zero or one");
    if (ENABLE_BOUNDARY_STOP && USE_SHARED_XFFT != 1)
      $fatal(1, "boundary stop requires the explicit shared composition");
    if (USE_REALTIME_XFFT != 0 && USE_REALTIME_XFFT != 1)
      $fatal(1, "USE_REALTIME_XFFT must be zero or one");
    if (USE_REALTIME_XFFT && USE_SHARED_XFFT != 1)
      $fatal(1, "realtime XFFT requires the explicit shared composition");
  end

  assign map_enable = enable && !flush && !detector_fault;
  // Conservative ready excludes the core's rearm edge itself.  A controller
  // drives a request only when ready, so both sides observe exactly the same
  // acceptance edge, including flush/detector-fault changes before that edge.
  assign stop_ready = ENABLE_BOUNDARY_STOP && map_enable && !stop_pending && !stop_done;
  assign source_discontinuity = sample_gap || scheduler_gap_pulse ||
      scheduler_index_error_pulse || scheduler_overflow_pulse ||
      detector_fault;

  // Additive experiment only: no AXI/receiver profile exposes this selector yet.
  // Map arithmetic, publication/stop semantics and health bit14 remain shared.
  generate if (USE_BANK_OWNED_XFFT) begin : bank_transform
  starlink_pss_iq_to_score_bank_owned #(
    .KERNEL_ROM_FILE(KERNEL_ROM_FILE),
    .COEFFICIENT_ENERGY(COEFFICIENT_ENERGY)
  ) iq_to_score (
    .fft_clk(fft_clk), .fft_resetn(fft_resetn), .clk(clk), .resetn(resetn),
    .enable(enable), .flush(flush), .sample_valid(sample_valid),
    .sample_gap(sample_gap), .sample_i(sample_i), .sample_q(sample_q),
    .sample_index(sample_index), .score_valid(raw_score_valid),
    .score_ready(1'b1), .score_value(raw_score_value),
    .score_start_index(raw_score_start_index),
    .score_denominator_zero(raw_score_denominator_zero),
    .detector_fault(detector_fault), .scheduler_gap_pulse(scheduler_gap_pulse),
    .scheduler_index_error_pulse(scheduler_index_error_pulse),
    .scheduler_overflow_pulse(scheduler_overflow_pulse),
    .forward_fft_fault(forward_fft_fault), .kernel_join_fault(kernel_join_fault),
    .product_overflow_fault(product_overflow_fault),
    .inverse_fft_fault(inverse_fft_fault),
    .forward_exponent_fault(forward_exponent_fault),
    .candidate_path_fault(candidate_path_fault),
    .candidate_fifo_stored_count(candidate_fifo_stored_count),
    .candidate_fifo_maximum_stored_count(candidate_fifo_maximum_stored_count)
  );
  end else if (USE_SHARED_XFFT) begin : shared_transform
  starlink_pss_iq_to_score_shared #(
    .USE_REALTIME_XFFT (USE_REALTIME_XFFT),
    .KERNEL_ROM_FILE   (KERNEL_ROM_FILE),
    .COEFFICIENT_ENERGY(COEFFICIENT_ENERGY)
  ) iq_to_score (
    .fft_clk                             (fft_clk),
    .fft_resetn                          (fft_resetn),
    .clk                                 (clk),
    .resetn                              (resetn),
    .enable                              (enable),
    .flush                               (flush),
    .sample_valid                        (sample_valid),
    .sample_gap                          (sample_gap),
    .sample_i                            (sample_i),
    .sample_q                            (sample_q),
    .sample_index                        (sample_index),
    .score_valid                         (raw_score_valid),
    .score_ready                         (1'b1),
    .score_value                         (raw_score_value),
    .score_start_index                   (raw_score_start_index),
    .score_denominator_zero              (raw_score_denominator_zero),
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
  end else begin : dedicated_transforms
  starlink_pss_iq_to_score #(
    .KERNEL_ROM_FILE   (KERNEL_ROM_FILE),
    .COEFFICIENT_ENERGY(COEFFICIENT_ENERGY)
  ) iq_to_score (
    .clk                                 (clk),
    .resetn                              (resetn),
    .enable                              (enable),
    .flush                               (flush),
    .sample_valid                        (sample_valid),
    .sample_gap                          (sample_gap),
    .sample_i                            (sample_i),
    .sample_q                            (sample_q),
    .sample_index                        (sample_index),
    .score_valid                         (raw_score_valid),
    .score_ready                         (1'b1),
    .score_value                         (raw_score_value),
    .score_start_index                   (raw_score_start_index),
    .score_denominator_zero              (raw_score_denominator_zero),
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
  end endgenerate

  starlink_pss_score_phase_tagger #(
    .PHASE_BINS       (PHASE_BINS),
    .PHASE_INDEX_WIDTH(PHASE_INDEX_WIDTH),
    .SCORE_WIDTH      (8)
  ) score_phase_tagger (
    .clk                         (clk),
    .resetn                      (resetn),
    .enable                      (map_enable),
    .flush                       (flush),
    .score_valid                 (raw_score_valid),
    .score_start_index           (raw_score_start_index),
    .score_value                 (raw_score_value),
    .stream_discontinuity        (source_discontinuity),
    .tagged_valid                (score_valid),
    .tagged_start_index          (score_start_index),
    .tagged_phase                (score_phase),
    .tagged_value                (score_value),
    .tagged_stream_discontinuity (tagged_stream_discontinuity),
    .accepted_pulse              (),
    .index_discontinuity_pulse   (phase_index_discontinuity_pulse)
  );

  assign score_denominator_zero = raw_score_denominator_zero;

  // Phase tagging and map qualification each contain an absolute-index
  // continuity comparison.  Register their boundary so those two independent
  // checks cannot collapse into one path ending at the segmented BRAM enables.
  // This stage accepts one score every clock and therefore does not reduce
  // detector throughput.
  always @(posedge clk) begin
    if (!resetn || !map_enable) begin
      map_score_valid <= 1'b0;
      map_score_start_index <= 64'd0;
      map_score_phase <= {PHASE_INDEX_WIDTH{1'b0}};
      map_score_value <= 8'd0;
      map_stream_discontinuity <= 1'b0;
    end else begin
      map_score_valid <= score_valid;
      map_score_start_index <= score_start_index;
      map_score_phase <= score_phase;
      map_score_value <= score_value;
      map_stream_discontinuity <= tagged_stream_discontinuity;
    end
  end

  starlink_pss_phase_map #(
    .PHASE_BINS              (PHASE_BINS),
    .PHASE_INDEX_WIDTH       (PHASE_INDEX_WIDTH),
    .TILE_FRAMES             (TILE_FRAMES),
    .TILE_FRAME_WIDTH        (TILE_FRAME_WIDTH),
    .SCORE_WIDTH             (8),
    .MAP_WIDTH               (MAP_WIDTH),
    .MAP_SEGMENT_ADDRESS_WIDTH(MAP_SEGMENT_ADDRESS_WIDTH),
    .MAP_SEGMENT_COUNT       (MAP_SEGMENT_COUNT),
    .MAP_SEGMENT_INDEX_WIDTH (MAP_SEGMENT_INDEX_WIDTH),
    .ENABLE_BOUNDARY_STOP    (ENABLE_BOUNDARY_STOP)
  ) phase_map (
    .clk                          (clk),
    .resetn                       (resetn),
    .acquisition_enable           (map_enable),
    .score_valid                  (map_score_valid),
    .score_start_index            (map_score_start_index),
    .score_phase                  (map_score_phase),
    .score_value                  (map_score_value),
    .stream_discontinuity         (map_stream_discontinuity),
    .map_ready_mask               (map_ready_mask),
    .map_generation_0             (map_generation_0),
    .map_generation_1             (map_generation_1),
    .map_start_index_0            (map_start_index_0),
    .map_start_index_1            (map_start_index_1),
    .map_read_request             (map_read_request),
    .map_read_bank                (map_read_bank),
    .map_read_index               (map_read_index),
    .map_read_valid               (map_read_valid),
    .map_read_data                (map_read_data),
    .map_read_error               (map_read_error),
    .map_release                  (map_release),
    .map_release_bank             (map_release_bank),
    .accepted_score_count         (accepted_score_count),
    .discarded_score_count        (discarded_score_count),
    .discontinuity_abort_count    (discontinuity_abort_count),
    .map_publish_count            (map_publish_count),
    .map_overrun_count            (map_overrun_count),
    .score_protocol_error_count   (score_protocol_error_count),
    .map_arithmetic_overflow_count(map_arithmetic_overflow_count),
    .map_read_error_count         (map_read_error_count),
    .map_release_error_count      (map_release_error_count),
    .map_counter_fault            (map_counter_fault),
    .stop_request                 (stop_request),
    .stop_pending                 (stop_pending),
    .stop_ack                     (stop_ack),
    .stop_done                    (stop_done),
    .stop_complete                (stop_complete),
    .stop_failed                  (stop_failed),
    .stop_failure_reason          (stop_failure_reason),
    .stop_has_map                 (stop_has_map),
    .stop_generation              (stop_generation),
    .stop_start_index             (stop_start_index),
    .stop_end_index               (stop_end_index)
  );

  starlink_pss_acquisition_health #(
    .USE_SHARED_XFFT(USE_SHARED_XFFT)
  ) acquisition_health (
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
    .score_valid                          (raw_score_valid),
    .score_denominator_zero               (raw_score_denominator_zero),
    .scheduler_gap_count                  (scheduler_gap_count),
    .scheduler_index_error_count          (scheduler_index_error_count),
    .scheduler_overflow_count             (scheduler_overflow_count),
    .detector_fault_count                 (detector_fault_count),
    .score_phase_index_discontinuity_count(score_phase_index_discontinuity_count),
    .score_denominator_zero_count         (score_denominator_zero_count),
    .detector_health_flags                (detector_health_flags)
  );

endmodule
