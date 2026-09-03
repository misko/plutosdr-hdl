// Pair one forward-XFFT complex bin with its hash-locked PSS kernel bin.
//
// The coefficient ROM has a synchronous one-cycle lookup.  This wrapper
// captures the accepted forward I/Q payload beside that lookup and exposes one
// elastic combined stream to the spectrum product.  The ROM owns all framing,
// exponent, block-identity, and stride checks; malformed input is consumed but
// can never make output_valid true.

`timescale 1ns/1ps

module starlink_pss_forward_kernel_join #(
  parameter KERNEL_ROM_FILE = "upper_edge_pss_kernel_q23.mem"
) (
  input  wire                    clk,
  input  wire                    resetn,
  input  wire                    flush,

  input  wire                    input_valid,
  output wire                    input_ready,
  input  wire signed [23:0]      input_i,
  input  wire signed [23:0]      input_q,
  input  wire [8:0]              input_bin_index,
  input  wire [4:0]              input_block_exponent,
  input  wire                    input_last,
  input  wire [63:0]             input_block_start_index,

  output wire                    output_valid,
  input  wire                    output_ready,
  output wire signed [23:0]      output_i,
  output wire signed [23:0]      output_q,
  output wire signed [23:0]      output_kernel_i,
  output wire signed [23:0]      output_kernel_q,
  output wire [8:0]              output_bin_index,
  output wire [4:0]              output_block_exponent,
  output wire                    output_last,
  output wire [63:0]             output_block_start_index,

  output wire                    accepted_pulse,
  output wire                    emitted_pulse,
  output wire                    input_block_complete_pulse,
  output wire                    sequence_error_pulse,
  output wire                    metadata_error_pulse,
  output wire                    protocol_fault
);

  reg signed [23:0] captured_i;
  reg signed [23:0] captured_q;

  wire input_accept;

  assign input_accept = input_valid && input_ready;
  assign output_i = captured_i;
  assign output_q = captured_q;

  starlink_pss_kernel_rom #(
    .ROM_FILE (KERNEL_ROM_FILE)
  ) kernel_rom (
    .clk                       (clk),
    .resetn                    (resetn),
    .flush                     (flush),
    .input_valid               (input_valid),
    .input_ready               (input_ready),
    .input_bin_index           (input_bin_index),
    .input_block_exponent      (input_block_exponent),
    .input_last                (input_last),
    .input_block_start_index   (input_block_start_index),
    .output_valid              (output_valid),
    .output_ready              (output_ready),
    .output_kernel_i           (output_kernel_i),
    .output_kernel_q           (output_kernel_q),
    .output_bin_index          (output_bin_index),
    .output_block_exponent     (output_block_exponent),
    .output_last               (output_last),
    .output_block_start_index  (output_block_start_index),
    .accepted_pulse            (accepted_pulse),
    .emitted_pulse             (emitted_pulse),
    .input_block_complete_pulse(input_block_complete_pulse),
    .sequence_error_pulse      (sequence_error_pulse),
    .metadata_error_pulse      (metadata_error_pulse),
    .protocol_fault            (protocol_fault)
  );

  always @(posedge clk) begin
    if (!resetn || flush) begin
      captured_i <= 0;
      captured_q <= 0;
    end else if (input_accept) begin
      captured_i <= input_i;
      captured_q <= input_q;
    end
  end

endmodule
