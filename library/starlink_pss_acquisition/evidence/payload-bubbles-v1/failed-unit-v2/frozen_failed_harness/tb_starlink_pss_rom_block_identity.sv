`timescale 1ns/1ps
module tb_starlink_pss_rom_block_identity;
  parameter integer BALANCED_MODE=0;
  reg clk=0; always #5 clk=!clk;
  reg resetn=0,flush=0,input_valid=0,output_ready=1;
  reg [8:0] input_bin_index=0;
  reg [4:0] input_block_exponent=7;
  reg input_last=0;
  reg [63:0] input_block_start_index=0;
  wire input_ready,output_valid,output_last,accepted_pulse,emitted_pulse,input_block_complete_pulse;
  wire sequence_error_pulse,metadata_error_pulse,protocol_fault;
  wire [17:0] output_kernel_i,output_kernel_q;
  wire [8:0] output_bin_index; wire [4:0] output_block_exponent; wire [63:0] output_block_start_index;
  wire old_ready,old_valid,old_last,old_accept,old_emit,old_complete,old_sequence,old_metadata,old_fault;
  wire [17:0] old_i,old_q; wire [8:0] old_position; wire [4:0] old_exponent; wire [63:0] old_start;
  starlink_pss_kernel_rom #(.DATA_WIDTH(18),.ROM_FILE("upper_edge_pss_kernel_q17.mem"),
    .BALANCED_BLOCK_IDENTITY_EQ(BALANCED_MODE)) dut(.*);
  starlink_pss_kernel_rom_7ee87258_golden #(.DATA_WIDTH(18),.ROM_FILE("upper_edge_pss_kernel_q17.mem")) old (
    .clk(clk),.resetn(resetn),.flush(flush),.input_valid(input_valid),.input_ready(old_ready),
    .input_bin_index(input_bin_index),.input_block_exponent(input_block_exponent),.input_last(input_last),
    .input_block_start_index(input_block_start_index),.output_valid(old_valid),.output_ready(output_ready),
    .output_kernel_i(old_i),.output_kernel_q(old_q),.output_bin_index(old_position),
    .output_block_exponent(old_exponent),.output_last(old_last),.output_block_start_index(old_start),
    .accepted_pulse(old_accept),.emitted_pulse(old_emit),.input_block_complete_pulse(old_complete),
    .sequence_error_pulse(old_sequence),.metadata_error_pulse(old_metadata),.protocol_fault(old_fault));
  integer comparison=-1,bit_number=-1,stall=0,checks=0,bit_rows=0,n,k;
  always @(negedge clk) if(resetn && !flush) begin
    checks=checks+1;
    if({input_ready,output_valid,output_kernel_i,output_kernel_q,output_bin_index,output_block_exponent,
        output_last,output_block_start_index,accepted_pulse,emitted_pulse,input_block_complete_pulse,
        sequence_error_pulse,metadata_error_pulse,protocol_fault,dut.expected_bin_index,
        dut.block_exponent,dut.block_start_index,dut.expected_next_block_start,dut.have_previous_block,
        dut.metadata_error_now,dut.sequence_error_now} !==
      {old_ready,old_valid,old_i,old_q,old_position,old_exponent,old_last,old_start,
        old_accept,old_emit,old_complete,old_sequence,old_metadata,old_fault,old.expected_bin_index,
        old.block_exponent,old.block_start_index,old.expected_next_block_start,old.have_previous_block,
        old.metadata_error_now,old.sequence_error_now})
      $fatal(1,"ROM_IDENTITY_MISMATCH comparison=%0d bit=%0d stall=%0d",comparison,bit_number,stall);
  end
  task tick; begin @(posedge clk); #1; end endtask
  task purge; begin
    resetn=0;input_valid=0;output_ready=1;input_bin_index=0;input_last=0;input_block_exponent=7;
    tick();tick();resetn=1;tick();
  end endtask
  task word(input integer pos,input reg [63:0] start); begin
    input_valid=1;input_bin_index=pos;input_last=pos==511;input_block_start_index=start;
    #0.001;while(!input_ready) tick();tick();input_valid=0;
  end endtask
  initial begin
    for(comparison=0;comparison<2;comparison=comparison+1)
      for(bit_number=0;bit_number<64;bit_number=bit_number+1)
        for(stall=0;stall<2;stall=stall+1) begin
          purge();word(0,64'hb23456789abcdef0);
          if(comparison==1) for(n=1;n<512;n=n+1) word(n,64'hb23456789abcdef0);
          output_ready=!stall;input_valid=1;input_bin_index=comparison==0?1:0;input_last=0;
          input_block_start_index=(64'hb23456789abcdef0+(comparison==0?0:447))^(64'b1<<bit_number);
          if(stall) begin
            repeat(3) tick();
            if(protocol_fault || accepted_pulse) $fatal(1,"ROM_STALLED_BEAT_WAS_ACCEPTED");
            output_ready=1;
          end
          tick();input_valid=0;tick();
          if(!protocol_fault) $fatal(1,"ROM_MISMATCH_NOT_REJECTED");
          bit_rows=bit_rows+1;
        end
    comparison=-1;bit_number=-1;
    // Both identity words' branch selection stays exact: first-ever block has
    // no prior-start restriction, and an interior beat does not use next-start.
    purge();word(0,64'hffffffffffffff00);
    for(n=1;n<512;n=n+1) word(n,64'hffffffffffffff00);
    for(n=0;n<512;n=n+1) word(n,64'hbf);
    if(protocol_fault || dut.expected_next_block_start !== 64'h27e) $fatal(1,"ROM_WRAP_CHANGED");
    for(k=0;k<5;k=k+1) begin
      purge();word(0,64'hffffffffffffffff);input_block_exponent=7^(1<<k);
      word(1,64'hffffffffffffffff);tick();
      if(!protocol_fault) $fatal(1,"ROM_EXPONENT_CHECK_LOST");
    end
    for(k=0;k<2;k=k+1) begin
      purge();word(0,73);input_valid=1;input_bin_index=k==0?9:1;input_last=k==1;
      tick();input_valid=0;tick();if(!protocol_fault) $fatal(1,"ROM_FRAMING_CHECK_LOST");
    end
    purge();word(0,500);input_valid=0;input_block_start_index='x;input_block_exponent='x;
    repeat(6) tick();
    flush=1;tick();flush=0;input_block_exponent=7;word(0,123);tick();
    if(protocol_fault || bit_rows!=256) $fatal(1,"ROM_FINAL_WITNESS_MISSING");
    $display("ROM_IDENTITY_PASS balanced=%0d bit_rows=256 comparisons=2 bits=64 ready_stall=2 checks=%0d history_wrap_flush_exponent_framing=1",BALANCED_MODE,checks);
    $finish;
  end
  initial begin #2000000;$fatal(1,"ROM_IDENTITY_TIMEOUT");end
endmodule
