// Additive interface witnesses only; original848 fixture preserved separately.
  integer iface_stall=0,iface_raw=0,iface_head=0,iface_receipt=0,iface_phase=0;
  integer iface_admissions=0,iface_completions=0,iface_capacity_verdict=0;
  reg [74:0] iface_saved_descriptor;
  reg [1:0] iface_saved_lease;
  reg iface_forcing=0,iface_finished=0;
  reg [74:0] iface_old_head,iface_changed;
  reg [1:0] iface_old_lease,iface_changed_lease;
  reg actor_receipt=0,actor_private_start=0,actor_epoch_fault=0;
  wire actor_current_fault=guard.idle_fault_now || adapter_fault || |current_faults;
  wire actor_emitted_start=actor_private_start && !actor_epoch_fault;
  always @(posedge clk)begin
    if(kind==108 && score)begin
      actor_epoch_fault<=actor_epoch_fault || actor_current_fault;
      actor_receipt<=dut.handoff_owned && !guard_busy && !actor_current_fault;
      if(actor_receipt)actor_private_start<=1;
    end
  end
  task inject_orphan;
    begin
      case(bit_index)
        0:raw_valid=1;
        1:status_valid=1;
        2:frame=1;
        3:input_beat=1;
        4:input_done=1;
      endcase
    end
  endtask
  always @(posedge clk) begin
    if(score && resetn && peer_resetn) begin
      // These use the actual real guard and product pipeline, not assumed
      // qualified pulses. Forged standalone pulses have a separate contract.
      if(kind!=111 && dut.issuer_current[1:0]!==0)
        $fatal(1,"INTERFACE_REAL_QUALIFIED_DIAGNOSTIC_REACHABLE");
      if(kind!=111 && dut.forward_job_accept)begin
        iface_admissions=iface_admissions+1;
        if(!reusable || dut.any_reference || guard.active || guard.awaiting_ack)
          $fatal(1,"INTERFACE_REAL_ADMISSION_OWNERSHIP_MISSING");
      end
      if(kind!=111 && forward_completion)begin
        iface_completions=iface_completions+1;
        if(!dut.producer_reference || dut.final_taken || dut.completion_reference ||
           dut.published_reference || !forward_phase || takes>=512 ||
           !guard.active || !return_last || !guard.final_qualified)
          $fatal(1,"INTERFACE_REAL_COMPLETION_PRODUCT_ORDER_MISSING");
      end
      if(handoff !== (guard.awaiting_ack && destination_ready && !guard_fault && !guard.idle_fault_now))
        $fatal(1,"INTERFACE_ACTUAL_GUARD_ACK_DIVERGED");
      if(dut.read_head_valid && !inverse_enable)begin
        iface_head=iface_head+1;
        if(core_take || core_valid || dut.read_head_metadata!==dut.reader.descriptor ||
           dut.read_head_lease!==dut.reader.lease_slot[dut.reader.head])
          $fatal(1,"INTERFACE_UNENABLED_HEAD_MISMATCH");
      end
      if(dut.handoff_seen && !adapter_fault && current_faults==0 && !dut.queue_validation_fault)begin
        iface_receipt=iface_receipt+1;
        if(!dut.handoff_owned) $fatal(1,"INTERFACE_PERSISTENT_RECEIPT_MISSING");
      end
      if(iface_forcing && product_valid!==0)begin
        iface_raw=iface_raw+1;
        if(dut.bank.input_valid!==product_valid) $fatal(1,"INTERFACE_RAW_OFFER_MASKED");
        if(product_take) $fatal(1,"INTERFACE_READY_ZERO_TAKE");
      end
    end
  end
  always @(negedge clk)begin
    if(score && kind==109 && !iface_finished && dut.handoff_capacity)begin
      iface_finished=1;
      force destination_ready=0;
      corrupt_read=dut.bank_metadata ^ (75'b1<<bit_index);
      force dut.bank_metadata=corrupt_read;
      repeat(2)tick();
      @(negedge clk);release destination_ready;#0.001;
      if(!dut.handoff_capacity || !dut.reader_token_fault_now ||
         dut.reader_offer_fault_now || adapter_fault || guard_fault || handoff)
        $fatal(1,"INTERFACE_CAPACITY_VERDICT_BOUNDARY_MISSING");
      iface_capacity_verdict=iface_capacity_verdict+1;
    end
    if(score && kind==110 && !iface_finished &&
       ((bit_index==0 && dut.handoff_capacity) || (bit_index!=0 && lease_release)))begin
      iface_finished=1;
      if(bit_index==1)force dut.bank_valid=1;else force dut.bank_valid=1'bx;
      #0.001;
      if(!dut.reader_offer_fault_now || adapter_fault || guard_fault ||
         handoff || core_take || lease_release)
        $fatal(1,"INTERFACE_RAW_OFFER_BOUNDARY_ESCAPE");
      if(bit_index==0 && !dut.handoff_capacity)
        $fatal(1,"INTERFACE_RAW_OFFER_CAPACITY_NOT_INDEPENDENT");
      if(bit_index!=0 && (!dut.issuer_current[6] || dut.bank_live!==0))
        $fatal(1,"INTERFACE_DERIVED_BANK_FAULT_FED_UPSTREAM");
    end
    if(score && kind==100 && !iface_finished)begin
      if(!iface_forcing && product_valid && product_position==target)begin
        force dut.product_ready=0;iface_forcing=1;
      end else if(iface_forcing)begin
        iface_stall=iface_stall+1;
        if(iface_stall==4)begin release dut.product_ready;iface_forcing=0;iface_finished=1;end
      end
    end
    // READY0 cannot hide genuinely new closed offers or X/Z raw controls.
    if(score && kind==101 && !iface_finished && dut.final_taken)begin
      force dut.product_ready=0;iface_forcing=1;iface_finished=1;
      case(bit_index)
        0: force dut.product_valid=1;
        1: force dut.product_valid=1'bx;
        2: force dut.product_valid=1'bz;
      endcase
      #0.001;
      if(publication || handoff || product_take) $fatal(1,"INTERFACE_CLOSED_RAW_CURRENT_ESCAPE");
    end
    if(score && kind==106 && !iface_finished && dut.queue_prefetched)begin
      forward_phase=0;iface_phase=iface_phase+1;
      #0.001;if(handoff_valid || handoff) $fatal(1,"INTERFACE_WRONG_PHASE_HANDOFF");
      if(iface_phase==3)begin forward_phase=1;iface_finished=1;end
    end
    if(score && kind==107 && !iface_finished && handoff_valid)begin
      if(guard_fault || !guard.awaiting_ack) $fatal(1,"INTERFACE_FRESH_ACK_ORPHAN_PHASE_MISSING");
      iface_finished=1;inject_orphan();#0.001;
      if(guard_fault || !guard.idle_fault_now || handoff || dut.handoff_owned)
        $fatal(1,"INTERFACE_CURRENT_ACK_ORPHAN_ESCAPE");
    end
  end
  task interface_after_wait;
    begin
      if(kind==111 && target==1)forge_qualified_pulse();
      if(kind==109)begin
        if(iface_capacity_verdict!=1 || !adapter_fault || !reader_reasons[2] ||
           handoffs || releases || core_take)
          $fatal(1,"INTERFACE_CURRENT_VERDICT_ACK_NOT_HELD");
        $display("PRODUCT_INTERFACE_CAPACITY_VERDICT_PASS bit=%0d capacity_edges=%0d",bit_index,iface_capacity_verdict);$finish;
      end
      if(kind==110 && bit_index==0)begin
        if(!iface_finished || !adapter_fault || !reader_reasons[7] || handoffs || releases)
          $fatal(1,"INTERFACE_RAW_ACK_REASON_MISSING");
        $display("PRODUCT_INTERFACE_RAW_BOUNDARY_PASS bit=%0d reasons=%h/%h",bit_index,reader_reasons,issuer_reasons);$finish;
      end
      if(kind==107)begin
        if(!iface_finished || !adapter_fault || !guard_fault || handoffs || core_take || releases)
          $fatal(1,"INTERFACE_ACK_ORPHAN_NOT_RETAINED");
        if((bit_index==0 && !guard.fault_reasons[5]) || (bit_index==1 && !guard.fault_reasons[4]) ||
           (bit_index==2 && !guard.fault_reasons[3]) || (bit_index>2 && !guard.fault_reasons[2]))
          $fatal(1,"INTERFACE_ORPHAN_SPECIFIC_REASON_MISSING");
        $display("PRODUCT_INTERFACE_ACK_ORPHAN_PASS bit=%0d reasons=%h",bit_index,guard.fault_reasons);$finish;
      end
      if(kind==108)begin
        if(handoffs!=1 || guard_busy || !dut.handoff_owned) $fatal(1,"INTERFACE_POST_ACK_ACTOR_PHASE_MISSING");
        if(target==1)begin tick();if(!actor_receipt) $fatal(1,"INTERFACE_RECEIPT_CAPTURE_MISSING");end
        @(negedge clk);inject_orphan();#0.001;
        if(guard_fault || !guard.idle_fault_now || dut.handoff_owned || handoff || core_take || releases)
          $fatal(1,"INTERFACE_POST_ACK_CURRENT_ESCAPE");
        repeat(3)tick();
        if(!actor_epoch_fault || actor_emitted_start || !guard_fault || !adapter_fault || core_take || releases)
          $fatal(1,"INTERFACE_RECEIPT_EMITTED_START_ESCAPE");
        if(target==1 && !actor_private_start) $fatal(1,"INTERFACE_PRIVATE_ADVANCE_WITNESS_MISSING");
        $display("PRODUCT_INTERFACE_RECEIPT_ORPHAN_PASS bit=%0d boundary=%0d private_advance=%0d safe_start=%0d",bit_index,target,actor_private_start,actor_emitted_start);$finish;
      end
      if(kind==100 && target==37)begin
        if(!adapter_fault || !iface_raw || !iface_stall || pubs || handoffs)
          $fatal(1,"INTERFACE_INTERIOR_READY_FAULT_MISSING");
        $display("PRODUCT_INTERFACE_NEGATIVE_PASS kind=100 raw=%0d stall=%0d",iface_raw,iface_stall);$finish;
      end
      if(kind==100 && target==511)begin
        if(adapter_fault || iface_raw<4 || iface_stall!=4 || !iface_finished)
          $fatal(1,"INTERFACE_FINAL_READY_HOLD_MISSING");
        $display("PRODUCT_INTERFACE_FINAL_STALL_PASS raw=%0d stall=%0d",iface_raw,iface_stall);
      end
      if(kind==101)begin
        if(!adapter_fault || !iface_raw || !issuer_reasons[3] || (bit_index!=0 && !bank_reasons[7]))
          $fatal(1,"INTERFACE_RAW_DIAGNOSTIC_MISSING");
        $display("PRODUCT_INTERFACE_NEGATIVE_PASS kind=101 bit=%0d raw=%0d reasons=%h/%h",bit_index,iface_raw,bank_reasons,issuer_reasons);$finish;
      end
      if(kind>=102 && kind<=105)begin
        if(!handoffs || guard_busy || !dut.handoff_owned || !dut.read_head_valid || core_take || !iface_head)
          $fatal(1,"INTERFACE_ACK_HEAD_BOUNDARY_MISSING");
        if(kind==102)begin
          // Deliberate private corruption establishes independent signal
          // sources, not admission safety (the future top binder is absent).
          iface_old_head=dut.read_head_metadata;iface_old_lease=dut.read_head_lease;
          iface_changed=dut.expected_metadata ^ (75'b1<<bit_index);
          iface_changed_lease=dut.lease_reference+1'b1;
          force dut.expected_metadata=iface_changed;force dut.lease_reference=iface_changed_lease;
          #0.001;
          if(dut.admitted_metadata!==iface_changed || dut.read_head_metadata!==iface_old_head ||
             dut.admitted_lease!==iface_changed_lease || dut.read_head_lease!==iface_old_lease)
            $fatal(1,"INTERFACE_ADMISSION_HEAD_ALIAS");
        end
        if(kind==103)begin
          repeat(4)tick();
          if(!dut.handoff_owned || handoff || guard_busy || reusable || core_take || iface_receipt<4)
            $fatal(1,"INTERFACE_POST_ACK_RECEIPT_MISSING");
        end
        if(kind==104)begin
          @(negedge clk);injected_faults=8'b1<<bit_index;#0.001;
          if(dut.handoff_owned || dut.read_head_valid || core_take || lease_release)
            $fatal(1,"INTERFACE_CURRENT_RECEIPT_VETO_MISSING");
          tick();if(!adapter_fault)$fatal(1,"INTERFACE_CURRENT_REASON_MISSING");
        end
        if(kind==105)begin
          force dut.reader.good=0;#0.001;
          if(dut.read_head_valid || core_take) $fatal(1,"INTERFACE_UNCHECKED_HEAD_VISIBLE");
        end
        $display("PRODUCT_INTERFACE_SNAPSHOT_PASS kind=%0d bit=%0d head=%0d receipt=%0d",kind,bit_index,iface_head,iface_receipt);$finish;
      end
    end
  endtask
  task forge_qualified_pulse;
    begin
      // These are deliberately impossible qualified-call inputs, NOT a raw
      // event equivalence claim. Exact reasons latch on this edge; upstream
      // bank/reader summary observes reason Q on the following edge.
      if(target==1 && (handoffs!=1 || guard_busy || !dut.handoff_owned))
        $fatal(1,"INTERFACE_FORGED_POST_ACK_PHASE_MISSING");
      @(negedge clk);
      iface_saved_descriptor=dut.expected_metadata;iface_saved_lease=dut.lease_reference;
      if(bit_index==0)begin
        force dut.forward_descriptor=70'h200000000000000000;
        force dut.forward_job_accept=1;
      end else if(bit_index==1)begin
        force dut.forward_exponent=5'd17;force dut.forward_completion=1;
      end else force dut.forward_completion=1'bx;
      #0.001;
      if(!dut.issuer_current[bit_index==2 ? 7 : bit_index] || adapter_fault ||
         dut.bank_live!==0 || dut.reader_live!==0)
        $fatal(1,"INTERFACE_QUALIFIED_DIAGNOSTIC_TIMING_CHANGED");
      tick();
      if(!issuer_reasons[bit_index==2 ? 7 : bit_index] || !adapter_fault ||
         dut.producer_reference || dut.completion_reference ||
         dut.expected_metadata!==iface_saved_descriptor || dut.lease_reference!==iface_saved_lease ||
         core_take || lease_release || dut.handoff_owned || bank_reasons[15] || reader_reasons[15])
        $fatal(1,"INTERFACE_FORGED_CAPTURE_OR_REASON_FAILURE");
      @(negedge clk);release dut.forward_job_accept;release dut.forward_descriptor;
      release dut.forward_completion;release dut.forward_exponent;
      tick();
      if(!bank_reasons[15] || (target==1 && !reader_reasons[15]) || reusable || core_take || lease_release)
        $fatal(1,"INTERFACE_DIAGNOSTIC_Q_SUMMARY_NOT_RETAINED");
      $display("PRODUCT_INTERFACE_QUALIFIED_DIAGNOSTIC_PASS bit=%0d phase=%0d issuer_edge=0 summary_edge=1",bit_index,target);$finish;
    end
  endtask
  task interface_before_jobs;
    begin
      if(kind==111 && target==0)forge_qualified_pulse();
    end
  endtask
  task interface_after_deliver;
    begin
      if(kind==110 && bit_index!=0)begin
        if(!iface_finished || !adapter_fault || !issuer_reasons[6] ||
           !reader_reasons[bit_index==1 ? 5 : 7] || releases || reusable || core_take)
          $fatal(1,"INTERFACE_RAW_RELEASE_REASON_MISSING");
        $display("PRODUCT_INTERFACE_RAW_BOUNDARY_PASS bit=%0d received=%0d reasons=%h/%h",bit_index,received,reader_reasons,issuer_reasons);$finish;
      end
    end
  endtask
  final begin
    if(kind==0 && ENABLED==1 && (iface_admissions!=8 || iface_completions!=8))
      $error("INTERFACE_QUALIFIED_STREAM_WITNESS_MISSING");
    if(kind==0)$display("PRODUCT_INTERFACE_ORDER_COUNTS admissions=%0d completions=%0d",iface_admissions,iface_completions);
  end
