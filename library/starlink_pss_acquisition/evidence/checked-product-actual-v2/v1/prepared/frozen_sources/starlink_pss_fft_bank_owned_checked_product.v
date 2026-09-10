// SPDX-License-Identifier: GPL-2.0
// Experimental three-bank, one-core FFT/product/IFFT island. No receiver use.
// Actual banks: source CDC (slow->fast), private product (fast->fast), and
// inverse output CDC (fast->slow). No stored forward-result bank or copy.
// Forward ACK means an ACTUAL validated product bank has transferred ownership
// to the inverse scheduler; it does not mean that bank may be overwritten.
// Its own mailbox ACK still requires all 512 inverse input reads. Final inverse
// ACK still requires all 512 slow output reads before resetting the core.
`timescale 1ns/1ps
module starlink_pss_fft_bank_owned_checked_product #(
  parameter KERNEL_ROM_FILE = "upper_edge_pss_kernel_q17.mem",
  parameter integer REGISTERED_SCHEDULING = 0,
  parameter integer DISTRIBUTED_FAST_FAULT = 0,
  parameter integer PER_CAUSE_FAULT_CDC = 0,
  parameter integer PRIVATE_NEXT_START_SCRATCH = 0,
  parameter integer PRIVATE_ROM_READ_AHEAD = 0,
  parameter integer PRIVATE_BLOCK_METADATA_READ_AHEAD = 0,
  parameter integer PRODUCER_LOCAL_FINAL_FENCE = 0,
  parameter integer CHECKED_PRODUCT_BANK = 0
) (
  input wire clk, resetn, fft_clk, fft_resetn,
  input wire input_valid,
  output wire input_ready,
  input wire [35:0] input_data,
  input wire [8:0] input_position,
  input wire input_last,
  input wire [63:0] input_block_start,
  output wire output_valid,
  input wire output_ready,
  output wire [35:0] output_data,
  output wire [8:0] output_position,
  output wire output_last,
  output wire [74:0] output_metadata,
  output wire fault
);
  initial begin
    if (CHECKED_PRODUCT_BANK !== 0 && CHECKED_PRODUCT_BANK !== 1)
      $fatal(1, "CHECKED_PRODUCT_BANK must be zero or one");
    if (CHECKED_PRODUCT_BANK && (REGISTERED_SCHEDULING !== 1 ||
        DISTRIBUTED_FAST_FAULT !== 1 || PER_CAUSE_FAULT_CDC !== 1 ||
        PRIVATE_NEXT_START_SCRATCH !== 1 || PRIVATE_ROM_READ_AHEAD !== 1 ||
        PRIVATE_BLOCK_METADATA_READ_AHEAD !== 1 || PRODUCER_LOCAL_FINAL_FENCE !== 1))
      $fatal(1, "CHECKED_PRODUCT_BANK requires frozen P1 R/D/S/C/K/M/P settings");
    if (PRODUCER_LOCAL_FINAL_FENCE !== 0 && PRODUCER_LOCAL_FINAL_FENCE !== 1)
      $fatal(1, "PRODUCER_LOCAL_FINAL_FENCE must be zero or one");
    if (PRIVATE_ROM_READ_AHEAD !== 0 && PRIVATE_ROM_READ_AHEAD !== 1)
      $fatal(1, "PRIVATE_ROM_READ_AHEAD must be zero or one");
    if (PRIVATE_BLOCK_METADATA_READ_AHEAD !== 0 && PRIVATE_BLOCK_METADATA_READ_AHEAD !== 1)
      $fatal(1, "PRIVATE_BLOCK_METADATA_READ_AHEAD must be zero or one");
    if (DISTRIBUTED_FAST_FAULT !== 0 && DISTRIBUTED_FAST_FAULT !== 1)
      $fatal(1, "DISTRIBUTED_FAST_FAULT must be zero or one");
    if (PRIVATE_NEXT_START_SCRATCH !== 0 && PRIVATE_NEXT_START_SCRATCH !== 1)
      $fatal(1, "PRIVATE_NEXT_START_SCRATCH must be zero or one");
    if (PER_CAUSE_FAULT_CDC !== 0 && PER_CAUSE_FAULT_CDC !== 1)
      $fatal(1, "PER_CAUSE_FAULT_CDC must be zero or one");
    if (PER_CAUSE_FAULT_CDC && !DISTRIBUTED_FAST_FAULT)
      $fatal(1, "PER_CAUSE_FAULT_CDC requires DISTRIBUTED_FAST_FAULT");
  end
  (* ASYNC_REG = "TRUE" *) reg [1:0] slow_reset_fast, fast_reset_fast;
  (* ASYNC_REG = "TRUE" *) reg [1:0] slow_reset_slow, fast_reset_slow;
  always @(posedge fft_clk or negedge resetn)
    if (!resetn) slow_reset_fast <= 0; else slow_reset_fast <= {slow_reset_fast[0], 1'b1};
  always @(posedge fft_clk or negedge fft_resetn)
    if (!fft_resetn) fast_reset_fast <= 0; else fast_reset_fast <= {fast_reset_fast[0], 1'b1};
  always @(posedge clk or negedge resetn)
    if (!resetn) slow_reset_slow <= 0; else slow_reset_slow <= {slow_reset_slow[0], 1'b1};
  always @(posedge clk or negedge fft_resetn)
    if (!fft_resetn) fast_reset_slow <= 0; else fast_reset_slow <= {fast_reset_slow[0], 1'b1};
  wire fast_running = slow_reset_fast[1] && fast_reset_fast[1];
  wire slow_running = slow_reset_slow[1] && fast_reset_slow[1];
  // An actual slow edge must purge the source writer after EITHER raw reset.
  // Fast reset release alone cannot attest a paused remote writer is fresh.
  wire source_epoch_open;
  generate if (CHECKED_PRODUCT_BANK) begin : common_source_epoch
    reg slow_purge_seen;
    (* ASYNC_REG = "TRUE" *) reg [1:0] slow_purge_fast;
    wire raw_common_resetn = resetn && fft_resetn;
    always @(posedge clk or negedge raw_common_resetn)
      if (!raw_common_resetn) slow_purge_seen <= 0;
      else if (!slow_running) slow_purge_seen <= 1;
    always @(posedge fft_clk or negedge raw_common_resetn)
      if (!raw_common_resetn) slow_purge_fast <= 0;
      else if (!fast_running) slow_purge_fast <= 0;
      else slow_purge_fast <= {slow_purge_fast[0], slow_purge_seen};
    assign source_epoch_open = fast_running && slow_purge_fast[1];
  end else begin : original_source_epoch
    assign source_epoch_open = fast_running;
  end endgenerate
  wire source_ready, source_fault, source_valid, source_last, source_read_ready;
  wire [35:0] source_data;
  wire [8:0] source_position;
  wire [69:0] source_metadata;
  starlink_pss_block_mailbox #(.RESET_RELEASE_EXTERNAL(1)) source_bank (
    .input_clk(clk), .input_resetn(slow_running),
    .input_valid(input_valid && !fault), .input_ready(source_ready),
    .input_data(input_data), .input_position(input_position), .input_last(input_last),
    .input_metadata({1'b0, input_block_start, 5'b0}), .input_commit_authorized(1'b0),
    .input_fault(source_fault), .input_framing_fault_now(),
    .output_clk(fft_clk), .output_resetn(source_epoch_open),
    .output_valid(source_valid), .output_ready(source_read_ready),
    .output_data(source_data), .output_position(source_position), .output_last(source_last),
    .output_metadata(source_metadata)
  );
  (* ASYNC_REG = "TRUE" *) reg [1:0] source_fault_fast, fast_fault_slow;
  reg fast_fault;
  always @(posedge fft_clk)
    if (!source_epoch_open) source_fault_fast <= 0;
    else source_fault_fast <= {source_fault_fast[0], source_fault};
  // BEGIN PER_CAUSE_FAULT_CDC: independent sticky event levels, not a data bus.
  // Fast-domain quarantine/publication fences still consume fast_fault exactly
  // as before. Only its slow-domain observation is factored across the two
  // synchronization stages; both aggregate stage names remain observable.
  generate if (PER_CAUSE_FAULT_CDC && DISTRIBUTED_FAST_FAULT) begin : per_cause_fault_cdc
    wire [11:0] first_stage, second_stage;
    for (genvar cause_index = 0; cause_index < 12; cause_index = cause_index + 1) begin : causes
      (* ASYNC_REG = "TRUE" *) reg [1:0] cause_sync;
      always @(posedge clk)
        if (!slow_running) cause_sync <= 0;
        else cause_sync <= {cause_sync[0], distributed_fast_fault.cause_sticky[cause_index]};
      assign first_stage[cause_index] = cause_sync[0];
      assign second_stage[cause_index] = cause_sync[1];
    end
    always @* fast_fault_slow = {|second_stage, |first_stage};
  end else begin : aggregate_fault_cdc
  always @(posedge clk)
    if (!slow_running) fast_fault_slow <= 0;
    else fast_fault_slow <= {fast_fault_slow[0], fast_fault};
  end endgenerate
  // END PER_CAUSE_FAULT_CDC
  assign fault = source_fault || fast_fault_slow[1];
  assign input_ready = slow_running && source_ready && !fault;

  localparam [3:0] RESET0=0, RESET1=1, WAIT_BANK=2, INPUT_ADMIT=3,
    CONFIGURE=4, ENABLE_INPUT=5, RUN_JOB=6, ACK_DRAIN=7, QUARANTINE=8,
    VERIFY_LEASE=9, ARM_JOB=10;
  reg [3:0] state;
  reg core_release, input_job_start_private, next_inverse;
  // A fresh preflight fault on receipt consumption may advance PRIVATE state.
  // Its same-edge epoch/reason Q masks this emitted token before the checker
  // can sample a start. No raw wide comparison is in the token's control cone.
  wire input_job_start = input_job_start_private &&
    (!REGISTERED_SCHEDULING || !registered_quarantine) &&
    (!CHECKED_PRODUCT_BANK || !held_phase || product_start_binding);
  reg [69:0] engine_metadata;
  reg engine_input_reserved, engine_output_reserved, forward_committed;
  reg held_phase;
  reg [(CHECKED_PRODUCT_BANK ? 2 : 1)-1:0] held_lease;
  reg source_consume_generation, product_consume_generation;
  reg descriptor_certified, admission_receipt, completion_receipt;
  reg [69:0] expected_product_metadata;
  reg [5:0] preparation_age;
  (* keep = "true" *) reg [2:0] epoch_input_reasons;
  (* keep = "true" *) reg [5:0] epoch_preflight_reasons;
  wire core_aresetn = fast_running && core_release;
  wire config_valid = state == CONFIGURE && core_aresetn && !fast_fault;
  wire config_ready;
  wire engine_input_enable = state == RUN_JOB && core_aresetn && !fast_fault;
  wire job_ready, result_busy, result_commit, result_fault;
  wire product_bank_valid, product_bank_last, product_bank_read_ready;
  wire product_core_valid, product_head_owned_good, product_handoff_owned;
  wire product_handoff_state_owned, product_handoff_capacity, product_reservation;
  wire product_reader_token_fault;
  wire [74:0] product_head_metadata;
  wire [1:0] product_head_lease, product_origin_lease;
  wire product_bound_receipt, product_start_binding, product_binding_fault_now;
  wire [35:0] product_bank_data;
  wire [8:0] product_bank_position;
  wire [69:0] product_bank_metadata;
  wire selected_phase = REGISTERED_SCHEDULING && state != WAIT_BANK &&
    state != RESET0 && state != RESET1 ? held_phase : next_inverse;
  wire selected_valid = selected_phase ? product_bank_valid : source_valid;
  wire [35:0] selected_data = selected_phase ? product_bank_data : source_data;
  wire [8:0] selected_position = selected_phase ? product_bank_position : source_position;
  wire selected_last = selected_phase ? product_bank_last : source_last;
  wire [69:0] selected_metadata = selected_phase ? product_bank_metadata : source_metadata;
  // Discovery/preflight may select by scheduler state. Every open checker slot
  // instead owns the immutable admitted phase, including quarantine. Retain the
  // original next_inverse selection for default callers; no beat check changes.
  wire guard_phase = REGISTERED_SCHEDULING ? held_phase : next_inverse;
  wire guard_valid = guard_phase ?
    (CHECKED_PRODUCT_BANK ? product_core_valid : product_bank_valid) : source_valid;
  wire [35:0] guard_data = guard_phase ? product_bank_data : source_data;
  wire [8:0] guard_position = guard_phase ? product_bank_position : source_position;
  wire guard_last = guard_phase ? product_bank_last : source_last;
  wire [69:0] guard_metadata = guard_phase ? product_bank_metadata : source_metadata;
  wire [(CHECKED_PRODUCT_BANK ? 2 : 1)-1:0] selected_lease = selected_phase ?
    (CHECKED_PRODUCT_BANK ? product_head_lease : product_consume_generation) : source_consume_generation;
  wire preparing = state == VERIFY_LEASE || state == ARM_JOB;
  // VERIFY/ARM own the captured phase. Discovery remains state-selected, but
  // this current preflight tuple need not put scheduler state before equality.
  wire preflight_phase = REGISTERED_SCHEDULING ? held_phase : next_inverse;
  wire preflight_valid = preflight_phase ? product_bank_valid : source_valid;
  wire [35:0] preflight_data = preflight_phase ? product_bank_data : source_data;
  wire [8:0] preflight_position = preflight_phase ? product_bank_position : source_position;
  wire preflight_last = preflight_phase ? product_bank_last : source_last;
  wire [69:0] preflight_metadata = preflight_phase ? product_bank_metadata : source_metadata;
  wire [(CHECKED_PRODUCT_BANK ? 2 : 1)-1:0] preflight_lease = preflight_phase ?
    (CHECKED_PRODUCT_BANK ? product_head_lease : product_consume_generation) : source_consume_generation;
  wire [1:0] preflight_identity_equal;
  generate if (REGISTERED_SCHEDULING) begin : balanced_preflight
    for (genvar comparison = 0; comparison < 2; comparison = comparison + 1) begin : comparisons
      wire [69:0] lhs = comparison == 0 ? preflight_metadata : engine_metadata;
      wire [69:0] rhs = comparison == 0 ? engine_metadata : expected_product_metadata;
      (* keep = "true" *) wire [23:0] leaf_equal;
      (* keep = "true" *) wire [3:0] group_equal;
      for (genvar leaf = 0; leaf < 24; leaf = leaf + 1) begin : leaves
        localparam integer BITS = leaf == 23 ? 1 : 3;
        assign leaf_equal[leaf] = lhs[3*leaf +: BITS] == rhs[3*leaf +: BITS];
      end
      for (genvar group_index = 0; group_index < 4; group_index = group_index + 1) begin : groups
        assign group_equal[group_index] = &leaf_equal[6*group_index +: 6];
      end
      assign preflight_identity_equal[comparison] = &group_equal;
    end
  end else begin : legacy_preflight
    assign preflight_identity_equal[0] = preflight_metadata == engine_metadata;
    assign preflight_identity_equal[1] = engine_metadata == expected_product_metadata;
  end endgenerate
  wire descriptor_header_valid = engine_metadata[69] == held_phase &&
    (held_phase ? preflight_identity_equal[1] : engine_metadata[4:0] == 0);
  wire preparation_valid = preflight_valid && preflight_position == 0 && !preflight_last &&
    preflight_lease == held_lease && preflight_identity_equal[0] &&
    descriptor_header_valid && destination_reserved &&
    (!CHECKED_PRODUCT_BANK || !held_phase || product_start_binding);
  // Bit order: timeout, destination, descriptor/header, lease, framing, owner.
  wire [5:0] preflight_events_now = REGISTERED_SCHEDULING && fast_running && preparing ?
    {preparation_age == 63, !destination_reserved,
     (!preflight_identity_equal[0] || !descriptor_header_valid ||
      (CHECKED_PRODUCT_BANK && held_phase && !product_start_binding)),
     (preflight_lease != held_lease), (preflight_position != 0 || preflight_last),
     !preflight_valid} : 6'b0;
  wire preparation_fault_now = |preflight_events_now;
  wire job_valid = (REGISTERED_SCHEDULING ?
    state == ARM_JOB && descriptor_certified && !admission_receipt :
    state == WAIT_BANK && selected_valid) && !fast_fault;
  wire job_accept = job_valid && job_ready;
  wire transport_ready, checked_input_complete, certified_input_beat, certified_input_complete;
  wire input_fault_now, input_guard_fault, duplicate_start_fault_now;
  wire [2:0] input_fault_events_now;
  wire [47:0] core_input_data, core_output_data;
  wire core_input_valid, core_input_ready, core_input_last;
  wire core_output_valid, core_output_last;
  wire [23:0] core_output_user;
  wire [7:0] core_status_data;
  wire core_status_valid, event_frame, event_last_unexpected, event_last_missing, event_input_halt;
  assign source_read_ready = !selected_phase && transport_ready && engine_input_enable;
  assign product_bank_read_ready = selected_phase && transport_ready && engine_input_enable;
  starlink_pss_realtime_checked_product_input_guard #(.CHECK_INPUT_BLOCK_IDENTITY(1),
    .BALANCED_IDENTITY_EQ(REGISTERED_SCHEDULING),
    .CHECKED_PRODUCT_BINDING(CHECKED_PRODUCT_BANK)) input_guard (
    .clk(fft_clk), .resetn(core_aresetn), .job_start(input_job_start),
    .job_descriptor(engine_metadata), .input_enable(engine_input_enable),
    .checked_job_binding(product_start_binding), .checked_job_lease(product_origin_lease),
    .checked_token_good(product_head_owned_good && !product_reader_token_fault),
    .checked_token_lease(product_head_lease),
    .input_valid(guard_valid), .input_ready(), .input_transport_ready(transport_ready),
    .input_data(guard_data), .input_position(guard_position), .input_last(guard_last),
    .input_metadata(guard_metadata), .core_input_tdata(core_input_data),
    .core_input_tvalid(core_input_valid), .core_input_tready(core_input_ready),
    .core_input_tlast(core_input_last), .certified_input_beat(certified_input_beat),
    .certified_input_complete(certified_input_complete), .input_complete(checked_input_complete),
    .fault_now(input_fault_now), .duplicate_start_fault_now(duplicate_start_fault_now),
    .fault_events_now(input_fault_events_now),
    .protocol_fault(input_guard_fault), .fault_reasons()
  );

  wire return_valid, return_private_valid, return_commit_valid, return_last;
  wire forward_retirement_valid;
  wire [35:0] return_data;
  wire [8:0] return_position;
  wire [74:0] return_metadata;
  wire kernel_ready, kernel_fault, joined_valid, joined_ready, joined_last;
  wire [17:0] joined_i, joined_q, kernel_i, kernel_q;
  wire [8:0] joined_position;
  wire [4:0] joined_exponent;
  wire [63:0] joined_start;
  wire product_valid, product_last, product_overflow;
  wire [17:0] product_i, product_q;
  wire [8:0] product_position;
  wire [4:0] product_exponent;
  wire [63:0] product_start;
  wire product_bank_ready, product_bank_fault, product_bank_framing_fault_now;
  wire output_bank_ready, output_bank_fault, output_bank_framing_fault_now;
  wire vendor_fault_now = event_last_unexpected || event_last_missing || event_input_halt;
  wire forward_handoff_identity = product_bank_metadata ==
    {1'b1, engine_metadata[68:5], return_metadata[4:0]};
  // The return exponent register is immutable after the forward guard commit.
  // A bank claiming ownership with the wrong descriptor cannot ACK that guard.
  wire handoff_fault_now = !next_inverse && forward_committed && product_bank_valid &&
    (!forward_handoff_identity || product_bank_position != 0 || product_bank_last) ||
    (CHECKED_PRODUCT_BANK && product_binding_fault_now);
  wire external_fault_now = input_fault_now || input_guard_fault || source_fault_fast[1] ||
    vendor_fault_now || fast_fault || kernel_fault || product_overflow || product_bank_fault ||
    product_bank_framing_fault_now || handoff_fault_now;
  wire forward_handoff_ack = CHECKED_PRODUCT_BANK ?
    (product_bound_receipt && product_handoff_owned && !external_fault_now && !result_fault) :
    (forward_committed && product_bank_valid &&
    forward_handoff_identity && product_bank_position == 0 && !product_bank_last &&
    !external_fault_now && !result_fault);
  wire result_destination_ready = next_inverse ? output_bank_ready :
    (forward_committed ? (CHECKED_PRODUCT_BANK ? product_handoff_capacity : product_bank_valid) :
     (kernel_ready && product_bank_ready));
  // Raw ownership readiness is not the certified forward ACK. While the
  // forward token is set the guard is inactive: its unchanged idle/current
  // faults veto ACK retirement. The controller independently requires the
  // complete identity/position/TLAST/current-fault certificate below.
  wire destination_reserved = next_inverse ? output_bank_ready :
    (CHECKED_PRODUCT_BANK ? product_reservation : product_bank_ready);
  // input_complete is already a registered per-core-epoch certificate. While
  // true, framing/delivery are impossible but a current duplicate job_start
  // remains an immediate fault. This fence is exactly the original full fence.
  wire final_fence = checked_input_complete && !input_guard_fault && !duplicate_start_fault_now;
  // An occupied return also excludes forward_committed: final commit clears
  // active on the same edge that sets that token. The full handoff comparator
  // remains on publication/ACK/quarantine; it cannot fault an occupied return.
  wire completed_input_fault_now = duplicate_start_fault_now || input_guard_fault ||
    source_fault_fast[1] || vendor_fault_now || fast_fault || kernel_fault ||
    product_overflow || product_bank_fault || product_bank_framing_fault_now;
  wire product_guard_ack_event;
  starlink_pss_realtime_result_guard_observe #(.USE_COMPLETED_INPUT_FAULT(1),
    .USE_PREFLIGHT_REASON_ONLY(REGISTERED_SCHEDULING),
    .USE_FORWARD_RETIREMENT(REGISTERED_SCHEDULING)) result_guard (
    .clk(fft_clk), .resetn(fast_running), .job_valid(job_valid), .job_ready(job_ready),
    .job_descriptor(REGISTERED_SCHEDULING ? engine_metadata : selected_metadata),
    .input_bank_reserved(!REGISTERED_SCHEDULING && state == WAIT_BANK ? selected_valid : engine_input_reserved),
    .output_bank_reserved(!REGISTERED_SCHEDULING && state == WAIT_BANK ? destination_reserved : engine_output_reserved),
    .certified_input_beat(certified_input_beat), .certified_input_complete(certified_input_complete),
    .final_fence_certified(final_fence), .external_fault_now(external_fault_now),
    .phase_input_fault_now(1'b0), .core_event_frame_started(event_frame),
    .preflight_fault_evidence_now(preparation_fault_now),
    .completed_input_certified(checked_input_complete),
    .completed_input_fault_now(completed_input_fault_now),
    .core_output_tdata(core_output_data), .core_output_tuser(core_output_user),
    .core_output_tvalid(core_output_valid), .core_output_tlast(core_output_last),
    .core_status_tdata(core_status_data), .core_status_tvalid(core_status_valid),
    .mailbox_input_valid(return_valid), .mailbox_private_valid(return_private_valid),
    .mailbox_commit_valid(return_commit_valid), .mailbox_input_ready(result_destination_ready),
    .mailbox_input_fault(output_bank_fault || output_bank_framing_fault_now),
    .inverse_phase(next_inverse), .forward_mailbox_fault(output_bank_fault),
    .forward_retirement_valid(forward_retirement_valid),
    .validated_ack(product_guard_ack_event),
    .mailbox_input_data(return_data), .mailbox_input_position(return_position),
    .mailbox_input_last(return_last), .mailbox_input_metadata(return_metadata),
    .busy(result_busy), .commit_pulse(result_commit), .protocol_fault(result_fault), .fault_reasons()
  );
  // Nonfinal checked results may compute privately before independent status.
  // The final result is admitted ONLY on the original guard's qualified commit.
  starlink_pss_forward_kernel_join_read_ahead #(.KERNEL_ROM_FILE(KERNEL_ROM_FILE), .DATA_WIDTH(18),
    .PRIVATE_PAYLOAD_BUBBLES(REGISTERED_SCHEDULING),
    .BALANCED_BLOCK_IDENTITY_EQ(REGISTERED_SCHEDULING),
    .PRIVATE_NEXT_START_SCRATCH(PRIVATE_NEXT_START_SCRATCH),
    .PRIVATE_ROM_READ_AHEAD(PRIVATE_ROM_READ_AHEAD),
    .PRIVATE_BLOCK_METADATA_READ_AHEAD(PRIVATE_BLOCK_METADATA_READ_AHEAD)) joiner (
    .clk(fft_clk), .resetn(fast_running), .flush(1'b0),
    // Match the guard's exact retirement event, including a held final word.
    // An owned bank should remain ready, but a readiness fault/stall must never
    // let the joiner consume a word that the guard has not retired.
    .input_valid((REGISTERED_SCHEDULING ? forward_retirement_valid :
      (return_valid && !next_inverse)) && !fast_fault && product_bank_ready),
    .input_ready(kernel_ready),
    .input_i(return_data[17:0]), .input_q(return_data[35:18]),
    .input_bin_index(return_position), .input_block_exponent(return_metadata[4:0]),
    .input_last(return_last), .input_block_start_index(return_metadata[73:10]),
    .output_valid(joined_valid), .output_ready(joined_ready),
    .output_i(joined_i), .output_q(joined_q), .output_kernel_i(kernel_i), .output_kernel_q(kernel_q),
    .output_bin_index(joined_position), .output_block_exponent(joined_exponent),
    .output_last(joined_last), .output_block_start_index(joined_start),
    .accepted_pulse(), .emitted_pulse(), .input_block_complete_pulse(),
    .sequence_error_pulse(), .metadata_error_pulse(), .protocol_fault(kernel_fault)
  );
  starlink_pss_spectrum_product #(.DATA_WIDTH(18),
    .PRIVATE_PAYLOAD_BUBBLES(REGISTERED_SCHEDULING)) product (
    .clk(fft_clk), .resetn(fast_running), .flush(1'b0),
    .input_valid(joined_valid && !fast_fault), .input_ready(joined_ready),
    .input_i(joined_i), .input_q(joined_q), .kernel_i(kernel_i), .kernel_q(kernel_q),
    .input_bin_index(joined_position), .input_block_exponent(joined_exponent),
    .input_last(joined_last), .input_block_start_index(joined_start),
    .output_valid(product_valid), .output_ready(product_bank_ready && !fast_fault),
    .output_i(product_i), .output_q(product_q), .output_bin_index(product_position),
    .output_block_exponent(product_exponent), .output_last(product_last),
    .output_block_start_index(product_start), .output_overflow(product_overflow), .overflow_pulse()
  );
  wire product_commit_authorized = forward_committed && !external_fault_now && !result_fault;
  // Final producer writes follow the certified forward completion. Input
  // framing/delivery are closed, but duplicate start and all sticky/current
  // causes below remain live. Producer READY excludes product consumer VALID,
  // hence handoff mismatch cannot affect this sampled final-write edge.
  // Keep the original authorization/global reasons literal and observable;
  // this private predicate may differ outside the mailbox's final-write slot.
  wire producer_final_fault_now = duplicate_start_fault_now || input_guard_fault ||
    source_fault_fast[1] || vendor_fault_now || fast_fault || kernel_fault ||
    product_overflow || product_bank_fault || product_bank_framing_fault_now || result_fault;
  wire producer_final_seal_authorized = forward_committed && !producer_final_fault_now;
  // New branch owns only the product bank. Source/output mailboxes, FFT,
  // arithmetic, guard/publication bodies and scheduling order remain P1.
  generate if (!CHECKED_PRODUCT_BANK) begin : original_product_bank
    assign product_core_valid=0;
    assign product_head_owned_good=0;
    assign product_handoff_owned=0;
    assign product_handoff_state_owned=0;
    assign product_handoff_capacity=0;
    assign product_reservation=0;
    assign product_reader_token_fault=0;
    assign product_head_metadata=0;
    assign product_head_lease=0;
    assign product_origin_lease=0;
    assign product_bound_receipt=0;
    assign product_start_binding=0;
    assign product_binding_fault_now=0;
  starlink_pss_product_fence_mailbox #(.RESET_RELEASE_EXTERNAL(1), .EXPLICIT_COMMIT(1),
    .USE_PRODUCER_FINAL_FENCE(PRODUCER_LOCAL_FINAL_FENCE)) product_bank (
    .input_clk(fft_clk), .input_resetn(fast_running),
    .input_valid(product_valid && !fast_fault), .input_ready(product_bank_ready),
    .input_commit_authorized(product_commit_authorized),
    .input_final_seal_authorized(producer_final_seal_authorized),
    .input_data({product_q, product_i}), .input_position(product_position), .input_last(product_last),
    .input_metadata({1'b1, product_start, product_exponent}),
    .input_fault(product_bank_fault), .input_framing_fault_now(product_bank_framing_fault_now),
    .output_clk(fft_clk), .output_resetn(fast_running),
    .output_valid(product_bank_valid), .output_ready(product_bank_read_ready),
    .output_data(product_bank_data), .output_position(product_bank_position),
    .output_last(product_bank_last), .output_metadata(product_bank_metadata)
  );
  end else begin : checked_product_bank
    reg [1:0] origin_lease;
    reg origin_valid, bound_receipt;
    wire producer_owned, reusable, epoch_active, adapter_fault;
    wire advertised_ready, head_valid, producer_verdict, reader_validation, offer_fault;
    wire handoff_current_fault, handoff_valid, actual_handoff, lease_release;
    wire private_take, seal, publication, core_take;
    wire [1:0] bank_lease;
    wire [15:0] bank_reasons, reader_reasons;
    wire [7:0] issuer_reasons, issuer_events;
    wire independent_head_identity = origin_valid &&
      product_head_metadata === {5'b0, expected_product_metadata} &&
      product_head_lease === origin_lease;
    wire first_head = product_bank_position === 9'b0 && product_bank_last === 1'b0;
    wire ack_binding = head_valid && independent_head_identity && first_head && forward_handoff_identity;
    // Only Q/GOOD/tag evidence here: live head_valid includes duplicate-start
    // and must not feed a mask which creates that same job_start event.
    assign product_start_binding = bound_receipt && product_handoff_state_owned &&
      product_head_owned_good && independent_head_identity && first_head &&
      !product_reader_token_fault && !producer_verdict && held_phase === 1'b1 &&
      next_inverse === 1'b1 && engine_metadata === expected_product_metadata;
    assign product_binding_fault_now =
      (!next_inverse && forward_committed && head_valid && !ack_binding) ||
      (input_job_start_private && held_phase && !product_start_binding);
    assign product_origin_lease=origin_lease;
    assign product_bound_receipt=bound_receipt;
    assign product_bank_valid=head_valid;
    assign product_bank_ready=producer_owned ? advertised_ready : reusable;
    assign product_bank_fault=adapter_fault;
    assign product_bank_framing_fault_now=handoff_current_fault;
    // Exact guard ACK-clear edge, not a fake RAM-reader ACK or pulse-derived
    // scheduler capacity. Current raw events still pass the original guard.
    wire guard_ack = fast_running && forward_committed && !next_inverse &&
      product_guard_ack_event && ack_binding;
    // Shared transport receives only independent causes. Qualified D0/D1 and
    // input certificate/current delivery predicates never feed reader VALID.
    wire [7:0] independent_current =
      {1'b0, result_fault || output_bank_fault, fast_fault, product_overflow, kernel_fault,
       vendor_fault_now, source_fault_fast[1], input_guard_fault || duplicate_start_fault_now};
    wire closed_forward_events = forward_committed && !next_inverse &&
      (core_output_valid || core_status_valid || event_frame ||
       certified_input_beat || certified_input_complete);
    wire [7:0] publication_current = {closed_forward_events,6'b0,input_fault_now};
    starlink_pss_product_sealed_observe #(.SEALED_PRODUCT_ADAPTER(1), .SEPARATE_PRODUCT_SEAMS(1)) adapter (
      .clk(fft_clk),.resetn(fast_running),.peer_resetn(source_epoch_open),
      .engine_reset_held(!core_release),.peer_epoch_idle(source_epoch_open),
      .forward_guard_busy(result_busy),.forward_phase(!next_inverse),
      .forward_job_accept(job_accept && !next_inverse),.forward_descriptor(engine_metadata),
      .forward_completion(return_commit_valid && result_destination_ready && !next_inverse),
      .forward_exponent(return_metadata[4:0]),
      .product_valid(product_valid),.product_ready(advertised_ready),
      .sampled_product_ready(product_bank_ready && !fast_fault),
      .publication_faults(publication_current),.product_data({product_q,product_i}),
      .product_position(product_position),.product_last(product_last),
      .product_metadata({1'b1,product_start,product_exponent}),
      .forward_handoff_valid(handoff_valid),.forward_handoff_ready(guard_ack),
      .inverse_job_start(input_job_start && held_phase),
      .inverse_input_enable(engine_input_enable && guard_phase),.core_ready(product_bank_read_ready),
      .consumer_complete(checked_input_complete && held_phase),.core_valid(product_core_valid),
      .core_data(product_bank_data),.core_position(product_bank_position),.core_last(product_bank_last),
      .core_metadata(product_bank_metadata),.current_faults(independent_current),
      .reusable(reusable),.reservation(product_reservation),.epoch_active(epoch_active),
      .product_take(private_take),.checked_seal(seal),.publication(publication),
      .handoff(actual_handoff),.core_take(core_take),.lease_release(lease_release),.current_lease(bank_lease),
      .bank_reasons(bank_reasons),.reader_reasons(reader_reasons),.issuer_reasons(issuer_reasons),
      .fault(adapter_fault),.producer_owned(producer_owned),.read_head_valid(head_valid),
      .read_head_owned_good(product_head_owned_good),.read_head_metadata(product_head_metadata),
      .read_head_lease(product_head_lease),.handoff_owned(product_handoff_owned),
      .handoff_state_owned(product_handoff_state_owned),.handoff_capacity(product_handoff_capacity),
      .handoff_fault_now(handoff_current_fault),.admitted_metadata(),.admitted_lease(),
      .producer_verdict_fault_now(producer_verdict),.reader_validation_fault_now(reader_validation),
      .reader_token_fault_now(product_reader_token_fault),.reader_offer_fault_now(offer_fault),
      .reader_fault_events_now(),.issuer_fault_events_now(issuer_events)
    );
    always @(posedge fft_clk)begin
      if(!fast_running || !source_epoch_open)begin
        origin_lease<=0;origin_valid<=0;bound_receipt<=0;
      end else begin
        if(job_accept && !next_inverse)begin origin_lease<=bank_lease;origin_valid<=1;end
        if(actual_handoff && ack_binding)bound_receipt<=1;
        if(input_job_start && held_phase)bound_receipt<=0;
        if(lease_release || fast_fault || result_fault || adapter_fault)begin
          bound_receipt<=0;origin_valid<=0;
        end
      end
    end
  end endgenerate
  wire slow_output_valid;
  assign output_valid = slow_running && slow_output_valid && !fault;
  starlink_pss_block_mailbox #(.METADATA_WIDTH(75), .RESET_RELEASE_EXTERNAL(1),
      .EXPLICIT_COMMIT(1)) output_bank (
    .input_clk(fft_clk), .input_resetn(fast_running),
    .input_valid(return_private_valid && next_inverse),
    .input_commit_authorized(return_commit_valid && next_inverse), .input_ready(output_bank_ready),
    .input_data(return_data), .input_position(return_position), .input_last(return_last),
    .input_metadata(return_metadata), .input_fault(output_bank_fault),
    .input_framing_fault_now(output_bank_framing_fault_now),
    .output_clk(clk), .output_resetn(slow_running),
    .output_valid(slow_output_valid), .output_ready(output_ready && !fault),
    .output_data(output_data), .output_position(output_position), .output_last(output_last),
    .output_metadata(output_metadata)
  );
  wire any_fast_fault = external_fault_now || result_fault || output_bank_fault || preparation_fault_now;
  wire registered_quarantine = fast_fault || result_fault || (|epoch_input_reasons) ||
    (|epoch_preflight_reasons);
  wire completion_accept = state == ACK_DRAIN && !result_busy &&
    (next_inverse ? output_bank_ready : forward_handoff_ack) && !any_fast_fault &&
    !certified_input_beat && !certified_input_complete && !event_frame &&
    !core_status_valid && !core_output_valid;
  // All detailed input evidence belongs to the common epoch, not the private
  // core-reset epoch. The original checker and result reason banks still run.
  always @(posedge fft_clk) begin
    if (!fast_running) begin
      epoch_input_reasons <= 0;
      epoch_preflight_reasons <= 0;
      source_consume_generation <= 0; product_consume_generation <= 0;
    end else begin
      epoch_input_reasons <= epoch_input_reasons | input_fault_events_now;
      epoch_preflight_reasons <= epoch_preflight_reasons | preflight_events_now;
      if (source_valid && source_read_ready && source_last)
        source_consume_generation <= !source_consume_generation;
      if (product_bank_valid && product_bank_read_ready && product_bank_last)
        product_consume_generation <= !product_consume_generation;
    end
  end
  // BEGIN DISTRIBUTED_FAST_FAULT: the exact scalar recurrence, factored at Q.
  // Every non-self term of any_fast_fault is present. Raw publication fences
  // and detailed reasons remain untouched; this does NOT register their OR
  // one cycle later. Per-bit if semantics also retain the scalar's X behavior:
  // only a definitely asserted cause sets a sticky bit.
  generate if (DISTRIBUTED_FAST_FAULT) begin : distributed_fast_fault
    wire [11:0] causes_now = {preparation_fault_now, output_bank_fault,
      result_fault, handoff_fault_now, product_bank_framing_fault_now,
      product_bank_fault, product_overflow, kernel_fault, vendor_fault_now,
      source_fault_fast[1], input_guard_fault, input_fault_now};
    (* keep = "true" *) reg [11:0] cause_sticky;
    for (genvar cause_index = 0; cause_index < 12; cause_index = cause_index + 1) begin : causes
      always @(posedge fft_clk)
        if (!fast_running) cause_sticky[cause_index] <= 0;
        else if (causes_now[cause_index]) cause_sticky[cause_index] <= 1;
    end
    always @* fast_fault = |cause_sticky;
  end else begin : scalar_fast_fault
    always @(posedge fft_clk)
      if (!fast_running) fast_fault <= 0;
      else if (any_fast_fault) fast_fault <= 1;
  end endgenerate
  // END DISTRIBUTED_FAST_FAULT
  generate if (!REGISTERED_SCHEDULING) begin : original_scheduling
  always @(posedge fft_clk) begin
    if (!fast_running) begin
      state <= RESET0; core_release <= 0; input_job_start_private <= 0; next_inverse <= 0;
      engine_metadata <= 0; engine_input_reserved <= 0; engine_output_reserved <= 0;
      forward_committed <= 0;
    end else begin
      input_job_start_private <= 0;
      if (any_fast_fault) state <= QUARANTINE;
      else begin
        if (certified_input_complete) engine_input_reserved <= 0;
        if (return_commit_valid && result_destination_ready && !next_inverse)
          forward_committed <= 1;
        case (state)
          RESET0: begin core_release <= 0; state <= RESET1; end
          RESET1: begin core_release <= 0; state <= WAIT_BANK; end
          WAIT_BANK: if (job_accept) begin
            engine_metadata <= selected_metadata;
            engine_input_reserved <= 1; engine_output_reserved <= 1;
            core_release <= 1; input_job_start_private <= 1; state <= INPUT_ADMIT;
            // Product ownership survives clearing this completed-forward token.
            forward_committed <= 0;
          end
          INPUT_ADMIT: state <= CONFIGURE;
          CONFIGURE: if (config_valid && config_ready) state <= ENABLE_INPUT;
          ENABLE_INPUT: state <= RUN_JOB;
          RUN_JOB: if (result_commit) state <= ACK_DRAIN;
          ACK_DRAIN: if (!result_busy &&
              (next_inverse ? output_bank_ready : forward_handoff_ack)) begin
            engine_output_reserved <= 0; core_release <= 0;
            next_inverse <= !next_inverse; state <= RESET0;
          end
          QUARANTINE: state <= QUARANTINE;
          default: state <= QUARANTINE;
        endcase
      end
    end
  end
  end else begin : registered_scheduling
    // Wide comparisons terminate only at certificates/reasons. The private
    // scheduler consumes registered receipts and registered epoch quarantine.
    // A fault-edge private advance is not publication or a bank release.
    always @(posedge fft_clk) begin
      if (!fast_running) begin
        state <= RESET0; core_release <= 0; input_job_start_private <= 0; next_inverse <= 0;
        engine_metadata <= 0; engine_input_reserved <= 0; engine_output_reserved <= 0;
        forward_committed <= 0; held_phase <= 0; held_lease <= 0;
        descriptor_certified <= 0; admission_receipt <= 0; completion_receipt <= 0;
        expected_product_metadata <= 0; preparation_age <= 0;
      end else begin
        input_job_start_private <= 0;
        admission_receipt <= job_accept;
        completion_receipt <= completion_accept;
        if (preparing) preparation_age <= preparation_age + 1'b1;
        else preparation_age <= 0;
        if (state == VERIFY_LEASE)
          descriptor_certified <= preparation_valid && !any_fast_fault;
        // Private expected descriptor capture does not authorize the bank.
        if (return_private_valid && !next_inverse && return_last)
          expected_product_metadata <= {1'b1, engine_metadata[68:5], return_metadata[4:0]};
        if (certified_input_complete) engine_input_reserved <= 0;
        if (return_commit_valid && result_destination_ready && !next_inverse)
          forward_committed <= 1;
        if (registered_quarantine) begin
          state <= QUARANTINE; descriptor_certified <= 0;
        end else case (state)
          RESET0: begin core_release <= 0; state <= RESET1; end
          RESET1: begin core_release <= 0; state <= WAIT_BANK; end
          WAIT_BANK: if (selected_valid && destination_reserved) begin
            engine_metadata <= selected_metadata;
            held_phase <= next_inverse; held_lease <= selected_lease;
            engine_input_reserved <= 1; engine_output_reserved <= 1;
            descriptor_certified <= 0; state <= VERIFY_LEASE;
          end
          VERIFY_LEASE: state <= ARM_JOB;
          ARM_JOB: if (admission_receipt) begin
            core_release <= 1; input_job_start_private <= 1; state <= INPUT_ADMIT;
            forward_committed <= 0; descriptor_certified <= 0;
          end
          INPUT_ADMIT: state <= CONFIGURE;
          CONFIGURE: if (config_ready) state <= ENABLE_INPUT;
          ENABLE_INPUT: state <= RUN_JOB;
          RUN_JOB: if (result_commit) state <= ACK_DRAIN;
          ACK_DRAIN: if (completion_receipt) begin
            engine_output_reserved <= 0; core_release <= 0;
            next_inverse <= !next_inverse; state <= RESET0;
          end
          QUARANTINE: state <= QUARANTINE;
          default: state <= QUARANTINE;
        endcase
      end
    end
  end endgenerate
  starlink_pss_fft512_bfp18_rt_candidate shared_xfft (
    .aclk(fft_clk), .aresetn(core_aresetn),
    .s_axis_config_tdata({7'b0, !engine_metadata[69]}),
    .s_axis_config_tvalid(config_valid), .s_axis_config_tready(config_ready),
    .s_axis_data_tdata(core_input_data), .s_axis_data_tvalid(core_input_valid),
    .s_axis_data_tready(core_input_ready), .s_axis_data_tlast(core_input_last),
    .m_axis_data_tdata(core_output_data), .m_axis_data_tuser(core_output_user),
    .m_axis_data_tvalid(core_output_valid), .m_axis_data_tlast(core_output_last),
    .m_axis_status_tdata(core_status_data), .m_axis_status_tvalid(core_status_valid),
    .event_frame_started(event_frame), .event_tlast_unexpected(event_last_unexpected),
    .event_tlast_missing(event_last_missing), .event_data_in_channel_halt(event_input_halt)
  );
endmodule
