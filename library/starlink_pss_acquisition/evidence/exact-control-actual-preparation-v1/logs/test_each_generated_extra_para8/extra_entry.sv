module extra_entry; parameter integer EXACT_EXTRA_EPOCHS=0;
  initial begin
    if (EXACT_EXTRA_EPOCHS !== 0 && EXACT_EXTRA_EPOCHS !== 1)
      $fatal(1, "EXACT_EXTRA_EPOCHS_REQUIRES_ZERO_OR_ONE");
  end
initial begin #1; $display("EXTRA_PARAMETER_VALID_NO_FFT"); $finish; end
endmodule
module extra_test; extra_entry #(.EXACT_EXTRA_EPOCHS(1'bx)) dut(); endmodule
