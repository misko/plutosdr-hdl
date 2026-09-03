// Qualify overlap-save IFFT output and attach an absolute candidate index.
//
// A 512-point linear correlation with a 66-sample template has 65 invalid
// circular-prefix results.  Those indexes are consumed but discarded.  The
// remaining indexes 65..511 map to candidate starts block_start + index - 65.
// The complete XFFT framing and per-block metadata are checked before a result
// can be emitted.  Any malformed block latches protocol_fault until flush.

`timescale 1ns/1ps

module starlink_pss_ifft_qualifier #(
  parameter integer DATA_WIDTH = 24
) (
  input  wire                    clk,
  input  wire                    resetn,
  input  wire                    flush,

  input  wire                    input_valid,
  output wire                    input_ready,
  input  wire signed [DATA_WIDTH-1:0] input_correlation_i,
  input  wire signed [DATA_WIDTH-1:0] input_correlation_q,
  input  wire [8:0]              input_ifft_index,
  input  wire [4:0]              input_forward_exponent,
  input  wire [4:0]              input_inverse_exponent,
  input  wire [63:0]             input_block_start_index,
  input  wire                    input_last,

  output reg                     output_valid,
  input  wire                    output_ready,
  output reg signed [DATA_WIDTH-1:0] output_correlation_i,
  output reg signed [DATA_WIDTH-1:0] output_correlation_q,
  output reg [4:0]               output_forward_exponent,
  output reg [4:0]               output_inverse_exponent,
  output reg [63:0]              output_start_index,
  output reg                     output_block_last,

  output reg                     accepted_pulse,
  output reg                     discarded_prefix_pulse,
  output reg                     emitted_pulse,
  output reg                     sequence_error_pulse,
  output reg                     metadata_error_pulse,
  output reg                     protocol_fault
);

  localparam integer INVALID_PREFIX_RESULTS = 65;
  localparam integer VALID_RESULTS = 447;

  reg [8:0] expected_ifft_index;
  reg [4:0] block_forward_exponent;
  reg [4:0] block_inverse_exponent;
  reg [63:0] block_start_index;
  reg [63:0] expected_next_block_start;
  reg have_previous_block;

  wire output_stage_ready;
  wire input_accept;
  wire at_block_start;
  wire sequence_error_now;
  wire metadata_error_now;
  wire protocol_error_now;
  wire prefix_result_now;

  assign output_stage_ready = !output_valid || output_ready;
  assign input_ready = resetn && !flush && !protocol_fault &&
                       output_stage_ready;
  assign input_accept = input_valid && input_ready;
  assign at_block_start = expected_ifft_index == 0;
  assign sequence_error_now =
    input_ifft_index != expected_ifft_index ||
    input_last != (expected_ifft_index == 9'd511);
  assign metadata_error_now = at_block_start ?
    (have_previous_block &&
     input_block_start_index != expected_next_block_start) :
    (input_forward_exponent != block_forward_exponent ||
     input_inverse_exponent != block_inverse_exponent ||
     input_block_start_index != block_start_index);
  assign protocol_error_now = sequence_error_now || metadata_error_now;
  assign prefix_result_now = expected_ifft_index < INVALID_PREFIX_RESULTS;

  always @(posedge clk) begin
    if (!resetn || flush) begin
      expected_ifft_index <= 0;
      block_forward_exponent <= 0;
      block_inverse_exponent <= 0;
      block_start_index <= 0;
      expected_next_block_start <= 0;
      have_previous_block <= 1'b0;
      output_valid <= 1'b0;
      output_correlation_i <= 0;
      output_correlation_q <= 0;
      output_forward_exponent <= 0;
      output_inverse_exponent <= 0;
      output_start_index <= 0;
      output_block_last <= 1'b0;
      accepted_pulse <= 1'b0;
      discarded_prefix_pulse <= 1'b0;
      emitted_pulse <= 1'b0;
      sequence_error_pulse <= 1'b0;
      metadata_error_pulse <= 1'b0;
      protocol_fault <= 1'b0;
    end else begin
      accepted_pulse <= input_accept;
      discarded_prefix_pulse <= 1'b0;
      emitted_pulse <= output_valid && output_ready;
      sequence_error_pulse <= 1'b0;
      metadata_error_pulse <= 1'b0;

      if (output_stage_ready)
        output_valid <= 1'b0;

      if (input_accept) begin
        if (protocol_error_now) begin
          output_valid <= 1'b0;
          sequence_error_pulse <= sequence_error_now;
          metadata_error_pulse <= metadata_error_now;
          protocol_fault <= 1'b1;
        end else begin
          if (at_block_start) begin
            block_forward_exponent <= input_forward_exponent;
            block_inverse_exponent <= input_inverse_exponent;
            block_start_index <= input_block_start_index;
          end

          if (prefix_result_now) begin
            discarded_prefix_pulse <= 1'b1;
          end else begin
            output_valid <= 1'b1;
            output_correlation_i <= input_correlation_i;
            output_correlation_q <= input_correlation_q;
            output_forward_exponent <= input_forward_exponent;
            output_inverse_exponent <= input_inverse_exponent;
            output_start_index <= input_block_start_index +
                                  input_ifft_index -
                                  INVALID_PREFIX_RESULTS;
            output_block_last <= expected_ifft_index == 9'd511;
          end

          if (expected_ifft_index == 9'd511) begin
            expected_ifft_index <= 0;
            expected_next_block_start <= input_block_start_index +
                                         VALID_RESULTS;
            have_previous_block <= 1'b1;
          end else begin
            expected_ifft_index <= expected_ifft_index + 1'b1;
          end
        end
      end
    end
  end

endmodule
