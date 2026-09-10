// Non-driving offered-summary witness. Original references and stimulus intact.
integer summary_pre=0,summary_post=0,summary_zero_pre=0,summary_zero_post=0;
integer summary_known_one=0,summary_unknown=0,summary_forward=0,summary_inverse=0;
integer summary_ends=0,summary_routed=0;
initial begin
  #0.001;
  if(dut.INPUT_OFFER_FAULT_SUMMARY!==1 || dut.retained.island.INPUT_OFFER_FAULT_SUMMARY!==1 ||
     dut.retained.island.cutover.ENABLE_OFFERED_FAULT_SUMMARY!==1 ||
     dut.retained.island.owners[0].result_guard.ENABLE_OFFERED_FAULT_SUMMARY!==1 ||
     dut.retained.island.owners[1].result_guard.ENABLE_OFFERED_FAULT_SUMMARY!==1)
    $fatal(1,"summary option forwarding readback");
  $display("RSUMMARY_FLAGS wrapper=1 top=1 cutover=1 owner0=1 owner1=1");
end
task automatic summary_actual_check(input integer post_edge);
  begin
    if(dut.retained.island.fast_running===1'b1)begin
      if(post_edge)summary_post=summary_post+1;else summary_pre=summary_pre+1;
      if(dut.retained.island.input_fault_now===1'b0 || dut.retained.island.input_fault_now===1'b1)begin
        if(dut.retained.island.common_current_fault!==dut.retained.island.original_common_current_fault)
          $fatal(1,"summary known input fault full common equality");
      end else begin
        if(dut.retained.island.common_current_fault!==1'b1)
          $fatal(1,"summary unknown direct input fault not known-one");
        summary_unknown=summary_unknown+1;
      end
      if(dut.retained.island.input_fault_now===1'b1)summary_known_one=summary_known_one+1;
      if(dut.retained.island.input_fault_now===1'b0)begin
        if({dut.retained.island.summary_offer_beat,dut.retained.island.summary_offer_complete}!==
           {dut.retained.island.certified_input_beat,dut.retained.island.certified_input_complete})
          $fatal(1,"summary original physical certificate premise");
        if({dut.retained.island.owners[0].result_guard.offered_input_beat,
            dut.retained.island.owners[0].result_guard.offered_input_complete}!==
           {dut.retained.island.owners[0].result_guard.certified_input_beat,
            dut.retained.island.owners[0].result_guard.certified_input_complete} ||
           {dut.retained.island.owners[1].result_guard.offered_input_beat,
            dut.retained.island.owners[1].result_guard.offered_input_complete}!==
           {dut.retained.island.owners[1].result_guard.certified_input_beat,
            dut.retained.island.owners[1].result_guard.certified_input_complete})
          $fatal(1,"summary exact per-owner routed certificate premise");
        summary_routed=summary_routed+2;
        if(post_edge)summary_zero_post=summary_zero_post+1;else summary_zero_pre=summary_zero_pre+1;
      end
    end
  end
endtask
always @(posedge fft_clk)begin
  #0; // Inactive pre-NBA, matching unchanged physical-input witness.
  summary_actual_check(0);
  if(dut.retained.island.fast_running===1'b1)begin
    if(dut.retained.island.core_input_valid===1'b1 && dut.retained.island.core_input_ready===1'b1)begin
      if(dut.retained.island.certified_input_beat!==1'b1)
        $fatal(1,"summary counted unqualified physical input");
      if(dut.retained.island.routed_inverse===1'b1)summary_inverse=summary_inverse+1;
      else if(dut.retained.island.routed_inverse===1'b0)summary_forward=summary_forward+1;
      else $fatal(1,"summary accepted unknown owner");
    end
    if(dut.retained.island.certified_input_complete===1'b1)summary_ends=summary_ends+1;
  end
  #0.001;
  summary_actual_check(1);
end
final begin
  if(summary_pre<1000 || summary_post<1000 || summary_pre!=summary_zero_pre ||
     summary_post!=summary_zero_post || summary_known_one!=0 || summary_unknown!=0 ||
     summary_ends!=38 || summary_routed!=2*(summary_pre+summary_post))
    $fatal(1,"summary healthy campaign proof inventory");
  $display("RSUMMARY_PROOF pre=%0d post=%0d zero_pre=%0d zero_post=%0d known_one=%0d unknown=%0d forward=%0d inverse=%0d ends=%0d routed=%0d",
    summary_pre,summary_post,summary_zero_pre,summary_zero_post,summary_known_one,summary_unknown,
    summary_forward,summary_inverse,summary_ends,summary_routed);
end
