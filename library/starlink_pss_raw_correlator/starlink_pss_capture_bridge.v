// SPDX-License-Identifier: GPL-2.0
//
// Abort-atomic, double-buffered clock-domain bridge between the accepted-
// sample scheduler and the exact correlator.  A capture bank is visible to the
// engine only after the full rate-scaled window has been written and capture_done
// has been observed.  Any capture_abort or malformed partial capture releases
// the bank locally without publishing a descriptor.

`timescale 1ns/1ps

module starlink_pss_capture_bridge #(
  parameter integer RATE_MULTIPLIER = 1
) (
  input  wire                i_sample_clk,
  input  wire                i_sample_resetn,

  input  wire                i_capture_valid,
  input  wire                i_capture_start,
  input  wire                i_capture_done,
  input  wire                i_capture_abort,
  input  wire  [$clog2(130 * RATE_MULTIPLIER)-1:0] i_capture_slot,
  input  wire         [31:0] i_capture_request_id,
  input  wire         [63:0] i_capture_center_index,
  input  wire         [63:0] i_capture_center_timestamp,
  input  wire         [63:0] i_capture_sample_timestamp,
  input  wire signed  [15:0] i_capture_sample_i,
  input  wire signed  [15:0] i_capture_sample_q,

  output wire                o_capture_ready,
  output wire          [1:0] o_capture_bank_free,
  output reg          [31:0] o_capture_published_count,
  output reg          [31:0] o_capture_abort_discard_count,
  output reg          [31:0] o_capture_buffer_overrun_count,
  output reg          [31:0] o_capture_protocol_error_count,

  input  wire                i_engine_clk,
  input  wire                i_engine_resetn,
  input  wire                i_engine_job_ready,

  output reg                 o_engine_job_start,
  output reg                 o_engine_job_done,
  output wire         [31:0] o_engine_request_id,
  output wire         [63:0] o_engine_center_index,
  output wire         [63:0] o_engine_center_timestamp,
  output wire                o_engine_sample_valid,
  input  wire                i_engine_sample_ready,
  output wire  [$clog2(130 * RATE_MULTIPLIER)-1:0] o_engine_sample_slot,
  output wire         [63:0] o_engine_sample_timestamp,
  output wire signed  [15:0] o_engine_sample_i,
  output wire signed  [15:0] o_engine_sample_q,
  output reg          [31:0] o_engine_consumed_count
);

  localparam integer DESCRIPTOR_WIDTH = 161;
  localparam integer CAPTURE_COUNT = 130 * RATE_MULTIPLIER;
  localparam integer CAPTURE_SLOT_WIDTH = $clog2(CAPTURE_COUNT);
  localparam integer CAPTURE_MEMORY_ADDRESS_WIDTH = CAPTURE_SLOT_WIDTH + 1;
  localparam [CAPTURE_SLOT_WIDTH-1:0] CAPTURE_LAST_SLOT =
      CAPTURE_COUNT - 1;

  generate
    if ((RATE_MULTIPLIER != 1) && (RATE_MULTIPLIER != 2) &&
        (RATE_MULTIPLIER != 4)) begin : g_invalid_rate_multiplier
      initial $fatal(1, "RATE_MULTIPLIER must be 1, 2, or 4");
    end
  endgenerate

  localparam [2:0] ENGINE_IDLE  = 3'd0;
  localparam [2:0] ENGINE_ISSUE = 3'd1;
  localparam [2:0] ENGINE_WAIT  = 3'd2;
  localparam [2:0] ENGINE_SEND  = 3'd3;

  function automatic [31:0] increment_saturating_32;
    input [31:0] value;
    begin
      increment_saturating_32 = (&value) ? value : value + 1'b1;
    end
  endfunction

  // The two resets are one coordinated reset contract.  The integration
  // wrapper must assert both together before releasing either one.  Resetting
  // only one side can invalidate both FIFO ownership and bank-return toggles.

  reg [1:0] capture_bank_free;
  reg preferred_capture_bank;
  reg capture_writer_active;
  reg capture_drop_active;
  reg capture_writer_bank;
  reg [CAPTURE_SLOT_WIDTH-1:0] capture_expected_slot;

  wire selected_capture_bank =
      capture_bank_free[preferred_capture_bank] ? preferred_capture_bank :
      ~preferred_capture_bank;
  wire selected_capture_bank_valid =
      capture_bank_free[preferred_capture_bank] ||
      capture_bank_free[~preferred_capture_bank];

  wire capture_start_well_formed =
      i_capture_start && i_capture_valid && !i_capture_done &&
      (i_capture_slot == {CAPTURE_SLOT_WIDTH{1'b0}});
  // The paired scheduler drives metadata directly from its registered FIFO
  // destination word and cannot prefetch another word while a capture is
  // pending or active.  That machine-checked composition invariant keeps all
  // three metadata fields stable, avoiding a redundant 160-bit register and
  // equality bank in this resource-constrained bridge.
  wire capture_active_beat_well_formed =
      capture_writer_active && i_capture_valid && !i_capture_start &&
      (i_capture_slot == capture_expected_slot) &&
      (!i_capture_done || (i_capture_slot == CAPTURE_LAST_SLOT));

  wire capture_first_write =
      !i_capture_abort && !capture_writer_active && !capture_drop_active &&
      capture_start_well_formed && selected_capture_bank_valid;
  wire capture_active_write =
      !i_capture_abort && capture_active_beat_well_formed;
  wire capture_memory_write = capture_first_write || capture_active_write;
  wire capture_memory_bank =
      capture_first_write ? selected_capture_bank : capture_writer_bank;
  wire [CAPTURE_MEMORY_ADDRESS_WIDTH-1:0] capture_memory_address = {
    capture_memory_bank,
    i_capture_slot
  };
  wire [95:0] capture_memory_write_data = {
    i_capture_sample_timestamp,
    i_capture_sample_q,
    i_capture_sample_i
  };

  wire descriptor_write_ready;
  wire [1:0] descriptor_fifo_room_unused;
  wire descriptor_read_valid;
  wire descriptor_read_ready;
  wire [DESCRIPTOR_WIDTH-1:0] descriptor_read_data;

  wire descriptor_write_valid =
      !i_capture_abort && capture_active_beat_well_formed && i_capture_done;
  wire [DESCRIPTOR_WIDTH-1:0] descriptor_write_data = {
    capture_writer_bank,
    i_capture_request_id,
    i_capture_center_index,
    i_capture_center_timestamp
  };

  starlink_pss_async_fifo #(
    .DATA_WIDTH    (DESCRIPTOR_WIDTH),
    .ADDRESS_WIDTH (2)
  ) i_descriptor_fifo (
    .i_write_clk    (i_sample_clk),
    .i_write_resetn (i_sample_resetn),
    .i_write_valid  (descriptor_write_valid),
    .o_write_ready  (descriptor_write_ready),
    .i_write_data   (descriptor_write_data),
    .o_write_room   (descriptor_fifo_room_unused),
    .i_read_clk     (i_engine_clk),
    .i_read_resetn  (i_engine_resetn),
    .o_read_valid   (descriptor_read_valid),
    .i_read_ready   (descriptor_read_ready),
    .o_read_data    (descriptor_read_data)
  );

  wire descriptor_write_handshake =
      descriptor_write_valid && descriptor_write_ready;
  reg [1:0] engine_release_toggle;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [1:0] sample_release_toggle_sync_1;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [1:0] sample_release_toggle_sync_2;
  reg [1:0] sample_release_toggle_seen;

  assign o_capture_ready =
      selected_capture_bank_valid && !capture_writer_active &&
      !capture_drop_active;
  assign o_capture_bank_free = capture_bank_free;

  integer release_index;
  always @(posedge i_sample_clk) begin
    if (!i_sample_resetn) begin
      capture_bank_free <= 2'b11;
      preferred_capture_bank <= 1'b0;
      capture_writer_active <= 1'b0;
      capture_drop_active <= 1'b0;
      capture_writer_bank <= 1'b0;
      capture_expected_slot <= {CAPTURE_SLOT_WIDTH{1'b0}};
      sample_release_toggle_sync_1 <= 2'b00;
      sample_release_toggle_sync_2 <= 2'b00;
      sample_release_toggle_seen <= 2'b00;
      o_capture_published_count <= 32'd0;
      o_capture_abort_discard_count <= 32'd0;
      o_capture_buffer_overrun_count <= 32'd0;
      o_capture_protocol_error_count <= 32'd0;
    end else begin
      sample_release_toggle_sync_1 <= engine_release_toggle;
      sample_release_toggle_sync_2 <= sample_release_toggle_sync_1;
      for (release_index = 0; release_index < 2;
           release_index = release_index + 1) begin
        if (sample_release_toggle_sync_2[release_index] !=
            sample_release_toggle_seen[release_index]) begin
          sample_release_toggle_seen[release_index] <=
              sample_release_toggle_sync_2[release_index];
          capture_bank_free[release_index] <= 1'b1;
        end
      end

      if (descriptor_write_handshake) begin
        o_capture_published_count <=
            increment_saturating_32(o_capture_published_count);
      end

      if (i_capture_abort) begin
        if (capture_writer_active) begin
          capture_bank_free[capture_writer_bank] <= 1'b1;
          o_capture_abort_discard_count <=
              increment_saturating_32(o_capture_abort_discard_count);
        end else if (capture_drop_active) begin
          o_capture_abort_discard_count <=
              increment_saturating_32(o_capture_abort_discard_count);
        end
        capture_writer_active <= 1'b0;
        capture_drop_active <= 1'b0;
      end else if (capture_writer_active) begin
        if (!capture_active_beat_well_formed) begin
          if (i_capture_valid || i_capture_start || i_capture_done) begin
            capture_bank_free[capture_writer_bank] <= 1'b1;
            capture_writer_active <= 1'b0;
            capture_drop_active <= !i_capture_done;
            o_capture_protocol_error_count <=
                increment_saturating_32(o_capture_protocol_error_count);
          end
        end else if (i_capture_done) begin
          capture_writer_active <= 1'b0;
          if (!descriptor_write_ready) begin
            // With two banks and a three-entry descriptor FIFO this is
            // unreachable under coordinated reset.  Fail closed if the CDC
            // contract is ever violated rather than exposing partial data.
            capture_bank_free[capture_writer_bank] <= 1'b1;
            o_capture_buffer_overrun_count <=
                increment_saturating_32(o_capture_buffer_overrun_count);
          end
        end else begin
          capture_expected_slot <= capture_expected_slot + 1'b1;
        end
      end else if (capture_drop_active) begin
        if (i_capture_done)
          capture_drop_active <= 1'b0;
      end else if (i_capture_start) begin
        if (!capture_start_well_formed) begin
          capture_drop_active <= !i_capture_done;
          o_capture_protocol_error_count <=
              increment_saturating_32(o_capture_protocol_error_count);
        end else if (selected_capture_bank_valid) begin
          capture_bank_free[selected_capture_bank] <= 1'b0;
          preferred_capture_bank <= ~selected_capture_bank;
          capture_writer_active <= 1'b1;
          capture_writer_bank <= selected_capture_bank;
          capture_expected_slot <= {{(CAPTURE_SLOT_WIDTH-1){1'b0}}, 1'b1};
        end else begin
          capture_drop_active <= 1'b1;
          o_capture_buffer_overrun_count <=
              increment_saturating_32(o_capture_buffer_overrun_count);
        end
      end else if (i_capture_valid || i_capture_done) begin
        capture_drop_active <= !i_capture_done;
        o_capture_protocol_error_count <=
            increment_saturating_32(o_capture_protocol_error_count);
      end
    end
  end

  reg [2:0] engine_state;
  reg engine_bank;
  reg [CAPTURE_SLOT_WIDTH-1:0] engine_slot;
  wire [CAPTURE_MEMORY_ADDRESS_WIDTH-1:0] engine_memory_address = {
    engine_bank, engine_slot
  };
  wire capture_memory_read = (engine_state == ENGINE_ISSUE);
  wire [95:0] capture_memory_read_data;

  ad_mem #(
    .DATA_WIDTH    (96),
    .ADDRESS_WIDTH (CAPTURE_MEMORY_ADDRESS_WIDTH)
  ) i_capture_memory (
    .clka  (i_sample_clk),
    .wea   (capture_memory_write),
    .addra (capture_memory_address),
    .dina  (capture_memory_write_data),
    .clkb  (i_engine_clk),
    .reb   (capture_memory_read),
    .addrb (engine_memory_address),
    .doutb (capture_memory_read_data)
  );

  assign descriptor_read_ready =
      (engine_state == ENGINE_IDLE) && i_engine_job_ready;
  wire descriptor_read_handshake =
      descriptor_read_valid && descriptor_read_ready;
  wire descriptor_read_bank = descriptor_read_data[160];
  wire [31:0] descriptor_read_request_id = descriptor_read_data[159:128];
  wire [63:0] descriptor_read_center_index = descriptor_read_data[127:64];
  wire [63:0] descriptor_read_center_timestamp = descriptor_read_data[63:0];

  assign o_engine_sample_valid = (engine_state == ENGINE_SEND);
  assign o_engine_request_id = descriptor_read_request_id;
  assign o_engine_center_index = descriptor_read_center_index;
  assign o_engine_center_timestamp = descriptor_read_center_timestamp;
  assign o_engine_sample_slot = engine_slot;
  assign o_engine_sample_timestamp = capture_memory_read_data[95:32];
  assign o_engine_sample_q = capture_memory_read_data[31:16];
  assign o_engine_sample_i = capture_memory_read_data[15:0];

  always @(posedge i_engine_clk) begin
    if (!i_engine_resetn) begin
      engine_state <= ENGINE_IDLE;
      engine_bank <= 1'b0;
      engine_slot <= {CAPTURE_SLOT_WIDTH{1'b0}};
      engine_release_toggle <= 2'b00;
      o_engine_job_start <= 1'b0;
      o_engine_job_done <= 1'b0;
      o_engine_consumed_count <= 32'd0;
    end else begin
      o_engine_job_start <= 1'b0;
      o_engine_job_done <= 1'b0;

      case (engine_state)
        ENGINE_IDLE: begin
          if (descriptor_read_handshake) begin
            engine_bank <= descriptor_read_bank;
            engine_slot <= {CAPTURE_SLOT_WIDTH{1'b0}};
            o_engine_job_start <= 1'b1;
            engine_state <= ENGINE_ISSUE;
          end
        end

        ENGINE_ISSUE: begin
          engine_state <= ENGINE_WAIT;
        end

        ENGINE_WAIT: begin
          engine_state <= ENGINE_SEND;
        end

        ENGINE_SEND: begin
          if (i_engine_sample_ready) begin
            if (engine_slot == CAPTURE_LAST_SLOT) begin
              engine_release_toggle[engine_bank] <=
                  ~engine_release_toggle[engine_bank];
              o_engine_job_done <= 1'b1;
              o_engine_consumed_count <=
                  increment_saturating_32(o_engine_consumed_count);
              engine_state <= ENGINE_IDLE;
            end else begin
              engine_slot <= engine_slot + 1'b1;
              engine_state <= ENGINE_ISSUE;
            end
          end
        end

        default: begin
          engine_state <= ENGINE_IDLE;
        end
      endcase
    end
  end

endmodule
