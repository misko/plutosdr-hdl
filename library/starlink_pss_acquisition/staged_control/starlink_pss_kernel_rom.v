// Hash-locked upper-edge Starlink PSS frequency-domain kernel.
//
// The 512 complex coefficients use signed Q1.(DATA_WIDTH-1). Each memory word
// is packed as {Q, I}. A one-entry elastic output register preserves one
// accepted lookup per clock while allowing downstream backpressure.  Complete
// FFT bin order, TLAST, block exponent, and absolute block identity are checked
// before any coefficient can be published.  A malformed beat latches a
// fail-closed protocol fault until the common acquisition flush.

`timescale 1ns/1ps

module starlink_pss_kernel_rom #(
  parameter ROM_FILE = "upper_edge_pss_kernel_q23.mem",
  parameter integer DATA_WIDTH = 24,
  parameter integer PRIVATE_PAYLOAD_BUBBLES = 0,
  parameter integer BALANCED_BLOCK_IDENTITY_EQ = 0
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
  output wire signed [DATA_WIDTH-1:0] output_kernel_i,
  output wire signed [DATA_WIDTH-1:0] output_kernel_q,
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

  (* rom_style = "block" *) reg [2*DATA_WIDTH-1:0] kernel_memory [0:511];
  reg [2*DATA_WIDTH-1:0] output_kernel_word;

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

  wire [1:0] block_identity_equal;
  generate if (BALANCED_BLOCK_IDENTITY_EQ) begin : balanced_block_identity
    for (genvar comparison = 0; comparison < 2; comparison = comparison + 1) begin : comparisons
      wire [63:0] rhs = comparison == 0 ? block_start_index : expected_next_block_start;
      (* keep = "true" *) wire [21:0] leaf_equal;
      (* keep = "true" *) wire [3:0] group_equal;
      for (genvar leaf = 0; leaf < 22; leaf = leaf + 1) begin : leaves
        localparam integer BITS = leaf == 21 ? 1 : 3;
        assign leaf_equal[leaf] = input_block_start_index[3*leaf +: BITS] == rhs[3*leaf +: BITS];
      end
      for (genvar group_index = 0; group_index < 4; group_index = group_index + 1) begin : groups
        localparam integer BITS = group_index == 3 ? 4 : 6;
        assign group_equal[group_index] = &leaf_equal[6*group_index +: BITS];
      end
      assign block_identity_equal[comparison] = &group_equal;
    end
  end else begin : legacy_block_identity
    assign block_identity_equal[0] = input_block_start_index == block_start_index;
    assign block_identity_equal[1] = input_block_start_index == expected_next_block_start;
  end endgenerate

  initial begin
    if (PRIVATE_PAYLOAD_BUBBLES !== 0 && PRIVATE_PAYLOAD_BUBBLES !== 1)
      $fatal(1, "private ROM payload mode must be known zero or one");
    if (BALANCED_BLOCK_IDENTITY_EQ != 0 && BALANCED_BLOCK_IDENTITY_EQ != 1)
      $fatal(1, "BALANCED_BLOCK_IDENTITY_EQ must be zero or one");
    if (DATA_WIDTH < 2 || DATA_WIDTH > 24)
      $fatal(1, "kernel DATA_WIDTH must lie in [2,24]");
    $readmemh(ROM_FILE, kernel_memory, 0, 511);
  end

  assign output_stage_ready = !output_valid || output_ready;
  assign input_ready = resetn && !flush && !protocol_fault &&
                       output_stage_ready;
  assign input_accept = input_valid && input_ready;
  assign output_kernel_i = output_kernel_word[DATA_WIDTH-1:0];
  assign output_kernel_q = output_kernel_word[DATA_WIDTH +: DATA_WIDTH];
  assign at_block_start = expected_bin_index == 0;
  assign sequence_error_now =
    input_bin_index != expected_bin_index ||
    input_last != (expected_bin_index == 9'd511);
  assign metadata_error_now = at_block_start ?
    (have_previous_block &&
     !block_identity_equal[1]) :
    (input_block_exponent != block_exponent ||
     !block_identity_equal[0]);
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

      // Private payload/first-bin metadata may load on a capacity bubble.
      // A held output still freezes these registers. All public valid,
      // ordinal, error, next-block and completion decisions remain below.
      if (PRIVATE_PAYLOAD_BUBBLES && input_ready) begin
        output_kernel_word <= kernel_memory[input_bin_index];
        output_bin_index <= input_bin_index;
        output_block_exponent <= input_block_exponent;
        output_last <= input_last;
        output_block_start_index <= input_block_start_index;
        if (at_block_start) begin
          block_exponent <= input_block_exponent;
          block_start_index <= input_block_start_index;
        end
      end
      if (input_accept) begin
        if (protocol_error_now) begin
          output_valid <= 1'b0;
          sequence_error_pulse <= sequence_error_now;
          metadata_error_pulse <= metadata_error_now;
          protocol_fault <= 1'b1;
        end else begin
          output_valid <= 1'b1;
          if (!PRIVATE_PAYLOAD_BUBBLES) begin
          output_kernel_word <= kernel_memory[input_bin_index];
          output_bin_index <= input_bin_index;
          output_block_exponent <= input_block_exponent;
          output_last <= input_last;
          output_block_start_index <= input_block_start_index;

          if (at_block_start) begin
            block_exponent <= input_block_exponent;
            block_start_index <= input_block_start_index;
          end
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
