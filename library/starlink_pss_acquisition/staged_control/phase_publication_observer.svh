// Original full publication authorization, independent of the reduced fault view.
wire phase_original_accept =
 (dut.REPLAY_QUIET_PUBLICATION === 0) ?
 (dut.output_replay_valid && dut.output_descriptor_valid &&
  dut.output_bank_ready && dut.output_stage_final_valid && !dut.common_current_fault) :
 ((dut.REPLAY_QUIET_PUBLICATION === 1 && dut.REPLAY_FENCE_PROFILE) ?
 (dut.output_replay_valid && dut.output_descriptor_valid &&
  dut.output_bank_ready && dut.output_stage_final_valid &&
  dut.replay_publication_context && !dut.replay_publication_fault) : 1'b0);
integer phase_checks=0,phase_accepts=0,phase_preflight=0,phase_differences=0;
task check_phase_publication;
begin
  if(dut.output_replay_accept !== phase_original_accept)
    $fatal(1,"publication original predicate mismatch");
  if(dut.REPLAY_QUIET_PUBLICATION === 1 && dut.REPLAY_FENCE_PROFILE)begin
    // Never mirror or suppress this comparison, including deliberate output vetoes.
    if((dut.replay_publication_context && !dut.replay_publication_fault) !==
       (dut.replay_publication_context && !dut.replay_phase_fault))
      $fatal(1,"publication unforced phase predicate mismatch");
    if(dut.preparing === 1'b1 && dut.preparation_fault_now === 1'b1)
      phase_preflight=phase_preflight+1;
    if(dut.replay_publication_fault !== dut.replay_phase_fault)
      phase_differences=phase_differences+1;
  end
  phase_checks=phase_checks+1;
end
endtask
always @(posedge fft_clk)begin
  check_phase_publication;
  if(dut.output_replay_accept === 1'b1)phase_accepts=phase_accepts+1;
  #0.001;check_phase_publication;
end
task report_phase_publication;
begin
  $display("PHASE_PUBLICATION_PASS checks=%0d accepts=%0d preflight=%0d fault_differences=%0d exact=1",
    phase_checks,phase_accepts,phase_preflight,phase_differences);
end
endtask

