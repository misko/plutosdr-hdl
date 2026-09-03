// Complete continuous CI16-to-bounded-phase-map acquisition pipeline.
//
// The normalized score stream is always consumed locally, tagged with a
// modulo-frame phase, and accumulated into the independently qualified
// ping-pong phase map.  The full-rate RX sample source is never backpressured.
// Only immutable, complete maps cross the eventual processor boundary.

`timescale 1ns/1ps

module starlink_pss_iq_to_phase_map #(
  parameter KERNEL_ROM_FILE = "upper_edge_pss_kernel_q23.mem",
  parameter integer PHASE_BINS = 20000,
  parameter integer PHASE_INDEX_WIDTH = 15,
  parameter integer TILE_FRAMES = 64,
  parameter integer TILE_FRAME_WIDTH = 6,
  parameter integer MAP_WIDTH = 16,
  parameter integer MAP_SEGMENT_ADDRESS_WIDTH = 11,
  parameter integer MAP_SEGMENT_COUNT = 10,
  parameter integer MAP_SEGMENT_INDEX_WIDTH = 4
) (
  input  wire                          clk,
  input  wire                          resetn,
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
  output reg  [31:0]                   score_phase_index_discontinuity_count,

  output wire [31:0]                   accepted_score_count,
  output wire [31:0]                   discarded_score_count,
  output wire [31:0]                   discontinuity_abort_count,
  output wire [31:0]                   map_publish_count,
  output wire [31:0]                   map_overrun_count,
  output wire [31:0]                   score_protocol_error_count,
  output wire [31:0]                   map_arithmetic_overflow_count,
  output wire [31:0]                   map_read_error_count,
  output wire [31:0]                   map_release_error_count
);

  function automatic [31:0] increment_saturating_32;
    input [31:0] value;
    begin
      increment_saturating_32 = (&value) ? value : value + 1'b1;
    end
  endfunction

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

  assign map_enable = enable && !flush && !detector_fault;
  assign source_discontinuity = sample_gap || scheduler_gap_pulse ||
      scheduler_index_error_pulse || scheduler_overflow_pulse ||
      detector_fault;

  starlink_pss_iq_to_score #(
    .KERNEL_ROM_FILE(KERNEL_ROM_FILE)
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
    .MAP_SEGMENT_INDEX_WIDTH (MAP_SEGMENT_INDEX_WIDTH)
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
    .map_release_error_count      (map_release_error_count)
  );

  always @(posedge clk) begin
    if (!resetn)
      score_phase_index_discontinuity_count <= 32'd0;
    else if (phase_index_discontinuity_pulse)
      score_phase_index_discontinuity_count <= increment_saturating_32(
          score_phase_index_discontinuity_count);
  end

endmodule
