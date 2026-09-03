// SPDX-License-Identifier: GPL-2.0
//
// Attach a modulo-frame phase to a consecutive normalized-score stream.
// The first score after reset, disable, flush, or an explicit discontinuity
// establishes phase zero.  A score-index jump is suppressed, reported as a
// discontinuity, and the following consecutive score establishes phase zero.
// Wall-clock gaps between valid scores are harmless: only accepted-score
// indexes define continuity.

`timescale 1ns/1ps

module starlink_pss_score_phase_tagger #(
  parameter integer PHASE_BINS = 20000,
  parameter integer PHASE_INDEX_WIDTH = 15,
  parameter integer SCORE_WIDTH = 8
) (
  input  wire                          clk,
  input  wire                          resetn,
  input  wire                          enable,
  input  wire                          flush,

  input  wire                          score_valid,
  input  wire [63:0]                   score_start_index,
  input  wire [SCORE_WIDTH-1:0]        score_value,
  input  wire                          stream_discontinuity,

  output wire                          tagged_valid,
  output wire [63:0]                   tagged_start_index,
  output wire [PHASE_INDEX_WIDTH-1:0]  tagged_phase,
  output wire [SCORE_WIDTH-1:0]        tagged_value,
  output wire                          tagged_stream_discontinuity,
  output wire                          accepted_pulse,
  output wire                          index_discontinuity_pulse
);

  localparam [PHASE_INDEX_WIDTH-1:0] LAST_PHASE = PHASE_BINS - 1;

  generate
    if (PHASE_BINS < 2) begin : g_invalid_phase_bins
      initial $fatal(1, "phase tagger requires at least two phase bins");
    end
    if ((1 << PHASE_INDEX_WIDTH) < PHASE_BINS) begin : g_invalid_phase_width
      initial $fatal(1, "PHASE_INDEX_WIDTH cannot address every phase bin");
    end
  endgenerate

  reg tracking;
  reg [63:0] expected_score_index;
  reg [PHASE_INDEX_WIDTH-1:0] next_phase;

  wire active = resetn && enable && !flush;
  wire index_matches = !tracking || score_start_index == expected_score_index;
  wire index_discontinuity = active && score_valid && tracking &&
      !stream_discontinuity && !index_matches;
  wire score_publish = active && score_valid && !stream_discontinuity &&
      !index_discontinuity;

  assign tagged_valid = score_publish;
  assign tagged_start_index = score_start_index;
  assign tagged_phase = tracking ? next_phase :
      {PHASE_INDEX_WIDTH{1'b0}};
  assign tagged_value = score_value;
  assign tagged_stream_discontinuity = active &&
      (stream_discontinuity || index_discontinuity);
  assign accepted_pulse = score_publish;
  assign index_discontinuity_pulse = index_discontinuity;

  always @(posedge clk) begin
    if (!resetn || !enable || flush) begin
      tracking <= 1'b0;
      expected_score_index <= 64'd0;
      next_phase <= {PHASE_INDEX_WIDTH{1'b0}};
    end else if (stream_discontinuity) begin
      tracking <= 1'b0;
      expected_score_index <= 64'd0;
      next_phase <= {PHASE_INDEX_WIDTH{1'b0}};
    end else if (score_valid) begin
      if (!tracking) begin
        tracking <= 1'b1;
        expected_score_index <= score_start_index + 1'b1;
        next_phase <= {{(PHASE_INDEX_WIDTH-1){1'b0}}, 1'b1};
      end else if (score_start_index == expected_score_index) begin
        expected_score_index <= score_start_index + 1'b1;
        if (next_phase == LAST_PHASE)
          next_phase <= {PHASE_INDEX_WIDTH{1'b0}};
        else
          next_phase <= next_phase + 1'b1;
      end else begin
        // Suppress the mismatched score.  It becomes the continuity anchor so
        // that the immediately following consecutive score can restart at
        // phase zero without requiring a second discarded score.
        tracking <= 1'b1;
        expected_score_index <= score_start_index + 1'b1;
        next_phase <= {PHASE_INDEX_WIDTH{1'b0}};
      end
    end
  end

endmodule
