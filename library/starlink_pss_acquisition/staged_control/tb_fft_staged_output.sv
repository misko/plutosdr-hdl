// SPDX-License-Identifier: GPL-2.0
// Real generated XFFT required. Exact frozen forward/product/inverse vectors.
// Changed control latency is measured, not assumed equal to the old controller.
`timescale 1ns/1fs
module tb #(parameter integer ACK_ONLY=0);
  // BEGIN FORWARD FINAL COMMIT WITNESS
  integer forward_final_checks=0, forward_final_accepts=0;
  always @(negedge fft_clk)begin
    #0.002;
    if(dut.owners[0].result_guard.final_commit !==
       (dut.owners[0].result_guard.mailbox_commit_valid && dut.owners[0].result_guard.mailbox_input_ready) ||
       dut.owners[1].result_guard.final_commit !==
       (dut.owners[1].result_guard.mailbox_commit_valid && dut.owners[1].result_guard.mailbox_input_ready))
      $fatal(1,"forward final commit changed the original current handshake");
    forward_final_checks=forward_final_checks+1;
    if(dut.owners[0].result_guard.final_commit === 1'b1)
      forward_final_accepts=forward_final_accepts+1;
  end
  task automatic report_forward_final;
    begin
      if(forward_final_checks<1000 || forward_final_accepts<18)
        $fatal(1,"forward final commit coverage incomplete");
      $display("STAGED_FORWARD_FINAL_PASS checks=%0d accepts=%0d exact_current=1 inverse_unchanged=1",forward_final_checks,forward_final_accepts);
    end
  endtask
  // END FORWARD FINAL COMMIT WITNESS
  // BEGIN PARALLEL READY WITNESS
  integer parallel_ready_checks=0;
  wire parallel_selected_ready = dut.fast_running && !dut.kernel_fault &&
    (dut.fast_running === 1'b1 ? dut.joiner.kernel_rom.parallel_input_room : dut.joiner.kernel_rom.output_stage_ready);
  always @(negedge fft_clk)begin
    #0.001;
    if(dut.PARALLEL_KERNEL_READY!==1 || dut.joiner.PARALLEL_INPUT_CAPACITY!==1 || dut.joiner.kernel_rom.PARALLEL_INPUT_CAPACITY!==1)
      $fatal(1,"parallel ready integrated profile mismatch");
    if(dut.product_pipeline_full !== (dut.product.registered_operands.valid && dut.product.arithmetic.product_valid &&
       dut.product.arithmetic.sum_valid && dut.product.arithmetic.output_valid))
      $fatal(1,"parallel ready owning occupancy mismatch");
    if(dut.product_identity_idle !== !dut.product_identity_stage.full || parallel_selected_ready !== capacity_original_ready)
      $fatal(1,"parallel ready original expression mismatch");
    parallel_ready_checks=parallel_ready_checks+1;
  end
  task automatic report_parallel_ready;
    begin
      report_forward_final; // FORWARD FINAL REPORT
      if(parallel_ready_checks<1000)$fatal(1,"parallel ready coverage incomplete");
      $display("STAGED_PARALLEL_READY_PASS checks=%0d ports=1 current_exact=1 original_guard_wiring=1 latency_unchanged=1",parallel_ready_checks);
    end
  endtask
  // END PARALLEL READY WITNESS
  // BEGIN FORWARD CAPACITY SHADOW
  // Observation only. No hierarchy reference below drives runtime logic.
  wire capacity_vacancy = !dut.joined_valid || !dut.product.registered_operands.valid ||
    !dut.product.arithmetic.product_valid || !dut.product.arithmetic.sum_valid || !dut.product.arithmetic.output_valid;
  wire capacity_tail = !dut.product_identity_stage.fault &&
    (!dut.product_identity_stage.full || ((dut.staged_product_last === 1'b0) && dut.product_identity_stage.refill_capacity)) && !dut.fast_fault;
  wire capacity_parallel_ready = dut.fast_running && !dut.kernel_fault && (capacity_vacancy || capacity_tail);
  // Compare the unforced RTL expression separately from artificial internal
  // ready/summary force injections. Those remain mandatory fault tests below.
  wire capacity_original_ready = dut.joiner.kernel_rom.resetn && !dut.joiner.kernel_rom.flush &&
    !dut.joiner.kernel_rom.protocol_fault && (!dut.joiner.kernel_rom.output_valid || dut.joiner.kernel_rom.output_ready);
  wire capacity_forward_ready = dut.forward_receipt_wait ? dut.product_bank_valid : (capacity_parallel_ready && dut.product_bank_ready);
  wire capacity_slot_error = dut.owners[0].result_guard.active && dut.owners[0].result_guard.return_valid &&
    ((!dut.owners[0].result_guard.return_last && !capacity_forward_ready) ||
     (dut.owners[0].result_guard.core_output_tvalid && (dut.owners[0].result_guard.return_last || !capacity_forward_ready)));
  wire capacity_common = dut.offered_external_fault_now ||
    (|{dut.guard_offered_local_faults[0][7],dut.guard_offered_local_faults[0][5:0]}) || capacity_slot_error ||
    dut.guard_offered_local_fault[1] || dut.output_bank_fault || dut.output_bank_framing_fault_now ||
    ((dut.fast_running === 1'b1 && dut.retained_reserved_known) ? (|dut.summary_preflight_events) : dut.preparation_fault_now) || dut.result_fault;
  integer capacity_checks=0,capacity_healthy=0,capacity_faults=0,capacity_ready_overrides=0;
  integer capacity_summary_overrides=0,capacity_common_differences=0,capacity_unexplained=0;
  always @(negedge fft_clk)begin
    #0.001;
    if(dut.INPUT_OFFER_FAULT_SUMMARY!==1 || dut.CONTEXTUAL_DESTINATION_SUMMARY!==1 || dut.REGISTER_OPERANDS!==1)
      $fatal(1,"forward capacity shadow profile mismatch");
    if(dut.fast_running === 1'b0 || dut.fast_running === 1'b1)begin
      if(capacity_parallel_ready!==capacity_original_ready)$fatal(1,"parallel capacity equation mismatch");
      capacity_checks=capacity_checks+1;
    end
    if(dut.fast_running === 1'b1)begin
      if(dut.offered_external_fault_now===1'b0)capacity_healthy=capacity_healthy+1;
      if(dut.offered_external_fault_now===1'b1)capacity_faults=capacity_faults+1;
      if(dut.kernel_ready!==capacity_original_ready)capacity_ready_overrides=capacity_ready_overrides+1;
      if(dut.guard_offered_local_faults[0][6]!==dut.owners[0].result_guard.summary_slot_error)
        capacity_summary_overrides=capacity_summary_overrides+1;
      if(capacity_common!==dut.common_current_fault)begin
        capacity_common_differences=capacity_common_differences+1;
        if(dut.kernel_ready===capacity_original_ready &&
           dut.guard_offered_local_faults[0][6]===dut.owners[0].result_guard.summary_slot_error)begin
          capacity_unexplained=capacity_unexplained+1;
          $fatal(1,"unexplained forward capacity fault mismatch");
        end
      end
    end
  end
  task automatic report_forward_capacity;
    begin
      if(capacity_checks<1000 || capacity_healthy<1000 || capacity_faults<10 || capacity_unexplained!=0)
        $fatal(1,"forward capacity coverage incomplete");
      $display("STAGED_FORWARD_CAPACITY_SHADOW_PASS checks=%0d healthy=%0d faults=%0d ready_overrides=%0d summary_overrides=%0d common_differences=%0d unexplained=%0d runtime_unchanged=0",capacity_checks,capacity_healthy,capacity_faults,capacity_ready_overrides,capacity_summary_overrides,capacity_common_differences,capacity_unexplained);
    end
  endtask
  // END FORWARD CAPACITY SHADOW
  // BEGIN MONOTONIC RESET WITNESS
  integer monotonic_fast_checks=0,monotonic_slow_checks=0,monotonic_reset_checks=0;
  wire monotonic_raw_ok = resetn === 1'b1 && fft_resetn === 1'b1;
  wire original_fast_release = monotonic_raw_ok && dut.outer_fast_running && dut.epoch_barrier.fast_release;
  wire original_slow_release = monotonic_raw_ok && dut.outer_slow_running && dut.epoch_barrier.fast_release_slow[1];
  task automatic check_monotonic_release;
    begin
      if(dut.MONOTONIC_OUTER_RESET!==1 || dut.epoch_barrier.MONOTONIC_OUTER_RESET!==1)
        $fatal(1,"monotonic reset profile mismatch");
      if({dut.slow_running,dut.fast_running}!=={original_slow_release,original_fast_release})
        $fatal(1,"monotonic reset release changed");
    end
  endtask
  always @(negedge fft_clk)begin #0.001;check_monotonic_release;monotonic_fast_checks=monotonic_fast_checks+1;end
  always @(negedge clk)begin #0.001;check_monotonic_release;monotonic_slow_checks=monotonic_slow_checks+1;end
  always @(resetn or fft_resetn)begin #0.001;check_monotonic_release;monotonic_reset_checks=monotonic_reset_checks+1;end
  task automatic report_monotonic_release;
    begin
      if(monotonic_fast_checks<1000 || monotonic_slow_checks<1000 || monotonic_reset_checks<4)
        $fatal(1,"monotonic reset witness incomplete");
      $display("STAGED_MONOTONIC_RESET_PASS fast=%0d slow=%0d resets=%0d current_exact=1 latency_unchanged=1",monotonic_fast_checks,monotonic_slow_checks,monotonic_reset_checks);
    end
  endtask
  // END MONOTONIC RESET WITNESS
  // BEGIN SPLIT PREFLIGHT WITNESS
  integer split_preflight_checks=0,split_preflight_source=0,split_preflight_product=0;
  wire [69:0] original_preflight_metadata = dut.preflight_phase ? dut.product_bank_metadata : dut.source_metadata;
  wire [1:0] original_preflight_equal = {dut.engine_metadata == dut.expected_product_metadata,
    original_preflight_metadata == dut.engine_metadata};
  always @(negedge fft_clk)begin
    #0.001;
    if(dut.fast_running)begin
      if(dut.SPLIT_PREFLIGHT_IDENTITY!==1 || dut.preflight_identity_equal!==original_preflight_equal)
        $fatal(1,"split preflight current identity mismatch");
      split_preflight_checks=split_preflight_checks+1;
      if(dut.preparing && !dut.preflight_phase)split_preflight_source=split_preflight_source+1;
      if(dut.preparing && dut.preflight_phase)split_preflight_product=split_preflight_product+1;
    end
  end
  task automatic report_split_preflight;
    begin
      if(split_preflight_checks<1000 || split_preflight_source<20 || split_preflight_product<20)
        $fatal(1,"split preflight witness coverage missing");
      $display("STAGED_SPLIT_PREFLIGHT_PASS checks=%0d source=%0d product=%0d current_exact=1 latency_unchanged=1",split_preflight_checks,split_preflight_source,split_preflight_product);
    end
  endtask
  // END SPLIT PREFLIGHT WITNESS
  // BEGIN PRIVATE QUARANTINE WITNESS
  integer private_quarantine_checks=0,private_quarantine_differences=0;
  always @(negedge fft_clk) begin
    #0.001;
    if(dut.fast_running)begin
      if(dut.PRIVATE_QUARANTINE_OFFER!==1 || dut.owners[1].result_guard.PRIVATE_QUARANTINE_OFFER!==1 ||
         dut.owners[0].result_guard.PRIVATE_QUARANTINE_OFFER!==0)
        $fatal(1,"private quarantine profile mismatch");
      if(dut.guard_private_out[1]!==original_inverse_ack.mailbox_private_valid)begin
        if(dut.result_fault!==1 || dut.owners[1].result_guard.protocol_fault!==1 ||
           dut.guard_private_out[1]!==1 || original_inverse_ack.mailbox_private_valid!==0 ||
           dut.guard_valid_out[1]!==0 || dut.guard_commit_out[1]!==0 ||
           dut.output_replay_accept!==0 || dut.guard_ack[1]!==0 || dut.job_ready!==0)
          $fatal(1,"private offer difference escaped quarantine");
        private_quarantine_differences=private_quarantine_differences+1;
      end
      private_quarantine_checks=private_quarantine_checks+1;
    end
  end
  task automatic report_private_quarantine;
    begin
      if(private_quarantine_checks<1000 || private_quarantine_differences==0)
        $fatal(1,"private quarantine witness coverage missing");
      $display("STAGED_PRIVATE_QUARANTINE_PASS checks=%0d differences=%0d public_fenced=1 healthy_exact=1",private_quarantine_checks,private_quarantine_differences);
    end
  endtask
  // END PRIVATE QUARANTINE WITNESS
  // BEGIN REPLAY QUIET WITNESS
  // Diagnostic only: nothing here drives DUT authorization or state.
  wire replay_quiet_context = dut.state==dut.ACK_DRAIN && dut.next_inverse && dut.routed_inverse &&
    !dut.preparing && !dut.owners[0].result_guard.active && !dut.owners[1].result_guard.active;
  wire replay_quiet_fault = dut.offered_external_fault_now || dut.result_fault ||
    dut.output_bank_fault || dut.output_bank_framing_fault_now || dut.preparation_fault_now ||
    dut.core_status_valid || dut.core_output_valid || dut.event_frame ||
    dut.summary_offer_beat || dut.summary_offer_complete;
  wire replay_quiet_accept = dut.output_replay_valid && dut.output_descriptor_valid &&
    dut.output_bank_ready && replay_quiet_context && !replay_quiet_fault;
  // Compare the original equation even when a test deliberately forces its
  // output low; independently require that test's forced stall to remain low.
  wire replay_original_predicate = dut.output_replay_valid && dut.output_descriptor_valid &&
    dut.output_bank_ready && !dut.common_current_fault;
  integer replay_quiet_checks=0,replay_quiet_offers=0,replay_quiet_accepts=0;
  integer replay_quiet_paused=0;
  integer replay_quiet_sweep=0;
  reg [7:0] replay_probe_data=0;
  task automatic check_replay_quiet;
    begin
      if(dut.fast_running)begin
        // BEGIN INTEGRATED REPLAY FENCE WITNESS
        if(dut.REPLAY_QUIET_PUBLICATION!==1 || dut.REPLAY_FENCE_PROFILE!==1)
          $fatal(1,"integrated replay fence not enabled in actual FFT");
        if(dut.guard_active!=={dut.owners[1].result_guard.active,dut.owners[0].result_guard.active} ||
           dut.replay_publication_context!==replay_quiet_context ||
           dut.replay_publication_fault!==replay_quiet_fault)
          $fatal(1,"integrated replay fence differs from independent shadow");
        // END INTEGRATED REPLAY FENCE WITNESS
        if((replay_quiet_accept===1'b1)!==(replay_original_predicate===1'b1))
          $fatal(1,"replay quiet publication decision differs");
        if((dut.output_replay_accept===1'b1)!==(!publication_probe_paused && replay_original_predicate===1'b1))
          $fatal(1,"replay quiet forced publication stall differs");
        if(publication_probe_paused)replay_quiet_paused=replay_quiet_paused+1;
        if(dut.output_replay_valid===1'b1)begin
          if(replay_quiet_context!==1'b1)$fatal(1,"replay quiet ownership premise missing");
          if(replay_quiet_fault!==dut.common_current_fault)$fatal(1,"replay quiet current fault differs");
          replay_quiet_offers=replay_quiet_offers+1;
        end
        if(replay_quiet_accept===1'b1)replay_quiet_accepts=replay_quiet_accepts+1;
        replay_quiet_checks=replay_quiet_checks+1;
      end
    end
  endtask
  always @(negedge fft_clk)begin #0.001;check_replay_quiet;end
  task automatic report_replay_quiet;
    begin
      if(replay_quiet_checks<1000 || replay_quiet_offers<18 || replay_quiet_accepts<18)
        $fatal(1,"replay quiet witness coverage short");
      $display("STAGED_REPLAY_QUIET_PASS checks=%0d offers=%0d accepts=%0d sweep=%0d paused=%0d current_exact=1 runtime_unchanged=0",replay_quiet_checks,replay_quiet_offers,replay_quiet_accepts,replay_quiet_sweep,replay_quiet_paused);
      $display("STAGED_REPLAY_FENCE_PASS enabled=1 profile=1 independent_shadow=1 current_publication_exact=1"); // INTEGRATED REPLAY FENCE REPORT
      report_private_quarantine; // PRIVATE QUARANTINE REPORT
      report_split_preflight; // SPLIT PREFLIGHT REPORT
      report_monotonic_release; // MONOTONIC RESET REPORT
      report_forward_capacity; // FORWARD CAPACITY REPORT
      report_parallel_ready; // PARALLEL READY REPORT
    end
  endtask
  // END REPLAY QUIET WITNESS
  // BEGIN COMPLETION MAILBOX WITNESS
  integer completion_slot_accepts=0, completion_slot_consumes=0, completion_slot_holds=0;
  reg completion_slot_held=0;
  reg [31:0] completion_slot_tag;
  reg [35:0] completion_slot_data;
  always @(posedge fft_clk) begin : completion_slot_monitor
    reg accepting,consuming;
    accepting=dut.fast_running && dut.output_complete_accept;
    consuming=dut.fast_running && !dut.output_control.fault && dut.output_control.complete_pending;
    if(!dut.fast_running)completion_slot_held=0;
    else begin
      if(accepting)begin
        completion_slot_held=1;completion_slot_tag=dut.inverse_tag;
        completion_slot_data=dut.guard_return_data[1];completion_slot_accepts=completion_slot_accepts+1;
      end
      #0.001;
      if(dut.fast_running)begin
        if(accepting && (!dut.output_publication_busy || dut.output_complete_ready))
          $fatal(1,"actual completion receipt did not reserve ownership immediately");
        if(consuming && !dut.output_control.fault)begin
          if(dut.output_control.complete_pending || dut.output_control.phase!==3'd1)
            $fatal(1,"actual completion receipt not consumed into private COMMIT");
          completion_slot_consumes=completion_slot_consumes+1;
        end
        if(completion_slot_held && dut.output_publication_busy)begin
          if(dut.output_control.active_tag!==completion_slot_tag || dut.output_control.final_data!==completion_slot_data)
            $fatal(1,"actual held completion tag/final word changed");
          completion_slot_holds=completion_slot_holds+1;
        end
        if(!dut.output_publication_busy)completion_slot_held=0;
      end
    end
  end
  // BEGIN REPLAY QUIET BOUNDARIES
  task automatic replay_quiet_boundary(input integer boundary);
    reg request_before;
    integer n;
    begin
      stress_reset;stress_fixture=0;send_block(0);
      while(dut.output_replay_valid!==1'b1)@(negedge fft_clk);
      if(replay_quiet_context!==1'b1 || dut.output_replay_accept!==1'b1)
        $fatal(1,"replay quiet boundary not initially publishable");
      request_before=dut.output_request;stress_fault_expected=1;
      if(boundary==0)begin
        force dut.core_status_data=replay_probe_data;
        force dut.core_status_valid=1'b0;
        for(n=0;n<256;n=n+1)begin
          replay_probe_data=n;#0.002;check_replay_quiet;
          if(dut.output_replay_accept!==1'b1)$fatal(1,"invalid status payload affected replay");
          replay_quiet_sweep=replay_quiet_sweep+1;
        end
        force dut.core_status_valid=1'b1;
        for(n=0;n<256;n=n+1)begin
          replay_probe_data=n;#0.002;check_replay_quiet;
          if(dut.output_replay_accept!==1'b0)$fatal(1,"late status payload authorized replay");
          replay_quiet_sweep=replay_quiet_sweep+1;
        end
      end
      if(boundary<8)begin
        case(boundary)
          0:replay_probe_data=8'h00;1:replay_probe_data=8'hff;
          2:replay_probe_data=8'h1f;3:replay_probe_data=8'h20;
          4:replay_probe_data=8'h80;5:replay_probe_data=8'hxx;
          6:replay_probe_data=8'hzz;7:replay_probe_data=8'h01;
        endcase
        force dut.core_status_data=replay_probe_data;force dut.core_status_valid=1'b1;
      end else if(boundary==8)force dut.core_output_valid=1'b1;
      else force dut.event_frame=1'b1;
      #0.002;check_replay_quiet;
      if(dut.output_replay_accept!==1'b0 || replay_quiet_accept!==1'b0)
        $fatal(1,"late event not rejected on publication edge");
      @(posedge fft_clk);#0.001;
      if(dut.output_request!==request_before)$fatal(1,"late event published payload");
      @(negedge fft_clk);
      release dut.core_status_data;release dut.core_status_valid;release dut.core_output_valid;
      release dut.event_frame;release dut.summary_offer_beat;release dut.summary_offer_complete;
      repeat(100)begin
        @(negedge fft_clk);
        if(dut.output_request!==request_before || dut.output_released_valid || output_valid)
          $fatal(1,"late replay event escaped quarantine");
      end
      if(fault!==1'b1 || stress_reads!=0 || stress_releases!=0)$fatal(1,"late replay fault not recorded");
      stress_reset;stress_fixture=0;send_block(0);stress_drain=1;
      while(stress_reads!=512 || !dut.retained_reusable)@(negedge fft_clk);
      if(fault || stress_releases!=1)$fatal(1,"replay quiet fresh recovery failed");
      $display("STAGED_REPLAY_QUIET_CASE_PASS boundary=%0d blocked_publication=1 fresh_reads=512 fresh_releases=1",boundary);
    end
  endtask
  // END REPLAY QUIET BOUNDARIES
  task automatic report_completion_slot;
    begin
      if(completion_slot_accepts<18 || completion_slot_consumes<18 || completion_slot_holds<1000)
        $fatal(1,"incomplete actual completion receipt coverage");
      $display("STAGED_COMPLETION_SLOT_PASS accepts=%0d consumes=%0d holds=%0d immediate_ownership=1 held_payload=1",completion_slot_accepts,completion_slot_consumes,completion_slot_holds);
    end
  endtask
  // END COMPLETION MAILBOX WITNESS
  // BEGIN BALANCED HANDOFF WITNESS
  integer handoff_checks=0, handoff_owned_checks=0;
  always @(negedge fft_clk) begin : settled_handoff_monitor
    reg before_identity, before_reference;
    before_identity=dut.forward_handoff_identity;
    before_reference=(dut.product_bank_metadata ==
      {1'b1,dut.engine_metadata[68:5],dut.return_metadata[4:0]});
    // Existing negative-edge fault drivers use force/release. Let their
    // combinational delta cycles settle; remain far before the sampling edge.
    #0.001;
    if (dut.fast_running === 1'b1) begin
      if (dut.forward_handoff_identity !== (dut.product_bank_metadata ==
          {1'b1,dut.engine_metadata[68:5],dut.return_metadata[4:0]}))
        $fatal(1,"balanced handoff differs from original current identity");
      if(before_identity !== before_reference)
        $display("STAGED_HANDOFF_SETTLED_DELTA time=%0t before=%b reference=%b settled=%b",$time,before_identity,before_reference,dut.forward_handoff_identity);
      handoff_checks=handoff_checks+1;
      if (dut.forward_committed && dut.product_bank_valid)
        handoff_owned_checks=handoff_owned_checks+1;
    end
  end
  task automatic report_balanced_handoff;
    begin
      if(handoff_checks<1000 || handoff_owned_checks<12)
        $fatal(1,"incomplete actual handoff identity coverage");
      $display("STAGED_BALANCED_HANDOFF_PASS checks=%0d owned=%0d exact_current=1",handoff_checks,handoff_owned_checks);
    end
  endtask
  // END BALANCED HANDOFF WITNESS
  reg clk=0,fft_clk=0,resetn=0,fft_resetn=0,run_slow=1;
  always #2.857143 fft_clk=~fft_clk;
  initial begin #1.3;forever begin #5;if(run_slow)clk=~clk;end end
  reg input_valid=0,input_last=0,output_ready=0;
  reg [35:0] input_data=0;
  reg [8:0] input_position=0;
  reg [63:0] input_block_start=0;
  reg [63:0] context_start_base=1000;
  wire input_ready,output_valid,output_last,fault;
  wire [35:0] output_data;
  wire [8:0] output_position;
  wire [74:0] output_metadata;
  starlink_pss_fft_staged_output_impl #(.REGISTERED_SCHEDULING(1),
    .BOUNDARY_ROUND_SAT(1),.REGISTER_OPERANDS(1),.LOCAL_FIRST_ADMISSION(1),
    .PRIVATE_DESCRIPTOR_OFFER(1),.CLOSED_INPUT_CUTOVER(1),
    .INPUT_OFFER_FAULT_SUMMARY(1),.CONTEXTUAL_DESTINATION_SUMMARY(1),.REPLAY_QUIET_PUBLICATION(1),.SPLIT_PREFLIGHT_IDENTITY(1),.MONOTONIC_OUTER_RESET(1),.PARALLEL_KERNEL_READY(1),.PRIVATE_QUARANTINE_OFFER(1)) dut(.*);
  reg [31:0] samples[0:1405];
  // BEGIN OUTPUT METADATA WITNESS
  integer output_metadata_checks=0,output_metadata_live_words=0,output_metadata_replay_words=0;
  reg [36:0] output_metadata_bad;
  always @(posedge fft_clk)begin
    if(dut.fast_running && dut.output_bank.input_accept)begin
      if(dut.output_bank.metadata_matches !==
         (dut.output_bank.input_metadata == dut.output_bank.metadata_in_hold))
        $fatal(1,"output metadata current comparison differs from original");
      output_metadata_checks=output_metadata_checks+1;
      if(dut.output_publication_busy)output_metadata_replay_words=output_metadata_replay_words+1;
      else output_metadata_live_words=output_metadata_live_words+1;
    end
  end
  task automatic report_output_metadata;
    begin
      if(output_metadata_checks<6144 || output_metadata_live_words<6144 || output_metadata_replay_words<12)
        $fatal(1,"output metadata actual branch coverage missing");
      $display("STAGED_OUTPUT_METADATA_PASS checks=%0d live=%0d replay=%0d current_exact=1 unchanged_publication=1",output_metadata_checks,output_metadata_live_words,output_metadata_replay_words);
    end
  endtask
  // END OUTPUT METADATA WITNESS
  // BEGIN SPLIT CAPACITY WITNESS
  integer split_capacity_checks=0,split_nonfinal_checks=0;
  wire original_product_capacity = (dut.fast_running && !dut.product_stage_fault) &&
    (!dut.product_identity_stage.full ||
     ((dut.staged_product_last === 1'b0) && dut.staged_product_ready));
  always @(posedge fft_clk)begin
    if(dut.fast_running)begin
      if(dut.product_stage_ready!==original_product_capacity)
        $fatal(1,"split capacity changed original producer acceptance");
      if(dut.staged_product_valid && !dut.staged_product_last)begin
        if(dut.product_identity_stage.refill_capacity!==dut.staged_product_ready)
          $fatal(1,"nonfinal capacity differs from actual retirement");
        split_nonfinal_checks=split_nonfinal_checks+1;
      end
      split_capacity_checks=split_capacity_checks+1;
    end
  end
  task automatic report_split_capacity;
    begin
      if(split_capacity_checks<1000 || split_nonfinal_checks<6144)
        $fatal(1,"split capacity coverage missing");
      $display("STAGED_SPLIT_CAPACITY_PASS checks=%0d nonfinal=%0d input_ready_exact=1 current_retirement_exact=1",split_capacity_checks,split_nonfinal_checks);
    end
  endtask
  // END SPLIT CAPACITY WITNESS
  // BEGIN FINAL CAPACITY WITNESS
  integer final_capacity_checks=0,final_capacity_starts=0;
  always @(posedge fft_clk)begin
    if(dut.fast_running && !dut.product_stage_fault)begin
      if(dut.staged_product_valid && dut.staged_product_last)begin
        if(dut.product_stage_ready!==0)$fatal(1,"held LAST allowed same-edge refill");
        if(!dut.common_current_fault && !dut.registered_quarantine && dut.product_valid)
          $fatal(1,"a new product offer overlapped its predecessor LAST");
        final_capacity_checks=final_capacity_checks+1;
      end
      if(dut.input_job_start && !dut.next_inverse && !dut.common_current_fault && !dut.registered_quarantine)begin
        if(dut.staged_product_valid || dut.product_bank_ready!==1)
          $fatal(1,"new forward block began before actual product-bank return");
        final_capacity_starts=final_capacity_starts+1;
      end
    end
  end
  task automatic report_final_capacity;
    begin
      if(final_capacity_checks<12 || final_capacity_starts<12)$fatal(1,"final capacity coverage missing");
      $display("STAGED_FINAL_CAPACITY_PASS finals=%0d starts=%0d no_refill=1 producer_quiet=1 actual_bank_return=1",final_capacity_checks,final_capacity_starts);
    end
  endtask
  // END FINAL CAPACITY WITNESS
  // BEGIN ACTUAL PRODUCT STAGE WITNESS
  reg product_slot_owned=0;
  reg [116:0] product_slot_word;
  integer product_slot_pushes=0,product_slot_pops=0,product_slot_checks=0;
  integer product_reference_updates=0,product_slot_holds=0;
  always @(posedge fft_clk) begin
    if(!dut.fast_running || dut.product_stage_fault)product_slot_owned=0;
    else begin
      if(dut.staged_product_valid!==product_slot_owned)
        $fatal(1,"actual product private slot occupancy mismatch");
      if(dut.staged_product_valid)begin
        product_slot_checks=product_slot_checks+1;
        if({dut.staged_product_data,dut.staged_product_position,dut.staged_product_last,
            dut.staged_product_metadata,dut.staged_product_identity_good} !== product_slot_word)
          $fatal(1,"actual product retained word/certificate changed");
        if(!dut.staged_product_ready)product_slot_holds=product_slot_holds+1;
        if(dut.product_bank_ready && dut.product_bank.write_position!=0 &&
           dut.staged_product_identity_good !==
             ((dut.staged_product_metadata==dut.product_bank.metadata_in_hold)===1'b1))
          $fatal(1,"registered product identity differs from original wide comparison");
      end
      if(dut.product_writer_metadata_load)begin
        if(!dut.product_stage_ready)$fatal(1,"actual product reference update paused continuous refill");
        product_reference_updates=product_reference_updates+1;
      end
      if(dut.staged_product_valid && dut.staged_product_ready)begin
        product_slot_owned=0;product_slot_pops=product_slot_pops+1;
        if(dut.staged_product_last && (dut.product_commit_authorized!==1 || dut.product_bank_ready!==1))
          $fatal(1,"private final product retired without actual commit");
      end
      if(dut.product_valid && dut.product_stage_ready && !dut.fast_fault)begin
        if(product_slot_owned)$fatal(1,"actual product private slot overwritten");
        product_slot_owned=1;product_slot_pushes=product_slot_pushes+1;
        product_slot_word={{dut.product_q,dut.product_i},dut.product_position,dut.product_last,
          {1'b1,dut.product_start,dut.product_exponent},
          (({1'b1,dut.product_start,dut.product_exponent}==
            (dut.product_writer_metadata_load ? dut.staged_product_metadata : dut.product_writer_metadata))===1'b1)};
      end
    end
  end
  task automatic report_product_stage;
    begin
      if(product_slot_checks<1000 || product_slot_pushes<6144 || product_reference_updates<12)
        $fatal(1,"actual product stage coverage missing");
      $display("STAGED_PRODUCT_STAGE_PASS pushes=%0d pops=%0d checks=%0d updates=%0d holds=%0d original_identity=1 private_conservation=1",product_slot_pushes,product_slot_pops,product_slot_checks,product_reference_updates,product_slot_holds);
    end
  endtask
  // END ACTUAL PRODUCT STAGE WITNESS
  // BEGIN FORWARD RECEIPT WITNESS
  // Original immediate token, driven by actual qualified guard handshakes.
  reg original_forward_committed=0;
  integer forward_receipt_checks=0,forward_receipt_pending=0;
  always @(posedge fft_clk) begin
    if(!dut.fast_running) original_forward_committed<=0;
    else begin
      if(dut.return_commit_valid && dut.result_destination_ready && !dut.next_inverse)
        original_forward_committed<=1;
      if(!dut.registered_quarantine && dut.state==10 && dut.admission_receipt)
        original_forward_committed<=0;
    end
    #0.004;
    if(dut.fast_running===1'b1) begin
      forward_receipt_checks=forward_receipt_checks+1;
      if(dut.forward_receipt_wait!==original_forward_committed)
        $fatal(1,"forward receipt changed actual ACK readiness phase");
      if(dut.forward_committed!==original_forward_committed) begin
        if(dut.forward_committed!==0 || original_forward_committed!==1 || dut.guard_commit[0]!==1)
          $fatal(1,"forward token differs outside one-cycle qualified receipt");
        forward_receipt_pending=forward_receipt_pending+1;
      end
      if(dut.guard_ack[0] && dut.product_bank_valid!==1)
        $fatal(1,"forward ACK before actual product ownership");
      if(dut.product_commit_authorized &&
         (!original_forward_committed || dut.external_fault_now || dut.result_fault))
        $fatal(1,"forward receipt expanded publication authority");
    end
  end
  task automatic report_forward_receipt;
    begin
      if(forward_receipt_checks<1000 || forward_receipt_pending<10)
        $fatal(1,"forward receipt witness coverage missing");
      $display("STAGED_FORWARD_RECEIPT_PASS checks=%0d pending=%0d ack_exact=1 publication_subset=1",forward_receipt_checks,forward_receipt_pending);
    end
  endtask
  // END FORWARD RECEIPT WITNESS
  // Original ACK-state update, same live inputs, no control authority.
  starlink_pss_result_guard_owner_view #(.USE_COMPLETED_INPUT_FAULT(1),
    .CERTIFIED_PRIVATE_ADMISSION(1),.PRIVATE_ACK_RETIREMENT(0),
    .USE_PRIVATE_DESCRIPTOR_OFFER(1),.ENABLE_OFFERED_FAULT_SUMMARY(1),
    .REQUIRE_KNOWN_COMPLETED_INPUT(1),.USE_PREFLIGHT_REASON_ONLY(1),
    .USE_FORWARD_RETIREMENT(1)) original_inverse_ack (
    .clk(fft_clk),.resetn(dut.fast_running),
    .job_valid(dut.job_valid && dut.job_ready && dut.next_inverse==1),.job_ready(),.admission_capacity(),
    .private_descriptor_offer(dut.job_valid && dut.next_inverse==1),
    .job_descriptor(dut.engine_metadata),.input_bank_reserved(dut.engine_input_reserved),
    .output_bank_reserved(dut.retained_reserved),
    .certified_input_beat(dut.certified_input_beat && dut.routed_inverse==1),
    .certified_input_complete(dut.certified_input_complete && dut.routed_inverse==1),
    .offered_input_beat(dut.summary_offer_beat && dut.routed_inverse==1),
    .offered_input_complete(dut.summary_offer_complete && dut.routed_inverse==1),
    .offered_local_fault_now(),.offered_local_faults_now(),
    .final_fence_certified(dut.final_fence),.external_fault_now(dut.external_fault_now),
    .phase_input_fault_now(1'b0),.core_event_frame_started(dut.event_frame && dut.routed_inverse==1),
    .preflight_fault_evidence_now(dut.preparation_fault_now),
    .completed_input_certified(dut.checked_input_complete),.completed_input_fault_now(dut.completed_input_fault_now),
    .core_output_tdata(dut.core_output_data),.core_output_tuser(dut.core_output_user),
    .core_output_tvalid(dut.core_output_valid && dut.routed_inverse==1),.core_output_tlast(dut.core_output_last),
    .core_status_tdata(dut.core_status_data),.core_status_tvalid(dut.core_status_valid && dut.routed_inverse==1),
    .mailbox_input_valid(),.mailbox_private_valid(),.mailbox_commit_valid(),
    .mailbox_input_ready(dut.inverse_guard_ready),
    .mailbox_input_fault(dut.output_bank_fault || dut.output_bank_framing_fault_now),
    .inverse_phase(1'b1),.forward_mailbox_fault(dut.output_bank_fault),
    .forward_retirement_valid(),.forward_private_offer(),.mailbox_input_data(),.mailbox_input_position(),
    .mailbox_input_last(),.mailbox_input_metadata(),.busy(),.commit_pulse(),.protocol_fault(),.fault_reasons(),
    .owner_active(),.owner_awaiting_ack(),.owner_fault_now(),.owner_ack_accept());
  integer private_ack_checks=0,private_ack_quarantine_cycles=0;
  always @(posedge fft_clk) begin
    #0.001;
    if(dut.fast_running) begin
      if({dut.owners[1].result_guard.job_ready,dut.owners[1].result_guard.admission_capacity,
          dut.owners[1].result_guard.mailbox_input_valid,
          dut.owners[1].result_guard.mailbox_commit_valid,dut.owners[1].result_guard.owner_ack_accept,
          dut.owners[1].result_guard.fault_reasons,dut.owners[1].result_guard.active,
          dut.guard_return_data[1],dut.guard_return_metadata[1],dut.guard_return_position[1],dut.guard_last_out[1]} !==
         {original_inverse_ack.job_ready,original_inverse_ack.admission_capacity,
          original_inverse_ack.mailbox_input_valid,
          original_inverse_ack.mailbox_commit_valid,original_inverse_ack.owner_ack_accept,
          original_inverse_ack.fault_reasons,original_inverse_ack.active,
          original_inverse_ack.mailbox_input_data,original_inverse_ack.mailbox_input_metadata,
          original_inverse_ack.mailbox_input_position,original_inverse_ack.mailbox_input_last})
        $fatal(1,"private ACK public/diagnostic outputs differ");
      if(dut.owners[1].result_guard.awaiting_ack!==original_inverse_ack.awaiting_ack) begin
        if(dut.owners[1].result_guard.awaiting_ack!==0 || original_inverse_ack.awaiting_ack!==1 ||
           dut.owners[1].result_guard.protocol_fault!==1 || original_inverse_ack.protocol_fault!==1 ||
           dut.owners[1].result_guard.job_ready!==0 || dut.owners[1].result_guard.owner_ack_accept!==0)
          $fatal(1,"private ACK occupancy difference not quarantined");
        private_ack_quarantine_cycles=private_ack_quarantine_cycles+1;
      end
      private_ack_checks=private_ack_checks+1;
    end
  end
  reg [35:0] forwards[0:1535],products[0:1535],inverses[0:1535];
  reg [4:0] fe[0:2],ie[0:2];
  integer mode=0,fast_cycles=0,slow_cycles=0,reads=0,jobs=0,publications=0,releases=0;
  integer forward_words=0,product_words=0,inverse_words=0,inputs=0,raws=0,statuses=0,frames=0;
  integer fixture=0,raw_position=0,input_count=0,last_forward=-1,max_service=0;
  integer overlap_inputs=0,overlap_reads=0,publication_cycle=0;
  reg phase=0,old_request=0,stalled=0;
  reg [120:0] held_output;
  reg [35:0] expected;
  integer log_file;
  integer publication_phase_checks=0,replay_phase_checks=0,preflight_unread_checks=0;
  integer stalled_publication_checks=0;
  reg [69:0] legacy_engine_metadata=0;
  integer engine_capture_checks=0,engine_private_differences=0;
  always @(posedge fft_clk) begin
    if(!dut.fast_running) legacy_engine_metadata<=0;
    else if(dut.registered_quarantine) begin end
    else if(dut.state==2 && dut.selected_valid && dut.destination_reserved)
      legacy_engine_metadata<=dut.selected_metadata;
  end
  always @(negedge fft_clk) begin
    #0.003;
    if(dut.fast_running===1'b1) begin
      engine_capture_checks=engine_capture_checks+1;
      if(dut.engine_metadata!==legacy_engine_metadata) begin
        engine_private_differences=engine_private_differences+1;
        if((dut.state!=2 && dut.state!=8) || dut.job_accept || dut.config_valid ||
           dut.core_input_valid || dut.output_complete_accept || dut.output_replay_accept)
          $fatal(1,"private engine descriptor reached an owned/public operation");
      end
    end
  end
  // Independent private-slot scoreboard across the actual FFT/core resets.
  integer input_stage_pushes=0,input_stage_pops=0,input_stage_checks=0,input_stage_final_holds=0;
  reg input_stage_owned=0;
  reg [35:0] input_stage_saved_data;
  reg [8:0] input_stage_saved_position;
  reg input_stage_saved_last,input_stage_saved_good;
  always @(posedge fft_clk) begin
    if(!dut.core_aresetn || dut.staged_input_fault) input_stage_owned=0;
    else begin
      if(dut.staged_input_valid!==input_stage_owned)
        $fatal(1,"actual FFT private input-stage occupancy mismatch");
      if(dut.staged_input_valid) begin
        input_stage_checks=input_stage_checks+1;
        if({dut.staged_input_data,dut.staged_input_position,dut.staged_input_last,dut.staged_identity_good} !==
           {input_stage_saved_data,input_stage_saved_position,input_stage_saved_last,input_stage_saved_good})
          $fatal(1,"actual FFT staged payload/identity changed");
        if(dut.staged_input_last && !dut.checked_input_complete) begin
          input_stage_final_holds=input_stage_final_holds+1;
          if(!dut.engine_input_reserved || !dut.staged_input_closed)
            $fatal(1,"buffered final word lost admitted ownership");
        end
      end
      if(dut.staged_input_valid && dut.transport_ready) begin
        input_stage_owned=0;input_stage_pops=input_stage_pops+1;
      end
      if(dut.staged_input_offer && dut.staged_input_ready) begin
        if(input_stage_owned || dut.staged_input_closed || dut.engine_metadata!==dut.input_guard.descriptor)
          $fatal(1,"input-stage overwrite/next-job descriptor capture");
        input_stage_owned=1;input_stage_pushes=input_stage_pushes+1;
        input_stage_saved_data=dut.guard_data;input_stage_saved_position=dut.guard_position;
        input_stage_saved_last=dut.guard_last;
        input_stage_saved_good=(dut.guard_metadata==dut.input_guard.descriptor)===1'b1;
      end
    end
  end
  reg publication_probe_paused=0;
  // Reachable-phase evidence, not an arbitrary-input combinational identity.
  // FFT producer reuse is publication-gated, not reader-release-gated.
  always @(negedge fft_clk) begin
    #0.002;
    if(dut.fast_running) begin
      publication_phase_checks=publication_phase_checks+1;
      if(dut.output_replay_valid===1'b1) begin
        replay_phase_checks=replay_phase_checks+1;
        if(dut.preparing!==1'b0 || dut.preflight_events_now!==6'b0 || dut.summary_preflight_events!==6'b0)
          $fatal(1,"unpublished inverse replay overlapped preflight validation");
      end
      if(dut.preparing && dut.output_publication_busy && dut.retained_published && !dut.output_bank_ready)
        preflight_unread_checks=preflight_unread_checks+1;
      if(publication_probe_paused) begin
        stalled_publication_checks=stalled_publication_checks+1;
        if(dut.preparing!==1'b0 || dut.next_inverse!==1'b1 ||
           dut.producer_transfer_receipt!==1'b0 || dut.completion_request!==1'b0 ||
           dut.completion_accept!==1'b0 || dut.output_published_valid!==1'b0)
          $fatal(1,"paused publication permitted early producer reuse");
      end
    end
  end
  reg stress=0,stress_drain=0,stress_fault_expected=0;
  integer stress_reads=0,stress_fixture=0,stress_prefix=0,stress_releases=0;
  integer handover_admissions=0,handover_completions=0,slow_edges=0;
  reg previous_admission=0,previous_completion=0;
  integer capture_load_checks=0,capture_hold_checks=0,capture_accept_checks=0;
  reg [177:0] capture_before,capture_inputs;
  reg capture_was_open,capture_was_accept,capture_was_release;
  // Clock-by-clock payload contract in every healthy numerical context. Fault
  // injection below deliberately corrupts held registers, so has its own checks.
  always @(posedge fft_clk) begin
    if(dut.fast_running && !stress) begin
      capture_before={dut.output_descriptor_tag,dut.output_descriptor_payload,
        dut.output_descriptor_expected,dut.output_descriptor_lookup_ok};
      capture_inputs={dut.inverse_tag,dut.output_lookup_descriptor,dut.guard_return_metadata[1][4:0],
        dut.guard_return_metadata[1][74:5],(dut.output_lookup_found===1'b1 && dut.output_lookup_committed===1'b0)};
      capture_was_open=dut.output_descriptor_capture;
      capture_was_accept=dut.output_complete_accept;
      capture_was_release=dut.output_released_valid;
      #0.001;
      if(dut.fast_running) begin
        if({dut.output_descriptor_tag,dut.output_descriptor_payload,
            dut.output_descriptor_expected,dut.output_descriptor_lookup_ok} !==
           (capture_was_open ? capture_inputs : capture_before))
          $fatal(1,"private descriptor load/freeze contract");
        if(capture_was_accept && !dut.output_descriptor_locked)
          $fatal(1,"accepted descriptor did not freeze");
        if(capture_was_release && dut.output_descriptor_locked)
          $fatal(1,"real release did not reopen private capture");
        if(capture_was_open) capture_load_checks=capture_load_checks+1;
        else capture_hold_checks=capture_hold_checks+1;
        if(capture_was_accept) capture_accept_checks=capture_accept_checks+1;
      end
    end
  end
  task automatic log_word(input string stream,input integer block_id,input integer position,
                input [47:0] data,input [9:0] exponent);
    $fdisplay(log_file,"%0d,%s,%0d,%0d,%012h,%03h",mode,stream,block_id,position,data,exponent);
  endtask
  // Real old-width certificate instances observe the same request, quarantine
  // and consumption events. They are witnesses only, not authorization paths.
  wire [21:0] guardfacts_legacy_admission = {!dut.next_inverse || dut.inverse_descriptor_live,
    dut.cutover_admission_capacity,dut.guard_capacity[dut.next_inverse],~dut.admission_reject};
  wire legacy_admission_permit,legacy_completion_permit;
  starlink_pss_admission_certificate #(.CHECKS(22)) legacy_admission (
    .clk(fft_clk),.resetn(dut.fast_running),.request(dut.admission_request),
    .quarantine(dut.registered_quarantine),.consume(dut.job_accept),
    .checks_good(guardfacts_legacy_admission),.permit(legacy_admission_permit),
    .snapshot_valid(),.snapshot_good());
  starlink_pss_admission_certificate #(.CHECKS(28)) legacy_completion (
    .clk(fft_clk),.resetn(dut.fast_running),.request(dut.completion_request),
    .quarantine(dut.registered_quarantine),.consume(dut.completion_accept),
    .checks_good(dut.completion_good),.permit(legacy_completion_permit),
    .snapshot_valid(),.snapshot_good());
  wire [21:0] compressed_admission = {dut.admission_gate.snapshot_good[35:24],
    (&dut.admission_gate.snapshot_good[23:16]),(&dut.admission_gate.snapshot_good[15:8]),
    dut.admission_gate.snapshot_good[7:0]};
  wire [27:0] compressed_completion = {dut.completion_gate.snapshot_good[41:24],
    (&dut.completion_gate.snapshot_good[23:16]),(&dut.completion_gate.snapshot_good[15:8]),
    dut.completion_gate.snapshot_good[7:0]};
  integer guardfacts_cycles=0;
  reg [7:0] guardfacts_mask;
  always @(posedge fft_clk) begin
    if(dut.fast_running) begin
      if((|dut.admission_reject_expanded)!==(|dut.admission_reject) ||
         (&dut.admission_checks)!==(&guardfacts_legacy_admission) ||
         (&dut.completion_checks)!==(&dut.completion_good))
        $fatal(1,"actual expanded current predicates differ");
      #0.001;
      if(dut.fast_running) begin
        if({dut.admission_permit,dut.admission_gate.snapshot_valid,dut.admission_gate.consumed} !==
           {legacy_admission_permit,legacy_admission.snapshot_valid,legacy_admission.consumed} ||
           (dut.admission_gate.snapshot_valid && compressed_admission!==legacy_admission.snapshot_good) ||
           {dut.completion_permit,dut.completion_gate.snapshot_valid,dut.completion_gate.consumed,compressed_completion} !==
           {legacy_completion_permit,legacy_completion.snapshot_valid,legacy_completion.consumed,legacy_completion.snapshot_good})
          $fatal(1,"actual old/expanded certificate state differs");
        guardfacts_cycles=guardfacts_cycles+1;
      end
    end
  end
  reg original_descriptor_certificate=0;
  // BEGIN PRIVATE ADMISSION FACTS WITNESS
  wire private_facts_reference_permit,private_facts_reference_valid;
  wire [35:0] private_facts_reference_good;
  starlink_pss_admission_certificate #(.CHECKS(36)) private_facts_reference (
    .clk(fft_clk),.resetn(dut.fast_running),.request(dut.admission_request),
    .quarantine(dut.registered_quarantine),.consume(dut.job_accept),
    .checks_good(dut.admission_checks),.permit(private_facts_reference_permit),
    .snapshot_valid(private_facts_reference_valid),.snapshot_good(private_facts_reference_good));
  integer private_facts_checks=0,private_facts_owned=0,private_facts_differences=0;
  always @(negedge fft_clk) begin
    #0.001;
    if(dut.fast_running)begin
      if({dut.admission_permit,dut.admission_gate.snapshot_valid,dut.admission_gate.consumed} !==
         {private_facts_reference_permit,private_facts_reference_valid,private_facts_reference.consumed})
        $fatal(1,"private admission control differs");
      private_facts_checks=private_facts_checks+1;
      if(dut.admission_gate.snapshot_valid)begin
        if(dut.admission_gate.snapshot_good!==private_facts_reference_good)
          $fatal(1,"private admission owned facts differ");
        private_facts_owned=private_facts_owned+1;
      end else if(dut.admission_gate.snapshot_good!==private_facts_reference_good)
        private_facts_differences=private_facts_differences+1;
    end
  end
  task automatic report_private_admission_facts;
    begin
      if(private_facts_checks<1000 || private_facts_owned<10 || private_facts_differences<100)
        $fatal(1,"private admission witness coverage short");
      $display("STAGED_PRIVATE_FACTS_PASS checks=%0d owned=%0d invalid_differences=%0d permit_exact=1 owned_exact=1",private_facts_checks,private_facts_owned,private_facts_differences);
    end
  endtask
  // END PRIVATE ADMISSION FACTS WITNESS
  integer certificate_checks=0,certificate_private_differences=0;
  always @(posedge fft_clk) begin
    if(!dut.fast_running) original_descriptor_certificate=0;
    else begin
      if(dut.state==9) original_descriptor_certificate=dut.preparation_valid && !dut.any_fast_fault;
      if(dut.registered_quarantine) original_descriptor_certificate=0;
      else if((dut.state==2 && dut.selected_valid && dut.destination_reserved) ||
              (dut.state==10 && dut.admission_receipt)) original_descriptor_certificate=0;
      #0.001;
      if(dut.fast_running) begin
        certificate_checks=certificate_checks+1;
        if(dut.descriptor_certified!==original_descriptor_certificate) begin
          certificate_private_differences=certificate_private_differences+1;
          if(dut.registered_quarantine!==1'b1 || dut.job_accept!==1'b0 ||
             dut.input_job_start!==1'b0 || dut.config_valid!==1'b0 || dut.core_input_valid!==1'b0)
            $fatal(1,"private descriptor difference escaped quarantine");
        end
      end
    end
  end
  reg [8:0] sequence_index_before;
  reg [63:0] sequence_next_before,sequence_input_next;
  reg sequence_previous_before,sequence_advance;
  reg [7:0] sequence_late_status;
  integer sequence_advances=0,sequence_holds=0,sequence_finals=0;
  always @(posedge fft_clk) begin
    if(dut.fast_running) begin
      sequence_index_before=dut.joiner.kernel_rom.expected_bin_index;
      sequence_next_before=dut.joiner.kernel_rom.expected_next_block_start;
      sequence_previous_before=dut.joiner.kernel_rom.have_previous_block;
      sequence_input_next=dut.joiner.kernel_rom.input_block_start_index+64'd447;
      sequence_advance=dut.joiner.kernel_rom.private_sequence_accept;
      if(sequence_advance!==1'b0 && sequence_advance!==1'b1) $fatal(1,"unknown private sequence handshake");
      if(dut.joiner.input_accept && !sequence_advance) $fatal(1,"public kernel input lacked private offer");
      if(!dut.common_current_fault && !dut.fast_fault && !dut.kernel_fault &&
         sequence_advance!==dut.joiner.input_accept) $fatal(1,"healthy private/public sequence divergence");
      #0.001;
      if(dut.fast_running) begin
        if(dut.joiner.kernel_rom.expected_bin_index !==
           (sequence_advance ? 9'(sequence_index_before+1) : sequence_index_before))
          $fatal(1,"private sequence index advance/hold");
        if({dut.joiner.kernel_rom.have_previous_block,dut.joiner.kernel_rom.expected_next_block_start} !==
           (sequence_advance && sequence_index_before==511 ? {1'b1,sequence_input_next} :
            {sequence_previous_before,sequence_next_before})) $fatal(1,"private sequence next-block advance/hold");
        if(!stress) begin
          if(sequence_advance) begin
            sequence_advances=sequence_advances+1;
            if(sequence_index_before==511) sequence_finals=sequence_finals+1;
          end else sequence_holds=sequence_holds+1;
        end
      end
    end
  end
  // Full campaign check: private adapter payload tracks only in EMPTY, while
  // every accepted/owned payload equals the original qualified capture.
  integer final_loads=0,final_holds=0,final_accepts=0,final_fault_loads=0;
  reg [68:0] final_before,final_inputs,final_original=0;
  reg final_open,final_accept,final_fault;
  always @(posedge fft_clk) begin
    if(!dut.fast_running) final_original=0;
    else begin
      final_before={dut.output_control.active_tag,dut.output_control.final_data,dut.output_control.initial_request};
      final_inputs={dut.inverse_tag,dut.guard_return_data[1],dut.output_request};
      final_open=!dut.output_publication_busy;
      final_accept=!dut.output_control.fault && dut.output_complete_valid && dut.output_complete_ready;
      final_fault=dut.output_control.fault;
      if(final_accept) final_original=final_inputs;
      #0.001;
      if(dut.fast_running) begin
        if({dut.output_control.active_tag,dut.output_control.final_data,dut.output_control.initial_request} !==
           (final_open ? final_inputs : final_before)) $fatal(1,"actual private final load/hold");
        if(dut.output_publication_busy &&
           {dut.output_control.active_tag,dut.output_control.final_data,dut.output_control.initial_request}!==final_original)
          $fatal(1,"actual accepted final differs from original");
        if(final_accept && !dut.output_publication_busy) $fatal(1,"actual final ownership missing");
        if(final_open) begin
          final_loads=final_loads+1;
          if(final_fault) final_fault_loads=final_fault_loads+1;
        end else final_holds=final_holds+1;
        if(final_accept) final_accepts=final_accepts+1;
      end
    end
  end
  always @(negedge clk) begin
    slow_cycles=slow_cycles+1;
    output_ready=stress ? stress_drain : mode==0 ? 1 : mode==1 ? slow_cycles%17<13 :
      mode==5 ? (!output_last || reads>=1024 || dut.forward_committed) :
      (dut.retained_published && fast_cycles-publication_cycle>(mode==2 ? 2200 : mode==4 ? 500 : 9000));
  end
  always @(posedge clk) begin
    slow_edges=slow_edges+1;
    if(resetn && fft_resetn && !stress) begin
      if(stalled && output_valid && held_output!=={output_data,output_position,output_last,output_metadata})
        $fatal(1,"stalled output changed");
      stalled=output_valid && !output_ready;held_output={output_data,output_position,output_last,output_metadata};
      if(output_valid && output_ready) begin
        if(reads>=1536 || output_position!==9'(reads%512) || output_last!==(reads%512==511) ||
           output_data!==inverses[reads] ||
           output_metadata!=={1'b1,64'(context_start_base+(reads/512)*447),fe[reads/512],ie[reads/512]} ||
           (^dut.output_control.committed===1'bx) || dut.output_control.committed==0 ||
           dut.reader_descriptor_tag!==dut.output_bank_metadata[36:5])
          $fatal(1,"native numerical/metadata output mismatch read=%0d",reads);
        log_word("read",reads/512,reads%512,{12'b0,output_data},output_metadata[9:0]);
        if(!dut.routed_inverse && dut.cutover.owner_open) overlap_reads=overlap_reads+1;
        reads=reads+1;
      end
    end else stalled=0;
    if(stress && resetn && fft_resetn && output_valid && output_ready) begin
      if(stress_reads>=512 || output_position!==9'(stress_reads) || output_last!==(stress_reads==511) ||
         output_data!==inverses[stress_fixture*512+stress_reads] ||
         output_metadata!=={1'b1,64'(1000+stress_fixture*447),fe[stress_fixture],ie[stress_fixture]})
        $fatal(1,"stress fresh output/descriptor mismatch");
      stress_reads=stress_reads+1;
    end
    if(output_valid && !dut.slow_metadata_valid) $fatal(1,"reader escaped metadata register boundary");
  end
  always @(posedge fft_clk) begin
    fast_cycles=fast_cycles+1;
    if(dut.fast_running && !stress) begin
      if(mode==0 && fast_cycles>=2748 && fast_cycles<=2760)
        $display("STAGED_TRACE cycle=%0d state=%0d known=%b job=%b config=%b close=%b common=%b ready=%b inverse_ready=%b live=%b pending=%b ctlphase=%0d ctlcmd=%0d guardfault=%b preflight=%h",
          fast_cycles,dut.state,dut.cutover.known,dut.job_accept,dut.cutover.config_accept,dut.completion_accept,
          dut.common_current_fault,dut.guard_ready,dut.inverse_guard_ready,dut.inverse_descriptor_live,
          dut.inverse_allocation_pending,dut.output_control.phase,dut.output_control.command_state,
          dut.guard_fault,dut.preflight_events_now);
      if(fault!==0 || dut.any_fast_fault!==0)
        $fatal(1,"FFT staged health mode=%0d cycle=%0d state=%0d cut=%h F=%h I=%h adapter=%b preflight=%h",
          mode,fast_cycles,dut.state,dut.cutover_reasons,dut.owners[0].result_guard.faults_now,
          dut.owners[1].result_guard.faults_now,dut.output_control_fault,dut.preflight_events_now);
      if(dut.job_accept) begin
        if(dut.engine_metadata[68:5]<context_start_base || (dut.engine_metadata[68:5]-context_start_base)%447!=0)
          $fatal(1,"admission timestamp mismatch");
        fixture=(dut.engine_metadata[68:5]-context_start_base)/447;phase=dut.next_inverse;
        if(fixture>2 || phase!==jobs[0]) $fatal(1,"job order mismatch");
        jobs=jobs+1;raw_position=0;input_count=0;
        if(!phase) begin
          if(last_forward>=0 && fast_cycles-last_forward>max_service) max_service=fast_cycles-last_forward;
          last_forward=fast_cycles;
        end
      end
      if(dut.core_input_valid && dut.core_input_ready) begin
        expected=phase ? products[fixture*512+input_count] :
          {samples[fixture*447+input_count][31:16],2'b0,samples[fixture*447+input_count][15:0],2'b0};
        if(input_count>=512 || dut.core_input_data!=={6'b0,expected[35:18],6'b0,expected[17:0]} ||
           dut.core_input_last!==(input_count==511)) $fatal(1,"core input mismatch");
        if(dut.retained_published && !phase) overlap_inputs=overlap_inputs+1;
        if(phase) log_word("inputI",fixture,input_count,dut.core_input_data,0);
        else log_word("inputF",fixture,input_count,dut.core_input_data,0);
        inputs=inputs+1;input_count=input_count+1;
      end
      if(dut.event_frame) frames=frames+1;
      if(dut.core_status_valid) begin
        if(raw_position!=2 || dut.core_status_data!=={3'b0,(phase?ie[fixture]:fe[fixture])})
          $fatal(1,"core status mismatch");
        statuses=statuses+1;
      end
      if(dut.core_output_valid) begin
        expected=phase?inverses[fixture*512+raw_position]:forwards[fixture*512+raw_position];
        if(raw_position>=512 || input_count!=512 ||
           dut.core_output_data!=={{6{expected[35]}},expected[35:18],{6{expected[17]}},expected[17:0]} ||
           dut.core_output_user!=={3'b0,(phase?ie[fixture]:fe[fixture]),7'b0,9'(raw_position)} ||
           dut.core_output_last!==(raw_position==511)) $fatal(1,"raw FFT numerical mismatch");
        if(phase) log_word("rawI",fixture,raw_position,dut.core_output_data,{5'b0,ie[fixture]});
        else log_word("rawF",fixture,raw_position,dut.core_output_data,{5'b0,fe[fixture]});
        raw_position=raw_position+1;raws=raws+1;
      end
      if(dut.forward_retirement_valid && dut.product_bank_ready && dut.kernel_ready) begin
        if(dut.return_data!==forwards[forward_words] || dut.return_position!==9'(forward_words%512))
          $fatal(1,"forward retirement mismatch");
        forward_words=forward_words+1;
      end
      if(dut.product_valid && dut.product_stage_ready) begin
        if({dut.product_q,dut.product_i}!==products[product_words] || dut.product_position!==9'(product_words%512))
          $fatal(1,"product mismatch");
        log_word("product",product_words/512,product_words%512,{12'b0,dut.product_q,dut.product_i},{5'b0,dut.product_exponent});
        product_words=product_words+1;
      end
      if(dut.guard_private_out[1] && dut.output_bank_ready) begin
        if(dut.guard_return_data[1]!==inverses[inverse_words] || dut.guard_return_position[1]!==9'(inverse_words%512))
          $fatal(1,"private inverse mismatch");
        log_word("privateI",inverse_words/512,inverse_words%512,{12'b0,dut.guard_return_data[1]},dut.guard_return_metadata[1][9:0]);
        inverse_words=inverse_words+1;
      end
      if(dut.output_request!==old_request) begin
        old_request=dut.output_request;publications=publications+1;publication_cycle=fast_cycles;
        if(dut.output_control.ledger.committed==0) $fatal(1,"publication without staged commit");
      end
      if(dut.reader_release) begin
        if(reads!=(releases+1)*512 || dut.output_request!==dut.output_ack_sync)
          $fatal(1,"early real-reader release");
        releases=releases+1;
      end
    end
  end
  // Receipt timing and physical core reset ordering, across all contexts.
  always @(posedge fft_clk) begin
    if(!dut.fast_running) begin previous_admission=0;previous_completion=0;end
    else begin
      if ((|dut.admission_reject)!==dut.common_current_fault)
        $fatal(1,"partitioned admission facts differ from full current predicate");
      if(dut.output_complete_accept && dut.inverse_descriptor_live!==1'b1)
        $fatal(1,"completion sampled private lookup without held ownership");
      if(dut.output_complete_accept && dut.output_descriptor_capture!==1'b1)
        $fatal(1,"completion missed its private descriptor capture");
      if(dut.output_descriptor_pending && !dut.output_descriptor_locked)
        $fatal(1,"pending descriptor was not frozen");
      if(dut.output_descriptor_pending && (dut.output_descriptor_valid || dut.output_replay_accept || dut.output_complete_accept))
        $fatal(1,"writer validation pending was overwritten or authorized output");
      if(dut.output_replay_accept!==(dut.output_replay_valid && dut.output_replay_private_ready && !dut.common_current_fault))
        $fatal(1,"private replay replaced current publication authorization");
      if(dut.completion_request && (((&dut.completion_good)===1'b1)!==(dut.legacy_completion_accept===1'b1)))
        $fatal(1,"completion facts differ from original close validation");
      if(dut.completion_accept && (!dut.completion_gate.snapshot_valid || !dut.completion_permit))
        $fatal(1,"producer close bypassed clocked facts");
      if(dut.job_accept && (!dut.admission_gate.snapshot_valid || !dut.admission_permit))
        $fatal(1,"private admission bypassed clocked certificate");
      if(dut.admission_receipt!==previous_admission || dut.completion_receipt!==previous_completion)
        $fatal(1,"handover receipt is not previous-edge validation");
      if(dut.cutover.job_accept!==(dut.admission_receipt && !dut.registered_quarantine) ||
         dut.cutover.producer_closed!==(dut.completion_receipt && !dut.registered_quarantine))
        $fatal(1,"raw validation bypassed registered handover");
      if(dut.cutover.job_accept) begin
        if(dut.core_aresetn!==0 || (!stress_fault_expected && dut.cutover_admission_allowed!==1))
          $fatal(1,"handover admitted before reset flush");
        handover_admissions=handover_admissions+1;
      end
      if(dut.cutover.producer_closed) begin
        if(dut.state!=7 || dut.core_aresetn!==1) $fatal(1,"handover closed outside owned producer");
        handover_completions=handover_completions+1;
      end
      previous_admission=dut.job_accept;previous_completion=dut.completion_accept;
      if(stress) begin
        if(!stress_fault_expected && (fault!==0 || dut.any_fast_fault!==0)) $fatal(1,"healthy reset stress fault");
        if(dut.core_input_valid && dut.core_input_ready && !dut.routed_inverse && dut.engine_metadata[68:5]==1447)
          stress_prefix=stress_prefix+1;
        if(dut.reader_release) stress_releases=stress_releases+1;
      end
    end
  end
  task automatic stress_reset;
    begin
      @(negedge fft_clk);resetn=0;fft_resetn=0;input_valid=0;stress_drain=0;
      repeat(10) @(negedge fft_clk);
      stress_reads=0;stress_prefix=0;stress_releases=0;stress_fault_expected=0;
      resetn=1;fft_resetn=1;
      while(!dut.fast_running) @(negedge fft_clk);
    end
  endtask
  task automatic input_stage_boundary(input integer boundary);
    reg request_before;
    integer owner,bad_position;
    begin
      stress_reset;stress_fixture=0;send_block(0);
      owner=boundary%2;bad_position=(boundary==1 || boundary==2)?511:7;
      if(boundary<4) begin
        while(!dut.staged_input_offer || !dut.staged_input_ready ||
              dut.routed_inverse!=owner || dut.guard_position!=bad_position) @(negedge fft_clk);
        request_before=dut.output_request;stress_fault_expected=1;
        if(boundary>=2) force dut.guard_metadata[69]=1'bx;
        else if(owner==0) force dut.guard_metadata[69]=1'b1;
        else force dut.guard_metadata[69]=1'b0;
        @(posedge fft_clk);#0.001;
        if(dut.staged_identity_good!==0 || dut.checked_fault_now!==1 ||
           dut.certified_input_beat!==0 || dut.core_input_valid!==0 ||
           dut.checked_input_complete!==0 || dut.input_guard.expected_position!==9'(bad_position))
          $fatal(1,"bad captured identity reached FFT or completion boundary=%0d",boundary);
        @(posedge fft_clk);#0.001;
        if(dut.fast_fault!==1)$fatal(1,"staged identity did not latch epoch quarantine");
        @(negedge fft_clk);release dut.guard_metadata[69];
      end else begin
        while(!dut.staged_input_valid || !dut.staged_input_last || dut.routed_inverse!==1'b1)
          @(negedge fft_clk);
        request_before=dut.output_request;stress_fault_expected=1;
        if(dut.checked_input_complete || !dut.engine_input_reserved || !dut.staged_input_closed)
          $fatal(1,"reset target did not own buffered final inverse word");
        if(boundary==4) fft_resetn=0;else resetn=0;
        repeat(10)@(negedge fft_clk);
        resetn=1;fft_resetn=1;request_before=dut.output_request;
      end
      repeat(100)begin
        @(negedge fft_clk);
        if(dut.output_request!==request_before || dut.output_published_valid ||
           dut.output_released_valid || dut.reader_release || dut.core_input_valid ||
           dut.job_accept || dut.config_valid || dut.staged_input_valid)
          $fatal(1,"staged input cancellation escaped epoch boundary=%0d",boundary);
      end
      if(stress_reads || stress_releases || (boundary<4 && !fault))
        $fatal(1,"staged identity cancellation missing evidence");
      stress_reset;stress_fixture=0;send_block(0);stress_drain=1;
      while(stress_reads!=512 || !dut.retained_reusable)@(negedge fft_clk);
      repeat(10)@(negedge fft_clk);
      if(fault || stress_releases!=1)$fatal(1,"staged input fresh recovery failed");
      $display("STAGED_INPUT_IDENTITY_CASE_PASS boundary=%0d stale_reads=0 publications=0 fresh_reads=512 fresh_releases=1",boundary);
    end
  endtask
  // BEGIN FORWARD RECEIPT BOUNDARIES
  task automatic forward_receipt_boundary(input integer boundary);
    integer stage,action;
    reg request_before;
    begin
      stage=boundary/4;action=boundary%4;
      stress_reset;stress_fixture=0;send_block(0);
      if(stage==0)begin
        while(!(dut.return_commit_valid && dut.result_destination_ready && !dut.next_inverse))
          @(negedge fft_clk);
      end else if(stage==1)begin
        while(!dut.guard_commit[0]) @(negedge fft_clk);
        if(dut.forward_committed!==0 || dut.forward_receipt_wait!==1)
          $fatal(1,"qualified receipt window not exercised");
      end else begin
        while(!dut.forward_committed) @(negedge fft_clk);
      end
      request_before=dut.output_request;
      if(action!=3)begin
        stress_fault_expected=1;
        if(action==0) force dut.event_last_missing=1'b1;
        else if(action==1) fft_resetn=0;
        else resetn=0;
        #0.001;
        if((action==0 && dut.product_commit_authorized!==0) || dut.guard_ack[0]!==0 ||
           (action!=0 && dut.product_bank.in_running!==0))
          $fatal(1,"forward receipt fault/reset did not veto authority");
        @(posedge fft_clk);#0.001;@(negedge fft_clk);
        release dut.event_last_missing;
        if(action!=0)begin
          repeat(10) @(negedge fft_clk);resetn=1;fft_resetn=1;
          request_before=dut.output_request;
        end
        repeat(100)begin
          @(negedge fft_clk);
          if(dut.output_request!==request_before || dut.output_released_valid ||
             dut.product_commit_authorized || dut.guard_ack[0])
            $fatal(1,"stale forward receipt escaped quarantine/reset");
        end
        if(stress_reads!=0 || stress_releases!=0 || (action==0 && !fault))
          $fatal(1,"forward receipt cancellation evidence missing");
        stress_reset;stress_fixture=0;send_block(0);
      end
      stress_drain=1;
      while(stress_reads!=512 || !dut.retained_reusable) @(negedge fft_clk);
      repeat(10) @(negedge fft_clk);
      if(fault || stress_releases!=1)$fatal(1,"forward receipt fresh recovery failed");
      $display("STAGED_FORWARD_RECEIPT_CASE_PASS boundary=%0d fresh_reads=512 fresh_releases=1",boundary);
    end
  endtask
  // END FORWARD RECEIPT BOUNDARIES
  // BEGIN ACTUAL PRODUCT STAGE BOUNDARIES
  task automatic product_stage_boundary(input integer boundary);
    reg request_before;
    begin
      stress_reset;stress_fixture=0;send_block(0);
      if(boundary<4 || boundary==11)begin
        while(!(dut.product_valid && dut.product_stage_ready &&
                dut.product_position==(boundary<2 || boundary==11 ? 1 : 511)))@(negedge fft_clk);
      end else if(boundary==4 || boundary==5 || boundary==8)begin
        while(!dut.product_writer_metadata_load)@(negedge fft_clk);
        if(!dut.product_stage_ready)$fatal(1,"first-reference continuous refill missing");
      end else begin
        while(!dut.staged_product_valid || !dut.staged_product_last)@(negedge fft_clk);
        force dut.product_bank_ready=1'b0;
        repeat(32)begin
          @(negedge fft_clk);
          if(!dut.staged_product_valid || !dut.staged_product_last || dut.staged_product_ready ||
             dut.product_bank_valid || dut.guard_ack[0])$fatal(1,"held product LAST published or dropped");
        end
      end
      request_before=dut.output_request;
      if(boundary!=8 && boundary!=9)begin
        stress_fault_expected=1;
        if(boundary<4)begin
          if(boundary%2==0)force dut.product_start=64'h20000000000003e8;
          else force dut.product_start=64'bx;
        end else if(boundary==4 || boundary==6)fft_resetn=0;
        else if(boundary==5 || boundary==7)resetn=0;
        else if(boundary==10)force dut.event_last_missing=1'b1;
        else force dut.product_valid=1'bx;
        @(posedge fft_clk);#0.001;@(negedge fft_clk);
        release dut.product_start;release dut.product_valid;release dut.event_last_missing;
        release dut.product_bank_ready;
        if(boundary>=4 && boundary<=7)begin
          repeat(10)@(negedge fft_clk);resetn=1;fft_resetn=1;request_before=dut.output_request;
        end
        repeat(100)begin
          @(negedge fft_clk);
          if(dut.output_request!==request_before || dut.output_released_valid || dut.guard_ack[0] ||
             dut.product_commit_authorized || output_valid)
            $fatal(1,"bad product stage word escaped cancellation");
        end
        if(stress_reads!=0 || stress_releases!=0 || ((boundary<4 || boundary>=10) && !fault))
          $fatal(1,"actual product stage cancellation evidence missing");
        stress_reset;stress_fixture=0;send_block(0);
      end
      release dut.product_bank_ready;
      stress_drain=1;
      while(stress_reads!=512 || !dut.retained_reusable)@(negedge fft_clk);
      repeat(10)@(negedge fft_clk);
      if(fault || stress_releases!=1)$fatal(1,"actual product stage fresh recovery failed");
      $display("STAGED_PRODUCT_STAGE_CASE_PASS boundary=%0d fresh_reads=512 fresh_releases=1",boundary);
    end
  endtask
  // END ACTUAL PRODUCT STAGE BOUNDARIES
  // BEGIN OUTPUT METADATA BOUNDARIES
  task automatic output_metadata_boundary(input integer boundary);
    reg request_before;
    begin
      stress_reset;stress_fixture=0;send_block(0);
      if(boundary<2)begin
        while(!(dut.output_bank.input_accept && !dut.output_publication_busy &&
                dut.output_bank.input_position==(boundary==0 ? 1 : 511)))@(negedge fft_clk);
      end else while(!dut.output_replay_valid)@(negedge fft_clk);
      request_before=dut.output_request;stress_fault_expected=1;
      if(boundary<2)begin
        force dut.inverse_tag=32'h80000000;
      end else if(boundary<4)begin
        if(boundary==2)force dut.output_replay_tag=32'h80000000;
        else force dut.output_descriptor_payload[4:0]=5'h1f;
      end else if(boundary==4)fft_resetn=0;
      else resetn=0;
      #0.001;
      $display("OUTPUT_METADATA_INJECTION boundary=%0d valid=%b ready=%b position=%0d selected=%h held=%h live=%h replay=%h match=%b framing=%b replay_accept=%b common=%b fault=%b",
        boundary,dut.output_bank.input_valid,dut.output_bank.input_ready,dut.output_bank.input_position,
        dut.output_bank.input_metadata,dut.output_bank.metadata_in_hold,dut.output_bank.input_metadata_live,
        dut.output_bank.input_metadata_replay,dut.output_bank.metadata_matches,dut.output_bank_framing_fault_now,
        dut.output_replay_accept,dut.common_current_fault,fault);
      if(boundary<4 && (dut.output_bank_framing_fault_now!==1 || dut.output_replay_accept!==0))
        $fatal(1,"selected output metadata failed immediate framing/publication veto");
      if(boundary<4 && dut.output_bank.input_metadata===dut.output_bank.metadata_in_hold)
        $fatal(1,"output metadata injection did not reach selected branch");
      @(posedge fft_clk);#0.001;@(negedge fft_clk);
      release dut.inverse_tag;release dut.output_replay_tag;release dut.output_descriptor_payload[4:0];
      if(boundary>=4)begin
        repeat(10)@(negedge fft_clk);resetn=1;fft_resetn=1;request_before=dut.output_request;
      end
      repeat(100)begin
        @(negedge fft_clk);
        if(dut.output_request!==request_before || dut.output_published_valid || dut.output_released_valid ||
           dut.output_replay_accept || output_valid)
          $fatal(1,"output metadata cancellation escaped quarantine");
      end
      if(stress_reads!=0 || stress_releases!=0 || (boundary<4 && !fault))
        $fatal(1,"missing actual output metadata cancellation evidence");
      stress_reset;stress_fixture=0;send_block(0);stress_drain=1;
      while(stress_reads!=512 || !dut.retained_reusable)@(negedge fft_clk);
      repeat(10)@(negedge fft_clk);
      if(fault || stress_releases!=1)$fatal(1,"output metadata fresh recovery failed");
      $display("STAGED_OUTPUT_METADATA_CASE_PASS boundary=%0d fresh_reads=512 fresh_releases=1",boundary);
    end
  endtask
  // END OUTPUT METADATA BOUNDARIES
  // BEGIN COMPLETION MAILBOX BOUNDARIES
  task automatic completion_slot_boundary(input integer boundary);
    reg request_before;
    begin
      stress_reset;stress_fixture=0;send_block(0);
      while(!dut.output_control.complete_pending)@(negedge fft_clk);
      if(!dut.output_publication_busy || dut.output_control.phase!==3'd0 || dut.output_complete_ready)
        $fatal(1,"actual test did not reach reserved pending receipt");
      request_before=dut.output_request;stress_fault_expected=1;
      if(boundary==0)force dut.event_last_missing=1'b1;
      else if(boundary==1)resetn=0;
      else fft_resetn=0;
      @(posedge fft_clk);#0.001;@(negedge fft_clk);
      release dut.event_last_missing;
      if(boundary!=0)begin
        repeat(10)@(negedge fft_clk);resetn=1;fft_resetn=1;request_before=dut.output_request;
      end
      repeat(100)begin
        @(negedge fft_clk);
        if(dut.output_request!==request_before || dut.output_published_valid || dut.output_released_valid || dut.output_replay_accept || output_valid)
          $fatal(1,"pending completion cancellation escaped quarantine");
      end
      if(stress_reads!=0 || stress_releases!=0 || (boundary==0 && !fault))
        $fatal(1,"missing pending completion cancellation evidence");
      stress_reset;stress_fixture=0;send_block(0);stress_drain=1;
      while(stress_reads!=512 || !dut.retained_reusable)@(negedge fft_clk);
      repeat(10)@(negedge fft_clk);
      if(fault || stress_releases!=1)$fatal(1,"pending completion fresh recovery failed");
      $display("STAGED_COMPLETION_SLOT_CASE_PASS boundary=%0d fresh_reads=512 fresh_releases=1",boundary);
    end
  endtask
  // END COMPLETION MAILBOX BOUNDARIES
  task automatic private_ack_boundary(input integer boundary);
    reg request_before;
    begin
      stress_reset;stress_fixture=0;send_block(0);stress_drain=1;
      while(!dut.output_released_valid || !dut.owners[1].result_guard.awaiting_ack) @(negedge fft_clk);
      if(stress_reads!=512 || stress_releases!=0 || dut.output_request!==dut.output_ack_sync)
        $fatal(1,"private ACK test lacks actual reader acknowledgment");
      request_before=dut.output_request;
      if(boundary<5) begin
        stress_fault_expected=1;
        if(boundary==0) force dut.event_last_missing=1'b1;
        else if(boundary==1) force dut.core_output_valid=1'b1;
        else if(boundary==2) force dut.core_status_valid=1'b1;
        else if(boundary==3) fft_resetn=0;
        else resetn=0;
        #0.001;
        if(dut.guard_ack[1]!==0 || dut.reader_release!==0) $fatal(1,"faulted ACK granted public release");
        @(posedge fft_clk);#0.002;
        if(boundary<3 && (dut.owners[1].result_guard.awaiting_ack!==0 ||
           original_inverse_ack.awaiting_ack!==1 || dut.owners[1].result_guard.protocol_fault!==1))
          $fatal(1,"missing private ACK fault-edge divergence/quarantine");
        @(negedge fft_clk);release dut.event_last_missing;release dut.core_output_valid;release dut.core_status_valid;
        if(boundary>=3) begin
          repeat(10) @(negedge fft_clk);resetn=1;fft_resetn=1;request_before=dut.output_request;
        end
        repeat(100) begin
          @(negedge fft_clk);
          if(dut.output_request!==request_before || dut.output_published_valid || dut.reader_release ||
             dut.job_accept || dut.config_valid || dut.core_input_valid || output_valid)
            $fatal(1,"private ACK cancellation escaped quarantine");
        end
        if(stress_releases!=0 || (boundary<3 && !fault)) $fatal(1,"private ACK cancellation evidence missing");
        stress_reset;stress_fixture=0;send_block(0);stress_drain=1;
      end
      while(stress_reads!=512 || !dut.retained_reusable) @(negedge fft_clk);
      repeat(10) @(negedge fft_clk);
      if(fault || stress_releases!=1) $fatal(1,"private ACK fresh recovery failed");
      $display("STAGED_PRIVATEACK_CASE_PASS boundary=%0d fresh_reads=512 fresh_releases=1",boundary);
    end
  endtask
  task automatic engine_capture_boundary(input integer boundary);
    reg request_before;
    begin
      stress_reset;stress_fixture=0;
      while(dut.state!=2)@(negedge fft_clk);
      force dut.destination_reserved=1'b0;
      if(boundary==2)begin
        send_block(0);
        while(dut.selected_valid!==1'b1)@(negedge fft_clk);
      end else if(boundary==1 || boundary>=4)force dut.selected_metadata=70'bx;
      else force dut.selected_metadata=70'h123456789abcdef;
      repeat(4)@(negedge fft_clk);
      #0.004;
      if(dut.engine_metadata!==dut.selected_metadata || dut.state!=2 || dut.job_accept ||
         dut.config_valid || dut.core_input_valid || dut.output_replay_accept)
        $fatal(1,"private engine capture did not stay private boundary=%0d",boundary);
      request_before=dut.output_request;
      if(boundary==3)begin
        stress_fault_expected=1;force dut.event_last_missing=1'b1;
        repeat(3)@(negedge fft_clk);release dut.event_last_missing;
      end else if(boundary>=4)begin
        stress_fault_expected=1;
        if(boundary==4)fft_resetn=0;else resetn=0;
        repeat(10)@(negedge fft_clk);
      end
      release dut.selected_metadata;release dut.destination_reserved;
      if(boundary>=3)begin
        repeat(20)begin
          @(negedge fft_clk);
          if(dut.output_request!==request_before || dut.output_published_valid ||
             dut.job_accept || dut.config_valid || dut.core_input_valid)
            $fatal(1,"cancelled private engine capture escaped boundary=%0d",boundary);
        end
        if(boundary==3 && !fault)$fatal(1,"missing engine capture cancellation fault");
        stress_reset;
      end
      if(boundary!=2)send_block(0);
      stress_drain=1;
      while(stress_reads!=512 || !dut.retained_reusable)@(negedge fft_clk);
      repeat(10)@(negedge fft_clk);
      if(fault || stress_releases!=1)$fatal(1,"private engine capture fresh recovery failed");
      $display("STAGED_ENGINE_CAPTURE_CASE_PASS boundary=%0d extra_private=1 stale_reads=0 fresh_reads=512 fresh_releases=1",boundary);
    end
  endtask
  task automatic guardfacts_boundary(input integer gate,input integer owner,input integer fact);
    reg request_before;
    begin
      stress_reset;stress_fixture=0;send_block(0);
      if(gate==0) while(!dut.admission_request || dut.admission_gate.snapshot_valid) @(negedge fft_clk);
      else while(!dut.completion_request || dut.completion_gate.snapshot_valid) @(negedge fft_clk);
      request_before=dut.output_request;stress_fault_expected=1;guardfacts_mask=8'(1<<fact);
      if(owner==0) force dut.owners[0].result_guard.summary_faults_now=guardfacts_mask;
      else force dut.owners[1].result_guard.summary_faults_now=guardfacts_mask;
      @(posedge fft_clk);#0.001;
      if(dut.fast_fault!==1'b1 || dut.admission_permit!==1'b0 || dut.completion_permit!==1'b0)
        $fatal(1,"guard fact did not quarantine real certificates");
      if(gate==0 && (dut.admission_gate.snapshot_valid!==1'b1 ||
         dut.admission_gate.snapshot_good[8+owner*8+fact]!==1'b0 || legacy_admission.snapshot_good[8+owner]!==1'b0))
        $fatal(1,"admission fact not independently captured");
      if(gate==1 && (dut.completion_gate.snapshot_valid!==1'b1 ||
         dut.completion_gate.snapshot_good[8+owner*8+fact]!==1'b0 || legacy_completion.snapshot_good[8+owner]!==1'b0))
        $fatal(1,"completion fact not independently captured");
      @(negedge fft_clk);
      release dut.owners[0].result_guard.summary_faults_now;release dut.owners[1].result_guard.summary_faults_now;
      repeat(100) begin
        @(negedge fft_clk);
        if(dut.input_job_start!==1'b0 || dut.config_valid!==1'b0 || dut.core_input_valid!==1'b0 ||
           dut.admission_permit!==1'b0 || dut.completion_permit!==1'b0 ||
           dut.admission_receipt!==1'b0 || dut.completion_receipt!==1'b0 ||
           dut.output_request!==request_before || dut.output_released_valid!==1'b0)
          $fatal(1,"guard fact escaped snapshot quarantine");
      end
      if(fault!==1'b1 || stress_reads!=0 || stress_releases!=0) $fatal(1,"guard fact veto evidence missing");
      $display("STAGED_GUARDFACTS_CASE_PASS gate=%0d owner=%0d fact=%0d starts=0 reads=0 releases=0",gate,owner,fact);
    end
  endtask
  task automatic publication_preflight_boundary(input integer boundary);
    reg request_before;
    integer paused_before;
    begin
      stress_reset;stress_fixture=0;send_block(0);
      while(dut.output_replay_valid!==1'b1) @(negedge fft_clk);
      request_before=dut.output_request;paused_before=stalled_publication_checks;
      force dut.output_replay_private_ready=1'b0;
      force dut.output_replay_accept=1'b0;
      publication_probe_paused=1;
      // A complete next source bank is queued while inverse replay is stalled.
      send_block(1);
      repeat(128) @(negedge fft_clk);
      if(dut.source_valid!==1'b1 || dut.source_metadata[68:5]!==64'd1447 ||
         dut.output_request!==request_before || dut.retained_published!==1'b0 ||
         stress_reads!=0 || stress_releases!=0 || stalled_publication_checks-paused_before<128)
        $fatal(1,"queued source / paused inverse publication premise failed");
      publication_probe_paused=0;
      if(boundary==2) begin
        // Cancel before releasing either pause, so reset cannot race a publish.
        fft_resetn=0;
        release dut.output_replay_private_ready;release dut.output_replay_accept;
        repeat(10) @(negedge fft_clk);
        if(dut.fast_running!==1'b0 || dut.output_replay_accept!==1'b0 || output_valid!==1'b0)
          $fatal(1,"paused publication reset did not cancel both domains");
      end else begin
        release dut.output_replay_private_ready;release dut.output_replay_accept;
        while(!(dut.preparing && !dut.next_inverse)) @(negedge fft_clk);
        if(dut.retained_published!==1'b1 || dut.output_request===request_before ||
           dut.output_publication_busy!==1'b1 || dut.output_bank_ready!==1'b0 ||
           dut.output_replay_valid!==1'b0 || stress_reads!=0 || stress_releases!=0)
          $fatal(1,"preflight must overlap published unread ownership, not replay");
        if(boundary==1) begin
          stress_fault_expected=1;force dut.preflight_position=9'd7;
          #0.003;
          if(dut.preparation_fault_now!==1'b1 || dut.common_current_fault!==1'b1)
            $fatal(1,"preflight corruption missed original current fault fence");
          @(posedge fft_clk);#0.003;
          if(dut.fast_fault!==1'b1) $fatal(1,"preflight fault not latched");
          @(negedge fft_clk);release dut.preflight_position;
          repeat(100) begin
            @(negedge fft_clk);
            if(dut.output_request===request_before || dut.input_job_start!==1'b0 ||
               dut.core_input_valid!==1'b0 || dut.output_replay_accept!==1'b0)
              $fatal(1,"preflight fault changed publication or allowed stale work");
          end
          if(!fault || stress_reads!=0 || stress_releases!=0) $fatal(1,"preflight unread fault evidence");
        end else begin
          stress_drain=1;
          while(stress_reads!=512 || !dut.retained_reusable) @(negedge fft_clk);
          if(fault || stress_releases!=1) $fatal(1,"old published reader did not release normally");
        end
      end
      stress_reset;stress_fixture=0;send_block(0);stress_drain=1;
      while(stress_reads!=512 || !dut.retained_reusable) @(negedge fft_clk);
      if(fault || stress_releases!=1) $fatal(1,"publication/preflight fresh recovery");
      $display("STAGED_PREFLIGHT_PUBLICATION_CASE_PASS boundary=%0d paused=%0d queued=1 fresh_reads=512 fresh_releases=1",boundary,stalled_publication_checks-paused_before);
    end
  endtask
  task automatic certification_boundary(input integer boundary);
    reg request_before;
    integer n;
    begin
      stress_reset;stress_fixture=0;send_block(0);
      while(dut.state!=9 || dut.next_inverse!==(boundary==1)) @(negedge fft_clk);
      request_before=dut.output_request;stress_fault_expected=1;
      if(boundary<2) begin
        if(dut.preparation_valid!==1'b1 || dut.registered_quarantine!==1'b0)
          $fatal(1,"snapshot not initially valid/live");
        force dut.event_last_missing=1'b1;
      end else if(boundary==2) resetn=0;
      else if(boundary==3) fft_resetn=0;
      else if(boundary==4) force dut.preflight_position=9'd1;
      else force dut.preflight_position=9'bx;
      @(posedge fft_clk);#0.001;
      if(boundary<2 && (dut.descriptor_certified!==1'b1 || original_descriptor_certificate!==1'b0 ||
                        dut.registered_quarantine!==1'b1))
        $fatal(1,"fault-edge private descriptor snapshot was not isolated");
      if(boundary>=4 && dut.descriptor_certified===1'b1)
        $fatal(1,"bad/unknown descriptor certified");
      if(boundary!=2 && boundary!=3 &&
         (dut.input_job_start!==1'b0 || dut.config_valid!==1'b0 || dut.core_input_valid!==1'b0))
        $fatal(1,"descriptor snapshot fault escaped into FFT");
      @(negedge fft_clk);release dut.event_last_missing;release dut.preflight_position;
      if(boundary==2 || boundary==3) begin
        repeat(10) @(negedge fft_clk);resetn=1;fft_resetn=1;
      end
      repeat(100) begin
        @(negedge fft_clk);
        if(dut.input_job_start!==1'b0 || dut.config_valid!==1'b0 || dut.core_input_valid!==1'b0 ||
           dut.admission_permit!==1'b0 || dut.admission_receipt!==1'b0 ||
           dut.output_request!==request_before || dut.output_released_valid!==1'b0)
          $fatal(1,"stale private descriptor escaped snapshot cancellation");
      end
      if(stress_reads!=0 || stress_releases!=0 ||
         ((boundary<2 || boundary==4) && fault!==1'b1) ||
         (boundary==5 && dut.epoch_preflight_reasons===6'b0))
        $fatal(1,"missing snapshot cancellation evidence");
      // Common reset must permit genuinely fresh work, not merely remain idle.
      stress_reset;stress_fixture=0;send_block(0);stress_drain=1;
      while(stress_reads!=512 || !dut.retained_reusable) @(negedge fft_clk);
      repeat(10) @(negedge fft_clk);
      if(fault || stress_releases!=1) $fatal(1,"fresh certification epoch recovery failed");
      $display("STAGED_CERTIFICATION_CASE_PASS boundary=%0d stale_starts=0 stale_reads=0 fresh_reads=512 fresh_releases=1",boundary);
    end
  endtask
  task automatic admission_boundary(input integer boundary);
    reg request_before;
    begin
      stress_reset;stress_fixture=0;send_block(0);
      if(boundary==0) while(!dut.job_valid || dut.admission_gate.snapshot_valid) @(negedge fft_clk);
      else if(boundary==2) while(!dut.admission_receipt) @(negedge fft_clk);
      else while(!dut.admission_permit) @(negedge fft_clk);
      request_before=dut.output_request;stress_fault_expected=1;
      if(boundary==3) force dut.preflight_lease=1'b1;
      else if(boundary==4) resetn=0;
      else if(boundary==5) fft_resetn=0;
      else force dut.core_output_valid=1'b1;
      @(posedge fft_clk);#0.001;
      if(boundary<4 && (dut.input_job_start || dut.config_valid || dut.core_input_valid))
        $fatal(1,"admission fault escaped into FFT start/config/input");
      @(negedge fft_clk);release dut.core_output_valid;release dut.preflight_lease;
      if(boundary>=4) begin
        repeat(10) @(negedge fft_clk);
        resetn=1;fft_resetn=1;
      end
      repeat(100) begin
        @(negedge fft_clk);
        if(dut.input_job_start || dut.config_valid || dut.core_input_valid || dut.admission_permit ||
           dut.admission_receipt || dut.output_request!==request_before || dut.output_released_valid)
          $fatal(1,"stale admission certificate escaped cancellation boundary=%0d",boundary);
      end
      if(stress_reads!=0 || stress_releases!=0 || (boundary<4 && !fault))
        $fatal(1,"admission cancellation evidence missing");
      $display("STAGED_ADMISSION_CASE_PASS boundary=%0d starts_after_cancel=0 publications=0 releases=0",boundary);
    end
  endtask
  task automatic send_block(input integer number);
    integer position;
    begin
      for(position=0;position<512;position=position+1) begin
        @(negedge clk);input_valid=1;input_position=position;input_last=position==511;
        input_block_start=1000+number*447;
        input_data={samples[number*447+position][31:16],2'b0,samples[number*447+position][15:0],2'b0};
        @(posedge clk);while(input_ready!==1) @(posedge clk);
        #0.001;
      end
      @(negedge clk);input_valid=0;
    end
  endtask
  task automatic reset_stopped_reader(input integer side);
    integer resume_edge,prefix,purge_edges;
    begin
      stress_reset;stress_fixture=0;
      send_block(0);send_block(1);
      while(!dut.retained_published || dut.routed_inverse || stress_prefix<64) @(negedge fft_clk);
      @(negedge clk);run_slow=0;prefix=stress_prefix;
      if(stress_reads!=0 || output_valid!==1 || dut.source_valid!==1) $fatal(1,"paused-reader reset premise");
      @(negedge fft_clk);if(side==1) resetn=0;else fft_resetn=0;
      #0.001;
      if(dut.fast_running!==0 || output_valid!==0 || dut.cutover.job_accept!==0 || dut.cutover.producer_closed!==0)
        $fatal(1,"asynchronous reset did not fence queued handover");
      repeat(4) @(negedge fft_clk);resetn=1;fft_resetn=1;
      repeat(20) begin
        @(negedge fft_clk);
        if(dut.fast_running!==0 || dut.job_accept!==0 || output_valid!==0) $fatal(1,"stopped reader permitted stale restart");
      end
      resume_edge=slow_edges;run_slow=1;
      while(!dut.fast_running) @(negedge fft_clk);
      purge_edges=slow_edges-resume_edge;
      if(purge_edges<4 || dut.slow_metadata_valid!==0 || dut.source_valid!==0 ||
         output_valid!==0 || dut.output_control.occupied!==0) $fatal(1,"reset did not purge reader/descriptor state");
      stress_fixture=2;stress_reads=0;stress_drain=1;
      send_block(2);
      while(stress_reads!=512 || !dut.retained_reusable) @(negedge fft_clk);
      repeat(10) @(negedge fft_clk);
      if(stress_releases!=1) $fatal(1,"fresh reset result did not release once");
      $display("STAGED_RESET_PASS side=%0d old_unread=512 aborted_forward_prefix=%0d fresh_reads=512 slow_purge_edges=%0d",side,prefix,purge_edges);
    end
  endtask
  task automatic fault_boundary(input integer boundary);
    reg request_before;
    begin
      stress_reset;stress_fixture=0;send_block(0);
      case(boundary)
        0: while(!dut.admission_receipt) @(negedge fft_clk);
        1: while(!dut.completion_receipt) @(negedge fft_clk);
        2: while(!(dut.output_control.ledger.pending && dut.output_control.command_opcode==1)) @(negedge fft_clk);
        3: while(!dut.output_replay_valid) @(negedge fft_clk);
        4: while(!dut.slow_output_valid || dut.reader_descriptor_phase!=0) @(negedge fft_clk);
        5: begin
          stress_drain=1;
          while(!output_valid || output_position!=511) @(negedge clk);
        end
        6: while(!dut.output_complete_valid || !dut.output_complete_ready) @(negedge fft_clk);
      endcase
      request_before=dut.output_request;stress_fault_expected=1;
      if(boundary==0) force dut.core_output_valid=1'b1;
      else if(boundary==1) force dut.core_status_valid=1'b1;
      else if(boundary==4) begin
        force dut.output_descriptor_tag=32'hffffffff;stress_drain=1;
        @(posedge clk);#0.001;
        if(dut.reader_descriptor_phase!=1 || output_valid) $fatal(1,"descriptor capture was bypassed");
        release dut.output_descriptor_tag;
        @(posedge clk);#0.001;
        if(!dut.slow_lookup_fault || output_valid) $fatal(1,"missing metadata escaped first-word boundary");
      end else if(boundary==6) force dut.output_lookup_descriptor=70'b0;
      else force dut.event_last_missing=1'b1;
      @(posedge fft_clk);#0.001;
      if(boundary==6) begin
        if(!dut.output_descriptor_pending || dut.output_descriptor_valid || dut.output_request!==request_before)
          $fatal(1,"writer capture did not hold publication closed");
        @(negedge fft_clk);release dut.output_lookup_descriptor;
        @(posedge fft_clk);#0.001;
        if(!dut.output_descriptor_fault || dut.output_descriptor_valid)
          $fatal(1,"captured writer mismatch did not cancel publication authority");
      end
      @(negedge fft_clk);
      release dut.core_output_valid;release dut.core_status_valid;
      release dut.event_last_missing;release dut.output_lookup_descriptor;
      repeat(80) begin
        @(negedge fft_clk);
        if(dut.output_request!==request_before || dut.output_released_valid || dut.reader_release)
          $fatal(1,"fault allowed publication or descriptor release");
      end
      if(!fault || !dut.fast_fault || stress_releases!=0 ||
         (boundary!=5 && stress_reads!=0) || (boundary==5 && stress_reads!=512))
        $fatal(1,"fault quarantine/evidence mismatch boundary=%0d reads=%0d",boundary,stress_reads);
      $display("STAGED_FAULT_PASS boundary=%0d no_late_publication=1 releases=0 reads=%0d",boundary,stress_reads);
    end
  endtask
  integer block_index,word_index,guardfacts_gate,guardfacts_owner,guardfacts_fact;
  task automatic sequence_boundary(input integer boundary);
    reg request_before;
    reg [8:0] index_before;
    reg [64:0] next_before;
    reg [63:0] next_expected;
    integer n;
    begin
      stress_reset;stress_fixture=0;send_block(0);
      if(boundary==3) begin
        while(!dut.job_accept || dut.next_inverse) @(negedge fft_clk);
        force dut.core_status_valid=1'b0;
        while(!dut.owners[0].result_guard.return_valid || !dut.owners[0].result_guard.return_last)
          @(negedge fft_clk);
        repeat(8) begin
          @(negedge fft_clk);
          if(dut.guard_forward_private_offer[0] || dut.forward_retirement_valid ||
             dut.joiner.kernel_rom.private_sequence_accept || dut.joiner.kernel_rom.expected_bin_index!==511 ||
             dut.joiner.kernel_rom.have_previous_block)
            $fatal(1,"private sequence skipped final status qualification");
        end
        sequence_late_status={3'b0,fe[0]};force dut.core_status_data=sequence_late_status;
        force dut.core_status_valid=1'b1;
        @(posedge fft_clk);#0.001;
        @(negedge fft_clk);release dut.core_status_valid;release dut.core_status_data;
      end else if(boundary==4) begin
        while(!dut.forward_retirement_valid || dut.return_position!=511) @(negedge fft_clk);
        force dut.joiner.kernel_rom.input_ready=1'b0;
        repeat(16) begin
          @(posedge fft_clk);#0.001;
          if(dut.kernel_ready || dut.joiner.input_accept || dut.joiner.kernel_rom.private_sequence_accept ||
             dut.joiner.kernel_rom.expected_bin_index!==511 || dut.forward_committed ||
             dut.joiner.kernel_rom.have_previous_block)
            $fatal(1,"private sequence failed final backpressure freeze");
          @(negedge fft_clk);
        end
        release dut.joiner.kernel_rom.input_ready;
      end else while(!dut.joiner.input_accept || dut.return_position!=(boundary==5 ? 511 : 64))
        @(negedge fft_clk);
      request_before=dut.output_request;index_before=dut.joiner.kernel_rom.expected_bin_index;
      next_before={dut.joiner.kernel_rom.have_previous_block,dut.joiner.kernel_rom.expected_next_block_start};
      next_expected=dut.joiner.kernel_rom.input_block_start_index+64'd447;
      if(boundary<3 || boundary==5) begin
        stress_fault_expected=1;
        if(boundary==0 || boundary==5) force dut.event_last_missing=1'b1;
        else if(boundary==1) force dut.product_bank_framing_fault_now=1'b1;
        else force dut.core_status_valid=1'b1;
        #0.001;
        if(!dut.joiner.kernel_rom.private_sequence_accept || dut.joiner.input_accept)
          $fatal(1,"fault did not separate private sequence from public acceptance");
        @(posedge fft_clk);#0.001;
        if(dut.joiner.kernel_rom.expected_bin_index!==9'(index_before+1) || dut.joined_valid ||
           dut.joiner.kernel_rom.accepted_pulse || dut.joiner.kernel_rom.input_block_complete_pulse ||
           {dut.joiner.kernel_rom.have_previous_block,dut.joiner.kernel_rom.expected_next_block_start} !==
             (boundary==5 ? {1'b1,next_expected} : next_before))
          $fatal(1,"faulted private sequence state/authority");
        @(negedge fft_clk);release dut.event_last_missing;release dut.product_bank_framing_fault_now;release dut.core_status_valid;
        repeat(100) begin
          @(negedge fft_clk);
          if(dut.output_request!==request_before || dut.output_published_valid || dut.output_released_valid ||
             dut.joiner.input_accept || dut.joiner.kernel_rom.private_sequence_accept || dut.job_accept ||
             dut.config_valid || dut.core_input_valid)
            $fatal(1,"private sequence escaped epoch quarantine");
        end
        if(!fault || stress_reads!=0 || stress_releases!=0) $fatal(1,"missing sequence veto evidence");
      end else begin
        n=0;@(posedge fft_clk);
        while(!dut.joiner.input_accept && n<32) begin n=n+1;@(posedge fft_clk);end
        if(!dut.joiner.input_accept || !dut.joiner.kernel_rom.private_sequence_accept ||
           dut.joiner.kernel_rom.expected_bin_index!==511) $fatal(1,"final sequence did not resume");
        #0.001;
        if(dut.joiner.kernel_rom.expected_bin_index!==0 || !dut.joiner.kernel_rom.input_block_complete_pulse ||
           !dut.joiner.kernel_rom.have_previous_block || dut.joiner.kernel_rom.expected_next_block_start!==1447)
          $fatal(1,"final sequence wrap/stride/completion mismatch");
        stress_drain=1;
        while(stress_reads!=512 || !dut.retained_reusable) @(negedge fft_clk);
        repeat(10) @(negedge fft_clk);
        if(fault || stress_releases!=1) $fatal(1,"sequence recovery failed real release");
      end
      $display("STAGED_SEQUENCE_CASE_PASS boundary=%0d private_advance=1 final=%0d reads=%0d releases=%0d",boundary,boundary>=3,stress_reads,stress_releases);
    end
  endtask
  task automatic capture_boundary(input integer boundary);
    reg request_before;
    reg [177:0] held_descriptor;
    integer n;
    begin
      stress_reset;stress_fixture=0;send_block(0);
      if(boundary==0) while(!dut.output_descriptor_capture) @(negedge fft_clk);
      else if(boundary==1) while(!dut.output_descriptor_pending) @(negedge fft_clk);
      else while(!dut.output_complete_accept) @(negedge fft_clk);
      request_before=dut.output_request;
      held_descriptor={dut.output_descriptor_tag,dut.output_descriptor_payload,
        dut.output_descriptor_expected,dut.output_descriptor_lookup_ok};
      if(boundary==2) begin
        stress_fault_expected=1;
        force dut.event_last_missing=1'b1;
        force dut.output_lookup_descriptor=70'b0;
        #0.001;
        if(!dut.output_descriptor_capture || dut.output_complete_accept || dut.output_replay_accept)
          $fatal(1,"fault-edge private load was not separated from authorization");
        @(posedge fft_clk);#0.001;
        if(dut.output_descriptor_payload[74:5]!==70'b0 || dut.output_descriptor_pending ||
           dut.output_descriptor_locked || dut.output_descriptor_valid)
          $fatal(1,"fault-edge capture acquired authority");
        @(negedge fft_clk);release dut.event_last_missing;release dut.output_lookup_descriptor;
        repeat(100) begin
          @(negedge fft_clk);
          if(dut.output_request!==request_before || dut.output_published_valid || dut.output_released_valid ||
             dut.output_replay_accept || dut.job_accept || dut.config_valid || dut.core_input_valid)
            $fatal(1,"fault-edge private capture escaped quarantine");
        end
        if(!fault || stress_reads!=0 || stress_releases!=0) $fatal(1,"missing capture veto evidence");
      end else begin
        // Only private lookup inputs are perturbed; actual bank/core inputs and
        // public faults are untouched. Before acceptance these may load, after
        // acceptance even invalid/X lookup values must not change the bundle.
        force dut.output_lookup_found=1'b0;force dut.output_lookup_committed=1'b1;
        for(n=0;n<16;n=n+1) begin
          if(n%2) force dut.output_lookup_descriptor={70{1'bx}};
          else force dut.output_lookup_descriptor=70'b0;
          @(posedge fft_clk);#0.001;
          if(boundary==0) begin
            if(dut.output_complete_accept || dut.output_descriptor_pending || dut.output_descriptor_locked ||
               dut.output_descriptor_valid || dut.output_descriptor_lookup_ok ||
               dut.output_descriptor_payload[74:5] !== (n%2 ? {70{1'bx}} : 70'b0))
              $fatal(1,"invalid private lookup churn gained authority or failed to load");
          end else if({dut.output_descriptor_tag,dut.output_descriptor_payload,
                       dut.output_descriptor_expected,dut.output_descriptor_lookup_ok}!==held_descriptor)
            $fatal(1,"pending/published descriptor changed with private lookup churn");
          @(negedge fft_clk);
        end
        if(boundary==0) begin
          release dut.output_lookup_descriptor;release dut.output_lookup_found;release dut.output_lookup_committed;
        end
        stress_drain=1;
        while(stress_reads!=512 || !dut.retained_reusable) begin
          @(negedge fft_clk);
          if(boundary==1 && {dut.output_descriptor_tag,dut.output_descriptor_payload,
                             dut.output_descriptor_expected,dut.output_descriptor_lookup_ok}!==held_descriptor)
            $fatal(1,"held reader bundle changed before real release");
        end
        release dut.output_lookup_descriptor;release dut.output_lookup_found;release dut.output_lookup_committed;
        repeat(10) @(negedge fft_clk);
        if(stress_releases!=1 || dut.output_descriptor_locked || fault)
          $fatal(1,"private capture recovery/real release missing");
      end
      $display("STAGED_CAPTURE_CASE_PASS boundary=%0d reads=%0d releases=%0d",boundary,stress_reads,stress_releases);
    end
  endtask
  task automatic writer_boundary(input integer boundary);
    reg request_before;
    begin
      stress_reset;stress_fixture=0;send_block(0);
      while(!dut.output_descriptor_pending) @(negedge fft_clk);
      request_before=dut.output_request;stress_fault_expected=1;
      if(boundary==0) force dut.event_last_missing=1'b1;
      else if(boundary==1) fft_resetn=0;
      else if(boundary==2) resetn=0;
      else force dut.output_descriptor_expected=70'b0;
      @(posedge fft_clk);#0.001;
      if(boundary==3 && (!dut.output_descriptor_fault || dut.output_descriptor_valid))
        $fatal(1,"held writer identity corruption was not rejected");
      @(negedge fft_clk);release dut.event_last_missing;release dut.output_descriptor_expected;
      if(boundary==1 || boundary==2) begin
        repeat(10) @(negedge fft_clk);
        resetn=1;fft_resetn=1;request_before=dut.output_request;
      end
      repeat(100) begin
        @(negedge fft_clk);
        if(dut.output_request!==request_before || dut.output_published_valid || dut.output_released_valid || dut.reader_release ||
           dut.output_replay_valid || dut.job_accept || dut.config_valid || dut.core_input_valid)
          $fatal(1,"pending writer validation escaped cancellation boundary=%0d",boundary);
      end
      if(stress_reads!=0 || stress_releases!=0 || ((boundary==0 || boundary==3) && !fault))
        $fatal(1,"writer cancellation evidence missing");
      $display("STAGED_WRITER_CASE_PASS boundary=%0d publications=0 releases=0",boundary);
    end
  endtask
  task automatic replay_boundary(input integer boundary);
    reg request_before;
    begin
      stress_reset;stress_fixture=0;send_block(0);
      while(!dut.output_replay_valid || !dut.output_replay_private_ready) @(negedge fft_clk);
      request_before=dut.output_request;stress_fault_expected=1;
      if(boundary==0) force dut.event_last_missing=1'b1;
      else if(boundary==1) force dut.product_bank_framing_fault_now=1'b1;
      else if(boundary==2) force dut.core_status_valid=1'b1;
      else if(boundary==3) fft_resetn=0;
      else resetn=0;
      #0.001;
      if(boundary<3 && (!dut.output_replay_valid || !dut.output_replay_private_ready || dut.output_replay_accept!==0))
        $fatal(1,"fault did not separate private replay from bank authorization");
      @(posedge fft_clk);#0.001;
      if(boundary<3 && (dut.output_control.phase!=4 || dut.output_request!==request_before || dut.output_published_valid))
        $fatal(1,"private replay step falsely became a publication");
      @(negedge fft_clk);
      release dut.event_last_missing;release dut.product_bank_framing_fault_now;release dut.core_status_valid;
      if(boundary>=3) begin
        repeat(10) @(negedge fft_clk);
        resetn=1;fft_resetn=1;request_before=dut.output_request;
      end
      repeat(100) begin
        @(negedge fft_clk);
        if(dut.output_request!==request_before || dut.output_published_valid || dut.output_released_valid || dut.reader_release ||
           dut.output_replay_valid || dut.job_accept || dut.config_valid || dut.core_input_valid)
          $fatal(1,"cancelled replay escaped to publication/release/reuse boundary=%0d",boundary);
      end
      if(stress_reads!=0 || stress_releases!=0 || (boundary<3 && !fault))
        $fatal(1,"replay cancellation evidence missing");
      $display("STAGED_REPLAY_CASE_PASS boundary=%0d private_step=%0d publications=0 releases=0",boundary,boundary<3);
    end
  endtask
  task automatic completion_boundary(input integer boundary);
    integer wanted_phase,stage;
    reg request_before;
    begin
      wanted_phase=(boundary<6 ? boundary/3 : boundary>=8 ? 1 : 0);
      stage=boundary<6 ? boundary%3 : 1;
      stress_reset;stress_fixture=0;send_block(0);
      if(stage==0)
        while(dut.next_inverse!=wanted_phase || !dut.completion_request || dut.completion_gate.snapshot_valid) @(negedge fft_clk);
      else if(stage==1)
        while(dut.next_inverse!=wanted_phase || !dut.completion_permit) @(negedge fft_clk);
      else
        while(dut.next_inverse!=wanted_phase || !dut.completion_receipt) @(negedge fft_clk);
      request_before=dut.output_request;stress_fault_expected=1;
      if(boundary==6) force dut.product_bank_metadata=70'b0;
      else if(boundary==7) force dut.product_bank_position=9'd1;
      else if(boundary==8) resetn=0;
      else if(boundary==9) fft_resetn=0;
      else force dut.core_status_valid=1'b1;
      @(posedge fft_clk);#0.001;
      @(negedge fft_clk);
      release dut.product_bank_metadata;release dut.product_bank_position;release dut.core_status_valid;
      if(boundary>=8) begin
        repeat(10) @(negedge fft_clk);
        resetn=1;fft_resetn=1;request_before=dut.output_request;
      end
      repeat(100) begin
        @(negedge fft_clk);
        if(dut.job_accept || dut.input_job_start || dut.config_valid || dut.core_input_valid ||
           dut.completion_permit || dut.completion_receipt || dut.output_request!==request_before ||
           dut.output_released_valid || dut.reader_release)
          $fatal(1,"cancelled completion escaped to core reuse/publication boundary=%0d",boundary);
      end
      if(stress_reads!=0 || stress_releases!=0 || (boundary<8 && !fault))
        $fatal(1,"completion cancellation evidence missing");
      $display("STAGED_COMPLETION_CASE_PASS boundary=%0d phase=%0d reuse_after_cancel=0 publications=0 releases=0",boundary,wanted_phase);
    end
  endtask
  initial begin
    $readmemh("samples_ci16.mem",samples);$readmemh("forward_q17.mem",forwards);
    $readmemh("product_q17.mem",products);$readmemh("inverse_q17.mem",inverses);
    $readmemh("forward_exponents.mem",fe);$readmemh("inverse_exponents.mem",ie);
    log_file=$fopen("staged_words.csv","w");
    $fdisplay(log_file,"context,stream,job,position,data,exponent");
    if(ACK_ONLY) begin
      stress=1;
      // BEGIN REPLAY QUIET AUXILIARY
      for(mode=0;mode<10;mode=mode+1)replay_quiet_boundary(mode);
      // END REPLAY QUIET AUXILIARY
      // BEGIN COMPLETION MAILBOX AUXILIARY
      for(mode=0;mode<3;mode=mode+1)completion_slot_boundary(mode);
      // END COMPLETION MAILBOX AUXILIARY
      // BEGIN OUTPUT METADATA AUXILIARY
      for(mode=0;mode<6;mode=mode+1)output_metadata_boundary(mode);
      // END OUTPUT METADATA AUXILIARY
      for(mode=0;mode<6;mode=mode+1)private_ack_boundary(mode);
      if(private_ack_checks<1000 || private_ack_quarantine_cycles<300)
        $fatal(1,"combined private ACK auxiliary coverage missing");
      $display("STAGED_ACKCOMBINED_AUX_PASS cases=6 checks=%0d quarantined=%0d public_exact=1 fresh_recovery=1",private_ack_checks,private_ack_quarantine_cycles);
      // BEGIN FORWARD RECEIPT AUXILIARY
      for(mode=0;mode<12;mode=mode+1)forward_receipt_boundary(mode);
      report_forward_receipt;
      // END FORWARD RECEIPT AUXILIARY
      // BEGIN ACTUAL PRODUCT STAGE AUXILIARY
      for(mode=0;mode<12;mode=mode+1)product_stage_boundary(mode);
      report_product_stage;
      // END ACTUAL PRODUCT STAGE AUXILIARY
      report_final_capacity; // FINAL CAPACITY AUXILIARY
      report_split_capacity; // SPLIT CAPACITY AUXILIARY
      report_output_metadata; // OUTPUT METADATA AUXILIARY
      report_balanced_handoff; // BALANCED HANDOFF AUXILIARY
      report_completion_slot; // COMPLETION MAILBOX AUXILIARY
      report_private_admission_facts; // PRIVATE ADMISSION FACTS AUXILIARY
      report_replay_quiet; // REPLAY QUIET AUXILIARY
      $fclose(log_file);$finish;
    end
    for(mode=0;mode<6;mode=mode+1) begin
      @(negedge fft_clk);resetn=0;fft_resetn=0;input_valid=0;
      repeat(10) @(negedge fft_clk);
      jobs=0;reads=0;publications=0;releases=0;inputs=0;raws=0;statuses=0;frames=0;
      forward_words=0;product_words=0;inverse_words=0;old_request=0;
      overlap_inputs=0;overlap_reads=0;last_forward=-1;max_service=0;
      context_start_base=mode==4 ? 64'ha5a5a5a5a5a5a000 : mode==5 ? 64'h5a5a5a5a5a5a5000 : 64'd1000;
      resetn=1;fft_resetn=1;
      for(block_index=0;block_index<3;block_index=block_index+1) begin
        for(word_index=0;word_index<512;word_index=word_index+1) begin
          @(negedge clk);input_valid=1;input_position=word_index;input_last=word_index==511;
          input_block_start=context_start_base+block_index*447;
          input_data={samples[block_index*447+word_index][31:16],2'b0,samples[block_index*447+word_index][15:0],2'b0};
          @(posedge clk);while(input_ready!==1) @(posedge clk);
          #0.001;
        end
        @(negedge clk);input_valid=0;
      end
      while(reads!=1536 || !dut.retained_reusable) @(negedge fft_clk);
      repeat(20) @(negedge fft_clk);
      if(jobs!=6 || inputs!=3072 || raws!=3072 || statuses!=6 || frames!=6 ||
         forward_words!=1536 || product_words!=1536 || inverse_words!=1536 ||
         publications!=3 || releases!=3 || overlap_inputs==0 || (mode<2 && overlap_reads==0))
        $fatal(1,"complete staged FFT inventory mismatch");
      if(mode!=3 && max_service>5215) $fatal(1,"175 MHz coarse service deadline");
      $display("STAGED_FFT_CONTEXT_PASS mode=%0d reads=1536 inputs=3072 raw=3072 status=6 publications=3 releases=3 max_service=%0d overlap_inputs=%0d overlap_reads=%0d",mode,max_service,overlap_inputs,overlap_reads);
      if(mode>=4) $display("STAGED_TIMESTAMP_PASS mode=%0d base=%016h words=1536",mode,context_start_base);
    end
    $fclose(log_file);$display("STAGED_FFT_PASS contexts=6 no_continuous_or_physical_claim");
    if(capture_load_checks<1000 || capture_hold_checks<1000 || capture_accept_checks!=18)
      $fatal(1,"missing private descriptor cycle coverage");
    $display("STAGED_CAPTURE_CYCLES_PASS loads=%0d holds=%0d accepts=%0d",capture_load_checks,capture_hold_checks,capture_accept_checks);
    if(sequence_advances!=9216 || sequence_holds<1000 || sequence_finals!=18)
      $fatal(1,"healthy sequence coverage missing");
    $display("STAGED_SEQUENCE_CYCLES_PASS advances=%0d holds=%0d finals=%0d",sequence_advances,sequence_holds,sequence_finals);
    stress=1;reset_stopped_reader(1);reset_stopped_reader(2);
    for(mode=0;mode<7;mode=mode+1) fault_boundary(mode);
    for(mode=0;mode<6;mode=mode+1) admission_boundary(mode);
    $display("STAGED_ADMISSION_PASS cases=6 partition_checked=1");
    for(mode=0;mode<10;mode=mode+1) completion_boundary(mode);
    $display("STAGED_COMPLETION_PASS cases=10 partition_checked=1");
    for(mode=0;mode<5;mode=mode+1) replay_boundary(mode);
    $display("STAGED_REPLAY_PASS cases=5 actual_authorization_checked=1");
    for(mode=0;mode<4;mode=mode+1) writer_boundary(mode);
    $display("STAGED_WRITER_PASS cases=4 pending_fenced=1");
    for(mode=0;mode<3;mode=mode+1) capture_boundary(mode);
    $display("STAGED_CAPTURE_PASS cases=3 private_load_checked=1 held_until_release=1");
    if(final_loads<1000 || final_holds<1000 || final_accepts<18 || final_fault_loads<100)
      $fatal(1,"missing private final actual cycle coverage");
    $display("STAGED_FINALCAPTURE_PASS loads=%0d holds=%0d accepts=%0d fault_loads=%0d original_payload_checked=1",final_loads,final_holds,final_accepts,final_fault_loads);
    for(mode=0;mode<6;mode=mode+1) sequence_boundary(mode);
    $display("STAGED_SEQUENCE_PASS cases=6 public_acceptance_preserved=1 next_block_checked=1 quarantine_checked=1");
    for(mode=0;mode<6;mode=mode+1) certification_boundary(mode);
    if(certificate_checks<1000 || certificate_private_differences<2)
      $fatal(1,"missing private certification cycle coverage");
    $display("STAGED_CERTIFICATION_CYCLES_PASS checks=%0d private_differences=%0d",certificate_checks,certificate_private_differences);
    $display("STAGED_CERTIFICATION_PASS cases=6 snapshot_cancelled=1 consume_cancelled=1 fresh_recovery=1");
    for(guardfacts_gate=0;guardfacts_gate<2;guardfacts_gate=guardfacts_gate+1)
      for(guardfacts_owner=0;guardfacts_owner<2;guardfacts_owner=guardfacts_owner+1)
        for(guardfacts_fact=0;guardfacts_fact<8;guardfacts_fact=guardfacts_fact+1)
          guardfacts_boundary(guardfacts_gate,guardfacts_owner,guardfacts_fact);
    stress_reset;stress_fixture=0;send_block(0);stress_drain=1;
    while(stress_reads!=512 || !dut.retained_reusable) @(negedge fft_clk);
    repeat(10) @(negedge fft_clk);
    if(fault || stress_releases!=1 || guardfacts_cycles<1000) $fatal(1,"guard facts fresh recovery or coverage failed");
    $display("STAGED_GUARDFACTS_PASS cases=32 cycles=%0d exact_certificates=1 fresh_reads=512 fresh_releases=1",guardfacts_cycles);
    for(integer boundary=0;boundary<3;boundary=boundary+1) publication_preflight_boundary(boundary);
    if(publication_phase_checks<1000 || replay_phase_checks<384 || preflight_unread_checks<2)
      $fatal(1,"publication/preflight phase coverage missing");
    $display("STAGED_PREFLIGHT_PUBLICATION_PASS cases=3 checks=%0d replay=%0d unread=%0d phase_exact=1",publication_phase_checks,replay_phase_checks,preflight_unread_checks);
    for(integer boundary=0;boundary<6;boundary=boundary+1) input_stage_boundary(boundary);
    if(input_stage_pushes<18432 || input_stage_pops<18432 || input_stage_checks<18432 || input_stage_final_holds<36)
      $fatal(1,"actual staged input coverage missing");
    $display("STAGED_INPUT_IDENTITY_PASS pushes=%0d pops=%0d checks=%0d final_holds=%0d exact_payload=1 admitted_descriptor=1",input_stage_pushes,input_stage_pops,input_stage_checks,input_stage_final_holds);
    for(integer boundary=0;boundary<6;boundary=boundary+1)engine_capture_boundary(boundary);
    if(engine_capture_checks<1000 || engine_private_differences<8)
      $fatal(1,"private engine capture oracle coverage missing");
    $display("STAGED_ENGINE_CAPTURE_PASS checks=%0d private_differences=%0d owned_exact=1 cases=6",engine_capture_checks,engine_private_differences);
    if(handover_admissions<36 || handover_completions<36) $fatal(1,"missing registered handover coverage");
    $display("STAGED_HANDOVER_PASS admissions=%0d completions=%0d reset_cases=2 fault_cases=7",handover_admissions,handover_completions);
    if(private_ack_checks<1000)$fatal(1,"combined ACK main witness coverage missing");
    $display("STAGED_ACKCOMBINED_MAIN_PASS checks=%0d public_exact=1",private_ack_checks);
    report_forward_receipt; // FORWARD RECEIPT MAIN
    report_product_stage; // ACTUAL PRODUCT STAGE MAIN
    report_final_capacity; // FINAL CAPACITY MAIN
    report_split_capacity; // SPLIT CAPACITY MAIN
    report_output_metadata; // OUTPUT METADATA MAIN
    report_balanced_handoff; // BALANCED HANDOFF MAIN
    report_completion_slot; // COMPLETION MAILBOX MAIN
    report_private_admission_facts; // PRIVATE ADMISSION FACTS MAIN
    report_replay_quiet; // REPLAY QUIET MAIN
    $finish;
  end
  initial begin #3000000;$fatal(1,"staged FFT absolute deadline");end
endmodule

module tb_ack_only;
  tb #(.ACK_ONLY(1)) isolated();
endmodule
