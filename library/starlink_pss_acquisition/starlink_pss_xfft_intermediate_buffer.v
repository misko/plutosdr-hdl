// SPDX-License-Identifier: GPL-2.0
//
// One-block spectrum buffer used to time-share a burst XFFT between the
// forward and inverse transforms.  A complete, metadata-consistent 512-bin
// product is committed before any inverse input is exposed.  The payload is
// exactly 512 complex 18-bit words and therefore maps to one RAMB18E1.

`timescale 1ns/1ps

module starlink_pss_xfft_intermediate_buffer #(
  parameter integer DATA_WIDTH = 18
) (
  input  wire                         clk,
  input  wire                         resetn,
  input  wire                         flush,
  input  wire                         release_buffer,

  input  wire                         input_valid,
  output wire                         input_ready,
  input  wire signed [DATA_WIDTH-1:0] input_i,
  input  wire signed [DATA_WIDTH-1:0] input_q,
  input  wire [8:0]                   input_position,
  input  wire [4:0]                   input_block_exponent,
  input  wire [63:0]                  input_block_start_index,
  input  wire                         input_last,

  input  wire                         read_enable,
  output wire                         output_valid,
  input  wire                         output_ready,
  output wire signed [DATA_WIDTH-1:0] output_i,
  output wire signed [DATA_WIDTH-1:0] output_q,
  output wire [8:0]                   output_position,
  output wire [4:0]                   output_block_exponent,
  output wire [63:0]                  output_block_start_index,
  output wire                         output_last,

  output reg                          write_complete_pulse,
  output reg                          read_complete_pulse,
  output reg                          protocol_error_pulse,
  output reg                          protocol_fault,
  output wire [9:0]                   stored_count
);

  generate
    if (DATA_WIDTH != 18) begin : g_invalid_width
      initial $fatal(1, "shared-XFFT buffer requires DATA_WIDTH=18");
    end
  endgenerate

  (* ram_style = "block", rw_addr_collision = "no" *)
  reg [(2*DATA_WIDTH)-1:0] payload_memory [0:511];

  reg write_in_progress;
  reg buffer_full;
  reg [8:0] expected_write_position;
  reg [4:0] active_block_exponent;
  reg [63:0] active_block_start_index;

  reg read_valid;
  reg read_all_loaded;
  reg [8:0] read_address;
  reg [8:0] read_output_position;
  reg [(2*DATA_WIDTH)-1:0] read_output_payload;

  wire input_accept = input_valid && input_ready;
  wire input_metadata_valid =
      input_position == expected_write_position &&
      input_last == (expected_write_position == 9'd511) &&
      (!write_in_progress ||
       (input_block_exponent == active_block_exponent &&
        input_block_start_index == active_block_start_index));
  wire output_accept = output_valid && output_ready;
  wire load_read_word = read_enable && buffer_full && !protocol_fault &&
      !read_all_loaded && (!read_valid || output_accept);

  assign input_ready = resetn && !flush && !buffer_full && !protocol_fault;
  assign output_valid = read_valid && read_enable && !protocol_fault;
  assign output_i = read_output_payload[DATA_WIDTH-1:0];
  assign output_q = read_output_payload[DATA_WIDTH +: DATA_WIDTH];
  assign output_position = read_output_position;
  assign output_block_exponent = active_block_exponent;
  assign output_block_start_index = active_block_start_index;
  assign output_last = read_output_position == 9'd511;
  assign stored_count = buffer_full ? 10'd512 :
                        {1'b0, expected_write_position};

  always @(posedge clk) begin
    if (!resetn || flush || release_buffer) begin
      write_in_progress <= 1'b0;
      buffer_full <= 1'b0;
      expected_write_position <= 9'd0;
      active_block_exponent <= 5'd0;
      active_block_start_index <= 64'd0;
      write_complete_pulse <= 1'b0;
      protocol_error_pulse <= 1'b0;
      protocol_fault <= 1'b0;
    end else begin
      write_complete_pulse <= 1'b0;
      protocol_error_pulse <= 1'b0;

      if (input_accept) begin
        if (!input_metadata_valid) begin
          protocol_error_pulse <= 1'b1;
          protocol_fault <= 1'b1;
        end else begin
          payload_memory[expected_write_position] <= {input_q, input_i};
          if (!write_in_progress) begin
            write_in_progress <= 1'b1;
            active_block_exponent <= input_block_exponent;
            active_block_start_index <= input_block_start_index;
          end

          if (expected_write_position == 9'd511) begin
            expected_write_position <= 9'd0;
            write_in_progress <= 1'b0;
            buffer_full <= 1'b1;
            write_complete_pulse <= 1'b1;
          end else begin
            expected_write_position <= expected_write_position + 1'b1;
          end
        end
      end
    end
  end

  // Synchronous, continuously prefetched read port.  A consumed word and its
  // successor may be handled on the same edge, so the inverse adapter sees a
  // gap-free 512-beat stream whenever the XFFT keeps TREADY asserted.
  always @(posedge clk) begin
    if (!resetn || flush || release_buffer) begin
      read_valid <= 1'b0;
      read_all_loaded <= 1'b0;
      read_address <= 9'd0;
      read_output_position <= 9'd0;
      read_complete_pulse <= 1'b0;
    end else begin
      read_complete_pulse <= 1'b0;

      if (load_read_word) begin
        read_output_payload <= payload_memory[read_address];
        read_output_position <= read_address;
        read_valid <= 1'b1;
        if (read_address == 9'd511)
          read_all_loaded <= 1'b1;
        else
          read_address <= read_address + 1'b1;
      end else if (output_accept) begin
        read_valid <= 1'b0;
        if (output_last)
          read_complete_pulse <= 1'b1;
      end
    end
  end

endmodule
