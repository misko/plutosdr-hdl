// SPDX-License-Identifier: GPL-2.0
// OFFLINE EXPERIMENT ONLY. One actual 512x36 RAM, fast-clock-only prototype.
// Default is the exact original explicit-commit mailbox. The opt-in separates
// private takes, pipelined checked sealing and publication; it changes latency.
//
// Lease/reset contract: a tagged release promises that the producer and the
// certificate issuer have no queued/held/in-flight reference to this lease.
// It is accepted only after actual final read/ACK and local pipeline drain.
// Two bits DO NOT reject arbitrarily delayed equal-tag certificates after wrap.
// Either reset invalidates everything; explicit rearm requires engine held in
// reset plus producer/certificate/consumer epoch-idle acknowledgements. Intended
// issuers: input/return pipeline controller, transform-status issuer, and bank
// reader/ACK controller. Their queues must be flushed before those acknowledgements.
// Those external controllers are NOT implemented or counted as state here.
`timescale 1ns/1ps
module starlink_pss_epoch_sealed_bank #(
  parameter integer SEALED_PUBLICATION = 0
) (
  input wire clk, input_resetn, output_resetn,
  input wire input_valid,
  // Issuer owns this pending-reference bit until private_take. It falls after
  // take even if legacy VALID keeps holding final payload; a new raw core event
  // creates a new reference (and separately remains a live orphan veto).
  input wire input_offer_new,
  output wire input_ready,
  input wire [35:0] input_data,
  input wire [8:0] input_position,
  input wire input_last,
  input wire [74:0] input_metadata,
  input wire input_commit_authorized,
  output wire input_fault,
  output wire input_framing_fault_now,
  output wire output_valid,
  input wire output_ready,
  output wire [35:0] output_data,
  output wire [8:0] output_position,
  output wire output_last,
  output wire [74:0] output_metadata,
  input wire rearm_valid,
  input wire engine_reset_held,
  input wire producer_epoch_idle,
  input wire certificate_epoch_idle,
  input wire consumer_epoch_idle,
  output wire rearm_ready,
  output wire epoch_active,
  input wire [1:0] input_lease,
  output wire [1:0] current_lease,
  input wire certificate_valid,
  input wire certificate_offer_new,
  output wire certificate_ready,
  input wire [1:0] certificate_lease,
  input wire [74:0] certificate_metadata,
  input wire certificate_good,
  input wire lease_release_valid,
  output wire lease_release_ready,
  input wire [1:0] lease_release_tag,
  // Remaining raw publication vetoes, including vendor/orphan/reset/timeout.
  // A held valid offer stalled by ownership is not by itself an orphan event.
  input wire [7:0] live_faults,
  output wire [15:0] fault_reasons,
  output wire fault_token_valid,
  output wire [8:0] fault_token_position,
  output wire [1:0] fault_token_lease,
  output wire private_take, checked_seal, publish, lease_release,
  output wire sealed, published
);
  initial begin
    if (SEALED_PUBLICATION !== 0 && SEALED_PUBLICATION !== 1)
      $fatal(1, "SEALED_PUBLICATION must be zero or one");
  end
  generate if (!SEALED_PUBLICATION) begin : legacy
    starlink_pss_block_mailbox #(.METADATA_WIDTH(75), .EXPLICIT_COMMIT(1)) original (
      .input_clk(clk), .input_resetn(input_resetn),
      .input_valid(input_valid), .input_ready(input_ready),
      .input_data(input_data), .input_position(input_position), .input_last(input_last),
      .input_metadata(input_metadata), .input_commit_authorized(input_commit_authorized),
      .input_fault(input_fault), .input_framing_fault_now(input_framing_fault_now),
      .output_clk(clk), .output_resetn(output_resetn), .output_valid(output_valid),
      .output_ready(output_ready), .output_data(output_data),
      .output_position(output_position), .output_last(output_last),
      .output_metadata(output_metadata)
    );
    assign rearm_ready = 0;
    assign epoch_active = 0;
    assign current_lease = 0;
    assign certificate_ready = 0;
    assign lease_release_ready = 0;
    assign fault_reasons = {15'b0, input_fault};
    assign fault_token_valid = 0;
    assign fault_token_position = 0;
    assign fault_token_lease = 0;
    assign private_take = 0;
    assign checked_seal = 0;
    assign publish = 0;
    assign lease_release = 0;
    assign sealed = 0;
    assign published = 0;
  end else begin : staged
    wire common_resetn = input_resetn && output_resetn;
    (* ASYNC_REG = "TRUE" *) reg [1:0] reset_release;
    always @(posedge clk or negedge common_resetn)
      if (!common_resetn) reset_release <= 0;
      else reset_release <= {reset_release[0], 1'b1};
    wire running = common_resetn && reset_release[1];
    reg armed;
    reg [1:0] lease;
    reg full, seal_q, published_q, certificate_seen;
    reg [15:0] reasons;
    // Reused bank storage/cursors and same-clock version of original reader.
    (* ram_style = "block" *) reg [35:0] payload_memory [0:511];
    reg [74:0] metadata_in_hold, metadata_out_hold;
    reg [8:0] write_position;
    reg request_toggle, acknowledge_toggle;
    reg [1:0] request_sync, acknowledge_sync;
    reg reading, read_all_loaded, read_valid;
    reg [8:0] read_address, read_output_position;
    reg [35:0] read_payload;
    // Independent two-stage check evidence: all 25 leaves, five groups.
    reg [24:0] equal_leaves;
    reg [4:0] equal_groups;
    reg [1:0] check_valid, check_last, check_bad;
    reg [1:0] check_lease0, check_lease1;
    reg [8:0] check_position0, check_position1;
    reg fault_token_q;
    reg [8:0] fault_position_q;
    reg [1:0] fault_lease_q;
    wire [24:0] leaves_now;
    for (genvar leaf = 0; leaf < 25; leaf = leaf + 1) begin : compare_leaves
      assign leaves_now[leaf] = write_position == 0 ||
        input_metadata[3*leaf +: 3] === metadata_in_hold[3*leaf +: 3];
    end
    wire [4:0] groups_next;
    for (genvar group_index = 0; group_index < 5; group_index = group_index + 1) begin : compare_groups
      localparam integer BITS = group_index == 4 ? 1 : 6;
      assign groups_next[group_index] = &equal_leaves[6*group_index +: BITS];
    end
    wire clean = reasons == 0;
    wire live_clean = live_faults === 8'b0;
    wire pipe_empty = check_valid == 0;
    wire framing_bad = input_position !== write_position ||
      input_last !== (write_position == 511);
    wire first_metadata_known = (^input_metadata !== 1'bx);
    assign input_ready = running && armed && clean && !full && !published_q;
    assign private_take = input_valid === 1'b1 && input_offer_new === 1'b1 && input_ready;
    // Opt-in check evidence is delayed two clock edges and tagged below. This
    // compatibility output is NOT the old immediate full metadata predicate.
    // No current full75-bit comparator parallels the staged leaf/group path.
    assign input_framing_fault_now = pipeline_bad;
    assign certificate_ready = running && armed && clean && !certificate_seen &&
      (write_position != 0 || full) && !published_q;
    wire certificate_take = certificate_valid === 1'b1 && certificate_offer_new === 1'b1 && certificate_ready;
    wire certificate_bad = certificate_lease !== lease ||
      certificate_metadata !== metadata_in_hold || certificate_good !== 1'b1;
    wire [1:0] next_lease = lease + 1'b1;
    // Release attests ONLY old-lease drain. Exact-next-lease offers may remain
    // queued/held; they are not old references and must not deadlock release.
    wire old_input_drained = input_valid === 1'b0 || input_lease === next_lease;
    wire old_certificate_drained = certificate_valid === 1'b0 || certificate_lease === next_lease;
    assign lease_release_ready = running && armed && clean && live_clean && published_q &&
      acknowledge_sync[1] == request_toggle && !reading && !read_valid && pipe_empty &&
      certificate_seen && old_certificate_drained && old_input_drained;
    wire release_take = lease_release_valid === 1'b1 && lease_release_ready;
    wire release_bad = lease_release_tag !== lease;
    wire pipeline_bad = check_valid[1] &&
      (check_bad[1] || !(&equal_groups) || check_lease1 !== lease);
    wire closed_input_offer = armed && full && input_valid === 1'b1 &&
      input_offer_new !== 1'b0 && input_lease !== next_lease;
    wire duplicate_certificate_offer = armed && certificate_seen && certificate_valid === 1'b1 &&
      certificate_offer_new !== 1'b0 && certificate_lease !== next_lease;
    // Simulation fail-closed control contract; this does not claim that
    // synthesized binary hardware can sense metastability or four-state X/Z.
    wire uncertain_interface = armed &&
      ((input_valid !== 1'b0 && input_valid !== 1'b1) ||
       (certificate_valid !== 1'b0 && certificate_valid !== 1'b1) ||
       (input_valid === 1'b1 && input_offer_new !== 1'b0 && input_offer_new !== 1'b1) ||
       (certificate_valid === 1'b1 && certificate_offer_new !== 1'b0 && certificate_offer_new !== 1'b1));
    wire [15:0] errors_now;
    assign errors_now[0] = check_valid[1] && check_bad[1];
    assign errors_now[1] = check_valid[1] && check_lease1 !== lease;
    assign errors_now[2] = certificate_take && certificate_bad;
    assign errors_now[3] = check_valid[1] && !(&equal_groups);
    assign errors_now[4] = release_take && release_bad;
    assign errors_now[5] = closed_input_offer;
    assign errors_now[6] = duplicate_certificate_offer;
    assign errors_now[7] = uncertain_interface;
    for (genvar cause = 0; cause < 8; cause = cause + 1) begin : live_causes
      assign errors_now[cause+8] = armed && live_faults[cause] !== 1'b0;
    end
    wire local_current_clean = errors_now == 0;
    // SEALED/PUBLISHED means input_ready=0 and the validation pipe is drained;
    // certificate_seen forbids another certificate take. Only genuinely new
    // closed-lease offers and raw live events can fault these publication edges.
    // The wide certificate comparison and staged metadata checks do not feed
    // this fence. Open/checking states cannot publish, even before error Q arrives.
    wire publication_current_clean = live_clean && !closed_input_offer && !duplicate_certificate_offer && !uncertain_interface;
    assign checked_seal = running && armed && clean && full && !seal_q &&
      check_valid[1] && check_last[1] && !pipeline_bad && local_current_clean;
    assign publish = running && armed && clean && publication_current_clean &&
      seal_q && full && certificate_seen && pipe_empty && !published_q &&
      request_toggle == acknowledge_sync[1];
    assign lease_release = release_take && !release_bad && local_current_clean;
    assign rearm_ready = running && !armed && clean &&
      engine_reset_held === 1'b1 && producer_epoch_idle === 1'b1 &&
      certificate_epoch_idle === 1'b1 && consumer_epoch_idle === 1'b1 &&
      input_valid === 1'b0 && certificate_valid === 1'b0 && lease_release_valid === 1'b0 &&
      live_clean && pipe_empty && !read_valid && !reading;
    assign epoch_active = running && armed;
    assign current_lease = lease;
    assign fault_reasons = reasons;
    assign fault_token_valid = fault_token_q;
    assign fault_token_position = fault_position_q;
    assign fault_token_lease = fault_lease_q;
    assign input_fault = |reasons;
    assign sealed = running && seal_q;
    assign published = running && published_q;
    assign output_valid = running && armed && read_valid && clean && publication_current_clean;
    assign output_data = read_payload;
    assign output_position = read_output_position;
    assign output_last = read_output_position == 511;
    assign output_metadata = metadata_out_hold;
    wire output_accept = output_valid && output_ready === 1'b1;
    wire load_read = running && reading && !read_all_loaded &&
      (!read_valid || output_accept) && clean;

    always @(posedge clk or negedge common_resetn) begin
      if (!common_resetn) begin
        armed <= 0; lease <= 0; full <= 0; seal_q <= 0; published_q <= 0;
        certificate_seen <= 0; reasons <= 0; write_position <= 0;
        metadata_in_hold <= 0; metadata_out_hold <= 0;
        request_toggle <= 0; acknowledge_toggle <= 0;
        request_sync <= 0; acknowledge_sync <= 0;
        reading <= 0; read_all_loaded <= 0; read_valid <= 0;
        read_address <= 0; read_output_position <= 0;
        equal_leaves <= 0; equal_groups <= 0;
        check_valid <= 0; check_last <= 0; check_bad <= 0;
        check_lease0 <= 0; check_lease1 <= 0;
        check_position0 <= 0; check_position1 <= 0;
        fault_token_q <= 0; fault_position_q <= 0; fault_lease_q <= 0;
      end else if (running) begin
        reasons <= reasons | errors_now;
        if (rearm_valid === 1'b1 && rearm_ready) armed <= 1;
        request_sync <= {request_sync[0], request_toggle};
        acknowledge_sync <= {acknowledge_sync[0], acknowledge_toggle};
        check_valid <= {check_valid[0], private_take};
        check_last <= {check_last[0], private_take && input_last === 1'b1};
        check_bad <= {check_bad[0], private_take &&
          (framing_bad || !first_metadata_known)};
        if (private_take) begin
          equal_leaves <= leaves_now;
          check_lease0 <= input_lease;
          check_position0 <= input_position;
          if (write_position == 0) metadata_in_hold <= input_metadata;
          if (write_position == 511) full <= 1;
          else write_position <= write_position + 1'b1;
        end
        if (check_valid[0]) begin
          equal_groups <= groups_next;
          check_lease1 <= check_lease0;
          check_position1 <= check_position0;
        end
        if (pipeline_bad && !fault_token_q) begin
          fault_token_q <= 1;
          fault_position_q <= check_position1;
          fault_lease_q <= check_lease1;
        end
        if (certificate_take && !certificate_bad && local_current_clean)
          certificate_seen <= 1;
        if (checked_seal) seal_q <= 1;
        if (publish) begin
          request_toggle <= !request_toggle;
          published_q <= 1;
        end
        if (!reading && request_sync[1] != acknowledge_toggle && clean) begin
          reading <= 1;
          read_all_loaded <= 0;
          read_address <= 0;
          metadata_out_hold <= metadata_in_hold;
        end
        if (load_read) begin
          read_valid <= 1;
          read_output_position <= read_address;
          if (read_address == 511) read_all_loaded <= 1;
          else read_address <= read_address + 1'b1;
        end else if (output_accept) read_valid <= 0;
        if (output_accept && output_last) begin
          reading <= 0;
          acknowledge_toggle <= request_sync[1];
        end
        if (lease_release) begin
          lease <= lease + 1'b1;
          full <= 0; seal_q <= 0; published_q <= 0;
          certificate_seen <= 0; write_position <= 0;
        end
      end
    end
    // No RAM clear/reset and no extra payload bank. Private corrupt writes are
    // allowed; their reason capture and drained evidence prohibit publication.
    always @(posedge clk) begin
      if (private_take) payload_memory[write_position] <= input_data;
      if (load_read) read_payload <= payload_memory[read_address];
    end
  end endgenerate
endmodule
