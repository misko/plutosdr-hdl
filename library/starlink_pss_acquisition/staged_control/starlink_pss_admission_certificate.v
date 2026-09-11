// SPDX-License-Identifier: GPL-2.0
`timescale 1ns/1ps
`default_nettype none
// Clocked PRIVATE admission evidence. The caller holds the bank/descriptor
// while request is high and quarantines every current fault before core start.
// This token is never a substitute for current public-output fault fencing.
module starlink_pss_admission_certificate #(
  parameter integer CHECKS=24,
  parameter integer PRIVATE_FACT_CAPTURE=0
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
  // Invalid evidence is private and has no reset value contract in opt-in mode.
  // Capture on the original acceptance edge, then hold while valid/consumed.
  // Validity and current permit fencing below remain the original authority.
  generate if (PRIVATE_FACT_CAPTURE) begin : private_facts
    always @(posedge clk)
      if (!snapshot_valid && !consumed) snapshot_good<=checks_good;
  end else begin : legacy_facts
    always @(posedge clk)
      if (!resetn || quarantine || !request) snapshot_good<=0;
      else if (!snapshot_valid && !consumed) snapshot_good<=checks_good;
  end endgenerate
  always @(posedge clk) begin
    if (!resetn || quarantine || !request) begin
      snapshot_valid<=0;consumed<=0;
    end else begin
      if (!snapshot_valid && !consumed) begin
        snapshot_valid<=1;
      end
      if (consume && permit) begin snapshot_valid<=0;consumed<=1;end
    end
  end
endmodule
`default_nettype wire
