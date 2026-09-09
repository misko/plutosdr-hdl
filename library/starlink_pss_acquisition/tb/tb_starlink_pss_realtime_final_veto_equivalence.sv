// SPDX-License-Identifier: GPL-2.0
// TEST ONLY: conditional algebra against the real result guard, not a service.
// Baseline: HDL 2e552234336a5426adcecb538f5da5ced844b7d1 (fault tree unchanged
// from ff4229). No golden or runtime module is modified. Hierarchical deposits
// below deliberately establish active/final-qualified/held-last state while
// clk is stopped. They do NOT prove reachability, caller certificates, a vendor
// event-latency bound, physical timing, or complete mailbox transactions.
`timescale 1ns/1ps
module tb_starlink_pss_realtime_final_veto_equivalence;
  parameter integer WATCHDOG_CYCLES = 5;
  // Mutation-only control: omit exactly one predicate term; -1 is unmutated.
  parameter integer OMIT_VETO = -1;
  localparam integer AGE_WIDTH = $clog2(WATCHDOG_CYCLES);
  reg clk = 0, resetn = 0, job_valid = 0;
  reg [69:0] job_descriptor = 0;
  reg input_bank_reserved = 1, output_bank_reserved = 1;
  reg certified_input_beat = 0, certified_input_complete = 0;
  reg final_fence_certified = 1, external_fault_now = 0;
  reg core_event_frame_started = 0;
  reg [47:0] core_output_tdata = 0;
  reg [23:0] core_output_tuser = 0;
  reg core_output_tvalid = 0, core_output_tlast = 0;
  reg [7:0] core_status_tdata = 0;
  reg core_status_tvalid = 0;
  reg mailbox_input_ready = 1, mailbox_input_fault = 0;
  wire job_ready, mailbox_input_valid, mailbox_input_last, busy;
  wire commit_pulse, protocol_fault;
  wire [35:0] mailbox_input_data;
  wire [8:0] mailbox_input_position;
  wire [74:0] mailbox_input_metadata;
  wire [7:0] fault_reasons;
  starlink_pss_realtime_result_guard #(.WATCHDOG_CYCLES(WATCHDOG_CYCLES)) dut (
    .mailbox_private_valid(), .*);

  wire [8:0] final_veto_terms = {
    dut.watchdog_error, core_output_tvalid, core_status_tvalid,
    core_event_frame_started, certified_input_complete, certified_input_beat,
    !output_bank_reserved, mailbox_input_fault, external_fault_now};
  wire [8:0] omission_mask = OMIT_VETO < 0 ? 9'b0 : (9'b1 << OMIT_VETO);
  wire proposed_final_fault = |(final_veto_terms & ~omission_mask);
  wire proposed_final_valid = resetn && dut.active && !protocol_fault &&
    dut.return_valid && dut.return_last && dut.final_qualified && !proposed_final_fault;
  wire proposed_final_commit = proposed_final_valid && mailbox_input_ready;
  integer rows = 0, edges = 0, mutation_witnesses = 0, boundaries = 0;
  integer exponent, events, gates, bit_index;
  reg [8:0] event_bits;
  reg [7:0] expected_reasons;
  reg [8:0] mutation_seen = 0;
  reg expected_commit;

  task automatic configure_events(input integer event_number);
    begin
      event_bits = event_number;
      external_fault_now = event_bits[0];
      mailbox_input_fault = event_bits[1];
      output_bank_reserved = !event_bits[2];
      certified_input_beat = event_bits[3];
      certified_input_complete = event_bits[4];
      core_event_frame_started = event_bits[5];
      core_status_tvalid = event_bits[6];
      core_output_tvalid = event_bits[7];
      expected_reasons = {event_bits[8], event_bits[7], event_bits[7],
        event_bits[6], event_bits[5], event_bits[4] || event_bits[3],
        event_bits[2], event_bits[1] || event_bits[0]};
    end
  endtask

  task automatic deposit_final_state(input integer exponent_value,
      input integer event_number, input integer gate_number);
    begin
      // Direct testbench deposits, never synthesis inputs or runtime forces.
      // The stopped clock prevents a race with the guard's sequential block.
      if (clk !== 0 || resetn !== 1) $fatal(1, "FINAL_VETO_BAD_DEPOSIT_PHASE");
      configure_events(event_number);
      input_bank_reserved = gate_number[0]; // irrelevant after certified input completion
      mailbox_input_ready = gate_number[1]; // must affect commit, not held-final valid
      job_valid = gate_number[3]; // must not admit/reuse an active result
      final_fence_certified = 1;
      dut.active = 1;
      dut.awaiting_ack = 0;
      dut.descriptor = {6'b101010, 64'h0123456789abcdef};
      dut.input_count = 512;
      dut.output_count = 512;
      dut.input_complete_seen = 1;
      dut.frame_seen = 1;
      dut.status_seen = 1;
      dut.exponent_seen = 1;
      dut.status_exponent = exponent_value;
      dut.output_exponent = exponent_value;
      dut.age = event_bits[8] ? WATCHDOG_CYCLES - 1 : WATCHDOG_CYCLES - 2;
      dut.return_valid = 1;
      dut.return_last = 1;
      dut.return_position = 511;
      dut.return_exponent = exponent_value;
      dut.return_data = 36'h987654321;
      dut.commit_pulse = 0;
      dut.fault_reasons = gate_number[2] ? 8'h24 : 8'h00;
      // Exercise every legal held exponent, both TLASTs, and valid/malformed
      // live output/status payloads. In this phase ANY new raw event is fatal,
      // irrespective of matching index, padding, exponent or sample values.
      core_output_tdata = {16'hface, 16'hcafe, 16'hb00c} ^ event_number;
      core_output_tlast = exponent_value[0] ^ event_number[0];
      case (event_number[1:0])
        0: begin core_output_tuser = {3'b0, exponent_value[4:0], 7'b0, 9'd511};
                 core_status_tdata = {3'b0, exponent_value[4:0]}; end
        1: begin core_output_tuser = 24'hffffff; core_status_tdata = 8'hff; end
        2: begin core_output_tuser = 0; core_status_tdata = 0; end
        3: begin core_output_tuser = 24'h13579b ^ (event_number << 9);
                 core_status_tdata = 8'h5a ^ exponent_value; end
      endcase
    end
  endtask

  task automatic check_conditioned_row;
    begin
      if (!(dut.active && dut.final_qualified && dut.return_valid && dut.return_last))
        $fatal(1, "FINAL_VETO_MISSING_PREMISE");
      if (dut.faults_now !== expected_reasons)
        $fatal(1, "FINAL_VETO_REASON_MISMATCH events=%h actual=%h expected=%h",
          event_bits, dut.faults_now, expected_reasons);
      if (dut.fault_now !== proposed_final_fault)
        $fatal(1, "FINAL_VETO_EQ_MISMATCH omit=%0d events=%h actual=%b proposed=%b",
          OMIT_VETO, event_bits, dut.fault_now, proposed_final_fault);
      if (mailbox_input_valid !== proposed_final_valid ||
          dut.final_commit !== proposed_final_commit || job_ready !== 0)
        $fatal(1, "FINAL_VETO_PUBLIC_MISMATCH events=%h", event_bits);
      if (mailbox_input_valid && (mailbox_input_data !== 36'h987654321 ||
          mailbox_input_position !== 511 || mailbox_input_last !== 1 ||
          mailbox_input_metadata !== {dut.descriptor, dut.return_exponent}))
        $fatal(1, "FINAL_VETO_PAYLOAD_CHANGED");
      rows = rows + 1;
    end
  endtask

  initial begin
    if (OMIT_VETO < -1 || OMIT_VETO > 8) $fatal(1, "FINAL_VETO_BAD_MUTATION");
    #1; resetn = 1; #1;
    // 32 exponents x every nine-event combination x four independent gates.
    // 262,144 actual-RTL rows; no randomized sampling of veto combinations.
    for (exponent = 0; exponent < 32; exponent = exponent + 1)
      for (events = 0; events < 512; events = events + 1)
        for (gates = 0; gates < 16; gates = gates + 1) begin
          deposit_final_state(exponent, events, gates);
          #1; check_conditioned_row();
          if (gates == 3 && exponent == 0)
            for (bit_index = 0; bit_index < 9; bit_index = bit_index + 1)
              if (event_bits == (9'b1 << bit_index) && dut.fault_now &&
                  !(|(final_veto_terms & ~(9'b1 << bit_index)))) begin
                mutation_seen[bit_index] = 1;
                mutation_witnesses = mutation_witnesses + 1;
              end
        end
    if (mutation_seen !== 9'h1ff || mutation_witnesses != 9)
      $fatal(1, "FINAL_VETO_MUTATION_COVERAGE_MISSING seen=%h", mutation_seen);

    // At actual sequential edges, all 511 nonempty event sets must veto that
    // edge and latch their exact fault reasons; the empty set commits once.
    for (events = 0; events < 512; events = events + 1) begin
      deposit_final_state(events % 32, events, 3);
      #1; check_conditioned_row();
      expected_commit = events == 0;
      clk = 1; #1;
      if (commit_pulse !== expected_commit || fault_reasons !== expected_reasons ||
          dut.active !== 0 || dut.return_valid !== 0 ||
          dut.awaiting_ack !== expected_commit)
        $fatal(1, "FINAL_VETO_EDGE_MISMATCH events=%h commit=%b reasons=%h",
          event_bits, commit_pulse, fault_reasons);
      edges = edges + 1;
      clk = 0; #1;
    end

    // Missing qualification is NOT covered by the reduced-fault identity.
    // Independently ensure every necessary final-publication premise gates it.
    for (bit_index = 0; bit_index < 10; bit_index = bit_index + 1) begin
      deposit_final_state(7, 0, 3);
      case (bit_index)
        0: dut.input_count = 511;
        1: dut.output_count = 511;
        2: dut.input_complete_seen = 0;
        3: dut.frame_seen = 0;
        4: dut.exponent_seen = 0;
        5: dut.status_seen = 0;
        6: dut.status_exponent = 8;
        7: final_fence_certified = 0;
        8: dut.active = 0;
        9: dut.return_valid = 0;
      endcase
      #1;
      if (mailbox_input_valid !== 0 || dut.final_commit !== 0)
        $fatal(1, "FINAL_VETO_BOUNDARY_ESCAPED premise=%0d", bit_index);
      boundaries = boundaries + 1;
    end
    // Check a real asynchronous reset, not a fabricated qualified reset state.
    deposit_final_state(31, 0, 3);
    #1; resetn = 0; #1;
    if (mailbox_input_valid !== 0 || commit_pulse !== 0 || busy !== 0 ||
        protocol_fault !== 0 || dut.return_valid !== 0)
      $fatal(1, "FINAL_VETO_RESET_ESCAPED");
    $display("FINAL_VETO_EQ_PASS watchdog=%0d rows=%0d edges=%0d mutation_witnesses=%0d boundaries=%0d reset=1",
      WATCHDOG_CYCLES, rows, edges, mutation_witnesses, boundaries);
    $finish;
  end
endmodule
