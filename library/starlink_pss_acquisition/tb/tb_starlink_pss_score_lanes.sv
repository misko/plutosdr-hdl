`timescale 1ns/1ps

module tb_starlink_pss_score_lanes;

  localparam integer STREAM_ITEMS = 1500;

  reg clk = 1'b0;
  reg resetn = 1'b0;
  reg flush = 1'b0;
  reg input_valid = 1'b0;
  reg [68:0] input_numerator = 0;
  reg [68:0] input_denominator = 0;
  reg [63:0] input_start_index = 0;
  reg output_ready = 1'b0;
  reg randomize_ready = 1'b0;
  reg monitor_outputs = 1'b0;

  wire input_ready;
  wire output_valid;
  wire [7:0] output_score;
  wire [63:0] output_start_index;
  wire output_denominator_zero;
  wire accepted_pulse;
  wire emitted_pulse;
  wire lane_zero_busy;
  wire lane_one_busy;
  wire next_input_lane;
  wire next_output_lane;

  integer cycle_count = 0;
  integer input_count = 0;
  integer output_count = 0;
  integer zero_denominator_count = 0;
  integer timeout;
  integer ordinal;
  reg [63:0] expected_next_index = 0;
  reg stalled_last_cycle = 1'b0;
  reg [72:0] stalled_payload;
  reg saw_input_backpressure = 1'b0;
  reg saw_output_stall = 1'b0;
  reg saw_lane_zero_busy = 1'b0;
  reg saw_lane_one_busy = 1'b0;

  always #5 clk = ~clk;

  starlink_pss_score_lanes dut (
    .clk                     (clk),
    .resetn                  (resetn),
    .flush                   (flush),
    .input_valid             (input_valid),
    .input_ready             (input_ready),
    .input_numerator         (input_numerator),
    .input_denominator       (input_denominator),
    .input_start_index       (input_start_index),
    .output_valid            (output_valid),
    .output_ready            (output_ready),
    .output_score            (output_score),
    .output_start_index      (output_start_index),
    .output_denominator_zero (output_denominator_zero),
    .accepted_pulse          (accepted_pulse),
    .emitted_pulse           (emitted_pulse),
    .lane_zero_busy          (lane_zero_busy),
    .lane_one_busy           (lane_one_busy),
    .next_input_lane         (next_input_lane),
    .next_output_lane        (next_output_lane)
  );

  function automatic [7:0] expected_score(input [63:0] index);
    integer item;
    begin
      item = index % 1000000;
      if ((item % 257) == 0)
        expected_score = 0;
      else
        expected_score = item % 256;
    end
  endfunction

  function automatic expected_zero(input [63:0] index);
    integer item;
    begin
      item = index % 1000000;
      expected_zero = (item % 257) == 0;
    end
  endfunction

  task automatic fail(input string message);
    begin
      $display("SCORE_LANES_FAIL %0s cycle=%0d inputs=%0d outputs=%0d inlane=%b outlane=%b",
               message, cycle_count, input_count, output_count,
               next_input_lane, next_output_lane);
      $fatal(1);
    end
  endtask

  task automatic send_one(input integer item, input [63:0] base_index);
    begin
      @(negedge clk);
      input_numerator = item % 256;
      input_denominator = ((item % 257) == 0) ? 0 : 255;
      input_start_index = base_index + item;
      input_valid = 1'b1;
      begin : wait_for_accept
        forever begin
          @(posedge clk);
          if (input_ready)
            disable wait_for_accept;
        end
      end
      @(negedge clk);
      input_valid = 1'b0;
    end
  endtask

  task automatic pulse_flush;
    begin
      @(negedge clk);
      input_valid = 1'b0;
      flush = 1'b1;
      @(negedge clk);
      flush = 1'b0;
      #1;
    end
  endtask

  always @(negedge clk) begin
    if (randomize_ready)
      output_ready = (cycle_count % 19) < 12;
  end

  always @(posedge clk) begin
    cycle_count <= cycle_count + 1;
    if (cycle_count > 30000)
      fail("simulation watchdog expired");

    if (resetn && input_valid && !input_ready)
      saw_input_backpressure <= 1'b1;
    if (resetn && output_valid && !output_ready)
      saw_output_stall <= 1'b1;
    if (lane_zero_busy)
      saw_lane_zero_busy <= 1'b1;
    if (lane_one_busy)
      saw_lane_one_busy <= 1'b1;
    if (input_valid && input_ready)
      input_count <= input_count + 1;

    if (resetn && monitor_outputs && stalled_last_cycle) begin
      if (!output_valid ||
          {output_denominator_zero, output_start_index, output_score} !==
          stalled_payload)
        fail("selected output changed while stalled");
    end
    stalled_last_cycle <= resetn && monitor_outputs &&
                          output_valid && !output_ready;
    if (output_valid && !output_ready)
      stalled_payload <= {
        output_denominator_zero, output_start_index, output_score
      };

    if (resetn && monitor_outputs && output_valid && output_ready) begin
      if (output_start_index !== expected_next_index)
        fail("two-lane output ordering mismatch");
      if (output_score !== expected_score(output_start_index) ||
          output_denominator_zero !== expected_zero(output_start_index))
        fail("two-lane score or zero-denominator metadata mismatch");
      if (output_denominator_zero)
        zero_denominator_count <= zero_denominator_count + 1;
      expected_next_index <= expected_next_index + 1'b1;
      output_count <= output_count + 1;
    end
  end

  initial begin
    $dumpfile("build/tb_starlink_pss_score_lanes.vcd");
    $dumpvars(0, tb_starlink_pss_score_lanes);

    repeat (3) @(negedge clk);
    resetn = 1'b1;
    expected_next_index = 64'd1000000;
    monitor_outputs = 1'b1;
    randomize_ready = 1'b1;

    for (ordinal = 0; ordinal < STREAM_ITEMS; ordinal = ordinal + 1)
      send_one(ordinal, 64'd1000000);

    timeout = 0;
    while (output_count < STREAM_ITEMS && timeout < 2000) begin
      @(negedge clk);
      timeout = timeout + 1;
    end
    randomize_ready = 1'b0;
    output_ready = 1'b1;
    repeat (3) @(negedge clk);
    if (input_count != STREAM_ITEMS || output_count != STREAM_ITEMS)
      fail("two-lane stream did not drain exactly");
    if (zero_denominator_count != 6)
      fail("zero-denominator count mismatch");
    if (!saw_input_backpressure || !saw_output_stall ||
        !saw_lane_zero_busy || !saw_lane_one_busy)
      fail("test did not exercise both lanes and both backpressure paths");

    // Flush two operations while both lanes are active. Nothing may escape,
    // and both ordering toggles must restart at lane zero.
    monitor_outputs = 1'b0;
    send_one(31, 64'd2000000);
    send_one(32, 64'd2000000);
    if (!lane_zero_busy || !lane_one_busy)
      fail("pre-flush test did not occupy both lanes");
    pulse_flush();
    if (lane_zero_busy || lane_one_busy || output_valid ||
        next_input_lane || next_output_lane)
      fail("flush did not clear lanes and ordering state");
    repeat (12) @(negedge clk);
    if (output_valid)
      fail("pre-flush operation escaped after flush");

    // Restart proves input and output lane phase are both deterministic.
    expected_next_index = 64'd3000000;
    output_count = 0;
    monitor_outputs = 1'b1;
    for (ordinal = 0; ordinal < 16; ordinal = ordinal + 1)
      send_one(ordinal, 64'd3000000);
    timeout = 0;
    while (output_count < 16 && timeout < 200) begin
      @(negedge clk);
      timeout = timeout + 1;
    end
    repeat (3) @(negedge clk);
    if (output_count != 16)
      fail("post-flush sequence did not drain exactly");

    $display("SCORE_LANES_PASS stream=1500 lanes=2 ordered=1 output_stalls=1 exact_scores=1 zero_denominator=6 flush_restart=1");
    $finish;
  end

endmodule
