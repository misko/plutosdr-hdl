// Hash-locked upper-edge Starlink PSS frequency-domain kernel.
//
// The 512 complex coefficients are signed Q1.23.  Each memory word is packed
// as {Q[23:0], I[23:0]}.  A one-entry elastic output register preserves one
// accepted lookup per clock while allowing downstream backpressure.  Complete
// FFT bin order, TLAST, block exponent, and absolute block identity are checked
// before any coefficient can be published.  A malformed beat latches a
// fail-closed protocol fault until the common acquisition flush.

`timescale 1ns/1ps

module starlink_pss_kernel_rom #(
  parameter ROM_FILE = "upper_edge_pss_kernel_q23.mem"
) (
  input  wire                    clk,
  input  wire                    resetn,
  input  wire                    flush,

  input  wire                    input_valid,
  output wire                    input_ready,
  input  wire [8:0]              input_bin_index,
  input  wire [4:0]              input_block_exponent,
  input  wire                    input_last,
  input  wire [63:0]             input_block_start_index,

  output reg                     output_valid,
  input  wire                    output_ready,
  output wire signed [23:0]      output_kernel_i,
  output wire signed [23:0]      output_kernel_q,
  output reg [8:0]               output_bin_index,
  output reg [4:0]               output_block_exponent,
  output reg                     output_last,
  output reg [63:0]              output_block_start_index,

  output reg                     accepted_pulse,
  output reg                     emitted_pulse,
  output reg                     input_block_complete_pulse,
  output reg                     sequence_error_pulse,
  output reg                     metadata_error_pulse,
  output reg                     protocol_fault
);

  localparam integer VALID_RESULTS_PER_BLOCK = 447;

  (* rom_style = "block" *) reg [47:0] kernel_memory [0:511];
  reg [47:0] output_kernel_word;

  reg [8:0] expected_bin_index;
  reg [4:0] block_exponent;
  reg [63:0] block_start_index;
  reg [63:0] expected_next_block_start;
  reg have_previous_block;

  wire output_stage_ready;
  wire input_accept;
  wire at_block_start;
  wire sequence_error_now;
  wire metadata_error_now;
  wire protocol_error_now;

  initial begin
    $readmemh(ROM_FILE, kernel_memory, 0, 511);
  end

  assign output_stage_ready = !output_valid || output_ready;
  assign input_ready = resetn && !flush && !protocol_fault &&
                       output_stage_ready;
  assign input_accept = input_valid && input_ready;
  assign output_kernel_i = output_kernel_word[23:0];
  assign output_kernel_q = output_kernel_word[47:24];
  assign at_block_start = expected_bin_index == 0;
  assign sequence_error_now =
    input_bin_index != expected_bin_index ||
    input_last != (expected_bin_index == 9'd511);
  assign metadata_error_now = at_block_start ?
    (have_previous_block &&
     input_block_start_index != expected_next_block_start) :
    (input_block_exponent != block_exponent ||
     input_block_start_index != block_start_index);
  assign protocol_error_now = sequence_error_now || metadata_error_now;

  always @(posedge clk) begin
    if (!resetn || flush) begin
      expected_bin_index <= 0;
      block_exponent <= 0;
      block_start_index <= 0;
      expected_next_block_start <= 0;
      have_previous_block <= 1'b0;
      output_valid <= 1'b0;
      output_kernel_word <= 0;
      output_bin_index <= 0;
      output_block_exponent <= 0;
      output_last <= 1'b0;
      output_block_start_index <= 0;
      accepted_pulse <= 1'b0;
      emitted_pulse <= 1'b0;
      input_block_complete_pulse <= 1'b0;
      sequence_error_pulse <= 1'b0;
      metadata_error_pulse <= 1'b0;
      protocol_fault <= 1'b0;
    end else begin
      accepted_pulse <= input_accept;
      emitted_pulse <= output_valid && output_ready;
      input_block_complete_pulse <= 1'b0;
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
          output_valid <= 1'b1;
          output_kernel_word <= kernel_memory[input_bin_index];
          output_bin_index <= input_bin_index;
          output_block_exponent <= input_block_exponent;
          output_last <= input_last;
          output_block_start_index <= input_block_start_index;

          if (at_block_start) begin
            block_exponent <= input_block_exponent;
            block_start_index <= input_block_start_index;
          end

          if (expected_bin_index == 9'd511) begin
            expected_bin_index <= 0;
            expected_next_block_start <= input_block_start_index +
                                         VALID_RESULTS_PER_BLOCK;
            have_previous_block <= 1'b1;
            input_block_complete_pulse <= 1'b1;
          end else begin
            expected_bin_index <= expected_bin_index + 1'b1;
          end
        end
      end
    end
  end

endmodule
