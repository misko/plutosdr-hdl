// SPDX-License-Identifier: GPL-2.0
//
// Signed 48-bit, after-tap saturating addition used by the experimental
// Starlink exact-PSS raw correlator.  This file belongs only to the
// starlink-rx-only-do-not-merge HDL branch.

`timescale 1ns/1ps

module starlink_sat_add48 (
  input  wire signed [47:0] i_accumulator,
  input  wire signed [35:0] i_addend,
  output reg  signed [47:0] o_result,
  output reg                o_saturated
);

  // These are the signed-49 representations of +2^47-1 and -2^47.
  localparam signed [48:0] ACCUMULATOR_MAX_EXT =
      {2'b00, {47{1'b1}}};
  localparam signed [48:0] ACCUMULATOR_MIN_EXT =
      {2'b11, {47{1'b0}}};

  reg signed [48:0] extended_sum;

  always @* begin
    extended_sum = {i_accumulator[47], i_accumulator} +
                   {{13{i_addend[35]}}, i_addend};
    o_saturated = 1'b0;
    if (extended_sum > ACCUMULATOR_MAX_EXT) begin
      o_result = {1'b0, {47{1'b1}}};
      o_saturated = 1'b1;
    end else if (extended_sum < ACCUMULATOR_MIN_EXT) begin
      o_result = {1'b1, {47{1'b0}}};
      o_saturated = 1'b1;
    end else begin
      o_result = extended_sum[47:0];
    end
  end

endmodule
