// Complete additive top; synthetic zero FFT interface, NOT FFT arithmetic.
// Reproduces the parent's exact paused slow/full old source reset scenario.
// OLD_FAULT instead builds a SEPARATE naturally reachable malformed empty bank.
`timescale 1ns/1ps
module tb_starlink_inverse_source_purge;
  parameter integer SIDE=0, OLD_FAULT=0, FILL_BEFORE_FAST=0;
  reg clk=0, fft_clk=0, slow_enable=1, fast_enable=1;
  always #5 if(slow_enable) clk=~clk; else clk=0;
  always #2.857 if(fast_enable) fft_clk=~fft_clk; else fft_clk=0;
  reg resetn=0, fft_resetn=0, input_valid=0, input_last=0, output_ready=1;
  reg [35:0] input_data=0;
  reg [8:0] input_position=0;
  reg [63:0] input_block_start=64'h200000000;
  wire input_ready, output_valid, output_last, fault;
  wire [35:0] output_data;
  wire [8:0] output_position;
  wire [74:0] output_metadata;
  integer i, fresh_reads=0, outputs=0, fast_cycles=0;
  reg fresh_epoch=0;
  localparam [63:0] FRESH=64'h2000001bf;
  starlink_pss_fft_bank_owned_inverse_sealed_probe #(
    .REGISTERED_SCHEDULING(1), .BOUNDARY_ROUND_SAT(1), .REGISTER_OPERANDS(1),
    .LOCAL_FIRST_ADMISSION(1), .SEALED_INVERSE_OUTPUT(1)) dut (.*);
  task fill;
    for(i=0;i<512;i=i+1) begin
      @(negedge clk); input_valid=1; input_position=i; input_last=(i==511);
      @(posedge clk); if(!input_ready) $fatal(1,"PURGE_SOURCE_CAPACITY_ABSENT");
    end
    @(negedge clk); input_valid=0;
  endtask
  always @(posedge fft_clk) begin
    fast_cycles=fast_cycles+1;
    if(fast_cycles>100000) $fatal(1,"PURGE_TOP_WATCHDOG");
    if(fresh_epoch && dut.source_valid && dut.source_read_ready) begin
      if(dut.source_position!==9'(fresh_reads) || dut.source_data!==0 ||
         dut.source_last!==(fresh_reads==511) || dut.source_metadata!=={1'b0,FRESH,5'b0})
        $fatal(1,"PURGE_FRESH_SOURCE_IDENTITY");
      $display("FRESH_SOURCE pos=%0d metadata=%h",fresh_reads,dut.source_metadata);
      fresh_reads=fresh_reads+1;
    end
  end
  always @(posedge clk) if(fresh_epoch && output_valid && output_ready) begin
    if(output_data!==0 || output_position!==9'(outputs) || output_last!==(outputs==511) ||
       output_metadata!=={1'b1,FRESH,10'b0}) $fatal(1,"PURGE_FRESH_OUTPUT_IDENTITY");
    $display("FRESH_OUTPUT pos=%0d metadata=%h",outputs,output_metadata);
    outputs=outputs+1;
  end
  initial begin
    // The real top has uninitialized reset synchronizer registers: hold the
    // initial asserted resets across actual edges, as the frozen old bench.
    repeat(5) @(negedge clk); resetn=1; fft_resetn=1;
    wait(dut.inverse_epoch_active); repeat(3) @(negedge fft_clk);
    if(OLD_FAULT) begin
      @(negedge clk); input_valid=1; input_position=1;
      @(posedge clk); @(negedge clk); input_valid=0;
      if(!dut.source_fault || dut.source_bank.request_toggle!==0)
        $fatal(1,"OLD_STICKY_EMPTY_SOURCE_NOT_NATURALLY_REACHED");
    end else begin
      // Keep the scheduler parked while filling the OLD bank. Then allow its
      // unchanged reader to prefetch before the one-sided reset is asserted.
      @(negedge fft_clk); fast_enable=0;
      fill(); fast_enable=1; wait(dut.source_valid);
      if(dut.source_fault || dut.source_bank.request_toggle!==1)
        $fatal(1,"OLD_HEALTHY_FULL_SOURCE_NOT_NATURALLY_REACHED");
    end
    @(negedge clk); slow_enable=0;
    #1; if(SIDE==0) resetn=0; else fft_resetn=0;
    repeat(5) @(negedge fft_clk);
    if(dut.fast_running || dut.slow_running || dut.source_valid)
      $fatal(1,"PURGE_ASSERTION_DID_NOT_CLOSE_FAST_READER");
    if(dut.source_bank.request_toggle!==(OLD_FAULT?1'b0:1'b1) || dut.source_fault!==1'(OLD_FAULT))
      $fatal(1,"PAUSED_OLD_PRODUCER_STATE_NOT_RETAINED");
    if(SIDE==0) resetn=1; else fft_resetn=1;
    repeat(80) @(negedge fft_clk);
    // More than the old63-cycle preparation deadline: park BEFORE VERIFY.
    if(!dut.fast_running || dut.slow_running || dut.source_reader_running ||
       dut.source_valid || dut.source_fault_fast || dut.fast_fault || dut.preparing ||
       dut.preparation_fault_now || dut.core_aresetn || dut.inverse_epoch_active)
      $fatal(1,"STALE_SOURCE_OR_FAULT_REOPENED_BEFORE_REMOTE_PURGE");
    $display("PAUSED_PURGE_BARRIER old_fault=%0d old_request=%0d waited_fast=80",OLD_FAULT,dut.source_bank.request_toggle);
    if(FILL_BEFORE_FAST) fast_enable=0;
    slow_enable=1; repeat(8) @(negedge clk);
    if(!dut.slow_running || dut.source_bank.request_toggle!==0 || dut.source_fault || dut.source_valid)
      $fatal(1,"OLD_SOURCE_STATE_SURVIVED_ACTUAL_REMOTE_PURGE");
    input_block_start=FRESH; input_position=0; input_last=0; fresh_epoch=1;
    fill();
    if(FILL_BEFORE_FAST) begin
      if(dut.source_bank.request_toggle!==1 || dut.source_reader_running)
        $fatal(1,"FRESH_FULL_SOURCE_BEFORE_FAST_REJOIN_NOT_EXERCISED");
      fast_enable=1;
    end
    wait(outputs==512); repeat(20) @(negedge clk);
    if(fresh_reads!=512 || fault || dut.fast_fault || dut.source_valid || !input_ready)
      $fatal(1,"PURGE_FRESH_COMPLETE_LIFECYCLE_FAILED");
    // A genuine NEW source fault must still cross and quarantine; the barrier
    // must not simply suppress all future slow-domain fault visibility.
    @(negedge clk); input_valid=1; input_position=1; input_last=0;
    @(posedge clk); @(negedge clk); input_valid=0;
    repeat(8) @(negedge fft_clk);
    if(!dut.source_fault || !dut.source_fault_fast[1] || !dut.fast_fault)
      $fatal(1,"FRESH_SOURCE_FAULT_MASKED_AFTER_REARM");
    $display("FRESH_SOURCE_FAULT_QUARANTINE source=1 synchronized=1 fast=1");
    $display("INVERSE_SOURCE_PURGE_PASS side=%0d old_fault=%0d fill_before_fast=%0d source_words=%0d output_words=%0d synthetic_not_fft=1",SIDE,OLD_FAULT,FILL_BEFORE_FAST,fresh_reads,outputs);
    $finish(0);
  end
endmodule
