// SPDX-License-Identifier: GPL-2.0
//
// Inference boundary for one segmented simple-dual-port phase-map memory.
// Segmenting the non-power-of-two 20,000-word map prevents a 15-bit address
// port from allocating an otherwise unreachable 32,768-word physical memory.

`timescale 1ns/1ps

module starlink_pss_phase_map_bank #(
  parameter integer DEPTH = 20000,
  parameter integer ADDRESS_WIDTH = 15,
  parameter integer DATA_WIDTH = 16,
  parameter integer SEGMENT_ADDRESS_WIDTH = 11,
  parameter integer SEGMENT_COUNT = 10,
  parameter integer SEGMENT_INDEX_WIDTH = 4
) (
  input  wire                       clk,
  input  wire                       write_enable,
  input  wire [ADDRESS_WIDTH-1:0]   write_address,
  input  wire [DATA_WIDTH-1:0]      write_data,
  input  wire                       read_enable,
  input  wire [ADDRESS_WIDTH-1:0]   read_address,
  output reg  [DATA_WIDTH-1:0]      read_data
);

  localparam integer SEGMENT_DEPTH = 1 << SEGMENT_ADDRESS_WIDTH;

  generate
    if (SEGMENT_ADDRESS_WIDTH > ADDRESS_WIDTH) begin : g_invalid_segment_address
      initial $fatal(1, "segment address width exceeds total address width");
    end
    if ((1 << SEGMENT_INDEX_WIDTH) < SEGMENT_COUNT) begin : g_invalid_segment_index
      initial $fatal(1, "segment index cannot select every memory segment");
    end
    if ((SEGMENT_COUNT * SEGMENT_DEPTH) < DEPTH) begin : g_invalid_capacity
      initial $fatal(1, "segmented memory cannot hold the requested depth");
    end
    if (((SEGMENT_COUNT - 1) * SEGMENT_DEPTH) >= DEPTH) begin : g_excess_segment
      initial $fatal(1, "segmented memory contains a wholly unreachable segment");
    end
  endgenerate

  wire [SEGMENT_INDEX_WIDTH-1:0] write_segment =
      write_address >> SEGMENT_ADDRESS_WIDTH;
  wire [SEGMENT_INDEX_WIDTH-1:0] read_segment =
      read_address >> SEGMENT_ADDRESS_WIDTH;
  wire [SEGMENT_ADDRESS_WIDTH-1:0] write_offset =
      write_address[SEGMENT_ADDRESS_WIDTH-1:0];
  wire [SEGMENT_ADDRESS_WIDTH-1:0] read_offset =
      read_address[SEGMENT_ADDRESS_WIDTH-1:0];

  reg [SEGMENT_INDEX_WIDTH-1:0] selected_read_segment;
  wire [SEGMENT_COUNT*DATA_WIDTH-1:0] segment_read_data;

  genvar segment;
  generate
    for (segment = 0; segment < SEGMENT_COUNT; segment = segment + 1) begin : g_segment
      (* ram_style = "block" *)
      reg [DATA_WIDTH-1:0] memory [0:SEGMENT_DEPTH-1];
      reg [DATA_WIDTH-1:0] segment_output;

      always @(posedge clk) begin
        if (write_enable && write_segment == segment)
          memory[write_offset] <= write_data;
      end

      always @(posedge clk) begin
        if (read_enable && read_segment == segment)
          segment_output <= memory[read_offset];
      end

      assign segment_read_data[
          segment*DATA_WIDTH +: DATA_WIDTH] = segment_output;
    end
  endgenerate

  always @(posedge clk) begin
    if (read_enable)
      selected_read_segment <= read_segment;
  end

  integer mux_index;
  always @* begin
    read_data = {DATA_WIDTH{1'b0}};
    for (mux_index = 0; mux_index < SEGMENT_COUNT; mux_index = mux_index + 1)
      if (selected_read_segment == mux_index)
        read_data = segment_read_data[mux_index*DATA_WIDTH +: DATA_WIDTH];
  end

endmodule
