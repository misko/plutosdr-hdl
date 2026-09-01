// SPDX-License-Identifier: GPL-2.0
//
// Small, distributed-memory asynchronous FIFO for sparse control descriptors.
// It deliberately reserves one physical address, matching the seven-usable-
// entries contract of the earlier ADI FIFO at ADDRESS_WIDTH=3.  The payload is
// read into a destination-clock register only after a Gray write pointer has
// crossed two read clocks.  A consumed word remains in that register until the
// consumer requests the next prefetch, allowing downstream logic to use it as
// stable job metadata without another full-width copy.

`timescale 1ns/1ps

module starlink_pss_async_fifo #(
  parameter integer DATA_WIDTH = 160,
  parameter integer ADDRESS_WIDTH = 3,
  parameter RAM_STYLE = "distributed"
) (
  input  wire                     i_write_clk,
  input  wire                     i_write_resetn,
  input  wire                     i_write_valid,
  output wire                     o_write_ready,
  input  wire [DATA_WIDTH-1:0]    i_write_data,
  output wire [ADDRESS_WIDTH-1:0] o_write_room,

  input  wire                     i_read_clk,
  input  wire                     i_read_resetn,
  output wire                     o_read_valid,
  input  wire                     i_read_ready,
  output wire [DATA_WIDTH-1:0]    o_read_data
);

  localparam integer DEPTH = (1 << ADDRESS_WIDTH);
  localparam [ADDRESS_WIDTH:0] USABLE_CAPACITY = {
    1'b0,
    {ADDRESS_WIDTH{1'b1}}
  };

  function automatic [ADDRESS_WIDTH:0] binary_to_gray;
    input [ADDRESS_WIDTH:0] value;
    begin
      binary_to_gray = (value >> 1) ^ value;
    end
  endfunction

  function automatic [ADDRESS_WIDTH:0] gray_to_binary;
    input [ADDRESS_WIDTH:0] value;
    integer bit_index;
    begin
      gray_to_binary[ADDRESS_WIDTH] = value[ADDRESS_WIDTH];
      for (bit_index = ADDRESS_WIDTH-1; bit_index >= 0;
           bit_index = bit_index - 1)
        gray_to_binary[bit_index] =
            gray_to_binary[bit_index+1] ^ value[bit_index];
    end
  endfunction

  (* ram_style = RAM_STYLE *)
  reg [DATA_WIDTH-1:0] payload_memory [0:DEPTH-1];

  reg [ADDRESS_WIDTH:0] write_binary;
  reg [ADDRESS_WIDTH:0] write_gray;
  reg [ADDRESS_WIDTH:0] read_binary;
  reg [ADDRESS_WIDTH:0] read_gray;
  reg read_valid;
  reg [DATA_WIDTH-1:0] read_data;

  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [ADDRESS_WIDTH:0] read_gray_write_sync_1;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [ADDRESS_WIDTH:0] read_gray_write_sync_2;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [ADDRESS_WIDTH:0] write_gray_read_sync_1;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [ADDRESS_WIDTH:0] write_gray_read_sync_2;

  wire [ADDRESS_WIDTH:0] read_binary_write_domain =
      gray_to_binary(read_gray_write_sync_2);
  wire [ADDRESS_WIDTH:0] write_fill =
      write_binary - read_binary_write_domain;
  wire [ADDRESS_WIDTH:0] write_room = USABLE_CAPACITY - write_fill;

  assign o_write_ready = (write_fill != USABLE_CAPACITY);
  assign o_write_room = write_room[ADDRESS_WIDTH-1:0];
  wire unread_payload_available =
      (read_gray != write_gray_read_sync_2);
  assign o_read_valid = read_valid;
  assign o_read_data = read_data;

  wire write_handshake = i_write_valid && o_write_ready;
  wire read_handshake = read_valid && i_read_ready;
  wire read_prefetch =
      !read_valid && i_read_ready && unread_payload_available;

  always @(posedge i_write_clk) begin
    if (!i_write_resetn) begin
      write_binary <= {(ADDRESS_WIDTH+1){1'b0}};
      write_gray <= {(ADDRESS_WIDTH+1){1'b0}};
      read_gray_write_sync_1 <= {(ADDRESS_WIDTH+1){1'b0}};
      read_gray_write_sync_2 <= {(ADDRESS_WIDTH+1){1'b0}};
    end else begin
      read_gray_write_sync_1 <= read_gray;
      read_gray_write_sync_2 <= read_gray_write_sync_1;
      if (write_handshake) begin
        payload_memory[write_binary[ADDRESS_WIDTH-1:0]] <= i_write_data;
        write_binary <= write_binary + 1'b1;
        write_gray <= binary_to_gray(write_binary + 1'b1);
      end
    end
  end

  always @(posedge i_read_clk) begin
    if (!i_read_resetn) begin
      read_binary <= {(ADDRESS_WIDTH+1){1'b0}};
      read_gray <= {(ADDRESS_WIDTH+1){1'b0}};
      read_valid <= 1'b0;
      read_data <= {DATA_WIDTH{1'b0}};
      write_gray_read_sync_1 <= {(ADDRESS_WIDTH+1){1'b0}};
      write_gray_read_sync_2 <= {(ADDRESS_WIDTH+1){1'b0}};
    end else begin
      write_gray_read_sync_1 <= write_gray;
      write_gray_read_sync_2 <= write_gray_read_sync_1;
      if (read_handshake) begin
        read_valid <= 1'b0;
      end else if (read_prefetch) begin
        read_valid <= 1'b1;
        read_data <= payload_memory[read_binary[ADDRESS_WIDTH-1:0]];
        read_binary <= read_binary + 1'b1;
        read_gray <= binary_to_gray(read_binary + 1'b1);
      end
    end
  end

endmodule
