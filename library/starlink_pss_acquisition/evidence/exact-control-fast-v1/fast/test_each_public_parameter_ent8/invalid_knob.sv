module invalid_knob;
starlink_pss_fft_bank_owned_slice #(.DISTRIBUTED_FAST_FAULT(32'bx), .KERNEL_ROM_FILE("upper_edge_pss_kernel_q17.mem")) dut ();
defparam dut.joiner.PRIVATE_NEXT_START_SCRATCH=0;
initial begin #10; $fatal(1,"INVALID_KNOB_WAS_ACCEPTED"); end
endmodule
