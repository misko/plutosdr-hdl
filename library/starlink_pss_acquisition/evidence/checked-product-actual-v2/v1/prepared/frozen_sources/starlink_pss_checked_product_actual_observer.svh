// Enabled actual-candidate observation contract. No DUT drives; no raw217 or
// cycle-CSV equivalence claim. Frozen old port-fed guard/ROM/arithmetic remain.
  integer checked_pre=0, checked_post=0, checked_jobs=0, checked_products=0;
  integer checked_seals=0, checked_publications=0, checked_acks=0, checked_starts=0;
  integer checked_raw_offers=0, checked_raw_takes=0, checked_raw_bad_offers=0;
  integer checked_core_takes=0, checked_releases=0, checked_resets=0;
  integer checked_current_vetoes=0, checked_purge_checks=0, checked_status_samples=0;
  integer checked_capacity_receipts=0, checked_retained_checks=0;
  integer checked_producer_index=0, checked_raw_index=0, checked_core_index=0;
  integer checked_forward_cycle=0, checked_product_final_cycle=0, checked_seal_cycle=0;
  integer checked_publication_cycle=0, checked_ack_cycle=0, checked_start_cycle=0;
  integer checked_first_core_cycle=0, checked_last_core_cycle=0;
  reg checked_origin_valid=0, checked_bound_receipt=0, checked_producer_bad=0;
  reg [1:0] checked_origin_lease=0;
  reg [69:0] checked_expected_product=0;
  reg checked_bad_word[0:511];
  reg [35:0] checked_raw_word[0:511];
  reg checked_slow_purge=0;
  reg checked_retained_watch=0;
  reg [1:0] checked_retained_lease=0;
  reg [1:0] checked_purge_fast=0;
  integer checked_ledger;
  initial begin
    if(dut.CHECKED_PRODUCT_BANK !== 1 || dut.input_guard.CHECKED_PRODUCT_BINDING !== 1 ||
       dut.input_guard.CHECK_INPUT_BLOCK_IDENTITY !== 1 ||
       dut.checked_product_bank.adapter.SEPARATE_PRODUCT_SEAMS !== 1)
      $fatal(1,"CHECKED_ACTUAL_BINDING_PARAMETERS_CHANGED");
    checked_ledger=$fopen("checked_product_ownership_trace.csv","w");
    $fdisplay(checked_ledger,"cycle,epoch,event,position,data,metadata,lease");
  end
  wire checked_common_resetn = resetn && fft_resetn;
  always @(posedge clk or negedge checked_common_resetn)
    if(!checked_common_resetn)checked_slow_purge<=0;
    else if(!dut.slow_running)checked_slow_purge<=1;
  always @(posedge fft_clk or negedge checked_common_resetn)
    if(!checked_common_resetn)checked_purge_fast<=0;
    else if(!dut.fast_running)checked_purge_fast<=0;
    else checked_purge_fast<={checked_purge_fast[0],checked_slow_purge};
  // Controller-origin evidence is independently captured from actual forward
  // admission. The candidate origin/head/expected copies cannot self-certify.
  wire checked_head_identity = checked_origin_valid &&
    dut.checked_product_bank.origin_valid === 1'b1 &&
    dut.product_origin_lease === checked_origin_lease &&
    dut.product_head_metadata === {5'b0,checked_expected_product} &&
    dut.product_head_lease === checked_origin_lease;
  wire checked_first_head = dut.product_bank_position === 9'd0 && dut.product_bank_last === 1'b0;
  wire checked_start_binding = checked_bound_receipt && dut.product_handoff_state_owned &&
    dut.product_head_owned_good && checked_head_identity && checked_first_head &&
    !dut.product_reader_token_fault && !dut.checked_product_bank.producer_verdict &&
    dut.held_phase === 1'b1 && dut.next_inverse === 1'b1 &&
    dut.engine_metadata === checked_expected_product;
  wire checked_old_guard_ack = dut.fast_running && forward_shadow.old_guard.awaiting_ack &&
    dut.result_destination_ready && !forward_shadow.old_guard.protocol_fault &&
    !forward_shadow.old_guard.idle_fault_now;
  task checked_record(input integer event_kind, input [8:0] position,
                      input [35:0] data, input [74:0] metadata, input [1:0] lease);
    $fdisplay(checked_ledger,"%0d,%0d,%0d,%0d,%h,%h,%h",fast_cycle,epoch,event_kind,position,data,metadata,lease);
  endtask
  task checked_begin_retained_watch;
    begin
      if(!dut.held_phase || !dut.checked_product_bank.adapter.published_reference ||
         !dut.checked_product_bank.adapter.reader_reference ||
         !dut.checked_product_bank.adapter.reader.owned ||
         dut.checked_product_bank.adapter.reader.consumed!=0)
        $fatal(1,"CHECKED_ACTUAL_RETAINED_WATCH_BAD_ENTRY");
      checked_retained_lease=dut.checked_product_bank.adapter.lease_reference;
      checked_retained_watch=1;
    end
  endtask
  task checked_retained_owner;
    begin
      if(!checked_retained_watch || !dut.checked_product_bank.adapter.published_reference ||
         !dut.checked_product_bank.adapter.reader_reference ||
         !dut.checked_product_bank.adapter.reader.owned || !dut.checked_product_bank.adapter.bank_published ||
         dut.checked_product_bank.adapter.lease_reference!==checked_retained_lease ||
         dut.checked_product_bank.bank_lease!==checked_retained_lease ||
         dut.checked_product_bank.adapter.reader.consumed!=0 ||
         dut.checked_product_bank.lease_release || dut.checked_product_bank.core_take ||
         dut.input_job_start || dut.config_valid)
        $fatal(1,"CHECKED_ACTUAL_RETAINED_LEASE_CONSUMED_OR_RELEASED");
      checked_retained_checks=checked_retained_checks+1;
    end
  endtask
  always @(posedge fft_clk or negedge fft_clk)begin
    #0.002;
    if(checked_retained_watch && dut.fast_running && dut.source_epoch_open)
      checked_retained_owner();
  end
  always @(posedge fft_clk)begin
    #0;
    checked_pre=checked_pre+1;
    // Also inspect the actually sampled pre-NBA boundary, so a take/release
    // pulse cannot disappear in the NBA update before the settled edge checks.
    if(checked_retained_watch && dut.fast_running && dut.source_epoch_open)
      checked_retained_owner();
    if(!dut.fast_running || !dut.source_epoch_open)begin
      checked_origin_valid=0;checked_bound_receipt=0;checked_producer_bad=0;
      checked_retained_watch=0;
      checked_producer_index=0;checked_raw_index=0;checked_core_index=0;
      for(integer i=0;i<512;i=i+1)begin checked_bad_word[i]=0;checked_raw_word[i]=0;end
      checked_resets=checked_resets+1;
    end else begin
      if(dut.product_guard_ack_event !== checked_old_guard_ack)
        $fatal(1,"CHECKED_ACTUAL_OLD_GUARD_ACK_EDGE_CHANGED");
      if(dut.state==dut.ACK_DRAIN && !dut.result_busy && !dut.any_fast_fault &&
         !dut.next_inverse && dut.forward_handoff_ack)begin
        if(dut.product_handoff_capacity || dut.result_destination_ready ||
           !checked_bound_receipt || !dut.product_handoff_state_owned)
          $fatal(1,"CHECKED_ACTUAL_CAPACITY_RECEIPT_OWNERSHIP_CHANGED");
        checked_capacity_receipts=checked_capacity_receipts+1;
      end
      if(dut.job_accept && !dut.next_inverse)begin
        checked_origin_lease=dut.checked_product_bank.bank_lease;
        checked_origin_valid=1;checked_bound_receipt=0;checked_producer_bad=0;
        checked_expected_product={1'b1,dut.engine_metadata[68:5],forward_exponents[active_fixture]};
        checked_producer_index=0;checked_raw_index=0;checked_core_index=0;
        for(integer i=0;i<512;i=i+1)begin checked_bad_word[i]=0;checked_raw_word[i]=0;end
        checked_jobs=checked_jobs+1;
      end
      if(dut.input_job_start && !dut.held_phase)checked_forward_cycle=fast_cycle;
      if(dut.core_status_valid===1'b1)checked_status_samples=checked_status_samples+1;
      if(dut.product_valid===1'b1)begin
        if(dut.checked_product_bank.adapter.product_metadata !== checked_expected_product ||
           dut.product_position !== checked_producer_index[8:0] ||
           dut.product_last !== (checked_producer_index==511))checked_producer_bad=1;
      end
      if(dut.checked_product_bank.private_take !==
         (dut.product_valid===1'b1 && (dut.product_bank_ready && !dut.fast_fault)===1'b1))
        $fatal(1,"CHECKED_ACTUAL_SAMPLED_PRODUCT_READY_CHANGED");
      if(dut.checked_product_bank.private_take)begin
        checked_products=checked_products+1;checked_producer_index=checked_producer_index+1;
        checked_record(1,dut.product_position,{dut.product_q,dut.product_i},
          {5'b0,dut.checked_product_bank.adapter.product_metadata},checked_origin_lease);
        if(dut.product_last)checked_product_final_cycle=fast_cycle;
      end
      if(dut.checked_product_bank.seal || dut.checked_product_bank.publication)begin
        if(checked_producer_bad || !checked_origin_valid || checked_producer_index!=512 ||
           !dut.forward_committed || dut.checked_product_bank.publication_current !== 8'b0 ||
           dut.checked_product_bank.independent_current !== 8'b0 ||
           dut.checked_product_bank.producer_verdict)
          $fatal(1,"CHECKED_ACTUAL_UNQUALIFIED_SEAL_PUBLICATION");
      end
      if(dut.checked_product_bank.seal)begin checked_seals=checked_seals+1;checked_seal_cycle=fast_cycle;end
      if(dut.checked_product_bank.publication)begin
        checked_publications=checked_publications+1;checked_publication_cycle=fast_cycle;
        checked_record(2,0,0,{5'b0,checked_expected_product},checked_origin_lease);
      end
      if(dut.checked_product_bank.adapter.reader.raw_valid===1'b1 &&
         dut.checked_product_bank.adapter.reader.owned)begin
        checked_raw_offers=checked_raw_offers+1;
        if(checked_raw_index>=512)$fatal(1,"CHECKED_ACTUAL_EXTRA_RAW_OFFER");
        if(dut.checked_product_bank.adapter.reader.raw_metadata !== {5'b0,checked_expected_product} ||
           dut.checked_product_bank.adapter.reader.raw_lease !== checked_origin_lease ||
           dut.checked_product_bank.adapter.reader.raw_position !== checked_raw_index[8:0] ||
           dut.checked_product_bank.adapter.reader.raw_last !== (checked_raw_index==511))begin
          checked_bad_word[checked_raw_index]=1;checked_raw_bad_offers=checked_raw_bad_offers+1;
        end
        if(dut.checked_product_bank.adapter.reader.raw_ready)begin
          checked_raw_word[checked_raw_index]=dut.checked_product_bank.adapter.reader.raw_data;
          checked_raw_index=checked_raw_index+1;checked_raw_takes=checked_raw_takes+1;
        end
      end
      if(dut.checked_product_bank.actual_handoff)begin
        if(!checked_old_guard_ack || !checked_head_identity || !checked_first_head ||
           !dut.checked_product_bank.head_valid || !dut.forward_handoff_identity)
          $fatal(1,"CHECKED_ACTUAL_UNBOUND_REAL_ACK");
        checked_bound_receipt=1;checked_acks=checked_acks+1;checked_ack_cycle=fast_cycle;
        checked_record(3,0,0,{5'b0,checked_expected_product},checked_origin_lease);
      end
      if(dut.input_job_start && dut.held_phase)begin
        if(!checked_start_binding)$fatal(1,"CHECKED_ACTUAL_UNBOUND_INVERSE_START");
        checked_starts=checked_starts+1;checked_start_cycle=fast_cycle;
        checked_bound_receipt=0;
      end
      if(dut.checked_product_bank.core_take !== (dut.certified_input_beat && dut.held_phase))
        $fatal(1,"CHECKED_ACTUAL_CORE_CERTIFICATE_DIVERGED");
      if(dut.checked_product_bank.core_take)begin
        if(checked_core_index>=512 || checked_core_index>=checked_raw_index ||
           checked_bad_word[checked_core_index] ||
           dut.product_bank_data !== checked_raw_word[checked_core_index] ||
           dut.product_bank_position !== checked_core_index[8:0] ||
           dut.product_bank_last !== (checked_core_index==511) ||
           dut.product_head_lease !== checked_origin_lease || !dut.product_head_owned_good ||
           dut.product_reader_token_fault)
          $fatal(1,"CHECKED_ACTUAL_BAD_OR_UNCHECKED_CORE_TOKEN");
        if(checked_core_index==0)checked_first_core_cycle=fast_cycle;
        checked_last_core_cycle=fast_cycle;
        checked_record(4,dut.product_bank_position,dut.product_bank_data,dut.product_head_metadata,dut.product_head_lease);
        checked_core_index=checked_core_index+1;checked_core_takes=checked_core_takes+1;
      end
      if(dut.checked_product_bank.lease_release)begin
        if(checked_core_index!=512 || checked_raw_index!=512 ||
           !dut.checked_input_complete || !dut.checked_product_bank.adapter.reader.drained)
          $fatal(1,"CHECKED_ACTUAL_PREMATURE_RELEASE");
        checked_releases=checked_releases+1;
        $display("CHECKED_ACTUAL_LATENCY epoch=%0d forward_start=%0d product_final=%0d seal=%0d publication=%0d ack=%0d inverse_start=%0d first_core=%0d last_core=%0d release=%0d",
          epoch,checked_forward_cycle,checked_product_final_cycle,checked_seal_cycle,checked_publication_cycle,
          checked_ack_cycle,checked_start_cycle,checked_first_core_cycle,checked_last_core_cycle,fast_cycle);
      end
      if(dut.any_fast_fault)checked_current_vetoes=checked_current_vetoes+1;
      if(dut.checked_product_bank.lease_release || dut.fast_fault || dut.result_fault ||
         dut.checked_product_bank.adapter_fault)begin checked_origin_valid=0;checked_bound_receipt=0;end
    end
    #0.001;#0;
    if(dut.source_epoch_open !== (dut.fast_running && checked_purge_fast[1]))
      $fatal(1,"CHECKED_ACTUAL_SOURCE_PURGE_RECURRENCE_CHANGED");
    checked_purge_checks=checked_purge_checks+1;checked_post=checked_post+1;
  end
  task checked_actual_verify_terminal;
    begin
      if(checked_pre<=0 || checked_post!=checked_pre || checked_jobs<=0 || checked_products<512 ||
         checked_seals<=0 || checked_publications<=0 || checked_acks<=0 || checked_starts<=0 ||
         checked_raw_offers<512 || checked_raw_takes<512 || checked_raw_bad_offers<=0 ||
         checked_core_takes<512 || checked_releases<=0 || checked_resets<=0 ||
         checked_current_vetoes<=0 || checked_status_samples<=0 || checked_purge_checks!=checked_post ||
         checked_capacity_receipts<=0 || checked_retained_checks<=0)
        $fatal(1,"CHECKED_ACTUAL_OWNERSHIP_COVERAGE_INCOMPLETE");
      $display("CHECKED_PRODUCT_ACTUAL_PASS enabled=1 pre=%0d post=%0d jobs=%0d products=%0d seals=%0d publications=%0d acks=%0d starts=%0d raw_offers=%0d raw_takes=%0d raw_bad_offers=%0d core_takes=%0d releases=%0d resets=%0d current_faults=%0d statuses=%0d purge_checks=%0d capacity_receipts=%0d retained_checks=%0d source=actual_ports_and_independent_origin changed_latency=1 raw217_claim=0",
        checked_pre,checked_post,checked_jobs,checked_products,checked_seals,checked_publications,
        checked_acks,checked_starts,checked_raw_offers,checked_raw_takes,checked_raw_bad_offers,
        checked_core_takes,checked_releases,checked_resets,checked_current_vetoes,checked_status_samples,checked_purge_checks,
        checked_capacity_receipts,checked_retained_checks);
      $fclose(checked_ledger);
    end
  endtask
