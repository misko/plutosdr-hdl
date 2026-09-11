  integer out_retirement_checks=0,out_retirement_publications=0,out_retirement_retires=0,out_retirement_extra_holds=0;
  reg out_retirement_running,out_retirement_publish,out_retirement_retire,out_retirement_request_before;
  always @(posedge fft_clk)begin
    out_retirement_running=dut.fast_running;
    out_retirement_request_before=dut.output_request;
    out_retirement_publish=dut.output_bank.input_accept && dut.output_bank.input_framing_valid &&
      dut.output_bank.write_position==511 && dut.output_replay_accept;
    out_retirement_retire=dut.output_stage_valid && dut.output_stage_last && dut.output_retire_ready;
    if(out_retirement_running)begin
      out_retirement_checks=out_retirement_checks+1;
      if(dut.output_published_receipt && dut.output_bank.input_accept)
        $fatal(1,"product write after ownership publication");
      if(out_retirement_publish)begin
        if(dut.output_published_receipt!==0 || dut.output_retire_ready!==0)
          $fatal(1,"private final slot retired before registered publication");
        out_retirement_publications=out_retirement_publications+1;
      end
      if(out_retirement_retire)begin
        if(dut.output_published_receipt!==1 || dut.output_stage_ready!==0 || dut.output_bank.input_accept!==0)
          $fatal(1,"private final receipt allowed reuse or duplicate write");
        out_retirement_retires=out_retirement_retires+1;
      end
    end
    #0.001;
    if(out_retirement_running && dut.fast_running)begin
      if((dut.output_request!==out_retirement_request_before) !== out_retirement_publish)
        $fatal(1,"product ownership differs from actual checked bank publication");
      if(out_retirement_publish && !dut.output_stage_fault)begin
        if(dut.output_identity_stage.full!==1 || dut.output_stage_last!==1 || dut.output_published_receipt!==1)
          $fatal(1,"missing extra private final hold");
        out_retirement_extra_holds=out_retirement_extra_holds+1;
      end
      if(out_retirement_retire && dut.output_identity_stage.full!==0)
        $fatal(1,"private slot did not retire on registered receipt");
    end
  end
  task automatic report_output_retirement_receipt;
    begin
      if(out_retirement_checks<10000 || out_retirement_publications<18 || out_retirement_retires<18 || out_retirement_extra_holds<18)
        $fatal(1,"vacuous product retirement observer");
      $display("OUTPUT_RETIREMENT_RECEIPT_PASS checks=%0d publications=%0d retires=%0d extra_holds=%0d exact_publication=1 no_post_publication_write=1 receipt_retirement=1",
        out_retirement_checks,out_retirement_publications,out_retirement_retires,out_retirement_extra_holds);
    end
  endtask
