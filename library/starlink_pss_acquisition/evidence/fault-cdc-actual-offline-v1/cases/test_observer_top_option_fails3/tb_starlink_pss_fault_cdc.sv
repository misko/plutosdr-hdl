`timescale 1ns/1ps
// CDC recurrence only. Vendor FFT is quiescent; forced source-Q snapshots
// deliberately include non-monotone/X/Z cases. This is NOT actual FFT coverage.
module tb_starlink_pss_fault_cdc;
  parameter integer ENABLED=1, REGISTERED=1, SLOW_PHASE_PS=0;
  parameter integer PER_CAUSE_FAULT_CDC=32'bz;
  `include "starlink_pss_fault_cdc_actual_observer.svh"
  reg clk=0, fft_clk=0, resetn=0, fft_resetn=0;
  initial begin #(SLOW_PHASE_PS * 1ps); forever #5ns clk=~clk; end
  always #2857ps fft_clk=~fft_clk;
  reg [11:0] driven_causes=0;
  wire dut_ready, dut_valid, dut_fault;
  wire golden_ready, golden_valid, golden_fault;
  starlink_pss_fft_bank_owned_slice #(.REGISTERED_SCHEDULING(REGISTERED),
    .DISTRIBUTED_FAST_FAULT(1), .PRIVATE_NEXT_START_SCRATCH(1), .PER_CAUSE_FAULT_CDC(ENABLED)) dut (
    .clk(clk), .fft_clk(fft_clk), .resetn(resetn), .fft_resetn(fft_resetn),
    .input_valid(1'b0), .input_data(36'b0), .input_position(9'b0), .input_last(1'b0),
    .input_block_start(64'b0), .input_ready(dut_ready),
    .output_valid(dut_valid), .output_ready(1'b1), .fault(dut_fault)
  );
  starlink_pss_fft_bank_owned_slice_cdc_golden #(.REGISTERED_SCHEDULING(REGISTERED),
    .DISTRIBUTED_FAST_FAULT(1), .PRIVATE_NEXT_START_SCRATCH(1)) golden (
    .clk(clk), .fft_clk(fft_clk), .resetn(resetn), .fft_resetn(fft_resetn),
    .input_valid(1'b0), .input_data(36'b0), .input_position(9'b0), .input_last(1'b0),
    .input_block_start(64'b0), .input_ready(golden_ready),
    .output_valid(golden_valid), .output_ready(1'b1), .fault(golden_fault)
  );
  reg [1:0] scalar_model=0;
  integer slow_checks=0, fast_checks=0, masks=0, x_rows=0;
  integer reset_rows=0, private_reset_rows=0, phase_kind=0, bit_index, mask;
  reg checking=0;
  always @(posedge clk) begin
    if (!golden.slow_running) scalar_model <= 0;
    else scalar_model <= {scalar_model[0], |driven_causes};
    #2ps;
    if (checking) begin
      slow_checks=slow_checks+1;
      if (dut.fast_fault_slow !== golden.fast_fault_slow ||
          dut.fast_fault_slow !== scalar_model ||
          {dut_ready,dut_valid,dut_fault} !==
          {golden_ready,golden_valid,golden_fault}) begin
        $display("CDC_MISMATCH kind=%0d causes=%b dut=%b golden=%b model=%b slow_running=%b",
          phase_kind,driven_causes,dut.fast_fault_slow,golden.fast_fault_slow,
          scalar_model,golden.slow_running);
        $fatal(1,"CDC_STAGE_OR_PUBLIC_MISMATCH");
      end
    end
  end
  always @(posedge fft_clk) begin
    #2ps;
    if (checking) begin
      fast_checks=fast_checks+1;
      if ({dut.fast_fault,dut.fast_running,dut.core_aresetn} !==
          {golden.fast_fault,golden.fast_running,golden.core_aresetn})
        $fatal(1,"CDC_FAST_DOMAIN_CHANGED");
    end
  end
  task settle;
    begin repeat(4) @(negedge clk); end
  endtask
  task drive(input [11:0] value);
    begin @(negedge fft_clk); driven_causes=value; settle(); end
  endtask
  task epoch_reset(input integer kind);
    begin
      phase_kind=10+kind;
      drive(12'h800);
      #173ps;
      if (kind != 1) resetn=0;
      if (kind != 0) fft_resetn=0;
      settle();
      if (dut.fast_fault_slow !== 0 || golden.fast_fault_slow !== 0)
        $fatal(1,"CDC_EPOCH_RESET_NOT_ZERO");
      driven_causes=0;
      #311ps; resetn=1; fft_resetn=1;
      settle();
      if (dut.fast_fault_slow !== 0) $fatal(1,"CDC_RESET_STALE_REPLAY");
      reset_rows=reset_rows+1;
    end
  endtask
  initial begin
    force dut.distributed_fast_fault.cause_sticky = driven_causes;
    force golden.distributed_fast_fault.cause_sticky = driven_causes;
    settle(); checking=1;
    #173ps; resetn=1; fft_resetn=1; settle();
    phase_kind=1;
    for (mask=0;mask<4096;mask=mask+1) begin drive(mask[11:0]); masks=masks+1; end
    phase_kind=2;
    for (bit_index=0;bit_index<12;bit_index=bit_index+1) begin
      drive(0); driven_causes[bit_index]=1'bx; settle(); x_rows=x_rows+1;
      drive(0); driven_causes[bit_index]=1'bz; settle(); x_rows=x_rows+1;
      drive(12'hfff); driven_causes[bit_index]=1'bx; settle(); x_rows=x_rows+1;
      drive(12'hfff); driven_causes[bit_index]=1'bz; settle(); x_rows=x_rows+1;
    end
    phase_kind=3;
    drive(12'h020);
    force dut.core_release=1; force golden.core_release=1; settle();
    force dut.core_release=0; force golden.core_release=0; settle();
    if (dut.fast_fault_slow !== 2'b11 || dut.fast_running !== 1'b1)
      $fatal(1,"CDC_PRIVATE_RESET_LOST_EPOCH_FAULT");
    private_reset_rows=private_reset_rows+1;
    release dut.core_release; release golden.core_release;
    epoch_reset(0); epoch_reset(1); epoch_reset(2);
    drive(12'h001); drive(0); drive(12'h800); drive(0);
    if (slow_checks == 0 || fast_checks == 0 || masks != 4096 || x_rows != 48 ||
        reset_rows != 3 || private_reset_rows != 1) $fatal(1,"CDC_SCOPE_INCOMPLETE");
    drive(12'h001);
    force dut.event_last_missing=1; force golden.event_last_missing=1;
    force dut.joiner.kernel_rom.expected_bin_index=511;
    repeat(4) @(negedge fft_clk);
    fault_cdc_verify_terminal();
    $display("FAULT_CDC_PASS enabled=%0d registered=%0d phase_ps=%0d masks=%0d x_rows=%0d reset_rows=%0d private_reset_rows=%0d slow_checks=%0d fast_checks=%0d quiescent_stub_not_fft=1",
      ENABLED,REGISTERED,SLOW_PHASE_PS,masks,x_rows,reset_rows,private_reset_rows,slow_checks,fast_checks);
    $finish;
  end
  initial begin #2ms; $fatal(1,"CDC_TEST_TIMEOUT"); end
endmodule
