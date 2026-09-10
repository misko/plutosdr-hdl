// Scheduler/real-guard proof only. Synthetic core events and minimal bank/
// joiner control models; NOT vendor FFT, bank RAM, or numerical qualification.
`timescale 1ns/1fs
module extra_edge_ordinal(input clk,resetn,accepted);
 reg[8:0]expected_bin_index=0;
 always @(posedge clk)if(!resetn)expected_bin_index<=0;
 else if(accepted && expected_bin_index!=511)expected_bin_index<=expected_bin_index+1;
endmodule
module extra_edge_join(input clk,resetn,input_valid);
 extra_edge_ordinal kernel_rom(clk,resetn,input_valid);
endmodule
module extra_edge_dut #(parameter integer MODE=0)(
 input clk,resetn,job_valid,certified_input_beat,certified_input_complete,
 input final_fence_certified,core_event_frame_started,
 input[23:0]core_output_tuser,input core_output_tvalid,core_output_tlast,
 input core_status_tvalid,output forward_old_valid);
 wire event_last_missing=0,product_bank_ready=1,next_inverse=0;
 reg fast_fault=0,forward_committed=0,product_bank_valid=0;
 wire return_valid,return_commit_valid,result_fault;
 wire forward_handoff_ack=forward_committed && product_bank_valid && !fast_fault;
 wire product_commit_authorized=return_commit_valid;
 wire raw_fault=event_last_missing || fast_fault;
 extra_edge_join joiner(clk,resetn,return_valid && !next_inverse && !fast_fault && product_bank_ready);
 starlink_pss_realtime_result_guard #(.USE_COMPLETED_INPUT_FAULT(1),
  .USE_FORWARD_RETIREMENT(MODE),.USE_PREFLIGHT_REASON_ONLY(MODE)) result_guard(
  .clk(clk),.resetn(resetn),.job_valid(job_valid),.job_descriptor(70'd9),
  .input_bank_reserved(1'b1),.output_bank_reserved(1'b1),
  .certified_input_beat(certified_input_beat),.certified_input_complete(certified_input_complete),
  .final_fence_certified(final_fence_certified),.external_fault_now(raw_fault),
  .phase_input_fault_now(1'b0),.completed_input_certified(final_fence_certified),
  .completed_input_fault_now(raw_fault),.preflight_fault_evidence_now(1'b0),
  .core_event_frame_started(core_event_frame_started),.core_output_tdata(48'd12),
  .core_output_tuser(core_output_tuser),.core_output_tvalid(core_output_tvalid),
  .core_output_tlast(core_output_tlast),.core_status_tdata(8'd5),.core_status_tvalid(core_status_tvalid),
  .mailbox_input_ready(product_bank_ready),.mailbox_input_fault(1'b0),
  .inverse_phase(next_inverse),.forward_mailbox_fault(1'b0),
  .mailbox_input_valid(return_valid),.mailbox_commit_valid(return_commit_valid),.protocol_fault(result_fault));
 starlink_pss_realtime_result_guard_ce6a885e_golden #(.USE_COMPLETED_INPUT_FAULT(1),
  .USE_PREFLIGHT_REASON_ONLY(MODE)) old_guard(
  .clk(clk),.resetn(resetn),.job_valid(job_valid),.job_descriptor(70'd9),
  .input_bank_reserved(1'b1),.output_bank_reserved(1'b1),
  .certified_input_beat(certified_input_beat),.certified_input_complete(certified_input_complete),
  .final_fence_certified(final_fence_certified),.external_fault_now(raw_fault),
  .phase_input_fault_now(1'b0),.completed_input_certified(final_fence_certified),
  .completed_input_fault_now(raw_fault),.preflight_fault_evidence_now(1'b0),
  .core_event_frame_started(core_event_frame_started),.core_output_tdata(48'd12),
  .core_output_tuser(core_output_tuser),.core_output_tvalid(core_output_tvalid),
  .core_output_tlast(core_output_tlast),.core_status_tdata(8'd5),.core_status_tvalid(core_status_tvalid),
  .mailbox_input_ready(product_bank_ready),.mailbox_input_fault(1'b0),
  .mailbox_input_valid(forward_old_valid));
 always @(posedge clk)begin
  if(!resetn)begin fast_fault<=0;forward_committed<=0;product_bank_valid<=0;end
  else begin
   if(raw_fault || result_fault)fast_fault<=1;
   if(return_commit_valid && product_bank_ready)begin forward_committed<=1;product_bank_valid<=1;end
  end
 end
endmodule

module tb_starlink_pss_fft_bank_owned_slice;
 parameter integer KIND=0,MODE=0,PROVIDER=0;
 reg fft_clk=0;always #2.857143 fft_clk=!fft_clk;
 reg resetn=0,job_valid=0,certified_input_beat=0,certified_input_complete=0;
 reg final_fence_certified=0,core_event_frame_started=0;
 reg[23:0]core_output_tuser=0;
 reg core_output_tvalid=0,core_output_tlast=0,core_status_tvalid=0;
 wire forward_old_valid;
 extra_edge_dut #(.MODE(MODE)) dut(.clk(fft_clk),.*);
 integer exact_extra_kind=KIND,exact_extra_stalls=0,exact_extra_faults=0,exact_extra_resets=0;
 integer inverse_jobs=0,held_edges=0,fault_edges=0,old_checks=0,lead_fs=0;
 reg expected_fault=0;realtime fault_drive_time,lead_ns;
 task tick;@(posedge fft_clk);#0.001;endtask
 task await_fault;
  if(!dut.fast_fault || dut.result_guard.fault_reasons!==8'h01)
   $fatal(1,"EDGE_EXACT_REASON_MISSING");
 endtask
 task reset_epoch(input integer side);$fatal(1,"EDGE_UNEXPECTED_RESET_BRANCH");endtask
 // This is the literal old sample delay and comparison, never moved.
 always @(posedge fft_clk)begin
  #0.001;
  if(dut.joiner.input_valid !==
      (forward_old_valid && !dut.next_inverse && !dut.fast_fault && dut.product_bank_ready))
   $fatal(1,"FORWARD_ACTUAL_JOIN_INPUT_MISMATCH");
  old_checks=old_checks+1;
 end
 always @(posedge fft_clk)if(resetn)begin
  if(dut.result_guard.final_qualified && dut.result_guard.return_last && !dut.product_bank_ready)
   held_edges=held_edges+1;
  if(dut.event_last_missing)begin
   lead_ns=$realtime-fault_drive_time;
   lead_fs=$rtoi(lead_ns*1000000.0+0.5);
   if(lead_fs<=0 || lead_fs>2857143 || dut.return_commit_valid!==0 ||
      dut.joiner.input_valid!==0 || dut.forward_committed || dut.product_bank_valid)
    $fatal(1,"EDGE_PRECOMMIT_CURRENT_FAULT_NOT_STABLE lead_ns=%0f",lead_ns);
   fault_edges=fault_edges+1;
  end
  if(dut.return_commit_valid && dut.product_bank_ready)
   $fatal(1,"EDGE_EARLY_FINAL_PUBLICATION");
 end
 always @(posedge dut.event_last_missing)begin
  fault_drive_time=$realtime;
  if(fft_clk!==0)$fatal(1,"EDGE_FAULT_DRIVE_NOT_LOW_PHASE");
  if(held_edges!==(KIND==1?3:0))$fatal(1,"EDGE_HELD_COUNT_WRONG count=%0d",held_edges);
 end
 task actual_added_fault_body;
    wait(!dut.next_inverse && dut.return_commit_valid &&
         dut.joiner.kernel_rom.expected_bin_index == 511);
    // This is a real vendor-completed, qualified FINAL slot, not a force of
    // guard occupancy/counts or a quiescent cause snapshot.
    if (!dut.result_guard.active || !dut.result_guard.final_qualified ||
        !dut.product_bank_ready || dut.forward_committed || inverse_jobs)
      $fatal(1, "EXACT_EXTRA_FINAL_BOUNDARY_MISSING");
    if (exact_extra_kind != 0) begin
      force dut.product_bank_ready = 0;
      repeat (3) tick(); exact_extra_stalls = exact_extra_stalls + 1;
      if (dut.joiner.input_valid || dut.forward_committed || dut.product_bank_valid || inverse_jobs)
        $fatal(1, "EXACT_EXTRA_STALLED_FINAL_PUBLISHED");
    end
    if (exact_extra_kind < 2) begin
      force fft_clk = 1'bz;
      // Added stimulus only: do not drive at tick's posedge+1ps,
      // which is also the unchanged original join-input checker's sample.
      // Kind1 retains all three held posedges; kind0 is still pre-commit.
      if (fft_clk !== 1'b0 && fft_clk !== 1'b1)
        $fatal(1, "EXACT_EXTRA_UNKNOWN_CLOCK_PHASE");
      if (exact_extra_kind == 1 || fft_clk === 1'b1)
        @(negedge fft_clk);
      if (fft_clk !== 1'b0)
        $fatal(1, "EXACT_EXTRA_ALIGNED_CLOCK_NOT_LOW");
      if (!dut.result_guard.active || !dut.result_guard.final_qualified ||
          !dut.return_commit_valid || !dut.result_guard.return_last ||
          dut.joiner.kernel_rom.expected_bin_index != 511 || dut.next_inverse ||
          dut.forward_committed || dut.product_bank_valid || inverse_jobs ||
          dut.forward_handoff_ack ||
          (exact_extra_kind == 0 && !dut.product_bank_ready) ||
          (exact_extra_kind == 1 && dut.product_bank_ready))
        $fatal(1, "EXACT_EXTRA_ALIGNED_FINAL_BOUNDARY_MISSING");
      expected_fault = 1;
      force dut.event_last_missing = 1;
      if (exact_extra_kind == 1) release dut.product_bank_ready;
      #0.001;
      if (dut.return_commit_valid || dut.joiner.input_valid || dut.forward_handoff_ack ||
          dut.product_commit_authorized)
        $fatal(1, "EXACT_EXTRA_CURRENT_FINAL_VETO_MISSING");
      tick();
      if (!dut.fast_fault || !dut.result_guard.fault_reasons[0])
        $fatal(1, "EXACT_EXTRA_FINAL_REASON_MISSING");
      @(negedge fft_clk); release dut.event_last_missing;
      await_fault(); exact_extra_faults = exact_extra_faults + 1;
      if (dut.product_bank_valid || inverse_jobs || dut.forward_handoff_ack)
        $fatal(1, "EXACT_EXTRA_POISONED_OWNERSHIP_ESCAPED");
    end else begin
      reset_epoch(exact_extra_kind - 1);
      @(negedge fft_clk); release dut.product_bank_ready;
      exact_extra_resets = exact_extra_resets + 1;
    end

 endtask
 integer n;
 initial begin
  if(PROVIDER!==0 && PROVIDER!==1 && PROVIDER!==2)$fatal(1,"EDGE_UNKNOWN_PROVIDER_MODEL");
  repeat(2)tick();@(negedge fft_clk);resetn=1;job_valid=1;
  tick();@(negedge fft_clk);job_valid=0;
  for(n=0;n<512;n=n+1)begin
   certified_input_beat=1;certified_input_complete=(n==511);core_event_frame_started=(n==0);
   tick();@(negedge fft_clk);
  end
  certified_input_beat=0;certified_input_complete=0;core_event_frame_started=0;final_fence_certified=1;
  fork
   begin
    if(PROVIDER==1)begin
     // Explicit posedge-registered provider: the guard observes the prior
     // registered beat; final valid deasserts via NBA on the capture edge.
     for(n=0;n<512;n=n+1)begin
      @(posedge fft_clk);
      core_output_tvalid<=1;core_output_tlast<=(n==511);core_status_tvalid<=(n==0);
      core_output_tuser<={3'b0,5'd5,7'b0,9'(n)};
     end
     @(posedge fft_clk);core_output_tvalid<=0;core_output_tlast<=0;core_status_tvalid<=0;
    end else begin
     // Preserve the original negedge provider. PROVIDER2 changes only its
     // final valid deassertion to a declared fixed low-half-cycle offset.
     for(n=0;n<512;n=n+1)begin
      core_output_tvalid=1;core_output_tlast=(n==511);core_status_tvalid=(n==0);
      core_output_tuser={3'b0,5'd5,7'b0,9'(n)};
      tick();@(negedge fft_clk);
     end
     if(PROVIDER==2)#1.428571;
     core_output_tvalid=0;core_output_tlast=0;core_status_tvalid=0;
    end
   end
   actual_added_fault_body();
  join
  if(held_edges!=(KIND==1?3:0) || fault_edges!=1 || exact_extra_faults!=1 ||
     exact_extra_stalls!=(KIND==1?1:0) || dut.forward_committed || dut.product_bank_valid || inverse_jobs)
   $fatal(1,"EDGE_TERMINAL_COUNTS_OR_OWNERSHIP_WRONG");
  $display("EXTRA_EDGE_GUARD_PASS kind=%0d mode=%0d provider=%0d held_posedges=%0d fault_edges=%0d lead_fs=%0d exact_reasons=%h old_checks=%0d synthetic_core_minimal_banks_not_fft=1",
   KIND,MODE,PROVIDER,held_edges,fault_edges,lead_fs,dut.result_guard.fault_reasons,old_checks);$finish;
 end
endmodule
