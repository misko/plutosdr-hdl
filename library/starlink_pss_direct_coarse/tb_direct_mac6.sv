`timescale 1ns/1ps
module tb_direct_mac6;
  reg clk = 0;
  always #2.5 clk = ~clk;
  reg resetn = 0, flush = 0, input_valid = 0;
  wire input_ready;
  reg input_first = 0, input_last = 0;
  reg [95:0] input_i = 0, input_q = 0, coefficient_i = 0, coefficient_q = 0;
  reg [63:0] input_timestamp = 0;
  reg [31:0] input_epoch = 0;
  wire output_valid;
  reg output_ready = 1;
  wire signed [39:0] output_i, output_q;
  wire [63:0] output_timestamp;
  wire [31:0] output_epoch;
  starlink_pss_direct_mac6 dut (.*);
  reg signed [63:0] expected_i [0:255], expected_q [0:255];
  reg [63:0] expected_timestamp [0:255];
  reg [31:0] expected_epoch [0:255];
  integer sent = 0, received = 0, cycle = 0, last_cycle = 0;
  integer cadence_checks = 0, stall_checks = 0;
  reg check_cadence = 0, stalled = 0;
  reg [175:0] held;
  reg signed [63:0] a, b, c, d, sum_i, sum_q;
  integer k, l, job, seed = 66;
  always @(posedge clk) begin
    cycle = cycle + 1;
    if (resetn && !flush) begin
      if (stalled && (!output_valid || {output_i, output_q, output_timestamp, output_epoch} !== held))
        $fatal(1, "stalled output changed");
      if (output_valid && output_ready) begin
        if (received >= sent) $fatal(1, "unexpected output");
        if ($signed(output_i) !== expected_i[received] ||
            $signed(output_q) !== expected_q[received] ||
            output_timestamp !== expected_timestamp[received] ||
            output_epoch !== expected_epoch[received])
          $fatal(1, "job %0d got %0d,%0d expected %0d,%0d", received,
                 $signed(output_i), $signed(output_q), expected_i[received], expected_q[received]);
        if (check_cadence && last_cycle != 0) begin
          if (cycle - last_cycle != 11) $fatal(1, "cadence %0d", cycle-last_cycle);
          cadence_checks = cadence_checks + 1;
        end
        last_cycle = cycle;
        received = received + 1;
      end
      stalled = output_valid && !output_ready;
      if (stalled) stall_checks = stall_checks + 1;
      held = {output_i, output_q, output_timestamp, output_epoch};
    end else begin
      stalled = 0;
    end
  end
  task send_job(input integer number, input integer beats);
    begin
      sum_i = 0; sum_q = 0;
      for (k=0; k<beats; k=k+1) begin
        @(negedge clk);
        input_valid = 1; input_first = k == 0; input_last = k == 10;
        input_timestamp = 64'hfffffffffffffff0 + number;
        input_epoch = number / 17;
        for (l=0; l<6; l=l+1) begin
          a = $signed($random(seed) & 16'hffff);
          b = $signed($random(seed) & 16'hffff);
          c = $signed($random(seed) & 16'hffff);
          d = $signed($random(seed) & 16'hffff);
          // Explicit 16-bit signed endpoints and wrap to signed CI16.
          a = $signed(a[15:0]); b = $signed(b[15:0]);
          c = $signed(c[15:0]); d = $signed(d[15:0]);
          if (number == 0) begin a=-32768; b=-32768; c=-32768; d=-32768; end
          if (number == 1) begin a=32767; b=-32768; c=-32768; d=32767; end
          if (number == 2) begin a=0; b=0; end
          input_i[l*16 +: 16] = a[15:0]; input_q[l*16 +: 16] = b[15:0];
          coefficient_i[l*16 +: 16] = c[15:0]; coefficient_q[l*16 +: 16] = d[15:0];
          // Independent four-product oracle; DUT uses three products.
          sum_i = sum_i + a*c + b*d;
          sum_q = sum_q + b*c - a*d;
        end
        @(posedge clk);
        while (!input_ready) @(posedge clk);
        if (number >= 104 && k % 3 == 0) begin
          @(negedge clk); input_valid = 0;
          @(posedge clk);
        end
      end
      if (beats == 11) begin
        expected_i[sent] = sum_i; expected_q[sent] = sum_q;
        expected_timestamp[sent] = input_timestamp;
        expected_epoch[sent] = input_epoch;
        sent = sent + 1;
      end
    end
  endtask
  task drain;
    begin
      @(negedge clk); input_valid = 0;
      wait(received == sent);
      repeat(12) @(negedge clk);
    end
  endtask
  initial begin
    repeat(4) @(negedge clk); resetn = 1;
    check_cadence = 1;
    for (job=0; job<50; job=job+1) send_job(job, 11);
    drain(); check_cadence = 0;
    fork
      begin
        for (job=50; job<100; job=job+1) send_job(job, 11);
        drain();
      end
      begin
        repeat(35) begin
          repeat(9) @(negedge clk); output_ready=0;
          repeat(7) @(negedge clk); output_ready=1;
        end
      end
    join
    send_job(100, 5);
    @(negedge clk); input_valid=0; flush=1;
    @(negedge clk); flush=0;
    repeat(12) @(negedge clk);
    send_job(101,11); drain();
    send_job(102,7);
    @(negedge clk); input_valid=0; resetn=0;
    @(negedge clk); resetn=1;
    repeat(12) @(negedge clk);
    send_job(103,11); drain();
    for (job=104; job<120; job=job+1) send_job(job, 11);
    drain();
    // Flush an already completed but unconsumed tuple as a hop fence must.
    output_ready=0;
    send_job(120,11);
    @(negedge clk); input_valid=0;
    wait(output_valid);
    @(negedge clk); flush=1; sent=sent-1;
    @(negedge clk); flush=0; output_ready=1;
    repeat(12) @(negedge clk);
    send_job(121,11); drain();
    if (received != 119 || cadence_checks != 49 || stall_checks == 0)
      $fatal(1, "coverage failed");
    $display("DIRECT_MAC6_PASS jobs=%0d cadence_checks=%0d stall_checks=%0d aborts=3", received, cadence_checks, stall_checks);
    $finish;
  end
  initial begin #200000; $fatal(1, "timeout"); end
endmodule
