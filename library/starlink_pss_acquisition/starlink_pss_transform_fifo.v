// Small registered boundary between the forward spectrum product and IFFT.
//
// Input readiness depends only on registered occupancy, never on downstream
// metadata or ready logic.  This intentionally breaks the long combinational
// path from the inverse adapter's 64-bit identity checks back into the forward
// kernel-ROM enable while preserving exact ready/valid ordering.

`timescale 1ns/1ps

module starlink_pss_transform_fifo #(
  parameter integer DATA_WIDTH = 18,
  parameter integer FIFO_DEPTH = 4,
  parameter integer ADDRESS_BITS = $clog2(FIFO_DEPTH),
  parameter integer COUNT_BITS = $clog2(FIFO_DEPTH + 1)
) (
  input  wire                    clk,
  input  wire                    resetn,
  input  wire                    flush,

  input  wire                    input_valid,
  output wire                    input_ready,
  input  wire signed [DATA_WIDTH-1:0] input_i,
  input  wire signed [DATA_WIDTH-1:0] input_q,
  input  wire [8:0]              input_position,
  input  wire [4:0]              input_block_exponent,
  input  wire [63:0]             input_block_start_index,
  input  wire                    input_last,

  output wire                    output_valid,
  input  wire                    output_ready,
  output wire signed [DATA_WIDTH-1:0] output_i,
  output wire signed [DATA_WIDTH-1:0] output_q,
  output wire [8:0]              output_position,
  output wire [4:0]              output_block_exponent,
  output wire [63:0]             output_block_start_index,
  output wire                    output_last,

  output wire [COUNT_BITS-1:0]   stored_count,
  output reg [COUNT_BITS-1:0]    maximum_stored_count,
  output reg                     protocol_fault
);

  localparam integer PAYLOAD_BITS = 79 + 2 * DATA_WIDTH;

  // The registered read already matches simple-dual-port block RAM. Spend
  // spare BRAM here to relieve LUT/FF packing in the complete paired receiver;
  // keep the output register, occupancy and ready/valid latency unchanged.
  (* ram_style = "block" *)
  reg [PAYLOAD_BITS-1:0] payload_memory [0:FIFO_DEPTH-1];
  reg [ADDRESS_BITS-1:0] write_pointer;
  reg [ADDRESS_BITS-1:0] read_pointer;
  reg [COUNT_BITS-1:0] memory_count;
  reg [PAYLOAD_BITS-1:0] output_payload;
  reg output_payload_valid;
  reg input_in_progress;
  reg [8:0] expected_input_position;
  reg [63:0] active_input_block_start;

  wire [PAYLOAD_BITS-1:0] input_payload;
  wire [COUNT_BITS-1:0] current_stored_count;
  wire input_metadata_valid;
  wire input_accept;
  wire input_write;
  wire output_accept;
  wire output_stage_ready;
  wire memory_read;

  assign input_payload = {
    input_last,
    input_block_start_index,
    input_block_exponent,
    input_position,
    input_q,
    input_i
  };
  assign {
    output_last,
    output_block_start_index,
    output_block_exponent,
    output_position,
    output_q,
    output_i
  } = output_payload;

  // Deliberately exclude output_ready from input_ready.  A full FIFO takes a
  // one-cycle bubble even when its head is consumed, which keeps the timing
  // boundary unconditional and is harmless for the matched FFT rates.
  assign current_stored_count = memory_count + output_payload_valid;
  assign input_metadata_valid =
    input_position == expected_input_position &&
    input_last == (expected_input_position == 9'd511) &&
    (!input_in_progress ||
     input_block_start_index == active_input_block_start);
  assign input_ready = resetn && !flush && !protocol_fault &&
                       current_stored_count < FIFO_DEPTH;
  assign output_valid = resetn && !flush && !protocol_fault &&
                        output_payload_valid;
  assign input_accept = input_valid && input_ready;
  assign input_write = input_accept && input_metadata_valid;
  assign output_accept = output_valid && output_ready;
  assign output_stage_ready = !output_payload_valid || output_accept;
  assign memory_read = output_stage_ready && memory_count != 0;
  assign stored_count = current_stored_count;

  initial begin
    if (FIFO_DEPTH < 2)
      $error("FIFO_DEPTH must be at least two");
    if ((1 << ADDRESS_BITS) != FIFO_DEPTH)
      $error("FIFO_DEPTH must be a power of two");
  end

  always @(posedge clk) begin
    if (!resetn || flush) begin
      write_pointer <= 0;
      read_pointer <= 0;
      memory_count <= 0;
      output_payload <= 0;
      output_payload_valid <= 1'b0;
      input_in_progress <= 1'b0;
      expected_input_position <= 0;
      active_input_block_start <= 0;
      maximum_stored_count <= 0;
      protocol_fault <= 1'b0;
    end else begin
      if (input_write) begin
        payload_memory[write_pointer] <= input_payload;
        write_pointer <= write_pointer + 1'b1;
      end

      if (output_stage_ready) begin
        output_payload_valid <= memory_count != 0;
        if (memory_count != 0) begin
          output_payload <= payload_memory[read_pointer];
          read_pointer <= read_pointer + 1'b1;
        end
      end

      case ({input_write, memory_read})
        2'b10: memory_count <= memory_count + 1'b1;
        2'b01: memory_count <= memory_count - 1'b1;
        default: memory_count <= memory_count;
      endcase

      if (input_write && !output_accept &&
          current_stored_count + 1'b1 > maximum_stored_count)
        maximum_stored_count <= current_stored_count + 1'b1;

      if (input_accept) begin
        if (!input_metadata_valid) begin
          protocol_fault <= 1'b1;
        end else begin
          if (!input_in_progress) begin
            input_in_progress <= 1'b1;
            active_input_block_start <= input_block_start_index;
          end
          if (expected_input_position == 9'd511) begin
            expected_input_position <= 0;
            input_in_progress <= 1'b0;
          end else begin
            expected_input_position <= expected_input_position + 1'b1;
          end
        end
      end
    end
  end

endmodule
