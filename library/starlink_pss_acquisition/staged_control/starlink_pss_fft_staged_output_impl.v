// SPDX-License-Identifier: GPL-2.0
// Experimental three-bank, one-core FFT/product/IFFT island. No receiver use.
// Actual banks: source CDC (slow->fast), private product (fast->fast), and
// inverse output CDC (fast->slow). No stored forward-result bank or copy.
// Forward ACK means an ACTUAL validated product bank has transferred ownership
// to the inverse scheduler; it does not mean that bank may be overwritten.
// Its own mailbox ACK still requires all 512 inverse input reads. Final inverse
// ACK still requires all 512 slow output reads before output-bank reuse.
// Staged inverse-output ownership candidate; not a receiver runtime path.
// Forward path and all FFT numerical/status/input validators are retained.
// Cutover consumes registered ownership receipts; forward arithmetic is unchanged.
`timescale 1ns/1ps
`default_nettype none
module starlink_pss_fft_staged_output_impl #(
  parameter KERNEL_ROM_FILE = "upper_edge_pss_kernel_q17.mem",
  parameter integer REGISTERED_SCHEDULING = 0,
  parameter integer BOUNDARY_ROUND_SAT = 0,
  parameter integer REGISTER_OPERANDS = 0,
  parameter integer LOCAL_FIRST_ADMISSION = 0,
  parameter integer PRIVATE_DESCRIPTOR_OFFER = 0,
  parameter integer CLOSED_INPUT_CUTOVER = 0,
  parameter integer INPUT_OFFER_FAULT_SUMMARY = 0,
  parameter integer CONTEXTUAL_DESTINATION_SUMMARY = 0
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
    if (CONTEXTUAL_DESTINATION_SUMMARY !== 0 && CONTEXTUAL_DESTINATION_SUMMARY !== 1)
      $fatal(1, "contextual destination summary mode must be known zero or one");
    if (INPUT_OFFER_FAULT_SUMMARY !== 0 && INPUT_OFFER_FAULT_SUMMARY !== 1)
      $fatal(1, "input-offer summary mode must be known zero or one");
    if (CLOSED_INPUT_CUTOVER !== 0 && CLOSED_INPUT_CUTOVER !== 1)
      $fatal(1, "closed-input cutover mode must be known zero or one");
    if (PRIVATE_DESCRIPTOR_OFFER !== 0 && PRIVATE_DESCRIPTOR_OFFER !== 1)
      $fatal(1, "private descriptor mode must be known zero or one");
    if (REGISTERED_SCHEDULING !== 1 || BOUNDARY_ROUND_SAT !== 1 ||
        REGISTER_OPERANDS !== 1 || LOCAL_FIRST_ADMISSION !== 1)
      $fatal(1, "retained implementation requires exact R1/B1/O1/L1");
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
  wire outer_fast_running = slow_reset_fast[1] && fast_reset_fast[1];
  wire outer_slow_running = slow_reset_slow[1] && fast_reset_slow[1];
  wire fast_running, slow_running;
  wire source_writer_idle, source_reader_idle, product_writer_idle, product_reader_idle;
  wire reader_descriptor_idle;
  wire output_writer_idle, output_reader_idle, output_request, output_ack_sync;
  starlink_pss_retained_epoch_barrier epoch_barrier (
    .slow_clk(clk), .fast_clk(fft_clk), .resetn(resetn), .fft_resetn(fft_resetn),
    .outer_slow_running(outer_slow_running), .outer_fast_running(outer_fast_running),
    .slow_mailboxes_reset_idle(source_writer_idle && output_reader_idle && reader_descriptor_idle),
    .fast_mailboxes_reset_idle(source_reader_idle && product_writer_idle && product_reader_idle && output_writer_idle),
    .slow_running(slow_running), .fast_running(fast_running)
  );
  wire source_ready, source_fault, source_valid, source_last, source_read_ready;
  wire [35:0] source_data;
  wire [8:0] source_position;
  wire [69:0] source_metadata;
  starlink_pss_mailbox_owner_view #(.RESET_RELEASE_EXTERNAL(1)) source_bank (
    .input_clk(clk), .input_resetn(slow_running),
    .input_valid(input_valid && !fault), .input_ready(source_ready),
    .input_data(input_data), .input_position(input_position), .input_last(input_last),
    .input_metadata({1'b0, input_block_start, 5'b0}), .input_commit_authorized(1'b0),
    .input_fault(source_fault), .input_framing_fault_now(),
    .output_clk(fft_clk), .output_resetn(fast_running),
    .output_valid(source_valid), .output_ready(source_read_ready),
    .output_data(source_data), .output_position(source_position), .output_last(source_last),
    .output_metadata(source_metadata), .owner_request(), .owner_ack_sync(),
    .writer_reset_idle(source_writer_idle), .reader_reset_idle(source_reader_idle)
  );
  (* ASYNC_REG = "TRUE" *) reg [1:0] source_fault_fast, lookup_fault_fast, fast_fault_slow;
  reg fast_fault;
  reg slow_lookup_fault;
  reg [1:0] reader_descriptor_phase;
  localparam [1:0] RD_EMPTY=0, RD_CHECK=1, RD_VALID=2, RD_FAULT=3;
  wire slow_metadata_valid = reader_descriptor_phase==RD_VALID;
  reg [74:0] slow_output_metadata;
  reg [31:0] reader_descriptor_tag;
  wire slow_faults_fast = source_fault_fast[1] || lookup_fault_fast[1];
  always @(posedge fft_clk)
    if (!fast_running) source_fault_fast <= 0;
    else source_fault_fast <= {source_fault_fast[0], source_fault};
  always @(posedge fft_clk)
    if (!fast_running) lookup_fault_fast <= 0;
    else lookup_fault_fast <= {lookup_fault_fast[0], slow_lookup_fault};
  always @(posedge clk)
    if (!slow_running) fast_fault_slow <= 0;
    else fast_fault_slow <= {fast_fault_slow[0], fast_fault};
  assign fault = source_fault || slow_lookup_fault || fast_fault_slow[1];
  assign input_ready = slow_running && source_ready && !fault;

  localparam [3:0] RESET0=0, RESET1=1, WAIT_BANK=2, INPUT_ADMIT=3,
    CONFIGURE=4, ENABLE_INPUT=5, RUN_JOB=6, ACK_DRAIN=7, QUARANTINE=8,
    VERIFY_LEASE=9, ARM_JOB=10;
  reg [3:0] state;
  localparam integer CERTIFIED_ADMISSION = REGISTERED_SCHEDULING &&
    INPUT_OFFER_FAULT_SUMMARY && CONTEXTUAL_DESTINATION_SUMMARY;
  reg core_release, input_job_start_private, next_inverse;
  wire registered_quarantine, destination_reserved, inverse_guard_ready, slow_output_valid;
  reg inverse_descriptor_live, inverse_allocation_pending;
  // A fresh preflight fault on receipt consumption may advance PRIVATE state.
  // Its same-edge epoch/reason Q masks this emitted token before the checker
  // can sample a start. No raw wide comparison is in the token's control cone.
  wire input_job_start = input_job_start_private &&
    (!REGISTERED_SCHEDULING || !registered_quarantine);
  reg [69:0] engine_metadata;
  reg engine_input_reserved, engine_output_reserved, forward_committed;
  reg held_phase, held_lease;
  reg source_consume_generation, product_consume_generation;
  reg descriptor_certified, admission_receipt, completion_receipt;
  reg [69:0] expected_product_metadata;
  reg [5:0] preparation_age;
  (* keep = "true" *) reg [2:0] epoch_input_reasons;
  (* keep = "true" *) reg [5:0] epoch_preflight_reasons;
  wire core_aresetn = fast_running && core_release;
  wire cutover_admission_allowed, cutover_admission_capacity, cutover_configuration_allowed, cutover_fault_now, routed_inverse;
  wire [7:0] cutover_reasons, retained_reasons;
  wire cutover_closed_input_fault_now;
  wire retained_reusable, retained_reserved, retained_fault_now;
  reg retained_published;
  wire retained_reserved_known;
  reg producer_transfer_receipt;
  wire reader_release;
  wire completion_accept;
  wire admission_permit;
  wire forward_fault_now, inverse_fault_now, common_current_fault;
  wire config_valid = state == CONFIGURE && core_aresetn && !fast_fault && cutover_configuration_allowed;
  wire config_ready;
  wire engine_input_enable = state == RUN_JOB && core_aresetn && !fast_fault;
  wire job_ready, result_busy, result_commit, result_fault;
  wire product_bank_valid, product_bank_last, product_bank_read_ready;
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
  wire guard_valid = guard_phase ? product_bank_valid : source_valid;
  wire [35:0] guard_data = guard_phase ? product_bank_data : source_data;
  wire [8:0] guard_position = guard_phase ? product_bank_position : source_position;
  wire guard_last = guard_phase ? product_bank_last : source_last;
  wire [69:0] guard_metadata = guard_phase ? product_bank_metadata : source_metadata;
  wire selected_lease = selected_phase ? product_consume_generation : source_consume_generation;
  wire preparing = state == VERIFY_LEASE || state == ARM_JOB;
  // VERIFY/ARM own the captured phase. Discovery remains state-selected, but
  // this current preflight tuple need not put scheduler state before equality.
  wire preflight_phase = REGISTERED_SCHEDULING ? held_phase : next_inverse;
  wire preflight_valid = preflight_phase ? product_bank_valid : source_valid;
  wire [35:0] preflight_data = preflight_phase ? product_bank_data : source_data;
  wire [8:0] preflight_position = preflight_phase ? product_bank_position : source_position;
  wire preflight_last = preflight_phase ? product_bank_last : source_last;
  wire [69:0] preflight_metadata = preflight_phase ? product_bank_metadata : source_metadata;
  wire preflight_lease = preflight_phase ? product_consume_generation : source_consume_generation;
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
    descriptor_header_valid && destination_reserved;
  // Bit order: timeout, destination, descriptor/header, lease, framing, owner.
  wire [5:0] preflight_events_now = REGISTERED_SCHEDULING && fast_running && preparing ?
    {preparation_age == 63, !destination_reserved,
     (!preflight_identity_equal[0] || !descriptor_header_valid),
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
  starlink_pss_realtime_input_guard_local_admission #(.CHECK_INPUT_BLOCK_IDENTITY(1),
    .BALANCED_IDENTITY_EQ(REGISTERED_SCHEDULING),
    .LOCAL_FIRST_ADMISSION(LOCAL_FIRST_ADMISSION)) input_guard (
    .clk(fft_clk), .resetn(core_aresetn), .job_start(input_job_start),
    .job_descriptor(engine_metadata), .input_enable(engine_input_enable),
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
  // Offered events are summary-only. They NEVER drive delivery or counters.
  // Caller premise: input_fault_now===0 implies offers case-equal certificates.
  wire summary_offer_beat = guard_valid && transport_ready;
  wire summary_offer_complete = summary_offer_beat && guard_last;
  wire cutover_offered_fault_now;
  wire [1:0] guard_offered_local_fault;
  wire vendor_fault_now = event_last_unexpected || event_last_missing || event_input_halt;
  wire forward_handoff_identity = product_bank_metadata ==
    {1'b1, engine_metadata[68:5], return_metadata[4:0]};
  // The return exponent register is immutable after the forward guard commit.
  // A bank claiming ownership with the wrong descriptor cannot ACK that guard.
  wire handoff_fault_now = !next_inverse && forward_committed && product_bank_valid &&
    (!forward_handoff_identity || product_bank_position != 0 || product_bank_last);
  wire external_fault_now = input_fault_now || input_guard_fault || slow_faults_fast ||
    vendor_fault_now || fast_fault || kernel_fault || product_overflow || product_bank_fault ||
    product_bank_framing_fault_now || handoff_fault_now || cutover_fault_now ||
    (|cutover_reasons) || retained_fault_now || (|retained_reasons);
  // Direct unknown input fault is explicitly fail-closed in this opt-in summary.
  // All original full diagnostic/current predicates remain above and in guards.
  wire offered_external_fault_now = (input_fault_now !== 1'b0) || input_guard_fault || slow_faults_fast ||
    vendor_fault_now || fast_fault || kernel_fault || product_overflow || product_bank_fault ||
    product_bank_framing_fault_now || handoff_fault_now || cutover_offered_fault_now ||
    (|cutover_reasons) || retained_fault_now || (|retained_reasons);
  wire forward_handoff_ack = forward_committed && product_bank_valid &&
    forward_handoff_identity && product_bank_position == 0 && !product_bank_last &&
    !external_fault_now && !result_fault;
  wire result_destination_ready = next_inverse ? output_bank_ready :
    (forward_committed ? product_bank_valid : (kernel_ready && product_bank_ready));
  // Raw ownership readiness is not the certified forward ACK. While the
  // forward token is set the guard is inactive: its unchanged idle/current
  // faults veto ACK retirement. The controller independently requires the
  // complete identity/position/TLAST/current-fault certificate below.
  assign destination_reserved = next_inverse ?
    (output_bank_ready && (retained_reserved || inverse_allocation_pending || retained_reusable)) : product_bank_ready;
  // input_complete is already a registered per-core-epoch certificate. While
  // true, framing/delivery are impossible but a current duplicate job_start
  // remains an immediate fault. This fence is exactly the original full fence.
  wire final_fence = checked_input_complete && !input_guard_fault && !duplicate_start_fault_now;
  // An occupied return also excludes forward_committed: final commit clears
  // active on the same edge that sets that token. The full handoff comparator
  // remains on publication/ACK/quarantine; it cannot fault an occupied return.
  wire completed_input_fault_now = duplicate_start_fault_now || input_guard_fault ||
    slow_faults_fast || vendor_fault_now || fast_fault || kernel_fault ||
    product_overflow || product_bank_fault || product_bank_framing_fault_now ||
    (CLOSED_INPUT_CUTOVER ? cutover_closed_input_fault_now : cutover_fault_now) ||
    (|cutover_reasons) || retained_fault_now || (|retained_reasons);
  wire [1:0] guard_ready, guard_capacity, guard_busy, guard_commit, guard_fault, guard_ack, guard_current_fault, guard_forward_retire;
  wire [1:0] guard_valid_out, guard_private_out, guard_commit_out, guard_last_out;
  wire [1:0] guard_forward_private_offer;
  wire [7:0] guard_offered_local_faults [0:1];
  wire [35:0] guard_return_data [0:1];
  wire [8:0] guard_return_position [0:1];
  wire [74:0] guard_return_metadata [0:1];
  assign job_ready = CERTIFIED_ADMISSION ? admission_permit && guard_ready[next_inverse] :
    guard_ready[next_inverse] && cutover_admission_allowed &&
    (!next_inverse || inverse_descriptor_live) && !common_current_fault;
  assign result_busy = guard_busy[next_inverse];
  assign result_commit = guard_commit[next_inverse];
  assign result_fault = |guard_fault;
  assign forward_fault_now = guard_current_fault[0];
  assign inverse_fault_now = guard_current_fault[1];
  assign return_valid = guard_valid_out[routed_inverse];
  assign return_private_valid = guard_private_out[routed_inverse];
  assign return_commit_valid = guard_commit_out[routed_inverse];
  assign return_last = guard_last_out[routed_inverse];
  assign return_data = guard_return_data[routed_inverse];
  assign return_position = guard_return_position[routed_inverse];
  assign return_metadata = guard_return_metadata[routed_inverse];
  wire original_common_current_fault = external_fault_now || forward_fault_now || inverse_fault_now ||
    output_bank_fault || output_bank_framing_fault_now || preparation_fault_now || result_fault;
  wire offered_common_current_fault = offered_external_fault_now ||
    guard_offered_local_fault[0] || guard_offered_local_fault[1] ||
    output_bank_fault || output_bank_framing_fault_now || preparation_fault_now || result_fault;
  // Contextual scalar absorption affects only the common summary. Keep the
  // complete original detailed preflight vector and both old aggregates above.
  wire summary_destination_ready = next_inverse ? output_bank_ready : product_bank_ready;
  wire summary_destination_event = REGISTERED_SCHEDULING && fast_running && preparing ?
    !summary_destination_ready : 1'b0;
  wire [5:0] summary_preflight_events =
    {preflight_events_now[5], summary_destination_event, preflight_events_now[3:0]};
  wire destination_original_common = external_fault_now || forward_fault_now || inverse_fault_now ||
    output_bank_fault || output_bank_framing_fault_now || (|summary_preflight_events) || result_fault;
  wire destination_offered_common = offered_external_fault_now ||
    guard_offered_local_fault[0] || guard_offered_local_fault[1] ||
    output_bank_fault || output_bank_framing_fault_now || (|summary_preflight_events) || result_fault;
  wire contextual_destination_common = (fast_running === 1'b1 && retained_reserved_known) ?
    (INPUT_OFFER_FAULT_SUMMARY ? destination_offered_common : destination_original_common) :
    (INPUT_OFFER_FAULT_SUMMARY ? offered_common_current_fault : original_common_current_fault);
  generate if (CONTEXTUAL_DESTINATION_SUMMARY === 0) begin : original_destination_summary
  assign common_current_fault = INPUT_OFFER_FAULT_SUMMARY ?
    offered_common_current_fault : original_common_current_fault;
  end else begin : contextual_destination_summary
    assign common_current_fault = contextual_destination_common;
  end endgenerate
  // Partition the SAME offered/contextual fault predicate into independently
  // clocked facts. No global OR or current input identity cone feeds admission.
  // The bank is held throughout ARM_JOB; faults still latch into quarantine on
  // the current edge and fence public writes independently of this certificate.
  wire [18:0] admission_reject;
  assign admission_reject[0] = input_fault_now !== 1'b0;
  assign admission_reject[1] = input_guard_fault || slow_faults_fast;
  assign admission_reject[2] = vendor_fault_now || fast_fault;
  assign admission_reject[3] = kernel_fault || product_overflow || product_bank_fault;
  assign admission_reject[4] = product_bank_framing_fault_now;
  assign admission_reject[5] = handoff_fault_now;
  assign admission_reject[6] = cutover_offered_fault_now || (|cutover_reasons);
  assign admission_reject[7] = retained_fault_now || (|retained_reasons);
  assign admission_reject[8] = guard_offered_local_fault[0];
  assign admission_reject[9] = guard_offered_local_fault[1];
  assign admission_reject[10] = output_bank_fault;
  assign admission_reject[11] = output_bank_framing_fault_now;
  assign admission_reject[17:12] = summary_preflight_events;
  assign admission_reject[18] = result_fault;
  // Preserve the scalar predicate for current fault fencing. Certificates
  // register each guard fact before reduction; no fault is omitted or delayed.
  wire [32:0] admission_reject_expanded = {admission_reject[18:10],
    guard_offered_local_faults[1],guard_offered_local_faults[0],admission_reject[7:0]};
  wire [35:0] admission_checks = {!next_inverse || inverse_descriptor_live,
    cutover_admission_capacity,guard_capacity[next_inverse],~admission_reject_expanded};
  // Availability may legitimately rise while inverse allocation is pending.
  // Do not freeze a rejected capacity snapshot; begin validation only after
  // these small private-capacity predicates are ready. No fault tree here.
  wire admission_request = CERTIFIED_ADMISSION && job_valid &&
    guard_capacity[next_inverse] && cutover_admission_capacity &&
    (!next_inverse || inverse_descriptor_live);
  starlink_pss_admission_certificate #(.CHECKS(36)) admission_gate (
    .clk(fft_clk), .resetn(fast_running),
    .request(admission_request), .quarantine(registered_quarantine),
    .consume(job_accept),
    .checks_good(admission_checks),
    .permit(admission_permit), .snapshot_valid(), .snapshot_good()
  );
  generate for (genvar owner_index = 0; owner_index < 2; owner_index = owner_index + 1) begin : owners
  localparam integer OWNER = owner_index;
  wire this_raw_owner = routed_inverse == OWNER;
  starlink_pss_result_guard_owner_view #(.USE_COMPLETED_INPUT_FAULT(1),
    .CERTIFIED_PRIVATE_ADMISSION(CERTIFIED_ADMISSION),
    .USE_PRIVATE_DESCRIPTOR_OFFER(PRIVATE_DESCRIPTOR_OFFER),
    .ENABLE_OFFERED_FAULT_SUMMARY(INPUT_OFFER_FAULT_SUMMARY),
    .REQUIRE_KNOWN_COMPLETED_INPUT(CLOSED_INPUT_CUTOVER),
    .USE_PREFLIGHT_REASON_ONLY(REGISTERED_SCHEDULING),
    .USE_FORWARD_RETIREMENT(REGISTERED_SCHEDULING)) result_guard (
    .clk(fft_clk), .resetn(fast_running),
    .job_valid(job_valid && job_ready && next_inverse == OWNER), .job_ready(guard_ready[OWNER]),
    .admission_capacity(guard_capacity[OWNER]),
    .private_descriptor_offer(job_valid && next_inverse == OWNER),
    .job_descriptor(REGISTERED_SCHEDULING ? engine_metadata : selected_metadata),
    .input_bank_reserved(!REGISTERED_SCHEDULING && state == WAIT_BANK ? selected_valid : engine_input_reserved),
    .output_bank_reserved(OWNER == 1 ? retained_reserved : engine_output_reserved),
    .certified_input_beat(certified_input_beat && this_raw_owner),
    .certified_input_complete(certified_input_complete && this_raw_owner),
    .offered_input_beat(summary_offer_beat && this_raw_owner),
    .offered_input_complete(summary_offer_complete && this_raw_owner),
    .offered_local_fault_now(guard_offered_local_fault[OWNER]),
    .offered_local_faults_now(guard_offered_local_faults[OWNER]),
    .final_fence_certified(final_fence), .external_fault_now(external_fault_now),
    .phase_input_fault_now(1'b0), .core_event_frame_started(event_frame && this_raw_owner),
    .preflight_fault_evidence_now(preparation_fault_now),
    .completed_input_certified(checked_input_complete),
    .completed_input_fault_now(completed_input_fault_now),
    .core_output_tdata(core_output_data), .core_output_tuser(core_output_user),
    .core_output_tvalid(core_output_valid && this_raw_owner), .core_output_tlast(core_output_last),
    .core_status_tdata(core_status_data), .core_status_tvalid(core_status_valid && this_raw_owner),
    .mailbox_input_valid(guard_valid_out[OWNER]), .mailbox_private_valid(guard_private_out[OWNER]),
    .mailbox_commit_valid(guard_commit_out[OWNER]),
    .mailbox_input_ready(OWNER == 1 ? inverse_guard_ready :
      (forward_committed ? product_bank_valid : (kernel_ready && product_bank_ready))),
    .mailbox_input_fault(output_bank_fault || output_bank_framing_fault_now),
    .inverse_phase(OWNER == 1), .forward_mailbox_fault(output_bank_fault),
    .forward_retirement_valid(guard_forward_retire[OWNER]),
    .forward_private_offer(guard_forward_private_offer[OWNER]),
    .mailbox_input_data(guard_return_data[OWNER]), .mailbox_input_position(guard_return_position[OWNER]),
    .mailbox_input_last(guard_last_out[OWNER]), .mailbox_input_metadata(guard_return_metadata[OWNER]),
    .busy(guard_busy[OWNER]), .commit_pulse(guard_commit[OWNER]),
    .protocol_fault(guard_fault[OWNER]), .fault_reasons(),
    .owner_active(), .owner_awaiting_ack(), .owner_ack_accept(guard_ack[OWNER]),
    .owner_fault_now(guard_current_fault[OWNER])
  );
  end endgenerate
  assign forward_retirement_valid = guard_forward_retire[0];
  // Allocate before inverse admission; keep descriptor identity through the
  // actual reader ACK. Allocation return storage cannot block COMMIT/RELEASE.
  reg [31:0] inverse_tag;
  reg [31:0] output_descriptor_tag;
  reg [74:0] output_descriptor_payload;
  reg output_descriptor_valid, output_descriptor_fault;
  reg output_descriptor_pending, output_descriptor_lookup_ok;
  reg output_descriptor_locked;
  reg [69:0] output_descriptor_expected;
  wire output_allocate_ready, output_allocated_valid;
  wire [31:0] output_allocated_tag;
  wire output_complete_ready, output_replay_valid, output_publication_busy;
  wire output_published_valid, output_released_valid, output_control_fault;
  wire [31:0] output_replay_tag;
  wire [35:0] output_replay_data;
  wire output_lookup_found, output_lookup_committed;
  wire [69:0] output_lookup_descriptor;
  wire [36:0] output_bank_metadata;
  wire output_allocate_valid = (state==VERIFY_LEASE || state==ARM_JOB) && next_inverse &&
    !inverse_descriptor_live && !inverse_allocation_pending;
  // The guard closes its producer on qualified completion, not on raw TLAST.
  // It must then see READY low until the actual reader ACK and ledger release.
  assign inverse_guard_ready = (output_bank_ready && output_complete_ready) || output_released_valid;
  wire output_complete_valid = guard_commit_out[1] && output_bank_ready;
  wire output_complete_accept = output_complete_valid && output_complete_ready;
  // Private payload may follow the owned producer before completion. The
  // acceptance edge freezes it through validation, publication and real reader
  // release. Only the small receipt/lock registers use qualified acceptance;
  // wide payload enables must not inherit the current-fault tree.
  wire output_descriptor_capture = inverse_descriptor_live && !output_descriptor_locked;
  // Private replay consumption is not publication. A new current fault still
  // vetoes bank authorization below, and its registered epoch abort cancels
  // the adapter before any notification/release. The adapter independently
  // rejects P_ACK if the real bank request did not transition.
  wire output_replay_private_ready = output_bank_ready && output_descriptor_valid;
  wire output_replay_accept = output_replay_valid && output_descriptor_valid && output_bank_ready && !common_current_fault;
  starlink_pss_staged_mailbox_control #(.PRIVATE_FINAL_CAPTURE(1)) output_control (
    .clk(fft_clk), .resetn(fast_running), .abort_epoch(fast_fault),
    .allocate_valid(output_allocate_valid), .allocate_ready(output_allocate_ready),
    .allocate_descriptor(engine_metadata), .allocated_valid(output_allocated_valid),
    .allocated_ready(1'b1), .allocated_tag(output_allocated_tag),
    .complete_valid(output_complete_valid), .complete_ready(output_complete_ready),
    .complete_tag(inverse_tag), .complete_final_data(guard_return_data[1]),
    .replay_valid(output_replay_valid),
    .replay_ready(output_replay_private_ready),
    .replay_tag(output_replay_tag), .replay_data(output_replay_data),
    .bank_request(output_request), .bank_ack_sync(output_ack_sync), .bank_fault(output_bank_fault),
    .publication_busy(output_publication_busy), .published_valid(output_published_valid),
    .released_valid(output_released_valid), .released_tag(),
    // Private lookup follows held descriptor ownership, not the fault-gated
    // completion event. Its result grants nothing until completion validation.
    .lookup_valid(inverse_descriptor_live), .lookup_tag(inverse_tag),
    .lookup_found(output_lookup_found), .lookup_committed(output_lookup_committed),
    .lookup_descriptor(output_lookup_descriptor),
    .occupied(), .committed(), .tags_exhausted(), .fault(output_control_fault)
  );
  assign retained_reusable = fast_running && !inverse_descriptor_live &&
    !inverse_allocation_pending && !output_publication_busy && output_bank_ready &&
    !output_control_fault;
  assign retained_reserved = inverse_descriptor_live;
  assign retained_reserved_known = 1'b1;
  assign retained_fault_now = output_control_fault || output_descriptor_fault;
  assign retained_reasons = 8'b0;
  assign reader_release = output_released_valid && guard_ack[1];
  // Writer-domain lookup/validation precedes publication. Only held registers
  // cross to this receiver, under the real bank's synchronized ownership event.
  // Capture first, then compare captured tag/exponent in the READER domain.
  // No live lookup result or fast-domain comparator drives a reader enable.
  assign output_metadata = slow_output_metadata;
  assign reader_descriptor_idle = reader_descriptor_phase==RD_EMPTY && !slow_lookup_fault;
  always @(posedge clk) begin
    if (!slow_running) begin
      reader_descriptor_phase<=RD_EMPTY;slow_output_metadata<=0;reader_descriptor_tag<=0;slow_lookup_fault<=0;
    end else begin
      if (slow_output_valid && reader_descriptor_phase==RD_EMPTY && !fault) begin
        slow_output_metadata<=output_descriptor_payload;reader_descriptor_tag<=output_descriptor_tag;
        reader_descriptor_phase<=RD_CHECK;
      end
      if (reader_descriptor_phase==RD_CHECK && !fault) begin
        if (slow_output_valid!==1'b1 || output_position!==9'b0 || output_last!==1'b0 ||
            reader_descriptor_tag!==output_bank_metadata[36:5] ||
            slow_output_metadata[4:0]!==output_bank_metadata[4:0]) begin
          slow_lookup_fault<=1;reader_descriptor_phase<=RD_FAULT;
        end
        else reader_descriptor_phase<=RD_VALID;
      end
      if (output_valid && output_ready && output_last) reader_descriptor_phase<=RD_EMPTY;
    end
  end
  always @(posedge fft_clk) begin
    if (!fast_running) begin
      inverse_descriptor_live<=0;inverse_allocation_pending<=0;inverse_tag<=0;
      output_descriptor_tag<=0;output_descriptor_payload<=0;output_descriptor_valid<=0;output_descriptor_fault<=0;
      output_descriptor_pending<=0;output_descriptor_lookup_ok<=0;output_descriptor_expected<=0;
      output_descriptor_locked<=0;
      retained_published<=0;producer_transfer_receipt<=0;
    end else begin
      if (output_allocate_valid && output_allocate_ready) inverse_allocation_pending<=1;
      if (output_allocated_valid) begin
        inverse_descriptor_live<=1;inverse_allocation_pending<=0;inverse_tag<=output_allocated_tag;
      end
      if (output_descriptor_capture) begin
        // Invalid private values grant nothing. On the actual acceptance edge
        // these are the same lookup/return values as the qualified capture.
        output_descriptor_tag<=inverse_tag;
        output_descriptor_payload<={output_lookup_descriptor,guard_return_metadata[1][4:0]};
        output_descriptor_expected<=guard_return_metadata[1][74:5];
        output_descriptor_lookup_ok<=output_lookup_found===1'b1 && output_lookup_committed===1'b0;
      end
      if (output_complete_accept) begin
        output_descriptor_locked<=1;
        output_descriptor_valid<=0;output_descriptor_pending<=1;
      end else if (output_descriptor_pending) begin
        output_descriptor_pending<=0;
        output_descriptor_valid<=output_descriptor_lookup_ok &&
          output_descriptor_payload[74:5]===output_descriptor_expected;
        if (!output_descriptor_lookup_ok || output_descriptor_payload[74:5]!==output_descriptor_expected)
          output_descriptor_fault<=1;
      end
      if (output_published_valid) begin retained_published<=1;producer_transfer_receipt<=1;end
      if (completion_accept && next_inverse) producer_transfer_receipt<=0;
      if (output_released_valid) begin
        inverse_descriptor_live<=0;retained_published<=0;output_descriptor_locked<=0;
      end
    end
  end
  starlink_pss_core_job_cutover #(.ENABLE_CLOSED_INPUT_VIEW(CLOSED_INPUT_CUTOVER),
    .ENABLE_OFFERED_FAULT_SUMMARY(INPUT_OFFER_FAULT_SUMMARY)) cutover (
    .clk(fft_clk), .resetn(fast_running), .core_resetn(core_aresetn),
    // Validation terminates at the existing receipt registers. The scheduler
    // applies the same receipt on this edge, preserving reset/config ordering.
    // A current fault may advance private state, but publication is still
    // vetoed on that edge and registered quarantine prevents any new job.
    .job_accept(fast_running && admission_receipt && !registered_quarantine), .job_inverse(held_phase),
    .producer_closed(fast_running && completion_receipt && !registered_quarantine),
    .config_accept(config_valid && config_ready), .input_beat(certified_input_beat),
    .input_complete(certified_input_complete), .raw_frame(event_frame),
    .offered_input_beat(summary_offer_beat), .offered_input_complete(summary_offer_complete),
    .offered_fault_now(cutover_offered_fault_now),
    .raw_output(core_output_valid), .raw_status(core_status_valid),
    .raw_vendor_faults({event_last_unexpected, event_last_missing, event_input_halt}),
    .admission_allowed(cutover_admission_allowed), .admission_capacity(cutover_admission_capacity),
    .configuration_allowed(cutover_configuration_allowed),
    .fault_now(cutover_fault_now), .routed_inverse(routed_inverse), .fault_reasons(cutover_reasons),
    .closed_input_fault_now(cutover_closed_input_fault_now)
  );
  // Nonfinal checked results may compute privately before independent status.
  // The final result is admitted ONLY on the original guard's qualified commit.
  starlink_pss_forward_kernel_join #(.KERNEL_ROM_FILE(KERNEL_ROM_FILE), .DATA_WIDTH(18),
    .PRIVATE_PAYLOAD_BUBBLES(REGISTERED_SCHEDULING),
    .PRIVATE_SEQUENCE_ADVANCE(REGISTERED_SCHEDULING),
    .BALANCED_BLOCK_IDENTITY_EQ(REGISTERED_SCHEDULING)) joiner (
    .clk(fft_clk), .resetn(fast_running), .flush(1'b0),
    // Match the guard's exact retirement event, including a held final word.
    // An owned bank should remain ready, but a readiness fault/stall must never
    // let the joiner consume a word that the guard has not retired.
    .input_valid((REGISTERED_SCHEDULING ? forward_retirement_valid :
      (return_valid && !next_inverse)) && !fast_fault && product_bank_ready),
    .input_private_valid(guard_forward_private_offer[0] && !fast_fault && product_bank_ready),
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
  starlink_pss_spectrum_product_operand_register #(.DATA_WIDTH(18),
    .BOUNDARY_ROUND_SAT(BOUNDARY_ROUND_SAT), .REGISTER_OPERANDS(REGISTER_OPERANDS),
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
  starlink_pss_mailbox_owner_view #(.RESET_RELEASE_EXTERNAL(1), .EXPLICIT_COMMIT(1)) product_bank (
    .input_clk(fft_clk), .input_resetn(fast_running),
    .input_valid(product_valid && !fast_fault), .input_ready(product_bank_ready),
    .input_commit_authorized(product_commit_authorized),
    .input_data({product_q, product_i}), .input_position(product_position), .input_last(product_last),
    .input_metadata({1'b1, product_start, product_exponent}),
    .input_fault(product_bank_fault), .input_framing_fault_now(product_bank_framing_fault_now),
    .output_clk(fft_clk), .output_resetn(fast_running),
    .output_valid(product_bank_valid), .output_ready(product_bank_read_ready),
    .output_data(product_bank_data), .output_position(product_bank_position),
    .output_last(product_bank_last), .output_metadata(product_bank_metadata),
    .owner_request(), .owner_ack_sync(), .writer_reset_idle(product_writer_idle),
    .reader_reset_idle(product_reader_idle)
  );
  assign output_valid = slow_running && slow_output_valid && slow_metadata_valid && !fault;
  // BEGIN HELD BANK METADATA
  // The inverse tag remains owned until real release. The retired inverse
  // guard holds its last exponent through that interval, including replay.
  // Use that same pair for private writes and replay: publication phase must
  // not select metadata into the bank's current framing/fault comparator.
  // Nonregistered callers retain their original selection. No valid, commit,
  // fault, descriptor validation or reader-ACK predicate changes here.
  wire [36:0] output_write_metadata = REGISTERED_SCHEDULING ?
    {inverse_tag,guard_return_metadata[1][4:0]} :
    (output_publication_busy ? {output_replay_tag,output_descriptor_payload[4:0]} :
      {inverse_tag,guard_return_metadata[1][4:0]});
  // END HELD BANK METADATA
  // BEGIN HELD BANK HANDOFF
  // Qualified completion retires the inverse guard on the same edge that
  // takes the adapter out of EMPTY. Its private-valid is then low and its
  // final payload remains held until actual reader release and a later job.
  // The two private offers are disjoint; neither grants commit authority.
  wire output_write_valid = REGISTERED_SCHEDULING ?
    (guard_private_out[1] || output_replay_valid) :
    (output_publication_busy ? output_replay_valid : guard_private_out[1]);
  wire [35:0] output_write_data = REGISTERED_SCHEDULING ? guard_return_data[1] :
    (output_publication_busy ? output_replay_data : guard_return_data[1]);
  wire [8:0] output_write_position = REGISTERED_SCHEDULING ? guard_return_position[1] :
    (output_publication_busy ? 9'd511 : guard_return_position[1]);
  wire output_write_last = REGISTERED_SCHEDULING ? guard_last_out[1] :
    (output_publication_busy ? 1'b1 : guard_last_out[1]);
  // END HELD BANK HANDOFF
  starlink_pss_mailbox_owner_view #(.METADATA_WIDTH(37), .RESET_RELEASE_EXTERNAL(1),
      .EXPLICIT_COMMIT(1)) output_bank (
    .input_clk(fft_clk), .input_resetn(fast_running),
    // Payload selection follows registered private ownership, not a fault-
    // gated public-valid signal. A fault must not switch the metadata mux and
    // then traverse a wide framing comparator back into global control.
    .input_valid(output_write_valid),
    .input_commit_authorized(output_replay_accept), .input_ready(output_bank_ready),
    .input_data(output_write_data),
    .input_position(output_write_position),
    .input_last(output_write_last),
    .input_metadata(output_write_metadata), .input_fault(output_bank_fault),
    .input_framing_fault_now(output_bank_framing_fault_now),
    .output_clk(clk), .output_resetn(slow_running),
    .output_valid(slow_output_valid), .output_ready(output_ready && slow_metadata_valid && !fault),
    .output_data(output_data), .output_position(output_position), .output_last(output_last),
    .output_metadata(output_bank_metadata), .owner_request(output_request), .owner_ack_sync(output_ack_sync),
    .writer_reset_idle(output_writer_idle), .reader_reset_idle(output_reader_idle)
  );
  wire any_fast_fault = common_current_fault;
  assign registered_quarantine = fast_fault || result_fault || (|epoch_input_reasons) ||
    (|epoch_preflight_reasons) || (|cutover_reasons) || (|retained_reasons);
  wire legacy_completion_accept = state == ACK_DRAIN && !completion_receipt &&
    (next_inverse ? producer_transfer_receipt : (!guard_busy[0] && forward_handoff_ack)) && !any_fast_fault &&
    !certified_input_beat && !certified_input_complete && !event_frame &&
    !core_status_valid && !core_output_valid;
  // The bank and phase remain owned throughout ACK_DRAIN. Capture each fault,
  // quiet-input and forward-identity check before issuing the private close.
  // The next-edge receipt consumer still observes registered quarantine; no
  // public write, reader release or core reuse is authorized by these facts.
  wire completion_request = CERTIFIED_ADMISSION && state==ACK_DRAIN && !completion_receipt &&
    (next_inverse ? producer_transfer_receipt : (!guard_busy[0] && forward_committed && product_bank_valid));
  wire [27:0] completion_good = {
    !cutover_fault_now,
    next_inverse || forward_handoff_identity,
    next_inverse || product_bank_position==0,
    next_inverse || !product_bank_last,
    !certified_input_beat,!certified_input_complete,
    !event_frame,!core_status_valid,!core_output_valid,
    ~admission_reject};
  wire completion_permit;
  wire [41:0] completion_checks = {completion_good[27:19],~admission_reject_expanded};
  starlink_pss_admission_certificate #(.CHECKS(42)) completion_gate (
    .clk(fft_clk), .resetn(fast_running), .request(completion_request),
    .quarantine(registered_quarantine), .consume(completion_accept),
    .checks_good(completion_checks), .permit(completion_permit),
    .snapshot_valid(), .snapshot_good()
  );
  assign completion_accept = CERTIFIED_ADMISSION ? completion_permit : legacy_completion_accept;
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
  always @(posedge fft_clk)
    if (!fast_running) fast_fault <= 0;
    else if (any_fast_fault) fast_fault <= 1;
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
          // In certified mode this is only a private descriptor snapshot.
          // Admission still checks current faults and consumes a registered
          // certificate under epoch quarantine before any core/job start.
          descriptor_certified <= preparation_valid && (CERTIFIED_ADMISSION || !any_fast_fault);
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
          CONFIGURE: if (config_valid && config_ready) state <= ENABLE_INPUT;
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
`default_nettype wire
