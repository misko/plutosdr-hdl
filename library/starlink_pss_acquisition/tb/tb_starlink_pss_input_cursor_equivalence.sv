// Existing public stimulus plus immutable input-checker reference. No private
// state is deposited: the only private observation counts fault-edge witnesses.
`timescale 1ns/1ps
module tb_starlink_pss_input_cursor_equivalence #(
  parameter integer CHECK_IDENTITY = 1
);
  tb_starlink_pss_realtime_input_guard #(.CHECK_IDENTITY(CHECK_IDENTITY)) stimulus();
  wire ready, transport_ready, core_valid, core_last, beat, complete_pulse;
  wire complete, fault_now, fault;
  wire [47:0] core_data;
  wire [2:0] reasons;
  starlink_pss_realtime_input_guard_0a1af893_golden #(
    .CHECK_INPUT_BLOCK_IDENTITY(CHECK_IDENTITY)) golden (
    .clk(stimulus.clk), .resetn(stimulus.resetn), .job_start(stimulus.job_start),
    .job_descriptor(stimulus.job_descriptor), .input_enable(stimulus.input_enable),
    .input_valid(stimulus.input_valid), .input_ready(ready),
    .input_transport_ready(transport_ready), .input_data(stimulus.input_data),
    .input_position(stimulus.input_position), .input_last(stimulus.input_last),
    .input_metadata(stimulus.input_metadata), .core_input_tdata(core_data),
    .core_input_tvalid(core_valid), .core_input_tready(stimulus.core_ready),
    .core_input_tlast(core_last), .certified_input_beat(beat),
    .certified_input_complete(complete_pulse), .input_complete(complete),
    .fault_now(fault_now), .protocol_fault(fault), .fault_reasons(reasons)
  );
  integer comparisons = 0, private_fault_rows = 0;
  always @(posedge stimulus.clk or negedge stimulus.clk) begin
    #0.2;
    comparisons = comparisons + 1;
    if ({ready, transport_ready, core_valid, core_last, beat, complete_pulse,
         complete, fault_now, fault, core_data, reasons} !==
        {stimulus.ready, stimulus.transport_ready, stimulus.core_valid,
         stimulus.core_last, stimulus.beat, stimulus.complete_pulse, stimulus.complete,
         stimulus.fault_now, stimulus.fault, stimulus.core_data, stimulus.reasons})
      $fatal(1, "INPUT_CURSOR_PUBLIC_MISMATCH time=%0t", $time);
    if (stimulus.resetn && stimulus.dut.expected_position !== golden.expected_position) begin
      private_fault_rows = private_fault_rows + 1;
      if (!fault || !stimulus.fault || ready || transport_ready || beat || complete_pulse)
        $fatal(1, "INPUT_CURSOR_PRIVATE_DIFFERENCE_ESCAPED");
    end
  end
  final begin
    if (comparisons < 10000 || private_fault_rows < 10)
      $fatal(1, "INPUT_CURSOR_COVERAGE_MISSING");
    $display("INPUT_CURSOR_EQ_PASS identity=%0d public_comparisons=%0d private_fault_rows=%0d no_internal_deposits=1",
      CHECK_IDENTITY, comparisons, private_fault_rows);
  end
endmodule
