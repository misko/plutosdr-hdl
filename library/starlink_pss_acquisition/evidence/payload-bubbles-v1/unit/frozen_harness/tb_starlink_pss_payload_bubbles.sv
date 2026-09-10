`timescale 1ns/1ps
module tb_starlink_pss_payload_bubbles;
  parameter integer JOIN_BUBBLES=0, PRODUCT_BUBBLES=0, BALANCED_ROM=0;
  reg clk=0; always #5 clk=!clk;
  reg resetn=0, flush=0, input_valid=0, product_enable=1, output_ready=1;
  reg [17:0] input_i=0, input_q=0;
  reg [8:0] input_position=0;
  reg [4:0] input_exponent=3;
  reg input_last=0;
  reg [63:0] input_start=0;
  wire j_ready,j_valid,j_last,j_accept,j_emit,j_complete,j_sequence,j_metadata,j_fault;
  wire [17:0] j_i,j_q,j_ki,j_kq;
  wire [8:0] j_position; wire [4:0] j_exponent; wire [63:0] j_start;
  wire p_ready,p_valid,p_last,p_overflow,p_overflow_pulse;
  wire [17:0] p_i,p_q; wire [8:0] p_position; wire [4:0] p_exponent; wire [63:0] p_start;
  wire [86:0] join_controls={j_ready,j_valid,j_position,j_exponent,j_last,j_start,
    j_accept,j_emit,j_complete,j_sequence,j_metadata,j_fault};
  wire [71:0] join_payload={j_i,j_q,j_ki,j_kq};
  wire [118:0] product_outputs={p_ready,p_valid,p_i,p_q,p_position,p_exponent,
    p_last,p_start,p_overflow,p_overflow_pulse};
  wire [144:0] product_private={product.product_valid,product.product_ii,product.product_qq,
    product.product_iq,product.product_qi};
  wire [31:0] checks,join_occupied,product_occupied,join_invalid_differences,product_invalid_differences;
  starlink_pss_forward_kernel_join #(.DATA_WIDTH(18),.KERNEL_ROM_FILE("upper_edge_pss_kernel_q17.mem"),
    .PRIVATE_PAYLOAD_BUBBLES(JOIN_BUBBLES),.BALANCED_BLOCK_IDENTITY_EQ(BALANCED_ROM)) joiner (
    .clk(clk),.resetn(resetn),.flush(flush),.input_valid(input_valid),.input_ready(j_ready),
    .input_i(input_i),.input_q(input_q),.input_bin_index(input_position),
    .input_block_exponent(input_exponent),.input_last(input_last),.input_block_start_index(input_start),
    .output_valid(j_valid),.output_ready(p_ready),.output_i(j_i),.output_q(j_q),
    .output_kernel_i(j_ki),.output_kernel_q(j_kq),.output_bin_index(j_position),
    .output_block_exponent(j_exponent),.output_last(j_last),.output_block_start_index(j_start),
    .accepted_pulse(j_accept),.emitted_pulse(j_emit),.input_block_complete_pulse(j_complete),
    .sequence_error_pulse(j_sequence),.metadata_error_pulse(j_metadata),.protocol_fault(j_fault));
  starlink_pss_spectrum_product #(.DATA_WIDTH(18),.PRIVATE_PAYLOAD_BUBBLES(PRODUCT_BUBBLES)) product (
    .clk(clk),.resetn(resetn),.flush(flush),.input_valid(j_valid&&product_enable),.input_ready(p_ready),
    .input_i(j_i),.input_q(j_q),.kernel_i(j_ki),.kernel_q(j_kq),.input_bin_index(j_position),
    .input_block_exponent(j_exponent),.input_last(j_last),.input_block_start_index(j_start),
    .output_valid(p_valid),.output_ready(output_ready),.output_i(p_i),.output_q(p_q),
    .output_bin_index(p_position),.output_block_exponent(p_exponent),.output_last(p_last),
    .output_block_start_index(p_start),.output_overflow(p_overflow),.overflow_pulse(p_overflow_pulse));
  starlink_pss_payload_bubble_shadow shadow (.*);
  task tick; begin @(posedge clk); #1; end endtask
  task purge; begin
    resetn=0; input_valid=0; output_ready=1; product_enable=1; tick(); tick();
    resetn=1; tick();
  end endtask
  task bubble(input integer count); begin
    input_valid=0;
    repeat(count) begin input_i='x; input_q='x; tick(); end
  end endtask
  task word(input integer position,input reg [63:0] start); begin
    input_valid=1; input_position=position; input_last=position==511; input_start=start;
    input_i=position*997-131072; input_q=131071-position*499;
    #0.001; while(!j_ready) tick(); tick(); input_valid=0;
  end endtask
  integer n,kind;
  initial begin
    purge(); bubble(8);
    // Independent product-only option needs changed invalid operands even if
    // the legacy joiner holds I/Q on bubbles. Accept one lookup with downstream
    // logical product tokens disabled; no product may become valid.
    product_enable=0; word(0,55); bubble(8); purge();
    // Fill all four elastic stages, then alter only invalid upstream payload
    // while every occupied stage must hold. Exercise drain/refill afterwards.
    output_ready=0;
    for(n=0;n<4;n=n+1) word(n,64'h8000000000000000);
    if(j_ready || p_ready || !j_valid || !product.product_valid || !product.sum_valid || !p_valid)
      $fatal(1,"PAYLOAD_MISSING_FULL_STALL");
    bubble(12); output_ready=1;
    for(n=4;n<512;n=n+1) begin word(n,64'h8000000000000000); if(n%11==0) bubble(3); end
    bubble(8);
    for(n=0;n<512;n=n+1) word(n,64'h8000000000000000+447);
    bubble(8);
    if(j_fault) $fatal(1,"PAYLOAD_HEALTHY_HISTORY_FAULT");
    // Preserve original unsigned 64-bit +447 wrap, not a newly invented rule.
    purge(); for(n=0;n<512;n=n+1) word(n,64'hffffffffffffff00);
    for(n=0;n<512;n=n+1) word(n,64'h00000000000000bf);
    bubble(8); if(j_fault) $fatal(1,"PAYLOAD_WRAP_HISTORY_FAULT");
    // Reset and flush occupied stages; subsequent healthy data cannot inherit
    // hostile invalid payload or prior metadata/history.
    purge(); output_ready=0; for(n=0;n<4;n=n+1) word(n,900);
    bubble(3); purge(); word(0,1000); bubble(8);
    flush=1; tick(); flush=0; word(0,1001); bubble(8);
    for(kind=0;kind<3;kind=kind+1) begin
      purge(); word(0,2000); input_valid=1; input_position=1; input_last=0; input_start=2000;
      if(kind==0) input_start=2001;
      if(kind==1) input_position=9;
      if(kind==2) input_last=1;
      tick(); input_valid=0; product_enable=0; bubble(9);
      if(!j_fault) $fatal(1,"PAYLOAD_MISSING_CHECKER_FAULT");
    end
    purge(); word(0,3000); bubble(8);
    if(!checks || !join_occupied || !product_occupied ||
      (JOIN_BUBBLES && !join_invalid_differences) ||
      (PRODUCT_BUBBLES && !product_invalid_differences)) $fatal(1,"PAYLOAD_MISSING_WITNESS");
    $display("PAYLOAD_BUBBLES_PASS join=%0d product=%0d balanced=%0d checks=%0d occupied_join=%0d occupied_product=%0d invalid_join=%0d invalid_product=%0d full_stall_reset_flush_wrap=1",JOIN_BUBBLES,PRODUCT_BUBBLES,BALANCED_ROM,
      checks,join_occupied,product_occupied,join_invalid_differences,product_invalid_differences);
    $finish;
  end
  initial begin #1000000; $fatal(1,"PAYLOAD_TIMEOUT position=%0d expected=%0d fault=%0d",input_position,joiner.kernel_rom.expected_bin_index,j_fault); end
endmodule

module tb_starlink_pss_product_bubbles;
  parameter integer BUBBLES=0;
  reg clk=0; always #5 clk=!clk;
  reg resetn=0,flush=0,input_valid=0,output_ready=0;
  reg signed [17:0] input_i=0,input_q=0,kernel_i=0,kernel_q=0;
  reg [8:0] input_bin_index=0; reg [4:0] input_block_exponent=0;
  reg input_last=0; reg [63:0] input_block_start_index=0;
  wire input_ready,output_valid,output_last,output_overflow,overflow_pulse;
  wire [17:0] output_i,output_q; wire [8:0] output_bin_index;
  wire [4:0] output_block_exponent; wire [63:0] output_block_start_index;
  wire old_ready,old_valid,old_last,old_overflow,old_pulse;
  wire [17:0] old_i,old_q; wire [8:0] old_position; wire [4:0] old_exponent; wire [63:0] old_start;
  starlink_pss_spectrum_product #(.DATA_WIDTH(18),.PRIVATE_PAYLOAD_BUBBLES(BUBBLES)) dut(.*);
  starlink_pss_spectrum_product_7ee87258_golden #(.DATA_WIDTH(18)) old (
    .clk(clk),.resetn(resetn),.flush(flush),.input_valid(input_valid),.input_ready(old_ready),
    .input_i(input_i),.input_q(input_q),.kernel_i(kernel_i),.kernel_q(kernel_q),
    .input_bin_index(input_bin_index),.input_block_exponent(input_block_exponent),
    .input_last(input_last),.input_block_start_index(input_block_start_index),
    .output_valid(old_valid),.output_ready(output_ready),.output_i(old_i),.output_q(old_q),
    .output_bin_index(old_position),.output_block_exponent(old_exponent),.output_last(old_last),
    .output_block_start_index(old_start),.output_overflow(old_overflow),.overflow_pulse(old_pulse));
  function automatic [18:0] numeric(input reg signed [63:0] value);
    reg signed [63:0] q,r;
    begin
      q=value>>>18; r=value&64'h3ffff;
      if(r>131072 || (r==131072 && q[0])) q=q+1;
      if(q>131071) numeric={1'b1,18'h1ffff};
      else if(q < -131072) numeric={1'b1,18'h20000};
      else numeric={1'b0,q[17:0]};
    end
  endfunction
  reg [36:0] expected[0:4095]; integer wr=0,rd=0,checks=0,occupied=0,unknown_bubbles=0,overflow_cases=0;
  reg signed [63:0] a,b,c,d; reg [18:0] real_value,imag_value;
  always @(posedge clk) begin
    if(!resetn || flush) begin wr=0; rd=0; end
    else begin
      if(input_valid && input_ready) begin
        a=input_i; b=input_q; c=kernel_i; d=kernel_q;
        real_value=numeric(a*c-b*d); imag_value=numeric(a*d+b*c);
        expected[wr]={real_value[18]||imag_value[18],imag_value[17:0],real_value[17:0]}; wr=wr+1;
      end
      if(output_valid && output_ready) begin
        if(rd>=wr || {output_overflow,output_q,output_i} !== expected[rd])
          $fatal(1,"PRODUCT_INDEPENDENT_NUMERIC_MISMATCH");
        if(output_overflow) overflow_cases=overflow_cases+1;
        rd=rd+1;
      end
    end
  end
  always @(negedge clk) begin
    if(resetn && !flush) begin
      checks=checks+1;
      if({input_ready,output_valid,output_i,output_q,output_bin_index,output_block_exponent,
          output_last,output_block_start_index,output_overflow,overflow_pulse} !==
        {old_ready,old_valid,old_i,old_q,old_position,old_exponent,old_last,old_start,old_overflow,old_pulse})
        $fatal(1,"PRODUCT_ALL_OUTPUT_MISMATCH");
      if(dut.product_valid !== old.product_valid) $fatal(1,"PRODUCT_INVALID_TOKEN_MISMATCH");
      if(dut.product_valid) begin
        occupied=occupied+1;
        if({dut.product_ii,dut.product_qq,dut.product_iq,dut.product_qi} !==
          {old.product_ii,old.product_qq,old.product_iq,old.product_qi})
          $fatal(1,"PRODUCT_OCCUPIED_MISMATCH");
      end
      if(!input_valid && (^input_i === 1'bx)) unknown_bubbles=unknown_bubbles+1;
    end
  end
  task tick; begin @(posedge clk); #1; end endtask
  integer cycle,k;
  initial begin
    tick(); tick(); resetn=1;
    for(cycle=0;cycle<1600;cycle=cycle+1) begin
      output_ready=cycle%23>=7; input_valid=cycle%13<9;
      input_bin_index=cycle; input_block_exponent=cycle%32;
      input_last=cycle%19==0; input_block_start_index=64'hffffffffffff0000+cycle;
      input_i=$random; input_q=$random; kernel_i=$random; kernel_q=$random;
      // Exact ties, below/above half, negative boundary and positive clipping.
      case(cycle%16)
        0: begin input_i=-131072;input_q=-131072;kernel_i=-131072;kernel_q=-131072;end
        1: begin input_i=-131072;input_q=-131072;kernel_i=131071;kernel_q=-131072;end
        2,3,4,5: begin input_i=(cycle%16)*2-7;input_q=0;kernel_i=-131072;kernel_q=0;end
        6,7,8: begin input_i=2;input_q=0;kernel_i=65529+cycle%16;kernel_q=0;end
      endcase
      if(!input_valid) begin input_i='x;input_q='x;kernel_i='x;kernel_q='x;end
      if(cycle==301 || cycle==901) begin resetn=0;tick();resetn=1;end
      if(cycle==601) begin flush=1;tick();flush=0;end
      tick();
    end
    input_valid=0;output_ready=1;repeat(8) tick();
    if(rd!=wr || !occupied || !unknown_bubbles || !overflow_cases) $fatal(1,"PRODUCT_MISSING_WITNESS");
    $display("PRODUCT_BUBBLES_PASS mode=%0d checks=%0d occupied=%0d unknown_bubbles=%0d clipped=%0d independent_round_even_and_boundary=1",BUBBLES,checks,occupied,unknown_bubbles,overflow_cases);
    $finish;
  end
endmodule
