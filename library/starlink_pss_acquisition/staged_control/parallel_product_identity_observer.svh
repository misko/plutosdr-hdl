  integer parallel_identity_checks=0,parallel_identity_captures=0,parallel_identity_refills=0;
  reg parallel_identity_expected,parallel_identity_take;
  always @(posedge fft_clk)begin
    parallel_identity_take=0;
    if(dut.fast_running)begin
      parallel_identity_checks=parallel_identity_checks+1;
      parallel_identity_expected=(dut.product_identity_stage.input_metadata ==
        (dut.product_writer_metadata_load ? dut.staged_product_metadata : dut.product_writer_metadata)) === 1'b1;
      if(dut.product_identity_stage.identity_good !== parallel_identity_expected)
        $fatal(1,"parallel product reference differs from original mux equality");
      parallel_identity_take=dut.product_identity_stage.take_input && !dut.product_identity_stage.fault;
      if(parallel_identity_take)begin
        parallel_identity_captures=parallel_identity_captures+1;
        if(dut.product_writer_metadata_load)parallel_identity_refills=parallel_identity_refills+1;
      end
    end
    #0.001;
    if(dut.fast_running && parallel_identity_take &&
       dut.staged_product_identity_good !== parallel_identity_expected)
      $fatal(1,"parallel product certificate not captured with word");
  end
  task automatic report_parallel_product_identity;
    begin
      if(parallel_identity_checks<10000 || parallel_identity_captures<9216 || parallel_identity_refills<18)
        $fatal(1,"vacuous parallel product identity observer");
      $display("PARALLEL_PRODUCT_IDENTITY_PASS checks=%0d captures=%0d first_refills=%0d four_state_exact=1 same_edge_capture=1",
        parallel_identity_checks,parallel_identity_captures,parallel_identity_refills);
    end
  endtask
