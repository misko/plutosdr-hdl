`timescale 1ns/1fs
// Real additive joiner + two real ROMs; NOT an FFT or bank-lifecycle model.
module rom_observer_owner #(
  parameter PRIVATE_ROM_READ_AHEAD=1, PRIVATE_BLOCK_METADATA_READ_AHEAD=1,
  parameter REGISTERED_SCHEDULING=1, DISTRIBUTED_FAST_FAULT=1,
  parameter PER_CAUSE_FAULT_CDC=1, PRIVATE_NEXT_START_SCRATCH=1
)(input clk, resetn, private_reset, event_fault, valid, ready,
  input [8:0] position, input last, input [63:0] start, input [4:0] exponent);
  wire fast_running=resetn, core_aresetn=resetn && !private_reset;
  wire any_fast_fault=event_fault;
  starlink_pss_forward_kernel_join_read_ahead #(
    .KERNEL_ROM_FILE("upper_edge_pss_kernel_q17.mem"), .DATA_WIDTH(18),
    .PRIVATE_PAYLOAD_BUBBLES(1), .BALANCED_BLOCK_IDENTITY_EQ(1),
    .PRIVATE_NEXT_START_SCRATCH(PRIVATE_NEXT_START_SCRATCH),
    .PRIVATE_ROM_READ_AHEAD(PRIVATE_ROM_READ_AHEAD),
    .PRIVATE_BLOCK_METADATA_READ_AHEAD(PRIVATE_BLOCK_METADATA_READ_AHEAD)
  ) joiner (.clk(clk), .resetn(resetn), .flush(1'b0),
    .input_valid(valid && !event_fault), .output_ready(ready),
    .input_i(18'sd123), .input_q(-18'sd17), .input_bin_index(position),
    .input_last(last), .input_block_start_index(start), .input_block_exponent(exponent));
endmodule

module tb_rom_actual_observer;
  parameter integer PRIVATE_ROM_READ_AHEAD=1, PRIVATE_BLOCK_METADATA_READ_AHEAD=1;
  parameter integer CORRUPTION=0, ALIAS_PORT=0, SAME_TIME_DRIVE=1;
  reg fft_clk=0, resetn=0, private_reset=0, event_fault=0, valid=0, ready=1;
  reg [8:0] position=0;
  reg last=0;
  reg [63:0] start=64'h8000000000000100;
  reg [4:0] exponent=5'd3;
  always #5 fft_clk=~fft_clk;
  rom_observer_owner #(.PRIVATE_ROM_READ_AHEAD(PRIVATE_ROM_READ_AHEAD),
    .PRIVATE_BLOCK_METADATA_READ_AHEAD(PRIVATE_BLOCK_METADATA_READ_AHEAD)) dut
    (.clk(fft_clk), .resetn(resetn), .private_reset(private_reset),
     .event_fault(event_fault), .valid(valid), .ready(ready),
     .position(position), .last(last), .start(start), .exponent(exponent));
  `include "starlink_pss_rom_actual_observer.svh"
  task tick;
    begin @(negedge fft_clk); #0.002; end
  endtask
  integer n;
  initial begin
    tick(); tick(); resetn=1; tick(); valid=1;
    // First accepted token makes the output occupied. Corruption is applied
    // to the candidate's visible field only; the input-only old ROM is free.
    tick();
    if (CORRUPTION==1) force dut.joiner.kernel_rom.output_kernel_word=36'h123;
    if (CORRUPTION==2) force dut.joiner.kernel_rom.block_start_index=64'h55;
    if (CORRUPTION==3) force dut.joiner.kernel_rom.output_valid=0;
    if (CORRUPTION==4) force dut.joiner.kernel_rom.expected_bin_index=9'h155;
    if (CORRUPTION==5) force dut.joiner.kernel_rom.metadata_error_pulse=1;
    valid=0; ready=0; repeat(3) tick(); ready=1; tick();
    if (ALIAS_PORT) begin
      // Deliberately corrupt the actual INPUT port, not the upstream signal.
      // The shadow must follow it, including its exact malformed-beat fault.
      force dut.joiner.kernel_rom.input_block_start_index=64'h400;
      valid=1; position=1; tick();
      if(dut.joiner.kernel_rom.protocol_fault!==1 || rom_input_reference.protocol_fault!==1)
        $fatal(1,"input-port alias/fault witness missing");
      release dut.joiner.kernel_rom.input_block_start_index;
      valid=0; resetn=0; tick(); resetn=1; tick(); position=0; valid=1; tick();
    end
    for(n=1;n<512;n=n+1) begin
      position=n; last=(n==511); valid=1;
      if(n==511) begin
        // Standalone withheld-final input: two current-fault sampling edges
        // precede final acceptance; this is NOT the real bank result guard.
        event_fault=1; private_reset=1; tick(); tick();
        if(dut.joiner.kernel_rom.expected_bin_index!==511)
          $fatal(1,"standalone final-retirement hold missing");
        event_fault=0; private_reset=0;
      end
      tick();
      if(n==100 && SAME_TIME_DRIVE) begin
        valid=0;
        @(posedge fft_clk); #0.001;
        start=~start; #0.001;
        // The extra same-time observation is not an input sampling edge.
        tick(); start=~start;
      end
    end
    valid=0; tick();
    if(dut.joiner.kernel_rom.protocol_fault!==0)
      $fatal(1,"healthy standalone stream unexpectedly faulted");
    // Reset the ROM, then exercise a malformed first token and sticky retention.
    resetn=0; tick(); resetn=1; tick(); valid=1; position=2; last=0; tick();
    if(dut.joiner.kernel_rom.protocol_fault!==1)
      $fatal(1,"malformed standalone first token not rejected");
    valid=0; start=64'bx; ready=1'bx; tick(); ready=1'bz; tick();
    resetn=0; tick(); resetn=1; valid=0; ready=1; tick();
    rom_verify_terminal();
    $display("ROM_ACTUAL_OBSERVER_OFFLINE_PASS real_joiner_rom=1 vendor_fft=0 bank_lifecycle=0 alias_port=%0d same_time_drive=%0d",ALIAS_PORT,SAME_TIME_DRIVE);
    $finish(0);
  end
  initial begin #20000; $fatal(1,"observer fixture watchdog"); end
endmodule
