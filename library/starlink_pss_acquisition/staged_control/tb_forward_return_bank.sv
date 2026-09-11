`timescale 1ns/1ps
module tb;
  localparam N=512;
  reg clk=0,resetn=0,abort_epoch=0,reserve_valid=0,capture_valid=0,seal_valid=0,output_ready=0;
  always #5 clk=~clk;
  reg [69:0] reserve_descriptor=0,capture_descriptor=0;
  reg [35:0] capture_data=0;
  reg [8:0] capture_position=0;
  reg capture_last=0;
  reg [4:0] capture_exponent=0;
  wire reserve_ready,capture_ready,output_valid,output_last,done_pulse,busy,fault;
  wire [35:0] output_data;
  wire [8:0] output_position;
  wire [4:0] output_exponent;
  wire [69:0] output_descriptor;
  starlink_pss_forward_return_bank dut(.*);
  integer seed=0,popped=0,total_reads=0,blocks=0,stalls=0,cycles=0,case_id=0;
  integer first_pop=-1,last_pop=-1;
  reg allow_replay=0,held=0;
  reg [120:0] held_word;
  function automatic [35:0] word(input integer k,input integer s);
    word=36'h800000001 ^ (s*32'h1021) ^ (k*32'h1f123);
  endfunction
  function automatic [69:0] tag(input integer s);
    tag=70'h1a5a5a5a5a5a5a0000+s*447;
  endfunction
  always @(posedge clk) begin
    cycles=cycles+1;
    if (!resetn || fault) held=0;
    else begin
      if(dut.read_enable && dut.read_count>=N)$fatal(1,"read beyond owned block");
      if (held && (!output_valid ||
          {output_data,output_position,output_last,output_exponent,output_descriptor}!==held_word))
        $fatal(1,"held replay changed");
      held=output_valid && !output_ready;
      held_word={output_data,output_position,output_last,output_exponent,output_descriptor};
      if (held) stalls=stalls+1;
      if (output_valid) begin
        if (!allow_replay) $fatal(1,"unsealed data exposed");
        if (output_data!==word(popped,seed) || output_position!==popped[8:0] ||
            output_last!==(popped==N-1) || output_descriptor!==tag(seed) ||
            output_exponent!==5'(seed+4)) $fatal(1,"replay mismatch pos=%0d",popped);
        if (output_ready) begin
          if(popped==0)first_pop=cycles;
          popped=popped+1;total_reads=total_reads+1;last_pop=cycles;
        end
      end
    end
  end
  task automatic step;
    begin @(posedge clk);#1;@(negedge clk);end
  endtask
  task automatic reset_bank;
    begin
      resetn=0;abort_epoch=0;reserve_valid=0;capture_valid=0;seal_valid=0;output_ready=0;
      allow_replay=0;held=0;
      repeat(3)step;resetn=1;step;
      if(fault || busy || output_valid || !reserve_ready)$fatal(1,"reset failed");
    end
  endtask
  task automatic reserve_block(input integer s);
    begin
      seed=s;popped=0;first_pop=-1;last_pop=-1;allow_replay=0;
      reserve_descriptor=tag(seed);capture_descriptor=tag(seed);capture_exponent=5'(seed+4);
      if(!reserve_ready)$fatal(1,"reservation unavailable");
      reserve_valid=1;step;reserve_valid=0;
      if(!capture_ready || reserve_ready || !busy)$fatal(1,"reservation not exclusive");
    end
  endtask
  task automatic beat(input integer k);
    begin capture_valid=1;capture_position=9'(k);capture_data=word(k,seed);capture_last=k==N-1;end
  endtask
  task automatic prefix(input integer n);
    begin
      for(integer k=0;k<n;k=k+1)begin
        beat(k);#1;if(!capture_ready)$fatal(1,"capture lost local capacity");step;
      end
      capture_valid=0;
    end
  endtask
  task automatic qualify;
    begin seal_valid=1;allow_replay=1;step;seal_valid=0;end
  endtask
  task automatic drain(input integer pause_mode);
    integer limit;
    begin
      limit=0;
      while(!done_pulse && limit<10000)begin
        output_ready=pause_mode==0 || (limit%7!=0 && limit%7!=1);
        if(pause_mode!=0 && popped==N-1 && limit<900)output_ready=0;
        step;limit=limit+1;
      end
      if(!done_pulse || popped!=N || fault || busy || !reserve_ready)
        $fatal(1,"incomplete replay popped=%0d limit=%0d",popped,limit);
      if(pause_mode==0 && last_pop-first_pop!=N-1)$fatal(1,"unstalled replay has bubbles");
      blocks=blocks+1;output_ready=0;allow_replay=0;step;
      if(done_pulse || output_valid)$fatal(1,"duplicate completion or residual valid");
    end
  endtask
  task automatic good_block(input integer s,input integer mode);
    begin
      reserve_block(s);
      for(integer k=0;k<N;k=k+1)begin
        // Downstream READY changes must not stall capture; descriptor offers
        // for a future reservation must not alter the presently owned block.
        output_ready=(k%3)==0;reserve_descriptor=~tag(seed);
        if(mode==2 && k%17==0)begin capture_valid=0;step;end
        beat(k);#1;if(!capture_ready)$fatal(1,"downstream affected capture");
        if(mode==1 && k==N-1)begin seal_valid=1;allow_replay=1;end
        step;
      end
      capture_valid=0;seal_valid=0;output_ready=0;
      if(mode!=1)begin
        repeat(13)begin step;if(output_valid || capture_ready || !busy)$fatal(1,"unsealed block leaked");end
        qualify;
      end
      drain(mode==0?0:1);
    end
  endtask
  task automatic expect_fault;
    begin
      #1;if(fault!==1'b1 || output_valid!==1'b0)$fatal(1,"current fault not fenced case=%0d",case_id);
      step;capture_valid=0;seal_valid=0;abort_epoch=0;output_ready=0;
      repeat(4)begin step;if(!fault || reserve_ready || capture_ready || output_valid || done_pulse)
        $fatal(1,"fault did not quarantine");end
      reset_bank;good_block(25,0);
    end
  endtask
  initial begin
    if(!$value$plusargs("CASE=%d",case_id))case_id=0;
    reset_bank;
    if(case_id==0)begin
      for(integer b=0;b<9;b=b+1)good_block(b,b%3);
      // Reset with an incomplete capture, an unsealed full block, and a held
      // replay word. Each fresh epoch must hide all prior payload RAM.
      reserve_block(12);prefix(73);reset_bank;good_block(13,0);
      reserve_block(14);prefix(N);reset_bank;good_block(15,1);
      reserve_block(16);prefix(N);qualify;repeat(5)step;
      reset_bank;good_block(17,2);
      $display("FORWARD_RETURN_BANK_PASS blocks=%0d reads=%0d stalls=%0d cycles=%0d capture_decoupled=1 seal_required=1 reset_cases=3",blocks,total_reads,stalls,cycles);
    end else begin
      if(case_id==8)begin beat(0);end
      else begin
        reserve_block(3);
        case(case_id)
          1:begin prefix(1);beat(1);capture_last=1;end
          2:begin prefix(N-1);beat(N-1);capture_last=0;end
          3:begin prefix(2);beat(2);capture_position=3;end
          4:begin prefix(2);beat(2);capture_descriptor=~tag(seed);end
          5:begin prefix(2);beat(2);capture_exponent=capture_exponent+1'b1;end
          6:begin prefix(3);seal_valid=1;end
          7:begin prefix(N);beat(0);end
          9:begin prefix(7);abort_epoch=1;end
          10:begin prefix(N);abort_epoch=1;end
          11:begin prefix(N);qualify;repeat(5)step;abort_epoch=1;end
          12:begin
            prefix(N);qualify;output_ready=1;
            while(popped<N-1)step;
            output_ready=0;step;abort_epoch=1;
          end
          13:begin capture_valid=1'bx;end
          14:begin beat(0);capture_last=1'bx;end
          15:begin beat(0);capture_exponent=5'bx;end
          16:begin beat(0);capture_descriptor=70'bx;end
          17:begin seal_valid=1'bx;end
          18:begin prefix(N);seal_valid=1'bx;end
          19:begin prefix(N);qualify;seal_valid=1;end
          20:begin prefix(N);qualify;output_ready=1'bx;end
          default:$fatal(1,"unknown fault case");
        endcase
      end
      expect_fault;
      $display("FORWARD_RETURN_FAULT_PASS case=%0d fresh_reads=512 immediate_fence=1 sticky=1",case_id);
    end
    $finish;
  end
  initial begin #10000000;$fatal(1,"watchdog");end
endmodule
