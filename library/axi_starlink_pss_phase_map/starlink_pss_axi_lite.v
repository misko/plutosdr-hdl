// SPDX-License-Identifier: GPL-2.0
//
// Single-outstanding AXI4-Lite front end for the Starlink PSS phase-map IP.
// Read acknowledgements may take longer than the fixed timeout in ADI's
// generic up_axi helper because MAP_DATA crosses into the acquisition clock.

`timescale 1ns/1ps

module starlink_pss_axi_lite #(
  parameter integer AXI_ADDRESS_WIDTH = 8
) (
  input  wire                              clk,
  input  wire                              resetn,

  input  wire                              s_axi_awvalid,
  input  wire [AXI_ADDRESS_WIDTH-1:0]      s_axi_awaddr,
  output wire                              s_axi_awready,
  input  wire                              s_axi_wvalid,
  input  wire [31:0]                       s_axi_wdata,
  input  wire [3:0]                        s_axi_wstrb,
  output wire                              s_axi_wready,
  output reg                               s_axi_bvalid,
  output wire [1:0]                        s_axi_bresp,
  input  wire                              s_axi_bready,

  input  wire                              s_axi_arvalid,
  input  wire [AXI_ADDRESS_WIDTH-1:0]      s_axi_araddr,
  output wire                              s_axi_arready,
  output reg                               s_axi_rvalid,
  output wire [1:0]                        s_axi_rresp,
  output reg  [31:0]                       s_axi_rdata,
  input  wire                              s_axi_rready,

  output reg                               up_wreq,
  output reg  [AXI_ADDRESS_WIDTH-3:0]      up_waddr,
  output reg  [31:0]                       up_wdata,
  output reg  [3:0]                        up_wstrb,
  input  wire                              up_wack,
  output reg                               up_rreq,
  output reg  [AXI_ADDRESS_WIDTH-3:0]      up_raddr,
  input  wire [31:0]                       up_rdata,
  input  wire                              up_rack
);

  generate
    if (AXI_ADDRESS_WIDTH < 3) begin : g_invalid_axi_address_width
      initial $fatal(1, "AXI address width must be at least three bits");
    end
  endgenerate

  reg aw_pending;
  reg [AXI_ADDRESS_WIDTH-1:0] awaddr_pending;
  reg w_pending;
  reg [31:0] wdata_pending;
  reg [3:0] wstrb_pending;
  reg write_waiting;

  reg ar_pending;
  reg [AXI_ADDRESS_WIDTH-1:0] araddr_pending;
  reg read_waiting;

  assign s_axi_awready = resetn && !aw_pending &&
      !write_waiting && !s_axi_bvalid;
  assign s_axi_wready = resetn && !w_pending &&
      !write_waiting && !s_axi_bvalid;
  assign s_axi_bresp = 2'b00;

  assign s_axi_arready = resetn && !ar_pending &&
      !read_waiting && !s_axi_rvalid;
  assign s_axi_rresp = 2'b00;

  always @(posedge clk) begin
    if (!resetn) begin
      aw_pending <= 1'b0;
      awaddr_pending <= {AXI_ADDRESS_WIDTH{1'b0}};
      w_pending <= 1'b0;
      wdata_pending <= 32'd0;
      wstrb_pending <= 4'd0;
      write_waiting <= 1'b0;
      s_axi_bvalid <= 1'b0;
      up_wreq <= 1'b0;
      up_waddr <= {(AXI_ADDRESS_WIDTH-2){1'b0}};
      up_wdata <= 32'd0;
      up_wstrb <= 4'd0;
    end else begin
      up_wreq <= 1'b0;

      if (s_axi_awready && s_axi_awvalid) begin
        aw_pending <= 1'b1;
        awaddr_pending <= s_axi_awaddr;
      end
      if (s_axi_wready && s_axi_wvalid) begin
        w_pending <= 1'b1;
        wdata_pending <= s_axi_wdata;
        wstrb_pending <= s_axi_wstrb;
      end

      if (!write_waiting && !s_axi_bvalid && aw_pending && w_pending) begin
        up_wreq <= 1'b1;
        up_waddr <= awaddr_pending[AXI_ADDRESS_WIDTH-1:2];
        up_wdata <= wdata_pending;
        up_wstrb <= wstrb_pending;
        aw_pending <= 1'b0;
        w_pending <= 1'b0;
        write_waiting <= 1'b1;
      end

      if (write_waiting && up_wack) begin
        write_waiting <= 1'b0;
        s_axi_bvalid <= 1'b1;
      end else if (s_axi_bvalid && s_axi_bready) begin
        s_axi_bvalid <= 1'b0;
      end
    end
  end

  always @(posedge clk) begin
    if (!resetn) begin
      ar_pending <= 1'b0;
      araddr_pending <= {AXI_ADDRESS_WIDTH{1'b0}};
      read_waiting <= 1'b0;
      s_axi_rvalid <= 1'b0;
      s_axi_rdata <= 32'd0;
      up_rreq <= 1'b0;
      up_raddr <= {(AXI_ADDRESS_WIDTH-2){1'b0}};
    end else begin
      up_rreq <= 1'b0;

      if (s_axi_arready && s_axi_arvalid) begin
        ar_pending <= 1'b1;
        araddr_pending <= s_axi_araddr;
      end

      if (!read_waiting && !s_axi_rvalid && ar_pending) begin
        up_rreq <= 1'b1;
        up_raddr <= araddr_pending[AXI_ADDRESS_WIDTH-1:2];
        ar_pending <= 1'b0;
        read_waiting <= 1'b1;
      end

      if (read_waiting && up_rack) begin
        read_waiting <= 1'b0;
        s_axi_rvalid <= 1'b1;
        s_axi_rdata <= up_rdata;
      end else if (s_axi_rvalid && s_axi_rready) begin
        s_axi_rvalid <= 1'b0;
        s_axi_rdata <= 32'd0;
      end
    end
  end

endmodule
