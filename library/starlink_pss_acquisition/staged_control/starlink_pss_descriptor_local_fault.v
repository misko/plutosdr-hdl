// SPDX-License-Identifier: GPL-2.0
// Experimental serialized control plane; sample/FFT processing is independent.
`timescale 1ns/1ps
module starlink_pss_descriptor_local_fault #(
  parameter integer DESCRIPTOR_WIDTH=70, TAG_WIDTH=32
) (
  input wire clk, resetn, abort_epoch,
  input wire command_valid,
  output wire command_ready,
  input wire [1:0] command_opcode,
  input wire [TAG_WIDTH-1:0] command_tag,
  input wire [DESCRIPTOR_WIDTH-1:0] command_descriptor,
  output wire response_valid,
  input wire response_ready,
  output reg [1:0] response_opcode,
  output reg [TAG_WIDTH-1:0] response_tag,
  input wire lookup_valid,
  input wire [TAG_WIDTH-1:0] lookup_tag,
  output wire lookup_found, lookup_committed,
  output wire [DESCRIPTOR_WIDTH-1:0] lookup_descriptor,
  output wire [1:0] occupied, committed,
  output wire tags_exhausted, fault,
  output wire local_fault
);
  localparam [1:0] ALLOCATE=0, COMMIT=1, RELEASE=2;
  localparam [1:0] FREE=0, OWNED=1, PUBLISHED=2;
  reg [1:0] state0, state1;
  reg [TAG_WIDTH-1:0] tag0, tag1, next_tag;
  reg [DESCRIPTOR_WIDTH-1:0] descriptor0, descriptor1;
  reg exhausted, fault_q, response_pending;
  reg pending, pending_good, pending_slot;
  reg [1:0] pending_opcode;
  reg [TAG_WIDTH-1:0] pending_tag;
  reg [DESCRIPTOR_WIDTH-1:0] pending_descriptor;

  initial if (TAG_WIDTH<1 || DESCRIPTOR_WIDTH<1)
    $fatal(1,"positive descriptor/tag widths required");

  wire tag_match0 = command_tag === tag0;
  wire tag_match1 = command_tag === tag1;
  wire commit0 = state0==OWNED && tag_match0;
  wire commit1 = state1==OWNED && tag_match1;
  wire release0 = state0==PUBLISHED && tag_match0;
  wire release1 = state1==PUBLISHED && tag_match1;
  // Scalar front-end controls only. Wide tag validation ends at pending_good.
  wire abort_now = abort_epoch !== 1'b0 ||
    (command_valid !== 1'b0 && command_valid !== 1'b1) ||
    (response_ready !== 1'b0 && response_ready !== 1'b1);
  assign fault = resetn && (fault_q || abort_now || (pending && !pending_good));
  // Caller retains abort_epoch as an immediate veto. Do not echo it through
  // another hierarchy of fault reductions; every intrinsic cause stays live.
  assign local_fault = resetn && (fault_q || (pending && !pending_good) ||
    (command_valid !== 1'b0 && command_valid !== 1'b1) ||
    (response_ready !== 1'b0 && response_ready !== 1'b1));
  wire live = resetn && !fault;
  assign command_ready = resetn && !abort_now && !fault_q && !pending && !response_pending &&
    (command_opcode !== ALLOCATE || (!exhausted && (state0==FREE || state1==FREE)));
  assign response_valid = live && response_pending;
  assign tags_exhausted = exhausted;
  assign occupied = {state1!=FREE,state0!=FREE};
  assign committed = live ? {state1==PUBLISHED,state0==PUBLISHED} : 2'b0;
  wire lookup0 = state0!=FREE && lookup_tag === tag0;
  wire lookup1 = state1!=FREE && lookup_tag === tag1;
  assign lookup_found = live && lookup_valid === 1'b1 && (lookup0 || lookup1);
  assign lookup_committed = lookup_found &&
    ((lookup0 && state0==PUBLISHED) || (lookup1 && state1==PUBLISHED));
  assign lookup_descriptor = lookup_found ? (lookup0 ? descriptor0 : descriptor1) : {DESCRIPTOR_WIDTH{1'b0}};

  // At most one command or unconsumed response exists. No allocation/commit/
  // release can alter either slot between validation and applying its result.
  always @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      state0<=FREE;state1<=FREE;tag0<=0;tag1<=0;next_tag<=0;
      descriptor0<=0;descriptor1<=0;exhausted<=0;fault_q<=0;
      response_pending<=0;response_opcode<=0;response_tag<=0;
      pending<=0;pending_good<=0;pending_slot<=0;pending_opcode<=0;
      pending_tag<=0;pending_descriptor<=0;
    end else if (abort_now || fault_q) begin
      fault_q<=1;pending<=0;response_pending<=0;
    end else begin
      if (response_pending && response_ready) response_pending<=0;
      if (pending) begin
        pending<=0;
        if (!pending_good) begin fault_q<=1;response_pending<=0;end
        else begin
          response_pending<=1;response_opcode<=pending_opcode;response_tag<=pending_tag;
          case (pending_opcode)
            ALLOCATE: begin
              if (!pending_slot) begin state0<=OWNED;tag0<=pending_tag;descriptor0<=pending_descriptor;end
              else begin state1<=OWNED;tag1<=pending_tag;descriptor1<=pending_descriptor;end
              if (&next_tag) exhausted<=1;
              else next_tag<=next_tag+1'b1;
            end
            COMMIT: if (!pending_slot) state0<=PUBLISHED;else state1<=PUBLISHED;
            RELEASE: if (!pending_slot) state0<=FREE;else state1<=FREE;
            default: begin fault_q<=1;response_pending<=0;end
          endcase
        end
      end else if (command_valid && command_ready) begin
        pending<=1;pending_opcode<=command_opcode;
        pending_tag<=command_tag;pending_descriptor<=command_descriptor;
        pending_slot<=0;pending_good<=0;
        case (command_opcode)
          ALLOCATE: begin
            pending_good<=1;pending_slot<=state0!=FREE;pending_tag<=next_tag;
          end
          COMMIT: begin pending_good<=commit0 || commit1;pending_slot<=!commit0;end
          RELEASE: begin pending_good<=release0 || release1;pending_slot<=!release0;end
          default: pending_good<=0;
        endcase
      end
    end
  end
endmodule
