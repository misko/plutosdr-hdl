`timescale 1ns/1ps
module tb_direct_feeder;
  reg clk=0; always #2.5 clk=~clk;
  reg resetn=0, flush=0, sample_valid=0, sample_gap=0;
  reg signed [15:0] sample_i=0, sample_q=0;
  reg [63:0] sample_timestamp=0;
  reg config_valid=0; reg [2:0] config_bank=0;
  wire config_accepted, config_rejected, segment_fence, expiry_now, gap_now;
  wire identity_exhausted;
  wire output_valid; reg output_ready=1;
  wire signed [39:0] output_i, output_q;
  wire [63:0] output_timestamp; wire [31:0] output_identity;
  wire [31:0] accepted_samples, emitted_results, expiry_events, gap_events;
  starlink_pss_direct_feeder dut (.*);
  reg [191:0] coefficients [0:65];
  reg signed [15:0] hi [0:127], hq [0:127];
  reg [63:0] ht [0:127];
  reg signed [63:0] expected_i [0:1023], expected_q [0:1023];
  reg [63:0] expected_time [0:1023];
  reg [31:0] expected_identity [0:1023];
  integer segment_count=0, qw=0, qr=0, bank=0, generation=0;
  integer checked=0, received_since_reset=0, inputs_since_reset=0;
  integer k, idx, count, b, source_n=0, seed=666;
  integer fences=0, observed_expiry=0, observed_gap=0, collisions_checked=0;
  integer stalls_checked=0;
  reg allow_expiry=0, stream_done=0, was_stalled=0;
  reg [175:0] held;
  reg have_time=0; reg [63:0] next_time;
  reg [63:0] source_time=64'hffffffffffffffc0;
  reg expected_gap;
  reg signed [63:0] xi, xq, ci, cq, re, im;
  reg [191:0] group_word;
  function integer stride(input integer selected);
    stride = selected < 2 ? 1 : selected < 4 ? 2 : 4;
  endfunction
  always @(posedge clk) begin
    if (!resetn) begin
      segment_count=0; qw=0; qr=0; bank=0; generation=0;
      have_time=0; was_stalled=0;
      received_since_reset=0; inputs_since_reset=0;
    end else begin
      expected_gap = sample_gap || (!flush && !config_accepted && !identity_exhausted &&
        sample_valid && have_time && sample_timestamp != next_time);
      if (gap_now !== expected_gap) $fatal(1,"gap classification mismatch");
      if (expiry_now && !allow_expiry) $fatal(1,"unexpected expiry in supported stream");
      if (segment_fence !== (identity_exhausted || flush || config_accepted || expected_gap || expiry_now))
        $fatal(1,"unexpected fence");
      if (sample_valid && dut.read_enable) begin
        for (k=0; k<6; k=k+1)
          if (dut.write_address == ((dut.read_base + k) & 127))
            $fatal(1,"same-address history overwrite/read");
        collisions_checked=collisions_checked+1;
      end
      if (segment_fence) begin
        segment_count=0; qw=0; qr=0; have_time=0; was_stalled=0;
        if (!identity_exhausted) generation=generation+1;
        if (config_accepted) bank=config_bank;
        if (!identity_exhausted) fences=fences+1;
        if (expiry_now) observed_expiry=observed_expiry+1;
        if (gap_now) observed_gap=observed_gap+1;
        if (output_valid) $fatal(1,"stale output published on fence");
      end
      if (sample_valid) begin
        inputs_since_reset=inputs_since_reset+1;
        hi[segment_count & 127]=sample_i;
        hq[segment_count & 127]=sample_q;
        ht[segment_count & 127]=sample_timestamp;
        next_time=sample_timestamp+stride(bank); have_time=1;
        if (segment_count >= 65) begin
          re=0; im=0;
          for (k=0; k<66; k=k+1) begin
            idx=(segment_count-65+k)&127;
            xi=hi[idx]; xq=hq[idx];
            group_word=coefficients[bank*11+k/6];
            ci=$signed(group_word[(k%6)*32 +: 16]);
            cq=$signed(group_word[(k%6)*32+16 +: 16]);
            re=re+xi*ci+xq*cq; im=im+xq*ci-xi*cq;
          end
          if (qw-qr >= 1024) $fatal(1,"reference queue overflow");
          expected_i[qw&1023]=re; expected_q[qw&1023]=im;
          expected_time[qw&1023]=ht[(segment_count-65)&127];
          expected_identity[qw&1023]=(generation<<3)|bank;
          qw=qw+1;
        end
        segment_count=segment_count+1;
      end
      if (was_stalled && (!output_valid || {output_i,output_q,output_timestamp,output_identity} !== held))
        $fatal(1,"held output changed without a fence");
      if (output_valid && output_ready) begin
        if (qr>=qw) $fatal(1,"output without a complete input window");
        if ($signed(output_i) !== expected_i[qr&1023] ||
            $signed(output_q) !== expected_q[qr&1023] ||
            output_timestamp !== expected_time[qr&1023] ||
            output_identity !== expected_identity[qr&1023])
          $fatal(1,"result%0d mismatch bank%0d got%0d,%0d ts%h id%h expected%0d,%0d ts%h id%h",
            checked,bank,$signed(output_i),$signed(output_q),output_timestamp,output_identity,
            expected_i[qr&1023],expected_q[qr&1023],expected_time[qr&1023],expected_identity[qr&1023]);
        qr=qr+1; checked=checked+1; received_since_reset=received_since_reset+1;
      end
      was_stalled=output_valid&&!output_ready;
      if (was_stalled) stalls_checked=stalls_checked+1;
      held={output_i,output_q,output_timestamp,output_identity};
    end
  end
  task send_samples(input integer amount,input integer step);
    integer n;
    begin
      for(n=0;n<amount;n=n+1) begin
        // Consecutive source beats are separated by 13,13,14 service clocks.
        repeat(source_n%3==2 ? 13 : 12) @(negedge clk);
        sample_valid=1; sample_i=$random(seed); sample_q=$random(seed);
        sample_timestamp=source_time; source_time=source_time+step;
        source_n=source_n+1;
        @(negedge clk); sample_valid=0;
      end
    end
  endtask
  task set_bank(input integer selected);
    begin
      @(negedge clk); config_bank=selected; config_valid=1;
      @(negedge clk); config_valid=0;
    end
  endtask
  task drain;
    begin
      repeat(2000) @(negedge clk);
      if(qr!=qw) $fatal(1,"undrained reference queue %0d/%0d",qr,qw);
      if(accepted_samples!=inputs_since_reset || emitted_results!=received_since_reset)
        $fatal(1,"source acceptance or result count mismatch");
    end
  endtask
  initial begin
    $readmemh("direct_groups_q15.mem",coefficients);
    repeat(5) @(negedge clk); resetn=1;
    for(b=0;b<6;b=b+1) begin set_bank(b); send_samples(400,stride(b)); drain(); end
    set_bank(0); send_samples(66050,1); drain(); // wraps the 16-bit issue sequences
    fork
      begin send_samples(2200,1); stream_done=1; end
      begin
        while(!stream_done) begin
          repeat(1000) @(negedge clk); output_ready=0;
          repeat(100) @(negedge clk); output_ready=1;
        end
      end
    join
    drain();
    allow_expiry=1; output_ready=0; send_samples(400,1);
    output_ready=1; drain(); allow_expiry=0;
    if(observed_expiry==0) $fatal(1,"expiry control did not expire");
    send_samples(17,1);
    @(negedge clk); sample_gap=1;
    @(negedge clk); sample_gap=0;
    send_samples(200,1); drain();
    source_time=source_time+99; send_samples(200,1); drain();
    if(observed_gap!=2) $fatal(1,"gap controls not exercised exactly twice");
    output_ready=0; send_samples(30,1);
    #1; if(!output_valid) $fatal(1,"bank-fence test did not hold a result");
    // Atomic bank replacement while an old result is stalled; the coincident
    // new sample belongs to the acknowledged bank and seeds its new segment.
    @(negedge clk); config_valid=1; config_bank=3; sample_valid=1; sample_gap=1;
    sample_i=-32768; sample_q=32767; sample_timestamp=source_time;
    source_time=source_time+2;
    @(negedge clk); config_valid=0; sample_valid=0; sample_gap=0; output_ready=1;
    send_samples(200,2); drain();
    @(negedge clk); config_valid=1; config_bank=7;
    #1; if(!config_rejected || segment_fence) $fatal(1,"invalid bank was accepted");
    @(negedge clk); config_valid=0;
    send_samples(100,2); drain();
    output_ready=0; send_samples(30,2);
    #1; if(!output_valid) $fatal(1,"reset test did not hold a result");
    @(negedge clk); resetn=0;
    @(negedge clk); resetn=1; output_ready=1;
    send_samples(200,1); drain();
    send_samples(15,1);
    @(negedge clk); flush=1; sample_gap=1;
    @(negedge clk); flush=0; sample_gap=0;
    send_samples(200,1); drain();
    if(observed_gap!=4 || gap_events!=1) $fatal(1,"coincident gaps were not retained across local fences");
    // Reach the otherwise impractically distant identity rail explicitly.
    @(negedge clk); force dut.generation=29'h1fffffff; flush=1;
    @(negedge clk); flush=0; release dut.generation;
    #1; if(!identity_exhausted) $fatal(1,"identity exhaustion was not sticky");
    send_samples(200,1);
    #1; if(output_valid || !identity_exhausted) $fatal(1,"identity alias published");
    @(negedge clk); config_valid=1; config_bank=1;
    #1; if(!config_rejected) $fatal(1,"exhausted identity accepted a config");
    @(negedge clk); config_valid=0; resetn=0;
    @(negedge clk); resetn=1;
    send_samples(100,1); drain();
    if(stalls_checked==0 || collisions_checked==0) $fatal(1,"missing stall/port coverage");
    $display("DIRECT_FEEDER_PASS results=%0d inputs=%0d fences=%0d expiries=%0d gaps=%0d stalled_cycles=%0d concurrent_port_checks=%0d",
      checked,source_n+1,fences,observed_expiry,observed_gap,stalls_checked,collisions_checked);
    $finish;
  end
  initial begin #20000000; $fatal(1,"timeout"); end
endmodule
