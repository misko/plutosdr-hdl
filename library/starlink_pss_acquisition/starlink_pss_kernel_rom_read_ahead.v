// Hash-locked upper-edge Starlink PSS frequency-domain kernel.
//
// The 512 complex coefficients use signed Q1.(DATA_WIDTH-1). Each memory word
// is packed as {Q, I}. A one-entry elastic output register preserves one
// accepted lookup per clock while allowing downstream backpressure.  Complete
// FFT bin order, TLAST, block exponent, and absolute block identity are checked
// before any coefficient can be published.  A malformed beat latches a
// fail-closed protocol fault until the common acquisition flush.

`timescale 1ns/1ps

module starlink_pss_kernel_rom_read_ahead #(
  parameter ROM_FILE = "upper_edge_pss_kernel_q23.mem",
  parameter integer DATA_WIDTH = 24,
  parameter integer BALANCED_BLOCK_IDENTITY_EQ = 0,
  parameter integer PRIVATE_NEXT_START_SCRATCH = 0,
  parameter integer PRIVATE_ROM_READ_AHEAD = 0,
  parameter integer PRIVATE_BLOCK_METADATA_READ_AHEAD = 0
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
  wire [2*DATA_WIDTH-1:0] output_kernel_word;

  reg [8:0] expected_bin_index;
  wire [4:0] block_exponent;
  wire [63:0] block_start_index;
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
    if (PRIVATE_BLOCK_METADATA_READ_AHEAD !== 0 && PRIVATE_BLOCK_METADATA_READ_AHEAD !== 1)
      $fatal(1, "PRIVATE_BLOCK_METADATA_READ_AHEAD must be zero or one");
    if (PRIVATE_ROM_READ_AHEAD !== 0 && PRIVATE_ROM_READ_AHEAD !== 1)
      $fatal(1, "PRIVATE_ROM_READ_AHEAD must be zero or one");
    if (PRIVATE_NEXT_START_SCRATCH !== 0 && PRIVATE_NEXT_START_SCRATCH !== 1)
      $fatal(1, "PRIVATE_NEXT_START_SCRATCH must be zero or one");
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

  // The checker-visible block tuple remains exact on every cycle. Only its
  // private capture excludes current acceptance/framing; the selector follows
  // the original nested first-beat update, including procedural X/Z semantics.
  generate if (PRIVATE_BLOCK_METADATA_READ_AHEAD) begin : private_block_metadata_read_ahead
    reg [68:0] speculative_metadata;
    reg [68:0] retained_metadata;
    reg metadata_selected;
    always @(posedge clk)
      if (input_ready && at_block_start)
        speculative_metadata <= {input_block_start_index, input_block_exponent};
    always @(posedge clk) begin
      if (!resetn || flush) begin
        retained_metadata <= 0;
        metadata_selected <= 0;
      end else begin
        if (metadata_selected)
          retained_metadata <= speculative_metadata;
        metadata_selected <= 0;
        if (input_accept) begin
          if (protocol_error_now)
            metadata_selected <= 0;
          else if (at_block_start)
            metadata_selected <= 1;
        end
      end
    end
    assign {block_start_index, block_exponent} =
      metadata_selected ? speculative_metadata : retained_metadata;
  end else begin : legacy_block_metadata
    reg [68:0] legacy_metadata;
    always @(posedge clk) begin
      if (!resetn || flush)
        legacy_metadata <= 0;
      else if (input_accept) begin
        if (protocol_error_now) begin
          // The original fault branch does not update block metadata.
        end else begin
          if (at_block_start)
            legacy_metadata <= {input_block_start_index, input_block_exponent};
        end
      end
    end
    assign {block_start_index, block_exponent} = legacy_metadata;
  end endgenerate

  // Read-ahead is private. The mux and retained word preserve every visible
  // coefficient bit, including invalid and fault cycles, without added latency.
  // The read enable excludes current framing/metadata checks. Publication and
  // every old checker below keep their original same-edge semantics.
  generate if (PRIVATE_ROM_READ_AHEAD) begin : private_rom_read_ahead
    reg [2*DATA_WIDTH-1:0] speculative_word;
    reg [2*DATA_WIDTH-1:0] retained_word;
    reg use_speculative;
    always @(posedge clk)
      if (input_ready)
        speculative_word <= kernel_memory[input_bin_index];
    always @(posedge clk) begin
      if (!resetn || flush) begin
        retained_word <= 0;
        use_speculative <= 0;
      end else begin
        if (use_speculative)
          retained_word <= speculative_word;
        use_speculative <= 0;
        // Preserve procedural four-state interpretation of both old tests.
        if (input_accept) begin
          if (protocol_error_now)
            use_speculative <= 0;
          else
            use_speculative <= 1;
        end
      end
    end
    assign output_kernel_word = use_speculative ? speculative_word : retained_word;
  end else begin : legacy_rom_read
    reg [2*DATA_WIDTH-1:0] legacy_word;
    always @(posedge clk) begin
      if (!resetn || flush)
        legacy_word <= 0;
      else if (input_accept) begin
        if (protocol_error_now) begin
          // The original fault branch does not update the coefficient.
        end else
          legacy_word <= kernel_memory[input_bin_index];
      end
    end
    assign output_kernel_word = legacy_word;
  end endgenerate

  always @(posedge clk) begin
    if (!resetn || flush) begin
      expected_bin_index <= 0;
      expected_next_block_start <= 0;
      have_previous_block <= 1'b0;
      output_valid <= 1'b0;
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

      // BEGIN PRIVATE_NEXT_START_SCRATCH: only this unused-at-bin511 value
      // may speculate. A healthy accepted final rewrites it on the same edge
      // before index0 can consult it; a malformed final quarantines instead.
      // No input acceptance, checker, history flag or public payload changes.
      if (PRIVATE_NEXT_START_SCRATCH && input_ready && expected_bin_index == 9'd511)
        expected_next_block_start <= input_block_start_index + VALID_RESULTS_PER_BLOCK;
      // END PRIVATE_NEXT_START_SCRATCH

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
          output_bin_index <= input_bin_index;
          output_block_exponent <= input_block_exponent;
          output_last <= input_last;
          output_block_start_index <= input_block_start_index;

          if (expected_bin_index == 9'd511) begin
            expected_bin_index <= 0;
            if (!PRIVATE_NEXT_START_SCRATCH)
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
