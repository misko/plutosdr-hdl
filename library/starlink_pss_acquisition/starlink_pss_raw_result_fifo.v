// Burst-absorbing FIFO for qualified overlap-save IFFT results.
//
// The 123-bit payload preserves signed Q1.23 correlation, both XFFT block
// exponents, the absolute candidate-start index, and the last-result marker.
// The memory is never bulk-reset; flush invalidates it through pointers/count.

`timescale 1ns/1ps

module starlink_pss_raw_result_fifo #(
  parameter integer FIFO_DEPTH = 512,
  parameter integer ADDRESS_BITS = $clog2(FIFO_DEPTH),
  parameter integer COUNT_BITS = $clog2(FIFO_DEPTH + 1)
) (
  input  wire                    clk,
  input  wire                    resetn,
  input  wire                    flush,

  input  wire                    input_valid,
  output wire                    input_ready,
  input  wire signed [23:0]      input_correlation_i,
  input  wire signed [23:0]      input_correlation_q,
  input  wire [4:0]              input_forward_exponent,
  input  wire [4:0]              input_inverse_exponent,
  input  wire [63:0]             input_start_index,
  input  wire                    input_block_last,

  output reg                     output_valid,
  input  wire                    output_ready,
  output wire signed [23:0]      output_correlation_i,
  output wire signed [23:0]      output_correlation_q,
  output wire [4:0]              output_forward_exponent,
  output wire [4:0]              output_inverse_exponent,
  output wire [63:0]             output_start_index,
  output wire                    output_block_last,

  output wire [COUNT_BITS-1:0]   stored_count,
  output reg [COUNT_BITS-1:0]    maximum_stored_count,
  output reg                     accepted_pulse,
  output reg                     emitted_pulse,
  output reg                     overflow_pulse
);

  localparam integer PAYLOAD_BITS = 123;

  (* ram_style = "block" *)
  reg [PAYLOAD_BITS-1:0] result_memory [0:FIFO_DEPTH-1];
  reg [ADDRESS_BITS-1:0] write_pointer;
  reg [ADDRESS_BITS-1:0] read_pointer;
  reg [COUNT_BITS-1:0] memory_count;
  reg [PAYLOAD_BITS-1:0] output_payload;

  wire [PAYLOAD_BITS-1:0] input_payload;
  wire [COUNT_BITS-1:0] current_stored_count;
  wire output_stage_ready;
  wire input_accept;
  wire output_accept;
  wire memory_read;

  assign input_payload = {
    input_block_last,
    input_start_index,
    input_inverse_exponent,
    input_forward_exponent,
    input_correlation_q,
    input_correlation_i
  };
  assign current_stored_count = memory_count + output_valid;
  assign stored_count = current_stored_count;
  assign output_stage_ready = !output_valid || output_ready;
  // Keep admission dependent only on registered occupancy.  Conservatively
  // refusing a same-cycle replacement while completely full costs at most one
  // cycle, and prevents the downstream divider ready chain from reaching back
  // through this burst-absorbing boundary to the XFFT output interface.
  assign input_ready = resetn && !flush &&
    current_stored_count < FIFO_DEPTH;
  assign input_accept = input_valid && input_ready;
  assign output_accept = output_valid && output_ready;
  assign memory_read = output_stage_ready && memory_count != 0;

  assign {
    output_block_last,
    output_start_index,
    output_inverse_exponent,
    output_forward_exponent,
    output_correlation_q,
    output_correlation_i
  } = output_payload;

  initial begin
    if (FIFO_DEPTH < 447)
      $error("FIFO_DEPTH must absorb one complete 447-result burst");
    if ((1 << ADDRESS_BITS) != FIFO_DEPTH)
      $error("FIFO_DEPTH must be a power of two");
  end

  always @(posedge clk) begin
    if (!resetn || flush) begin
      write_pointer <= 0;
      read_pointer <= 0;
      memory_count <= 0;
      output_valid <= 1'b0;
      output_payload <= 0;
      maximum_stored_count <= 0;
      accepted_pulse <= 1'b0;
      emitted_pulse <= 1'b0;
      overflow_pulse <= 1'b0;
    end else begin
      accepted_pulse <= input_accept;
      emitted_pulse <= output_accept;
      overflow_pulse <= input_valid && !input_ready;

      if (input_accept) begin
        result_memory[write_pointer] <= input_payload;
        write_pointer <= write_pointer + 1'b1;
      end

      if (output_stage_ready) begin
        output_valid <= memory_count != 0;
        if (memory_count != 0) begin
          output_payload <= result_memory[read_pointer];
          read_pointer <= read_pointer + 1'b1;
        end
      end

      case ({input_accept, memory_read})
        2'b10: memory_count <= memory_count + 1'b1;
        2'b01: memory_count <= memory_count - 1'b1;
        default: memory_count <= memory_count;
      endcase

      if (current_stored_count > maximum_stored_count)
        maximum_stored_count <= current_stored_count;
      if (input_accept && !output_accept &&
          current_stored_count + 1'b1 > maximum_stored_count)
        maximum_stored_count <= current_stored_count + 1'b1;
    end
  end

endmodule
