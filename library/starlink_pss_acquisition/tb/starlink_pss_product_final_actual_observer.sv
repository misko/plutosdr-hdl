// Observation only: no output drives either implementation.
`timescale 1ns/1fs
module starlink_pss_product_final_actual_observer (
  input wire clk, in_running, input_accept, input_framing_valid,
  input wire [8:0] write_position,
  input wire old_authorized, new_authorized, forward_committed,
  input wire slot_open, checked_complete, inverse_phase, guard_phase,
  input wire input_fault_now, duplicate_start, handoff_fault_now,
  input wire request_toggle, acknowledge_stage1, reading, read_valid,
  input wire public_ready, public_valid, fast_running, current_fault, core_resetn,
  input wire output_ready,
  output integer pre_checks=0, post_checks=0, sampled=0, authorized=0,
  output integer vetoed=0, unknown_authorization=0, malformed_final=0,
  output integer nonsampled_differences=0, closed_samples=0, reset_samples=0,
  output integer inverse_owned=0, owned_stalls=0, current_fault_edges=0,
  output integer private_reset_samples=0, public_overlap=0
);
  reg expected_toggle, sampled_this_edge;
  always @(posedge clk) begin
    // Settle active-region force/port propagation, without crossing NBA.
    #0;
    pre_checks=pre_checks+1;
    expected_toggle=request_toggle;
    sampled_this_edge=0;
    // Deliberately literal procedural nesting. In particular unknown framing
    // takes the ELSE branch, and unknown !in_running does not take reset.
    if (!in_running) begin
      expected_toggle=0;
      reset_samples=reset_samples+1;
    end else if (input_accept) begin
      if (!input_framing_valid) begin
        if (write_position == 511) malformed_final=malformed_final+1;
      end else if (write_position == 511) begin
        sampled_this_edge=1;
        sampled=sampled+1;
        // Never skip this comparison for forced states, X framing, faults,
        // phase, or forward qualification. This is the sampled interface.
        if (new_authorized !== old_authorized)
          $fatal(1,"PRODUCT_FINAL_ACTUAL_SAMPLED_AUTHORIZATION_MISMATCH old=%b new=%b",old_authorized,new_authorized);
        if (old_authorized) expected_toggle=!request_toggle;
        if (old_authorized === 1'b1) authorized=authorized+1;
        else if (old_authorized === 1'b0) vetoed=vetoed+1;
        else unknown_authorization=unknown_authorization+1;
        // Natural ownership uses unforced INTERNAL toggle/read state, not
        // public valid/ready aliases that old malformed-state tests force.
        if (request_toggle !== acknowledge_stage1 || reading !== 1'b0 || read_valid !== 1'b0)
          $fatal(1,"PRODUCT_FINAL_ACTUAL_INTERNAL_OWNERSHIP_BROKEN");
        if (forward_committed === 1'b1) begin
          closed_samples=closed_samples+1;
          if (slot_open !== 1'b0 || checked_complete !== 1'b1 ||
              inverse_phase !== 1'b0 || guard_phase !== 1'b0 ||
              input_fault_now !== duplicate_start || handoff_fault_now !== 1'b0)
            $fatal(1,"PRODUCT_FINAL_ACTUAL_CLOSED_INPUT_PHASE_BROKEN");
        end
      end
    end
    if (!sampled_this_edge && new_authorized !== old_authorized)
      nonsampled_differences=nonsampled_differences+1;
    // Diagnostic only: existing stimulus intentionally forces public aliases.
    // This counter does not disable any sampled comparison or publication test.
    if (public_ready === 1'b1 && public_valid === 1'b1) public_overlap=public_overlap+1;
    if (fast_running === 1'b1 && inverse_phase === 1'b1 && read_valid === 1'b1)
      inverse_owned=inverse_owned+1;
    if (read_valid === 1'b1 && output_ready === 1'b0) owned_stalls=owned_stalls+1;
    if (fast_running === 1'b1 && current_fault === 1'b1) current_fault_edges=current_fault_edges+1;
    if (fast_running === 1'b1 && core_resetn === 1'b0) private_reset_samples=private_reset_samples+1;
    #0.001; #0;
    if (request_toggle !== expected_toggle)
      $fatal(1,"PRODUCT_FINAL_ACTUAL_OLD_PUBLICATION_TRANSITION_MISMATCH expected=%b actual=%b",expected_toggle,request_toggle);
    post_checks=post_checks+1;
  end
  task verify_terminal(input integer enabled);
    begin
      if (pre_checks <= 0 || post_checks != pre_checks || sampled <= 0 ||
          authorized <= 0 || closed_samples <= 0 || reset_samples <= 0 ||
          inverse_owned <= 0 || owned_stalls <= 0 || current_fault_edges < 2 || private_reset_samples <= 0 ||
          sampled != authorized+vetoed+unknown_authorization)
        $fatal(1,"PRODUCT_FINAL_ACTUAL_COVERAGE_INCOMPLETE");
      $display("PRODUCT_FINAL_FENCE_ACTUAL_PASS enabled=%0d pre=%0d post=%0d sampled=%0d authorized=%0d vetoed=%0d unknown=%0d malformed=%0d nonsampled_private=%0d closed=%0d resets=%0d inverse_owned=%0d owned_stalls=%0d current_faults=%0d private_reset=%0d public_overlap=%0d source=real_controller old_public_shadow=unchanged_dec20 qualified_status_only=1",
        enabled,pre_checks,post_checks,sampled,authorized,vetoed,unknown_authorization,
        malformed_final,nonsampled_differences,closed_samples,reset_samples,inverse_owned,
        owned_stalls,current_fault_edges,private_reset_samples,public_overlap);
    end
  endtask
endmodule
