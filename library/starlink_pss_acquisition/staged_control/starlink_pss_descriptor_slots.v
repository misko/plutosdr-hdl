// SPDX-License-Identifier: GPL-2.0
// Experimental single-clock ownership table; not connected to the receiver.
`timescale 1ns/1ps
module starlink_pss_descriptor_slots #(
  parameter integer DESCRIPTOR_WIDTH = 70,
  parameter integer TAG_WIDTH = 32
) (
  input wire clk, resetn,
  // resetn starts a coordinated epoch: all upstream/downstream token holders
  // must be reset/drained too. This table alone cannot prove that boundary.
  input wire abort_epoch,
  input wire allocate_valid,
  output wire allocate_ready,
  input wire [DESCRIPTOR_WIDTH-1:0] allocate_descriptor,
  output wire [TAG_WIDTH-1:0] allocate_tag,
  // A commit is a pulse from a completed validator, not raw FFT TLAST/status.
  input wire commit_valid,
  input wire [TAG_WIDTH-1:0] commit_tag,
  // Release is a pulse from the real consuming buffer, never a timeout.
  input wire release_valid,
  input wire [TAG_WIDTH-1:0] release_tag,
  input wire lookup_valid,
  input wire [TAG_WIDTH-1:0] lookup_tag,
  output wire lookup_found,
  output wire lookup_committed,
  output wire [DESCRIPTOR_WIDTH-1:0] lookup_descriptor,
  output wire [1:0] occupied,
  output wire [1:0] committed,
  output wire tags_exhausted,
  output wire fault
);
  localparam [1:0] FREE=0, OWNED=1, COMMITTED=2;
  reg [1:0] state0, state1;
  reg [DESCRIPTOR_WIDTH-1:0] descriptor0, descriptor1;
  reg [TAG_WIDTH-1:0] tag0, tag1, next_tag;
  reg exhausted, fault_q;

  initial begin
    if (TAG_WIDTH < 1 || DESCRIPTOR_WIDTH < 1)
      $fatal(1, "positive descriptor/tag widths required");
  end

  wire commit0 = state0 == OWNED && commit_tag === tag0;
  wire commit1 = state1 == OWNED && commit_tag === tag1;
  wire release0 = state0 == COMMITTED && release_tag === tag0;
  wire release1 = state1 == COMMITTED && release_tag === tag1;
  // Bad/duplicate/stale transition commands quarantine the whole epoch.
  // Backpressured allocation is legal and is not an error.
  wire commands_known = (commit_valid === 1'b0 || commit_valid === 1'b1) &&
    (release_valid === 1'b0 || release_valid === 1'b1) &&
    (allocate_valid === 1'b0 || allocate_valid === 1'b1) &&
    (abort_epoch === 1'b0 || abort_epoch === 1'b1);
  wire command_error = !commands_known || abort_epoch ||
    (commit_valid && !(commit0 || commit1)) ||
    (release_valid && !(release0 || release1));
  assign fault = resetn && (fault_q || command_error);
  wire live = resetn && !fault;
  assign allocate_ready = live && !exhausted && (state0 == FREE || state1 == FREE);
  assign allocate_tag = next_tag;
  assign tags_exhausted = exhausted;
  assign occupied = {state1 != FREE, state0 != FREE};
  assign committed = live ? {state1 == COMMITTED, state0 == COMMITTED} : 2'b0;
  wire lookup0 = state0 != FREE && lookup_tag === tag0;
  wire lookup1 = state1 != FREE && lookup_tag === tag1;
  assign lookup_found = live && lookup_valid === 1'b1 && (lookup0 || lookup1);
  assign lookup_committed = lookup_found &&
    ((lookup0 && state0 == COMMITTED) || (lookup1 && state1 == COMMITTED));
  assign lookup_descriptor = lookup_found ? (lookup0 ? descriptor0 : descriptor1) : {DESCRIPTOR_WIDTH{1'b0}};

  always @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      state0 <= FREE; state1 <= FREE;
      descriptor0 <= 0; descriptor1 <= 0;
      tag0 <= 0; tag1 <= 0; next_tag <= 0;
      exhausted <= 0; fault_q <= 0;
    end else if (fault_q || command_error) begin
      fault_q <= 1;
      // Keep private ownership evidence. No lookup/publication is authorized.
    end else begin
      if (commit_valid) begin
        if (commit0) state0 <= COMMITTED;
        if (commit1) state1 <= COMMITTED;
      end
      if (release_valid) begin
        if (release0) state0 <= FREE;
        if (release1) state1 <= FREE;
      end
      if (allocate_valid && allocate_ready) begin
        // A just-released slot is not reused until the following cycle.
        if (state0 == FREE) begin
          state0 <= OWNED; descriptor0 <= allocate_descriptor; tag0 <= next_tag;
        end else begin
          state1 <= OWNED; descriptor1 <= allocate_descriptor; tag1 <= next_tag;
        end
        // Never wrap inside an epoch. Exhaustion blocks new work, but existing
        // owners can still commit and release before a coordinated restart.
        if (&next_tag) exhausted <= 1;
        else next_tag <= next_tag + 1'b1;
      end
    end
  end
endmodule
