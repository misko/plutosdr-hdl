// SPDX-License-Identifier: GPL-2.0
`timescale 1ns/1ps
`default_nettype none
// Clocked PRIVATE admission evidence. The caller holds the bank/descriptor
// while request is high and quarantines every current fault before core start.
// This token is never a substitute for current public-output fault fencing.
module starlink_pss_admission_certificate #(
  parameter integer CHECKS=24
) (
  input wire clk, resetn, request, quarantine, consume,
  input wire [CHECKS-1:0] checks_good,
  output wire permit,
  output reg snapshot_valid,
  output reg [CHECKS-1:0] snapshot_good
);
  reg consumed;
  assign permit = resetn && request && !quarantine && snapshot_valid &&
    ((&snapshot_good) === 1'b1) && !consumed;
  always @(posedge clk) begin
    if (!resetn || quarantine || !request) begin
      snapshot_valid<=0;snapshot_good<=0;consumed<=0;
    end else begin
      if (!snapshot_valid && !consumed) begin
        snapshot_good<=checks_good;snapshot_valid<=1;
      end
      if (consume && permit) begin snapshot_valid<=0;consumed<=1;end
    end
  end
endmodule
`default_nettype wire
