`timescale 1ns/1ps
module tb_starlink_spectrum_round_boundary;
  parameter integer D = 18;
  reg clk=0;
  always #5 clk=~clk;
  reg resetn=0, flush=0, input_valid=0, output_ready=0;
  reg signed [D-1:0] input_i=0, input_q=0, kernel_i=0, kernel_q=0;
  reg [8:0] input_bin_index=0;
  reg [4:0] input_block_exponent=0;
  reg input_last=0;
  reg [63:0] input_block_start_index=0;
  wire ready[0:1], valid[0:1], last[0:1], overflow[0:1], pulse[0:1];
  wire signed [D-1:0] oi[0:1], oq[0:1];
  wire [8:0] bin[0:1]; wire [4:0] exponent[0:1];
  wire [63:0] start[0:1];
  generate for(genvar n=0;n<2;n=n+1) begin: option_mode
    starlink_pss_spectrum_product #(.DATA_WIDTH(D),.BOUNDARY_ROUND_SAT(n)) dut (
      .clk(clk),.resetn(resetn),.flush(flush),.input_valid(input_valid),
      .input_ready(ready[n]),.input_i(input_i),.input_q(input_q),
      .kernel_i(kernel_i),.kernel_q(kernel_q),.input_bin_index(input_bin_index),
      .input_block_exponent(input_block_exponent),.input_last(input_last),
      .input_block_start_index(input_block_start_index),.output_valid(valid[n]),
      .output_ready(output_ready),.output_i(oi[n]),.output_q(oq[n]),
      .output_bin_index(bin[n]),.output_block_exponent(exponent[n]),
      .output_last(last[n]),.output_block_start_index(start[n]),
      .output_overflow(overflow[n]),.overflow_pulse(pulse[n]));
  end endgenerate
  wire gr, gv, gl, go, gp;
  wire signed [D-1:0] gi,gq;
  wire [8:0] gb; wire [4:0] ge; wire [63:0] gs;
  starlink_pss_spectrum_product_b495_golden #(.DATA_WIDTH(D)) golden (
    .clk(clk),.resetn(resetn),.flush(flush),.input_valid(input_valid),
    .input_ready(gr),.input_i(input_i),.input_q(input_q),
    .kernel_i(kernel_i),.kernel_q(kernel_q),.input_bin_index(input_bin_index),
    .input_block_exponent(input_block_exponent),.input_last(input_last),
    .input_block_start_index(input_block_start_index),.output_valid(gv),
    .output_ready(output_ready),.output_i(gi),.output_q(gq),.output_bin_index(gb),
    .output_block_exponent(ge),.output_last(gl),.output_block_start_index(gs),
    .output_overflow(go),.overflow_pulse(gp));
  integer fd, rc, count=0, cycle, seed=91231, accepted=0, emitted=0;
  integer overflows=0, stalls=0, busy_flushes=0;
  reg [2*D:0] value;
  reg [D:0] expected, old_answer, new_answer;
  reg previous_accept=0;
  reg [1023:0] vector_file;
  initial begin
    if (!$value$plusargs("VECTORS=%s",vector_file)) $fatal(1,"missing vectors");
    fd=$fopen(vector_file,"r"); if(!fd) $fatal(1,"cannot read vectors");
    while(!$feof(fd)) begin
      rc=$fscanf(fd,"%h %h\n",value,expected);
      if(rc!=2) $fatal(1,"bad vector");
      old_answer=golden.round_and_saturate(value);
      new_answer=option_mode[1].dut.boundary_round_and_saturate(value);
      if(old_answer !== expected || new_answer !== expected)
        $fatal(1,"ROUND_BOUNDARY_MISMATCH row=%0d value=%h old=%h new=%h expected=%h",
          count,value,old_answer,new_answer,expected);
      count=count+1;
    end
    $fclose(fd);
    repeat(2) @(negedge clk);
    for(cycle=0;cycle<6000;cycle=cycle+1) begin
      // Keep a source token stable while the preceding edge could not accept it.
      if (!input_valid || previous_accept || flush || !resetn) begin
        input_valid=($random(seed)&3)!=0;
        input_i=$random(seed); input_q=$random(seed);
        kernel_i=$random(seed); kernel_q=$random(seed);
        if(cycle%17==0) begin
          input_i={1'b1,{(D-1){1'b0}}}; input_q=input_i;
          kernel_i=input_i; kernel_q=input_i;
        end
        input_bin_index=$random(seed); input_block_exponent=$random(seed);
        input_last=$random(seed);
        input_block_start_index={$random(seed),$random(seed)};
      end
      // Hostile invalid source payload must not poison later valid results.
      if (!input_valid) begin
        input_i='x; input_q='z; kernel_i='z; kernel_q='x;
      end
      resetn=(cycle%997)!=0;
      flush=(cycle%211)==0;
      output_ready=(cycle%73>=23) && (($random(seed)&3)!=0);
      #1;
      if (flush && (gv || golden.sum_valid || golden.product_valid))
        busy_flushes=busy_flushes+1;
      @(posedge clk);
      previous_accept=input_valid && gr;
      if(input_valid && gr) accepted=accepted+1;
      if(resetn && !flush && gv && output_ready) emitted=emitted+1;
      if(resetn && !flush && gv && !output_ready) stalls=stalls+1;
      #0.001;
      for(integer n=0;n<2;n=n+1)
        if({ready[n],valid[n],oi[n],oq[n],bin[n],exponent[n],last[n],start[n],overflow[n],pulse[n]}
          !== {gr,gv,gi,gq,gb,ge,gl,gs,go,gp})
          $fatal(1,"ROUND_PIPELINE_MISMATCH cycle=%0d option=%0d",cycle,n);
      if(gp) overflows=overflows+1;
      @(negedge clk);
    end
    if(accepted<1000 || emitted<1000 || overflows<20 || stalls<100 || busy_flushes<10)
      $fatal(1,"insufficient pipeline coverage a=%0d e=%0d o=%0d s=%0d f=%0d",
        accepted,emitted,overflows,stalls,busy_flushes);
    $display("ROUND_BOUNDARY_PASS width=%0d vectors=%0d cycles=6000 accepted=%0d emitted=%0d overflow=%0d stalls=%0d busy_flushes=%0d",
      D,count,accepted,emitted,overflows,stalls,busy_flushes);
    $finish;
  end
endmodule
