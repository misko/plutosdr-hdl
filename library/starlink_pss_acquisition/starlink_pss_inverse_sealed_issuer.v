// SPDX-License-Identifier: GPL-2.0
// OFFLINE inverse-only adapter. The unchanged result guard owns the return
// slot/status. The new bank owns payload after one private take per token.
// This adapter owns references until actual guard publication and reader ACK.
// No local/core reset may clear these references: use the common epoch only.
`timescale 1ns/1ps
module starlink_pss_inverse_sealed_issuer (
  input wire input_clk, input_resetn, output_clk, output_resetn,
  // Already-qualified per-domain common reset releases, each including both
  // raw resets. Never connect per-transform core_aresetn to these resets.
  input wire core_reset_held, inverse_phase, guard_busy,
  input wire inverse_job_accept,
  input wire guard_private_valid, guard_commit_valid,
  input wire [35:0] guard_data,
  input wire [8:0] guard_position,
  input wire guard_last,
  input wire [74:0] guard_metadata,
  input wire core_output_event, external_fault_now,
  input wire output_fault,
  output wire guard_destination_ready,
  output wire reusable, reservation, epoch_active,
  output wire input_fault, input_framing_fault_now,
  output wire output_valid,
  input wire output_ready,
  output wire [35:0] output_data,
  output wire [8:0] output_position,
  output wire output_last,
  output wire [74:0] output_metadata,
  output wire private_take, certificate_take, publication, reader_ack, lease_release,
  output wire [15:0] fault_reasons
);
  // Nine added logical state bits. The bank's CDC/check/ownership state is
  // separate. These are declaration counts, not a mapped resource estimate.
  reg producer_reference, final_taken;
  reg certificate_reference, certificate_consumed;
  reg published_reference, reader_reference;
  reg [1:0] lease_reference;
  reg bad_admission_q;
  wire bank_input_ready, bank_certificate_ready, bank_release_ready;
  wire bank_reader_idle, bank_published;
  wire [1:0] bank_lease;
  wire bank_certificate_valid = certificate_reference && !certificate_consumed;
  assign certificate_take = bank_certificate_valid && bank_certificate_ready;
  // Capture is not publication authority by itself. The ORIGINAL held final
  // certificate must remain live through the actual publication edge, so its
  // own current watchdog/event/fence veto still takes effect immediately.
  // Normal loss AFTER publication is expected and must not quarantine ACK.
  wire certificate_lost = certificate_reference && !published_reference &&
    guard_commit_valid !== 1'b1;
  wire raw_orphan = final_taken && core_output_event !== 1'b0;
  wire phase_lost = (producer_reference || certificate_reference ||
    published_reference || reader_reference) && inverse_phase !== 1'b1;
  wire unowned_offer = inverse_phase && !producer_reference && !published_reference &&
    (guard_private_valid !== 1'b0 || guard_commit_valid !== 1'b0);
  wire bad_admission = inverse_job_accept && (!reusable || inverse_phase !== 1'b1);
  // The unchanged guard cannot admit while active/awaiting ACK. Diagnose an
  // invalid offered admission after one edge; never feed job_ready back into
  // its own publication/READY cone. Actual raw publication vetoes stay direct.
  wire [7:0] live_faults = {2'b0, bad_admission_q, unowned_offer, phase_lost, raw_orphan,
    certificate_lost, external_fault_now};
  // No certificate_lost -> guard mailbox_fault combinational feedback:
  // the bank captures this cause in its reason Q. Its live veto remains
  // direct at publication. Only the separate pipelined framing check is now.
  wire producer_idle = !producer_reference && !guard_private_valid && !guard_busy;
  wire certificate_idle = !certificate_reference && !guard_commit_valid && !guard_busy;
  wire consumer_idle = !reader_reference && bank_reader_idle;
  wire rearm = core_reset_held && producer_idle && certificate_idle && consumer_idle;
  wire release_valid = published_reference && !producer_reference &&
    !certificate_reference && !reader_reference && !guard_busy;
  // Admission/reuse is NOT the guard's overloaded mailbox READY.
  assign reusable = epoch_active && bank_input_ready && !producer_reference &&
    !final_taken && !certificate_reference && !certificate_consumed &&
    !published_reference && !reader_reference;
  // Admission consumes free capacity but retains owned reservation through
  // ARM_JOB's registered receipt. Reusable is not that preflight premise.
  assign reservation = epoch_active && (reusable || producer_reference ||
    certificate_reference || published_reference || reader_reference);
  // Idle/nonfinal: actual transport capacity. Held final: bank publication.
  // Awaiting ACK: actual synchronized final read, not private consumption or
  // a certificate receipt. The unchanged guard independently gates idle faults.
  assign guard_destination_ready = published_reference ? reader_ack :
    ((guard_private_valid && guard_last) ? publication : bank_input_ready);

  starlink_pss_epoch_sealed_bank_cdc #(.SEALED_PUBLICATION(1)) bank (
    .input_clk(input_clk), .input_resetn(input_resetn),
    .output_clk(output_clk), .output_resetn(output_resetn), .output_fault(output_fault),
    .input_valid(guard_private_valid && inverse_phase && producer_reference), .input_offer_new(!final_taken),
    .input_ready(bank_input_ready), .input_data(guard_data),
    .input_position(guard_position), .input_last(guard_last), .input_metadata(guard_metadata),
    .input_commit_authorized(1'b0), .input_fault(input_fault),
    .input_framing_fault_now(input_framing_fault_now),
    .output_valid(output_valid), .output_ready(output_ready), .output_data(output_data),
    .output_position(output_position), .output_last(output_last), .output_metadata(output_metadata),
    .rearm_valid(rearm), .engine_reset_held(core_reset_held),
    .producer_epoch_idle(producer_idle), .certificate_epoch_idle(certificate_idle),
    .consumer_epoch_idle(consumer_idle), .rearm_ready(), .epoch_active(epoch_active),
    .input_lease(lease_reference), .current_lease(bank_lease),
    .certificate_valid(bank_certificate_valid), .certificate_offer_new(bank_certificate_valid),
    .certificate_ready(bank_certificate_ready), .certificate_lease(lease_reference),
    .certificate_metadata(guard_metadata), .certificate_good(guard_commit_valid),
    .lease_release_valid(release_valid), .lease_release_ready(bank_release_ready),
    .lease_release_tag(lease_reference), .live_faults(live_faults),
    .fault_reasons(fault_reasons), .fault_token_valid(), .fault_token_position(), .fault_token_lease(),
    .private_take(private_take), .checked_seal(), .publish(publication), .lease_release(lease_release),
    .sealed(), .published(bank_published),
    .read_acknowledged(reader_ack), .reader_epoch_idle(bank_reader_idle)
  );
  always @(posedge input_clk or negedge input_resetn) begin
    if (!input_resetn) begin
      producer_reference <= 0; final_taken <= 0;
      certificate_reference <= 0; certificate_consumed <= 0;
      published_reference <= 0; reader_reference <= 0; lease_reference <= 0;
      bad_admission_q <= 0;
    end else begin
      bad_admission_q <= bad_admission_q || bad_admission;
      // Lease binding belongs to actual inverse JOB ADMISSION, before any
      // return offer. Never self-tag arriving data with today's bank lease.
      if (inverse_job_accept && reusable) begin
        producer_reference <= 1;
        lease_reference <= bank_lease;
      end
      if (private_take) begin
        if (guard_last) final_taken <= 1;
      end
      if (producer_reference && inverse_phase && guard_commit_valid && !certificate_reference && !published_reference)
        certificate_reference <= 1;
      if (certificate_take) certificate_consumed <= 1;
      if (publication) begin
        published_reference <= 1; reader_reference <= 1;
        // Publication also performs the original guard's final handshake.
        producer_reference <= 0; certificate_reference <= 0;
      end
      if (reader_ack) reader_reference <= 0;
      if (lease_release) begin
        final_taken <= 0; certificate_consumed <= 0;
        published_reference <= 0;
      end
    end
  end
endmodule
