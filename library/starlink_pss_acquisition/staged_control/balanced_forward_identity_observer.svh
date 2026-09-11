  integer balanced_checks=0,balanced_captures=0;
  always @(posedge fft_clk)if(dut.fast_running)begin
    if(dut.forward_buffer.capture_descriptor_equal !==
       (dut.forward_buffer.capture_descriptor==dut.forward_buffer.descriptor))
      $fatal(1,"balanced descriptor comparison differs from original");
    if(dut.forward_buffer.capture_valid && dut.forward_buffer.capture_ready)
      balanced_captures=balanced_captures+1;
    balanced_checks=balanced_checks+1;
  end
  task automatic report_balanced_forward_identity;
    begin
      if(balanced_checks<10000 || balanced_captures<9216)$fatal(1,"vacuous balanced descriptor check");
      $display("BALANCED_FORWARD_IDENTITY_PASS checks=%0d captures=%0d same_edge=1 four_state_exact=1",
        balanced_checks,balanced_captures);
    end
  endtask
