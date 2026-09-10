// Read-only candidate witnesses. No DUT writes, feedback, masks or new stimulus.
integer candidate_jobs=0,candidate_finals=0,candidate_pre=0,candidate_post=0;
integer candidate_public=0;
reg candidate_admit_before,candidate_inverse_before;
reg[69:0] candidate_descriptor_before;
integer candidate_cycle_before,candidate_context_before;
initial begin
  #0.001;
  if(dut.PRIVATE_DESCRIPTOR_OFFER!==1 || dut.CLOSED_INPUT_CUTOVER!==1 ||
     dut.retained.island.PRIVATE_DESCRIPTOR_OFFER!==1 ||
     dut.retained.island.CLOSED_INPUT_CUTOVER!==1)
    $fatal(1,"candidate option readback");
  $display("RCAND_FLAGS private_offer=1 closed_input=1 wrapper_private=1 wrapper_closed=1");
end
task automatic candidate_closed_check(input integer post_edge);
  begin
    if(dut.retained.island.fast_running===1'b1 &&
       dut.retained.island.checked_input_complete===1'b1)begin
      if({dut.retained.island.certified_input_beat,
          dut.retained.island.certified_input_complete}!==2'b0)
        $fatal(1,"candidate closed input strobe premise");
      if(dut.retained.island.cutover.closed_input_fault_now!==dut.retained.island.cutover.fault_now ||
         candidate_original_completed_input_fault!==dut.retained.island.completed_input_fault_now)
        $fatal(1,"candidate full original predicate differs on closed use");
      if(post_edge)candidate_post=candidate_post+1;else candidate_pre=candidate_pre+1;
    end
    if(dut.retained.island.fast_running===1'b1 &&
       (|{dut.retained.island.guard_valid_out,dut.retained.island.guard_commit_out,
          dut.retained.island.forward_retirement_valid})===1'b1)begin
      if(dut.retained.island.checked_input_complete!==1'b1 ||
         candidate_original_completed_input_fault!==1'b0)
        $fatal(1,"candidate public return lacked original full authority");
      if(!post_edge)candidate_public=candidate_public+1;
    end
  end
endtask
always @(posedge fft_clk)begin
  #0; // Same inactive, pre-NBA observation region as the frozen physical-input witness.
  candidate_closed_check(0);
  candidate_admit_before=dut.retained.island.fast_running===1'b1 &&
    dut.retained.island.job_accept===1'b1;
  candidate_inverse_before=dut.retained.island.next_inverse;
  candidate_descriptor_before=dut.retained.island.engine_metadata;
  candidate_cycle_before=fast_cycles;candidate_context_before=context_id;
  if(candidate_admit_before)begin
    if(candidate_inverse_before!==1'b0 && candidate_inverse_before!==1'b1)
      $fatal(1,"candidate accepted unknown phase");
    candidate_jobs=candidate_jobs+1;
    if(candidate_inverse_before)begin
      if(dut.retained.island.owners[1].result_guard.private_descriptor_offer!==1'b1 ||
         dut.retained.island.owners[1].result_guard.job_descriptor!==candidate_descriptor_before)
        $fatal(1,"candidate accepted inverse private offer/descriptor");
    end else begin
      if(dut.retained.island.owners[0].result_guard.private_descriptor_offer!==1'b1 ||
         dut.retained.island.owners[0].result_guard.job_descriptor!==candidate_descriptor_before)
        $fatal(1,"candidate accepted forward private offer/descriptor");
    end
  end
  if(dut.retained.island.fast_running===1'b1 &&
     dut.retained.island.certified_input_complete===1'b1)begin
    if(dut.retained.island.checked_input_complete!==1'b0 ||
       {dut.retained.island.guard_valid_out,dut.retained.island.guard_commit_out,
        dut.retained.island.forward_retirement_valid}!==5'b0)
      $fatal(1,"candidate final input prematurely used closed public return");
    candidate_finals=candidate_finals+1;
  end
  #0.001;
  candidate_closed_check(1);
  if(candidate_admit_before)begin
    if(actual_jobs!=candidate_jobs || actual_admit!=candidate_cycle_before ||
       actual_inverse!==candidate_inverse_before || actual_start!==candidate_descriptor_before[68:5])
      $fatal(1,"candidate admission original witness join");
    if(candidate_inverse_before)begin
      if(dut.retained.island.owners[1].result_guard.descriptor!==candidate_descriptor_before)
        $fatal(1,"candidate sampled inverse descriptor");
    end else if(dut.retained.island.owners[0].result_guard.descriptor!==candidate_descriptor_before)
      $fatal(1,"candidate sampled forward descriptor");
    $display("RCAND_JOB context=%0d job=%0d inverse=%0d start=%0d cycle=%0d offered=1 sampled=1",
      candidate_context_before,candidate_jobs,candidate_inverse_before,
      candidate_descriptor_before[68:5],candidate_cycle_before);
  end
end
generate for(genvar candidate_owner=0;candidate_owner<2;candidate_owner=candidate_owner+1)begin : candidate_owner_witness
  reg running_before,owned_before,accept_before;
  reg[69:0] descriptor_before,offered_before;
  integer accepted=0,held=0,real_ack=0;
  always @(posedge fft_clk)begin
    #0;
    running_before=dut.retained.island.fast_running;
    owned_before=dut.retained.island.owners[candidate_owner].result_guard.active ||
      dut.retained.island.owners[candidate_owner].result_guard.awaiting_ack;
    accept_before=dut.retained.island.owners[candidate_owner].result_guard.job_accept;
    descriptor_before=dut.retained.island.owners[candidate_owner].result_guard.descriptor;
    offered_before=dut.retained.island.owners[candidate_owner].result_guard.job_descriptor;
    if(running_before===1'b1)begin
      if(accept_before===1'b1)accepted=accepted+1;
      if(dut.retained.island.owners[candidate_owner].result_guard.owner_ack_accept===1'b1)
        real_ack=real_ack+1;
    end
    #0.001;
    if(running_before===1'b1 && dut.retained.island.fast_running===1'b1)begin
      if(owned_before===1'b1)begin
        if(dut.retained.island.owners[candidate_owner].result_guard.descriptor!==descriptor_before)
          $fatal(1,"candidate active/parked/real-ACK descriptor changed");
        held=held+1;
      end
      if(accept_before===1'b1 &&
         dut.retained.island.owners[candidate_owner].result_guard.descriptor!==offered_before)
        $fatal(1,"candidate owner accepted descriptor equality");
    end
  end
  final begin
    if(accepted!=(candidate_owner?19:21) || real_ack!=(candidate_owner?17:19) || held<1000)
      $fatal(1,"candidate owner inventory");
    $display("RCAND_OWNER owner=%0d accepted=%0d real_ack=%0d held=%0d",candidate_owner,accepted,real_ack,held);
  end
end endgenerate
final begin
  if(candidate_jobs!=40 || candidate_finals!=38 || candidate_pre<1000 ||
     candidate_post<1000 || candidate_public<19456)
    $fatal(1,"candidate complete premise inventory");
  $display("RCAND_PROOF jobs=%0d final_inputs=%0d closed_pre=%0d closed_post=%0d public_pre=%0d",
    candidate_jobs,candidate_finals,candidate_pre,candidate_post,candidate_public);
end
