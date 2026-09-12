// Registered stimulus/observation harness; measures fabric-to-fabric paths.
// Random bus traffic preserves the real AXI decode/read mux, not a functional
// capture scenario. Simulation benches qualify its functional behavior.
module starlink_coarse25_capture_probe (input wire clk, output reg [71:0] observed);
  reg [2:0] startup = 0;
  reg [5:0] cadence = 0;
  reg [63:0] index = 0;
  reg [63:0] noise = 64'hf13916397307151a;
  wire resetn = startup == 7;
  wire strobe = cadence == 39;
  wire [31:0] rdata, iq;
  wire [1:0] bresp, rresp;
  wire awready, wready, bvalid, arready, rvalid, valid, enabled, irq;
  always @(posedge clk) begin
    if (!resetn) startup <= startup + 1'b1;
    cadence <= !resetn || strobe ? 0 : cadence + 1'b1;
    if (strobe) index <= index + 1'b1;
    noise <= {noise[62:0], noise[63]^noise[62]^noise[60]^noise[59]};
    observed <= {rdata, iq, bresp, rresp, bvalid, rvalid, valid, irq};
  end
  (* dont_touch = "yes" *) axi_starlink_pilot_capture #(.COARSE25_BYPASS(1)) dut (
    .s_axi_aclk(clk), .s_axi_aresetn(resetn),
    .s_axi_awvalid(noise[0]), .s_axi_awaddr(noise[8:1]), .s_axi_awready(awready),
    .s_axi_wdata(noise[31:0]), .s_axi_wstrb(noise[35:32]), .s_axi_wvalid(noise[36]),
    .s_axi_wready(wready), .s_axi_bvalid(bvalid), .s_axi_bresp(bresp), .s_axi_bready(noise[37]),
    .s_axi_arvalid(noise[38]), .s_axi_araddr(noise[46:39]), .s_axi_arready(arready),
    .s_axi_rvalid(rvalid), .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rready(noise[47]),
    .s_axi_awprot(3'd0), .s_axi_arprot(3'd0),
    .canonical_valid(strobe), .canonical_gap(noise[48]), .canonical_flush(noise[49]),
    .canonical_i(noise[15:0]), .canonical_q(noise[31:16]), .canonical_index(index),
    .pilot_enable(enabled), .m_axis_tvalid(valid), .m_axis_tdata(iq),
    .m_axis_tready(noise[50]), .irq(irq)
  );
endmodule
