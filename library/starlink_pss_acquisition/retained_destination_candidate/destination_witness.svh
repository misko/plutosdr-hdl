// Additive read-only source-specific common/owner shadow. All old observers stay.
`define DS dut.retained.island
  wire ds_reusable,ds_reservation,ds_retained,ds_fault,ds_receipt,ds_release;
  wire [7:0] ds_reasons;
  wire [1:0] ds_lease,ds_held;
  wire ds_original_common = `DS.INPUT_OFFER_FAULT_SUMMARY ?
    `DS.offered_common_current_fault : `DS.original_common_current_fault;
  starlink_pss_retained_output_owner destination_owner_shadow(
    .clk(fft_clk),.resetn(`DS.fast_running),
    .inverse_admit(`DS.job_accept && `DS.next_inverse),
    .inverse_publication(`DS.guard_commit_out[1] && `DS.output_bank_ready),
    .inverse_guard_ack(`DS.guard_ack[1]),
    .transfer_consumed(`DS.completion_accept && `DS.next_inverse),
    .bank_ready(`DS.output_bank_ready),.bank_request(`DS.output_request),
    .bank_ack_sync(`DS.output_ack_sync),.common_current_fault(ds_original_common),
    .reusable(ds_reusable),.reservation(ds_reservation),.retained(ds_retained),.fault_now(ds_fault),
    .transfer_receipt(ds_receipt),.reader_release(ds_release),.fault_reasons(ds_reasons),
    .current_lease(ds_lease),.admitted_lease(ds_held));
  integer ds_pre=0,ds_post=0,ds_releases=0,ds_admits=0,ds_publications=0;
  task destination_check;
    begin
      if(`DS.common_current_fault!==ds_original_common)
        $fatal(1,"destination composed exact common");
      if({`DS.retained_owner.reserved,`DS.retained_owner.published,`DS.retained_owner.busy_seen,
          `DS.retained_owner.expected_request,`DS.retained_owner.lease,`DS.retained_owner.held_lease,
          `DS.retained_owner.transfer_receipt,`DS.retained_owner.fault_reasons} !==
         {destination_owner_shadow.reserved,destination_owner_shadow.published,destination_owner_shadow.busy_seen,
          destination_owner_shadow.expected_request,destination_owner_shadow.lease,destination_owner_shadow.held_lease,
          destination_owner_shadow.transfer_receipt,destination_owner_shadow.fault_reasons})
        $fatal(1,"destination composed full17 owner state");
      if({`DS.retained_reusable,`DS.retained_reserved,`DS.retained_published,`DS.retained_fault_now,
          `DS.producer_transfer_receipt,`DS.reader_release,`DS.retained_reasons,
          `DS.retained_owner.current_lease,`DS.retained_owner.admitted_lease} !==
         {ds_reusable,ds_reservation,ds_retained,ds_fault,ds_receipt,ds_release,ds_reasons,ds_lease,ds_held})
        $fatal(1,"destination composed every old owner output");
      if(`DS.retained_reserved_known !==
         (destination_owner_shadow.reserved===1'b0 || destination_owner_shadow.reserved===1'b1))
        $fatal(1,"destination composed knownness port");
    end
  endtask
  always @(posedge fft_clk)begin
    destination_check();ds_pre=ds_pre+1;
    if(`DS.fast_running)begin
      if(`DS.reader_release)ds_releases=ds_releases+1;
      if(`DS.job_accept && `DS.next_inverse)ds_admits=ds_admits+1;
      if(`DS.guard_commit_out[1] && `DS.output_bank_ready)ds_publications=ds_publications+1;
    end
    #0.001;destination_check();ds_post=ds_post+1;
  end
  final begin
    if(ds_pre<1000||ds_post<1000||ds_releases!=17||ds_admits!=19||ds_publications!=19)
      $fatal(1,"destination composed full campaign witnesses");
    $display("DESTINATION_COMPOSED_PASS mode=%0d pre=%0d post=%0d releases=%0d admits=%0d publications=%0d",
      `DS.CONTEXTUAL_DESTINATION_SUMMARY,ds_pre,ds_post,ds_releases,ds_admits,ds_publications);
  end
`undef DS
