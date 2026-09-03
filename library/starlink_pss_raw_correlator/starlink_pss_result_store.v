// SPDX-License-Identifier: GPL-2.0
//
// Atomic, double-buffered publication store for exact PSS winner packets.
// The engine-side producer holds one complete result stable while it is
// serialized into 26 32-bit words.  Only after the final word is committed is
// a one-bit bank descriptor published across the clock boundary.  The control
// side may read the current packet in any order and explicitly releases its
// bank when finished.  If both banks are occupied, a new complete result is
// accepted and discarded as one counted overrun; no partial packet is exposed.

`timescale 1ns/1ps

module starlink_pss_result_store #(
  parameter integer LAG_WIDTH = 7
) (
  input  wire                i_engine_clk,
  input  wire                i_engine_resetn,

  input  wire                i_result_valid,
  output wire                o_result_ready,
  input  wire                i_result_score_valid,
  input  wire                i_result_includes_eh,
  input  wire         [31:0] i_result_request_id,
  input  wire         [63:0] i_result_center_index,
  input  wire         [63:0] i_result_center_timestamp,
  input  wire signed [LAG_WIDTH-1:0] i_result_lag,
  input  wire         [63:0] i_result_timestamp,
  input  wire         [31:0] i_result_coefficient_generation,
  input  wire signed  [47:0] i_result_c_re,
  input  wire signed  [47:0] i_result_c_im,
  input  wire signed  [47:0] i_result_ex,
  input  wire signed  [47:0] i_result_eh,
  input  wire          [8:0] i_result_saturation_events,
  input  wire         [76:0] i_result_score_numerator,
  input  wire         [68:0] i_result_score_denominator,

  output wire          [1:0] o_result_bank_free,
  output reg          [31:0] o_result_published_count,
  output reg          [31:0] o_result_overrun_count,

  input  wire                i_control_clk,
  input  wire                i_control_resetn,
  output reg                 o_control_result_available,
  output reg                 o_control_result_bank,
  input  wire          [4:0] i_control_word_index,
  input  wire                i_control_word_read,
  output reg                 o_control_word_valid,
  output wire         [31:0] o_control_word_data,
  input  wire                i_control_result_release,
  output reg          [31:0] o_control_consumed_count
);

  localparam [4:0] PACKET_WORDS = 5'd26;
  localparam [4:0] LAST_PACKET_WORD = PACKET_WORDS - 1'b1;
  localparam [31:0] PACKET_MAGIC = 32'h3153_5350; // "PSS1" in LE bytes.

  generate
    if ((LAG_WIDTH < 2) || (LAG_WIDTH > 32)) begin : g_invalid_lag_width
      initial $fatal(1, "LAG_WIDTH must be between 2 and 32");
    end
  endgenerate

  function automatic [31:0] increment_saturating_32;
    input [31:0] value;
    begin
      increment_saturating_32 = (&value) ? value : value + 1'b1;
    end
  endfunction

  // Both resets form one coordinated epoch.  Integration must assert both
  // before releasing either, because descriptor state and bank ownership span
  // the clock boundary.
  reg [1:0] engine_bank_free;
  reg preferred_engine_bank;
  reg writer_active;
  reg writer_bank;
  reg [4:0] writer_word_index;

  reg [1:0] control_release_toggle;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [1:0] engine_release_toggle_sync_1;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [1:0] engine_release_toggle_sync_2;
  reg [1:0] engine_release_toggle_seen;

  wire [1:0] engine_release_event =
      engine_release_toggle_sync_2 ^ engine_release_toggle_seen;
  wire [1:0] effective_bank_free =
      engine_bank_free | engine_release_event;
  wire selected_engine_bank =
      effective_bank_free[preferred_engine_bank] ? preferred_engine_bank :
      ~preferred_engine_bank;
  wire selected_engine_bank_valid =
      effective_bank_free[preferred_engine_bank] ||
      effective_bank_free[~preferred_engine_bank];

  reg [31:0] packet_word_data;
  always @* begin
    case (writer_word_index)
      5'd0:  packet_word_data = PACKET_MAGIC;
      5'd1:  packet_word_data = {
        3'd0, PACKET_WORDS, 8'd1, 14'd0,
        i_result_includes_eh, i_result_score_valid
      };
      5'd2:  packet_word_data = i_result_request_id;
      5'd3:  packet_word_data = i_result_center_index[31:0];
      5'd4:  packet_word_data = i_result_center_index[63:32];
      5'd5:  packet_word_data = i_result_center_timestamp[31:0];
      5'd6:  packet_word_data = i_result_center_timestamp[63:32];
      5'd7:  packet_word_data = {
        {(32-LAG_WIDTH){i_result_lag[LAG_WIDTH-1]}}, i_result_lag
      };
      5'd8:  packet_word_data = i_result_timestamp[31:0];
      5'd9:  packet_word_data = i_result_timestamp[63:32];
      5'd10: packet_word_data = i_result_coefficient_generation;
      5'd11: packet_word_data = i_result_c_re[31:0];
      5'd12: packet_word_data = {
        {16{i_result_c_re[47]}}, i_result_c_re[47:32]
      };
      5'd13: packet_word_data = i_result_c_im[31:0];
      5'd14: packet_word_data = {
        {16{i_result_c_im[47]}}, i_result_c_im[47:32]
      };
      5'd15: packet_word_data = i_result_ex[31:0];
      5'd16: packet_word_data = {
        {16{i_result_ex[47]}}, i_result_ex[47:32]
      };
      5'd17: packet_word_data = i_result_eh[31:0];
      5'd18: packet_word_data = {
        {16{i_result_eh[47]}}, i_result_eh[47:32]
      };
      5'd19: packet_word_data = {23'd0, i_result_saturation_events};
      5'd20: packet_word_data = i_result_score_numerator[31:0];
      5'd21: packet_word_data = i_result_score_numerator[63:32];
      5'd22: packet_word_data = {
        19'd0, i_result_score_numerator[76:64]
      };
      5'd23: packet_word_data = i_result_score_denominator[31:0];
      5'd24: packet_word_data = i_result_score_denominator[63:32];
      5'd25: packet_word_data = {
        27'd0, i_result_score_denominator[68:64]
      };
      default: packet_word_data = 32'd0;
    endcase
  end

  wire result_memory_write = writer_active && i_result_valid;
  wire [5:0] result_memory_write_address = {
    writer_bank,
    writer_word_index
  };
  wire [5:0] result_memory_read_address = {
    o_control_result_bank,
    i_control_word_index
  };
  wire control_memory_read =
      o_control_result_available && i_control_word_read &&
      !i_control_result_release;

  ad_mem #(
    .DATA_WIDTH    (32),
    .ADDRESS_WIDTH (6)
  ) i_result_memory (
    .clka  (i_engine_clk),
    .wea   (result_memory_write),
    .addra (result_memory_write_address),
    .dina  (packet_word_data),
    .clkb  (i_control_clk),
    .reb   (control_memory_read),
    .addrb (result_memory_read_address),
    .doutb (o_control_word_data)
  );

  wire descriptor_write_ready;
  wire [1:0] descriptor_write_room_unused;
  wire descriptor_read_valid;
  wire descriptor_read_ready;
  wire descriptor_read_bank;

  wire descriptor_write_valid =
      writer_active && i_result_valid &&
      (writer_word_index == LAST_PACKET_WORD);
  wire descriptor_write_handshake =
      descriptor_write_valid && descriptor_write_ready;

  starlink_pss_async_fifo #(
    .DATA_WIDTH    (1),
    .ADDRESS_WIDTH (2)
  ) i_result_descriptor_fifo (
    .i_write_clk    (i_engine_clk),
    .i_write_resetn (i_engine_resetn),
    .i_write_valid  (descriptor_write_valid),
    .o_write_ready  (descriptor_write_ready),
    .i_write_data   (writer_bank),
    .o_write_room   (descriptor_write_room_unused),
    .i_read_clk     (i_control_clk),
    .i_read_resetn  (i_control_resetn),
    .o_read_valid   (descriptor_read_valid),
    .i_read_ready   (descriptor_read_ready),
    .o_read_data    (descriptor_read_bank)
  );

  assign descriptor_read_ready = !o_control_result_available;
  wire descriptor_read_handshake =
      descriptor_read_valid && descriptor_read_ready;

  // For a stored packet, ready is the completion handshake after word 25.
  // When no bank is free, ready accepts the result immediately as an atomic
  // drop.  The upstream ready/valid producer must hold all fields stable until
  // this completion handshake, which is exactly the reducer's output contract.
  assign o_result_ready = writer_active ? descriptor_write_handshake :
      !selected_engine_bank_valid;
  assign o_result_bank_free = engine_bank_free;

  integer release_index;
  always @(posedge i_engine_clk) begin
    if (!i_engine_resetn) begin
      engine_bank_free <= 2'b11;
      preferred_engine_bank <= 1'b0;
      writer_active <= 1'b0;
      writer_bank <= 1'b0;
      writer_word_index <= 5'd0;
      engine_release_toggle_sync_1 <= 2'b00;
      engine_release_toggle_sync_2 <= 2'b00;
      engine_release_toggle_seen <= 2'b00;
      o_result_published_count <= 32'd0;
      o_result_overrun_count <= 32'd0;
    end else begin
      engine_release_toggle_sync_1 <= control_release_toggle;
      engine_release_toggle_sync_2 <= engine_release_toggle_sync_1;
      engine_release_toggle_seen <= engine_release_toggle_sync_2;
      for (release_index = 0; release_index < 2;
           release_index = release_index + 1) begin
        if (engine_release_event[release_index])
          engine_bank_free[release_index] <= 1'b1;
      end

      if (writer_active) begin
        if (i_result_valid) begin
          if (writer_word_index == LAST_PACKET_WORD) begin
            if (descriptor_write_ready) begin
              writer_active <= 1'b0;
              o_result_published_count <= increment_saturating_32(
                  o_result_published_count);
            end
          end else begin
            writer_word_index <= writer_word_index + 1'b1;
          end
        end
      end else if (i_result_valid) begin
        if (selected_engine_bank_valid) begin
          engine_bank_free[selected_engine_bank] <= 1'b0;
          preferred_engine_bank <= ~selected_engine_bank;
          writer_bank <= selected_engine_bank;
          writer_word_index <= 5'd0;
          writer_active <= 1'b1;
        end else begin
          o_result_overrun_count <= increment_saturating_32(
              o_result_overrun_count);
        end
      end
    end
  end

  always @(posedge i_control_clk) begin
    if (!i_control_resetn) begin
      o_control_result_available <= 1'b0;
      o_control_result_bank <= 1'b0;
      o_control_word_valid <= 1'b0;
      control_release_toggle <= 2'b00;
      o_control_consumed_count <= 32'd0;
    end else begin
      o_control_word_valid <= control_memory_read;

      if (descriptor_read_handshake) begin
        o_control_result_available <= 1'b1;
        o_control_result_bank <= descriptor_read_bank;
      end

      if (o_control_result_available && i_control_result_release) begin
        control_release_toggle[o_control_result_bank] <=
            ~control_release_toggle[o_control_result_bank];
        o_control_result_available <= 1'b0;
        o_control_consumed_count <= increment_saturating_32(
            o_control_consumed_count);
      end
    end
  end

endmodule
