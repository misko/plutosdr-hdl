// ***************************************************************************
// RX-only replacement for the AXI AD9361 transmit register hierarchy.
//
// The ADC and DAC register banks share one up_axi aperture.  A disabled DAC
// responder must therefore acknowledge only addresses formerly owned by the
// DAC common/channel blocks.  A responder that acknowledges every request can
// complete an ADC read before the ADC bank returns its data.
// ***************************************************************************

`timescale 1ns/100ps

module axi_ad9361_tx_null #(
  parameter MODE_1R1T = 0
) (
  input           up_wreq,
  input   [13:0]  up_waddr,
  output          up_wack,
  input           up_rreq,
  input   [13:0]  up_raddr,
  output  [31:0]  up_rdata,
  output          up_rack
);

  wire write_common_selected;
  wire write_channel_selected;
  wire read_common_selected;
  wire read_channel_selected;

  // Match the implemented ranges in up_dac_common and up_dac_channel.  The
  // disabled DAC delay controller intentionally remains unacknowledged, just
  // as up_delay_cntrl does when its DISABLE parameter is set.
  assign write_common_selected =
    (up_waddr[13:7] == {6'h10, 1'b0});
  assign write_channel_selected =
    (up_waddr[13:8] == 6'h11) &&
    (up_waddr[7:4] < (MODE_1R1T ? 4'd2 : 4'd4));
  assign read_common_selected =
    (up_raddr[13:7] == {6'h10, 1'b0});
  assign read_channel_selected =
    (up_raddr[13:8] == 6'h11) &&
    (up_raddr[7:4] < (MODE_1R1T ? 4'd2 : 4'd4));

  assign up_wack = up_wreq &
    (write_common_selected | write_channel_selected);
  assign up_rack = up_rreq &
    (read_common_selected | read_channel_selected);
  assign up_rdata = 32'd0;

endmodule
