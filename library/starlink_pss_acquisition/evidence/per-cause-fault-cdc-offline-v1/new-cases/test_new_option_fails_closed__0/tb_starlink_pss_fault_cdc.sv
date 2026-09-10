module tb_starlink_pss_fault_cdc;
starlink_pss_fft_bank_owned_slice #(.DISTRIBUTED_FAST_FAULT(1),
  .PER_CAUSE_FAULT_CDC(-1)) candidate ();
initial begin #10; $fatal(1,"CDC_BAD_OPTION_ACCEPTED"); end
endmodule
