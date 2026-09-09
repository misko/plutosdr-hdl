// TEST ONLY: private register capture plus exact count equality, not FFT timing.
// Reuse the unchanged adversarial real-mailbox stimulus. Private data may
// change on its first fault edge; no validity, commit or reuse may escape.
`timescale 1ns/1ps

module realtime_effective_input_full_truth(output reg done = 0);
  reg clk = 0, resetn = 0, certified_input_beat = 0;
  starlink_pss_realtime_result_guard dut (
    .clk(clk), .resetn(resetn), .job_valid(1'b0), .job_descriptor(70'b0),
    .input_bank_reserved(1'b1), .output_bank_reserved(1'b1),
    .certified_input_beat(certified_input_beat), .certified_input_complete(1'b0),
    .final_fence_certified(1'b0), .external_fault_now(1'b0),
    .core_event_frame_started(1'b0), .core_output_tdata(48'b0),
    .core_output_tuser(24'b0), .core_output_tvalid(1'b0), .core_output_tlast(1'b0),
    .core_status_tdata(8'b0), .core_status_tvalid(1'b0),
    .mailbox_input_ready(1'b1), .mailbox_input_fault(1'b0)
  );
  integer count, beat, rows = 0;
  reg [9:0] count_bits;
  reg [10:0] old_sum;
  initial begin
    // Stopped-clock deposits enumerate the predicate's complete binary domain;
    // they do not assert that every deposited count is reachable in a job.
    #0.01; resetn = 1;
    for (count = 0; count < 1024; count = count + 1)
      for (beat = 0; beat < 2; beat = beat + 1) begin
        count_bits = 10'(count);
        dut.input_count = count_bits;
        certified_input_beat = 1'(beat);
        old_sum = {1'b0, count_bits} + {10'b0, certified_input_beat};
        #0.001;
        if (dut.effective_input_full !== (old_sum == 11'd512))
          $fatal(1, "EFFECTIVE_INPUT_FULL_MISMATCH count=%0d beat=%0d old_sum=%0d",
            count, beat, old_sum);
        rows = rows + 1;
      end
    if (rows != 2048) $fatal(1, "EFFECTIVE_INPUT_FULL_INCOMPLETE");
    done = 1;
    $display("EFFECTIVE_INPUT_FULL_PASS rows=2048 binary_domain_only=1");
  end
endmodule

module tb_starlink_pss_realtime_private_return_payload;
  parameter real SLOW_HALF_NS = 5.0;
  parameter real SLOW_PHASE_NS = 1.3;
  tb_starlink_pss_realtime_result_guard #(
    .SLOW_HALF_NS(SLOW_HALF_NS), .SLOW_PHASE_NS(SLOW_PHASE_NS)
  ) stimulus();
  wire truth_done;
  realtime_effective_input_full_truth count_truth(truth_done);

  wire [50:0] private_payload = {
    stimulus.dut.return_data, stimulus.dut.return_position,
    stimulus.dut.return_last, stimulus.dut.return_exponent};
  reg [50:0] before_payload, arriving_payload, fault_payload;
  reg capture_edge, new_fault_capture, already_poisoned, in_fault_epoch = 0;
  reg [7:0] expected_reasons;
  reg mailbox_toggle_before;
  integer capture_edges = 0, fault_capture_edges = 0;
  integer changed_fault_payloads = 0, quarantine_edges = 0, fault_reset_epochs = 0;
  reg [7:0] captured_fault_classes = 0;

  always @(posedge stimulus.clk) begin
    // Sample the exact sequential predicates before any nonblocking updates.
    before_payload = private_payload;
    arriving_payload = {stimulus.core_output_tdata[41:24],
      stimulus.core_output_tdata[17:0], stimulus.core_output_tuser[8:0],
      stimulus.core_output_tlast, stimulus.core_output_tuser[20:16]};
    capture_edge = stimulus.resetn && stimulus.dut.active &&
      !stimulus.protocol_fault && stimulus.core_output_tvalid;
    new_fault_capture = capture_edge && stimulus.dut.fault_now;
    already_poisoned = in_fault_epoch;
    expected_reasons = stimulus.fault_reasons | stimulus.dut.faults_now;
    mailbox_toggle_before = stimulus.mailbox.request_toggle;
    #0.001;
    if (!stimulus.resetn) begin
      if (private_payload !== 51'b0 || stimulus.dut.return_valid !== 0 ||
          stimulus.protocol_fault !== 0 || stimulus.commit_pulse !== 0)
        $fatal(1, "PRIVATE_RETURN_RESET_NOT_PURGED");
      if (in_fault_epoch) fault_reset_epochs = fault_reset_epochs + 1;
      in_fault_epoch = 0;
    end else begin
      if (capture_edge) begin
        if (private_payload !== arriving_payload)
          $fatal(1, "PRIVATE_RETURN_CAPTURE_MISMATCH fault=%b expected=%h got=%h",
            new_fault_capture, arriving_payload, private_payload);
        capture_edges = capture_edges + 1;
      end else if (private_payload !== before_payload)
        $fatal(1, "PRIVATE_RETURN_CHANGED_WITHOUT_CAPTURE");
      if (new_fault_capture) begin
        if (stimulus.dut.return_valid !== 0 || stimulus.protocol_fault !== 1 ||
            stimulus.commit_pulse !== 0 || stimulus.guard_valid !== 0 ||
            stimulus.job_ready !== 0 || stimulus.dut.active !== 0 ||
            stimulus.fault_reasons !== expected_reasons ||
            stimulus.mailbox.request_toggle !== mailbox_toggle_before)
          $fatal(1, "PRIVATE_RETURN_FAULT_EDGE_ESCAPED");
        fault_capture_edges = fault_capture_edges + 1;
        if (private_payload !== before_payload)
          changed_fault_payloads = changed_fault_payloads + 1;
        captured_fault_classes = captured_fault_classes | expected_reasons;
        fault_payload = arriving_payload;
        in_fault_epoch = 1;
      end
      if (already_poisoned) begin
        if (private_payload !== fault_payload || stimulus.dut.return_valid !== 0 ||
            stimulus.protocol_fault !== 1 || stimulus.commit_pulse !== 0 ||
            stimulus.guard_valid !== 0 || stimulus.job_ready !== 0 ||
            stimulus.dut.active !== 0 || stimulus.output_valid !== 0)
          $fatal(1, "PRIVATE_RETURN_QUARANTINE_ESCAPED");
        quarantine_edges = quarantine_edges + 1;
      end
    end
  end

  final begin
    if (!truth_done || stimulus.healthy != 23 || stimulus.rejected != 37 ||
        stimulus.reset_cases != 12 || capture_edges != 25882 ||
        fault_capture_edges != 21 || changed_fault_payloads != 21 ||
        fault_reset_epochs != 21 || quarantine_edges != 504 ||
        (captured_fault_classes & 8'h61) !== 8'h61)
      $fatal(1, "PRIVATE_RETURN_COVERAGE_INCOMPLETE captures=%0d faults=%0d changed=%0d resets=%0d quarantine=%0d classes=%h",
        capture_edges, fault_capture_edges, changed_fault_payloads,
        fault_reset_epochs, quarantine_edges, captured_fault_classes);
    else
      $display("PRIVATE_RETURN_PAYLOAD_PASS fault_captures=%0d changed_fault_payloads=%0d reset_epochs=%0d legacy_healthy=23 legacy_rejected=37 independent_resets=12 real_mailbox=1 quarantine_edges=%0d capture_edges=%0d",
        fault_capture_edges, changed_fault_payloads, fault_reset_epochs,
        quarantine_edges, capture_edges);
  end
endmodule
