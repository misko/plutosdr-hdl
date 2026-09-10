// Real bank/guard/product wiring with an explicitly synthetic zero-return
// interface transactor. NOT actual FFT math, latency, throughput or RF evidence.
`timescale 1ns/1ps
module tb_starlink_bank_arithmetic_ownership;
  parameter integer R=1, B=1, S=1, CASE=0;
  localparam [63:0] BASE=64'h200000000;
  reg clk=0, fft_clk=0, resetn=0, fft_resetn=0;
  always #5 clk=~clk;
  always #2.857 fft_clk=~fft_clk;
  reg input_valid=0, input_last=0, output_ready=0, reader_enable=1;
  wire input_ready, output_valid, output_last, fault;
  reg [35:0] input_data=0;
  reg [8:0] input_position=0;
  reg [63:0] input_block_start=BASE;
  wire [35:0] output_data;
  wire [8:0] output_position;
  wire [74:0] output_metadata;
  integer fast_cycles=0, slow_cycles=0, outputs=0, output_blocks=0, inverse_jobs=0;
  integer product_words=0, prefetch=0, forward_tail_wait=0, pulses=0;
  integer target, count, before_prefix, held_snapshots=0;
  reg expect_fault=0, injected=0;
  // Unchanged full old guard observes the candidate environment every edge.
  wire forward_old_valid, forward_old_private;
  wire [31:0] forward_checks, forward_cycles, forward_current, forward_sticky;
  starlink_pss_forward_retirement_shadow #(.ENABLED(S),
    .COMPLETED(1), .PREFLIGHT(S)) forward_shadow (
    .clk(fft_clk), .resetn(dut.fast_running), .job_valid(dut.job_valid),
    .job_descriptor(dut.result_guard.job_descriptor),
    .input_bank_reserved(dut.result_guard.input_bank_reserved),
    .output_bank_reserved(dut.result_guard.output_bank_reserved),
    .certified_input_beat(dut.certified_input_beat), .certified_input_complete(dut.certified_input_complete),
    .final_fence_certified(dut.final_fence), .external_fault_now(dut.external_fault_now),
    .phase_input_fault_now(1'b0), .completed_input_certified(dut.checked_input_complete),
    .completed_input_fault_now(dut.completed_input_fault_now),
    .preflight_fault_evidence_now(dut.preparation_fault_now),
    .core_event_frame_started(dut.event_frame), .core_output_tdata(dut.core_output_data),
    .core_output_tuser(dut.core_output_user), .core_output_tvalid(dut.core_output_valid),
    .core_output_tlast(dut.core_output_last), .core_status_tdata(dut.core_status_data),
    .core_status_tvalid(dut.core_status_valid), .mailbox_input_ready(dut.result_destination_ready),
    .mailbox_input_fault(dut.output_bank_fault || dut.output_bank_framing_fault_now),
    .inverse_phase(dut.next_inverse), .forward_mailbox_fault(dut.output_bank_fault),
    .mailbox_current_fault_now(dut.output_bank_framing_fault_now),
    .actual_public({dut.job_ready, dut.return_valid, dut.return_private_valid, dut.return_commit_valid,
      dut.return_data, dut.return_position, dut.return_last, dut.return_metadata,
      dut.result_busy, dut.result_commit, dut.result_fault, dut.result_guard.fault_reasons}),
    .actual_forward_valid(dut.forward_retirement_valid), .old_valid(forward_old_valid),
    .old_private_valid(forward_old_private), .checks(forward_checks), .forward_cycles(forward_cycles),
    .inverse_current_faults(forward_current), .sticky_forward_faults(forward_sticky)
  );
  // This second frozen arithmetic chain is driven by OLD certified retirement,
  starlink_pss_fft_bank_owned_arithmetic_probe #(.REGISTERED_SCHEDULING(S),
    .BOUNDARY_ROUND_SAT(B), .REGISTER_OPERANDS(R)) dut (.*);
  always @(negedge clk) begin
    slow_cycles=slow_cycles+1;
    output_ready=reader_enable && (slow_cycles%37>=7);
  end
  always @(posedge clk) begin
    if(!resetn || !fft_resetn) begin outputs=0; output_blocks=0; end
    else if(output_valid && output_ready) begin
      if(output_position !== 9'(outputs%512) || output_last !== (outputs%512==511) || output_data !== 0 ||
         output_metadata !== {1'b1,BASE+64'(447*(outputs/512)),5'b0,5'b0})
        $fatal(1,"BANK_OFFLINE_SLOW_IDENTITY_DATA pos=%0d expected=%0d meta=%h",output_position,outputs%512,output_metadata);
      outputs=outputs+1;
      if(output_last) output_blocks=output_blocks+1;
    end
  end
  always @(posedge fft_clk) begin
    fast_cycles=fast_cycles+1;
    if(!dut.fast_running) begin inverse_jobs=0; product_words=0; pulses=0; end
    else begin
      if(dut.config_valid && dut.config_ready && dut.engine_metadata[69]) inverse_jobs=inverse_jobs+1;
      if(dut.product_valid && dut.product.output_ready) begin
        if(!expect_fault && (dut.product_i !== 0 || dut.product_q !== 0 ||
          dut.product_position !== 9'(product_words%512) || dut.product_last !== (product_words%512==511) ||
          dut.product_start !== BASE+64'(447*(product_words/512)) || dut.product_exponent !== 0))
          $fatal(1,"BANK_OFFLINE_PRODUCT_IDENTITY_DATA");
        product_words=product_words+1;
      end
      if(dut.product.overflow_pulse) pulses=pulses+1;
      if(dut.forward_committed && !dut.product_bank_valid && !dut.next_inverse) forward_tail_wait=forward_tail_wait+1;
      if(dut.source_valid && dut.checked_input_complete && !dut.next_inverse && dut.state==dut.RUN_JOB) begin
        prefetch=prefetch+1;
        if(dut.core_input_valid || dut.certified_input_beat || dut.certified_input_complete || dut.source_read_ready)
          $fatal(1,"BANK_OFFLINE_PREFETCH_OVERWROTE_CURRENT");
      end
      if(!expect_fault && dut.fast_fault) $fatal(1,"BANK_OFFLINE_UNEXPECTED_FAULT state=%0d reasons=%h",dut.state,dut.result_guard.fault_reasons);
      if(fast_cycles>180000) $fatal(1,"BANK_OFFLINE_TIMEOUT case=%0d",CASE);
    end
  end
  task reset_epoch;
    begin
      input_valid=0; resetn=0; fft_resetn=0; reader_enable=1;
      dut.shared_xfft.pause_outputs=0; dut.shared_xfft.inject_missing=0; dut.shared_xfft.hold_status=0;
      repeat(5) @(negedge clk);
      resetn=1; fft_resetn=1;
      repeat(5) @(negedge clk);
      expect_fault=0; injected=0;
    end
  endtask
  task send_source(input [63:0] start_index);
    integer pos, wait_count;
    begin
      for(pos=0;pos<512;pos=pos+1) begin
        @(negedge clk);
        input_valid=1; input_position=9'(pos); input_last=(pos==511); input_block_start=start_index;
        wait_count=0;
        while(!input_ready) begin
          @(negedge clk); wait_count=wait_count+1;
          if(wait_count>30000) $fatal(1,"BANK_OFFLINE_SOURCE_TIMEOUT");
        end
        @(posedge clk);
      end
      @(negedge clk); input_valid=0;
    end
  endtask
  task require_quarantine;
    begin
      repeat(8) @(negedge clk);
      if(!fault || !dut.fast_fault || dut.forward_handoff_ack || dut.product_commit_authorized ||
         inverse_jobs || output_valid || output_blocks || dut.core_release==0)
        $fatal(1,"BANK_OFFLINE_FAULT_OWNERSHIP_ESCAPE fault=%b inverse=%0d",fault,inverse_jobs);
    end
  endtask
  task wait_join(input integer position);
    begin
      count=0;
      while(!(dut.joined_valid && dut.joined_ready && dut.joined_position==position)) begin
        @(negedge fft_clk); count=count+1;
        if(count>12000) $fatal(1,"BANK_OFFLINE_JOIN_TIMEOUT");
      end
    end
  endtask
  initial begin
    if(dut.REGISTER_OPERANDS !== R || dut.BOUNDARY_ROUND_SAT !== B ||
       dut.product.REGISTER_OPERANDS !== R || dut.product.PRIVATE_PAYLOAD_BUBBLES !== S ||
       dut.product.arithmetic.PRIVATE_PAYLOAD_BUBBLES !== S || dut.product.arithmetic.BOUNDARY_ROUND_SAT !== B ||
       dut.product.arithmetic.DATA_WIDTH !== 18 || dut.shared_xfft.OFFLINE_NOT_FFT !== 1)
      $fatal(1,"BANK_OFFLINE_ACTUAL_BINDING_MISMATCH");
    reset_epoch();
    if(CASE==0) begin
      send_source(BASE); send_source(BASE+447);
      wait(outputs==1024);
      repeat(20) @(negedge clk);
      if(fault || output_blocks!=2 || inverse_jobs!=2 || product_words!=1024 || !prefetch || !forward_tail_wait)
        $fatal(1,"BANK_OFFLINE_HEALTHY_COVERAGE");
    end else if(CASE==1 || CASE==2) begin
      reader_enable=0;
      send_source(BASE);
      target=CASE==1 ? 17 : 511;
      wait_join(target);
      if(fault || dut.fast_fault || (CASE==2 && !dut.forward_committed))
        $fatal(1,"BANK_OFFLINE_SATURATION_PREMISE");
      expect_fault=1; injected=1; dut.shared_xfft.pause_outputs=1;
      force dut.joined_i=18'h20000; force dut.joined_q=18'h20000;
      force dut.kernel_i=18'h20000; force dut.kernel_q=18'h20000;
      @(posedge fft_clk); @(negedge fft_clk);
      release dut.joined_i; release dut.joined_q; release dut.kernel_i; release dut.kernel_q;
      force dut.product_bank_ready=1'b0;
      wait(dut.product_overflow); #0.001;
      if(!dut.product.overflow_pulse || !dut.external_fault_now || !dut.completed_input_fault_now ||
         dut.product_commit_authorized || dut.forward_handoff_ack || dut.product_bank_valid)
        $fatal(1,"BANK_OFFLINE_CURRENT_HELD_OVERFLOW_VETO");
      repeat(3) @(negedge fft_clk);
      if(!dut.product_valid || !dut.product_overflow || dut.product.overflow_pulse || !dut.fast_fault)
        $fatal(1,"BANK_OFFLINE_HELD_OVERFLOW_NOT_PULSE");
      // Predicate-only isolation AFTER real sticky capture. No clock advances:
      // prove the held flag is still a cause, independently of sticky masking.
      force dut.fast_fault=0;
      #0.001;
      if(!dut.external_fault_now || !dut.completed_input_fault_now || dut.product_commit_authorized)
        $fatal(1,"BANK_OFFLINE_HELD_CAUSE_LOST_WHEN_PULSE_CLEARED");
      held_snapshots=held_snapshots+1;
      release dut.fast_fault;
      require_quarantine();
      release dut.product_bank_ready;
    end else if(CASE==3 || CASE==4) begin
      reader_enable=0; send_source(BASE);
      if(CASE==3) wait(dut.forward_committed && !dut.product_bank_valid);
      else wait(dut.product_bank_valid && !dut.next_inverse);
      @(negedge fft_clk); expect_fault=1; dut.shared_xfft.inject_missing=1;
      #0.001;
      if(!dut.external_fault_now || dut.forward_handoff_ack || dut.product_commit_authorized)
        $fatal(1,"BANK_OFFLINE_LATE_FORWARD_EVENT_VETO");
      @(negedge fft_clk); dut.shared_xfft.inject_missing=0;
      require_quarantine();
    end else if(CASE>=5 && CASE<=8) begin
      reader_enable=0; send_source(BASE);
      wait(dut.product_valid && dut.product_position==511); @(negedge fft_clk);
      expect_fault=1;
      case(CASE)
        5: force dut.product_start=64'h8000000200000000;
        6: force dut.product_exponent=5'd1;
        7: force dut.product_last=1'b0;
        8: force dut.product_position=9'd510;
      endcase
      #0.001;
      if(!dut.product_bank_framing_fault_now || !dut.external_fault_now || dut.product_commit_authorized)
        $fatal(1,"BANK_OFFLINE_PRODUCT_RAW_CURRENT_FAULT");
      @(posedge fft_clk); @(negedge fft_clk);
      release dut.product_start; release dut.product_exponent; release dut.product_last; release dut.product_position;
      require_quarantine();
    end else if(CASE==9) begin
      send_source(BASE); wait(outputs>=20); before_prefix=outputs;
      @(negedge fft_clk); expect_fault=1; dut.shared_xfft.inject_missing=1;
      repeat(8) @(negedge clk);
      dut.shared_xfft.inject_missing=0;
      if(!fault || outputs<before_prefix || outputs>before_prefix+8 || output_valid || output_blocks || input_ready)
        $fatal(1,"BANK_OFFLINE_PROVISIONAL_PREFIX_QUARANTINE");
      $display("BANK_OFFLINE_PREFIX before=%0d provisional_after=%0d complete_blocks=0 cdc_wait_slow_cycles=8",before_prefix,outputs);
    end else if(CASE==10) begin
      reader_enable=0; send_source(BASE); wait(dut.forward_committed && !dut.product_bank_valid);
      @(negedge clk); fft_resetn=0;
      repeat(8) @(negedge clk);
      if(dut.product_valid || dut.product_overflow || dut.product_bank_valid || output_valid || dut.result_fault)
        $fatal(1,"BANK_OFFLINE_FAST_RESET_DID_NOT_PURGE");
    end else if(CASE==11) begin
      dut.shared_xfft.hold_status=1; send_source(BASE);
      wait(dut.result_guard.return_valid && dut.result_guard.return_last && !dut.result_guard.status_seen);
      repeat(12) begin
        @(negedge fft_clk);
        if(dut.forward_committed || dut.return_commit_valid || dut.product_bank_valid ||
           (dut.joined_valid && dut.joined_position==511) || product_words!=511)
          $fatal(1,"BANK_OFFLINE_STATUS_ABSENCE_PUBLISHED_FINAL");
      end
      dut.shared_xfft.hold_status=0;
      wait(outputs==512);
      $display("BANK_OFFLINE_STATUS_FENCE delayed_fast_edges=12 final_product_withheld=1");
    end else $fatal(1,"BANK_OFFLINE_UNKNOWN_CASE");
    if(CASE!=0) begin
      reset_epoch(); send_source(BASE); wait(outputs==512); repeat(20) @(negedge clk);
      if(fault || output_blocks!=1 || product_words!=512 || inverse_jobs!=1)
        $fatal(1,"BANK_OFFLINE_FRESH_RESET_RECOVERY");
    end
    if(!forward_checks || !forward_cycles) $fatal(1,"BANK_OFFLINE_OLD_GUARD_SHADOW_MISSING");
    $display("BANK_ARITHMETIC_OWNERSHIP_PASS registered=%0d round=%0d scheduling=%0d case=%0d outputs=%0d tail_wait=%0d prefetch=%0d held_cause_snapshots=%0d old_guard_checks=%0d synthetic_interface_not_fft=1 no_capacity_claim=1",R,B,S,CASE,outputs,forward_tail_wait,prefetch,held_snapshots,forward_checks);
    $finish(0);
  end
endmodule
