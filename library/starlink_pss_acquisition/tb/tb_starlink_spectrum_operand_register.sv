`timescale 1ns/1ps
module tb_starlink_spectrum_operand_register;
  parameter integer D=18, B=0;
  localparam integer N=1024, W=6*D+80, OUT=2*D+80;
  reg clk=0; always #5 clk=~clk;
  reg resetn=0, flush=0, sink_ready=0;
  reg iv[0:1]; wire ir[0:1], ov[0:1], of[0:1], pulse[0:1];
  reg signed [D-1:0] ii[0:1], iq[0:1], ki[0:1], kq[0:1];
  reg [8:0] bin[0:1]; reg [4:0] exponent[0:1]; reg last[0:1]; reg [63:0] start[0:1];
  wire signed [D-1:0] oi[0:1], oq[0:1];
  wire [8:0] ob[0:1]; wire [4:0] oe[0:1]; wire ol[0:1]; wire [63:0] os[0:1];
  wire [OUT-1:0] out[0:1];
  generate for(genvar r=0;r<2;r=r+1) begin: mode
    starlink_pss_spectrum_product_operand_register #(
      .DATA_WIDTH(D),.REGISTER_OPERANDS(r),.BOUNDARY_ROUND_SAT(B)) dut (
      .clk(clk),.resetn(resetn),.flush(flush),.input_valid(iv[r]),.input_ready(ir[r]),
      .input_i(ii[r]),.input_q(iq[r]),.kernel_i(ki[r]),.kernel_q(kq[r]),
      .input_bin_index(bin[r]),.input_block_exponent(exponent[r]),.input_last(last[r]),
      .input_block_start_index(start[r]),.output_valid(ov[r]),.output_ready(sink_ready),
      .output_i(oi[r]),.output_q(oq[r]),.output_bin_index(ob[r]),.output_block_exponent(oe[r]),
      .output_last(ol[r]),.output_block_start_index(os[r]),.output_overflow(of[r]),.overflow_pulse(pulse[r]));
    assign out[r]={oi[r],oq[r],ob[r],oe[r],ol[r],os[r],of[r]};
  end endgenerate
  wire gr,gv,go,gp,gl; wire signed [D-1:0] gi,gq;
  wire [8:0] gb; wire [4:0] ge; wire [63:0] gs;
  // Exact default-mode public behavior, including invalid payload retention.
  starlink_pss_spectrum_product #(.DATA_WIDTH(D),.BOUNDARY_ROUND_SAT(B)) golden (
    .clk(clk),.resetn(resetn),.flush(flush),.input_valid(iv[0]),.input_ready(gr),
    .input_i(ii[0]),.input_q(iq[0]),.kernel_i(ki[0]),.kernel_q(kq[0]),
    .input_bin_index(bin[0]),.input_block_exponent(exponent[0]),.input_last(last[0]),
    .input_block_start_index(start[0]),.output_valid(gv),.output_ready(sink_ready),
    .output_i(gi),.output_q(gq),.output_bin_index(gb),.output_block_exponent(ge),
    .output_last(gl),.output_block_start_index(gs),.output_overflow(go),.overflow_pulse(gp));
  reg [W-1:0] vectors[0:N-1];
  reg mv[0:1][0:3], mr[0:1][0:3];
  integer mid[0:1][0:3], age[0:1][0:3];
  integer row[0:1], cursor[0:1], accepted[0:1], emitted[0:1], discarded[0:1];
  integer simultaneous[0:1], stalls[0:1], pulses[0:1], saturated_reset[0:1], saturated_flush[0:1];
  integer latency_checks[0:1], occupancy, r,s,cycle,depth;
  reg previous_accept[0:1], expected_pulse[0:1], held[0:1];
  reg [OUT-1:0] held_out[0:1], expected_out;
  reg [31:0] rng=32'h15a01824;
  reg [1023:0] path;

  task automatic drive_payload(input integer channel);
    if(iv[channel])
      {ii[channel],iq[channel],ki[channel],kq[channel],bin[channel],exponent[channel],last[channel],start[channel]}
        = vectors[row[channel]][W-1:2*D+1];
    else begin
      ii[channel]='x; iq[channel]='z; ki[channel]='z; kq[channel]='x;
      bin[channel]='x; exponent[channel]='z; last[channel]=1'bx; start[channel]='z;
    end
  endtask

  initial begin
    if(!$value$plusargs("VECTORS=%s",path)) $fatal(1,"missing operand vectors");
    $readmemh(path,vectors);
    for(r=0;r<2;r=r+1) begin
      iv[r]=0; previous_accept[r]=0; cursor[r]=0; row[r]=0;
      accepted[r]=0; emitted[r]=0; discarded[r]=0; simultaneous[r]=0;
      stalls[r]=0; pulses[r]=0; saturated_reset[r]=0; saturated_flush[r]=0; latency_checks[r]=0;
      for(s=0;s<4;s=s+1) begin mv[r][s]=0; mid[r][s]=0; age[r][s]=0; end
    end
    repeat(2) @(negedge clk);
    for(cycle=0;cycle<5010;cycle=cycle+1) begin
      resetn=!(cycle==170 || cycle==212 || (cycle>=260 && cycle<5000 && cycle%997==0));
      flush=(cycle==190 || cycle==242 || (cycle>=260 && cycle<5000 && cycle%211==0));
      sink_ready=(cycle<128 || (cycle>=148 && cycle<168) || cycle>=5000 ||
                  (cycle>=260 && cycle%73>=23 && rng[0]));
      for(r=0;r<2;r=r+1) begin
        if(!iv[r] || previous_accept[r] || !resetn || flush) begin
          if(cycle<170) iv[r]=1;
          else if(cycle<260) iv[r]=(cycle==200 || cycle==230);
          else if(cycle<5000) iv[r]=rng[3:1]!=0;
          else iv[r]=0;
          row[r]=(cycle==200 || cycle==230) ? 0 : cursor[r]%N;
        end
        drive_payload(r);
      end
      rng={rng[30:0],rng[31]^rng[21]^rng[1]^rng[0]};
      #1;
      for(r=0;r<2;r=r+1) begin
        depth=3+r;
        mr[r][depth-1]=!mv[r][depth-1] || sink_ready;
        for(s=depth-2;s>=0;s=s-1) mr[r][s]=!mv[r][s] || mr[r][s+1];
        if(ir[r] !== (resetn && !flush && mr[r][0]))
          $fatal(1,"OPERAND_READY_MISMATCH mode=%0d cycle=%0d",r,cycle);
        held[r]=ov[r] && !sink_ready; held_out[r]=out[r];
      end
      @(posedge clk);
      for(r=0;r<2;r=r+1) begin
        depth=3+r; occupancy=0;
        for(s=0;s<depth;s=s+1) occupancy=occupancy+integer'(mv[r][s]);
        previous_accept[r]=iv[r] && ir[r]; expected_pulse[r]=0;
        if(!resetn || flush) begin
          if(cycle==212 && ov[r] && of[r] && ol[r]) saturated_reset[r]=saturated_reset[r]+1;
          if(cycle==242 && ov[r] && of[r] && ol[r]) saturated_flush[r]=saturated_flush[r]+1;
          discarded[r]=discarded[r]+occupancy;
          for(s=0;s<depth;s=s+1) mv[r][s]=0;
        end else begin
          if(ov[r] && sink_ready) emitted[r]=emitted[r]+1;
          if(ov[r] && !sink_ready) stalls[r]=stalls[r]+1;
          if(previous_accept[r] && mv[r][0] && mr[r][1]) simultaneous[r]=simultaneous[r]+1;
          expected_pulse[r]=mr[r][depth-1] && mv[r][depth-2] && vectors[mid[r][depth-2]][0];
          for(s=depth-1;s>0;s=s-1) if(mr[r][s]) begin
            mv[r][s]=mv[r][s-1]; mid[r][s]=mid[r][s-1]; age[r][s]=age[r][s-1];
          end
          if(mr[r][0]) begin mv[r][0]=iv[r]; mid[r][0]=row[r]; age[r][0]=cycle; end
          if(previous_accept[r]) begin accepted[r]=accepted[r]+1; cursor[r]=cursor[r]+1; end
        end
      end
      #0.001;
      if({ir[0],ov[0],out[0],pulse[0]} !== {gr,gv,gi,gq,gb,ge,gl,gs,go,gp})
        $fatal(1,"OPERAND_DEFAULT_PASSTHROUGH_MISMATCH cycle=%0d",cycle);
      for(r=0;r<2;r=r+1) begin
        depth=3+r; occupancy=0;
        for(s=0;s<depth;s=s+1) occupancy=occupancy+integer'(mv[r][s]);
        if(accepted[r] != emitted[r]+discarded[r]+occupancy)
          $fatal(1,"OPERAND_CONSERVATION_MISMATCH mode=%0d cycle=%0d",r,cycle);
        if(ov[r] !== mv[r][depth-1] || pulse[r] !== expected_pulse[r])
          $fatal(1,"OPERAND_VALID_PULSE_MISMATCH mode=%0d cycle=%0d",r,cycle);
        if(ov[r]) begin
          expected_out={vectors[mid[r][depth-1]][2*D:1],vectors[mid[r][depth-1]][2*D+79:2*D+1],vectors[mid[r][depth-1]][0]};
          if(out[r] !== expected_out)
            $fatal(1,"OPERAND_MATH_METADATA_MISMATCH mode=%0d cycle=%0d token=%0d",r,cycle,mid[r][depth-1]);
          if(cycle<128) begin
            if(cycle-age[r][depth-1] != 2+r) $fatal(1,"OPERAND_LATENCY_MISMATCH mode=%0d",r);
            latency_checks[r]=latency_checks[r]+1;
          end
        end
        if(held[r] && resetn && !flush && (!ov[r] || out[r] !== held_out[r]))
          $fatal(1,"OPERAND_STALL_HOLD_MISMATCH mode=%0d cycle=%0d",r,cycle);
        if(pulse[r]) pulses[r]=pulses[r]+1;
      end
      @(negedge clk);
    end
    for(r=0;r<2;r=r+1) begin
      if(ov[r] || accepted[r]!=emitted[r]+discarded[r] || accepted[r]<500 || emitted[r]<500 ||
         simultaneous[r]<100 || stalls[r]<100 || pulses[r]<10 || latency_checks[r]<100 ||
         saturated_reset[r]!=1 || saturated_flush[r]!=1)
        $fatal(1,"OPERAND_COVERAGE_MISSING mode=%0d a=%0d e=%0d d=%0d pulses=%0d reset=%0d flush=%0d",r,accepted[r],emitted[r],discarded[r],pulses[r],saturated_reset[r],saturated_flush[r]);
      $display("OPERAND_MODE_PASS width=%0d round=%0d registered=%0d no_stall_elapsed_clocks=%0d accepted=%0d emitted=%0d discarded=%0d simultaneous=%0d stalls=%0d pulses=%0d last_saturation_reset=1 last_saturation_flush=1 outstanding=0",
        D,B,r,2+r,accepted[r],emitted[r],discarded[r],simultaneous[r],stalls[r],pulses[r]);
    end
    $display("OPERAND_BOUNDARY_PASS cycles=5010 options=2 default_exact=1 registered_additional_latency=1 actual_FFT_physical=0");
    $finish;
  end
endmodule
