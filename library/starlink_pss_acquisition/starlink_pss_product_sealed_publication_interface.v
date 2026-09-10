// SPDX-License-Identifier: GPL-2.0
// OFFLINE additive producer/product adapter. Default inert; no top binding.
// Fixed product70 encoding is zero-extended to the opaque d9c75-bit checker.
// Common epoch reset/peer-purge attestation is external; never use core reset.
`timescale 1ns/1ps
module starlink_pss_product_sealed_publication_interface #(
  parameter integer SEALED_PRODUCT_ADAPTER = 0,
  parameter integer SEPARATE_PRODUCT_SEAMS = 0
) (
  input wire clk, resetn, peer_resetn,
  input wire engine_reset_held, peer_epoch_idle, forward_guard_busy, forward_phase,
  input wire forward_job_accept,
  input wire [69:0] forward_descriptor,
  input wire forward_completion,
  input wire [4:0] forward_exponent,
  input wire product_valid,
  output wire product_ready,
  input wire sampled_product_ready,
  input wire [7:0] publication_faults,
  input wire [35:0] product_data,
  input wire [8:0] product_position,
  input wire product_last,
  input wire [69:0] product_metadata,
  output wire forward_handoff_valid,
  input wire forward_handoff_ready,
  input wire inverse_job_start, inverse_input_enable, core_ready, consumer_complete,
  output wire core_valid,
  output wire [35:0] core_data,
  output wire [8:0] core_position,
  output wire core_last,
  output wire [69:0] core_metadata,
  input wire [7:0] current_faults,
  output wire reusable, reservation, epoch_active,
  output wire product_take, checked_seal, publication, handoff, core_take, lease_release,
  output wire [1:0] current_lease,
  output wire [15:0] bank_reasons, reader_reasons,
  output wire [7:0] issuer_reasons,
  output wire fault,
  output wire producer_owned,
  output wire read_head_valid,
  output wire [74:0] read_head_metadata,
  output wire [1:0] read_head_lease,
  output wire handoff_owned,
  output wire handoff_capacity, handoff_fault_now,
  output wire [74:0] admitted_metadata,
  output wire [1:0] admitted_lease,
  output wire producer_verdict_fault_now, reader_validation_fault_now,
  output wire reader_token_fault_now, reader_offer_fault_now,
  output wire [15:0] reader_fault_events_now,
  output wire [7:0] issuer_fault_events_now
);
  initial if (SEALED_PRODUCT_ADAPTER !== 0 && SEALED_PRODUCT_ADAPTER !== 1)
    $fatal(1,"SEALED_PRODUCT_ADAPTER must be zero or one");
  initial if (SEPARATE_PRODUCT_SEAMS !== 0 && SEPARATE_PRODUCT_SEAMS !== 1)
    $fatal(1,"SEPARATE_PRODUCT_SEAMS must be zero or one");
  wire epoch_resetn = resetn && peer_resetn && SEALED_PRODUCT_ADAPTER;
  reg producer_reference, final_taken, completion_reference, certificate_consumed;
  reg published_reference, reader_reference, handoff_seen, consumer_started;
  reg [1:0] lease_reference;
  reg [74:0] expected_metadata;
  reg [7:0] reasons;
  wire bank_input_ready, certificate_ready, bank_release_ready, bank_input_fault;
  wire bank_valid, bank_ready, bank_last, bank_published;
  wire [35:0] bank_data;
  wire [8:0] bank_position;
  wire [74:0] bank_metadata;
  wire queue_admit_ready, queue_active, queue_prefetched, queue_final, queue_drained;
  wire queue_release_ready, queue_released;
  wire queue_validation_fault;
  wire [74:0] queue_metadata;
  wire queue_admit_valid = published_reference && !reader_reference;
  wire [1:0] bank_lease;
  wire any_reference = producer_reference || final_taken || completion_reference ||
    published_reference || reader_reference || handoff_seen || consumer_started;
  assign reusable = epoch_resetn && epoch_active && bank_input_ready &&
    queue_admit_ready && !any_reference && !fault;
  assign reservation = epoch_resetn && epoch_active && (reusable || any_reference);
  wire admission = forward_job_accept && reusable;
  wire invalid_admission = forward_job_accept &&
    (!reusable || forward_phase !== 1'b1 || forward_descriptor[69] !== 1'b0 ||
     forward_descriptor[4:0] !== 5'b0 || ^forward_descriptor === 1'bx);
  wire invalid_completion = forward_completion &&
    (!producer_reference || completion_reference || published_reference ||
     forward_phase !== 1'b1 || ^forward_exponent === 1'bx);
  wire [7:0] issuer_current;
  // Capacity is registered-state-derived; A is the caller's ACTUAL arithmetic
  // READY. Raw VALID still reaches the bank even when A=0 or unknown.
  wire sampled_ready = SEPARATE_PRODUCT_SEAMS ? sampled_product_ready : product_ready;
  // A may only reduce advertised capacity. A forged high cannot bypass C
  // while issuer-only reason Q has closed C but inner bank capacity is still1.
  wire sampled_offer = SEPARATE_PRODUCT_SEAMS ?
    (producer_reference && !final_taken && sampled_ready && product_ready) :
    (producer_reference && !final_taken && product_ready);
  wire sampled_ready_error = SEPARATE_PRODUCT_SEAMS && product_valid !== 1'b0 &&
    ((sampled_product_ready !== 1'b0 && sampled_product_ready !== 1'b1) ||
     (sampled_product_ready === 1'b1 && product_ready !== 1'b1));
  assign issuer_current[0] = invalid_admission;
  assign issuer_current[1] = invalid_completion;
  wire phase_error = (producer_reference && forward_phase !== 1'b1) ||
    (consumer_started && !consumer_complete && forward_phase !== 1'b0);
  // The concrete spectrum_product consumes final on READY and advances its
  // output stage. Unlike guard-held final VALID, a remaining product is NEW.
  wire closed_product = final_taken && product_valid !== 1'b0;
  wire unowned_product = product_valid === 1'b1 && !producer_reference && !final_taken;
  wire invalid_inverse_start = inverse_job_start &&
    (!handoff_seen || consumer_started || forward_phase !== 1'b0);
  wire extra_bank_offer = queue_final && bank_valid !== 1'b0;
  assign issuer_current[2] = phase_error;
  assign issuer_current[3] = closed_product;
  assign issuer_current[4] = unowned_product;
  assign issuer_current[5] = invalid_inverse_start;
  assign issuer_current[6] = extra_bank_offer;
  assign issuer_current[7] = any_reference &&
    ((product_valid !== 1'b0 && product_valid !== 1'b1) ||
     (forward_completion !== 1'b0 && forward_completion !== 1'b1) ||
     (product_valid !== 1'b0 && product_ready !== 1'b0 && product_ready !== 1'b1)) || sampled_ready_error;
  assign issuer_reasons = reasons;
  assign fault = |bank_reasons || |reader_reasons || |reasons;
  // D0/D1 and unknown completion classify qualified handshakes: feeding them
  // upstream would feed acceptance back into its own READY/current-fault cone.
  // Capture rejects and exact reason bits stay immediate; their upstream veto
  // is reasons Q. The real guard/product ordering obligation is tested apart
  // from deliberately forged standalone qualified pulses.
  wire raw_product_uncertain = any_reference &&
    ((product_valid !== 1'b0 && product_valid !== 1'b1) ||
     (product_valid !== 1'b0 && product_ready !== 1'b0 && product_ready !== 1'b1)) || sampled_ready_error;
  // Named scalar causes make the direction of each dependency explicit;
  // do not reconstruct these predicates from the aggregate diagnostic bus.
  wire issuer_bank_current = raw_product_uncertain || phase_error ||
    closed_product || unowned_product || invalid_inverse_start;
  wire issuer_reader_current = issuer_bank_current || extra_bank_offer;
  assign handoff_fault_now = current_faults !== 8'b0 || issuer_reader_current ||
    queue_validation_fault || producer_verdict_fault_now;
  wire direct_clean = !handoff_fault_now;
  assign producer_owned = epoch_resetn && producer_reference;
  assign admitted_metadata = expected_metadata;
  assign admitted_lease = lease_reference;
  assign read_head_metadata = queue_metadata;
  assign issuer_fault_events_now = issuer_current;
  assign reader_validation_fault_now = queue_validation_fault;
  assign handoff_owned = epoch_resetn && handoff_seen && published_reference &&
    reader_reference && direct_clean && !fault;
  // Capacity is NOT authorization. In ACK phase the real guard sees this
  // state/GOOD-only capacity and independently checks handoff_fault_now plus
  // its exact current idle faults before clearing ownership.
  assign handoff_capacity = epoch_resetn && epoch_active && published_reference &&
    reader_reference && completion_reference && queue_prefetched && !handoff_seen &&
    forward_phase && !fault;
  // Full original raw cause bits remain separately present; local summaries
  // share bit7 ONLY here, with complete issuer/reader/bank reason ports retained.
  wire [7:0] bank_live = current_faults |
    {(issuer_bank_current || |reasons || |reader_reasons),7'b0};
  wire [7:0] reader_live = current_faults |
    {(issuer_reader_current || |reasons || |bank_reasons),7'b0};
  // issuer6 observes bank_valid. It must not feed bank_live, which determines
  // that same bank_valid. It remains immediate at reader/ACK/release and in
  // its detailed reason register; bank summary sees that reason next cycle.
  wire certificate_valid = completion_reference && !certificate_consumed;
  wire certificate_take = certificate_valid && certificate_ready;
  wire producer_idle = !producer_reference && !product_valid;
  wire certificate_idle = !completion_reference && !forward_completion;
  wire consumer_idle = !reader_reference && !queue_active;
  wire rearm = engine_reset_held && peer_epoch_idle && !forward_guard_busy &&
    producer_idle && certificate_idle && consumer_idle && !any_reference;
  wire bank_release_valid = published_reference && handoff_seen && queue_drained &&
    !producer_reference && !completion_reference && direct_clean && !fault;
  assign product_ready = producer_reference && bank_input_ready && !fault;
  assign forward_handoff_valid = handoff_capacity && direct_clean;
  assign handoff = forward_handoff_valid && forward_handoff_ready;
  assign current_lease = bank_lease;
  assign core_metadata = queue_metadata[69:0];
  starlink_pss_epoch_sealed_publication_bank #(.SEALED_PUBLICATION(1),
    .PUBLICATION_ONLY_FAULTS(SEPARATE_PRODUCT_SEAMS)) bank (
    .clk(clk), .input_resetn(epoch_resetn), .output_resetn(epoch_resetn),
    // RAW offers remain observable even when READY is low or ownership closed.
    // Only private take uses the exact exported handshake. The issuer retains
    // independent closed/unowned/X observation; d9c remains byte-identical.
    .input_valid(product_valid), .input_offer_new(sampled_offer),
    .input_ready(bank_input_ready), .input_data(product_data), .input_position(product_position),
    .input_last(product_last), .input_metadata({5'b0,product_metadata}),
    .input_commit_authorized(1'b0), .input_fault(bank_input_fault), .input_framing_fault_now(producer_verdict_fault_now),
    .output_valid(bank_valid), .output_ready(bank_ready), .output_data(bank_data),
    .output_position(bank_position), .output_last(bank_last), .output_metadata(bank_metadata),
    .rearm_valid(rearm), .engine_reset_held(engine_reset_held),
    .producer_epoch_idle(producer_idle && peer_epoch_idle),
    .certificate_epoch_idle(certificate_idle && peer_epoch_idle),
    .consumer_epoch_idle(consumer_idle && peer_epoch_idle), .rearm_ready(), .epoch_active(epoch_active),
    .input_lease(lease_reference), .current_lease(bank_lease),
    .certificate_valid(certificate_valid), .certificate_offer_new(certificate_valid),
    .certificate_ready(certificate_ready), .certificate_lease(lease_reference),
    .certificate_metadata(expected_metadata), .certificate_good(completion_reference),
    .lease_release_valid(bank_release_valid), .lease_release_ready(bank_release_ready),
    .lease_release_tag(lease_reference), .live_faults(bank_live), .fault_reasons(bank_reasons),
    // Deliberately NOT returned to bank_live/reader_live/direct_clean. Caller
    // separately protects its actual ACK/result publication from these causes.
    .publication_faults(publication_faults),
    .fault_token_valid(), .fault_token_position(), .fault_token_lease(),
    .private_take(product_take), .checked_seal(checked_seal), .publish(publication),
    .lease_release(lease_release), .sealed(), .published(bank_published)
  );
  starlink_pss_checked_product_read_interface #(.CHECKED_PRODUCT_READ(1)) reader (
    .clk(clk), .resetn(epoch_resetn), .admit_valid(queue_admit_valid), .admit_ready(queue_admit_ready),
    .admit_lease(lease_reference), .admit_metadata(expected_metadata),
    .raw_valid(bank_valid && reader_reference), .raw_ready(bank_ready), .raw_data(bank_data),
    .raw_position(bank_position), .raw_last(bank_last), .raw_metadata(bank_metadata),
    .raw_lease(lease_reference), .core_enable(consumer_started && inverse_input_enable),
    .core_ready(core_ready), .core_valid(core_valid), .core_data(core_data),
    .core_position(core_position), .core_last(core_last), .core_metadata(queue_metadata),
    .consumer_complete(consumer_complete), .release_valid(lease_release), .release_lease(lease_reference),
    .release_ready(queue_release_ready), .released(queue_released), .live_faults(reader_live),
    .active(queue_active), .prefetched(queue_prefetched), .final_consumed(queue_final), .drained(queue_drained),
    .private_take(), .core_take(core_take), .validation_fault_now(queue_validation_fault), .fault_reasons(reader_reasons),
    .head_valid(read_head_valid), .head_lease(read_head_lease), .fault_events_now(reader_fault_events_now),
    .token_fault_now(reader_token_fault_now), .offer_fault_now(reader_offer_fault_now),
    .fault_token_valid(), .fault_token_position(), .fault_token_lease()
  );
  always @(posedge clk or negedge epoch_resetn) begin
    if (!epoch_resetn) begin
      producer_reference<=0; final_taken<=0; completion_reference<=0; certificate_consumed<=0;
      published_reference<=0; reader_reference<=0; handoff_seen<=0; consumer_started<=0;
      lease_reference<=0; expected_metadata<=0; reasons<=0;
    end else begin
      reasons<=reasons | issuer_current;
      if(admission && !invalid_admission && direct_clean) begin
        producer_reference<=1;lease_reference<=bank_lease;
        expected_metadata<={5'b0,1'b1,forward_descriptor[68:5],5'b0};
      end
      if(forward_completion && !invalid_completion) begin
        expected_metadata[4:0]<=forward_exponent;completion_reference<=1;
      end
      if(certificate_take) certificate_consumed<=1;
      if(product_take && product_last) begin final_taken<=1;producer_reference<=0;end
      if(publication) published_reference<=1;
      if(queue_admit_valid && queue_admit_ready) reader_reference<=1;
      if(handoff) begin handoff_seen<=1;completion_reference<=0;end
      if(inverse_job_start && !issuer_current[5]) consumer_started<=1;
      if(lease_release) begin
        final_taken<=0;certificate_consumed<=0;published_reference<=0;
        reader_reference<=0;handoff_seen<=0;consumer_started<=0;
      end
    end
  end
endmodule
