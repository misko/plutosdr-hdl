// Join queued raw correlation metadata with its absolute-indexed energy.
//
// Exactly one metadata item is retained for the energy-cache request in
// flight.  A good cache response may be retired while the next request is
// accepted, sustaining one join per clock.  A miss, mismatched index, or
// orphan response is consumed but never emitted; it latches protocol_fault
// and quarantines both interfaces until flush.

`timescale 1ns/1ps

module starlink_pss_energy_join #(
  parameter integer DATA_WIDTH = 24
) (
  input  wire                    clk,
  input  wire                    resetn,
  input  wire                    flush,

  input  wire                    input_valid,
  output wire                    input_ready,
  input  wire signed [DATA_WIDTH-1:0] input_correlation_i,
  input  wire signed [DATA_WIDTH-1:0] input_correlation_q,
  input  wire [4:0]              input_forward_exponent,
  input  wire [4:0]              input_inverse_exponent,
  input  wire [63:0]             input_start_index,

  output wire                    cache_lookup_valid,
  input  wire                    cache_lookup_ready,
  output wire [63:0]             cache_lookup_start_index,
  input  wire                    cache_output_valid,
  output wire                    cache_output_ready,
  input  wire [37:0]             cache_output_energy,
  input  wire [63:0]             cache_output_start_index,
  input  wire                    cache_output_found,

  output reg                     output_valid,
  input  wire                    output_ready,
  output reg signed [DATA_WIDTH-1:0] output_correlation_i,
  output reg signed [DATA_WIDTH-1:0] output_correlation_q,
  output reg [37:0]              output_sample_energy,
  output reg [4:0]               output_forward_exponent,
  output reg [4:0]               output_inverse_exponent,
  output reg [63:0]              output_start_index,

  output reg                     accepted_pulse,
  output reg                     joined_pulse,
  output reg                     cache_miss_pulse,
  output reg                     index_mismatch_pulse,
  output reg                     orphan_response_pulse,
  output reg                     protocol_fault
);

  reg metadata_valid;
  reg signed [DATA_WIDTH-1:0] metadata_correlation_i;
  reg signed [DATA_WIDTH-1:0] metadata_correlation_q;
  reg [4:0] metadata_forward_exponent;
  reg [4:0] metadata_inverse_exponent;
  reg [63:0] metadata_start_index;

  wire output_stage_ready;
  wire orphan_response_now;
  wire cache_miss_now;
  wire index_mismatch_now;
  wire response_fault_now;
  wire response_accept;
  wire metadata_stage_ready;
  wire input_accept;

  assign output_stage_ready = !output_valid || output_ready;
  assign orphan_response_now = cache_output_valid && !metadata_valid;
  assign cache_miss_now = cache_output_valid && metadata_valid &&
                          !cache_output_found;
  assign index_mismatch_now = cache_output_valid && metadata_valid &&
                              cache_output_start_index !=
                              metadata_start_index;
  assign response_fault_now = orphan_response_now || cache_miss_now ||
                              index_mismatch_now;
  assign cache_output_ready = resetn && !flush && !protocol_fault &&
                              output_stage_ready;
  assign response_accept = cache_output_valid && cache_output_ready;
  assign metadata_stage_ready = !metadata_valid || response_accept;
  assign cache_lookup_valid = resetn && !flush && !protocol_fault &&
                              !response_fault_now &&
                              metadata_stage_ready && input_valid;
  assign input_ready = resetn && !flush && !protocol_fault &&
                       !response_fault_now && metadata_stage_ready &&
                       cache_lookup_ready;
  assign input_accept = input_valid && input_ready;
  assign cache_lookup_start_index = input_start_index;

  always @(posedge clk) begin
    if (!resetn || flush) begin
      metadata_valid <= 1'b0;
      metadata_correlation_i <= 0;
      metadata_correlation_q <= 0;
      metadata_forward_exponent <= 0;
      metadata_inverse_exponent <= 0;
      metadata_start_index <= 0;
      output_valid <= 1'b0;
      output_correlation_i <= 0;
      output_correlation_q <= 0;
      output_sample_energy <= 0;
      output_forward_exponent <= 0;
      output_inverse_exponent <= 0;
      output_start_index <= 0;
      accepted_pulse <= 1'b0;
      joined_pulse <= 1'b0;
      cache_miss_pulse <= 1'b0;
      index_mismatch_pulse <= 1'b0;
      orphan_response_pulse <= 1'b0;
      protocol_fault <= 1'b0;
    end else begin
      accepted_pulse <= input_accept;
      joined_pulse <= 1'b0;
      cache_miss_pulse <= 1'b0;
      index_mismatch_pulse <= 1'b0;
      orphan_response_pulse <= 1'b0;

      if (output_stage_ready)
        output_valid <= 1'b0;

      if (response_accept) begin
        metadata_valid <= 1'b0;
        if (response_fault_now) begin
          output_valid <= 1'b0;
          cache_miss_pulse <= cache_miss_now;
          index_mismatch_pulse <= index_mismatch_now;
          orphan_response_pulse <= orphan_response_now;
          protocol_fault <= 1'b1;
        end else begin
          output_valid <= 1'b1;
          output_correlation_i <= metadata_correlation_i;
          output_correlation_q <= metadata_correlation_q;
          output_sample_energy <= cache_output_energy;
          output_forward_exponent <= metadata_forward_exponent;
          output_inverse_exponent <= metadata_inverse_exponent;
          output_start_index <= metadata_start_index;
          joined_pulse <= 1'b1;
        end
      end

      if (input_accept) begin
        metadata_valid <= 1'b1;
        metadata_correlation_i <= input_correlation_i;
        metadata_correlation_q <= input_correlation_q;
        metadata_forward_exponent <= input_forward_exponent;
        metadata_inverse_exponent <= input_inverse_exponent;
        metadata_start_index <= input_start_index;
      end
    end
  end

endmodule
