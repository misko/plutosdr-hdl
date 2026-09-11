// SPDX-License-Identifier: GPL-2.0
// Experimental writer-clock adapter: staged descriptor commands + one real
// explicit-commit payload bank. This is not the FFT completion validator.
// complete_* MUST describe an independently validated, fully privately written
// block, including its exact saved final word. No other writer may touch that
// bank from complete acceptance until publication_busy falls after release.
// replay_* exclusively drives that bank's final position/TLAST. replay_ready
// may indicate PRIVATE consumption if the caller separately gates actual
// authorization with current faults and aborts the epoch on a veto. The real
// bank request transition, never this private receipt, proves publication.
// bank_request/ack must be that bank's writer-domain ownership observations.
// All tag holders and both bank clock domains MUST share coordinated reset.
`timescale 1ns/1ps
module starlink_pss_completion_mailbox_stage #(
  parameter integer DESCRIPTOR_WIDTH=70, TAG_WIDTH=32, DATA_WIDTH=36,
  parameter integer PRIVATE_FINAL_CAPTURE=0
) (
  input wire clk, resetn, abort_epoch,
  input wire allocate_valid,
  output wire allocate_ready,
  input wire [DESCRIPTOR_WIDTH-1:0] allocate_descriptor,
  output wire allocated_valid,
  input wire allocated_ready,
  output reg [TAG_WIDTH-1:0] allocated_tag,
  input wire complete_valid,
  output wire complete_ready,
  input wire [TAG_WIDTH-1:0] complete_tag,
  input wire [DATA_WIDTH-1:0] complete_final_data,
  output wire replay_valid,
  input wire replay_ready,
  output wire [TAG_WIDTH-1:0] replay_tag,
  output wire [DATA_WIDTH-1:0] replay_data,
  input wire bank_request, bank_ack_sync, bank_fault,
  output wire publication_busy,
  output wire published_valid,
  output wire released_valid,
  output reg [TAG_WIDTH-1:0] released_tag,
  input wire lookup_valid,
  input wire [TAG_WIDTH-1:0] lookup_tag,
  output wire lookup_found, lookup_committed,
  output wire [DESCRIPTOR_WIDTH-1:0] lookup_descriptor,
  output wire [1:0] occupied, committed,
  output wire tags_exhausted, fault
);
  localparam [1:0] ALLOCATE=0, COMMIT=1, RELEASE=2;
  localparam [1:0] C_IDLE=0, C_SEND=1, C_RESPONSE=2;
  localparam [2:0] P_EMPTY=0, P_COMMIT=1, P_COMMIT_RESPONSE=2,
    P_REPLAY=3, P_ACK=4, P_RELEASE=5, P_RELEASE_RESPONSE=6;
  reg [1:0] command_state;
  reg [2:0] phase;
  reg [1:0] command_opcode;
  reg [TAG_WIDTH-1:0] command_tag, active_tag;
  reg [DESCRIPTOR_WIDTH-1:0] command_descriptor;
  reg [DATA_WIDTH-1:0] final_data;
  reg initial_request, fault_q, allocated_pending, released_pending;
  reg publication_seen, published_pending;
  // One-entry receipt: reserves/fixes payload immediately, sequences next edge.
  reg complete_pending;
  wire ledger_fault, command_ready, response_valid;
  wire [1:0] response_opcode;
  wire [TAG_WIDTH-1:0] response_tag;
  wire scalar_fault = abort_epoch !== 1'b0 || bank_fault !== 1'b0 ||
    (allocate_valid !== 1'b0 && allocate_valid !== 1'b1) ||
    (allocated_ready !== 1'b0 && allocated_ready !== 1'b1) ||
    (complete_valid !== 1'b0 && complete_valid !== 1'b1) ||
    (replay_ready !== 1'b0 && replay_ready !== 1'b1);
  assign fault = resetn && (fault_q || scalar_fault || ledger_fault);
  wire live = resetn && !fault;
  assign allocated_valid = live && allocated_pending;
  assign released_valid = live && released_pending;
  assign published_valid = live && published_pending;
  wire command_valid = live && command_state==C_SEND;
  wire response_ready = live && command_state==C_RESPONSE;
  // Never put a blocked third ALLOCATE into the serialized command port.
  // A held allocation result occupies only its return register, not this port.
  wire allocation_room = occupied!=2'b11 && !tags_exhausted && !allocated_valid;
  assign allocate_ready = live && !complete_pending && command_state==C_IDLE && allocation_room &&
    phase!=P_COMMIT && phase!=P_RELEASE;
  assign complete_ready = live && phase==P_EMPTY && !complete_pending &&
    ((bank_request===1'b0 && bank_ack_sync===1'b0) ||
     (bank_request===1'b1 && bank_ack_sync===1'b1));
  assign replay_valid = live && phase==P_REPLAY;
  assign replay_tag = active_tag;
  assign replay_data = final_data;
  assign publication_busy = phase!=P_EMPTY || complete_pending;

  starlink_pss_descriptor_commands #(.DESCRIPTOR_WIDTH(DESCRIPTOR_WIDTH),.TAG_WIDTH(TAG_WIDTH)) ledger (
    .clk(clk),.resetn(resetn),.abort_epoch(scalar_fault || fault_q),
    .command_valid(command_valid),.command_ready(command_ready),
    .command_opcode(command_opcode),.command_tag(command_tag),.command_descriptor(command_descriptor),
    .response_valid(response_valid),.response_ready(response_ready),
    .response_opcode(response_opcode),.response_tag(response_tag),
    .lookup_valid(lookup_valid),.lookup_tag(lookup_tag),.lookup_found(lookup_found),
    .lookup_committed(lookup_committed),.lookup_descriptor(lookup_descriptor),
    .occupied(occupied),.committed(committed),.tags_exhausted(tags_exhausted),.fault(ledger_fault)
  );

  // Private payloads may track unvalidated/X inputs only while ownership is
  // empty. Acceptance still uses the original fault-qualified handshake and
  // captures these same inputs on that edge. Non-empty phase freezes them
  // through COMMIT, replay, publication and the real reader ACK/RELEASE.
  // Invalid replay payloads have no meaning. No public-valid gate is removed.
  wire capture_final_payload = PRIVATE_FINAL_CAPTURE ? (phase==P_EMPTY && !complete_pending) :
    (!fault && complete_valid && complete_ready);
  always @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      active_tag<=0;final_data<=0;initial_request<=0;
    end else if (capture_final_payload) begin
      active_tag<=complete_tag;final_data<=complete_final_data;
      initial_request<=bank_request;
    end
  end

  always @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      command_state<=C_IDLE;phase<=P_EMPTY;command_opcode<=0;command_tag<=0;
      command_descriptor<=0;
      fault_q<=0;allocated_pending<=0;allocated_tag<=0;released_pending<=0;released_tag<=0;
      publication_seen<=0;published_pending<=0;complete_pending<=0;
    end else if (fault) begin
      fault_q<=1;allocated_pending<=0;released_pending<=0;
      published_pending<=0;
    end else begin
      released_pending<=0;
      published_pending<=0;
      if (allocated_valid && allocated_ready) allocated_pending<=0;
      if (complete_valid && complete_ready) begin
        complete_pending<=1;publication_seen<=0;
      end
      // Fault holds this private receipt occupied; reset alone purges it.
      // No publication/release is authorized merely by consuming the receipt.
      if (complete_pending) begin phase<=P_COMMIT;complete_pending<=0;end
      if (phase==P_REPLAY && replay_ready) phase<=P_ACK;
      // P_ACK is an observation boundary, not proof of publication. Reject a
      // missing actual request transition before notification or RELEASE.
      // Equality while idle, or merely a successful COMMIT response, is NOT ACK.
      if (phase==P_ACK) begin
        if (bank_request !== !initial_request ||
            (bank_ack_sync !== 1'b0 && bank_ack_sync !== 1'b1)) fault_q<=1;
        else begin
          if (!publication_seen) begin publication_seen<=1;published_pending<=1;end
          if (bank_ack_sync==bank_request) phase<=P_RELEASE;
        end
      end
      case (command_state)
        C_IDLE: begin
          // Payload release/completion take priority over new allocation.
          if (phase==P_RELEASE || phase==P_COMMIT) begin
            command_opcode<=phase==P_RELEASE ? RELEASE : COMMIT;
            command_tag<=active_tag;command_descriptor<=0;command_state<=C_SEND;
            phase<=phase==P_RELEASE ? P_RELEASE_RESPONSE : P_COMMIT_RESPONSE;
          end else if (allocate_valid && allocate_ready) begin
            command_opcode<=ALLOCATE;command_tag<=0;
            command_descriptor<=allocate_descriptor;command_state<=C_SEND;
          end
        end
        C_SEND: if (command_ready) command_state<=C_RESPONSE;
        C_RESPONSE: if (response_valid) begin
          command_state<=C_IDLE;
          if (response_opcode!==command_opcode ||
              (command_opcode!=ALLOCATE && response_tag!==active_tag)) fault_q<=1;
          else case (command_opcode)
            ALLOCATE: begin allocated_pending<=1;allocated_tag<=response_tag;end
            COMMIT: phase<=P_REPLAY;
            RELEASE: begin phase<=P_EMPTY;released_pending<=1;released_tag<=response_tag;end
            default: fault_q<=1;
          endcase
        end
        default: fault_q<=1;
      endcase
    end
  end
endmodule
