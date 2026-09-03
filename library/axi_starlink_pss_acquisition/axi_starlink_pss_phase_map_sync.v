// SPDX-License-Identifier: GPL-2.0
//
// Single-clock PSMA control boundary for the Pluto acquisition shell.
//
// The reusable axi_starlink_pss_phase_map block deliberately supports
// unrelated map and AXI clocks.  In this shell the map engine and AXI bus are
// both clocked by sys_cpu_clk.  Keeping the asynchronous mailbox payloads in
// that composition costs thousands of registers and creates avoidable control
// sets.  This implementation preserves the register ABI and atomic snapshot
// contract while using one clock and one copy of every held payload.

`timescale 1ns/1ps

module axi_starlink_pss_phase_map_sync #(
  parameter integer PHASE_BINS = 20000,
  parameter integer PHASE_INDEX_WIDTH = 15,
  parameter integer TILE_FRAMES = 64,
  parameter integer MAP_WIDTH = 16,
  parameter integer INPUT_RATE_MSPS = 15,
  parameter [30:0] COEFFICIENT_ENERGY = 31'd1073742825
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

  input  wire [31:0]                   detector_health_flags,
  input  wire                          ingress_overflow_sticky,
  input  wire [31:0]                   ingress_dropped_sample_count,
  input  wire [15:0]                   ingress_fifo_level,
  input  wire [15:0]                   ingress_maximum_fifo_level,
  input  wire [31:0]                   scheduler_gap_count,
  input  wire [31:0]                   scheduler_index_error_count,
  input  wire [31:0]                   scheduler_overflow_count,
  input  wire [31:0]                   detector_fault_count,
  input  wire [31:0]                   score_phase_index_discontinuity_count,
  input  wire [31:0]                   score_denominator_zero_count,
  input  wire [9:0]                    candidate_fifo_stored_count,
  input  wire [9:0]                    candidate_fifo_maximum_stored_count,
  input  wire [31:0]                   ddc_accepted_sample_count,
  input  wire [31:0]                   ddc_emitted_sample_count,
  input  wire [31:0]                   ddc_discontinuity_count,
  input  wire [31:0]                   ddc_saturation_event_count,

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

  localparam [31:0] IDENTIFICATION = 32'h5053_4d41;
  localparam integer DDC_ENABLED = INPUT_RATE_MSPS != 15;
  localparam [31:0] VERSION = (INPUT_RATE_MSPS == 60) ?
      32'h0001_0003 :
      ((INPUT_RATE_MSPS == 30) ? 32'h0001_0002 : 32'h0001_0001);
  localparam [31:0] CAPABILITIES = DDC_ENABLED ?
      32'h0000_007f : 32'h0000_003f;
  // ABI 1.1/1.2 values remain exact. ABI 1.3 advertises two cascaded stages
  // in the high byte and total decimation four in the third byte.
  localparam [31:0] DDC_CONFIG = (INPUT_RATE_MSPS == 60) ?
      32'h020f_0403 :
      {8'd0, 8'd15, 8'd2, 6'd0, 1'b1,
       (DDC_ENABLED ? 1'b1 : 1'b0)};
  localparam [31:0] DDC_GROUP_DELAY = (INPUT_RATE_MSPS == 60) ?
      32'd21 : (DDC_ENABLED ? 32'd7 : 32'd0);
  localparam [255:0] DDC_CONTRACT = (INPUT_RATE_MSPS == 60) ?
      256'h8e807d15d5372b0a9669d1190d899697e7c2911a73ddfb23095806c2a31de5b2 :
      256'h731426047077b036f9213db3574e4a556fd424b97a293843bd6ee085c2bf33af;
  localparam [31:0] TILE_GEOMETRY =
      (TILE_FRAMES << 16) | (MAP_WIDTH << 8) | 2;
  localparam [PHASE_INDEX_WIDTH-1:0] LAST_PHASE = PHASE_BINS - 1;
  localparam integer SNAPSHOT_BITS = 790;

  localparam [5:0] REG_IDENTIFICATION = 6'h00;
  localparam [5:0] REG_VERSION = 6'h01;
  localparam [5:0] REG_PHASE_BINS = 6'h02;
  localparam [5:0] REG_TILE_GEOMETRY = 6'h03;
  localparam [5:0] REG_CAPABILITIES = 6'h04;
  localparam [5:0] REG_CONTROL = 6'h05;
  localparam [5:0] REG_STATUS = 6'h06;
  localparam [5:0] REG_MAP_SELECT = 6'h07;
  localparam [5:0] REG_MAP_INDEX = 6'h08;
  localparam [5:0] REG_MAP_DATA = 6'h09;
  localparam [5:0] REG_MAP_RELEASE = 6'h0a;
  localparam [5:0] REG_COMMAND_STATUS = 6'h0b;
  localparam [5:0] REG_SNAPSHOT_CONTROL = 6'h0c;
  localparam [5:0] REG_SNAPSHOT_STATUS = 6'h0d;
  localparam [5:0] REG_SNAPSHOT_GENERATION = 6'h0e;
  localparam [5:0] REG_SNAPSHOT_READY = 6'h0f;
  localparam [5:0] REG_SNAPSHOT_MAP_GENERATION_0 = 6'h10;
  localparam [5:0] REG_SNAPSHOT_MAP_GENERATION_1 = 6'h11;
  localparam [5:0] REG_SNAPSHOT_START_INDEX_0_LO = 6'h12;
  localparam [5:0] REG_SNAPSHOT_START_INDEX_0_HI = 6'h13;
  localparam [5:0] REG_SNAPSHOT_START_INDEX_1_LO = 6'h14;
  localparam [5:0] REG_SNAPSHOT_START_INDEX_1_HI = 6'h15;
  localparam [5:0] REG_SNAPSHOT_ACCEPTED = 6'h16;
  localparam [5:0] REG_SNAPSHOT_DISCARDED = 6'h17;
  localparam [5:0] REG_SNAPSHOT_DISCONTINUITY = 6'h18;
  localparam [5:0] REG_SNAPSHOT_PUBLISHED = 6'h19;
  localparam [5:0] REG_SNAPSHOT_OVERRUN = 6'h1a;
  localparam [5:0] REG_SNAPSHOT_PROTOCOL_ERROR = 6'h1b;
  localparam [5:0] REG_SNAPSHOT_ARITHMETIC_OVERFLOW = 6'h1c;
  localparam [5:0] REG_SNAPSHOT_READ_ERROR = 6'h1d;
  localparam [5:0] REG_SNAPSHOT_RELEASE_ERROR = 6'h1e;
  localparam [5:0] REG_BRIDGE_READ_ERROR = 6'h1f;
  localparam [5:0] REG_BRIDGE_RELEASE_ERROR = 6'h20;
  localparam [5:0] REG_SNAPSHOT_REQUEST_OVERRUN = 6'h21;
  localparam [5:0] REG_SNAPSHOT_HEALTH_FLAGS = 6'h22;
  localparam [5:0] REG_SNAPSHOT_INGRESS_DROPPED = 6'h23;
  localparam [5:0] REG_SNAPSHOT_INGRESS_FIFO = 6'h24;
  localparam [5:0] REG_SNAPSHOT_SCHEDULER_GAP = 6'h25;
  localparam [5:0] REG_SNAPSHOT_SCHEDULER_INDEX_ERROR = 6'h26;
  localparam [5:0] REG_SNAPSHOT_SCHEDULER_OVERFLOW = 6'h27;
  localparam [5:0] REG_SNAPSHOT_DETECTOR_FAULT = 6'h28;
  localparam [5:0] REG_SNAPSHOT_PHASE_DISCONTINUITY = 6'h29;
  localparam [5:0] REG_SNAPSHOT_DENOMINATOR_ZERO = 6'h2a;
  localparam [5:0] REG_SNAPSHOT_CANDIDATE_FIFO = 6'h2b;
  localparam [5:0] REG_INPUT_RATE_MSPS = 6'h2c;
  localparam [5:0] REG_DDC_CONFIG = 6'h2d;
  localparam [5:0] REG_DDC_GROUP_DELAY = 6'h2e;
  localparam [5:0] REG_COEFFICIENT_ENERGY = 6'h2f;
  localparam [5:0] REG_DDC_CONTRACT_0 = 6'h30;
  localparam [5:0] REG_DDC_CONTRACT_1 = 6'h31;
  localparam [5:0] REG_DDC_CONTRACT_2 = 6'h32;
  localparam [5:0] REG_DDC_CONTRACT_3 = 6'h33;
  localparam [5:0] REG_DDC_CONTRACT_4 = 6'h34;
  localparam [5:0] REG_DDC_CONTRACT_5 = 6'h35;
  localparam [5:0] REG_DDC_CONTRACT_6 = 6'h36;
  localparam [5:0] REG_DDC_CONTRACT_7 = 6'h37;
  localparam [5:0] REG_DDC_ACCEPTED = 6'h38;
  localparam [5:0] REG_DDC_EMITTED = 6'h39;
  localparam [5:0] REG_DDC_DISCONTINUITY = 6'h3a;
  localparam [5:0] REG_DDC_SATURATION = 6'h3b;

  localparam integer HEALTH_INGRESS_OVERFLOW = 12;
  localparam integer HEALTH_DDC_SATURATION = 13;

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
    if ((INPUT_RATE_MSPS != 15) && (INPUT_RATE_MSPS != 30) &&
        (INPUT_RATE_MSPS != 60)) begin : g_invalid_rate
      initial $fatal(1, "INPUT_RATE_MSPS must be 15, 30, or 60");
    end
  endgenerate

  function automatic [31:0] increment_saturating_32;
    input [31:0] value;
    begin
      increment_saturating_32 = (&value) ? value : value + 1'b1;
    end
  endfunction

  wire core_resetn = s_axi_aresetn && !map_reset;
  reg control_enable;
  assign acquisition_enable = core_resetn && control_enable;
  assign irq = core_resetn && |map_ready_mask;

  wire [31:0] snapshot_health_flags = detector_health_flags |
      (ingress_overflow_sticky ?
       (32'd1 << HEALTH_INGRESS_OVERFLOW) : 32'd0) |
      ((DDC_ENABLED && |ddc_saturation_event_count) ?
       (32'd1 << HEALTH_DDC_SATURATION) : 32'd0);

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
  reg release_pending;
  reg release_last_error;
  reg snapshot_pending;
  reg snapshot_valid;
  reg [SNAPSHOT_BITS-1:0] snapshot_payload;
  reg [31:0] snapshot_generation;
  reg [31:0] bridge_read_error_count;
  reg [31:0] bridge_release_error_count;
  reg [31:0] snapshot_request_overrun_count;
  reg register_read_pending;
  reg [31:0] register_read_data;

  wire [31:0] up_write_mask = {
    {8{up_wstrb[3]}}, {8{up_wstrb[2]}},
    {8{up_wstrb[1]}}, {8{up_wstrb[0]}}
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
    map_ready_mask,
    control_enable,
    core_resetn
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
        REG_SNAPSHOT_STATUS:
          register_value = {30'd0, snapshot_pending, snapshot_valid};
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
        REG_SNAPSHOT_ACCEPTED:
          register_value = snapshot_payload[225:194];
        REG_SNAPSHOT_DISCARDED:
          register_value = snapshot_payload[257:226];
        REG_SNAPSHOT_DISCONTINUITY:
          register_value = snapshot_payload[289:258];
        REG_SNAPSHOT_PUBLISHED:
          register_value = snapshot_payload[321:290];
        REG_SNAPSHOT_OVERRUN:
          register_value = snapshot_payload[353:322];
        REG_SNAPSHOT_PROTOCOL_ERROR:
          register_value = snapshot_payload[385:354];
        REG_SNAPSHOT_ARITHMETIC_OVERFLOW:
          register_value = snapshot_payload[417:386];
        REG_SNAPSHOT_READ_ERROR:
          register_value = snapshot_payload[449:418];
        REG_SNAPSHOT_RELEASE_ERROR:
          register_value = snapshot_payload[481:450];
        REG_BRIDGE_READ_ERROR:
          register_value = bridge_read_error_count;
        REG_BRIDGE_RELEASE_ERROR:
          register_value = bridge_release_error_count;
        REG_SNAPSHOT_REQUEST_OVERRUN:
          register_value = snapshot_request_overrun_count;
        REG_SNAPSHOT_HEALTH_FLAGS:
          register_value = snapshot_payload[513:482];
        REG_SNAPSHOT_INGRESS_DROPPED:
          register_value = snapshot_payload[545:514];
        REG_SNAPSHOT_INGRESS_FIFO:
          register_value = snapshot_payload[577:546];
        REG_SNAPSHOT_SCHEDULER_GAP:
          register_value = snapshot_payload[609:578];
        REG_SNAPSHOT_SCHEDULER_INDEX_ERROR:
          register_value = snapshot_payload[641:610];
        REG_SNAPSHOT_SCHEDULER_OVERFLOW:
          register_value = snapshot_payload[673:642];
        REG_SNAPSHOT_DETECTOR_FAULT:
          register_value = snapshot_payload[705:674];
        REG_SNAPSHOT_PHASE_DISCONTINUITY:
          register_value = snapshot_payload[737:706];
        REG_SNAPSHOT_DENOMINATOR_ZERO:
          register_value = snapshot_payload[769:738];
        REG_SNAPSHOT_CANDIDATE_FIFO:
          register_value = {
            6'd0, snapshot_payload[789:780],
            6'd0, snapshot_payload[779:770]
          };
        REG_INPUT_RATE_MSPS: register_value = INPUT_RATE_MSPS;
        REG_DDC_CONFIG: register_value = DDC_CONFIG;
        REG_DDC_GROUP_DELAY: register_value = DDC_GROUP_DELAY;
        REG_COEFFICIENT_ENERGY:
          register_value = {1'b0, COEFFICIENT_ENERGY};
        REG_DDC_CONTRACT_0:
          register_value = DDC_ENABLED ? DDC_CONTRACT[255:224] : 32'd0;
        REG_DDC_CONTRACT_1:
          register_value = DDC_ENABLED ? DDC_CONTRACT[223:192] : 32'd0;
        REG_DDC_CONTRACT_2:
          register_value = DDC_ENABLED ? DDC_CONTRACT[191:160] : 32'd0;
        REG_DDC_CONTRACT_3:
          register_value = DDC_ENABLED ? DDC_CONTRACT[159:128] : 32'd0;
        REG_DDC_CONTRACT_4:
          register_value = DDC_ENABLED ? DDC_CONTRACT[127:96] : 32'd0;
        REG_DDC_CONTRACT_5:
          register_value = DDC_ENABLED ? DDC_CONTRACT[95:64] : 32'd0;
        REG_DDC_CONTRACT_6:
          register_value = DDC_ENABLED ? DDC_CONTRACT[63:32] : 32'd0;
        REG_DDC_CONTRACT_7:
          register_value = DDC_ENABLED ? DDC_CONTRACT[31:0] : 32'd0;
        REG_DDC_ACCEPTED:
          register_value = DDC_ENABLED ? ddc_accepted_sample_count : 32'd0;
        REG_DDC_EMITTED:
          register_value = DDC_ENABLED ? ddc_emitted_sample_count : 32'd0;
        REG_DDC_DISCONTINUITY:
          register_value = DDC_ENABLED ? ddc_discontinuity_count : 32'd0;
        REG_DDC_SATURATION:
          register_value = DDC_ENABLED ? ddc_saturation_event_count : 32'd0;
        default: register_value = 32'd0;
      endcase
    end
  endfunction

  always @(posedge s_axi_aclk) begin
    if (!core_resetn) begin
      up_wack <= up_wreq;
      up_rack <= up_rreq || read_pending || register_read_pending;
      up_rdata <= 32'd0;
      control_enable <= 1'b0;
      acquisition_flush <= 1'b0;
      map_read_request <= 1'b0;
      map_read_bank <= 1'b0;
      map_read_index <= {PHASE_INDEX_WIDTH{1'b0}};
      map_release <= 1'b0;
      map_release_bank <= 1'b0;
      selected_map_bank <= 1'b0;
      selected_map_index <= {PHASE_INDEX_WIDTH{1'b0}};
      read_pending <= 1'b0;
      read_last_error <= 1'b0;
      release_pending <= 1'b0;
      release_last_error <= 1'b0;
      snapshot_pending <= 1'b0;
      snapshot_valid <= 1'b0;
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
      acquisition_flush <= 1'b0;
      map_read_request <= 1'b0;
      map_release <= 1'b0;

      if (read_pending && (map_read_valid || map_read_error)) begin
        up_rdata <= map_read_error ? 32'd0 :
            {{(32-MAP_WIDTH){1'b0}}, map_read_data};
        up_rack <= 1'b1;
        read_pending <= 1'b0;
        read_last_error <= map_read_error;
        if (map_read_error) begin
          bridge_read_error_count <= increment_saturating_32(
              bridge_read_error_count);
        end else if (selected_map_bank == map_read_bank &&
                     selected_map_index == map_read_index &&
                     map_read_index != LAST_PHASE) begin
          selected_map_index <= map_read_index + 1'b1;
        end
      end

      if (release_pending) begin
        release_pending <= 1'b0;
        if (map_ready_mask[map_release_bank]) begin
          map_release <= 1'b1;
          release_last_error <= 1'b0;
        end else begin
          release_last_error <= 1'b1;
          bridge_release_error_count <= increment_saturating_32(
              bridge_release_error_count);
        end
      end

      if (snapshot_pending) begin
        snapshot_payload <= {
          candidate_fifo_maximum_stored_count,
          candidate_fifo_stored_count,
          score_denominator_zero_count,
          score_phase_index_discontinuity_count,
          detector_fault_count,
          scheduler_overflow_count,
          scheduler_index_error_count,
          scheduler_gap_count,
          {ingress_maximum_fifo_level, ingress_fifo_level},
          ingress_dropped_sample_count,
          snapshot_health_flags,
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
        snapshot_pending <= 1'b0;
        snapshot_valid <= 1'b1;
        snapshot_generation <= increment_saturating_32(
            snapshot_generation);
      end

      if (up_wreq) begin
        case (up_waddr)
          REG_CONTROL: begin
            if (up_wstrb[0]) begin
              control_enable <= up_wdata[0];
              if (up_wdata[1])
                acquisition_flush <= 1'b1;
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
                map_release_bank <= selected_map_bank;
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
            map_read_bank <= selected_map_bank;
            map_read_index <= selected_map_index;
            map_read_request <= 1'b1;
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

  wire unused_fields = ^{
    map_clk, s_axi_awprot, s_axi_arprot
  };

  starlink_pss_axi_lite #(
    .AXI_ADDRESS_WIDTH (8)
  ) i_axi_lite (
    .resetn            (s_axi_aresetn),
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
