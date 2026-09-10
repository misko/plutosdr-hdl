// Additive standalone epochs; the frozen original bench remains intact.
integer metadata_fault_bits=0, metadata_unknown_first=0;
integer metadata_bubbles=0, metadata_flush_zero=0, metadata_flush_one=0;
integer metadata_wrap_blocks=0, metadata_malformed_first=0;
integer metadata_unknown_framing=0;
task metadata_prime;
  begin
    reset_epoch(); input_valid=1; output_ready=1; input_bin_index=0;
    input_last=0; input_block_start_index=64'hfedcba9876543210;
    input_block_exponent=5'h15; tick();
    if(candidate.private_block_metadata_read_ahead.metadata_selected!==1 ||
       candidate.block_start_index!==64'hfedcba9876543210 ||
       candidate.block_exponent!==5'h15 || candidate.output_valid!==1)
      $fatal(1,"metadata healthy first-beat witness missing");
  end
endtask
task metadata_walk(input [63:0] base, input [4:0] exponent);
  integer bin_number;
  begin
    for(bin_number=0;bin_number<512;bin_number=bin_number+1) begin
      input_valid=1; output_ready=1; input_bin_index=bin_number;
      input_last=(bin_number==511); input_block_start_index=base;
      input_block_exponent=exponent; tick();
      if(candidate.output_valid!==1 || candidate.protocol_fault!==0 ||
         candidate.block_start_index!==base || candidate.block_exponent!==exponent)
        $fatal(1,"metadata continuous/wrap block witness missing");
      if(candidate.private_block_metadata_read_ahead.metadata_selected!==(bin_number==0))
        $fatal(1,"metadata private selector must follow exact first-beat event");
    end
    metadata_wrap_blocks=metadata_wrap_blocks+1;
  end
endtask
task metadata_extra_cases;
  integer bit_number, kind, selected;
  reg [68:0] changed_tuple;
  begin
    // Every tuple bit must retain the admitted descriptor on interior faults.
    for(bit_number=0;bit_number<69;bit_number=bit_number+1) begin
      metadata_prime(); input_bin_index=1;
      changed_tuple={64'hfedcba9876543210,5'h15} ^ (69'b1<<bit_number);
      {input_block_start_index,input_block_exponent}=changed_tuple;
      tick();
      if(candidate.protocol_fault!==1 || candidate.metadata_error_pulse!==1 ||
         candidate.output_valid!==0 ||
         {candidate.block_start_index,candidate.block_exponent}!==
           {64'hfedcba9876543210,5'h15})
        $fatal(1,"metadata bit fault changed admitted tuple or veto");
      metadata_fault_bits=metadata_fault_bits+1;
    end
    // Speculative capture is allowed on invalid/X/Z-valid first-slot bubbles,
    // but the externally and checker-visible tuple must stay exactly zero.
    for(kind=0;kind<3;kind=kind+1) begin
      reset_epoch(); output_ready=1; input_valid=kind==0 ? 1'b0 :
        (kind==1 ? 1'bx : 1'bz);
      input_bin_index=0; input_last=0;
      input_block_start_index=64'h0123456789abcdef; input_block_exponent=5'h1f;
      tick();
      if(candidate.private_block_metadata_read_ahead.speculative_metadata!==
           {64'h0123456789abcdef,5'h1f} ||
         {candidate.block_start_index,candidate.block_exponent}!==69'b0 ||
         candidate.private_block_metadata_read_ahead.metadata_selected!==0)
        $fatal(1,"metadata invalid first-slot capture/retention witness missing");
      metadata_bubbles=metadata_bubbles+1;
    end
    // First-block metadata is not validated against previous history. Keep the
    // original procedural semantics when the accepted tuple itself has X/Z.
    for(kind=0;kind<2;kind=kind+1) begin
      reset_epoch(); output_ready=1; input_valid=1; input_bin_index=0; input_last=0;
      input_block_start_index=kind ? 64'bz : 64'bx;
      input_block_exponent=kind ? 5'bz : 5'bx; tick();
      if(candidate.output_valid!==1 || candidate.protocol_fault!==0 ||
         {candidate.block_start_index,candidate.block_exponent}!==
         {input_block_start_index,input_block_exponent})
        $fatal(1,"metadata accepted unknown first tuple changed");
      metadata_unknown_first=metadata_unknown_first+1;
    end
    for(selected=0;selected<2;selected=selected+1) begin
      metadata_prime();
      if(!selected) begin output_ready=0; tick(); end
      if(candidate.output_valid!==1 ||
         candidate.private_block_metadata_read_ahead.metadata_selected!==selected[0])
        $fatal(1,"metadata occupied flush selector witness missing");
      flush=1; tick();
      if({candidate.block_start_index,candidate.block_exponent}!==69'b0 ||
         candidate.private_block_metadata_read_ahead.metadata_selected!==0)
        $fatal(1,"metadata flush failed");
      if(selected) metadata_flush_one=metadata_flush_one+1;
      else metadata_flush_zero=metadata_flush_zero+1;
    end
    for(kind=0;kind<2;kind=kind+1) begin
      reset_epoch(); output_ready=1; input_valid=1; input_bin_index=0;
      input_last=kind ? 1'bz : 1'bx;
      input_block_start_index=64'h8070605040302010; input_block_exponent=9;
      #1;
      if(candidate.protocol_error_now!==1'bx || candidate.input_accept!==1)
        $fatal(1,"metadata unknown first framing precondition missing");
      tick();
      if(candidate.output_valid!==1 || candidate.protocol_fault!==0 ||
         candidate.block_start_index!==64'h8070605040302010 || candidate.block_exponent!==9)
        $fatal(1,"metadata procedural unknown framing branch changed");
      metadata_unknown_framing=metadata_unknown_framing+1;
    end
    // Malformed first TLAST and ordinal must not expose the speculative tuple.
    for(kind=0;kind<2;kind=kind+1) begin
      reset_epoch(); output_ready=1; input_valid=1;
      input_bin_index=kind ? 0 : 1; input_last=kind ? 1 : 0;
      input_block_start_index=64'h8000000000000001; input_block_exponent=31;
      tick();
      if(candidate.protocol_fault!==1 || candidate.sequence_error_pulse!==1 ||
         candidate.output_valid!==0 ||
         {candidate.block_start_index,candidate.block_exponent}!==69'b0)
        $fatal(1,"metadata malformed first publication escaped");
      metadata_malformed_first=metadata_malformed_first+1;
    end
    reset_epoch(); metadata_walk(64'hffffffffffffff38,5'h1f);
    if(candidate.expected_next_block_start!==64'hf7 ||
       candidate.at_block_start!==1 || candidate.have_previous_block!==1)
      $fatal(1,"metadata modulo-64 plus447 witness missing");
    input_valid=0; input_bin_index=0; input_last=0;
    input_block_start_index=64'h80000000000000f7; input_block_exponent=0; tick();
    if(candidate.block_start_index!==64'hffffffffffffff38 || candidate.protocol_fault!==0)
      $fatal(1,"metadata next-first invalid bubble changed old tuple");
    metadata_walk(64'hf7,5'h02);
    input_valid=1; input_bin_index=0; input_last=0;
    input_block_start_index=64'h80000000000002b6; input_block_exponent=0; tick();
    if(candidate.metadata_error_pulse!==1 || candidate.protocol_fault!==1 ||
       candidate.block_start_index!==64'hf7 || candidate.block_exponent!==2)
      $fatal(1,"metadata next-block bit63 mismatch escaped");
    if(metadata_fault_bits!=69 || metadata_unknown_first!=2 || metadata_bubbles!=3 ||
       metadata_flush_zero!=1 || metadata_flush_one!=1 || metadata_wrap_blocks!=2 ||
       metadata_malformed_first!=2 || metadata_unknown_framing!=2)
      $fatal(1,"missing metadata extra coverage");
    $display("ROM_METADATA_EXTRA_PASS bit_faults=%0d unknown_first=%0d invalid_bubbles=%0d flush_zero=%0d flush_one=%0d wrap_blocks=%0d malformed_first=%0d",metadata_fault_bits,metadata_unknown_first,metadata_bubbles,metadata_flush_zero,metadata_flush_one,metadata_wrap_blocks,metadata_malformed_first);
    $display("ROM_METADATA_FOUR_STATE_PASS unknown_framing=%0d",metadata_unknown_framing);
  end
endtask
