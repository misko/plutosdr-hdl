module invalid_knob;
starlink_pss_kernel_rom #(.PRIVATE_NEXT_START_SCRATCH(32'bz), .ROM_FILE("upper_edge_pss_kernel_q17.mem")) dut ();

initial begin #10; $fatal(1,"INVALID_KNOB_WAS_ACCEPTED"); end
endmodule
