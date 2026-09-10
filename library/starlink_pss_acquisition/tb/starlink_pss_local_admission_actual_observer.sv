`timescale 1ns/1fs
// Test-only literal-original observer. Inputs are DUT guard INPUT PORTS,
// never DUT eligibility/certificate predicates. No stimulus or force here.
module starlink_pss_local_admission_actual_observer #(
  parameter integer L = 0
) (
  input wire clk, resetn, job_start,
  input wire [69:0] job_descriptor,
  input wire input_enable, input_valid,
  input wire [35:0] input_data,
  input wire [8:0] input_position,
  input wire input_last,
  input wire [69:0] input_metadata,
  input wire core_input_tready,
  input wire [154:0] actual_view
);
`define LOCAL_GUARD_PORTS .clk(clk), .resetn(resetn), .job_start(job_start), \
  .job_descriptor(job_descriptor), .input_enable(input_enable), .input_valid(input_valid), \
  .input_data(input_data), .input_position(input_position), .input_last(input_last), \
  .input_metadata(input_metadata), .core_input_tready(core_input_tready)
  local_admission_original_guard #(.CHECK_INPUT_BLOCK_IDENTITY(1),
    .BALANCED_IDENTITY_EQ(1)) original_guard (`LOCAL_GUARD_PORTS);
  // Deliberately omit the new option: exercise its actual default, not L=0 wiring.
  starlink_pss_realtime_input_guard_local_admission #(.CHECK_INPUT_BLOCK_IDENTITY(1),
    .BALANCED_IDENTITY_EQ(1)) default_guard (`LOCAL_GUARD_PORTS);
`undef LOCAL_GUARD_PORTS
`define LOCAL_GUARD_VIEW(g) {g.input_ready,g.input_transport_ready,g.core_input_tdata, \
  g.core_input_tvalid,g.core_input_tlast,g.certified_input_beat,g.certified_input_complete, \
  g.input_complete,g.fault_now,g.duplicate_start_fault_now,g.fault_events_now, \
  g.protocol_fault,g.fault_reasons,g.job_started,g.input_started,g.descriptor,g.expected_position, \
  g.slot_open,g.eligible,g.metadata_valid,g.identity_matches,g.errors_now, \
  g.framing_error,g.delivery_error,g.duplicate_start}
  wire [154:0] original_view = `LOCAL_GUARD_VIEW(original_guard);
  wire [154:0] default_view = `LOCAL_GUARD_VIEW(default_guard);
  integer pre_checks=0, post_checks=0, reset_checks=0;
  integer forward_starts=0, inverse_starts=0, current_faults=0, sticky_faults=0;
  integer completed_checks=0, closed_prefetch=0, duplicate_checks=0;
  task compare(input integer phase);
    begin
      if (actual_view !== original_view || default_view !== original_view) begin
        $display("LOCAL_GUARD_COMPARISON phase=%0d time=%0t actual=%039h original=%039h default=%039h resetn=%b start=%b descriptor=%018h input_metadata=%018h position=%03h",
          phase,$time,actual_view,original_view,default_view,resetn,job_start,job_descriptor,input_metadata,input_position);
        $fatal(1,"LOCAL_GUARD_UNCONDITIONAL_STATE_OUTPUT_MISMATCH");
      end
    end
  endtask
  initial begin
    if ((L !== 0 && L !== 1) || default_guard.LOCAL_FIRST_ADMISSION !== 0 ||
        $bits(`LOCAL_GUARD_VIEW(original_guard)) != 155)
      $fatal(1,"LOCAL_GUARD_OBSERVER_BINDING_MISMATCH");
  end
  // No valid/reset/fault/phase masks: both edges before and after NBA settlement.
  always @(posedge clk or negedge clk) begin
    #0; compare(0); pre_checks=pre_checks+1;
    #0.001; compare(1); post_checks=post_checks+1;
  end
  always @(negedge resetn) begin
    #0; compare(2);
    #0.001; compare(3); reset_checks=reset_checks+1;
  end
  always @(posedge clk) begin
    if (resetn && job_start && !original_guard.job_started) begin
      if (job_descriptor[69]) inverse_starts=inverse_starts+1;
      else forward_starts=forward_starts+1;
    end
    if (original_guard.fault_now) current_faults=current_faults+1;
    if (original_guard.protocol_fault) sticky_faults=sticky_faults+1;
    if (original_guard.input_complete) completed_checks=completed_checks+1;
    if (original_guard.input_complete && input_valid) closed_prefetch=closed_prefetch+1;
    if (original_guard.duplicate_start_fault_now) duplicate_checks=duplicate_checks+1;
  end
  task final_receipt;
    begin
      compare(4);
      if (pre_checks < 1024 || post_checks < 1024 || !reset_checks ||
          forward_starts < 38 || inverse_starts < 38 || !current_faults || !sticky_faults ||
          !completed_checks || !closed_prefetch || !duplicate_checks)
        $fatal(1,"LOCAL_GUARD_INCOMPLETE_FULLSUITE_OBSERVATION");
      $display("LOCAL_ADMISSION_ACTUAL_PASS L=%0d R=1 B=1 O=1 width=155 pre_checks=%0d post_checks=%0d reset_checks=%0d forward_starts=%0d inverse_starts=%0d current_faults=%0d sticky_faults=%0d completed_checks=%0d closed_prefetch=%0d duplicate_checks=%0d full_unconditional_state_outputs=1 original_guard_literal=1 default_omitted=1 added_latency=0",
        L,pre_checks,post_checks,reset_checks,forward_starts,inverse_starts,current_faults,sticky_faults,completed_checks,closed_prefetch,duplicate_checks);
    end
  endtask
`undef LOCAL_GUARD_VIEW
endmodule
