// Added only in a mechanically derived copy of the immutable1444 fixture.
// Actual arithmetic READY and advertised capacity are distinct force targets.
  wire actual_product_ready=product_ready;
  // Independent hostile unused ports in option0; do NOT corrupt the actual
  // arithmetic READY while proving the disabled option ignores its new input.
  wire sampled_ready_for_dut=dut.SEPARATE_PRODUCT_SEAMS ? actual_product_ready :
    ((cycle%3==0)?1'bx:((cycle%3==1)?1'bz:1'b1));
  reg [7:0] publication_injection=0;
  reg publication_feedback_enabled=0;
  // Deliberately modeled caller coupling: real checked-input certificates
  // route only to publication plus the independent result guard fence.
  wire [7:0] publication_faults=!dut.SEPARATE_PRODUCT_SEAMS ?
    ((cycle%3==0)?8'bx:((cycle%3==1)?8'bz:8'hff)) : (publication_injection |
    {6'b0,publication_feedback_enabled && consumer_complete,
     publication_feedback_enabled && consumer_beat});
  integer seam_stall=0,seam_witness=0;
  reg seam_started=0;
  reg [35:0] seam_payload;
  reg [8:0] seam_position;
  // Default mode's only new predicates are independently restored every edge;
  // strict whole-body inverse proves no other state/enables changed. Bank0 is
  // additionally paired with canonical bank in the separate bank bench.
  always @(posedge clk)if(!dut.SEPARATE_PRODUCT_SEAMS)begin
    if(dut.sampled_offer !== (dut.producer_reference && !dut.final_taken && product_ready) ||
       dut.sampled_ready_error !== 1'b0 || dut.bank.staged.publication_causes !== 0 ||
       dut.issuer_current[7] !== (dut.any_reference &&
        ((product_valid !== 1'b0 && product_valid !== 1'b1) ||
         (forward_completion !== 1'b0 && forward_completion !== 1'b1) ||
         (product_valid !== 1'b0 && product_ready !== 1'b0 && product_ready !== 1'b1))) ||
       dut.raw_product_uncertain !== (dut.any_reference &&
        ((product_valid !== 1'b0 && product_valid !== 1'b1) ||
         (product_valid !== 1'b0 && product_ready !== 1'b0 && product_ready !== 1'b1))))
      $fatal(1,"SEAM_DEFAULT_OLD_PREDICATE_MISMATCH");
  end
  task inject_publication;
    begin
      publication_injection=0;
      case(bit_index/8)
        0:publication_injection[bit_index%8]=1;
        1:publication_injection[bit_index%8]=1'bx;
        2:publication_injection[bit_index%8]=1'bz;
      endcase
    end
  endtask
  always @(negedge clk)begin
    if(kind==200 && score && !seam_started && product_valid && product_position==target)begin
      seam_started=1;seam_payload={product_q,product_i};seam_position=product_position;
      force actual_product_ready=0;#0.001;
      if(!product_ready)$fatal(1,"SEAM_INITIAL_CAPACITY_NOT_READY");
      repeat(4)begin
        if(actual_product_ready!==0 || product_take || dut.bank.input_valid!==product_valid)
          $fatal(1,"SEAM_ACTUAL_READY_HOLD_FAILED");
        tick();seam_stall=seam_stall+1;
        if({product_q,product_i}!==seam_payload || product_position!==seam_position)
          $fatal(1,"SEAM_OCCUPIED_ARITHMETIC_CHANGED");
        @(negedge clk);
      end
      release actual_product_ready;
      $display("PRODUCT_SEAM_READY_HOLD target=%0d edges=%0d",target,seam_stall);
      if(target==37)begin
        // Original raw-result actor is intentionally not backpressureable.
        // Preserve its late READY overflow/quarantine, not fake healthy FFT.
        repeat(12)tick();
        if(!guard_fault || pubs || handoffs || releases)$fatal(1,"SEAM_LATE_READY_QUARANTINE_MISSING");
        $display("PRODUCT_SEAM_INTERIOR_QUARANTINE_PASS");$finish;
      end
    end
    if(kind==201 && score && !seam_started && product_valid && product_position==target)begin
      seam_started=1;score=0; // Deliberately invalid caller; no claimed binary handshake equality.
      if(bit_index==0)force actual_product_ready=1'bx;else force actual_product_ready=1'bz;
      #0.001;
      if(!product_ready || product_take || !dut.issuer_current[7] ||
         dut.bank.input_valid!==1'b1 || !dut.handoff_fault_now || publication)
        $fatal(1,"SEAM_UNKNOWN_READY_NOT_OBSERVED");
    end
    if(kind==202 && score && !seam_started && dut.final_taken)begin
      seam_started=1;score=0;force actual_product_ready=0;
      case(bit_index)
        0:force product_valid=1;
        1:force product_valid=1'bx;
        2:force product_valid=1'bz;
      endcase
      #0.001;
      if(dut.bank.input_valid!==product_valid || !dut.closed_product || product_take ||
         !dut.handoff_fault_now || publication)$fatal(1,"SEAM_RAW_CLOSED_OFFER_MASKED");
    end
    if(kind==203 && score && !seam_started && dut.producer_reference && !product_valid)begin
      seam_started=1;score=0;
      // A second qualified pulse is an invalid caller, not a real guard job.
      // Its reason Q closes C one edge before the bank summary Q closes.
      force dut.forward_job_accept=1;
      tick();@(negedge clk);release dut.forward_job_accept;
      force product_valid=1;force actual_product_ready=1;#0.001;
      if(issuer_reasons!==8'h01 || bank_reasons!==0 || !dut.producer_reference ||
         !dut.bank_input_ready || product_ready!==0 || !dut.sampled_ready_error)
        $fatal(1,"SEAM_MIXED_REASON_BOUNDARY_MISSING");
      if(product_take)$fatal(1,"SEAM_OVERADVERTISED_READY_PRIVATE_TAKE");
      tick();
      if(issuer_reasons!==8'h81 || !bank_reasons[15])$fatal(1,"SEAM_OVERADVERTISED_REASON_MISSING");
      $display("PRODUCT_SEAM_OVERADVERTISED_READY_PASS");$finish;
    end
    if(kind==204 && score && !seam_started &&
       ((target==0 && checked_seal) || (target==1 && publication)))begin
      seam_started=1;inject_publication();#0.001;
      if(bank_reasons || publication || checked_seal || !guard.fault_now || dut.bank_live!==0)
        $fatal(1,"SEAM_PUBLICATION_CURRENT_FENCE_MISSING");
    end
    if(kind==205 && score && !seam_started && dut.handoff_capacity)begin
      seam_started=1;inject_publication();#0.001;
      if(!dut.handoff_capacity || handoff || !guard.idle_fault_now || bank_reasons || dut.bank_live!==0)
        $fatal(1,"SEAM_CALLER_CURRENT_ACK_FENCE_MISSING");
    end
    if(kind==206 && score && !seam_started && dut.consumer_started && core_valid && physical_ready)begin
      seam_started=1;publication_feedback_enabled=1;#0.001;
      if(!consumer_beat || publication_faults!==8'h01 || bank_reasons ||
         dut.bank_live!==0 || publication || handoff || !guard.fault_now)
        $fatal(1,"SEAM_REAL_CERTIFICATE_CURRENT_BOUNDARY_MISSING");
      tick();if(!bank_reasons[8] || !guard_fault || core_valid || releases)
        $fatal(1,"SEAM_REAL_CERTIFICATE_QUARANTINE_MISSING");
      $display("PRODUCT_SEAM_REAL_CERTIFICATE_PASS received=%0d",received);$finish;
    end
  end
  // New negative epochs terminate in the main actor's existing wait seam,
  // not concurrently with its original healthy-handoff fatal at the same1ps.
  // Every original assertion and every old-case path remains literal.
  task seam_after_wait;
    begin
      if(kind==201 || kind==202 || kind==204 || kind==205)begin
        if(!seam_started)$fatal(1,"SEAM_BOUNDARY_NOT_REACHED");
        if(kind==201 && !issuer_reasons[7])$fatal(1,"SEAM_UNKNOWN_READY_REASON_MISSING");
        if(kind==202 && !issuer_reasons[3])$fatal(1,"SEAM_RAW_CLOSED_REASON_MISSING");
        if(kind==204 && (!bank_reasons[8+bit_index%8] || pubs || handoffs || releases))
          $fatal(1,"SEAM_PUBLICATION_REASON_OR_QUARANTINE_MISSING");
        if(kind==205 && (!guard_fault || handoffs || releases || !bank_reasons[8+bit_index%8]))
          $fatal(1,"SEAM_CALLER_ACK_REASON_MISSING");
        $display("PRODUCT_SEAM_BOUNDARY_PASS kind=%0d phase=%0d bitvalue=%0d",kind,target,bit_index);$finish;
      end
    end
  endtask
