`timescale 1ns/1ps

module tb_starlink_pss_event_cdc;

  reg          adc_clk = 1'b0;
  reg          adc_reset = 1'b1;
  reg          candidate_valid = 1'b0;
  reg [63:0]   candidate_sample_index = 64'd0;
  reg [82:0]   candidate_metric_num = 83'd0;
  reg [81:0]   candidate_metric_den = 82'd0;

  reg          cpu_clk = 1'b0;
  reg          cpu_resetn = 1'b0;
  wire [31:0]  snapshot_generation;
  wire [63:0]  snapshot_event_count;
  wire [63:0]  snapshot_sample_index;
  wire [82:0]  snapshot_metric_num;
  wire [81:0]  snapshot_metric_den;

  integer n;
  reg [31:0] first_generation;

  always #2 adc_clk = ~adc_clk;
  always #11 cpu_clk = ~cpu_clk;

  starlink_pss_event_cdc dut (
    .adc_clk(adc_clk),
    .adc_reset(adc_reset),
    .candidate_valid(candidate_valid),
    .candidate_sample_index(candidate_sample_index),
    .candidate_metric_num(candidate_metric_num),
    .candidate_metric_den(candidate_metric_den),
    .cpu_clk(cpu_clk),
    .cpu_resetn(cpu_resetn),
    .snapshot_generation(snapshot_generation),
    .snapshot_event_count(snapshot_event_count),
    .snapshot_sample_index(snapshot_sample_index),
    .snapshot_metric_num(snapshot_metric_num),
    .snapshot_metric_den(snapshot_metric_den)
  );

  task automatic pulse_event;
    input [63:0] sample_index;
    input [82:0] metric_num;
    input [81:0] metric_den;
    begin
      @(negedge adc_clk);
      candidate_sample_index = sample_index;
      candidate_metric_num = metric_num;
      candidate_metric_den = metric_den;
      candidate_valid = 1'b1;
      @(negedge adc_clk);
      candidate_valid = 1'b0;
    end
  endtask

  initial begin
    repeat (4) @(posedge adc_clk);
    repeat (2) @(posedge cpu_clk);
    @(negedge adc_clk);
    adc_reset = 1'b0;
    @(negedge cpu_clk);
    cpu_resetn = 1'b1;

    // Five events arrive faster than one round-trip handshake.  Snapshot
    // generations may coalesce, but the count and newest 83/82-bit payload
    // must be exact.
    for (n = 0; n < 5; n = n + 1)
      pulse_event(64'd1000 + n,
                  {19'h50000 + n, 64'h1234_5678_9abc_def0 + n},
                  {18'h20000 + n, 64'h0fed_cba9_8765_4321 + n});

    repeat (20) @(posedge cpu_clk);
    if (snapshot_generation == 0)
      $fatal(1, "CDC did not publish burst");
    if (snapshot_event_count != 64'd5)
      $fatal(1, "coalesced event count mismatch: %0d", snapshot_event_count);
    if (snapshot_sample_index != 64'd1004)
      $fatal(1, "coalesced latest index mismatch");
    if (snapshot_metric_num !=
        {19'h50004, 64'h1234_5678_9abc_def4})
      $fatal(1, "coalesced 83-bit numerator mismatch");
    if (snapshot_metric_den !=
        {18'h20004, 64'h0fed_cba9_8765_4325})
      $fatal(1, "coalesced 82-bit denominator mismatch");

    first_generation = snapshot_generation;
    pulse_event(64'd2000,
                {19'h6abcd, 64'hffff_0000_aaaa_5555},
                {18'h3abcd, 64'h1111_2222_3333_4444});
    repeat (12) @(posedge cpu_clk);
    if (snapshot_generation <= first_generation)
      $fatal(1, "idle mailbox did not publish another generation");
    if (snapshot_event_count != 64'd6 ||
        snapshot_sample_index != 64'd2000 ||
        snapshot_metric_num != {19'h6abcd, 64'hffff_0000_aaaa_5555} ||
        snapshot_metric_den != {18'h3abcd, 64'h1111_2222_3333_4444})
      $fatal(1, "second CDC snapshot mismatch");

    $display("PASS starlink_pss_event_cdc coalescing/accounting");
    $finish;
  end

endmodule
