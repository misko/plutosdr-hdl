// SPDX-License-Identifier: GPL-2.0
// Registered-boundary microprobe, not a receiver or deployment top.
`timescale 1ns/1ps
module descriptor_slots_timing_probe (
  input wire clk, resetn,
  input wire abort_in, allocate_in, commit_in, release_in, lookup_in,
  input wire [69:0] descriptor_in,
  input wire [31:0] commit_tag_in, release_tag_in, lookup_tag_in,
  output reg allocate_ready_out, lookup_found_out, lookup_committed_out,
  output reg exhausted_out, fault_out,
  output reg [31:0] allocate_tag_out,
  output reg [69:0] descriptor_out,
  output reg [1:0] occupied_out, committed_out
);
  reg abort_epoch, allocate_valid, commit_valid, release_valid, lookup_valid;
  reg [69:0] allocate_descriptor;
  reg [31:0] commit_tag, release_tag, lookup_tag;
  wire allocate_ready, lookup_found, lookup_committed, tags_exhausted, fault;
  wire [31:0] allocate_tag;
  wire [69:0] lookup_descriptor;
  wire [1:0] occupied, committed;
  starlink_pss_descriptor_slots slots(.*);
  always @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      abort_epoch<=0;allocate_valid<=0;commit_valid<=0;release_valid<=0;lookup_valid<=0;
      allocate_descriptor<=0;commit_tag<=0;release_tag<=0;lookup_tag<=0;
      allocate_ready_out<=0;lookup_found_out<=0;lookup_committed_out<=0;
      exhausted_out<=0;fault_out<=0;allocate_tag_out<=0;descriptor_out<=0;
      occupied_out<=0;committed_out<=0;
    end else begin
      abort_epoch<=abort_in;allocate_valid<=allocate_in;commit_valid<=commit_in;
      release_valid<=release_in;lookup_valid<=lookup_in;allocate_descriptor<=descriptor_in;
      commit_tag<=commit_tag_in;release_tag<=release_tag_in;lookup_tag<=lookup_tag_in;
      allocate_ready_out<=allocate_ready;lookup_found_out<=lookup_found;
      lookup_committed_out<=lookup_committed;exhausted_out<=tags_exhausted;fault_out<=fault;
      allocate_tag_out<=allocate_tag;descriptor_out<=lookup_descriptor;
      occupied_out<=occupied;committed_out<=committed;
    end
  end
endmodule
