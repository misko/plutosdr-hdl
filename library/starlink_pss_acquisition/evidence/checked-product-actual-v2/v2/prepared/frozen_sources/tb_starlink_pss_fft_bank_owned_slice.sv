`timescale 1ns/1fs
module tb_starlink_pss_fft_bank_owned_slice;
  parameter integer FAST_MHZ = 200;
  parameter integer QUICK_MUTATION = 0;
  parameter integer REGISTERED_SCHEDULING = 0;
  // BEGIN EXACT_CONTROL_PARAMETERS
  parameter integer DISTRIBUTED_FAST_FAULT = 0;
  parameter integer PER_CAUSE_FAULT_CDC = 0;
  parameter integer PRIVATE_ROM_READ_AHEAD = 0;
  parameter integer PRIVATE_BLOCK_METADATA_READ_AHEAD = 0;
  parameter integer PRODUCER_LOCAL_FINAL_FENCE = 0;
  parameter integer CHECKED_PRODUCT_BANK = 1;
  parameter integer PRIVATE_NEXT_START_SCRATCH = 0;
  parameter integer EXACT_EXTRA_EPOCHS = 0;
  initial begin
    if (EXACT_EXTRA_EPOCHS !== 0 && EXACT_EXTRA_EPOCHS !== 1)
      $fatal(1, "EXACT_EXTRA_EPOCHS_REQUIRES_ZERO_OR_ONE");
  end
  // END EXACT_CONTROL_PARAMETERS
  reg clk = 0, fft_clk = 0;
  initial begin #1.3; forever #5 clk = !clk; end
  always #(500.0/FAST_MHZ) fft_clk = !fft_clk;
  reg resetn = 0, fft_resetn = 0;
  reg input_valid = 0, input_last = 0;
  reg [35:0] input_data = 0;
  reg [8:0] input_position = 0;
  reg [63:0] input_block_start = 0;
  wire input_ready, output_valid, output_last, fault;
  wire [35:0] output_data;
  wire [8:0] output_position;
  wire [74:0] output_metadata;
  integer fast_cycle = 0, slow_cycle = 0, epoch = 0, profile = 0;
  always @(negedge clk) slow_cycle = slow_cycle + 1;
  always @(negedge fft_clk) fast_cycle = fast_cycle + 1;
  reg reader_enable = 1, expected_fault = 0, expected_results = 1, injecting_readiness = 0;
  reg allow_inverse_commit_before_late_fault = 0;
  reg allow_provisional_prefix_after_fault = 0;
  wire output_ready = reader_enable && (profile == 0 || slow_cycle % 17 < 13);
  starlink_pss_fft_bank_owned_checked_product #(.REGISTERED_SCHEDULING(REGISTERED_SCHEDULING),
    .DISTRIBUTED_FAST_FAULT(DISTRIBUTED_FAST_FAULT),
    .PER_CAUSE_FAULT_CDC(PER_CAUSE_FAULT_CDC),
    .PRIVATE_NEXT_START_SCRATCH(PRIVATE_NEXT_START_SCRATCH),
    .PRIVATE_ROM_READ_AHEAD(PRIVATE_ROM_READ_AHEAD),
    .PRIVATE_BLOCK_METADATA_READ_AHEAD(PRIVATE_BLOCK_METADATA_READ_AHEAD),
    .PRODUCER_LOCAL_FINAL_FENCE(PRODUCER_LOCAL_FINAL_FENCE),
    .CHECKED_PRODUCT_BANK(CHECKED_PRODUCT_BANK)) dut (.*);
  `include "starlink_pss_fault_cdc_actual_observer.svh"
  `include "starlink_pss_rom_actual_observer.svh"
  // Old sampled-mailbox observer is preserved in disabled/history scope.
  `include "starlink_pss_checked_product_actual_observer.svh"
  `include "starlink_pss_exact_control_extra_epochs.svh"
  // BEGIN PAYLOAD_BUBBLE_SHADOW: additive independent frozen arithmetic chain.
  wire [31:0] payload_checks, payload_join_occupied, payload_product_occupied;
  wire [31:0] payload_join_invalid, payload_product_invalid;
  starlink_pss_payload_bubble_shadow payload_shadow (
    .clk(fft_clk), .resetn(dut.fast_running), .flush(1'b0),
    .input_valid(dut.joiner.input_valid), .product_enable(!dut.fast_fault),
    .output_ready(dut.product.output_ready),
    .input_i(dut.joiner.input_i), .input_q(dut.joiner.input_q),
    .input_position(dut.joiner.input_bin_index), .input_exponent(dut.joiner.input_block_exponent),
    .input_last(dut.joiner.input_last), .input_start(dut.joiner.input_block_start_index),
    .join_controls({dut.joiner.input_ready, dut.joiner.output_valid, dut.joiner.output_bin_index,
      dut.joiner.output_block_exponent, dut.joiner.output_last, dut.joiner.output_block_start_index,
      dut.joiner.accepted_pulse, dut.joiner.emitted_pulse, dut.joiner.input_block_complete_pulse,
      dut.joiner.sequence_error_pulse, dut.joiner.metadata_error_pulse, dut.joiner.protocol_fault}),
    .join_payload({dut.joiner.output_i, dut.joiner.output_q, dut.joiner.output_kernel_i, dut.joiner.output_kernel_q}),
    .product_outputs({dut.product.input_ready, dut.product.output_valid, dut.product.output_i,
      dut.product.output_q, dut.product.output_bin_index, dut.product.output_block_exponent,
      dut.product.output_last, dut.product.output_block_start_index, dut.product.output_overflow,
      dut.product.overflow_pulse}),
    .product_private({dut.product.product_valid, dut.product.product_ii, dut.product.product_qq,
      dut.product.product_iq, dut.product.product_qi}),
    .checks(payload_checks), .join_occupied(payload_join_occupied), .product_occupied(payload_product_occupied),
    .join_invalid_differences(payload_join_invalid), .product_invalid_differences(payload_product_invalid)
  );
  // END PAYLOAD_BUBBLE_SHADOW
  // BEGIN FORWARD_RETIREMENT_SHADOW: additive frozen old full guard/chain.
  wire forward_old_valid, forward_old_private;
  wire [31:0] forward_checks, forward_cycles, forward_current, forward_sticky;
  starlink_pss_forward_retirement_shadow #(.ENABLED(REGISTERED_SCHEDULING),
    .COMPLETED(1), .PREFLIGHT(REGISTERED_SCHEDULING)) forward_shadow (
    .clk(fft_clk), .resetn(dut.fast_running), .job_valid(dut.job_valid),
    .job_descriptor(dut.result_guard.job_descriptor),
    .input_bank_reserved(dut.result_guard.input_bank_reserved),
    .output_bank_reserved(dut.result_guard.output_bank_reserved),
    .certified_input_beat(dut.certified_input_beat), .certified_input_complete(dut.certified_input_complete),
    .final_fence_certified(dut.final_fence), .external_fault_now(dut.external_fault_now),
    .phase_input_fault_now(1'b0), .completed_input_certified(dut.checked_input_complete),
    .completed_input_fault_now(dut.completed_input_fault_now),
    .preflight_fault_evidence_now(dut.preparation_fault_now),
    .core_event_frame_started(dut.event_frame), .core_output_tdata(dut.core_output_data),
    .core_output_tuser(dut.core_output_user), .core_output_tvalid(dut.core_output_valid),
    .core_output_tlast(dut.core_output_last), .core_status_tdata(dut.core_status_data),
    .core_status_tvalid(dut.core_status_valid), .mailbox_input_ready(dut.result_destination_ready),
    .mailbox_input_fault(dut.output_bank_fault || dut.output_bank_framing_fault_now),
    .inverse_phase(dut.next_inverse), .forward_mailbox_fault(dut.output_bank_fault),
    .mailbox_current_fault_now(dut.output_bank_framing_fault_now),
    .actual_public({dut.job_ready, dut.return_valid, dut.return_private_valid, dut.return_commit_valid,
      dut.return_data, dut.return_position, dut.return_last, dut.return_metadata,
      dut.result_busy, dut.result_commit, dut.result_fault, dut.result_guard.fault_reasons}),
    .actual_forward_valid(dut.forward_retirement_valid), .old_valid(forward_old_valid),
    .old_private_valid(forward_old_private), .checks(forward_checks), .forward_cycles(forward_cycles),
    .inverse_current_faults(forward_current), .sticky_forward_faults(forward_sticky)
  );
  // This second frozen arithmetic chain is driven by OLD certified retirement,
  // not by the candidate join input. All existing shadows remain untouched.
  starlink_pss_payload_bubble_shadow forward_chain_shadow (
    .clk(fft_clk), .resetn(dut.fast_running), .flush(1'b0),
    .input_valid(forward_old_valid && !dut.next_inverse && !dut.fast_fault && dut.product_bank_ready),
    .product_enable(!dut.fast_fault), .output_ready(dut.product.output_ready),
    .input_i(dut.joiner.input_i), .input_q(dut.joiner.input_q),
    .input_position(dut.joiner.input_bin_index), .input_exponent(dut.joiner.input_block_exponent),
    .input_last(dut.joiner.input_last), .input_start(dut.joiner.input_block_start_index),
    .join_controls({dut.joiner.input_ready, dut.joiner.output_valid, dut.joiner.output_bin_index,
      dut.joiner.output_block_exponent, dut.joiner.output_last, dut.joiner.output_block_start_index,
      dut.joiner.accepted_pulse, dut.joiner.emitted_pulse, dut.joiner.input_block_complete_pulse,
      dut.joiner.sequence_error_pulse, dut.joiner.metadata_error_pulse, dut.joiner.protocol_fault}),
    .join_payload({dut.joiner.output_i, dut.joiner.output_q, dut.joiner.output_kernel_i, dut.joiner.output_kernel_q}),
    .product_outputs({dut.product.input_ready, dut.product.output_valid, dut.product.output_i,
      dut.product.output_q, dut.product.output_bin_index, dut.product.output_block_exponent,
      dut.product.output_last, dut.product.output_block_start_index, dut.product.output_overflow,
      dut.product.overflow_pulse}),
    .product_private({dut.product.product_valid, dut.product.product_ii, dut.product.product_qq,
      dut.product.product_iq, dut.product.product_qi}),
    .checks(), .join_occupied(), .product_occupied(), .join_invalid_differences(), .product_invalid_differences()
  );
  always @(posedge fft_clk) begin
    #0.001;
    if (dut.joiner.input_valid !==
        (forward_old_valid && !dut.next_inverse && !dut.fast_fault && dut.product_bank_ready))
      $fatal(1, "FORWARD_ACTUAL_JOIN_INPUT_MISMATCH");
    if (dut.output_bank.input_valid !== (dut.return_private_valid && dut.next_inverse))
      $fatal(1, "FORWARD_ACTUAL_BANK_PHASE_WIRING_BROKEN");
  end
  // END FORWARD_RETIREMENT_SHADOW
  // Frozen old state-mux expression from tested cee639e4. This witness is
  // independent of the DUT's new guard mux and its selected_* discovery wires.
  wire old_input_phase = REGISTERED_SCHEDULING && dut.state != dut.WAIT_BANK &&
    dut.state != dut.RESET0 && dut.state != dut.RESET1 ? dut.held_phase : dut.next_inverse;
  wire old_discovery_valid = old_input_phase ? dut.product_bank_valid : dut.source_valid;
  wire old_input_valid = old_input_phase ? dut.product_core_valid : dut.source_valid;
  wire [35:0] old_input_data = old_input_phase ? dut.product_bank_data : dut.source_data;
  wire [8:0] old_input_position = old_input_phase ? dut.product_bank_position : dut.source_position;
  wire old_input_last = old_input_phase ? dut.product_bank_last : dut.source_last;
  wire [69:0] old_input_metadata = old_input_phase ? dut.product_bank_metadata : dut.source_metadata;
  wire [1:0] old_preflight_lease = old_input_phase ? dut.product_head_lease : {1'b0,dut.source_consume_generation};
  // Frozen preflight expressions from447183b8: neither equality nor current
  // cause shares the DUT's new balanced comparator/predicate implementation.
  wire old_descriptor_header_valid = dut.engine_metadata[69] == dut.held_phase &&
    (dut.held_phase ? dut.engine_metadata == dut.expected_product_metadata : dut.engine_metadata[4:0] == 0);
  wire old_preparation_valid = old_discovery_valid && old_input_position == 0 && !old_input_last &&
    old_preflight_lease == dut.held_lease && old_input_metadata == dut.engine_metadata &&
    old_descriptor_header_valid && dut.destination_reserved && (!old_input_phase || checked_start_binding);
  wire [5:0] old_preflight_events_now = REGISTERED_SCHEDULING && dut.fast_running &&
    (dut.state == dut.VERIFY_LEASE || dut.state == dut.ARM_JOB) ?
    {dut.preparation_age == 63, !dut.destination_reserved,
     (old_input_metadata != dut.engine_metadata || !old_descriptor_header_valid ||
      (old_input_phase && !checked_start_binding)),
     (old_preflight_lease != dut.held_lease), (old_input_position != 0 || old_input_last),
     !old_discovery_valid} : 6'b0;
  wire old_preflight_fault_now = |old_preflight_events_now;
  integer preflight_tuple_checks = 0, preflight_cause_checks = 0, cache_phase_cases = 0;
  reg [1:0] injected_preflight_lease;
  reg [69:0] injected_expected_product;
  wire old_transport_ready, old_input_complete, old_certified_beat, old_certified_complete;
  wire old_input_fault_now, old_input_fault, old_duplicate, old_core_valid, old_core_last;
  wire [2:0] old_input_events, old_input_reasons;
  wire [47:0] old_core_data;
  integer input_shadow_checks = 0, input_open_checks = 0, input_quarantine_open_checks = 0;
  integer active_fault_cases = 0, active_inverse, active_kind, active_ready;
  starlink_pss_realtime_input_guard #(.CHECK_INPUT_BLOCK_IDENTITY(1)) old_input_guard (
    .clk(fft_clk), .resetn(dut.core_aresetn), .job_start(dut.input_job_start),
    .job_descriptor(dut.engine_metadata), .input_enable(dut.engine_input_enable),
    .input_valid(old_input_valid), .input_ready(), .input_transport_ready(old_transport_ready),
    .input_data(old_input_data), .input_position(old_input_position), .input_last(old_input_last),
    .input_metadata(old_input_metadata), .core_input_tdata(old_core_data),
    .core_input_tvalid(old_core_valid), .core_input_tready(dut.core_input_ready),
    .core_input_tlast(old_core_last), .certified_input_beat(old_certified_beat),
    .certified_input_complete(old_certified_complete), .input_complete(old_input_complete),
    .fault_now(old_input_fault_now), .duplicate_start_fault_now(old_duplicate),
    .fault_events_now(old_input_events), .protocol_fault(old_input_fault), .fault_reasons(old_input_reasons)
  );
  always @(posedge fft_clk or negedge fft_clk) begin
    #0.001;
    preflight_cause_checks = preflight_cause_checks + 1;
    if ({dut.preflight_events_now, dut.preparation_fault_now} !==
        {old_preflight_events_now, old_preflight_fault_now})
      $fatal(1, "held-preflight full current-cause mismatch");
    if (dut.preparing) begin
      preflight_tuple_checks = preflight_tuple_checks + 1;
      if ({dut.preflight_phase, dut.preflight_valid, dut.preflight_data, dut.preflight_position,
           dut.preflight_last, dut.preflight_metadata, dut.preflight_lease, dut.preparation_valid} !==
          {old_input_phase, old_discovery_valid, old_input_data, old_input_position,
           old_input_last, old_input_metadata, old_preflight_lease, old_preparation_valid})
        $fatal(1, "held-preflight full preparing tuple/lease/predicate mismatch");
    end
    if (dut.fast_running) begin
      input_shadow_checks = input_shadow_checks + 1;
      if ({dut.transport_ready, dut.checked_input_complete, dut.certified_input_beat,
           dut.certified_input_complete, dut.input_fault_now, dut.input_guard_fault,
           dut.duplicate_start_fault_now, dut.input_fault_events_now,
           dut.input_guard.fault_reasons, dut.core_input_valid} !==
          {old_transport_ready, old_input_complete, old_certified_beat,
           old_certified_complete, old_input_fault_now, old_input_fault,
           old_duplicate, old_input_events, old_input_reasons, old_core_valid})
        $fatal(1, "held-phase input checker current/sticky/certificate mismatch");
      if (dut.input_guard.slot_open !== old_input_guard.slot_open)
        $fatal(1, "held-phase slot-open mismatch");
      if (dut.input_guard.slot_open) begin
        input_open_checks = input_open_checks + 1;
        if (dut.state == dut.QUARANTINE) input_quarantine_open_checks = input_quarantine_open_checks + 1;
        if ({dut.guard_phase, dut.guard_valid, dut.guard_data, dut.guard_position,
             dut.guard_last, dut.guard_metadata} !==
            {old_input_phase, old_input_valid, old_input_data, old_input_position,
             old_input_last, old_input_metadata})
          $fatal(1, "held-phase full open-slot tuple differs from frozen state mux");
      end
      if (dut.core_input_valid && {dut.core_input_data, dut.core_input_last} !== {old_core_data, old_core_last})
        $fatal(1, "held-phase certified core payload/TLAST mismatch");
      if ({dut.source_valid && dut.source_read_ready, dut.product_bank_valid && dut.product_bank_read_ready} !==
          {dut.source_valid && !old_input_phase && old_transport_ready && dut.engine_input_enable,
           dut.product_bank_valid && old_input_phase && old_transport_ready && dut.engine_input_enable})
        $fatal(1, "held-phase actual bank read handshake changed");
    end
  end
  // Default-mode shadow retains the original full nonfinal predicate and full
  // final fence. Compare before and after every edge, including injected faults.
  wire shadow_ready, shadow_valid, shadow_private, shadow_commit_valid;
  wire shadow_busy, shadow_commit, shadow_fault, shadow_last;
  wire [7:0] shadow_reasons;
  wire [35:0] shadow_data;
  wire [8:0] shadow_position;
  wire [74:0] shadow_metadata;
  integer completed_return_checks = 0, full_shadow_checks = 0;
  // Shadow receives the actual guard READY/capacity input, never an old reconstructed ACK.
  wire original_destination_ready = dut.result_guard.mailbox_input_ready;
  integer raw_ready_handoff_fault_cases = 0, raw_ready_differences = 0, late_ack_witnesses = 0;
  integer late_orphan_private_advances = 0;
  starlink_pss_realtime_result_guard shadow (
    .clk(fft_clk), .resetn(dut.fast_running), .job_valid(dut.job_valid), .job_ready(shadow_ready),
    .job_descriptor(REGISTERED_SCHEDULING ? dut.engine_metadata : dut.selected_metadata),
    .input_bank_reserved(!REGISTERED_SCHEDULING && dut.state == dut.WAIT_BANK ? dut.selected_valid : dut.engine_input_reserved),
    .output_bank_reserved(!REGISTERED_SCHEDULING && dut.state == dut.WAIT_BANK ? dut.destination_reserved : dut.engine_output_reserved),
    .certified_input_beat(dut.certified_input_beat), .certified_input_complete(dut.certified_input_complete),
    .final_fence_certified(dut.checked_input_complete && !dut.input_guard_fault && !dut.input_fault_now),
    // Shadow retains the prior RAW preflight veto. Only private ready/admit
    // may differ; reason accumulation and every public result stay exact.
    .external_fault_now(dut.external_fault_now || old_preflight_fault_now), .phase_input_fault_now(1'bz),
    .preflight_fault_evidence_now(1'bz),
    .completed_input_certified(1'bz), .completed_input_fault_now(1'bz),
    .core_event_frame_started(dut.event_frame), .core_output_tdata(dut.core_output_data),
    .core_output_tuser(dut.core_output_user), .core_output_tvalid(dut.core_output_valid),
    .core_output_tlast(dut.core_output_last), .core_status_tdata(dut.core_status_data),
    .core_status_tvalid(dut.core_status_valid), .mailbox_input_valid(shadow_valid),
    .mailbox_private_valid(shadow_private), .mailbox_commit_valid(shadow_commit_valid),
    .mailbox_input_ready(original_destination_ready),
    .mailbox_input_fault(dut.output_bank_fault || dut.output_bank_framing_fault_now),
    .mailbox_input_data(shadow_data), .mailbox_input_position(shadow_position),
    .mailbox_input_last(shadow_last), .mailbox_input_metadata(shadow_metadata),
    .busy(shadow_busy), .commit_pulse(shadow_commit), .protocol_fault(shadow_fault),
    .fault_reasons(shadow_reasons)
  );
  always @(posedge fft_clk or negedge fft_clk) begin
    #0.001;
    if (dut.fast_running) begin
      full_shadow_checks = full_shadow_checks + 1;
      if (dut.result_guard.awaiting_ack !== shadow.awaiting_ack)
        $fatal(1, "raw ownership readiness changed guard ACK-clear edge");
      if (dut.result_destination_ready !== original_destination_ready) begin
        raw_ready_differences = raw_ready_differences + 1;
        if (!dut.forward_committed || dut.result_guard.active || dut.result_guard.return_valid ||
            (!dut.result_guard.idle_fault_now && !dut.result_fault) ||
            (!shadow.idle_fault_now && !shadow_fault))
          $fatal(1, "raw/certified readiness differed outside fault-vetoed inactive handoff");
      end
      // Enabled actual ACK capacity is not the retained scheduler receipt.
      // The independent checked observer asserts each lifetime separately.
      if (dut.product_guard_ack_event !== checked_old_guard_ack)
        $fatal(1, "checked actual guard ACK differs from frozen port-fed guard");
      if (dut.job_ready !== shadow_ready) begin
        if (!REGISTERED_SCHEDULING || !dut.preparing || !old_preflight_fault_now ||
            !dut.job_ready || shadow_ready || dut.input_job_start || dut.source_read_ready ||
            dut.product_bank_read_ready || dut.config_valid || dut.return_private_valid ||
            dut.return_valid || dut.return_commit_valid)
          $fatal(1, "private preflight ready difference escaped unpublished phase");
        preflight_ready_differences = preflight_ready_differences + 1;
      end
      if ({dut.return_valid, dut.return_private_valid, dut.return_commit_valid,
           dut.result_busy, dut.result_commit, dut.result_fault, dut.result_guard.fault_reasons} !==
          {shadow_valid, shadow_private, shadow_commit_valid,
           shadow_busy, shadow_commit, shadow_fault, shadow_reasons})
        $fatal(1, "completed-input full shadow control/reasons mismatch");
      if (dut.return_private_valid &&
          {dut.return_data, dut.return_position, dut.return_last, dut.return_metadata} !==
          {shadow_data, shadow_position, shadow_last, shadow_metadata})
        $fatal(1, "completed-input full shadow private payload mismatch");
      if (dut.final_fence !== (dut.checked_input_complete && !dut.input_guard_fault && !dut.input_fault_now))
        $fatal(1, "completed-input fence differs from original same-edge fence");
      if (dut.result_guard.return_valid) begin
        completed_return_checks = completed_return_checks + 1;
        if (!dut.checked_input_complete || dut.input_guard.slot_open ||
            dut.result_guard.input_count != 512 || !dut.result_guard.input_complete_seen ||
            !dut.result_guard.frame_seen || !dut.result_guard.exponent_seen ||
            dut.certified_input_beat || dut.certified_input_complete || dut.handoff_fault_now ||
            dut.completed_input_fault_now !== dut.external_fault_now ||
            dut.result_guard.completed_return_fault_now !== dut.result_guard.fault_now ||
            dut.result_guard.completed_final_fault_now !== dut.result_guard.final_fault_now)
          $fatal(1, "completed-return phase invariant/predicate mismatch");
      end
    end
  end
  reg [31:0] samples [0:1405];
  reg [35:0] forwards [0:1535], products [0:1535], inverses [0:1535];
  reg [4:0] forward_exponents [0:2], inverse_exponents [0:2];
  reg [63:0] epoch_base = 64'h200000000;
  integer output_words = 0, published = 0, loaded = 0, consumed = 0;
  integer forward_jobs = 0, inverse_jobs = 0, delivered = 0, raw_words = 0;
  integer total_inverse = 0, total_forward = 0, total_products = 0, total_blocks = 0;
  integer fault_cases = 0, purge_cases = 0, overlapping_loads = 0, equality_witnesses = 0;
  integer completed_input_prefetch_witnesses = 0;
  integer held_final_ready_witnesses = 0;
  integer provisional_prefix_words = 0;
  integer active_fixture = 0, output_fixture = 0, trace, job_index, previous_admit = -1;
  integer max_forward_interval = 0, admission_cycle = 0, config_cycle = 0, first_core_output = 0;
  integer first_core_input = 0, last_core_input = 0, statuses = 0, frames = 0;
  integer held_core_reset_cycles = 0;
  integer scheduling_fault_cases = 0, scheduling_reset_cases = 0;
  integer snapshot_cycle = 0, max_snapshot_to_admission = 0;
  integer completion_capture_cycle = 0, completion_consumptions = 0;
  reg previous_completion_receipt = 0;
  reg [2:0] expected_epoch_input_reasons = 0;
  reg [5:0] expected_epoch_preflight_reasons = 0;
  integer preflight_ready_differences = 0, preflight_private_admits = 0;
  integer preflight_masked_starts = 0, preflight_matrix_cases = 0;
  integer preflight_phase, preflight_kind, preflight_when, preflight_inverse;
  reg [5:0] expected_preflight_mask = 0;
  reg [7:0] expected_preflight_guard_reasons = 0;
  reg [1:0] preflight_generations = 0;
  reg previous_core_resetn = 0;
  reg [7:0] injected_status = 0;
  integer n, test_kind, i, wait_count;
  real epoch_first_admit_ns = 0;

  always @(posedge fft_clk) begin
    if (!dut.fast_running) begin
      expected_epoch_input_reasons = 0; previous_completion_receipt = 0;
      expected_epoch_preflight_reasons = 0;
    end else if (REGISTERED_SCHEDULING) begin
      if (dut.epoch_input_reasons !== expected_epoch_input_reasons)
        $fatal(1, "private core reset lost exact epoch input reasons");
      expected_epoch_input_reasons = expected_epoch_input_reasons | dut.input_fault_events_now;
      if (dut.epoch_preflight_reasons !== expected_epoch_preflight_reasons)
        $fatal(1, "private reset lost exact preflight reasons");
      expected_epoch_preflight_reasons = expected_epoch_preflight_reasons | old_preflight_events_now;
      if (dut.state == dut.WAIT_BANK && dut.selected_valid && dut.destination_reserved)
        snapshot_cycle = fast_cycle;
      if (dut.job_accept) begin
        if (!dut.descriptor_certified) $fatal(1, "private admission without prior certificate");
        if (!dut.preparation_valid || dut.selected_lease != dut.held_lease) begin
          if (!dut.preparation_fault_now || !dut.preparing || shadow_ready ||
              dut.input_job_start || dut.config_valid || dut.source_read_ready || dut.product_bank_read_ready)
            $fatal(1, "bad private admission escaped preflight quarantine boundary");
          preflight_private_admits = preflight_private_admits + 1;
        end
        if (fast_cycle-snapshot_cycle > max_snapshot_to_admission)
          max_snapshot_to_admission = fast_cycle-snapshot_cycle;
      end
      if (dut.preparing && (dut.source_read_ready || dut.product_bank_read_ready))
        $fatal(1, "snapshot lease was consumed before registered admission");
      if (dut.completion_accept && !dut.completion_receipt) completion_capture_cycle = fast_cycle;
      if (dut.state == dut.ACK_DRAIN && dut.completion_receipt && !dut.registered_quarantine) begin
        if (!previous_completion_receipt || dut.result_busy || fast_cycle-completion_capture_cycle != 1)
          $fatal(1, "private phase released bank without actual registered completion");
        completion_consumptions = completion_consumptions + 1;
      end
      previous_completion_receipt = dut.completion_accept;
    end
    if (fast_cycle > 1500000) $fatal(1, "bank-owned bench watchdog");
    $fdisplay(trace, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
      fast_cycle, epoch, profile, dut.fast_running, dut.state, dut.core_aresetn,
      dut.job_accept, dut.config_valid && dut.config_ready, dut.next_inverse,
      dut.certified_input_beat, dut.core_output_valid, dut.core_status_valid,
      dut.return_commit_valid && dut.result_destination_ready,
      dut.forward_committed, dut.product_valid && dut.product_bank_ready && dut.product_last && dut.product_commit_authorized,
      dut.forward_handoff_ack, dut.result_busy, dut.source_valid, dut.source_ready,
      dut.product_bank_valid, dut.product_bank_read_ready, dut.output_bank_ready,
      dut.fast_fault, dut.engine_metadata[68:5]);
    if (!dut.fast_running) begin
      forward_jobs = 0; inverse_jobs = 0; delivered = 0; raw_words = 0; consumed = 0;
      previous_admit = -1; held_core_reset_cycles = 0; previous_core_resetn = 0;
    end else begin
      if (!dut.core_aresetn) held_core_reset_cycles = held_core_reset_cycles + 1;
      if (dut.core_aresetn && !previous_core_resetn) begin
        if (held_core_reset_cycles < 2) $fatal(1, "short core reset");
        held_core_reset_cycles = 0;
      end
      previous_core_resetn = dut.core_aresetn;
      if (!expected_fault && dut.fast_fault) $fatal(1, "unexpected fast fault epoch=%0d state=%0d", epoch, dut.state);
      if ((dut.joiner.input_valid && dut.kernel_ready) !==
          (dut.return_valid && !dut.next_inverse && !dut.fast_fault && dut.result_destination_ready))
        $fatal(1, "join acceptance differs from guard retirement");
      if (!expected_fault && dut.state == dut.RUN_JOB && !dut.next_inverse &&
          dut.checked_input_complete && dut.source_valid &&
          dut.source_metadata[68:5] != dut.engine_metadata[68:5]) begin
        completed_input_prefetch_witnesses = completed_input_prefetch_witnesses + 1;
        if (!dut.engine_input_enable || dut.core_input_valid || dut.certified_input_beat || dut.source_read_ready)
          $fatal(1, "prefetched N+1 was delivered into completed N input epoch");
      end
      if (injecting_readiness && !dut.product_bank_ready && dut.kernel_ready) begin
        equality_witnesses = equality_witnesses + 1;
        if (dut.joiner.input_valid) $fatal(1, "unretired return reached joiner");
      end
      if (!expected_fault && dut.result_guard.return_last && dut.result_guard.final_qualified &&
          !dut.next_inverse && !dut.product_bank_ready && dut.kernel_ready) begin
        held_final_ready_witnesses = held_final_ready_witnesses + 1;
        if (!dut.return_valid || dut.result_destination_ready || dut.joiner.input_valid || dut.forward_committed)
          $fatal(1, "held final escaped its actual guard retirement");
      end
      if (dut.job_accept) begin
        job_index = ((REGISTERED_SCHEDULING ? dut.engine_metadata[68:5] :
          dut.selected_metadata[68:5]) - epoch_base) / 447;
        active_fixture = job_index % 3;
        admission_cycle = fast_cycle;
        delivered = 0; raw_words = 0; statuses = 0; frames = 0;
        if (dut.next_inverse) begin
          inverse_jobs = inverse_jobs + 1;
          if (!dut.preparation_fault_now && (!dut.product_bank_valid || dut.product_bank_position != 0 ||
              dut.product_bank_metadata !== {1'b1, 64'(epoch_base+job_index*447), forward_exponents[active_fixture]})
            ) $fatal(1, "inverse admitted without validated owned product descriptor");
        end else begin
          if (profile == 0 && previous_admit >= 0 && fast_cycle-previous_admit > max_forward_interval)
            max_forward_interval = fast_cycle - previous_admit;
          $display("BANK_FORWARD_ADMIT epoch=%0d profile=%0d index=%0d fast_cycle=%0d time_ns=%0.6f interval_cycles=%0d",
            epoch, profile, job_index, fast_cycle, $realtime, previous_admit < 0 ? 0 : fast_cycle-previous_admit);
          previous_admit = fast_cycle;
          forward_jobs = forward_jobs + 1;
        end
      end
      if (dut.config_valid && dut.config_ready) config_cycle = fast_cycle;
      if (dut.certified_input_beat) begin
        if (delivered == 0) first_core_input = fast_cycle;
        last_core_input = fast_cycle;
        if (!expected_fault && dut.selected_data !== (dut.next_inverse ? products[active_fixture*512+delivered] :
            {samples[active_fixture*447+delivered][31:16], 2'b00, samples[active_fixture*447+delivered][15:0], 2'b00}))
          $fatal(1, "source/product bank input changed or reordered");
        delivered = delivered + 1;
      end
      if (dut.certified_input_complete && !dut.next_inverse) consumed = consumed + 1;
      if (dut.core_status_valid) statuses = statuses + 1;
      if (dut.event_frame) frames = frames + 1;
      if (dut.core_output_valid) begin
        if (raw_words == 0) first_core_output = fast_cycle;
        raw_words = raw_words + 1;
      end
      if (dut.return_valid && dut.result_destination_ready && !dut.next_inverse && !expected_fault) begin
        if (dut.return_data !== forwards[active_fixture*512+dut.return_position] ||
            dut.return_metadata[4:0] !== forward_exponents[active_fixture]) $fatal(1, "forward mismatch");
        total_forward = total_forward + 1;
      end
      if (dut.product_valid && dut.product_bank_ready && !expected_fault) begin
        if ({dut.product_q, dut.product_i} !== products[active_fixture*512+dut.product_position] ||
            dut.product_exponent !== forward_exponents[active_fixture]) $fatal(1, "product mismatch");
        total_products = total_products + 1;
      end
      if (dut.return_commit_valid && dut.result_destination_ready) begin
        if (delivered != 512 || raw_words != 512 || statuses != 1 || frames != 1 || !dut.final_fence)
          $fatal(1, "unqualified guard commit");
        if (expected_fault && dut.next_inverse && !allow_inverse_commit_before_late_fault)
          $fatal(1, "inverse commit escaped its planned current fault veto");
        $display("BANK_JOB epoch=%0d inverse=%0d admit=%0d config_delta=%0d input_span=%0d input_last_to_output_first=%0d commit_delta=%0d",
          epoch, dut.next_inverse, admission_cycle, config_cycle-admission_cycle,
          last_core_input-first_core_input+1, first_core_output-last_core_input, fast_cycle-admission_cycle);
      end
    end
  end
  always @(posedge fft_clk or negedge fft_clk) begin
    #0.001;
    if (REGISTERED_SCHEDULING && dut.fast_running && (|dut.epoch_preflight_reasons)) begin
      if (dut.input_job_start || dut.source_read_ready || dut.product_bank_read_ready ||
          dut.config_valid || dut.certified_input_beat || dut.return_valid ||
          dut.return_private_valid || dut.return_commit_valid || output_valid)
        $fatal(1, "preflight mismatch escaped emitted start/read/config/publication fence");
      if (dut.input_job_start_private) preflight_masked_starts = preflight_masked_starts + 1;
    end
  end
  always @(posedge clk) begin
    if (!dut.slow_running) begin loaded = 0; published = 0; output_words = 0; end
    else begin
      if (input_valid && input_ready) begin
        if (loaded > consumed) $fatal(1, "N+1 overwrote source bank while N still needed it");
        if (input_position == 0 && loaded > 0 && dut.core_aresetn) overlapping_loads = overlapping_loads + 1;
        if (input_position == 0)
          $display("BANK_CAPTURE_START epoch=%0d profile=%0d block=%0d time_ns=%0.6f", epoch, profile, loaded, $realtime);
        if (input_last) begin
          $display("BANK_CAPTURE_COMMIT epoch=%0d profile=%0d block=%0d time_ns=%0.6f", epoch, profile, loaded, $realtime);
          loaded = loaded + 1;
        end
      end
      if (output_valid && output_ready) begin
        output_fixture = ((output_metadata[73:10]-epoch_base) / 447) % 3;
        if (!expected_results || (expected_fault && !allow_provisional_prefix_after_fault) ||
            output_position != output_words || output_last != (output_words == 511) ||
            output_metadata !== {1'b1, 64'(epoch_base+published*447), forward_exponents[output_fixture], inverse_exponents[output_fixture]} ||
            output_data !== inverses[output_fixture*512+output_words]) $fatal(1, "inverse output mismatch/invalid publication");
        if (allow_provisional_prefix_after_fault && output_last)
          $fatal(1, "faulted provisional prefix became a complete block");
        total_inverse = total_inverse + 1;
        if (output_position == 0)
          $display("BANK_OUTPUT_START epoch=%0d profile=%0d block=%0d time_ns=%0.6f", epoch, profile, published, $realtime);
        if (output_last) begin
          output_words = 0; published = published + 1; total_blocks = total_blocks + 1;
          $display("BANK_OUTPUT epoch=%0d profile=%0d block=%0d time_ns=%0.6f", epoch, profile, published-1, $realtime);
        end else output_words = output_words + 1;
      end
    end
  end
  task automatic tick;
    @(posedge fft_clk); #0.001;
  endtask
  task automatic reset_epoch(input integer side);
    @(negedge clk); input_valid = 0;
    if (side != 2) resetn = 0;
    if (side != 1) fft_resetn = 0;
    repeat (20) tick();
    @(negedge clk); resetn = 1; fft_resetn = 1;
    epoch = epoch + 1; epoch_base = 64'h200000000 + 64'(epoch)*65536;
    repeat (20) tick();
    if (fault || output_valid || dut.result_busy || dut.product_bank_valid || dut.source_valid)
      $fatal(1, "reset leaked bank ownership/results");
    expected_fault = 0; expected_results = 1; reader_enable = 1;
    allow_inverse_commit_before_late_fault = 0;
    allow_provisional_prefix_after_fault = 0;
  endtask
  task automatic send_words(input integer index, input integer count);
    integer word_index, fixture;
    fixture = index % 3;
    for (word_index = 0; word_index < count; word_index = word_index + 1) begin
      @(negedge clk); input_valid = 1;
      input_block_start = epoch_base + index*447;
      input_position = word_index; input_last = word_index == 511;
      input_data = {samples[fixture*447+word_index][31:16], 2'b00, samples[fixture*447+word_index][15:0], 2'b00};
      @(posedge clk); while (!input_ready) @(posedge clk);
      if (profile == 1 && word_index % 13 == 0) begin
        @(negedge clk); input_valid = 0; repeat (3) @(posedge clk);
      end
    end
    @(negedge clk); input_valid = 0;
  endtask
  task automatic await_results(input integer count);
    integer timeout;
    timeout = 0;
    while ((published != count || dut.state != dut.WAIT_BANK || dut.next_inverse) && timeout < 25000) begin
      tick(); timeout = timeout + 1;
    end
    if (timeout == 25000 || fault) $fatal(1, "outputs/final real ACK failed to drain");
  endtask
  // Observe the same live pre-edge drain required by the complete CSV gate.
  // await_results may first see WAIT_BANK after NBA; do not reset before a
  // following live trace sample. The original 5215-clock service bound applies.
  task automatic checked_profile_drain(input integer count);
    reg observed;
    integer drain_cycle, service_cycles;
    observed = 0;
    while (!observed) begin
      @(posedge fft_clk);
      if (dut.fast_running !== 1'b1 || dut.fast_fault !== 1'b0 || fault !== 1'b0)
        $fatal(1, "CHECKED_PROFILE_DRAIN_RESET_OR_FAULT");
      drain_cycle = fast_cycle;
      service_cycles = drain_cycle - previous_admit;
      if (previous_admit < 0 || service_cycles <= 0 || service_cycles > 5215)
        $fatal(1, "CHECKED_PROFILE_DRAIN_SERVICE_BOUND");
      observed = published === count && dut.state === dut.WAIT_BANK &&
        dut.next_inverse === 1'b0 && dut.result_busy === 1'b0 &&
        dut.output_bank_ready === 1'b1;
      #0.001;
      if (dut.fast_running !== 1'b1 || dut.fast_fault !== 1'b0 || fault !== 1'b0)
        $fatal(1, "CHECKED_PROFILE_DRAIN_RESET_OR_FAULT");
    end
    $display("CHECKED_PROFILE_DRAIN_WITNESS profile=%0d count=%0d forward=%0d drain=%0d service=%0d",
      profile, count, previous_admit, drain_cycle, service_cycles);
  endtask
  task automatic await_fault;
    repeat (24) tick();
    if (!fault || !dut.fast_fault || output_valid || dut.state != dut.QUARANTINE)
      $fatal(1, "fault was not sticky/fail closed");
    repeat (32) tick();
    if (output_valid || dut.job_accept) $fatal(1, "quarantine leaked result/job");
    fault_cases = fault_cases + 1;
  endtask
  initial begin
    trace = $fopen("fft_bank_owned_trace.csv", "w");
    $fdisplay(trace, "cycle,epoch,profile,running,state,core_resetn,admit,config,inverse,core_input,core_output,status,guard_commit,forward_committed,product_commit,handoff_ack,result_busy,source_valid,source_ready,product_read_valid,product_read_ready,output_bank_ready,fault,block_start");
    $readmemh("samples_ci16.mem", samples); $readmemh("forward_q17.mem", forwards);
    $readmemh("product_q17.mem", products); $readmemh("inverse_q17.mem", inverses);
    $readmemh("forward_exponents.mem", forward_exponents); $readmemh("inverse_exponents.mem", inverse_exponents);
    reset_epoch(0);
    for (n = 0; n < (QUICK_MUTATION ? 0 : 32); n = n + 1) send_words(n, 512);
    await_results(QUICK_MUTATION ? 0 : 32);
    if (!QUICK_MUTATION) checked_profile_drain(32);
    profile = 1; reset_epoch(0);
    for (n = 0; n < (QUICK_MUTATION ? 0 : 6); n = n + 1) send_words(n, 512);
    await_results(QUICK_MUTATION ? 0 : 6);
    if (!QUICK_MUTATION) checked_profile_drain(6);
    profile = 0;
    // Partial capture, active forward, active inverse, and inverse ACK resets.
    for (test_kind = 0; test_kind < (QUICK_MUTATION ? 0 : 4); test_kind = test_kind + 1) begin
      reset_epoch(0); expected_results = 0;
      if (test_kind == 0) send_words(0, 128);
      else begin
        reader_enable = 0; send_words(0, 512);
        if (test_kind == 3) wait(dut.next_inverse && dut.result_guard.awaiting_ack);
        else begin
          wait(dut.certified_input_beat && dut.next_inverse == (test_kind == 2));
          repeat (128) tick();
        end
      end
      reset_epoch(test_kind % 2 + 1); purge_cases = purge_cases + 1;
      send_words(0, 512); await_results(1);
    end
    // Forward status absent: even an apparent product candidate cannot admit
    // an inverse; deliver the one delayed valid status, then recover exactly.
    reset_epoch(0); send_words(0, 512);
    wait(dut.config_valid && dut.config_ready);
    force dut.core_status_valid = 0;
    wait(dut.result_guard.output_count == 512);
    repeat (8) tick();
    force dut.product_bank_valid = 1;
    repeat (8) tick();
    if (dut.forward_committed || inverse_jobs || dut.next_inverse || dut.job_accept)
      $fatal(1, "inverse candidate bypassed missing forward status");
    release dut.product_bank_valid;
    // All preceding products have drained. Hold the actually qualified final
    // return with the bank unavailable while the real empty joiner can accept.
    // Removing only the joiner's product_bank_ready gate MUST fail equality.
    @(negedge fft_clk); force dut.product_bank_ready = 0;
    injected_status = {3'b0, forward_exponents[0]};
    force dut.core_status_data = injected_status; force dut.core_status_valid = 1;
    tick(); @(negedge fft_clk); release dut.core_status_data; release dut.core_status_valid;
    repeat (3) tick();
    if (!held_final_ready_witnesses || fault) $fatal(1, "missing healthy held-final readiness witness");
    @(negedge fft_clk); release dut.product_bank_ready;
    await_results(1);
    if (QUICK_MUTATION) $fatal(1, "join-gate mutation unexpectedly survived witness");
    // Current and late forward faults: immediately after guard commit and at
    // the actual product handoff; do not reset away the forward epoch.
    for (test_kind = 0; test_kind < 2; test_kind = test_kind + 1) begin
      reset_epoch(0); expected_fault = 1; expected_results = 0; send_words(0, 512);
      if (test_kind == 0) wait(dut.forward_committed);
      else wait(dut.checked_product_bank.actual_handoff);
      if (!dut.core_aresetn) $fatal(1, "forward epoch retired before ownership ACK");
      force dut.event_last_missing = 1;
      tick(); @(negedge fft_clk); release dut.event_last_missing;
      await_fault();
      if (inverse_jobs || !dut.core_aresetn) $fatal(1, "late forward fault was reset or admitted inverse");
    end
    // Product overflow flag, ordinal corruption, metadata mismatch.
    for (test_kind = 0; test_kind < 3; test_kind = test_kind + 1) begin
      reset_epoch(0); expected_fault = 1; expected_results = 0; send_words(0, 512);
      wait(dut.product_valid && dut.product_position == 64);
      if (test_kind == 0) force dut.product_overflow = 1;
      if (test_kind == 1) force dut.product_position = 9'd19;
      if (test_kind == 2) force dut.product_start = 64'hdeadbeef;
      tick(); @(negedge fft_clk);
      release dut.product_overflow; release dut.product_position; release dut.product_start;
      await_fault();
      if (dut.product_bank_valid || inverse_jobs) $fatal(1, "malformed product bank published");
    end
    // Missing active input and loss of reserved product-write readiness.
    reset_epoch(0); expected_fault = 1; expected_results = 0; send_words(0, 512);
    wait(dut.certified_input_beat); repeat (128) tick();
    // Inject the actual forward bank transport, not discovery-only mux wires.
    @(negedge fft_clk); force dut.source_valid = 0;
    repeat (2) tick(); release dut.source_valid; await_fault();
    reset_epoch(0); expected_fault = 1; expected_results = 0; send_words(0, 512);
    wait(dut.core_output_valid); @(negedge fft_clk);
    injecting_readiness = 1; force dut.product_bank_ready = 0;
    repeat (2) tick(); release dut.product_bank_ready; injecting_readiness = 0;
    await_fault();
    if (!equality_witnesses) $fatal(1, "missing product-not-ready/kernel-ready witness");
    // Inverse final commit veto and postcommit actual slow ACK fault.
    for (test_kind = 0; test_kind < 2; test_kind = test_kind + 1) begin
      reset_epoch(0); expected_fault = 1; expected_results = 0; reader_enable = 0; send_words(0, 512);
      allow_inverse_commit_before_late_fault = test_kind == 1;
      if (test_kind == 0) wait(dut.next_inverse && dut.return_commit_valid);
      else wait(dut.next_inverse && dut.result_guard.awaiting_ack);
      allow_inverse_commit_before_late_fault = 0;
      force dut.event_last_missing = 1;
      #0.001;
      if (test_kind == 0 && dut.return_commit_valid) $fatal(1, "inverse final fault missed current veto");
      tick(); @(negedge fft_clk); release dut.event_last_missing;
      await_fault();
    end
    // Some already accepted words cannot be retracted across a clock domain.
    // Keep the exact prefix provisional, permit the real sticky-fault crossing
    // to close validity, and prohibit a completed result or the queued N+1.
    reset_epoch(0); send_words(0, 512); send_words(1, 512);
    wait(output_words == 128);
    @(negedge fft_clk);
    expected_fault = 1; allow_provisional_prefix_after_fault = 1;
    $display("BANK_PREFIX_FAULT_INJECT fast_cycle=%0d slow_cycle=%0d accepted_words=%0d time_ns=%0.6f",
      fast_cycle, slow_cycle, output_words, $realtime);
    force dut.event_last_missing = 1;
    tick(); @(negedge fft_clk); release dut.event_last_missing;
    await_fault();
    provisional_prefix_words = output_words;
    if (published || forward_jobs != 1 || inverse_jobs != 1 || loaded != 2 ||
        provisional_prefix_words < 128 || provisional_prefix_words > 132)
      $fatal(1, "late prefix fault lost evidence, escaped CDC bound, or admitted queued N+1");
    $display("BANK_PREFIX_FAULT_QUARANTINED accepted_words=%0d complete_blocks=%0d queued_source_blocks=%0d",
      provisional_prefix_words, published, loaded-consumed);
    reset_epoch(0); send_words(0, 512); await_results(1);
    if (!overlapping_loads || !completed_input_prefetch_witnesses)
      $fatal(1, "no capture/prefetch N+1 with closed N input epoch observed");
    if (!completed_return_checks || !full_shadow_checks)
      $fatal(1, "no completed-input equivalence witnesses");
    $display("CHECKED_PORT_FED_GUARD_PASS return_checks=%0d full_shadow_checks=%0d",
      completed_return_checks, full_shadow_checks);
    $display("FFT_BANK_OWNED_SLICE_PASS fast_mhz=%0d healthy_blocks=%0d inverse_words=%0d forward_words=%0d product_words=%0d purge_cases=%0d fault_cases=%0d overlap_loads=%0d acceptance_equality_witnesses=%0d closed_input_prefetch_witnesses=%0d held_final_ready_witnesses=%0d provisional_prefix_words=%0d nominal_max_forward_interval_cycles=%0d",
      FAST_MHZ, total_blocks, total_inverse, total_forward, total_products, purge_cases,
      fault_cases, overlapping_loads, equality_witnesses, completed_input_prefetch_witnesses,
      held_final_ready_witnesses, provisional_prefix_words, max_forward_interval);
    // Additional raw-ready/certified-ACK tests follow the unchanged suite's
    // receipt. Any failure still fails the complete log gate; this separate
    // receipt does not redefine its original numerical/fault counters.
    for (test_kind = 0; test_kind < 11; test_kind = test_kind + 1) begin
      reset_epoch(0); expected_fault = 1; expected_results = 0; send_words(0, 512);
      wait(dut.checked_product_bank.actual_handoff);
      if (test_kind >= 7) begin
        wait(!dut.result_guard.awaiting_ack);
        if (dut.state != dut.ACK_DRAIN || !dut.core_aresetn)
          $fatal(1, "no late post-ACK/pre-controller-drain boundary");
        late_ack_witnesses = late_ack_witnesses + 1;
      end
      case (test_kind)
        0: force dut.product_head_metadata = 75'h123456789;
        1: force dut.product_bank_position = 9'd7;
        2: force dut.product_bank_last = 1;
        3: force dut.event_frame = 1;
        4: force dut.core_status_valid = 1;
        5: force dut.core_output_valid = 1;
        6: force dut.input_job_start = 1;
        7: force dut.event_last_missing = 1;
        8: force dut.event_frame = 1;
        9: force dut.core_status_valid = 1;
        10: force dut.core_output_valid = 1;
      endcase
      #0.001;
      if (test_kind < 7 && (dut.checked_product_bank.actual_handoff || dut.product_guard_ack_event))
        $fatal(1, "checked actual ACK missed current external/identity/orphan fault");
      if (dut.forward_handoff_ack && test_kind != 3 && test_kind != 4 && test_kind != 5 && test_kind < 8)
        $fatal(1, "certified handoff receipt missed current external/identity fault");
      tick(); @(negedge fft_clk);
      release dut.product_head_metadata; release dut.product_bank_position; release dut.product_bank_last;
      release dut.event_frame; release dut.core_status_valid; release dut.core_output_valid;
      release dut.input_job_start; release dut.event_last_missing;
      await_fault(); raw_ready_handoff_fault_cases = raw_ready_handoff_fault_cases + 1;
      if (inverse_jobs || (test_kind < 8 && !dut.core_aresetn))
        $fatal(1, "raw ownership admitted inverse or reset away handoff external fault");
      if (test_kind >= 8) begin
        // Baseline may advance private phase/reset on this controller edge:
        // current raw orphan faults are owned by the result guard, not the
        // wrapper's external_fault_now. Its full sticky reason bank survives
        // core reset and must quarantine before any inverse/new publication.
        if (!dut.result_fault || !dut.result_guard.fault_reasons || !dut.fast_fault)
          $fatal(1, "late orphan reason disappeared across private core reset");
        if (dut.next_inverse && !dut.core_aresetn)
          late_orphan_private_advances = late_orphan_private_advances + 1;
      end
    end
    // One-sided reset while valid product ownership is waiting for the forward
    // controller must purge the unpublished/owned state before healthy reuse.
    reset_epoch(0); expected_results = 0; send_words(0, 512); wait(dut.checked_product_bank.actual_handoff);
    reset_epoch(1); send_words(0, 512); await_results(1);
    if (raw_ready_handoff_fault_cases != 11 || !checked_capacity_receipts || late_ack_witnesses != 4)
      $fatal(1, "missing raw-ready/certified-ACK negative witnesses");
    $display("CHECKED_CAPACITY_ACTUAL_ACK_PASS handoff_fault_cases=%0d raw_ready_differences=%0d late_ack_witnesses=%0d late_orphan_private_advances=%0d handoff_reset_recovery=1 full_shadow_checks=%0d",
      raw_ready_handoff_fault_cases, raw_ready_differences, late_ack_witnesses,
      late_orphan_private_advances, full_shadow_checks);
    if (REGISTERED_SCHEDULING) begin
      // Snapshot, certificate capture, admission certificate consume, and
      // completion capture/consume each have a distinct current-fault witness.
      for (test_kind = 0; test_kind < 8; test_kind = test_kind + 1) begin
        reset_epoch(0); expected_fault = 1; expected_results = 0; send_words(0, 512);
        case (test_kind)
          0: begin wait(dut.state == dut.VERIFY_LEASE); force dut.source_metadata = 70'h123; end
          1: begin wait(dut.state == dut.VERIFY_LEASE); injected_preflight_lease = dut.held_lease ^ 2'b01;
            force dut.held_lease = injected_preflight_lease; end
          2: begin wait(dut.state == dut.ARM_JOB && !dut.admission_receipt); force dut.product_reservation = 0; end
          3: begin wait(dut.admission_receipt); force dut.source_metadata = 70'h456; end
          // First matching status is legal after guard admission, even before
          // the input frame. Reserved bits make this an actual current fault.
          4: begin wait(dut.admission_receipt); force dut.core_status_data = 8'h80;
            force dut.core_status_valid = 1; end
          5: begin wait(dut.completion_accept); force dut.event_last_missing = 1; end
          6: begin wait(dut.completion_receipt); force dut.event_frame = 1; end
          7: begin wait(dut.completion_receipt); force dut.input_job_start = 1; end
        endcase
        tick(); @(negedge fft_clk);
        release dut.source_metadata; release dut.held_lease; release dut.product_reservation;
        release dut.core_status_valid; release dut.core_status_data;
        release dut.event_last_missing; release dut.event_frame;
        release dut.input_job_start;
        await_fault(); scheduling_fault_cases = scheduling_fault_cases + 1;
        if (inverse_jobs || output_valid) $fatal(1, "scheduling boundary fault escaped to inverse/output");
      end
      for (test_kind = 0; test_kind < 4; test_kind = test_kind + 1) begin
        reset_epoch(0); expected_results = 0; send_words(0, 512);
        case (test_kind)
          0: wait(dut.state == dut.VERIFY_LEASE);
          1: wait(dut.descriptor_certified);
          2: wait(dut.admission_receipt);
          3: wait(dut.completion_receipt);
        endcase
        reset_epoch(test_kind % 2 + 1); scheduling_reset_cases = scheduling_reset_cases + 1;
        send_words(0, 512); await_results(1);
      end
      if (scheduling_fault_cases != 8 || scheduling_reset_cases != 4 ||
          max_snapshot_to_admission != 2 || !completion_consumptions)
        $fatal(1, "missing registered scheduling boundary/cadence witnesses");
      $display("REGISTERED_SCHEDULING_PASS boundary_fault_cases=%0d boundary_reset_cases=%0d snapshot_to_admission_cycles=%0d completion_receipt_consumptions=%0d nominal_max_forward_interval_cycles=%0d",
        scheduling_fault_cases, scheduling_reset_cases, max_snapshot_to_admission,
        completion_consumptions, max_forward_interval);
      // Both transform phases: each raw preflight cause, alone and combined,
      // at VERIFY, guard-admission capture, and admission-receipt consumption.
      // A matching first status is legal only after private guard admission;
      // the following cycle must classify it as orphan after any mismatch.
      for (preflight_inverse = 0; preflight_inverse < 2; preflight_inverse = preflight_inverse + 1)
      for (preflight_phase = 0; preflight_phase < 3; preflight_phase = preflight_phase + 1)
      for (preflight_kind = 0; preflight_kind < 7; preflight_kind = preflight_kind + 1)
      for (preflight_when = 0; preflight_when < 2; preflight_when = preflight_when + 1) begin
        reset_epoch(0); expected_fault = 1; expected_results = 0; send_words(0, 512);
        case (preflight_phase)
          0: wait(dut.state == dut.VERIFY_LEASE && dut.next_inverse == preflight_inverse);
          1: wait(dut.state == dut.ARM_JOB && !dut.admission_receipt && dut.next_inverse == preflight_inverse);
          2: wait(dut.admission_receipt && dut.next_inverse == preflight_inverse);
        endcase
        preflight_generations = {dut.product_consume_generation, dut.source_consume_generation};
        if(preflight_inverse)checked_begin_retained_watch();
        expected_preflight_mask = preflight_kind == 6 ? 6'h3f :
          (preflight_inverse && preflight_kind == 1 ? 6'h0a : 6'b1 << preflight_kind);
        // Corrupt the real bank tuple. Do not mutate ownership counters merely
        // to inject a bad lease: their no-consumption invariant must stay real.
        if (preflight_inverse) begin
          if (preflight_kind == 0 || preflight_kind == 6) force dut.product_bank_valid = 0;
          if (preflight_kind == 1 || preflight_kind == 6) force dut.product_bank_position = 7;
          if (preflight_kind == 3 || preflight_kind == 6) force dut.product_bank_metadata = 70'h123;
          if (preflight_kind == 4 || preflight_kind == 6) force dut.output_bank_ready = 0;
        end else begin
          if (preflight_kind == 0 || preflight_kind == 6) force dut.source_valid = 0;
          if (preflight_kind == 1 || preflight_kind == 6) force dut.source_position = 7;
          if (preflight_kind == 3 || preflight_kind == 6) force dut.source_metadata = 70'h123;
          if (preflight_kind == 4 || preflight_kind == 6) force dut.product_reservation = 0;
        end
        if (preflight_kind == 2 || preflight_kind == 6) begin
          injected_preflight_lease = dut.held_lease ^ 2'b01; force dut.held_lease = injected_preflight_lease;
        end
        if (preflight_kind == 5 || preflight_kind == 6) force dut.preparation_age = 63;
        if (preflight_when == 0) force dut.core_input_ready = 0;
        else force dut.core_input_ready = 1;
        expected_preflight_guard_reasons = preflight_when == 0 && preflight_phase != 2 ? 8'h11 : 8'h01;
        if (preflight_when == 0) begin
          force dut.core_status_data = 0; force dut.core_status_valid = 1;
        end
        #0.001;
        if (dut.preflight_events_now !== expected_preflight_mask)
          $fatal(1, "preflight raw detailed cause mismatch phase=%0d kind=%0d", preflight_phase, preflight_kind);
        tick();
        if (dut.epoch_preflight_reasons !== expected_preflight_mask ||
            dut.result_guard.fault_reasons !== expected_preflight_guard_reasons)
          $fatal(1, "preflight same-edge exact reason lost phase=%0d kind=%0d when=%0d actual=%h expected=%h",
            preflight_phase, preflight_kind, preflight_when, dut.result_guard.fault_reasons, expected_preflight_guard_reasons);
        @(negedge fft_clk);
        release dut.source_valid; release dut.source_position; release dut.source_metadata;
        release dut.product_bank_valid; release dut.product_bank_position; release dut.product_bank_metadata;
        release dut.held_lease; release dut.product_reservation; release dut.output_bank_ready;
        release dut.preparation_age; release dut.core_input_ready;
        release dut.core_status_valid; release dut.core_status_data;
        if (preflight_when == 1) begin
          force dut.core_status_data = 0; force dut.core_status_valid = 1;
        end
        tick();
        if (dut.result_guard.fault_reasons !== (preflight_when == 1 ? 8'h11 : expected_preflight_guard_reasons))
          $fatal(1, "preflight next-edge matching status was not preserved as orphan");
        @(negedge fft_clk); release dut.core_status_valid; release dut.core_status_data;
        await_fault();
        if ({dut.product_consume_generation, dut.source_consume_generation} !== preflight_generations)
          $fatal(1, "preflight fault changed consumption generations");
        if(preflight_inverse)begin
          checked_retained_owner();
          if(!dut.fast_fault || dut.state!=dut.QUARANTINE)
            $fatal(1,"checked retained bank missing quarantine");
        end else if(!dut.selected_valid || dut.selected_position!=0)
          $fatal(1, "preflight fault released/consumed the still-owned source bank");
        preflight_matrix_cases = preflight_matrix_cases + 1;
      end
      // A captured detailed reason is sticky across private core reset, and
      // both independent reset directions purge it before healthy reuse.
      for (preflight_when = 1; preflight_when <= 2; preflight_when = preflight_when + 1) begin
        if (preflight_when == 2) begin
          reset_epoch(0); expected_fault = 1; expected_results = 0; send_words(0, 512);
          wait(dut.state == dut.ARM_JOB && dut.admission_receipt);
          force dut.source_metadata = 70'h123; tick();
          @(negedge fft_clk); release dut.source_metadata; await_fault();
        end
        if (!(|dut.epoch_preflight_reasons)) $fatal(1, "missing preflight reason before reset");
        reset_epoch(preflight_when);
        if (dut.epoch_preflight_reasons || dut.epoch_input_reasons || dut.result_guard.fault_reasons)
          $fatal(1, "one-sided reset did not purge detailed reason epoch");
        send_words(0, 512); await_results(1);
      end
      if (preflight_matrix_cases != 84 || !preflight_ready_differences ||
          !preflight_private_admits || !preflight_masked_starts)
        $fatal(1, "missing preflight private-admit/start-mask matrix witnesses");
      $display("PREFLIGHT_REASON_SPLIT_PASS matrix_cases=%0d transform_phases=2 reason_bits=6 simultaneous_orphan_and_next_status=1 one_sided_fault_recoveries=2 private_ready_differences=%0d private_admits=%0d masked_start_samples=%0d exact_public_and_reason_shadow=1",
        preflight_matrix_cases, preflight_ready_differences, preflight_private_admits, preflight_masked_starts);
      // The second full identity comparison is required only for inverse.
      // Exercise its final bit at all three real scheduler boundaries, with
      // raw core readiness both low and high. Forward cache-only corruption
      // must remain ignored and recover through the normal forward capture.
      for (preflight_inverse = 0; preflight_inverse < 2; preflight_inverse = preflight_inverse + 1)
      for (preflight_phase = 0; preflight_phase < 3; preflight_phase = preflight_phase + 1)
      for (preflight_when = 0; preflight_when < 2; preflight_when = preflight_when + 1) begin
        reset_epoch(0); expected_fault = preflight_inverse;
        expected_results = preflight_inverse ? 0 : 1; send_words(0, 512);
        case (preflight_phase)
          0: wait(dut.state == dut.VERIFY_LEASE && dut.next_inverse == preflight_inverse);
          1: wait(dut.state == dut.ARM_JOB && !dut.admission_receipt && dut.next_inverse == preflight_inverse);
          2: wait(dut.admission_receipt && dut.next_inverse == preflight_inverse);
        endcase
        preflight_generations = {dut.product_consume_generation, dut.source_consume_generation};
        if(preflight_inverse)checked_begin_retained_watch();
        injected_expected_product = dut.expected_product_metadata ^ (70'b1 << 69);
        force dut.expected_product_metadata = injected_expected_product;
        if (preflight_when == 0) force dut.core_input_ready = 0;
        else force dut.core_input_ready = 1;
        #0.001;
        if (dut.preflight_events_now !== (preflight_inverse ? 6'b001000 : 6'b0))
          $fatal(1, "expected-product comparison lost phase qualification");
        tick();
        if (preflight_inverse && (dut.epoch_preflight_reasons !== 6'b001000 ||
            dut.input_job_start || dut.config_valid || dut.source_read_ready || dut.product_bank_read_ready ||
            dut.return_valid || dut.return_private_valid || dut.return_commit_valid))
          $fatal(1, "inverse expected-cache mismatch escaped same-edge epoch quarantine");
        @(negedge fft_clk); release dut.expected_product_metadata; release dut.core_input_ready;
        if (preflight_inverse) begin
          await_fault();
          if ({dut.product_consume_generation, dut.source_consume_generation} !== preflight_generations)
            $fatal(1, "expected-cache mismatch changed consumption generations");
          checked_retained_owner();
          if(!dut.fast_fault || dut.state!=dut.QUARANTINE)
            $fatal(1, "expected-cache mismatch lost retained quarantine");
        end else await_results(1);
        cache_phase_cases = cache_phase_cases + 1;
      end
    end
    // Same12 phase/kind/readiness cases; inverse targets the real raw offered
    // tuple before staged GOOD. Source checks below are the literal old body.
    for (active_inverse = 0; active_inverse < 2; active_inverse = active_inverse + 1)
    for (active_kind = 0; active_kind < 3; active_kind = active_kind + 1)
    for (active_ready = 0; active_ready < 2; active_ready = active_ready + 1) begin
      reset_epoch(0); expected_fault = 1; expected_results = 0; send_words(0, 512);
      if(active_inverse)begin
        wait(dut.checked_product_bank.adapter.reader.raw_valid &&
             dut.checked_product_bank.adapter.reader.raw_position==37);
        @(negedge fft_clk);
        if(active_ready==0)force dut.core_input_ready=0;
        else force dut.core_input_ready=1;
        if(active_kind==0)force dut.checked_product_bank.adapter.reader.raw_metadata=75'h123;
        if(active_kind==1)force dut.checked_product_bank.adapter.reader.raw_position=9'd7;
        if(active_kind==2)force dut.checked_product_bank.adapter.reader.raw_last=1;
        // Offered-word evidence includes a stalled/not-taken word. The
        // independent observer forbids delivery of this nominal word37.
        repeat(4)tick();
        if(dut.checked_product_bank.reader_reasons[3:0] !==
           (active_kind==0 ? 4'h4 : active_kind==1 ? 4'h1 : 4'h2) ||
           dut.checked_product_bank.core_take || dut.return_commit_valid ||
           checked_core_index>37)
          $fatal(1,"checked inverse offered corruption lost verdict or escaped");
        @(negedge fft_clk);release dut.core_input_ready;
        release dut.checked_product_bank.adapter.reader.raw_metadata;
        release dut.checked_product_bank.adapter.reader.raw_position;
        release dut.checked_product_bank.adapter.reader.raw_last;
      end else begin
      wait(dut.state == dut.RUN_JOB && dut.next_inverse == active_inverse && dut.input_guard.expected_position == 37);
      @(negedge fft_clk);
      if (active_ready == 0) force dut.core_input_ready = 0;
      else force dut.core_input_ready = 1;
      if (active_inverse) begin
        if (active_kind == 0) force dut.product_bank_metadata = 70'h123;
        if (active_kind == 1) force dut.product_bank_position = 9'd7;
        if (active_kind == 2) force dut.product_bank_last = 1;
      end else begin
        if (active_kind == 0) force dut.source_metadata = 70'h123;
        if (active_kind == 1) force dut.source_position = 9'd7;
        if (active_kind == 2) force dut.source_last = 1;
      end
      #0.001;
      if (!dut.input_fault_now || dut.input_fault_events_now !== (active_ready ? 3'b011 : 3'b010) ||
          dut.certified_input_beat || dut.certified_input_complete || dut.core_input_valid || dut.return_commit_valid)
        $fatal(1, "active identity/position/TLAST did not veto same edge");
      tick();
      if (dut.input_guard.fault_reasons !== (active_ready ? 3'b011 : 3'b010))
        $fatal(1, "active corruption lost exact framing/delivery reasons");
      @(negedge fft_clk);
      release dut.core_input_ready; release dut.product_bank_metadata; release dut.product_bank_position;
      release dut.product_bank_last; release dut.source_metadata; release dut.source_position; release dut.source_last;
      end
      await_fault(); active_fault_cases = active_fault_cases + 1;
    end
    // Vendor-only quarantine can leave the input checker slot open. Hold raw
    // ready low so it does not add a delivery fault before this premise check.
    for (active_inverse = 0; active_inverse < 2; active_inverse = active_inverse + 1) begin
      reset_epoch(0); expected_fault = 1; expected_results = 0; send_words(0, 512);
      wait(dut.state == dut.RUN_JOB && dut.next_inverse == active_inverse && dut.input_guard.expected_position == 37);
      @(negedge fft_clk); force dut.core_input_ready = 0; force dut.event_last_missing = 1;
      repeat (4) tick();
      if (dut.state != dut.QUARANTINE || !dut.input_guard.slot_open)
        $fatal(1, "missing vendor-quarantine open-slot witness");
      @(negedge fft_clk); release dut.core_input_ready; release dut.event_last_missing; await_fault();
    end
    reset_epoch(1); send_words(0, 512); await_results(1);
    reset_epoch(2); send_words(0, 512); await_results(1);
    if (active_fault_cases != 12 || !input_shadow_checks || !input_open_checks || !input_quarantine_open_checks)
      $fatal(1, "missing held-phase input tuple/active fault evidence");
    $display("CHECKED_INPUT_PHASE_PASS registered=%0d active_fault_cases=12 vendor_open_quarantine_cases=2 reset_recoveries=2 input_shadow_checks=%0d full_open_tuple_checks=%0d quarantine_open_checks=%0d exact_certified_and_bank_reads=1", REGISTERED_SCHEDULING,
      input_shadow_checks, input_open_checks, input_quarantine_open_checks);
    if (dut.input_guard.BALANCED_IDENTITY_EQ != REGISTERED_SCHEDULING || old_input_guard.BALANCED_IDENTITY_EQ != 0)
      $fatal(1, "balanced identity actual/reference parameter mismatch");
    $display("CHECKED_SOURCE_IDENTITY_ACTUAL_PASS enabled=%0d legacy_input_shadow_checks=%0d exact_per_beat_fault_reasons=1", REGISTERED_SCHEDULING, input_shadow_checks);
    if (!preflight_cause_checks || (REGISTERED_SCHEDULING && (!preflight_tuple_checks || cache_phase_cases != 12)))
      $fatal(1, "missing held-preflight current-cause/cache qualification evidence");
    $display("CHECKED_PREFLIGHT_ACTUAL_PASS registered=%0d global_current_cause_checks=%0d preparing_tuple_checks=%0d expected_cache_cases=%0d raw_bank_boundary_rows=%0d independent_old_reason_shadow=1", REGISTERED_SCHEDULING,
      preflight_cause_checks, preflight_tuple_checks, cache_phase_cases, preflight_matrix_cases);
    // BEGIN PAYLOAD_BUBBLE_RECEIPT
    if (dut.joiner.PRIVATE_PAYLOAD_BUBBLES != REGISTERED_SCHEDULING ||
        dut.product.PRIVATE_PAYLOAD_BUBBLES != REGISTERED_SCHEDULING ||
        dut.joiner.kernel_rom.BALANCED_BLOCK_IDENTITY_EQ != REGISTERED_SCHEDULING ||
        !payload_checks || !payload_join_occupied || !payload_product_occupied)
      $fatal(1, "missing data-only payload/ROM actual parameter or occupied-payload evidence");
    $display("PAYLOAD_BUBBLES_ACTUAL_PASS registered=%0d checks=%0d join_occupied=%0d product_occupied=%0d invalid_join=%0d invalid_product=%0d frozen_old_chain=1 logical_retirement_unchanged=1",REGISTERED_SCHEDULING,
      payload_checks,payload_join_occupied,payload_product_occupied,payload_join_invalid,payload_product_invalid);
    // END PAYLOAD_BUBBLE_RECEIPT
    // BEGIN FORWARD_RETIREMENT_RECEIPT
    if (dut.result_guard.USE_FORWARD_RETIREMENT != REGISTERED_SCHEDULING ||
        !forward_checks || !forward_cycles)
      $fatal(1, "missing frozen forward-retirement actual evidence");
    $display("FORWARD_RETIREMENT_ACTUAL_PASS registered=%0d checks=%0d forward=%0d inverse_current=%0d sticky_forward=%0d all_old_outputs_literal=1 frozen_old_guard_chain=1",REGISTERED_SCHEDULING,
      forward_checks, forward_cycles, forward_current, forward_sticky);
    // END FORWARD_RETIREMENT_RECEIPT
    $fclose(trace);
    if(EXACT_EXTRA_EPOCHS)begin
      trace=$fopen("exact_control_extra_trace.csv","w");
      exact_control_extra_epochs();
    end else $fatal(1,"checked actual requires original extra epochs");
    #0.003;
    fault_cdc_verify_terminal();
    rom_verify_terminal();
    checked_actual_verify_terminal();
    $fclose(trace); $finish;
  end
  // Raw217 diagnostics retained in immutable original and disabled control.
  // Enabled status is checked by frozen actual-input guard/ROM shadows; no retimed raw217 comparison.
endmodule
