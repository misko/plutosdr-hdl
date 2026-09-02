`timescale 1ns/1ps

module tb_starlink_pss_energy_cache;

  localparam integer WINDOW_SAMPLES = 66;
  localparam integer CACHE_ENTRIES = 2048;
  localparam integer FIRST_SEGMENT_SAMPLES = 2500;
  localparam [63:0] FIRST_BASE = 64'd32768;
  localparam [63:0] SECOND_BASE = 64'd100000;
  localparam [63:0] THIRD_BASE = 64'd200000;

  reg clk = 1'b0;
  reg resetn = 1'b0;
  reg enable = 1'b0;
  reg flush = 1'b0;
  reg sample_valid = 1'b0;
  reg sample_gap = 1'b0;
  reg signed [15:0] sample_i = 0;
  reg signed [15:0] sample_q = 0;
  reg [63:0] sample_index = 0;
  reg lookup_valid = 1'b0;
  reg [63:0] lookup_start_index = 0;
  reg output_ready = 1'b0;

  wire lookup_ready;
  wire output_valid;
  wire [37:0] output_energy;
  wire [63:0] output_start_index;
  wire output_found;
  wire energy_write_pulse;
  wire [37:0] energy_write_value;
  wire [63:0] energy_write_start_index;
  wire gap_pulse;
  wire index_error_pulse;
  wire restart_pulse;
  wire retention_miss_pulse;
  wire [11:0] stored_energy_count;
  wire [63:0] oldest_energy_start_index;
  wire [63:0] newest_energy_start_index;

  integer cycle_count = 0;
  integer observed_energy_count = 0;
  integer expected_segment_energy_count = 0;
  integer gap_pulses = 0;
  integer index_error_pulses = 0;
  integer restart_pulses = 0;
  integer retention_miss_pulses = 0;
  integer sample_number;
  integer timeout;
  reg [63:0] expected_segment_base = FIRST_BASE;
  reg stalled_last_cycle = 1'b0;
  reg [37:0] stalled_energy;
  reg [63:0] stalled_start_index;
  reg stalled_found;

  always #5 clk = ~clk;

  starlink_pss_energy_cache dut (
    .clk                       (clk),
    .resetn                    (resetn),
    .enable                    (enable),
    .flush                     (flush),
    .sample_valid              (sample_valid),
    .sample_gap                (sample_gap),
    .sample_i                  (sample_i),
    .sample_q                  (sample_q),
    .sample_index              (sample_index),
    .lookup_valid              (lookup_valid),
    .lookup_ready              (lookup_ready),
    .lookup_start_index        (lookup_start_index),
    .output_valid              (output_valid),
    .output_ready              (output_ready),
    .output_energy             (output_energy),
    .output_start_index        (output_start_index),
    .output_found              (output_found),
    .energy_write_pulse        (energy_write_pulse),
    .energy_write_value        (energy_write_value),
    .energy_write_start_index  (energy_write_start_index),
    .gap_pulse                 (gap_pulse),
    .index_error_pulse         (index_error_pulse),
    .restart_pulse             (restart_pulse),
    .retention_miss_pulse      (retention_miss_pulse),
    .stored_energy_count       (stored_energy_count),
    .oldest_energy_start_index (oldest_energy_start_index),
    .newest_energy_start_index (newest_energy_start_index)
  );

  task automatic fail(input string message);
    begin
      $display("ENERGY_CACHE_FAIL %0s cycle=%0d writes=%0d",
               message, cycle_count, observed_energy_count);
      $fatal(1);
    end
  endtask

  function automatic signed [15:0] encoded_i(input [63:0] index);
    encoded_i = index[15:0];
  endfunction

  function automatic signed [15:0] encoded_q(input [63:0] index);
    encoded_q = ~index[15:0];
  endfunction

  function automatic [31:0] encoded_power(input [63:0] index);
    reg signed [15:0] value_i;
    reg signed [15:0] value_q;
    reg signed [31:0] product_i;
    reg signed [31:0] product_q;
    begin
      value_i = encoded_i(index);
      value_q = encoded_q(index);
      product_i = value_i * value_i;
      product_q = value_q * value_q;
      encoded_power = product_i + product_q;
    end
  endfunction

  function automatic [37:0] expected_energy(input [63:0] start_index);
    integer offset;
    reg [63:0] accumulator;
    begin
      accumulator = 0;
      for (offset = 0; offset < WINDOW_SAMPLES; offset = offset + 1)
        accumulator = accumulator + encoded_power(start_index + offset);
      expected_energy = accumulator[37:0];
    end
  endfunction

  task automatic send_sample(
    input [63:0] index,
    input gap,
    input integer idle_cycles
  );
    begin
      @(negedge clk);
      sample_index = index;
      sample_i = encoded_i(index);
      sample_q = encoded_q(index);
      sample_gap = gap;
      sample_valid = 1'b1;
      @(negedge clk);
      sample_valid = 1'b0;
      sample_gap = 1'b0;
      repeat (idle_cycles) @(negedge clk);
    end
  endtask

  task automatic check_lookup(
    input [63:0] index,
    input expected_found,
    input stall_response
  );
    begin
      @(negedge clk);
      output_ready = !stall_response;
      lookup_start_index = index;
      lookup_valid = 1'b1;
      while (!lookup_ready) @(negedge clk);
      @(negedge clk);
      lookup_valid = 1'b0;
      timeout = 0;
      while (!output_valid && timeout < 20) begin
        @(negedge clk);
        timeout = timeout + 1;
      end
      if (!output_valid)
        fail("lookup response timed out");
      if (output_start_index !== index || output_found !== expected_found)
        fail("lookup identity or found flag mismatch");
      if (expected_found && output_energy !== expected_energy(index))
        fail("lookup energy mismatch");
      if (stall_response) begin
        repeat (3) @(negedge clk);
        output_ready = 1'b1;
        @(negedge clk);
      end else begin
        @(negedge clk);
      end
      output_ready = 1'b0;
    end
  endtask

  task automatic send_sample_with_lookup(
    input [63:0] new_sample_index,
    input [63:0] requested_index,
    input expected_found
  );
    begin
      // The request is presented after the square stage captures the sample,
      // so its acceptance coincides exactly with the energy-cache write.
      @(negedge clk);
      sample_index = new_sample_index;
      sample_i = encoded_i(new_sample_index);
      sample_q = encoded_q(new_sample_index);
      sample_valid = 1'b1;
      @(negedge clk);
      sample_valid = 1'b0;
      output_ready = 1'b0;
      lookup_start_index = requested_index;
      lookup_valid = 1'b1;
      #1;
      if (!lookup_ready)
        fail("concurrent write lookup was not accepted");
      @(negedge clk);
      lookup_valid = 1'b0;
      if (!output_valid || output_start_index !== requested_index ||
          output_found !== expected_found)
        fail("concurrent write lookup response mismatch");
      if (expected_found &&
          output_energy !== expected_energy(requested_index))
        fail("same-cycle newest-energy bypass mismatch");
      repeat (2) @(negedge clk);
      output_ready = 1'b1;
      @(negedge clk);
      output_ready = 1'b0;
    end
  endtask

  always @(posedge clk) begin
    cycle_count <= cycle_count + 1;
    if (gap_pulse)
      gap_pulses <= gap_pulses + 1;
    if (index_error_pulse)
      index_error_pulses <= index_error_pulses + 1;
    if (restart_pulse)
      restart_pulses <= restart_pulses + 1;
    if (retention_miss_pulse)
      retention_miss_pulses <= retention_miss_pulses + 1;

    if (resetn && enable && !flush && !dut.input_restart &&
        stalled_last_cycle) begin
      if (!output_valid || output_energy !== stalled_energy ||
          output_start_index !== stalled_start_index ||
          output_found !== stalled_found)
        fail("lookup output changed while stalled");
    end
    stalled_last_cycle <= resetn && enable && !flush &&
                          !dut.input_restart &&
                          output_valid && !output_ready;
    if (output_valid && !output_ready) begin
      stalled_energy <= output_energy;
      stalled_start_index <= output_start_index;
      stalled_found <= output_found;
    end

    if (energy_write_pulse) begin
      if (energy_write_start_index !==
          expected_segment_base + expected_segment_energy_count)
        fail("energy write index mismatch");
      if (energy_write_value !== expected_energy(
          expected_segment_base + expected_segment_energy_count))
        fail("energy write value mismatch");
      observed_energy_count <= observed_energy_count + 1;
      expected_segment_energy_count <= expected_segment_energy_count + 1;
    end
  end

  initial begin
    $dumpfile("build/tb_starlink_pss_energy_cache.vcd");
    $dumpvars(0, tb_starlink_pss_energy_cache);

    repeat (3) @(negedge clk);
    resetn = 1'b1;
    enable = 1'b1;

    // Alternate six- and seven-clock periods: approximately 15 MS/s at the
    // 100 MHz acquisition clock. The base starts at signed CI16 extremes.
    for (sample_number = 0;
         sample_number < FIRST_SEGMENT_SAMPLES;
         sample_number = sample_number + 1)
      send_sample(FIRST_BASE + sample_number, 1'b0,
                  (sample_number & 1) ? 5 : 4);
    repeat (4) @(negedge clk);

    if (expected_segment_energy_count !=
        FIRST_SEGMENT_SAMPLES - WINDOW_SAMPLES + 1)
      fail("first-segment energy count mismatch");
    if (stored_energy_count != CACHE_ENTRIES ||
        oldest_energy_start_index !== FIRST_BASE + 387 ||
        newest_energy_start_index !== FIRST_BASE + 2434)
      fail("full-cache retained range mismatch");

    check_lookup(FIRST_BASE + 387, 1'b1, 1'b1);
    check_lookup(FIRST_BASE + 2434, 1'b1, 1'b0);
    check_lookup(FIRST_BASE + 386, 1'b0, 1'b0);
    check_lookup(FIRST_BASE + 2435, 1'b0, 1'b0);

    // A request for the energy being written is bypassed exactly. A request
    // for the oldest entry while its circular address is overwritten fails
    // closed instead of returning device-dependent BRAM read/write data.
    send_sample_with_lookup(FIRST_BASE + 2500,
                            FIRST_BASE + 2435, 1'b1);
    send_sample_with_lookup(FIRST_BASE + 2501,
                            FIRST_BASE + 388, 1'b0);

    // An explicit gap invalidates a response already stalled at the output,
    // then the gap-tagged sample becomes sample zero of the next segment.
    @(negedge clk);
    lookup_start_index = FIRST_BASE + 1000;
    lookup_valid = 1'b1;
    while (!lookup_ready) @(negedge clk);
    @(negedge clk);
    lookup_valid = 1'b0;
    while (!output_valid) @(negedge clk);

    expected_segment_base = SECOND_BASE;
    expected_segment_energy_count = 0;
    send_sample(SECOND_BASE, 1'b1, 0);
    if (output_valid)
      fail("gap did not invalidate stalled lookup response");
    for (sample_number = 1; sample_number < 70;
         sample_number = sample_number + 1)
      send_sample(SECOND_BASE + sample_number, 1'b0, 0);
    repeat (4) @(negedge clk);
    if (expected_segment_energy_count != 5 || stored_energy_count != 5 ||
        oldest_energy_start_index !== SECOND_BASE ||
        newest_energy_start_index !== SECOND_BASE + 4)
      fail("gap restart energy range mismatch");
    check_lookup(SECOND_BASE + 4, 1'b1, 1'b0);

    // A nonconsecutive index has the same fail-closed restart semantics and
    // is accounted separately from an explicit gap.
    expected_segment_base = THIRD_BASE;
    expected_segment_energy_count = 0;
    for (sample_number = 0; sample_number < WINDOW_SAMPLES;
         sample_number = sample_number + 1)
      send_sample(THIRD_BASE + sample_number, 1'b0, 0);
    repeat (4) @(negedge clk);
    if (expected_segment_energy_count != 1 || stored_energy_count != 1)
      fail("index restart energy count mismatch");
    check_lookup(THIRD_BASE, 1'b1, 1'b1);

    enable = 1'b0;
    @(negedge clk);
    if (stored_energy_count != 0 || output_valid || lookup_ready)
      fail("disable did not clear cache and lookup state");

    if (gap_pulses != 1 || index_error_pulses != 1 ||
        restart_pulses != 3 || retention_miss_pulses != 3)
      fail("lifecycle event accounting mismatch");

    $display("ENERGY_CACHE_PASS window=%0d cache=%0d writes=%0d gap_restart=1 index_restart=1 retention=1 backpressure=1",
             WINDOW_SAMPLES, CACHE_ENTRIES, observed_energy_count);
    $finish;
  end

endmodule
