// Read-only current-word reconstruction against the real output bank's header.
  integer output_identity_checks=0,output_identity_words=0,output_identity_finals=0;
  integer output_identity_first_refills=0;
  wire output_original_framing = dut.output_stage_position==dut.output_bank.write_position &&
    dut.output_stage_last==(dut.output_bank.write_position==9'd511) &&
    (dut.output_bank.write_position==0 || dut.output_stage_metadata[36:0]==dut.output_bank.metadata_in_hold);
  always @(posedge fft_clk)if(dut.fast_running)begin
    if(dut.output_bank.input_accept)begin
      if(dut.output_bank.input_framing_valid!==output_original_framing)
        $fatal(1,"output registered identity differs from held actual word");
      output_identity_words=output_identity_words+1;
      if(dut.output_stage_last)output_identity_finals=output_identity_finals+1;
    end
    if(dut.output_writer_metadata_load && dut.output_stage_offer_valid && dut.output_stage_ready)
      output_identity_first_refills=output_identity_first_refills+1;
    if(dut.output_replay_accept && (!dut.output_stage_valid || !dut.output_stage_last ||
       !dut.output_bank.input_accept || !dut.output_bank.input_framing_valid))
      $fatal(1,"output replay accepted before actual validated final write");
    if(dut.output_stage_offer_valid && !dut.output_publication_busy && dut.guard_last_out[1])
      $fatal(1,"unqualified live final entered output stage");
    output_identity_checks=output_identity_checks+1;
  end
  task automatic report_output_identity;
    begin
      if(output_identity_checks<10000 || output_identity_words<9216 ||
         output_identity_finals<18 || output_identity_first_refills<18)
        $fatal(1,"output identity comparison coverage missing");
      $display("OUTPUT_IDENTITY_PASS checks=%0d words=%0d finals=%0d first_refills=%0d actual_word_exact=1 actual_publication=1",
        output_identity_checks,output_identity_words,output_identity_finals,output_identity_first_refills);
    end
  endtask
