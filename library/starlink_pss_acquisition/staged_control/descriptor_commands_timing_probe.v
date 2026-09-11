// SPDX-License-Identifier: GPL-2.0
// Registered-boundary staged command microprobe; not a receiver top.
`timescale 1ns/1ps
module descriptor_commands_timing_probe (
  input wire clk, resetn,
  input wire abort_in, command_valid_in, response_ready_in, lookup_valid_in,
  input wire [1:0] command_opcode_in,
  input wire [31:0] command_tag_in, lookup_tag_in,
  input wire [69:0] command_descriptor_in,
  output reg command_ready_out, response_valid_out, lookup_found_out,
  output reg lookup_committed_out, exhausted_out, fault_out,
  output reg [1:0] response_opcode_out, occupied_out, committed_out,
  output reg [31:0] response_tag_out,
  output reg [69:0] descriptor_out
);
  reg abort_epoch, command_valid, response_ready, lookup_valid;
  reg [1:0] command_opcode;
  reg [31:0] command_tag, lookup_tag;
  reg [69:0] command_descriptor;
  wire command_ready,response_valid,lookup_found,lookup_committed,tags_exhausted,fault;
  wire [1:0] response_opcode,occupied,committed;
  wire [31:0] response_tag;
  wire [69:0] lookup_descriptor;
  starlink_pss_descriptor_commands commands(.*);
  always @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      abort_epoch<=0;command_valid<=0;response_ready<=0;lookup_valid<=0;
      command_opcode<=0;command_tag<=0;lookup_tag<=0;command_descriptor<=0;
      command_ready_out<=0;response_valid_out<=0;lookup_found_out<=0;
      lookup_committed_out<=0;exhausted_out<=0;fault_out<=0;response_opcode_out<=0;
      occupied_out<=0;committed_out<=0;response_tag_out<=0;descriptor_out<=0;
    end else begin
      abort_epoch<=abort_in;command_valid<=command_valid_in;response_ready<=response_ready_in;
      lookup_valid<=lookup_valid_in;command_opcode<=command_opcode_in;
      command_tag<=command_tag_in;lookup_tag<=lookup_tag_in;command_descriptor<=command_descriptor_in;
      command_ready_out<=command_ready;response_valid_out<=response_valid;
      lookup_found_out<=lookup_found;lookup_committed_out<=lookup_committed;
      exhausted_out<=tags_exhausted;fault_out<=fault;response_opcode_out<=response_opcode;
      occupied_out<=occupied;committed_out<=committed;response_tag_out<=response_tag;
      descriptor_out<=lookup_descriptor;
    end
  end
endmodule
