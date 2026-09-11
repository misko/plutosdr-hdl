  integer retirement_checks=0,retirement_publications=0,retirement_retires=0,retirement_extra_holds=0;
  reg retirement_running,retirement_publish,retirement_retire,retirement_request_before;
  always @(posedge fft_clk)begin
    retirement_running=dut.fast_running;
    retirement_request_before=dut.product_owner_request;
    retirement_publish=dut.product_bank.input_accept && dut.product_bank.input_framing_valid &&
      dut.product_bank.write_position==511 && dut.product_commit_authorized;
    retirement_retire=dut.staged_product_valid && dut.staged_product_last && dut.product_retire_ready;
    if(retirement_running)begin
      retirement_checks=retirement_checks+1;
      if(dut.product_published_receipt && dut.product_bank.input_accept)
        $fatal(1,"product write after ownership publication");
      if(retirement_publish)begin
        if(dut.product_published_receipt!==0 || dut.product_retire_ready!==0)
          $fatal(1,"private final slot retired before registered publication");
        retirement_publications=retirement_publications+1;
      end
      if(retirement_retire)begin
        if(dut.product_published_receipt!==1 || dut.product_stage_ready!==0 || dut.product_bank.input_accept!==0)
          $fatal(1,"private final receipt allowed reuse or duplicate write");
        retirement_retires=retirement_retires+1;
      end
    end
    #0.001;
    if(retirement_running && dut.fast_running)begin
      if((dut.product_owner_request!==retirement_request_before) !== retirement_publish)
        $fatal(1,"product ownership differs from actual checked bank publication");
      if(retirement_publish && !dut.product_stage_fault)begin
        if(dut.product_identity_stage.full!==1 || dut.staged_product_last!==1 || dut.product_published_receipt!==1)
          $fatal(1,"missing extra private final hold");
        retirement_extra_holds=retirement_extra_holds+1;
      end
      if(retirement_retire && dut.product_identity_stage.full!==0)
        $fatal(1,"private slot did not retire on registered receipt");
    end
  end
  task automatic report_product_retirement_receipt;
    begin
      if(retirement_checks<10000 || retirement_publications<18 || retirement_retires<18 || retirement_extra_holds<18)
        $fatal(1,"vacuous product retirement observer");
      $display("PRODUCT_RETIREMENT_RECEIPT_PASS checks=%0d publications=%0d retires=%0d extra_holds=%0d exact_publication=1 no_post_publication_write=1 receipt_retirement=1",
        retirement_checks,retirement_publications,retirement_retires,retirement_extra_holds);
    end
  endtask
