`timescale 1ns/1ps

module tb_starlink_pss_raw_result_fifo;

  localparam integer FIFO_DEPTH = 512;
  localparam integer MAX_EXPECTED = 4096;

  reg clk = 1'b0;
  reg resetn = 1'b0;
  reg flush = 1'b0;
  reg input_valid = 1'b0;
  reg signed [23:0] input_correlation_i = 0;
  reg signed [23:0] input_correlation_q = 0;
  reg [4:0] input_forward_exponent = 0;
  reg [4:0] input_inverse_exponent = 0;
  reg [63:0] input_start_index = 0;
  reg input_block_last = 1'b0;
  reg output_ready = 1'b0;

  wire input_ready;
  wire output_valid;
  wire signed [23:0] output_correlation_i;
  wire signed [23:0] output_correlation_q;
  wire [4:0] output_forward_exponent;
  wire [4:0] output_inverse_exponent;
  wire [63:0] output_start_index;
  wire output_block_last;
  wire [9:0] stored_count;
  wire [9:0] maximum_stored_count;
  wire accepted_pulse;
  wire emitted_pulse;
  wire overflow_pulse;

  reg [23:0] expected_i [0:MAX_EXPECTED-1];
  reg [23:0] expected_q [0:MAX_EXPECTED-1];
  reg [4:0] expected_forward [0:MAX_EXPECTED-1];
  reg [4:0] expected_inverse [0:MAX_EXPECTED-1];
  reg [63:0] expected_index [0:MAX_EXPECTED-1];
  reg expected_last [0:MAX_EXPECTED-1];

  integer accepted_count = 0;
  integer emitted_count = 0;
  integer accepted_pulses = 0;
  integer emitted_pulses = 0;
  integer overflow_pulses = 0;
  integer cycle_count = 0;
  integer drive_ordinal = 0;
  integer timeout = 0;
  reg scoreboard_enabled = 1'b0;
  reg input_backpressure_observed = 1'b0;
  reg simultaneous_io_observed = 1'b0;
  reg stalled_last_cycle = 1'b0;
  reg [122:0] stalled_payload;

  always #5 clk = ~clk;

  starlink_pss_raw_result_fifo dut (
    .clk                     (clk),
    .resetn                  (resetn),
    .flush                   (flush),
    .input_valid             (input_valid),
    .input_ready             (input_ready),
    .input_correlation_i     (input_correlation_i),
    .input_correlation_q     (input_correlation_q),
    .input_forward_exponent  (input_forward_exponent),
    .input_inverse_exponent  (input_inverse_exponent),
    .input_start_index       (input_start_index),
    .input_block_last        (input_block_last),
    .output_valid            (output_valid),
    .output_ready            (output_ready),
    .output_correlation_i    (output_correlation_i),
    .output_correlation_q    (output_correlation_q),
    .output_forward_exponent (output_forward_exponent),
    .output_inverse_exponent (output_inverse_exponent),
    .output_start_index      (output_start_index),
    .output_block_last       (output_block_last),
    .stored_count            (stored_count),
    .maximum_stored_count    (maximum_stored_count),
    .accepted_pulse          (accepted_pulse),
    .emitted_pulse           (emitted_pulse),
    .overflow_pulse          (overflow_pulse)
  );

  task automatic fail(input string message);
    begin
      $display("RAW_FIFO_FAIL %0s accepted=%0d emitted=%0d stored=%0d cycle=%0d",
               message, accepted_count, emitted_count, stored_count,
               cycle_count);
      $fatal(1);
    end
  endtask

  task automatic drive_value(input integer ordinal, input last_value);
    begin
      input_correlation_i = (ordinal * 7919 + 17) & 24'hffffff;
      input_correlation_q = (ordinal * 104729 + 23) & 24'hffffff;
      input_forward_exponent = ordinal % 32;
      input_inverse_exponent = (ordinal * 7 + 3) % 32;
      input_start_index = 64'd900000 + ordinal;
      input_block_last = last_value;
    end
  endtask

  task automatic clear_scoreboard;
    begin
      scoreboard_enabled = 1'b0;
      accepted_count = 0;
      emitted_count = 0;
      accepted_pulses = 0;
      emitted_pulses = 0;
      overflow_pulses = 0;
      input_backpressure_observed = 1'b0;
      simultaneous_io_observed = 1'b0;
      stalled_last_cycle = 1'b0;
      @(negedge clk);
      scoreboard_enabled = 1'b1;
    end
  endtask

  always @(posedge clk) begin
    cycle_count <= cycle_count + 1;

    if (resetn && scoreboard_enabled && input_valid && !input_ready)
      input_backpressure_observed <= 1'b1;
    if (resetn && scoreboard_enabled && input_valid && input_ready) begin
      if (accepted_count >= MAX_EXPECTED)
        fail("scoreboard input capacity exceeded");
      expected_i[accepted_count] <= input_correlation_i;
      expected_q[accepted_count] <= input_correlation_q;
      expected_forward[accepted_count] <= input_forward_exponent;
      expected_inverse[accepted_count] <= input_inverse_exponent;
      expected_index[accepted_count] <= input_start_index;
      expected_last[accepted_count] <= input_block_last;
      accepted_count <= accepted_count + 1;
    end
    if (resetn && scoreboard_enabled && accepted_pulse)
      accepted_pulses <= accepted_pulses + 1;
    if (resetn && scoreboard_enabled && emitted_pulse)
      emitted_pulses <= emitted_pulses + 1;
    if (resetn && scoreboard_enabled && overflow_pulse)
      overflow_pulses <= overflow_pulses + 1;
    if (resetn && scoreboard_enabled && input_valid && input_ready &&
        output_valid && output_ready)
      simultaneous_io_observed <= 1'b1;

    if (resetn && scoreboard_enabled && stalled_last_cycle) begin
      if (!output_valid ||
          {output_block_last, output_start_index,
           output_inverse_exponent, output_forward_exponent,
           output_correlation_q, output_correlation_i} !== stalled_payload)
        fail("output payload changed while stalled");
    end
    stalled_last_cycle <= resetn && scoreboard_enabled &&
                          output_valid && !output_ready;
    if (output_valid && !output_ready)
      stalled_payload <= {
        output_block_last, output_start_index,
        output_inverse_exponent, output_forward_exponent,
        output_correlation_q, output_correlation_i
      };

    if (resetn && scoreboard_enabled && output_valid && output_ready) begin
      if (emitted_count >= accepted_count)
        fail("output had no accepted scoreboard item");
      if (output_correlation_i !== expected_i[emitted_count] ||
          output_correlation_q !== expected_q[emitted_count] ||
          output_forward_exponent !== expected_forward[emitted_count] ||
          output_inverse_exponent !== expected_inverse[emitted_count] ||
          output_start_index !== expected_index[emitted_count] ||
          output_block_last !== expected_last[emitted_count])
        fail("FIFO ordering or payload mismatch");
      emitted_count <= emitted_count + 1;
    end
  end

  initial begin
    $dumpfile("build/tb_starlink_pss_raw_result_fifo.vcd");
    $dumpvars(0, tb_starlink_pss_raw_result_fifo);

    repeat (3) @(negedge clk);
    resetn = 1'b1;
    clear_scoreboard();

    // One complete valid overlap-save burst must fit while fully stalled.
    output_ready = 1'b0;
    for (drive_ordinal = 0; drive_ordinal < 447;
         drive_ordinal = drive_ordinal + 1) begin
      if (!input_ready)
        fail("447-result burst experienced input backpressure");
      drive_value(drive_ordinal, drive_ordinal == 446);
      input_valid = 1'b1;
      @(negedge clk);
    end
    input_valid = 1'b0;
    repeat (2) @(negedge clk);
    if (stored_count != 447 || maximum_stored_count != 447)
      fail("complete-burst occupancy mismatch");

    output_ready = 1'b1;
    timeout = 0;
    while (emitted_count < 447 && timeout < 1000) begin
      @(negedge clk);
      output_ready = (cycle_count % 11) != 0;
      timeout = timeout + 1;
    end
    output_ready = 1'b1;
    repeat (3) @(negedge clk);
    if (emitted_count != 447 || stored_count != 0)
      fail("complete burst did not drain exactly");
    if (accepted_pulses != 447 || emitted_pulses != 447)
      fail("complete-burst pulse accounting mismatch");

    // Sustained concurrent traffic proves simultaneous read/write ordering.
    flush = 1'b1;
    @(negedge clk);
    flush = 1'b0;
    clear_scoreboard();
    output_ready = 1'b1;
    drive_ordinal = 1000;
    timeout = 0;
    while ((accepted_count < 1200 || emitted_count < 1200) &&
           timeout < 5000) begin
      @(negedge clk);
      output_ready = (cycle_count % 17) < 12;
      if (accepted_count < 1200) begin
        input_valid = 1'b1;
        drive_value(drive_ordinal, (accepted_count % 447) == 446);
        if (input_ready)
          drive_ordinal = drive_ordinal + 1;
      end else begin
        input_valid = 1'b0;
      end
      timeout = timeout + 1;
    end
    input_valid = 1'b0;
    output_ready = 1'b1;
    repeat (4) @(negedge clk);
    if (accepted_count != 1200 || emitted_count != 1200 || stored_count != 0)
      fail("concurrent stream did not drain exactly");
    if (!simultaneous_io_observed)
      fail("test did not exercise simultaneous input/output");

    // Fill the declared total capacity and prove the next item faults.
    flush = 1'b1;
    @(negedge clk);
    flush = 1'b0;
    clear_scoreboard();
    output_ready = 1'b0;
    for (drive_ordinal = 3000; drive_ordinal < 3000 + FIFO_DEPTH;
         drive_ordinal = drive_ordinal + 1) begin
      if (!input_ready)
        fail("FIFO refused an item below declared capacity");
      drive_value(drive_ordinal, 1'b0);
      input_valid = 1'b1;
      @(negedge clk);
    end
    if (stored_count != FIFO_DEPTH || input_ready)
      fail("full-capacity ready/count mismatch");
    drive_value(4000, 1'b1);
    input_valid = 1'b1;
    @(negedge clk);
    input_valid = 1'b0;
    @(negedge clk);
    if (overflow_pulses != 1 || stored_count != FIFO_DEPTH)
      fail("overflow was not reported without state mutation");

    flush = 1'b1;
    @(negedge clk);
    flush = 1'b0;
    scoreboard_enabled = 1'b0;
    if (stored_count != 0 || output_valid)
      fail("flush did not invalidate full FIFO");

    $display("RAW_FIFO_PASS depth=512 burst=447 concurrent=1200 exact_payload=1 backpressure=1 overflow=1 flush=1");
    $finish;
  end

endmodule
