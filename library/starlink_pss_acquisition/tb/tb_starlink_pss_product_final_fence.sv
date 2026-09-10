`timescale 1ns/1ps
// Real input checker and paired real mailboxes, no FFT/controller model claim.
// Predicate declarations are inserted literally from the two pinned wrappers.
module tb_starlink_pss_product_final_fence;
  parameter integer ENABLED=1, ADDRESS_WIDTH=2, BROKEN_CALLER=0;
  localparam integer N=1<<ADDRESS_WIDTH;
  reg clk=0; always #3 clk=~clk;
  reg running=0, core_aresetn=0, job_start=0, inverse=0;
  reg g_valid=0, g_last=0; reg [8:0] g_position=0;
  reg [69:0] g_metadata=0; reg [35:0] g_data=0;
  reg [69:0] descriptor=0; reg core_ready=1;
  wire [69:0] guard_metadata=inverse ? product_bank_metadata : g_metadata;
  wire [8:0] guard_position=inverse ? product_bank_position : g_position;
  wire guard_valid=inverse ? product_bank_valid : g_valid;
  wire guard_last=inverse ? product_bank_last : g_last;
  wire [35:0] guard_data=inverse ? product_bank_data : g_data;
  wire input_fault_now,input_guard_fault,duplicate_start_fault_now;
  wire checked_input_complete, certified_input_beat, certified_input_complete, transport_ready;
  wire [2:0] input_events; wire [47:0] core_data; wire core_valid,core_last;
  starlink_pss_realtime_input_guard #(.CHECK_INPUT_BLOCK_IDENTITY(1),.BALANCED_IDENTITY_EQ(1)) guard (
    .clk(clk),.resetn(core_aresetn),.job_start(job_start),.job_descriptor(descriptor),
    .input_enable(!inverse || reader_ready),.input_valid(guard_valid),.input_ready(),
    .input_transport_ready(transport_ready),.input_data(guard_data),
    .input_position(guard_position),.input_last(guard_last),.input_metadata(guard_metadata),
    .core_input_tdata(core_data),.core_input_tvalid(core_valid),.core_input_tready(core_ready),
    .core_input_tlast(core_last),.certified_input_beat(certified_input_beat),
    .certified_input_complete(certified_input_complete),.input_complete(checked_input_complete),
    .fault_now(input_fault_now),.duplicate_start_fault_now(duplicate_start_fault_now),
    .fault_events_now(input_events),.protocol_fault(input_guard_fault),.fault_reasons());
  reg forward_committed=0;
  reg [1:0] source_fault_fast=0;
  reg vendor_fault_now=0,fast_fault=0,kernel_fault=0,product_overflow=0,result_fault=0;
  reg [69:0] expected_handoff=70'h200000000000000023;
  wire handoff_fault_now=!inverse && forward_committed && product_bank_valid &&
    (product_bank_metadata!=expected_handoff || product_bank_position!=0 || product_bank_last);
  // FROZEN_AND_CANDIDATE_PREDICATES
  reg product_valid=0,product_last=0,reader_ready=0;
  reg [ADDRESS_WIDTH-1:0] product_position=0;
  reg [35:0] product_data=0; reg [69:0] product_metadata=70'h200000000000000023;
  wire product_bank_ready,product_bank_fault,product_bank_framing_fault_now;
  wire product_bank_valid,product_bank_last;
  wire [ADDRESS_WIDTH-1:0] bank_position;
  wire [8:0] product_bank_position=bank_position;
  wire [35:0] product_bank_data; wire [69:0] product_bank_metadata;
  wire read_ready=reader_ready && (!inverse || transport_ready);
  starlink_pss_product_fence_mailbox #(.ADDRESS_WIDTH(ADDRESS_WIDTH),
    .RESET_RELEASE_EXTERNAL(1),.EXPLICIT_COMMIT(1),.USE_PRODUCER_FINAL_FENCE(ENABLED)) candidate (
    .input_clk(clk),.input_resetn(running),.input_valid(product_valid && !fast_fault),
    .input_commit_authorized(product_commit_authorized),
    .input_final_seal_authorized(producer_final_seal_authorized),
    .input_ready(product_bank_ready),.input_data(product_data),.input_position(product_position),
    .input_last(product_last),.input_metadata(product_metadata),.input_fault(product_bank_fault),
    .input_framing_fault_now(product_bank_framing_fault_now),.output_clk(clk),.output_resetn(running),
    .output_valid(product_bank_valid),.output_ready(read_ready),.output_data(product_bank_data),
    .output_position(bank_position),.output_last(product_bank_last),.output_metadata(product_bank_metadata));
  frozen_product_mailbox #(.ADDRESS_WIDTH(ADDRESS_WIDTH),.RESET_RELEASE_EXTERNAL(1),.EXPLICIT_COMMIT(1)) reference (
    .input_clk(clk),.input_resetn(running),.input_valid(product_valid && !fast_fault),
    .input_commit_authorized(product_commit_authorized),.input_ready(),.input_data(product_data),
    .input_position(product_position),.input_last(product_last),.input_metadata(product_metadata),
    .input_fault(),.input_framing_fault_now(),.output_clk(clk),.output_resetn(running),
    .output_valid(),.output_ready(read_ready),.output_data(),.output_position(),.output_last(),.output_metadata());
`define VIEW(m) {m.input_ready,m.input_fault,m.input_framing_fault_now,m.output_valid,m.output_data,m.output_position,m.output_last,m.output_metadata,m.request_toggle,m.acknowledge_toggle,m.request_sync,m.acknowledge_sync,m.metadata_in_hold,m.metadata_out_hold,m.write_position,m.reading,m.read_all_loaded,m.read_address,m.read_output_position,m.read_payload,m.read_valid}
  wire [1023:0] old_view=`VIEW(reference), new_view=`VIEW(candidate);
  integer checks=0,samples=0,private_differences=0,phase_rows=0,stalls=0;
  integer input_bad_bits=0,last_bad_bits=0,current_rows=0,sticky_rows=0,unknown_rows=0,reset_rows=0,words=0;
  integer i,j,k; reg [2:0] epoch_input_reasons=0; reg epoch_external=0;
  // Match the RTL's procedural else branch: X framing is NOT the known-bad
  // branch and still evaluates authorization (which must remain X, not true).
  wire final_sample=candidate.input_accept &&
    (candidate.input_framing_valid !== 1'b0) && candidate.write_position==N-1;
  always @(posedge clk) begin
    if(running) begin
      checks=checks+1;
      if(product_bank_ready && product_bank_valid) $fatal(1,"PRODUCER_CONSUMER_OVERLAP");
      if(final_sample) begin
        samples=samples+1;
        if(forward_committed && (guard.slot_open || inverse))
          $fatal(1,"PRODUCER_FINAL_CALLER_INVARIANT_BROKEN");
        if(producer_final_seal_authorized !== product_commit_authorized)
          $fatal(1,"SAMPLED_FINAL_AUTHORIZATION_MISMATCH");
      end else if(producer_final_seal_authorized !== product_commit_authorized)
        private_differences=private_differences+1;
      epoch_input_reasons<=epoch_input_reasons|input_events;
      epoch_external<=epoch_external|external_fault_now;
      if(product_bank_valid && read_ready) words=words+1;
    end else begin epoch_input_reasons<=0; epoch_external<=0; end
    #0.001;
    if(old_view !== new_view) $fatal(1,"PRODUCT_PUBLIC_STATE_MISMATCH");
    for(integer cell_index=0;cell_index<N;cell_index=cell_index+1)
      if(candidate.payload_memory[cell_index] !== reference.payload_memory[cell_index])
        $fatal(1,"PRODUCT_PAYLOAD_MEMORY_MISMATCH");
  end
  task tick; begin @(posedge clk); #0.002; end endtask
  task low; begin @(negedge clk); end endtask
  task reset_epoch;
    begin low; running=0;core_aresetn=0;job_start=0;inverse=0;g_valid=0;
      forward_committed=0;product_valid=0;reader_ready=0;core_ready=1;
      source_fault_fast=0;vendor_fault_now=0;fast_fault=0;kernel_fault=0;product_overflow=0;result_fault=0;
      descriptor=0;g_metadata=0;expected_handoff=70'h200000000000000023;
      product_metadata=expected_handoff;tick;low;running=1;core_aresetn=1;tick;
    end
  endtask
  task start_input;
    begin low;job_start=1;tick;low;job_start=0;end
  endtask
  task complete_forward;
    begin
      start_input;
      for(integer n=0;n<512;n=n+1) begin
        low;g_valid=1;g_position=n;g_last=n==511;g_data=n;tick;
      end
      low;g_valid=0;
      if(!checked_input_complete || guard.slot_open || input_guard_fault)
        $fatal(1,"FORWARD_INPUT_NOT_NATURALLY_COMPLETE");
      forward_committed=1;
    end
  endtask
  task product_prefix;
    begin
      for(integer n=0;n<N-1;n=n+1) begin
        low;product_valid=1;product_position=n;product_last=0;product_data=36'habc000+n;tick;
      end
      low;product_valid=1;product_position=N-1;product_last=1;product_data=36'habc000+N-1;
    end
  endtask
  task finish_healthy;
    begin
      tick;low;product_valid=0;
      repeat(5) tick;
      if(!product_bank_valid || product_bank_ready) $fatal(1,"COMMITTED_BANK_NOT_OWNED");
      // Deliberately malformed consumer handoff while producer is excluded.
      low;expected_handoff=expected_handoff^70'h1;repeat(3) tick;
      if(!handoff_fault_now || product_commit_authorized!==0 || producer_final_seal_authorized!==1)
        $fatal(1,"NONSAMPLED_HANDOFF_DIFFERENCE_NOT_REACHED");
      low;expected_handoff=product_metadata;
      repeat(3) begin tick;stalls=stalls+1;end
      // Private core reset cannot release or overwrite product ownership.
      low;core_aresetn=0;tick;
      if(!product_bank_valid || product_bank_ready) $fatal(1,"PRIVATE_RESET_RELEASED_BANK");
      low;core_aresetn=1;inverse=1;forward_committed=0;descriptor=product_metadata;start_input;
      phase_rows=phase_rows+1;
      for(integer n=0;n<N;n=n+1) begin
        low;core_ready=0;reader_ready=1;tick;stalls=stalls+1;
        low;core_ready=1;tick;
      end
      low;reader_ready=0;repeat(4) tick;
      if(ADDRESS_WIDTH==9) begin
        if(!product_bank_ready || product_bank_valid) $fatal(1,"ACK_DID_NOT_RETURN_OWNERSHIP");
        if(!checked_input_complete || input_guard_fault) $fatal(1,"INVERSE_INPUT_NOT_NATURALLY_COMPLETE");
      end else begin
        // A four-word mailbox is intentionally TOO SHORT for this fixed512
        // guard. Its early TLAST faults even during the final stall, so the
        // last word stays owned and cannot ACK. This is not a healthy inverse.
        if(product_bank_ready || !product_bank_valid || !input_guard_fault ||
           product_bank_position!=N-1 || checked_input_complete)
          $fatal(1,"SHORT_INVERSE_DID_NOT_HOLD_POISONED_OWNERSHIP");
      end
    end
  endtask
  initial begin
    reset_epoch;
    if(BROKEN_CALLER) begin
      start_input;low;g_valid=1;g_position=0;g_last=0;tick;low;g_position=1;core_ready=0;
      forward_committed=1;product_prefix;tick;
      $fatal(1,"BROKEN_CALLER_ESCAPED");
    end
    complete_forward;product_prefix;finish_healthy;
    // Real open-input corruption remains live; this cut never changes guard.
    for(j=0;j<70;j=j+1) begin
      reset_epoch;start_input;low;g_valid=1;g_position=0;g_last=0;g_metadata=70'b1<<j;
      #0.001;if(!input_fault_now || certified_input_beat || !input_events[1])
        $fatal(1,"ACTIVE_INPUT_CURRENT_FAULT_LOST");
      tick;if(!input_guard_fault || !epoch_input_reasons[1] || !epoch_external)
        $fatal(1,"ACTIVE_INPUT_STICKY_REASON_LOST");
      input_bad_bits=input_bad_bits+1;
    end
    // Current final-edge vetoes: duplicate, source, vendor, kernel, overflow,
    // result fault, and all simultaneously. No registered-only fault surrogate.
    for(j=0;j<7;j=j+1) begin
      reset_epoch;complete_forward;product_prefix;
      case(j)
        0:job_start=1;1:source_fault_fast=2'b10;2:vendor_fault_now=1;
        3:kernel_fault=1;4:product_overflow=1;5:result_fault=1;
        6:begin job_start=1;source_fault_fast=2'b10;vendor_fault_now=1;kernel_fault=1;product_overflow=1;result_fault=1;end
      endcase
      #0.001;if(!final_sample || product_commit_authorized!==0) $fatal(1,"CURRENT_VETO_NOT_APPLIED");
      tick;if(candidate.request_toggle!==0) $fatal(1,"FAULTED_PRODUCT_PUBLISHED");
      current_rows=current_rows+1;
      if(j==0) begin
        // Isolate the REAL checker's retained reason after the duplicate pulse
        // ends. This is a local-veto witness, not a claim that the full wrapper
        // would leave its additional fast_fault latch clear on this next edge.
        low;job_start=0;#0.001;
        if(!final_sample || !checked_input_complete || duplicate_start_fault_now ||
           input_fault_now || !input_guard_fault || !epoch_input_reasons[2] ||
           (|source_fault_fast) || vendor_fault_now || fast_fault || kernel_fault ||
           product_overflow || product_bank_fault || product_bank_framing_fault_now ||
           result_fault || handoff_fault_now)
          $fatal(1,"STICKY_ONLY_INPUT_VETO_NOT_REACHED");
        tick;if(candidate.request_toggle!==0) $fatal(1,"STICKY_INPUT_FAULT_PUBLISHED");
        sticky_rows=sticky_rows+1;
      end
    end
    // Every current final metadata bit and malformed TLAST is still checked
    // inside the mailbox, independently of the local authorization predicate.
    for(j=0;j<71;j=j+1) begin
      reset_epoch;complete_forward;product_prefix;
      if(j==70) product_last=0;else product_metadata=product_metadata^(70'b1<<j);
      #0.001;if(!product_bank_framing_fault_now || candidate.input_framing_valid)
        $fatal(1,"MALFORMED_FINAL_NOT_CURRENT_FAULT");
      tick;if(!product_bank_fault || candidate.request_toggle!==0) $fatal(1,"MALFORMED_FINAL_PUBLISHED");
      last_bad_bits=last_bad_bits+1;
    end
    // Actual authorization evaluation under four-state framing/current veto.
    // Every old/public state remains compared; no invalid payload masking.
    for(j=0;j<4;j=j+1) begin
      reset_epoch;complete_forward;product_prefix;
      case(j)
        0:product_metadata='x;1:product_metadata='z;
        2:vendor_fault_now=1'bx;3:kernel_fault=1'bz;
      endcase
      #0.001;
      if(!final_sample || product_commit_authorized!==1'bx ||
         producer_final_seal_authorized!==1'bx) $fatal(1,"UNKNOWN_FINAL_AUTHORIZATION_NOT_REACHED");
      tick;if(candidate.request_toggle!==0) $fatal(1,"UNKNOWN_FINAL_AUTHORIZATION_PUBLISHED");
      unknown_rows=unknown_rows+1;
    end
    // Unknown invalid payload/authorization is not a sampled event.
    reset_epoch;complete_forward;low;product_valid=0;product_position='x;product_metadata='z;
    repeat(3) tick;
    // Epoch reset before a pending final and while consumer owns a block.
    reset_epoch;complete_forward;product_prefix;low;running=0;core_aresetn=0;tick;reset_rows=reset_rows+1;
    reset_epoch;complete_forward;product_prefix;tick;low;product_valid=0;repeat(5) tick;
    low;running=0;core_aresetn=0;tick;reset_rows=reset_rows+1;
    if(samples==0 || private_differences==0 || words!=(ADDRESS_WIDTH==9 ? N : N-1)) $fatal(1,"FENCE_COVERAGE_MISSING");
    $display("PRODUCT_FINAL_FENCE_PASS enabled=%0d depth=%0d checks=%0d sampled=%0d nonsampled_private=%0d input_bits=%0d final_rows=%0d current_rows=%0d inverse_epochs=%0d stalls=%0d epoch_resets=%0d words=%0d short_inverse_poison=%0d unknown_final_rows=%0d sticky_input_rows=%0d scope=real_guard_mailbox_NOT_FFT_controller",ENABLED,N,checks,samples,private_differences,input_bad_bits,last_bad_bits,current_rows,phase_rows,stalls,reset_rows,words,ADDRESS_WIDTH!=9,unknown_rows,sticky_rows);
    $finish;
  end
  initial begin #20000000;$fatal(1,"FENCE_TEST_TIMEOUT");end
endmodule
