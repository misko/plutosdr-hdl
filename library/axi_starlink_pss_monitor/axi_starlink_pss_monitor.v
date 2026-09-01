// -----------------------------------------------------------------------------
// axi_starlink_pss_monitor.v
//
// Read-only AXI-Lite monitor for the experimental repeated-delay candidate
// detector.  A candidate is a diagnostic hint only; it is not an exact PSS
// match and must never be reported as Starlink frame-alignment evidence without
// subsequent exact template correlation and cadence qualification.
// -----------------------------------------------------------------------------

`timescale 1ns/1ps

module axi_starlink_pss_monitor #(
  parameter integer RATE_MSPS = 15,
  parameter integer THRESHOLD_Q15 = 24576,
  parameter [40:0] MIN_WINDOW_ENERGY = 41'd1
) (
  // Post-decimator ADC stream.  sample_index is the same 64-bit counter
  // used by the capture timestamp path, before its increment for this beat.
  input  wire                 sample_clk,
  input  wire                 sample_reset,
  input  wire signed [15:0]   sample_i,
  input  wire signed [15:0]   sample_q,
  input  wire                 sample_strobe,
  input  wire                 sample_enable,
  input  wire [63:0]          sample_index,

  // Read-only AXI4-Lite register interface.
  input  wire                 s_axi_aclk,
  input  wire                 s_axi_aresetn,
  input  wire                 s_axi_awvalid,
  input  wire [6:0]           s_axi_awaddr,
  output wire                 s_axi_awready,
  input  wire                 s_axi_wvalid,
  input  wire [31:0]          s_axi_wdata,
  input  wire [3:0]           s_axi_wstrb,
  output wire                 s_axi_wready,
  output wire                 s_axi_bvalid,
  output wire [1:0]           s_axi_bresp,
  input  wire                 s_axi_bready,
  input  wire                 s_axi_arvalid,
  input  wire [6:0]           s_axi_araddr,
  output wire                 s_axi_arready,
  output wire                 s_axi_rvalid,
  output wire [1:0]           s_axi_rresp,
  output wire [31:0]          s_axi_rdata,
  input  wire                 s_axi_rready,
  input  wire [2:0]           s_axi_awprot,
  input  wire [2:0]           s_axi_arprot
);

  localparam integer DELAY_SAMPLES =
      (RATE_MSPS == 60) ? 32 : ((RATE_MSPS == 30) ? 16 : 8);
  localparam integer SYMBOL_SAMPLES =
      (RATE_MSPS == 60) ? 264 : ((RATE_MSPS == 30) ? 132 : 66);
  localparam integer CORRELATION_SAMPLES = SYMBOL_SAMPLES - DELAY_SAMPLES;
  localparam [31:0] GEOMETRY =
      {5'd0, CORRELATION_SAMPLES[8:0], SYMBOL_SAMPLES[8:0],
       DELAY_SAMPLES[8:0]};
  localparam [31:0] IDENTIFICATION = 32'h50535343; // ASCII "PSSC"
  localparam [31:0] VERSION = 32'h00010000;

  // Word addresses.  Every location is immutable; writes receive a normal
  // AXI response but are intentionally ignored.
  localparam [4:0] REG_IDENTIFICATION       = 5'h00; // 0x00
  localparam [4:0] REG_VERSION              = 5'h01; // 0x04
  localparam [4:0] REG_RATE_MSPS            = 5'h02; // 0x08
  localparam [4:0] REG_THRESHOLD_Q15        = 5'h03; // 0x0c
  localparam [4:0] REG_MIN_ENERGY_LO        = 5'h04; // 0x10
  localparam [4:0] REG_MIN_ENERGY_HI        = 5'h05; // 0x14
  localparam [4:0] REG_GEOMETRY             = 5'h06; // 0x18
  localparam [4:0] REG_METRIC_WIDTHS         = 5'h07; // 0x1c
  localparam [4:0] REG_GENERATION            = 5'h08; // 0x20
  localparam [4:0] REG_EVENT_COUNT_LO        = 5'h09; // 0x24
  localparam [4:0] REG_EVENT_COUNT_HI        = 5'h0a; // 0x28
  localparam [4:0] REG_SAMPLE_INDEX_LO       = 5'h0b; // 0x2c
  localparam [4:0] REG_SAMPLE_INDEX_HI       = 5'h0c; // 0x30
  localparam [4:0] REG_METRIC_NUM_LO         = 5'h0d; // 0x34
  localparam [4:0] REG_METRIC_NUM_MID        = 5'h0e; // 0x38
  localparam [4:0] REG_METRIC_NUM_HI         = 5'h0f; // 0x3c
  localparam [4:0] REG_METRIC_DEN_LO         = 5'h10; // 0x40
  localparam [4:0] REG_METRIC_DEN_MID        = 5'h11; // 0x44
  localparam [4:0] REG_METRIC_DEN_HI         = 5'h12; // 0x48

  wire            candidate_valid_s;
  wire [63:0]     candidate_sample_index_s;
  wire [82:0]     candidate_metric_num_s;
  wire [81:0]     candidate_metric_den_s;

  wire [31:0]     snapshot_generation_s;
  wire [63:0]     snapshot_event_count_s;
  wire [63:0]     snapshot_sample_index_s;
  wire [82:0]     snapshot_metric_num_s;
  wire [81:0]     snapshot_metric_den_s;

  wire            up_wreq_s;
  wire [4:0]      up_waddr_s;
  wire [31:0]     up_wdata_s;
  wire            up_rreq_s;
  wire [4:0]      up_raddr_s;
  reg             up_wack = 1'b0;
  reg             up_rack = 1'b0;
  reg [31:0]      up_rdata = 32'd0;

  // Keep lint and synthesis explicit about deliberately unused write fields.
  wire unused_write_fields = ^{s_axi_awprot, s_axi_arprot, up_waddr_s,
                               up_wdata_s};

  starlink_pss_delay_candidate #(
    .RATE_MSPS(RATE_MSPS),
    .THRESHOLD_Q15(THRESHOLD_Q15),
    .MIN_WINDOW_ENERGY(MIN_WINDOW_ENERGY)
  ) i_candidate_detector (
    .clk(sample_clk),
    .reset_n(~sample_reset),
    .in_i(sample_i),
    .in_q(sample_q),
    .in_enable(sample_enable),
    .in_valid(sample_strobe),
    .in_sample_index(sample_index),
    .candidate_valid(candidate_valid_s),
    .candidate_sample_index(candidate_sample_index_s),
    .candidate_metric_num(candidate_metric_num_s),
    .candidate_metric_den(candidate_metric_den_s)
  );

  starlink_pss_event_cdc i_event_cdc (
    .adc_clk(sample_clk),
    .adc_reset(sample_reset),
    .candidate_valid(candidate_valid_s),
    .candidate_sample_index(candidate_sample_index_s),
    .candidate_metric_num(candidate_metric_num_s),
    .candidate_metric_den(candidate_metric_den_s),
    .cpu_clk(s_axi_aclk),
    .cpu_resetn(s_axi_aresetn),
    .snapshot_generation(snapshot_generation_s),
    .snapshot_event_count(snapshot_event_count_s),
    .snapshot_sample_index(snapshot_sample_index_s),
    .snapshot_metric_num(snapshot_metric_num_s),
    .snapshot_metric_den(snapshot_metric_den_s)
  );

  // Read-only register bank.  The CDC module changes every snapshot word and
  // generation on the same CPU-clock edge.  Software uses generation as a
  // seqlock: generation -> payload -> generation, retrying when the two reads
  // differ.
  always @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
    if (!s_axi_aresetn) begin
      up_wack  <= 1'b0;
      up_rack  <= 1'b0;
      up_rdata <= 32'd0;
    end else begin
      up_wack <= up_wreq_s;
      up_rack <= up_rreq_s;

      if (up_rreq_s) begin
        case (up_raddr_s)
          REG_IDENTIFICATION:
            up_rdata <= IDENTIFICATION;
          REG_VERSION:
            up_rdata <= VERSION;
          REG_RATE_MSPS:
            up_rdata <= RATE_MSPS;
          REG_THRESHOLD_Q15:
            up_rdata <= THRESHOLD_Q15;
          REG_MIN_ENERGY_LO:
            up_rdata <= MIN_WINDOW_ENERGY[31:0];
          REG_MIN_ENERGY_HI:
            up_rdata <= {23'd0, MIN_WINDOW_ENERGY[40:32]};
          REG_GEOMETRY:
            up_rdata <= GEOMETRY;
          REG_METRIC_WIDTHS:
            up_rdata <= {16'd0, 8'd83, 8'd82};
          REG_GENERATION:
            up_rdata <= snapshot_generation_s;
          REG_EVENT_COUNT_LO:
            up_rdata <= snapshot_event_count_s[31:0];
          REG_EVENT_COUNT_HI:
            up_rdata <= snapshot_event_count_s[63:32];
          REG_SAMPLE_INDEX_LO:
            up_rdata <= snapshot_sample_index_s[31:0];
          REG_SAMPLE_INDEX_HI:
            up_rdata <= snapshot_sample_index_s[63:32];
          REG_METRIC_NUM_LO:
            up_rdata <= snapshot_metric_num_s[31:0];
          REG_METRIC_NUM_MID:
            up_rdata <= snapshot_metric_num_s[63:32];
          REG_METRIC_NUM_HI:
            up_rdata <= {13'd0, snapshot_metric_num_s[82:64]};
          REG_METRIC_DEN_LO:
            up_rdata <= snapshot_metric_den_s[31:0];
          REG_METRIC_DEN_MID:
            up_rdata <= snapshot_metric_den_s[63:32];
          REG_METRIC_DEN_HI:
            up_rdata <= {14'd0, snapshot_metric_den_s[81:64]};
          default:
            up_rdata <= 32'd0;
        endcase
      end else begin
        up_rdata <= 32'd0;
      end
    end
  end

  up_axi #(
    .AXI_ADDRESS_WIDTH(7)
  ) i_up_axi (
    .up_rstn(s_axi_aresetn),
    .up_clk(s_axi_aclk),
    .up_axi_awvalid(s_axi_awvalid),
    .up_axi_awaddr(s_axi_awaddr),
    .up_axi_awready(s_axi_awready),
    .up_axi_wvalid(s_axi_wvalid),
    .up_axi_wdata(s_axi_wdata),
    .up_axi_wstrb(s_axi_wstrb),
    .up_axi_wready(s_axi_wready),
    .up_axi_bvalid(s_axi_bvalid),
    .up_axi_bresp(s_axi_bresp),
    .up_axi_bready(s_axi_bready),
    .up_axi_arvalid(s_axi_arvalid),
    .up_axi_araddr(s_axi_araddr),
    .up_axi_arready(s_axi_arready),
    .up_axi_rvalid(s_axi_rvalid),
    .up_axi_rresp(s_axi_rresp),
    .up_axi_rdata(s_axi_rdata),
    .up_axi_rready(s_axi_rready),
    .up_wreq(up_wreq_s),
    .up_waddr(up_waddr_s),
    .up_wdata(up_wdata_s),
    .up_wack(up_wack),
    .up_rreq(up_rreq_s),
    .up_raddr(up_raddr_s),
    .up_rdata(up_rdata),
    .up_rack(up_rack)
  );

endmodule
