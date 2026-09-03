// SPDX-License-Identifier: GPL-2.0
//
// AXI4-Lite and CDC boundary for immutable Starlink PSS phase maps.
//
// The acquisition side owns the phase-map memories.  This bridge transfers
// one explicit read or release command at a time with toggle mailboxes, and
// returns read data only after a source-domain acknowledgement.  Map metadata
// and counters are captured atomically into a separate 16-word snapshot.
// No acquisition sample or score is ever backpressured by this block.

`timescale 1ns/1ps

module axi_starlink_pss_phase_map #(
  parameter integer PHASE_BINS = 20000,
  parameter integer PHASE_INDEX_WIDTH = 15,
  parameter integer TILE_FRAMES = 64,
  parameter integer MAP_WIDTH = 16
) (
  input  wire                          map_clk,
  input  wire                          map_reset,

  input  wire [1:0]                    map_ready_mask,
  input  wire [31:0]                   map_generation_0,
  input  wire [31:0]                   map_generation_1,
  input  wire [63:0]                   map_start_index_0,
  input  wire [63:0]                   map_start_index_1,

  output reg                           map_read_request,
  output reg                           map_read_bank,
  output reg  [PHASE_INDEX_WIDTH-1:0]  map_read_index,
  input  wire                          map_read_valid,
  input  wire [MAP_WIDTH-1:0]          map_read_data,
  input  wire                          map_read_error,

  output reg                           map_release,
  output reg                           map_release_bank,

  input  wire [31:0]                   accepted_score_count,
  input  wire [31:0]                   discarded_score_count,
  input  wire [31:0]                   discontinuity_abort_count,
  input  wire [31:0]                   map_publish_count,
  input  wire [31:0]                   map_overrun_count,
  input  wire [31:0]                   score_protocol_error_count,
  input  wire [31:0]                   map_arithmetic_overflow_count,
  input  wire [31:0]                   map_read_error_count,
  input  wire [31:0]                   map_release_error_count,

  output wire                          acquisition_enable,
  output reg                           acquisition_flush,
  output wire                          irq,

  input  wire                          s_axi_aclk,
  input  wire                          s_axi_aresetn,
  input  wire                          s_axi_awvalid,
  input  wire [7:0]                    s_axi_awaddr,
  output wire                          s_axi_awready,
  input  wire                          s_axi_wvalid,
  input  wire [31:0]                   s_axi_wdata,
  input  wire [3:0]                    s_axi_wstrb,
  output wire                          s_axi_wready,
  output wire                          s_axi_bvalid,
  output wire [1:0]                    s_axi_bresp,
  input  wire                          s_axi_bready,
  input  wire                          s_axi_arvalid,
  input  wire [7:0]                    s_axi_araddr,
  output wire                          s_axi_arready,
  output wire                          s_axi_rvalid,
  output wire [1:0]                    s_axi_rresp,
  output wire [31:0]                   s_axi_rdata,
  input  wire                          s_axi_rready,
  input  wire [2:0]                    s_axi_awprot,
  input  wire [2:0]                    s_axi_arprot
);

  localparam [31:0] IDENTIFICATION = 32'h5053_4d41; // ASCII "PSMA".
  localparam [31:0] VERSION = 32'h0001_0000;
  localparam [31:0] CAPABILITIES = 32'h0000_001f;
  localparam [31:0] TILE_GEOMETRY =
      (TILE_FRAMES << 16) | (MAP_WIDTH << 8) | 2;
  localparam [PHASE_INDEX_WIDTH-1:0] LAST_PHASE = PHASE_BINS - 1;
  // Fifteen full telemetry words plus the two meaningful ready-mask bits.
  // The AXI register view expands the mask back to a zero-extended word.
  localparam integer SNAPSHOT_BITS = 482;

  localparam [5:0] REG_IDENTIFICATION = 6'h00; // 0x00
  localparam [5:0] REG_VERSION = 6'h01; // 0x04
  localparam [5:0] REG_PHASE_BINS = 6'h02; // 0x08
  localparam [5:0] REG_TILE_GEOMETRY = 6'h03; // 0x0c
  localparam [5:0] REG_CAPABILITIES = 6'h04; // 0x10
  localparam [5:0] REG_CONTROL = 6'h05; // 0x14
  localparam [5:0] REG_STATUS = 6'h06; // 0x18
  localparam [5:0] REG_MAP_SELECT = 6'h07; // 0x1c
  localparam [5:0] REG_MAP_INDEX = 6'h08; // 0x20
  localparam [5:0] REG_MAP_DATA = 6'h09; // 0x24
  localparam [5:0] REG_MAP_RELEASE = 6'h0a; // 0x28
  localparam [5:0] REG_COMMAND_STATUS = 6'h0b; // 0x2c
  localparam [5:0] REG_SNAPSHOT_CONTROL = 6'h0c; // 0x30
  localparam [5:0] REG_SNAPSHOT_STATUS = 6'h0d; // 0x34
  localparam [5:0] REG_SNAPSHOT_GENERATION = 6'h0e; // 0x38
  localparam [5:0] REG_SNAPSHOT_READY = 6'h0f; // 0x3c
  localparam [5:0] REG_SNAPSHOT_MAP_GENERATION_0 = 6'h10; // 0x40
  localparam [5:0] REG_SNAPSHOT_MAP_GENERATION_1 = 6'h11; // 0x44
  localparam [5:0] REG_SNAPSHOT_START_INDEX_0_LO = 6'h12; // 0x48
  localparam [5:0] REG_SNAPSHOT_START_INDEX_0_HI = 6'h13; // 0x4c
  localparam [5:0] REG_SNAPSHOT_START_INDEX_1_LO = 6'h14; // 0x50
  localparam [5:0] REG_SNAPSHOT_START_INDEX_1_HI = 6'h15; // 0x54
  localparam [5:0] REG_SNAPSHOT_ACCEPTED = 6'h16; // 0x58
  localparam [5:0] REG_SNAPSHOT_DISCARDED = 6'h17; // 0x5c
  localparam [5:0] REG_SNAPSHOT_DISCONTINUITY = 6'h18; // 0x60
  localparam [5:0] REG_SNAPSHOT_PUBLISHED = 6'h19; // 0x64
  localparam [5:0] REG_SNAPSHOT_OVERRUN = 6'h1a; // 0x68
  localparam [5:0] REG_SNAPSHOT_PROTOCOL_ERROR = 6'h1b; // 0x6c
  localparam [5:0] REG_SNAPSHOT_ARITHMETIC_OVERFLOW = 6'h1c; // 0x70
  localparam [5:0] REG_SNAPSHOT_READ_ERROR = 6'h1d; // 0x74
  localparam [5:0] REG_SNAPSHOT_RELEASE_ERROR = 6'h1e; // 0x78
  localparam [5:0] REG_BRIDGE_READ_ERROR = 6'h1f; // 0x7c
  localparam [5:0] REG_BRIDGE_RELEASE_ERROR = 6'h20; // 0x80
  localparam [5:0] REG_SNAPSHOT_REQUEST_OVERRUN = 6'h21; // 0x84

  generate
    if (PHASE_BINS < 2) begin : g_invalid_phase_bins
      initial $fatal(1, "phase-map AXI bridge requires at least two bins");
    end
    if ((64'd1 << PHASE_INDEX_WIDTH) < PHASE_BINS) begin : g_invalid_phase_width
      initial $fatal(1, "PHASE_INDEX_WIDTH cannot address every phase bin");
    end
    if (PHASE_INDEX_WIDTH < 1 || PHASE_INDEX_WIDTH > 31) begin : g_invalid_phase_index_width
      initial $fatal(1, "PHASE_INDEX_WIDTH must lie in [1, 31]");
    end
    if (TILE_FRAMES < 2 || TILE_FRAMES > 255) begin : g_invalid_tile_frames
      initial $fatal(1, "TILE_FRAMES must lie in [2, 255]");
    end
    if (MAP_WIDTH < 1 || MAP_WIDTH > 32) begin : g_invalid_map_width
      initial $fatal(1, "MAP_WIDTH must lie in [1, 32]");
    end
  endgenerate

  function automatic [31:0] increment_saturating_32;
    input [31:0] value;
    begin
      increment_saturating_32 = (&value) ? value : value + 1'b1;
    end
  endfunction

  // One asynchronous epoch resets both domains.  The local map reset also
  // clears the AXI/control state after a synchronized observation, preventing
  // a pre-reset command from being replayed into a new acquisition epoch.
  wire reset_epoch_async_n = s_axi_aresetn;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [1:0] control_reset_sync;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [1:0] map_reset_sync;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [1:0] map_reset_control_sync;

  always @(posedge s_axi_aclk or negedge reset_epoch_async_n) begin
    if (!reset_epoch_async_n)
      control_reset_sync <= 2'b00;
    else
      control_reset_sync <= {control_reset_sync[0], 1'b1};
  end

  always @(posedge map_clk or negedge reset_epoch_async_n) begin
    if (!reset_epoch_async_n)
      map_reset_sync <= 2'b00;
    else
      map_reset_sync <= {map_reset_sync[0], 1'b1};
  end

  always @(posedge s_axi_aclk or negedge reset_epoch_async_n) begin
    if (!reset_epoch_async_n)
      map_reset_control_sync <= 2'b11;
    else
      map_reset_control_sync <= {map_reset_control_sync[0], map_reset};
  end

  wire core_control_resetn =
      control_reset_sync[1] && !map_reset_control_sync[1];
  wire core_map_resetn = map_reset_sync[1] && !map_reset;

  // AXI-programmed enable is a level.  Flush is a one-shot toggle mailbox.
  reg control_enable;
  reg flush_request_toggle;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [1:0] control_enable_map_sync;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [1:0] flush_request_sync;
  reg flush_request_seen;

  assign acquisition_enable = core_map_resetn && control_enable_map_sync[1];

  always @(posedge map_clk) begin
    if (!core_map_resetn) begin
      control_enable_map_sync <= 2'b00;
      flush_request_sync <= 2'b00;
      flush_request_seen <= 1'b0;
      acquisition_flush <= 1'b0;
    end else begin
      control_enable_map_sync <= {
        control_enable_map_sync[0], control_enable
      };
      flush_request_sync <= {flush_request_sync[0], flush_request_toggle};
      acquisition_flush <= 1'b0;
      if (flush_request_sync[1] != flush_request_seen) begin
        flush_request_seen <= flush_request_sync[1];
        acquisition_flush <= 1'b1;
      end
    end
  end

  // Map-read command and response mailboxes.  The request payload remains
  // fixed until the response has crossed back into AXI.  The map side waits
  // one additional clock after seeing a command toggle.  The AXI side also
  // gives returned read data one additional clock after its response toggle;
  // slower control-only responses use two.  The map-side read interface has
  // a bounded one-request/one-response contract.
  reg read_request_toggle;
  reg read_request_bank;
  reg [PHASE_INDEX_WIDTH-1:0] read_request_index;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [1:0] read_request_sync;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg read_request_bank_sync_1;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg read_request_bank_sync_2;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [PHASE_INDEX_WIDTH-1:0] read_request_index_sync_1;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [PHASE_INDEX_WIDTH-1:0] read_request_index_sync_2;
  reg read_request_seen;
  reg [1:0] read_request_settle_count;
  reg map_read_inflight;
  reg read_response_toggle;
  reg [MAP_WIDTH:0] read_response_payload;

  always @(posedge map_clk) begin
    if (!core_map_resetn) begin
      read_request_sync <= 2'b00;
      read_request_bank_sync_1 <= 1'b0;
      read_request_bank_sync_2 <= 1'b0;
      read_request_index_sync_1 <= {PHASE_INDEX_WIDTH{1'b0}};
      read_request_index_sync_2 <= {PHASE_INDEX_WIDTH{1'b0}};
      read_request_seen <= 1'b0;
      read_request_settle_count <= 2'd0;
      map_read_inflight <= 1'b0;
      map_read_request <= 1'b0;
      map_read_bank <= 1'b0;
      map_read_index <= {PHASE_INDEX_WIDTH{1'b0}};
      read_response_toggle <= 1'b0;
      read_response_payload <= {(MAP_WIDTH+1){1'b0}};
    end else begin
      read_request_sync <= {read_request_sync[0], read_request_toggle};
      read_request_bank_sync_1 <= read_request_bank;
      read_request_bank_sync_2 <= read_request_bank_sync_1;
      read_request_index_sync_1 <= read_request_index;
      read_request_index_sync_2 <= read_request_index_sync_1;
      map_read_request <= 1'b0;

      if (!map_read_inflight && read_request_settle_count == 0 &&
          read_request_sync[1] != read_request_seen) begin
        read_request_seen <= read_request_sync[1];
        read_request_settle_count <= 2'd1;
      end else if (read_request_settle_count != 0) begin
        read_request_settle_count <= read_request_settle_count - 1'b1;
        if (read_request_settle_count == 1) begin
          map_read_bank <= read_request_bank_sync_2;
          map_read_index <= read_request_index_sync_2;
          map_read_request <= 1'b1;
          map_read_inflight <= 1'b1;
        end
      end

      if (map_read_inflight && (map_read_valid || map_read_error)) begin
        read_response_payload <= {
          map_read_error, map_read_error ? {MAP_WIDTH{1'b0}} : map_read_data
        };
        read_response_toggle <= read_request_seen;
        map_read_inflight <= 1'b0;
      end
    end
  end

  // Release is separately acknowledged.  The bridge validates the selected
  // immutable bank before presenting a release pulse to the map core.
  reg release_request_toggle;
  reg release_request_bank;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [1:0] release_request_sync;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg release_request_bank_sync_1;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg release_request_bank_sync_2;
  reg release_request_seen;
  reg [1:0] release_request_settle_count;
  reg release_response_toggle;
  reg release_response_error;

  always @(posedge map_clk) begin
    if (!core_map_resetn) begin
      release_request_sync <= 2'b00;
      release_request_bank_sync_1 <= 1'b0;
      release_request_bank_sync_2 <= 1'b0;
      release_request_seen <= 1'b0;
      release_request_settle_count <= 2'd0;
      release_response_toggle <= 1'b0;
      release_response_error <= 1'b0;
      map_release <= 1'b0;
      map_release_bank <= 1'b0;
    end else begin
      release_request_sync <= {
        release_request_sync[0], release_request_toggle
      };
      release_request_bank_sync_1 <= release_request_bank;
      release_request_bank_sync_2 <= release_request_bank_sync_1;
      map_release <= 1'b0;
      if (release_request_settle_count == 0 &&
          release_request_sync[1] != release_request_seen) begin
        release_request_seen <= release_request_sync[1];
        release_request_settle_count <= 2'd1;
      end else if (release_request_settle_count != 0) begin
        release_request_settle_count <= release_request_settle_count - 1'b1;
        if (release_request_settle_count == 1) begin
          map_release_bank <= release_request_bank_sync_2;
          if (map_ready_mask[release_request_bank_sync_2]) begin
            map_release <= 1'b1;
            release_response_error <= 1'b0;
          end else begin
            release_response_error <= 1'b1;
          end
          release_response_toggle <= release_request_seen;
        end
      end
    end
  end

  // Atomic 16-word telemetry snapshot.  Word zero contains the ready mask;
  // the remaining words contain immutable metadata followed by all nine map
  // counters.  The acknowledgement is delayed at the destination before the
  // synchronized payload is published.
  reg snapshot_request_toggle;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [1:0] snapshot_request_sync;
  reg snapshot_request_seen;
  reg snapshot_response_toggle;
  reg [SNAPSHOT_BITS-1:0] snapshot_source_payload;

  always @(posedge map_clk) begin
    if (!core_map_resetn) begin
      snapshot_request_sync <= 2'b00;
      snapshot_request_seen <= 1'b0;
      snapshot_response_toggle <= 1'b0;
      snapshot_source_payload <= {SNAPSHOT_BITS{1'b0}};
    end else begin
      snapshot_request_sync <= {
        snapshot_request_sync[0], snapshot_request_toggle
      };
      if (snapshot_request_sync[1] != snapshot_request_seen) begin
        snapshot_request_seen <= snapshot_request_sync[1];
        snapshot_source_payload <= {
          map_release_error_count,
          map_read_error_count,
          map_arithmetic_overflow_count,
          score_protocol_error_count,
          map_overrun_count,
          map_publish_count,
          discontinuity_abort_count,
          discarded_score_count,
          accepted_score_count,
          map_start_index_1[63:32],
          map_start_index_1[31:0],
          map_start_index_0[63:32],
          map_start_index_0[31:0],
          map_generation_1,
          map_generation_0,
          map_ready_mask
        };
        snapshot_response_toggle <= snapshot_request_sync[1];
      end
    end
  end

  // Destination synchronizers.  Payloads are held stable by the source
  // protocol and pass through two destination registers.  Two additional
  // settling cycles after observing each toggle bind the data to its event.
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [1:0] read_response_sync;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [MAP_WIDTH:0] read_response_payload_sync_1;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [MAP_WIDTH:0] read_response_payload_sync_2;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [1:0] release_response_sync;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [1:0] release_error_sync;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [1:0] snapshot_response_sync;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [SNAPSHOT_BITS-1:0] snapshot_payload_sync_1;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [SNAPSHOT_BITS-1:0] snapshot_payload_sync_2;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [1:0] ready_mask_sync_1;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [1:0] ready_mask_sync_2;

  always @(posedge s_axi_aclk) begin
    if (!core_control_resetn) begin
      read_response_sync <= 2'b00;
      read_response_payload_sync_1 <= {(MAP_WIDTH+1){1'b0}};
      read_response_payload_sync_2 <= {(MAP_WIDTH+1){1'b0}};
      release_response_sync <= 2'b00;
      release_error_sync <= 2'b00;
      snapshot_response_sync <= 2'b00;
      snapshot_payload_sync_1 <= {SNAPSHOT_BITS{1'b0}};
      snapshot_payload_sync_2 <= {SNAPSHOT_BITS{1'b0}};
      ready_mask_sync_1 <= 2'b00;
      ready_mask_sync_2 <= 2'b00;
    end else begin
      read_response_sync <= {
        read_response_sync[0], read_response_toggle
      };
      read_response_payload_sync_1 <= read_response_payload;
      read_response_payload_sync_2 <= read_response_payload_sync_1;
      release_response_sync <= {
        release_response_sync[0], release_response_toggle
      };
      release_error_sync <= {
        release_error_sync[0], release_response_error
      };
      snapshot_response_sync <= {
        snapshot_response_sync[0], snapshot_response_toggle
      };
      snapshot_payload_sync_1 <= snapshot_source_payload;
      snapshot_payload_sync_2 <= snapshot_payload_sync_1;
      ready_mask_sync_1 <= map_ready_mask;
      ready_mask_sync_2 <= ready_mask_sync_1;
    end
  end

  assign irq = core_control_resetn && |ready_mask_sync_2;

  wire up_wreq;
  wire [5:0] up_waddr;
  wire [31:0] up_wdata;
  wire [3:0] up_wstrb;
  reg up_wack;
  wire up_rreq;
  wire [5:0] up_raddr;
  reg [31:0] up_rdata;
  reg up_rack;

  reg selected_map_bank;
  reg [PHASE_INDEX_WIDTH-1:0] selected_map_index;
  reg read_pending;
  reg read_last_error;
  reg [1:0] read_settle_count;
  reg read_response_seen;
  reg release_pending;
  reg release_last_error;
  reg [1:0] release_settle_count;
  reg release_response_seen;
  reg snapshot_pending;
  reg snapshot_valid;
  reg [1:0] snapshot_settle_count;
  reg snapshot_response_seen;
  reg [SNAPSHOT_BITS-1:0] snapshot_payload;
  reg [31:0] snapshot_generation;
  reg [31:0] bridge_read_error_count;
  reg [31:0] bridge_release_error_count;
  reg [31:0] snapshot_request_overrun_count;
  reg register_read_pending;
  reg [31:0] register_read_data;

  wire [31:0] up_write_mask = {
    {8{up_wstrb[3]}},
    {8{up_wstrb[2]}},
    {8{up_wstrb[1]}},
    {8{up_wstrb[0]}}
  };
  wire [31:0] selected_map_index_word =
      {{(32-PHASE_INDEX_WIDTH){1'b0}}, selected_map_index};
  wire [31:0] merged_map_index =
      (selected_map_index_word & ~up_write_mask) |
      (up_wdata & up_write_mask);

  wire [31:0] status_word = {
    23'd0,
    snapshot_valid,
    snapshot_pending,
    release_pending,
    read_pending,
    irq,
    ready_mask_sync_2,
    control_enable,
    core_control_resetn
  };
  wire [31:0] command_status_word = {
    28'd0,
    release_last_error,
    read_last_error,
    release_pending,
    read_pending
  };

  function automatic [31:0] register_value;
    input [5:0] address;
    begin
      case (address)
        REG_IDENTIFICATION: register_value = IDENTIFICATION;
        REG_VERSION: register_value = VERSION;
        REG_PHASE_BINS: register_value = PHASE_BINS;
        REG_TILE_GEOMETRY: register_value = TILE_GEOMETRY;
        REG_CAPABILITIES: register_value = CAPABILITIES;
        REG_CONTROL: register_value = {31'd0, control_enable};
        REG_STATUS: register_value = status_word;
        REG_MAP_SELECT: register_value = {31'd0, selected_map_bank};
        REG_MAP_INDEX: register_value = selected_map_index;
        REG_COMMAND_STATUS: register_value = command_status_word;
        REG_SNAPSHOT_STATUS: register_value = {
          30'd0, snapshot_pending, snapshot_valid
        };
        REG_SNAPSHOT_GENERATION: register_value = snapshot_generation;
        REG_SNAPSHOT_READY:
          register_value = {30'd0, snapshot_payload[1:0]};
        REG_SNAPSHOT_MAP_GENERATION_0:
          register_value = snapshot_payload[33:2];
        REG_SNAPSHOT_MAP_GENERATION_1:
          register_value = snapshot_payload[65:34];
        REG_SNAPSHOT_START_INDEX_0_LO:
          register_value = snapshot_payload[97:66];
        REG_SNAPSHOT_START_INDEX_0_HI:
          register_value = snapshot_payload[129:98];
        REG_SNAPSHOT_START_INDEX_1_LO:
          register_value = snapshot_payload[161:130];
        REG_SNAPSHOT_START_INDEX_1_HI:
          register_value = snapshot_payload[193:162];
        REG_SNAPSHOT_ACCEPTED: register_value = snapshot_payload[225:194];
        REG_SNAPSHOT_DISCARDED: register_value = snapshot_payload[257:226];
        REG_SNAPSHOT_DISCONTINUITY:
          register_value = snapshot_payload[289:258];
        REG_SNAPSHOT_PUBLISHED: register_value = snapshot_payload[321:290];
        REG_SNAPSHOT_OVERRUN: register_value = snapshot_payload[353:322];
        REG_SNAPSHOT_PROTOCOL_ERROR:
          register_value = snapshot_payload[385:354];
        REG_SNAPSHOT_ARITHMETIC_OVERFLOW:
          register_value = snapshot_payload[417:386];
        REG_SNAPSHOT_READ_ERROR:
          register_value = snapshot_payload[449:418];
        REG_SNAPSHOT_RELEASE_ERROR:
          register_value = snapshot_payload[481:450];
        REG_BRIDGE_READ_ERROR: register_value = bridge_read_error_count;
        REG_BRIDGE_RELEASE_ERROR:
          register_value = bridge_release_error_count;
        REG_SNAPSHOT_REQUEST_OVERRUN:
          register_value = snapshot_request_overrun_count;
        default: register_value = 32'd0;
      endcase
    end
  endfunction

  // AXI-domain command issue, response publication, and register bank.
  always @(posedge s_axi_aclk) begin
    if (!core_control_resetn) begin
      // Keep the AXI transport alive across a map-local reset.  Any command
      // already presented to this register bank is acknowledged and reads
      // return zero, so an in-flight CPU access cannot be stranded.
      up_wack <= up_wreq;
      up_rack <= up_rreq || read_pending || register_read_pending;
      up_rdata <= 32'd0;
      control_enable <= 1'b0;
      flush_request_toggle <= 1'b0;
      selected_map_bank <= 1'b0;
      selected_map_index <= {PHASE_INDEX_WIDTH{1'b0}};
      read_request_toggle <= 1'b0;
      read_request_bank <= 1'b0;
      read_request_index <= {PHASE_INDEX_WIDTH{1'b0}};
      read_pending <= 1'b0;
      read_last_error <= 1'b0;
      read_settle_count <= 2'd0;
      read_response_seen <= 1'b0;
      release_request_toggle <= 1'b0;
      release_request_bank <= 1'b0;
      release_pending <= 1'b0;
      release_last_error <= 1'b0;
      release_settle_count <= 2'd0;
      release_response_seen <= 1'b0;
      snapshot_request_toggle <= 1'b0;
      snapshot_pending <= 1'b0;
      snapshot_valid <= 1'b0;
      snapshot_settle_count <= 2'd0;
      snapshot_response_seen <= 1'b0;
      snapshot_payload <= {SNAPSHOT_BITS{1'b0}};
      snapshot_generation <= 32'd0;
      bridge_read_error_count <= 32'd0;
      bridge_release_error_count <= 32'd0;
      snapshot_request_overrun_count <= 32'd0;
      register_read_pending <= 1'b0;
      register_read_data <= 32'd0;
    end else begin
      up_wack <= up_wreq;
      up_rack <= 1'b0;
      up_rdata <= 32'd0;

      if (read_pending && read_settle_count == 0 &&
          read_response_sync[1] != read_response_seen) begin
        read_response_seen <= read_response_sync[1];
        read_settle_count <= 2'd1;
      end else if (read_settle_count != 0) begin
        read_settle_count <= read_settle_count - 1'b1;
        if (read_settle_count == 1) begin
          up_rdata <= {{(32-MAP_WIDTH){1'b0}},
                       read_response_payload_sync_2[MAP_WIDTH-1:0]};
          up_rack <= 1'b1;
          read_pending <= 1'b0;
          read_last_error <= read_response_payload_sync_2[MAP_WIDTH];
          if (read_response_payload_sync_2[MAP_WIDTH]) begin
            bridge_read_error_count <= increment_saturating_32(
                bridge_read_error_count);
          end else if (selected_map_bank == read_request_bank &&
                       selected_map_index == read_request_index &&
                       read_request_index != LAST_PHASE) begin
            selected_map_index <= read_request_index + 1'b1;
          end
        end
      end

      if (release_pending && release_settle_count == 0 &&
          release_response_sync[1] != release_response_seen) begin
        release_response_seen <= release_response_sync[1];
        release_settle_count <= 2'd2;
      end else if (release_settle_count != 0) begin
        release_settle_count <= release_settle_count - 1'b1;
        if (release_settle_count == 1) begin
          release_pending <= 1'b0;
          release_last_error <= release_error_sync[1];
          if (release_error_sync[1])
            bridge_release_error_count <= increment_saturating_32(
                bridge_release_error_count);
        end
      end

      if (snapshot_pending && snapshot_settle_count == 0 &&
          snapshot_response_sync[1] != snapshot_response_seen) begin
        snapshot_response_seen <= snapshot_response_sync[1];
        snapshot_settle_count <= 2'd2;
      end else if (snapshot_settle_count != 0) begin
        snapshot_settle_count <= snapshot_settle_count - 1'b1;
        if (snapshot_settle_count == 1) begin
          snapshot_payload <= snapshot_payload_sync_2;
          snapshot_pending <= 1'b0;
          snapshot_valid <= 1'b1;
          snapshot_generation <= increment_saturating_32(
              snapshot_generation);
        end
      end

      if (up_wreq) begin
        case (up_waddr)
          REG_CONTROL: begin
            if (up_wstrb[0]) begin
              control_enable <= up_wdata[0];
              if (up_wdata[1])
                flush_request_toggle <= ~flush_request_toggle;
            end
          end
          REG_MAP_SELECT: begin
            if (up_wstrb[0])
              selected_map_bank <= up_wdata[0];
          end
          REG_MAP_INDEX: begin
            if (|up_wstrb) begin
              if (merged_map_index < PHASE_BINS)
                selected_map_index <=
                    merged_map_index[PHASE_INDEX_WIDTH-1:0];
              else
                selected_map_index <= LAST_PHASE;
            end
          end
          REG_MAP_RELEASE: begin
            if (up_wstrb[0] && up_wdata[0]) begin
              if (!read_pending && !release_pending) begin
                release_request_bank <= selected_map_bank;
                release_request_toggle <= ~release_request_toggle;
                release_pending <= 1'b1;
                release_last_error <= 1'b0;
              end else begin
                release_last_error <= 1'b1;
                bridge_release_error_count <= increment_saturating_32(
                    bridge_release_error_count);
              end
            end
          end
          REG_SNAPSHOT_CONTROL: begin
            if (up_wstrb[0] && up_wdata[0]) begin
              if (!snapshot_pending) begin
                snapshot_request_toggle <= ~snapshot_request_toggle;
                snapshot_pending <= 1'b1;
                snapshot_valid <= 1'b0;
              end else begin
                snapshot_request_overrun_count <= increment_saturating_32(
                    snapshot_request_overrun_count);
              end
            end
          end
          default: begin
          end
        endcase
      end

      if (register_read_pending) begin
        up_rdata <= register_read_data;
        up_rack <= 1'b1;
        register_read_pending <= 1'b0;
      end

      if (up_rreq && !register_read_pending && !read_pending) begin
        if (up_raddr == REG_MAP_DATA) begin
          if (!release_pending) begin
            read_request_bank <= selected_map_bank;
            read_request_index <= selected_map_index;
            read_request_toggle <= ~read_request_toggle;
            read_pending <= 1'b1;
            read_last_error <= 1'b0;
          end else begin
            register_read_data <= 32'd0;
            register_read_pending <= 1'b1;
            read_last_error <= 1'b1;
            bridge_read_error_count <= increment_saturating_32(
                bridge_read_error_count);
          end
        end else begin
          register_read_data <= register_value(up_raddr);
          register_read_pending <= 1'b1;
        end
      end
    end
  end

  wire unused_axi_fields = ^{s_axi_awprot, s_axi_arprot, map_read_inflight};

  starlink_pss_axi_lite #(
    .AXI_ADDRESS_WIDTH (8)
  ) i_axi_lite (
    .resetn            (control_reset_sync[1]),
    .clk               (s_axi_aclk),
    .s_axi_awvalid     (s_axi_awvalid),
    .s_axi_awaddr      (s_axi_awaddr),
    .s_axi_awready     (s_axi_awready),
    .s_axi_wvalid      (s_axi_wvalid),
    .s_axi_wdata       (s_axi_wdata),
    .s_axi_wstrb       (s_axi_wstrb),
    .s_axi_wready      (s_axi_wready),
    .s_axi_bvalid      (s_axi_bvalid),
    .s_axi_bresp       (s_axi_bresp),
    .s_axi_bready      (s_axi_bready),
    .s_axi_arvalid     (s_axi_arvalid),
    .s_axi_araddr      (s_axi_araddr),
    .s_axi_arready     (s_axi_arready),
    .s_axi_rvalid      (s_axi_rvalid),
    .s_axi_rresp       (s_axi_rresp),
    .s_axi_rdata       (s_axi_rdata),
    .s_axi_rready      (s_axi_rready),
    .up_wreq           (up_wreq),
    .up_waddr          (up_waddr),
    .up_wdata          (up_wdata),
    .up_wstrb          (up_wstrb),
    .up_wack           (up_wack),
    .up_rreq           (up_rreq),
    .up_raddr          (up_raddr),
    .up_rdata          (up_rdata),
    .up_rack           (up_rack)
  );

endmodule
