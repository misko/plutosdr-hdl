// SPDX-License-Identifier: GPL-2.0
//
// AXI-Lite wrapper for the bounded 15 MS/s periodic PSS qualification source.

`timescale 1ns/1ps

module axi_starlink_pss_periodic_injector (
  input  wire                 sample_clk,
  input  wire                 sample_reset,
  input  wire signed [15:0]   sample_i,
  input  wire signed [15:0]   sample_q,
  input  wire                 sample_strobe,
  input  wire                 sample_enable,
  input  wire [63:0]          sample_index,
  input  wire [63:0]          sample_timestamp,
  output wire signed [15:0]   selected_sample_i,
  output wire signed [15:0]   selected_sample_q,
  output wire                 selected_sample_strobe,
  output wire                 selected_sample_enable,
  output wire [63:0]          selected_sample_index,
  output wire [63:0]          selected_sample_timestamp,
  output wire                 selected_sample_substituted,
  output wire                 selected_sample_fixture,

  input  wire                 s_axi_aclk,
  input  wire                 s_axi_aresetn,
  input  wire                 s_axi_awvalid,
  input  wire [7:0]           s_axi_awaddr,
  output wire                 s_axi_awready,
  input  wire                 s_axi_wvalid,
  input  wire [31:0]          s_axi_wdata,
  input  wire [3:0]           s_axi_wstrb,
  output wire                 s_axi_wready,
  output wire                 s_axi_bvalid,
  output wire [1:0]           s_axi_bresp,
  input  wire                 s_axi_bready,
  input  wire                 s_axi_arvalid,
  input  wire [7:0]           s_axi_araddr,
  output wire                 s_axi_arready,
  output wire                 s_axi_rvalid,
  output wire [1:0]           s_axi_rresp,
  output wire [31:0]          s_axi_rdata,
  input  wire                 s_axi_rready,
  input  wire [2:0]           s_axi_awprot,
  input  wire [2:0]           s_axi_arprot
);

  localparam [31:0] IDENTIFICATION = 32'h5053_5349; // ASCII "PSSI".
  localparam [31:0] VERSION = 32'h0001_0000;
  localparam [31:0] CAPABILITIES = 32'h0000_000f;
  localparam integer SAMPLE_COUNT = 130;
  localparam integer PERIOD_SAMPLES = 20000;
  localparam integer REPEAT_COUNT = 130;
  localparam [63:0] LAST_SAMPLE_OFFSET = 64'd2580129;

  localparam [5:0] REG_IDENTIFICATION = 6'h00; // 0x00
  localparam [5:0] REG_VERSION = 6'h01; // 0x04
  localparam [5:0] REG_CAPABILITIES = 6'h02; // 0x08
  localparam [5:0] REG_GEOMETRY = 6'h03; // 0x0c
  localparam [5:0] REG_PERIOD_SAMPLES = 6'h04; // 0x10
  localparam [5:0] REG_CURRENT_INDEX_LO = 6'h05; // 0x14
  localparam [5:0] REG_CURRENT_INDEX_HI = 6'h06; // 0x18
  localparam [5:0] REG_FIXTURE_DATA = 6'h07; // 0x1c
  localparam [5:0] REG_CONTROL = 6'h08; // 0x20
  localparam [5:0] REG_START_INDEX_LO = 6'h09; // 0x24
  localparam [5:0] REG_START_INDEX_HI = 6'h0a; // 0x28
  localparam [5:0] REG_GENERATION = 6'h0b; // 0x2c
  localparam [5:0] REG_STATUS = 6'h0c; // 0x30
  localparam [5:0] REG_LAST_GENERATION = 6'h0d; // 0x34
  localparam [5:0] REG_LAST_REPETITIONS = 6'h0e; // 0x38
  localparam [5:0] REG_LAST_OFFSET_LO = 6'h0f; // 0x3c
  localparam [5:0] REG_LAST_OFFSET_HI = 6'h10; // 0x40

  function automatic [63:0] binary_to_gray_64;
    input [63:0] value;
    begin
      binary_to_gray_64 = (value >> 1) ^ value;
    end
  endfunction

  function automatic [63:0] gray_to_binary_64;
    input [63:0] value;
    reg [63:0] prefix;
    begin
      prefix = value;
      prefix = prefix ^ (prefix >> 1);
      prefix = prefix ^ (prefix >> 2);
      prefix = prefix ^ (prefix >> 4);
      prefix = prefix ^ (prefix >> 8);
      prefix = prefix ^ (prefix >> 16);
      prefix = prefix ^ (prefix >> 32);
      gray_to_binary_64 = prefix;
    end
  endfunction

  wire reset_epoch_async_n = s_axi_aresetn;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [1:0] control_reset_sync;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [1:0] sample_reset_sync;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [1:0] sample_reset_control_sync;

  always @(posedge s_axi_aclk or negedge reset_epoch_async_n) begin
    if (!reset_epoch_async_n)
      control_reset_sync <= 2'b00;
    else
      control_reset_sync <= {control_reset_sync[0], 1'b1};
  end

  always @(posedge sample_clk or negedge reset_epoch_async_n) begin
    if (!reset_epoch_async_n)
      sample_reset_sync <= 2'b00;
    else
      sample_reset_sync <= {sample_reset_sync[0], 1'b1};
  end

  always @(posedge s_axi_aclk or negedge reset_epoch_async_n) begin
    if (!reset_epoch_async_n)
      sample_reset_control_sync <= 2'b11;
    else
      sample_reset_control_sync <= {
        sample_reset_control_sync[0], sample_reset
      };
  end

  wire core_control_resetn =
      control_reset_sync[1] && !sample_reset_control_sync[1];
  wire core_sample_resetn = sample_reset_sync[1] && !sample_reset;
  wire source_sample_accepted = sample_enable && sample_strobe;

  reg [63:0] sample_index_gray;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [63:0] sample_index_gray_sync_1;
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [63:0] sample_index_gray_sync_2;

  always @(posedge sample_clk) begin
    if (!core_sample_resetn)
      sample_index_gray <= 64'd0;
    else if (source_sample_accepted)
      sample_index_gray <= binary_to_gray_64(sample_index);
  end

  always @(posedge s_axi_aclk) begin
    if (!core_control_resetn) begin
      sample_index_gray_sync_1 <= 64'd0;
      sample_index_gray_sync_2 <= 64'd0;
    end else begin
      sample_index_gray_sync_1 <= sample_index_gray;
      sample_index_gray_sync_2 <= sample_index_gray_sync_1;
    end
  end

  wire [63:0] current_sample_index =
      gray_to_binary_64(sample_index_gray_sync_2);

  wire up_wreq;
  wire [5:0] up_waddr;
  wire [31:0] up_wdata;
  wire up_rreq;
  wire [5:0] up_raddr;
  reg up_wack;
  reg up_rack;
  reg [31:0] up_rdata;

  up_axi #(
    .AXI_ADDRESS_WIDTH(8)
  ) i_up_axi (
    .up_rstn        (core_control_resetn),
    .up_clk         (s_axi_aclk),
    .up_axi_awvalid (s_axi_awvalid),
    .up_axi_awaddr  (s_axi_awaddr),
    .up_axi_awready (s_axi_awready),
    .up_axi_wvalid  (s_axi_wvalid),
    .up_axi_wdata   (s_axi_wdata),
    .up_axi_wstrb   (s_axi_wstrb),
    .up_axi_wready  (s_axi_wready),
    .up_axi_bvalid  (s_axi_bvalid),
    .up_axi_bresp   (s_axi_bresp),
    .up_axi_bready  (s_axi_bready),
    .up_axi_arvalid (s_axi_arvalid),
    .up_axi_araddr  (s_axi_araddr),
    .up_axi_arready (s_axi_arready),
    .up_axi_rvalid  (s_axi_rvalid),
    .up_axi_rresp   (s_axi_rresp),
    .up_axi_rdata   (s_axi_rdata),
    .up_axi_rready  (s_axi_rready),
    .up_wreq        (up_wreq),
    .up_waddr       (up_waddr),
    .up_wdata       (up_wdata),
    .up_wack        (up_wack),
    .up_rreq        (up_rreq),
    .up_raddr       (up_raddr),
    .up_rdata       (up_rdata),
    .up_rack        (up_rack)
  );

  reg fixture_clear;
  reg fixture_write;
  reg [31:0] fixture_write_data;
  reg fixture_commit;
  reg arm;
  reg [63:0] start_index_stage;
  reg [31:0] generation_stage;
  reg [63:0] current_index_snapshot;
  wire fixture_write_ready;
  wire arm_ready;
  wire [31:0] injection_status;
  wire [31:0] last_completed_generation;
  wire [31:0] last_completed_repetitions;

  starlink_pss_periodic_injection_mux #(
    .SAMPLE_COUNT             (SAMPLE_COUNT),
    .PERIOD_SAMPLES           (PERIOD_SAMPLES),
    .REPEAT_COUNT             (REPEAT_COUNT),
    .MINIMUM_ARM_LEAD_SAMPLES (64'd65536)
  ) i_periodic_injection_mux (
    .control_clk                (s_axi_aclk),
    .control_resetn             (core_control_resetn),
    .fixture_clear              (fixture_clear),
    .fixture_write              (fixture_write),
    .fixture_write_data         (fixture_write_data),
    .fixture_commit             (fixture_commit),
    .fixture_generation_stage   (generation_stage),
    .arm                        (arm),
    .arm_start_stage            (start_index_stage),
    .control_current_index      (current_sample_index),
    .fixture_write_ready        (fixture_write_ready),
    .arm_ready                  (arm_ready),
    .status                     (injection_status),
    .last_completed_generation  (last_completed_generation),
    .last_completed_repetitions (last_completed_repetitions),
    .sample_clk                 (sample_clk),
    .sample_resetn              (core_sample_resetn),
    .source_sample_i            (sample_i),
    .source_sample_q            (sample_q),
    .source_sample_strobe       (sample_strobe),
    .source_sample_enable       (sample_enable),
    .source_sample_index        (sample_index),
    .source_sample_timestamp    (sample_timestamp),
    .selected_sample_i          (selected_sample_i),
    .selected_sample_q          (selected_sample_q),
    .selected_sample_strobe     (selected_sample_strobe),
    .selected_sample_enable     (selected_sample_enable),
    .selected_sample_index      (selected_sample_index),
    .selected_sample_timestamp  (selected_sample_timestamp),
    .selected_sample_substituted(selected_sample_substituted),
    .selected_sample_fixture    (selected_sample_fixture)
  );

  always @(posedge s_axi_aclk) begin
    if (!core_control_resetn) begin
      up_wack <= 1'b0;
      up_rack <= 1'b0;
      up_rdata <= 32'd0;
      fixture_clear <= 1'b0;
      fixture_write <= 1'b0;
      fixture_write_data <= 32'd0;
      fixture_commit <= 1'b0;
      arm <= 1'b0;
      start_index_stage <= 64'd0;
      generation_stage <= 32'd0;
      current_index_snapshot <= 64'd0;
    end else begin
      up_wack <= up_wreq;
      up_rack <= up_rreq;
      fixture_clear <= 1'b0;
      fixture_write <= 1'b0;
      fixture_commit <= 1'b0;
      arm <= 1'b0;

      if (up_wreq) begin
        case (up_waddr)
          REG_FIXTURE_DATA: begin
            fixture_write_data <= up_wdata;
            fixture_write <= 1'b1;
          end
          REG_CONTROL: begin
            case (up_wdata)
              32'h0000_0001: fixture_clear <= 1'b1;
              32'h0000_0002: fixture_commit <= 1'b1;
              32'h0000_0004: arm <= 1'b1;
              default: begin
                // Present an impossible multi-command to the core so malformed
                // writes become a sticky rejection without changing state.
                fixture_clear <= 1'b1;
                fixture_commit <= 1'b1;
              end
            endcase
          end
          REG_START_INDEX_LO: start_index_stage[31:0] <= up_wdata;
          REG_START_INDEX_HI: start_index_stage[63:32] <= up_wdata;
          REG_GENERATION: generation_stage <= up_wdata;
          default: begin end
        endcase
      end

      if (up_rreq) begin
        case (up_raddr)
          REG_IDENTIFICATION: up_rdata <= IDENTIFICATION;
          REG_VERSION: up_rdata <= VERSION;
          REG_CAPABILITIES: up_rdata <= CAPABILITIES;
          REG_GEOMETRY: up_rdata <= {REPEAT_COUNT[15:0], SAMPLE_COUNT[15:0]};
          REG_PERIOD_SAMPLES: up_rdata <= PERIOD_SAMPLES;
          REG_CURRENT_INDEX_LO: begin
            current_index_snapshot <= current_sample_index;
            up_rdata <= current_sample_index[31:0];
          end
          REG_CURRENT_INDEX_HI: up_rdata <= current_index_snapshot[63:32];
          REG_FIXTURE_DATA: up_rdata <= 32'd0;
          REG_CONTROL: up_rdata <= 32'd0;
          REG_START_INDEX_LO: up_rdata <= start_index_stage[31:0];
          REG_START_INDEX_HI: up_rdata <= start_index_stage[63:32];
          REG_GENERATION: up_rdata <= generation_stage;
          REG_STATUS: up_rdata <= injection_status;
          REG_LAST_GENERATION: up_rdata <= last_completed_generation;
          REG_LAST_REPETITIONS: up_rdata <= last_completed_repetitions;
          REG_LAST_OFFSET_LO: up_rdata <= LAST_SAMPLE_OFFSET[31:0];
          REG_LAST_OFFSET_HI: up_rdata <= LAST_SAMPLE_OFFSET[63:32];
          default: up_rdata <= 32'd0;
        endcase
      end
    end
  end

  wire unused_protection = ^{s_axi_awprot, s_axi_arprot};
  wire unused_ready = fixture_write_ready ^ arm_ready;

endmodule
