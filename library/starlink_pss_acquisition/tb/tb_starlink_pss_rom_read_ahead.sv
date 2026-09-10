`timescale 1ns/1ps
// Standalone ROM only: exact old-source shadow, no FFT or physical claim.
module tb_starlink_pss_rom_read_ahead;
  parameter integer WIDTH=18, BALANCED=1, SCRATCH=1;
  reg clk=0, resetn=0, flush=0, input_valid=0, output_ready=0;
  reg [8:0] input_bin_index=0;
  reg [4:0] input_block_exponent=0;
  reg input_last=0;
  reg [63:0] input_block_start_index=0;
  always #5 clk=~clk;
`define PORTS .clk(clk),.resetn(resetn),.flush(flush),.input_valid(input_valid), \
    .output_ready(output_ready),.input_bin_index(input_bin_index), \
    .input_block_exponent(input_block_exponent),.input_last(input_last), \
    .input_block_start_index(input_block_start_index)
  original_kernel #(.ROM_FILE("kernel.mem"),.DATA_WIDTH(WIDTH),
    .BALANCED_BLOCK_IDENTITY_EQ(BALANCED),.PRIVATE_NEXT_START_SCRATCH(SCRATCH)) original (`PORTS);
  starlink_pss_kernel_rom_read_ahead #(.ROM_FILE("kernel.mem"),.DATA_WIDTH(WIDTH),
    .BALANCED_BLOCK_IDENTITY_EQ(BALANCED),.PRIVATE_NEXT_START_SCRATCH(SCRATCH)) default_rom (`PORTS);
  starlink_pss_kernel_rom_read_ahead #(.ROM_FILE("kernel.mem"),.DATA_WIDTH(WIDTH),
    .BALANCED_BLOCK_IDENTITY_EQ(BALANCED),.PRIVATE_NEXT_START_SCRATCH(SCRATCH),
    .PRIVATE_ROM_READ_AHEAD(1)) candidate (`PORTS);
`undef PORTS
`define VIEW(g) {g.input_ready,g.output_valid,g.output_kernel_i,g.output_kernel_q, \
    g.output_kernel_word,g.output_bin_index,g.output_block_exponent,g.output_last, \
    g.output_block_start_index,g.accepted_pulse,g.emitted_pulse, \
    g.input_block_complete_pulse,g.sequence_error_pulse,g.metadata_error_pulse, \
    g.protocol_fault,g.expected_bin_index,g.block_exponent,g.block_start_index, \
    g.expected_next_block_start,g.have_previous_block,g.output_stage_ready, \
    g.input_accept,g.at_block_start,g.sequence_error_now,g.metadata_error_now, \
    g.protocol_error_now,g.block_identity_equal}
  wire [1023:0] old_view=`VIEW(original), default_view=`VIEW(default_rom), new_view=`VIEW(candidate);
  integer checks=0, cycles=0, healthy=0, stalls=0, faults=0, unknowns=0;
  reg [2*WIDTH-1:0] words[0:511];
  reg [31:0] rng=32'h7e571eaf;
  function automatic [31:0] step(input [31:0] x);
    reg [31:0] y;
    begin y=x^(x<<13); y=y^(y>>17); step=y^(y<<5); end
  endfunction
  task compare;
    begin
      if(old_view !== default_view || old_view !== new_view) begin
        $display("ROM_READ_AHEAD_MISMATCH cycles=%0d old=%h default=%h new=%h",cycles,old_view,default_view,new_view);
        $fatal(1,"unconditional visible and old-private-state mismatch");
      end
      checks=checks+1;
    end
  endtask
  always @(posedge clk) begin
    cycles=cycles+1; compare(); #1; compare();
  end
  task tick;
    begin @(negedge clk); #1; compare(); end
  endtask
  task reset_epoch;
    begin
      resetn=0; flush=0; input_valid=0; output_ready=0;
      tick(); tick(); resetn=1; tick();
    end
  endtask
  task block(input [63:0] base, input [4:0] exponent);
    integer n;
    begin
      for(n=0;n<512;n=n+1) begin
        input_valid=1; input_bin_index=n; input_last=(n==511);
        input_block_exponent=exponent; input_block_start_index=base;
        output_ready=1; tick();
        if(candidate.output_valid!==1 || candidate.output_kernel_word!==words[n])
          $fatal(1,"accepted coefficient latency/value mismatch");
        if(n%7==0) begin
          output_ready=0; input_valid=1; input_bin_index=~n;
          input_block_start_index=~base; tick(); tick(); stalls=stalls+2;
        end
        // Reading a bubble must not change the last visible coefficient.
        output_ready=1; input_valid=0; input_bin_index=n^9'h155;
        tick();
        if(candidate.output_kernel_word!==words[n]) $fatal(1,"invalid coefficient changed");
      end
      healthy=healthy+1;
    end
  endtask
  integer n, bit_index;
  initial begin
    if($bits(`VIEW(original))>1024) $fatal(1,"comparison truncation");
    $readmemh("kernel.mem",words);
    #1; reset_epoch(); block(64'h123456780,5'd3); block(64'h12345693f,5'd7);
    for(bit_index=0;bit_index<64;bit_index=bit_index+1) begin
      reset_epoch(); output_ready=1; input_valid=1; input_bin_index=0;
      input_last=0; input_block_start_index=64'h123456780; input_block_exponent=3; tick();
      input_bin_index=1; input_block_start_index=64'h123456780^(64'b1<<bit_index); tick();
      if(candidate.protocol_fault!==1) $fatal(1,"metadata fault missing");
      input_valid=0; input_bin_index=500; tick(); faults=faults+1;
    end
    // Four-state metadata on an otherwise accepted beat exercises the exact
    // original procedural 'if(error) ... else lookup' behavior, not sanitization.
    for(n=0;n<2;n=n+1) begin
      reset_epoch(); output_ready=1; input_valid=1; input_bin_index=0;
      input_last=0; input_block_start_index=64'h123; input_block_exponent=3; tick();
      input_bin_index=1; input_block_start_index=n ? 64'bz : 64'bx; tick();
      if(candidate.output_kernel_word!==words[1]) $fatal(1,"unknown metadata branch changed");
      unknowns=unknowns+1;
    end
    // Deterministic unconstrained input stream, explicitly not all healthy jobs.
    for(n=0;n<20000;n=n+1) begin
      rng=step(rng); resetn=(n%137!=0); flush=(n%193==0);
      input_valid=rng[0]; output_ready=rng[1]; input_bin_index=rng[10:2];
      input_last=rng[11]; input_block_exponent=rng[16:12];
      input_block_start_index={rng,~rng};
      case(n%97)
        1: input_valid=1'bx;
        2: input_valid=1'bz;
        3: output_ready=1'bx;
        4: output_ready=1'bz;
        5: input_bin_index=9'bx;
        6: input_last=1'bz;
        7: flush=1'bx;
        8: resetn=1'bx;
      endcase
      tick();
    end
    reset_epoch(); block(64'h2468,5'd2); flush=1; tick(); flush=0; tick();
    if(healthy!=3 || faults!=64 || unknowns!=2 || stalls==0)
      $fatal(1,"missing coverage");
    $display("ROM_READ_AHEAD_OFFLINE_PASS width=%0d balanced=%0d scratch=%0d healthy=%0d faults=%0d unknown_metadata=%0d stalls=%0d cycles=%0d checks=%0d",WIDTH,BALANCED,SCRATCH,healthy,faults,unknowns,stalls,cycles,checks);
    $finish(0);
  end
  initial begin #1000000; $fatal(1,"watchdog"); end
endmodule
