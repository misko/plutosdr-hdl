  integer publication_cone_checks=0,publication_cone_enabled=0,publication_cone_faults=0;
  task automatic check_publication_cone;
    reg old_identity,old_fault;
    begin
      old_identity = dut.product_bank_metadata == {1'b1,dut.engine_metadata[68:5],dut.return_metadata[4:0]};
      old_fault = !dut.next_inverse && dut.forward_committed && dut.product_bank_valid &&
        (!old_identity || dut.product_bank_position != 0 || dut.product_bank_last);
      if(dut.forward_handoff_identity !== old_identity || dut.handoff_fault_now !== old_fault)
        $fatal(1,"publication cone changed current four-state predicate");
      publication_cone_checks=publication_cone_checks+1;
      if(dut.handoff_fault_enabled===1'b1)publication_cone_enabled=publication_cone_enabled+1;
      if(old_fault===1'b1)publication_cone_faults=publication_cone_faults+1;
    end
  endtask
  always @(posedge fft_clk)begin
    if(dut.fast_running)check_publication_cone;
    #0.001;
    if(dut.fast_running)check_publication_cone;
  end
  task automatic report_publication_cone;
    begin
      if(publication_cone_checks<10000 || publication_cone_enabled<18)
        $fatal(1,"vacuous publication cone observer");
      $display("PUBLICATION_CONE_PASS checks=%0d enabled=%0d faults=%0d current_exact=1 four_state_exact=1",
        publication_cone_checks,publication_cone_enabled,publication_cone_faults);
    end
  endtask
