// Additive observations only. No old stimulus, expectation or wait is retimed.
// Forward/product monitors run on fft_clk; inverse consumption runs on clk.
integer arithmetic_events, arithmetic_forward = 0, arithmetic_product = 0;
integer arithmetic_inverse = 0, arithmetic_first_operand = -1, arithmetic_latency_checks = 0;
integer arithmetic_f_epoch = 0, arithmetic_p_epoch = 0, arithmetic_i_epoch = 0;
integer arithmetic_f_count = 0, arithmetic_p_count = 0, arithmetic_i_count = 0;
integer arithmetic_block, arithmetic_position, arithmetic_fixture;
initial begin
  arithmetic_events = $fopen("bank_arithmetic_events.csv", "w");
  $fdisplay(arithmetic_events, "epoch,stream,ordinal,data,position,last,start,ef,ei,cycle");
  #0.01;
  if ((R !== 0 && R !== 1) || (B !== 0 && B !== 1) || (O !== 0 && O !== 1) ||
      REGISTERED_SCHEDULING !== R || QUICK_MUTATION !== 0 ||
      dut.REGISTERED_SCHEDULING !== R || dut.REGISTER_OPERANDS !== O ||
      dut.BOUNDARY_ROUND_SAT !== B || dut.product.REGISTER_OPERANDS !== O ||
      dut.product.PRIVATE_PAYLOAD_BUBBLES !== R || dut.product.DATA_WIDTH !== 18 ||
      dut.product.arithmetic.DATA_WIDTH !== 18 || dut.product.arithmetic.BOUNDARY_ROUND_SAT !== B ||
      dut.product.arithmetic.PRIVATE_PAYLOAD_BUBBLES !== R)
    $fatal(1, "ARITHMETIC_ACTUAL_INSTANCE_BINDING_MISMATCH");
end
always @(posedge fft_clk) begin
  if (dut.fast_running && !expected_fault && (epoch == 1 || epoch == 2)) begin
    if (epoch == 1 && dut.product.input_valid && dut.product.input_ready &&
        dut.product.input_bin_index == 0) arithmetic_first_operand = fast_cycle;
    if (dut.return_valid && dut.result_destination_ready && !dut.next_inverse) begin
      if (arithmetic_f_epoch != epoch) begin arithmetic_f_epoch = epoch; arithmetic_f_count = 0; end
      arithmetic_block = arithmetic_f_count / 512; arithmetic_position = arithmetic_f_count % 512;
      arithmetic_fixture = arithmetic_block % 3;
      if ({dut.return_position, dut.return_last, dut.return_metadata} !==
          {9'(arithmetic_position), (arithmetic_position == 511), 1'b0,
           64'(epoch_base+447*arithmetic_block), 5'd0, forward_exponents[arithmetic_fixture]})
        $fatal(1, "ARITHMETIC_FORWARD_EVENT_METADATA_MISMATCH");
      $fdisplay(arithmetic_events, "%0d,forward,%0d,%09h,%0d,%0d,%0d,%0d,0,%0d",
        epoch, arithmetic_f_count, dut.return_data, dut.return_position, dut.return_last,
        dut.return_metadata[73:10], dut.return_metadata[4:0], fast_cycle);
      arithmetic_f_count = arithmetic_f_count + 1; arithmetic_forward = arithmetic_forward + 1;
    end
    if (dut.product_valid && dut.product_bank_ready) begin
      if (arithmetic_p_epoch != epoch) begin arithmetic_p_epoch = epoch; arithmetic_p_count = 0; end
      arithmetic_block = arithmetic_p_count / 512; arithmetic_position = arithmetic_p_count % 512;
      arithmetic_fixture = arithmetic_block % 3;
      if ({dut.product_position, dut.product_last, dut.product_start, dut.product_exponent, dut.product_overflow} !==
          {9'(arithmetic_position), (arithmetic_position == 511), 64'(epoch_base+447*arithmetic_block),
           forward_exponents[arithmetic_fixture], 1'b0})
        $fatal(1, "ARITHMETIC_PRODUCT_EVENT_METADATA_MISMATCH");
      if (epoch == 1 && arithmetic_position == 0) begin
        if (arithmetic_first_operand < 0 || fast_cycle-arithmetic_first_operand != 3+O)
          $fatal(1, "ARITHMETIC_ACCEPT_TO_BANK_LATENCY_MISMATCH");
        arithmetic_latency_checks = arithmetic_latency_checks + 1;
      end
      $fdisplay(arithmetic_events, "%0d,product,%0d,%09h,%0d,%0d,%0d,%0d,0,%0d",
        epoch, arithmetic_p_count, {dut.product_q,dut.product_i}, dut.product_position,
        dut.product_last, dut.product_start, dut.product_exponent, fast_cycle);
      arithmetic_p_count = arithmetic_p_count + 1; arithmetic_product = arithmetic_product + 1;
    end
  end
end
always @(posedge clk) begin
  if (dut.slow_running && !expected_fault && (epoch == 1 || epoch == 2) && output_valid && output_ready) begin
    if (arithmetic_i_epoch != epoch) begin arithmetic_i_epoch = epoch; arithmetic_i_count = 0; end
    $fdisplay(arithmetic_events, "%0d,inverse,%0d,%09h,%0d,%0d,%0d,%0d,%0d,%0d",
      epoch, arithmetic_i_count, output_data, output_position, output_last, output_metadata[73:10],
      output_metadata[9:5], output_metadata[4:0], slow_cycle);
    arithmetic_i_count = arithmetic_i_count + 1; arithmetic_inverse = arithmetic_inverse + 1;
  end
end
task automatic arithmetic_final_receipt;
  begin
    if (arithmetic_forward != 19456 || arithmetic_product != 19456 || arithmetic_inverse != 19456 ||
        arithmetic_latency_checks != 32)
      $fatal(1, "ARITHMETIC_ACTUAL_INCOMPLETE_EVENT_OR_LATENCY_COVERAGE");
    $fclose(arithmetic_events);
    $display("BANK_ARITHMETIC_ACTUAL_PASS R=%0d B=%0d O=%0d fast_mhz=%0d exact_event_words_per_stream=19456 nominal_blocks=32 stalled_blocks=6 latency_checks=32 accept_to_bank_clocks=%0d old_fault_checks_unchanged=1 score_oracle_only=1",
      R, B, O, FAST_MHZ, 3+O);
  end
endtask
