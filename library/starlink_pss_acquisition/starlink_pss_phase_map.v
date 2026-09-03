// SPDX-License-Identifier: GPL-2.0
//
// Continuous, one-sample-resolution phase-map accumulator for the
// experimental Starlink PSS acquisition path.  This block consumes an
// already-normalized score stream.  It never gates or backpressures RX DMA.
//
// Two map banks permit software to read one complete tile while the other is
// filled.  Only complete, consecutive nominal frames are published.  A score
// phase or absolute-index discontinuity invalidates and clears the active map.

`timescale 1ns/1ps

module starlink_pss_phase_map #(
  parameter integer PHASE_BINS = 20000,
  parameter integer PHASE_INDEX_WIDTH = 15,
  parameter integer TILE_FRAMES = 64,
  parameter integer TILE_FRAME_WIDTH = 6,
  parameter integer SCORE_WIDTH = 8,
  parameter integer MAP_WIDTH = 16,
  parameter integer MAP_SEGMENT_ADDRESS_WIDTH = 11,
  parameter integer MAP_SEGMENT_COUNT = 10,
  parameter integer MAP_SEGMENT_INDEX_WIDTH = 4
) (
  input  wire                           clk,
  input  wire                           resetn,
  input  wire                           acquisition_enable,

  input  wire                           score_valid,
  input  wire [63:0]                    score_start_index,
  input  wire [PHASE_INDEX_WIDTH-1:0]   score_phase,
  input  wire [SCORE_WIDTH-1:0]         score_value,
  input  wire                           stream_discontinuity,

  output wire [1:0]                     map_ready_mask,
  output wire [31:0]                    map_generation_0,
  output wire [31:0]                    map_generation_1,
  output wire [63:0]                    map_start_index_0,
  output wire [63:0]                    map_start_index_1,

  input  wire                           map_read_request,
  input  wire                           map_read_bank,
  input  wire [PHASE_INDEX_WIDTH-1:0]   map_read_index,
  output reg                            map_read_valid,
  output reg  [MAP_WIDTH-1:0]           map_read_data,
  output reg                            map_read_error,

  input  wire                           map_release,
  input  wire                           map_release_bank,

  output reg  [31:0]                    accepted_score_count,
  output reg  [31:0]                    discarded_score_count,
  output reg  [31:0]                    discontinuity_abort_count,
  output reg  [31:0]                    map_publish_count,
  output reg  [31:0]                    map_overrun_count,
  output reg  [31:0]                    score_protocol_error_count,
  output reg  [31:0]                    map_arithmetic_overflow_count,
  output reg  [31:0]                    map_read_error_count,
  output reg  [31:0]                    map_release_error_count
);

  localparam [1:0] STATE_WAIT_BANK = 2'd0;
  localparam [1:0] STATE_WAIT_FRAME = 2'd1;
  localparam [1:0] STATE_FILL = 2'd2;
  localparam [1:0] STATE_DRAIN = 2'd3;

  localparam [PHASE_INDEX_WIDTH-1:0] LAST_PHASE = PHASE_BINS - 1;
  localparam [TILE_FRAME_WIDTH-1:0] LAST_FRAME = TILE_FRAMES - 1;

  generate
    if (PHASE_BINS < 2) begin : g_invalid_phase_bins
      initial $fatal(1, "phase map requires at least two phase bins");
    end
    if ((1 << PHASE_INDEX_WIDTH) < PHASE_BINS) begin : g_invalid_phase_width
      initial $fatal(1, "PHASE_INDEX_WIDTH cannot address every phase bin");
    end
    if (TILE_FRAMES < 2) begin : g_invalid_tile_frames
      initial $fatal(1, "phase map requires at least two frames per tile");
    end
    if ((1 << TILE_FRAME_WIDTH) < TILE_FRAMES) begin : g_invalid_frame_width
      initial $fatal(1, "TILE_FRAME_WIDTH cannot count every tile frame");
    end
    if ((TILE_FRAMES * ((1 << SCORE_WIDTH) - 1)) >= (1 << MAP_WIDTH)) begin : g_invalid_map_width
      initial $fatal(1, "one phase-map bin can overflow MAP_WIDTH");
    end
  endgenerate

  function automatic [31:0] increment_saturating_32;
    input [31:0] value;
    begin
      increment_saturating_32 = (&value) ? value : value + 1'b1;
    end
  endfunction

  wire [MAP_WIDTH-1:0] bank_read_data_0;
  wire [MAP_WIDTH-1:0] bank_read_data_1;

  reg [1:0] state;
  reg fill_bank;
  reg [PHASE_INDEX_WIDTH-1:0] expected_phase;
  reg [TILE_FRAME_WIDTH-1:0] frame_index;
  reg [63:0] expected_score_index;
  reg [63:0] active_tile_start_index;

  reg update_pending;
  reg update_bank;
  reg [PHASE_INDEX_WIDTH-1:0] update_address;
  reg [SCORE_WIDTH-1:0] update_score;

  // Register the completed read/modify result before driving the segmented
  // BRAM write ports.  This separates the segment read mux plus accumulator
  // from the BRAM input path without reducing score-stream throughput.
  reg write_pending;
  reg write_bank;
  reg [PHASE_INDEX_WIDTH-1:0] write_address;
  reg [MAP_WIDTH-1:0] write_data;

  // A completed tile becomes software-visible on the clock that its final
  // registered update is committed.  DRAIN may already accept phase zero of
  // the next tile into the other bank, so publication needs its own pipeline
  // state rather than stalling the score stream.
  reg publish_pending;
  reg publish_bank;

  reg ready_0;
  reg ready_1;
  reg clean_0;
  reg clean_1;
  reg clear_active_0;
  reg clear_active_1;
  reg [PHASE_INDEX_WIDTH-1:0] clear_address_0;
  reg [PHASE_INDEX_WIDTH-1:0] clear_address_1;
  reg [31:0] generation_0;
  reg [31:0] generation_1;
  reg [63:0] start_index_0;
  reg [63:0] start_index_1;
  reg read_pending;
  reg read_pending_bank;
  reg read_pending_allowed;

  wire score_accept_wait_frame = acquisition_enable &&
      state == STATE_WAIT_FRAME && score_valid && !stream_discontinuity &&
      score_phase == 0;
  wire drain_next_bank_clean = fill_bank ?
      (clean_0 && !ready_0 && !clear_active_0) :
      (clean_1 && !ready_1 && !clear_active_1);
  wire score_accept_drain = acquisition_enable && state == STATE_DRAIN &&
      drain_next_bank_clean && score_valid && !stream_discontinuity &&
      score_phase == 0 && score_start_index == expected_score_index;
  // A wrong absolute index aborts the tile and suppresses update_pending, so
  // an otherwise well-phased speculative BRAM read is harmless.  Keep the
  // 64-bit protocol comparison in the state/control path, but do not put it
  // in front of twenty physically distributed BRAM read enables.
  wire score_read_fill = acquisition_enable && state == STATE_FILL &&
      score_valid && !stream_discontinuity &&
      score_phase == expected_phase;
  wire score_read_drain = acquisition_enable && state == STATE_DRAIN &&
      drain_next_bank_clean && score_valid && !stream_discontinuity &&
      score_phase == 0;
  wire score_read = score_accept_wait_frame || score_read_fill ||
      score_read_drain;
  wire score_read_bank = (state == STATE_DRAIN) ? !fill_bank : fill_bank;

  // The elaboration guard above proves TILE_FRAMES maximum scores fit in
  // MAP_WIDTH.  Every clean bank starts at zero and each phase is updated
  // exactly once per frame, so saturation and a runtime overflow detector
  // would be unreachable hardware.  Keep the ABI counter as an invariant
  // zero while retaining the exact full-width sum here.
  wire [MAP_WIDTH-1:0] update_sum_0 =
      bank_read_data_0 + update_score;
  wire [MAP_WIDTH-1:0] update_sum_1 =
      bank_read_data_1 + update_score;

  wire bank_write_enable_0 = clear_active_0 ||
      (write_pending && !write_bank);
  wire bank_write_enable_1 = clear_active_1 ||
      (write_pending && write_bank);
  wire [PHASE_INDEX_WIDTH-1:0] bank_write_address_0 =
      clear_active_0 ? clear_address_0 : write_address;
  wire [PHASE_INDEX_WIDTH-1:0] bank_write_address_1 =
      clear_active_1 ? clear_address_1 : write_address;
  wire [MAP_WIDTH-1:0] bank_write_data_0 = clear_active_0 ?
      {MAP_WIDTH{1'b0}} : write_data;
  wire [MAP_WIDTH-1:0] bank_write_data_1 = clear_active_1 ?
      {MAP_WIDTH{1'b0}} : write_data;
  wire bank_read_enable_0 = (score_read && !score_read_bank) ||
      (map_read_request && !map_read_bank);
  wire bank_read_enable_1 = (score_read && score_read_bank) ||
      (map_read_request && map_read_bank);
  wire [PHASE_INDEX_WIDTH-1:0] bank_read_address_0 =
      (score_read && !score_read_bank) ? score_phase : map_read_index;
  wire [PHASE_INDEX_WIDTH-1:0] bank_read_address_1 =
      (score_read && score_read_bank) ? score_phase : map_read_index;

  assign map_ready_mask = {ready_1, ready_0};
  assign map_generation_0 = generation_0;
  assign map_generation_1 = generation_1;
  assign map_start_index_0 = start_index_0;
  assign map_start_index_1 = start_index_1;

  // Port A writes a pending score update or clears a bank.  Port B reads the
  // next score address while a bank is filling, then becomes the software
  // read port while that bank is immutable.  A filling bank is never a legal
  // software-read target, so this is a true two-port memory rather than an
  // accidental three-port replication.  The explicit clear walkers establish
  // memory validity after reset/release.
  starlink_pss_phase_map_bank #(
    .DEPTH        (PHASE_BINS),
    .ADDRESS_WIDTH(PHASE_INDEX_WIDTH),
    .DATA_WIDTH   (MAP_WIDTH),
    .SEGMENT_ADDRESS_WIDTH(MAP_SEGMENT_ADDRESS_WIDTH),
    .SEGMENT_COUNT(MAP_SEGMENT_COUNT),
    .SEGMENT_INDEX_WIDTH(MAP_SEGMENT_INDEX_WIDTH)
  ) i_map_bank_0 (
    .clk          (clk),
    .write_enable (bank_write_enable_0),
    .write_address(bank_write_address_0),
    .write_data   (bank_write_data_0),
    .read_enable  (bank_read_enable_0),
    .read_address (bank_read_address_0),
    .read_data    (bank_read_data_0)
  );

  starlink_pss_phase_map_bank #(
    .DEPTH        (PHASE_BINS),
    .ADDRESS_WIDTH(PHASE_INDEX_WIDTH),
    .DATA_WIDTH   (MAP_WIDTH),
    .SEGMENT_ADDRESS_WIDTH(MAP_SEGMENT_ADDRESS_WIDTH),
    .SEGMENT_COUNT(MAP_SEGMENT_COUNT),
    .SEGMENT_INDEX_WIDTH(MAP_SEGMENT_INDEX_WIDTH)
  ) i_map_bank_1 (
    .clk          (clk),
    .write_enable (bank_write_enable_1),
    .write_address(bank_write_address_1),
    .write_data   (bank_write_data_1),
    .read_enable  (bank_read_enable_1),
    .read_address (bank_read_address_1),
    .read_data    (bank_read_data_1)
  );

  always @(posedge clk) begin
    if (!resetn) begin
      state <= STATE_WAIT_BANK;
      fill_bank <= 1'b0;
      expected_phase <= {PHASE_INDEX_WIDTH{1'b0}};
      frame_index <= {TILE_FRAME_WIDTH{1'b0}};
      expected_score_index <= 64'd0;
      active_tile_start_index <= 64'd0;

      update_pending <= 1'b0;
      update_bank <= 1'b0;
      update_address <= {PHASE_INDEX_WIDTH{1'b0}};
      update_score <= {SCORE_WIDTH{1'b0}};
      write_pending <= 1'b0;
      write_bank <= 1'b0;
      write_address <= {PHASE_INDEX_WIDTH{1'b0}};
      write_data <= {MAP_WIDTH{1'b0}};
      publish_pending <= 1'b0;
      publish_bank <= 1'b0;

      ready_0 <= 1'b0;
      ready_1 <= 1'b0;
      clean_0 <= 1'b0;
      clean_1 <= 1'b0;
      clear_active_0 <= 1'b1;
      clear_active_1 <= 1'b1;
      clear_address_0 <= {PHASE_INDEX_WIDTH{1'b0}};
      clear_address_1 <= {PHASE_INDEX_WIDTH{1'b0}};
      generation_0 <= 32'd0;
      generation_1 <= 32'd0;
      start_index_0 <= 64'd0;
      start_index_1 <= 64'd0;

      map_read_valid <= 1'b0;
      map_read_data <= {MAP_WIDTH{1'b0}};
      map_read_error <= 1'b0;
      read_pending <= 1'b0;
      read_pending_bank <= 1'b0;
      read_pending_allowed <= 1'b0;

      accepted_score_count <= 32'd0;
      discarded_score_count <= 32'd0;
      discontinuity_abort_count <= 32'd0;
      map_publish_count <= 32'd0;
      map_overrun_count <= 32'd0;
      score_protocol_error_count <= 32'd0;
      map_arithmetic_overflow_count <= 32'd0;
      map_read_error_count <= 32'd0;
      map_release_error_count <= 32'd0;
    end else begin
      map_read_valid <= 1'b0;
      map_read_error <= 1'b0;
      update_pending <= 1'b0;
      write_pending <= update_pending;
      publish_pending <= 1'b0;

      if (update_pending) begin
        write_bank <= update_bank;
        write_address <= update_address;
        write_data <= update_bank ? update_sum_1 : update_sum_0;
      end

      // The final map word is written by the BRAMs on this same edge.  DRAIN
      // preloads metadata while ready is low; asserting ready here publishes
      // that metadata and the now-complete map atomically to software.
      if (publish_pending) begin
        if (!publish_bank)
          ready_0 <= 1'b1;
        else
          ready_1 <= 1'b1;
      end

      if (read_pending) begin
        if (read_pending_allowed) begin
          map_read_valid <= 1'b1;
          map_read_data <= read_pending_bank ?
              bank_read_data_1 : bank_read_data_0;
        end else begin
          map_read_error <= 1'b1;
          map_read_error_count <=
              increment_saturating_32(map_read_error_count);
        end
      end
      read_pending <= map_read_request;
      if (map_read_request) begin
        read_pending_bank <= map_read_bank;
        read_pending_allowed <= (map_read_index < PHASE_BINS) &&
            ((!map_read_bank && ready_0) || (map_read_bank && ready_1)) &&
            !(map_release && map_release_bank == map_read_bank);
      end

      if (clear_active_0) begin
        if (clear_address_0 == LAST_PHASE) begin
          clear_active_0 <= 1'b0;
          clear_address_0 <= {PHASE_INDEX_WIDTH{1'b0}};
          clean_0 <= 1'b1;
        end else begin
          clear_address_0 <= clear_address_0 + 1'b1;
        end
      end
      if (clear_active_1) begin
        if (clear_address_1 == LAST_PHASE) begin
          clear_active_1 <= 1'b0;
          clear_address_1 <= {PHASE_INDEX_WIDTH{1'b0}};
          clean_1 <= 1'b1;
        end else begin
          clear_address_1 <= clear_address_1 + 1'b1;
        end
      end

      if (map_release) begin
        if (!map_release_bank && ready_0) begin
          ready_0 <= 1'b0;
          clean_0 <= 1'b0;
          clear_active_0 <= 1'b1;
          clear_address_0 <= {PHASE_INDEX_WIDTH{1'b0}};
        end else if (map_release_bank && ready_1) begin
          ready_1 <= 1'b0;
          clean_1 <= 1'b0;
          clear_active_1 <= 1'b1;
          clear_address_1 <= {PHASE_INDEX_WIDTH{1'b0}};
        end else begin
          map_release_error_count <=
              increment_saturating_32(map_release_error_count);
        end
      end

      // DRAIN owns a complete tile whose final read result is entering the
      // registered write stage.  Let that state queue publication once even
      // if software disables acquisition on the immediately following cycle;
      // only partial FILL state is invalidated by disable.
      if (!acquisition_enable && state != STATE_DRAIN) begin
        if (state == STATE_FILL) begin
          discontinuity_abort_count <=
              increment_saturating_32(discontinuity_abort_count);
          if (!fill_bank) begin
            clean_0 <= 1'b0;
            clear_active_0 <= 1'b1;
            clear_address_0 <= {PHASE_INDEX_WIDTH{1'b0}};
          end else begin
            clean_1 <= 1'b0;
            clear_active_1 <= 1'b1;
            clear_address_1 <= {PHASE_INDEX_WIDTH{1'b0}};
          end
        end else if (state == STATE_WAIT_FRAME) begin
          // No score has touched the reserved bank yet, so return it directly
          // to the clean pool instead of stranding it across disable.
          if (!fill_bank)
            clean_0 <= 1'b1;
          else
            clean_1 <= 1'b1;
        end
        state <= STATE_WAIT_BANK;
        if (score_valid)
          discarded_score_count <=
              increment_saturating_32(discarded_score_count);
      end else begin
        case (state)
          STATE_WAIT_BANK: begin
            if (clean_0 && !ready_0 && !clear_active_0) begin
              fill_bank <= 1'b0;
              clean_0 <= 1'b0;
              state <= STATE_WAIT_FRAME;
            end else if (clean_1 && !ready_1 && !clear_active_1) begin
              fill_bank <= 1'b1;
              clean_1 <= 1'b0;
              state <= STATE_WAIT_FRAME;
            end
            if (score_valid)
              discarded_score_count <=
                  increment_saturating_32(discarded_score_count);
          end

          STATE_WAIT_FRAME: begin
            if (score_valid) begin
              if (!stream_discontinuity && score_phase == 0) begin
                active_tile_start_index <= score_start_index;
                expected_score_index <= score_start_index + 1'b1;
                expected_phase <= {{(PHASE_INDEX_WIDTH-1){1'b0}}, 1'b1};
                frame_index <= {TILE_FRAME_WIDTH{1'b0}};
                update_pending <= 1'b1;
                update_bank <= fill_bank;
                update_address <= score_phase;
                update_score <= score_value;
                accepted_score_count <=
                    increment_saturating_32(accepted_score_count);
                state <= STATE_FILL;
              end else begin
                discarded_score_count <=
                    increment_saturating_32(discarded_score_count);
              end
            end
          end

          STATE_FILL: begin
            if (stream_discontinuity ||
                (score_valid &&
                 (score_phase != expected_phase ||
                  score_start_index != expected_score_index))) begin
              discontinuity_abort_count <=
                  increment_saturating_32(discontinuity_abort_count);
              if (score_valid && !stream_discontinuity)
                score_protocol_error_count <=
                    increment_saturating_32(score_protocol_error_count);
              if (!fill_bank) begin
                clean_0 <= 1'b0;
                clear_active_0 <= 1'b1;
                clear_address_0 <= {PHASE_INDEX_WIDTH{1'b0}};
              end else begin
                clean_1 <= 1'b0;
                clear_active_1 <= 1'b1;
                clear_address_1 <= {PHASE_INDEX_WIDTH{1'b0}};
              end
              state <= STATE_WAIT_BANK;
              if (score_valid)
                discarded_score_count <=
                    increment_saturating_32(discarded_score_count);
            end else if (score_valid) begin
              update_pending <= 1'b1;
              update_bank <= fill_bank;
              update_address <= score_phase;
              update_score <= score_value;
              accepted_score_count <=
                  increment_saturating_32(accepted_score_count);
              expected_score_index <= score_start_index + 1'b1;
              if (score_phase == LAST_PHASE) begin
                expected_phase <= {PHASE_INDEX_WIDTH{1'b0}};
                if (frame_index == LAST_FRAME) begin
                  state <= STATE_DRAIN;
                end else begin
                  frame_index <= frame_index + 1'b1;
                end
              end else begin
                expected_phase <= expected_phase + 1'b1;
              end
            end
          end

          STATE_DRAIN: begin
            publish_pending <= 1'b1;
            publish_bank <= fill_bank;
            map_publish_count <= increment_saturating_32(map_publish_count);
            if (!fill_bank) begin
              generation_0 <= increment_saturating_32(map_publish_count);
              start_index_0 <= active_tile_start_index;
              if (acquisition_enable &&
                  clean_1 && !ready_1 && !clear_active_1) begin
                fill_bank <= 1'b1;
                clean_1 <= 1'b0;
                if (score_accept_drain) begin
                  active_tile_start_index <= score_start_index;
                  expected_score_index <= score_start_index + 1'b1;
                  expected_phase <=
                      {{(PHASE_INDEX_WIDTH-1){1'b0}}, 1'b1};
                  frame_index <= {TILE_FRAME_WIDTH{1'b0}};
                  update_pending <= 1'b1;
                  update_bank <= 1'b1;
                  update_address <= score_phase;
                  update_score <= score_value;
                  accepted_score_count <=
                      increment_saturating_32(accepted_score_count);
                  state <= STATE_FILL;
                end else begin
                  state <= STATE_WAIT_FRAME;
                  if (score_valid)
                    discarded_score_count <=
                        increment_saturating_32(discarded_score_count);
                end
              end else begin
                state <= STATE_WAIT_BANK;
                if (acquisition_enable)
                  map_overrun_count <=
                      increment_saturating_32(map_overrun_count);
                if (score_valid)
                  discarded_score_count <=
                      increment_saturating_32(discarded_score_count);
              end
            end else begin
              generation_1 <= increment_saturating_32(map_publish_count);
              start_index_1 <= active_tile_start_index;
              if (acquisition_enable &&
                  clean_0 && !ready_0 && !clear_active_0) begin
                fill_bank <= 1'b0;
                clean_0 <= 1'b0;
                if (score_accept_drain) begin
                  active_tile_start_index <= score_start_index;
                  expected_score_index <= score_start_index + 1'b1;
                  expected_phase <=
                      {{(PHASE_INDEX_WIDTH-1){1'b0}}, 1'b1};
                  frame_index <= {TILE_FRAME_WIDTH{1'b0}};
                  update_pending <= 1'b1;
                  update_bank <= 1'b0;
                  update_address <= score_phase;
                  update_score <= score_value;
                  accepted_score_count <=
                      increment_saturating_32(accepted_score_count);
                  state <= STATE_FILL;
                end else begin
                  state <= STATE_WAIT_FRAME;
                  if (score_valid)
                    discarded_score_count <=
                        increment_saturating_32(discarded_score_count);
                end
              end else begin
                state <= STATE_WAIT_BANK;
                if (acquisition_enable)
                  map_overrun_count <=
                      increment_saturating_32(map_overrun_count);
                if (score_valid)
                  discarded_score_count <=
                      increment_saturating_32(discarded_score_count);
              end
            end
          end

          default: state <= STATE_WAIT_BANK;
        endcase
      end
    end
  end

endmodule
