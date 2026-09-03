`timescale 1ns/1ps

// Interface-complete acquisition stub used only to test the wrapper's CDC,
// rate adapter, and AXI control. The XFFT pipeline has separate bit-accurate
// Vivado simulations.
module starlink_pss_iq_to_phase_map #(
  parameter KERNEL_ROM_FILE = "",
  parameter [30:0] COEFFICIENT_ENERGY = 31'd1,
  parameter integer PHASE_BINS = 20000,
  parameter integer PHASE_INDEX_WIDTH = 15,
  parameter integer TILE_FRAMES = 64,
  parameter integer TILE_FRAME_WIDTH = 6,
  parameter integer MAP_WIDTH = 16,
  parameter integer MAP_SEGMENT_ADDRESS_WIDTH = 11,
  parameter integer MAP_SEGMENT_COUNT = 10,
  parameter integer MAP_SEGMENT_INDEX_WIDTH = 4
) (
  input  wire                         clk,
  input  wire                         resetn,
  input  wire                         enable,
  input  wire                         flush,
  input  wire                         sample_valid,
  input  wire                         sample_gap,
  input  wire signed [15:0]           sample_i,
  input  wire signed [15:0]           sample_q,
  input  wire [63:0]                  sample_index,
  output wire [1:0]                   map_ready_mask,
  output wire [31:0]                  map_generation_0,
  output wire [31:0]                  map_generation_1,
  output wire [63:0]                  map_start_index_0,
  output wire [63:0]                  map_start_index_1,
  input  wire                         map_read_request,
  input  wire                         map_read_bank,
  input  wire [PHASE_INDEX_WIDTH-1:0] map_read_index,
  output wire                         map_read_valid,
  output wire [MAP_WIDTH-1:0]         map_read_data,
  output wire                         map_read_error,
  input  wire                         map_release,
  input  wire                         map_release_bank,
  output wire                         score_valid,
  output wire [7:0]                   score_value,
  output wire [63:0]                  score_start_index,
  output wire [PHASE_INDEX_WIDTH-1:0] score_phase,
  output wire                         score_denominator_zero,
  output wire                         detector_fault,
  output wire                         scheduler_gap_pulse,
  output wire                         scheduler_index_error_pulse,
  output wire                         scheduler_overflow_pulse,
  output wire                         forward_fft_fault,
  output wire                         kernel_join_fault,
  output wire                         product_overflow_fault,
  output wire                         inverse_fft_fault,
  output wire                         forward_exponent_fault,
  output wire                         candidate_path_fault,
  output wire [9:0]                   candidate_fifo_stored_count,
  output wire [9:0]                   candidate_fifo_maximum_stored_count,
  output wire [31:0]                  score_phase_index_discontinuity_count,
  output wire [31:0]                  scheduler_gap_count,
  output wire [31:0]                  scheduler_index_error_count,
  output wire [31:0]                  scheduler_overflow_count,
  output wire [31:0]                  detector_fault_count,
  output wire [31:0]                  score_denominator_zero_count,
  output wire [31:0]                  detector_health_flags,
  output wire [31:0]                  accepted_score_count,
  output wire [31:0]                  discarded_score_count,
  output wire [31:0]                  discontinuity_abort_count,
  output wire [31:0]                  map_publish_count,
  output wire [31:0]                  map_overrun_count,
  output wire [31:0]                  score_protocol_error_count,
  output wire [31:0]                  map_arithmetic_overflow_count,
  output wire [31:0]                  map_read_error_count,
  output wire [31:0]                  map_release_error_count
);

  assign map_ready_mask = 2'd0;
  assign map_generation_0 = 32'd0;
  assign map_generation_1 = 32'd0;
  assign map_start_index_0 = 64'd0;
  assign map_start_index_1 = 64'd0;
  assign map_read_valid = 1'b0;
  assign map_read_data = {MAP_WIDTH{1'b0}};
  assign map_read_error = map_read_request;
  assign score_valid = 1'b0;
  assign score_value = 8'd0;
  assign score_start_index = 64'd0;
  assign score_phase = {PHASE_INDEX_WIDTH{1'b0}};
  assign score_denominator_zero = 1'b0;
  assign detector_fault = 1'b0;
  assign scheduler_gap_pulse = 1'b0;
  assign scheduler_index_error_pulse = 1'b0;
  assign scheduler_overflow_pulse = 1'b0;
  assign forward_fft_fault = 1'b0;
  assign kernel_join_fault = 1'b0;
  assign product_overflow_fault = 1'b0;
  assign inverse_fft_fault = 1'b0;
  assign forward_exponent_fault = 1'b0;
  assign candidate_path_fault = 1'b0;
  assign candidate_fifo_stored_count = 10'd0;
  assign candidate_fifo_maximum_stored_count = 10'd0;
  assign score_phase_index_discontinuity_count = 32'd0;
  assign scheduler_gap_count = 32'd0;
  assign scheduler_index_error_count = 32'd0;
  assign scheduler_overflow_count = 32'd0;
  assign detector_fault_count = 32'd0;
  assign score_denominator_zero_count = 32'd0;
  assign detector_health_flags = 32'd0;
  assign accepted_score_count = 32'd0;
  assign discarded_score_count = 32'd0;
  assign discontinuity_abort_count = 32'd0;
  assign map_publish_count = 32'd0;
  assign map_overrun_count = 32'd0;
  assign score_protocol_error_count = 32'd0;
  assign map_arithmetic_overflow_count = 32'd0;
  assign map_read_error_count = 32'd0;
  assign map_release_error_count = 32'd0;

  wire unused = ^{
    KERNEL_ROM_FILE, COEFFICIENT_ENERGY, PHASE_BINS, TILE_FRAMES,
    TILE_FRAME_WIDTH, MAP_SEGMENT_ADDRESS_WIDTH, MAP_SEGMENT_COUNT,
    MAP_SEGMENT_INDEX_WIDTH, clk, resetn, enable, flush, sample_valid,
    sample_gap, sample_i, sample_q, sample_index, map_read_bank,
    map_read_index, map_release, map_release_bank
  };

endmodule
