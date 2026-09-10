module preflight_reference #(parameter integer REGISTERED_SCHEDULING = 1) (input wire [3:0] state,
  input wire held_phase, next_inverse, fast_running, source_valid, product_bank_valid,
  input wire [35:0] source_data, product_bank_data,
  input wire [8:0] source_position, product_bank_position,
  input wire source_last, product_bank_last, source_consume_generation, product_consume_generation,
  input wire [69:0] source_metadata, product_bank_metadata, engine_metadata, expected_product_metadata,
  input wire held_lease, destination_reserved,
  input wire [5:0] preparation_age);
localparam [3:0] RESET0=0, RESET1=1, WAIT_BANK=2, INPUT_ADMIT=3,
    CONFIGURE=4, ENABLE_INPUT=5, RUN_JOB=6, ACK_DRAIN=7, QUARANTINE=8,
    VERIFY_LEASE=9, ARM_JOB=10;
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
  wire descriptor_header_valid = engine_metadata[69] == held_phase &&
    (held_phase ? engine_metadata == expected_product_metadata : engine_metadata[4:0] == 0);
  wire preparation_valid = selected_valid && selected_position == 0 && !selected_last &&
    selected_lease == held_lease && selected_metadata == engine_metadata &&
    descriptor_header_valid && destination_reserved;
  // Bit order: timeout, destination, descriptor/header, lease, framing, owner.
  wire [5:0] preflight_events_now = REGISTERED_SCHEDULING && fast_running && preparing ?
    {preparation_age == 63, !destination_reserved,
     (selected_metadata != engine_metadata || !descriptor_header_valid),
     (selected_lease != held_lease), (selected_position != 0 || selected_last),
     !selected_valid} : 6'b0;
  wire preparation_fault_now = |preflight_events_now;
endmodule
