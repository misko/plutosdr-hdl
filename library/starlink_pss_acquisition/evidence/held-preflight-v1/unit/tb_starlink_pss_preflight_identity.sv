// Fast extracted-RTL predicate comparison. NO FFT or numerical receiver model.
`timescale 1ns/1ps
module tb_starlink_pss_preflight_identity;
  parameter integer REGISTERED_MODE = 1;
  reg [3:0] state;
  reg held_phase, next_inverse, fast_running, source_valid, product_bank_valid;
  reg [35:0] source_data, product_bank_data;
  reg [8:0] source_position, product_bank_position;
  reg source_last, product_bank_last, source_consume_generation, product_consume_generation;
  reg [69:0] source_metadata, product_bank_metadata, engine_metadata, expected_product_metadata;
  reg held_lease, destination_reserved;
  reg [5:0] preparation_age;
  integer phase, boundary, ready_case, family, bit_index, mask, idle_state;
  integer bit_rows = 0, cause_rows = 0, idle_rows = 0, private_idle_differences = 0;
  reg [5:0] expected_causes;
  preflight_candidate #(.REGISTERED_SCHEDULING(REGISTERED_MODE)) dut (.*);
  preflight_reference #(.REGISTERED_SCHEDULING(REGISTERED_MODE)) reference_guard (.*);
  task automatic baseline;
    state = boundary == 0 ? 9 : 10; held_phase = phase; next_inverse = phase; fast_running = 1;
    source_valid = 1; product_bank_valid = 1; source_data = 36'h123456789; product_bank_data = 36'habcdef012;
    source_position = 0; product_bank_position = 0; source_last = 0; product_bank_last = 0;
    source_consume_generation = 0; product_consume_generation = 1; held_lease = phase;
    source_metadata = {1'b0, 64'h123456789abcdef0, 5'b0};
    product_bank_metadata = {1'b1, 64'h123456789abcdef0, 5'b0};
    engine_metadata = phase ? product_bank_metadata : source_metadata;
    expected_product_metadata = engine_metadata; destination_reserved = ready_case; preparation_age = 0;
  endtask
  task automatic compare;
    #1;
    if ({dut.preflight_events_now, dut.preparation_fault_now, dut.descriptor_header_valid} !==
        {reference_guard.preflight_events_now, reference_guard.preparation_fault_now,
         reference_guard.descriptor_header_valid})
      $fatal(1, "PREFLIGHT_PREDICATE_MISMATCH family=%0d phase=%0d bit=%0d boundary=%0d ready=%0d new=%h old=%h",
        family, phase, bit_index, boundary, ready_case, dut.preflight_events_now, reference_guard.preflight_events_now);
    if (dut.preflight_events_now !== (REGISTERED_MODE ? expected_causes : 6'b0))
      $fatal(1, "preflight predicate expected-cause mismatch");
    if (dut.preparing) begin
      if ({dut.preflight_phase, dut.preflight_valid, dut.preflight_data, dut.preflight_position,
           dut.preflight_last, dut.preflight_metadata, dut.preflight_lease, dut.preparation_valid} !==
          {reference_guard.selected_phase, reference_guard.selected_valid, reference_guard.selected_data,
           reference_guard.selected_position, reference_guard.selected_last, reference_guard.selected_metadata,
           reference_guard.selected_lease, reference_guard.preparation_valid})
        $fatal(1, "preparing tuple/lease/predicate mismatch");
    end else if (dut.preparation_valid !== reference_guard.preparation_valid) begin
      if (!REGISTERED_MODE || dut.preparation_fault_now) $fatal(1, "idle private predicate escaped");
      private_idle_differences = private_idle_differences + 1;
    end
  endtask
  initial begin
    for (phase = 0; phase < 2; phase = phase + 1)
    for (boundary = 0; boundary < 3; boundary = boundary + 1)
    for (ready_case = 0; ready_case < 2; ready_case = ready_case + 1)
    for (family = 0; family < 3; family = family + 1)
    for (bit_index = 0; bit_index < 70; bit_index = bit_index + 1) begin
      baseline(); expected_causes = ready_case ? 0 : 6'b010000;
      if (family == 0) begin
        if (phase) product_bank_metadata = engine_metadata ^ (70'b1 << bit_index);
        else source_metadata = engine_metadata ^ (70'b1 << bit_index);
        expected_causes[3] = 1;
      end else if (family == 1) begin
        expected_product_metadata = engine_metadata ^ (70'b1 << bit_index);
        expected_causes[3] = phase;
      end else begin
        // Coherent bank/engine corruption isolates phase and forward low5
        // header requirements from bank identity (inverse cache still binds).
        engine_metadata = engine_metadata ^ (70'b1 << bit_index);
        if (phase) product_bank_metadata = engine_metadata;
        else source_metadata = engine_metadata;
        expected_causes[3] = phase || bit_index < 5 || bit_index == 69;
      end
      compare(); bit_rows = bit_rows + 1;
    end
    for (phase = 0; phase < 2; phase = phase + 1)
    for (boundary = 0; boundary < 3; boundary = boundary + 1)
    for (mask = 0; mask < 64; mask = mask + 1) begin
      ready_case = 1; baseline(); expected_causes = mask;
      if (mask & 1) begin if (phase) product_bank_valid = 0; else source_valid = 0; end
      if (mask & 2) begin if (phase) product_bank_position = 7; else source_position = 7; end
      if (mask & 4) begin if (phase) product_consume_generation = 0; else source_consume_generation = 1; end
      if (mask & 8) begin if (phase) product_bank_metadata = ~engine_metadata; else source_metadata = ~engine_metadata; end
      if (mask & 16) destination_reserved = 0;
      if (mask & 32) preparation_age = 63;
      compare(); cause_rows = cause_rows + 1;
    end
    for (phase = 0; phase < 2; phase = phase + 1)
    for (boundary = 0; boundary < 3; boundary = boundary + 1)
    for (ready_case = 0; ready_case < 2; ready_case = ready_case + 1) begin
      baseline(); if (phase) product_bank_last = 1; else source_last = 1;
      expected_causes = ready_case ? 6'b000010 : 6'b010010; compare(); cause_rows = cause_rows + 1;
    end
    for (phase = 0; phase < 2; phase = phase + 1)
    for (idle_state = 0; idle_state < 9; idle_state = idle_state + 1) begin
      ready_case = 1; baseline(); state = idle_state; next_inverse = !held_phase;
      expected_causes = 0; compare(); idle_rows = idle_rows + 1;
      fast_running = 0; compare(); idle_rows = idle_rows + 1;
    end
    if (bit_rows != 2520 || cause_rows != 396 || idle_rows != 36 || (REGISTERED_MODE && !private_idle_differences))
      $fatal(1, "preflight predicate coverage incomplete");
    $display("PREFLIGHT_PREDICATE_PASS registered=%0d bit_rows=2520 cause_rows=396 idle_rows=36 private_idle_differences=%0d both70bit_comparisons=1 phase_low5_header=1 extracted_live_rtl_no_fft=1", REGISTERED_MODE, private_idle_differences);
    $finish;
  end
endmodule
