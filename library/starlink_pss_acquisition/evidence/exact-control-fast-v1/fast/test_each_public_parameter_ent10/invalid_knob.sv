module invalid_knob;
starlink_pss_forward_kernel_join #(.PRIVATE_NEXT_START_SCRATCH(32'bx), .KERNEL_ROM_FILE("upper_edge_pss_kernel_q17.mem")) dut ();
defparam dut.kernel_rom.PRIVATE_NEXT_START_SCRATCH=0;
initial begin #10; $fatal(1,"INVALID_KNOB_WAS_ACCEPTED"); end
endmodule
