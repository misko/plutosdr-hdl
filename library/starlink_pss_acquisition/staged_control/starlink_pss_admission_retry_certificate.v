// SPDX-License-Identifier: GPL-2.0
`timescale 1ns/1ps
`default_nettype none
// Private, retrying admission evidence for a held-bank/held-descriptor request.
// A rejected snapshot may be resampled; a good snapshot is immutable until
// consumption or cancellation. Quarantine/current public fences remain external.
// Request deassertion must cross a clock edge before a different held job.
// Unknown checks never grant. There is no new payload storage or clock domain.
module starlink_pss_admission_retry_certificate #(
  parameter integer CHECKS=36
) (
  input wire clk, resetn, request, quarantine, consume,
  input wire [CHECKS-1:0] checks_good,
  output wire permit,
  output reg snapshot_valid,
  output reg [CHECKS-1:0] snapshot_good
);
  reg consumed;
  wire sampled_good = ((&snapshot_good) === 1'b1);
  assign permit = resetn && request && !quarantine && snapshot_valid &&
    sampled_good && !consumed;
  // Private evidence has no value contract while invalid. The small validity
  // and consumption bits retain the original synchronous reset behavior.
  always @(posedge clk)
    if ((!snapshot_valid || !sampled_good) && !consumed)
      snapshot_good <= checks_good;
  always @(posedge clk) begin
    if (!resetn || quarantine || !request) begin
      snapshot_valid <= 0; consumed <= 0;
    end else begin
      if (!consumed) snapshot_valid <= 1;
      if (consume && permit) begin snapshot_valid <= 0; consumed <= 1; end
    end
  end
endmodule
`default_nettype wire
