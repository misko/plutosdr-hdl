// SPDX-License-Identifier: GPL-2.0
// One complete transform block crosses clocks via dual-port RAM and ownership
// toggles. The producer holds payload/metadata until the consumer acknowledges
// the LAST output handshake. No partial or malformed block is published.
//
// Intended for the experimental shared-XFFT island, not ADC ingress. The caller
// MUST obey input_ready. Both resets purge both domains; either may assert alone.
// Bundled metadata is stable from the first input beat through synchronized ACK.
// Physical CDC constraints/reports and full receiver integration remain required.
`timescale 1ns/1ps

module starlink_pss_block_mailbox #(
  parameter integer ADDRESS_WIDTH = 9,
  parameter integer DATA_WIDTH = 36,
  parameter integer METADATA_WIDTH = 70
) (
  input wire input_clk,
  input wire input_resetn,
  input wire input_valid,
  output wire input_ready,
  input wire [DATA_WIDTH-1:0] input_data,
  input wire [ADDRESS_WIDTH-1:0] input_position,
  input wire input_last,
  input wire [METADATA_WIDTH-1:0] input_metadata,
  output reg input_fault,
  input wire output_clk,
  input wire output_resetn,
  output wire output_valid,
  input wire output_ready,
  output wire [DATA_WIDTH-1:0] output_data,
  output wire [ADDRESS_WIDTH-1:0] output_position,
  output wire output_last,
  output wire [METADATA_WIDTH-1:0] output_metadata
);
  localparam integer DEPTH = 1 << ADDRESS_WIDTH;
  localparam [ADDRESS_WIDTH-1:0] LAST_POSITION = DEPTH - 1;
  initial begin
    if (ADDRESS_WIDTH < 2 || ADDRESS_WIDTH > 9 || DATA_WIDTH < 1 || METADATA_WIDTH < 1)
      $fatal(1, "unsupported block mailbox geometry");
  end

  (* ASYNC_REG = "TRUE" *) reg [1:0] in_reset_in_sync;
  (* ASYNC_REG = "TRUE" *) reg [1:0] out_reset_in_sync;
  (* ASYNC_REG = "TRUE" *) reg [1:0] in_reset_out_sync;
  (* ASYNC_REG = "TRUE" *) reg [1:0] out_reset_out_sync;
  always @(posedge input_clk or negedge input_resetn)
    if (!input_resetn) in_reset_in_sync <= 0;
    else in_reset_in_sync <= {in_reset_in_sync[0], 1'b1};
  always @(posedge input_clk or negedge output_resetn)
    if (!output_resetn) out_reset_in_sync <= 0;
    else out_reset_in_sync <= {out_reset_in_sync[0], 1'b1};
  always @(posedge output_clk or negedge input_resetn)
    if (!input_resetn) in_reset_out_sync <= 0;
    else in_reset_out_sync <= {in_reset_out_sync[0], 1'b1};
  always @(posedge output_clk or negedge output_resetn)
    if (!output_resetn) out_reset_out_sync <= 0;
    else out_reset_out_sync <= {out_reset_out_sync[0], 1'b1};
  wire in_running = in_reset_in_sync[1] && out_reset_in_sync[1];
  wire out_running = in_reset_out_sync[1] && out_reset_out_sync[1];

  reg request_toggle;
  reg acknowledge_toggle;
  (* ASYNC_REG = "TRUE" *) reg [1:0] request_sync;
  (* ASYNC_REG = "TRUE" *) reg [1:0] acknowledge_sync;
  always @(posedge input_clk)
    if (!in_running) acknowledge_sync <= 0;
    else acknowledge_sync <= {acknowledge_sync[0], acknowledge_toggle};
  always @(posedge output_clk)
    if (!out_running) request_sync <= 0;
    else request_sync <= {request_sync[0], request_toggle};

  (* ram_style = "block" *) reg [DATA_WIDTH-1:0] payload_memory [0:DEPTH-1];
  reg [METADATA_WIDTH-1:0] metadata_in_hold;
  reg [METADATA_WIDTH-1:0] metadata_out_hold;
  reg [ADDRESS_WIDTH-1:0] write_position;
  wire input_accept = input_valid && input_ready;
  wire input_framing_valid = input_position == write_position &&
    input_last == (write_position == LAST_POSITION) &&
    (write_position == 0 || input_metadata == metadata_in_hold);
  assign input_ready = in_running && !input_fault && request_toggle == acknowledge_sync[1];

  always @(posedge input_clk) begin
    if (!in_running) begin
      request_toggle <= 0;
      write_position <= 0;
      input_fault <= 0;
    end else if (input_accept) begin
      if (!input_framing_valid) begin
        input_fault <= 1;
      end else begin
        if (write_position == 0) metadata_in_hold <= input_metadata;
        if (write_position == LAST_POSITION) begin
          request_toggle <= !request_toggle;
          write_position <= 0;
        end else write_position <= write_position + 1'b1;
      end
    end
    // This RAM is exclusively producer-owned until a fully checked final beat
    // commits it. Even a malformed beat may write an unpublished word: the
    // fault prevents commit/reuse until reset. Keep the wide metadata comparator
    // off the BRAM write-enable path without weakening publication checks.
    if (input_accept)
      payload_memory[write_position] <= input_data;
  end

  reg reading;
  reg read_all_loaded;
  reg [ADDRESS_WIDTH-1:0] read_address;
  reg [ADDRESS_WIDTH-1:0] read_output_position;
  reg [DATA_WIDTH-1:0] read_payload;
  reg read_valid;
  wire output_accept = output_valid && output_ready;
  wire load_read = out_running && reading && !read_all_loaded &&
                   (!read_valid || output_ready);
  assign output_valid = out_running && read_valid;
  assign output_data = read_payload;
  assign output_position = read_output_position;
  assign output_last = read_output_position == LAST_POSITION;
  assign output_metadata = metadata_out_hold;

  always @(posedge output_clk) begin
    if (!out_running) begin
      acknowledge_toggle <= 0;
      reading <= 0;
      read_all_loaded <= 0;
      read_address <= 0;
      read_valid <= 0;
    end else begin
      if (!reading && request_sync[1] != acknowledge_toggle) begin
        reading <= 1;
        read_all_loaded <= 0;
        read_address <= 0;
        metadata_out_hold <= metadata_in_hold;
      end
      if (load_read) begin
        read_valid <= 1;
        read_output_position <= read_address;
        if (read_address == LAST_POSITION) read_all_loaded <= 1;
        else read_address <= read_address + 1'b1;
      end else if (output_accept) read_valid <= 0;
      if (output_accept && output_last) begin
        reading <= 0;
        acknowledge_toggle <= request_sync[1];
      end
    end
    if (load_read) read_payload <= payload_memory[read_address];
  end
endmodule
