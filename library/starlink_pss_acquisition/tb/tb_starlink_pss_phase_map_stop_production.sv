`timescale 1ns/1ps

// Production geometry, one bounded mid-tile request, real M2 score fixture.
// This qualifies only the map core: no FFT, pilot, PSMA, IIO, or RF assertion.
module tb_starlink_pss_phase_map_stop_production;
  localparam integer BINS = 20000;
  localparam integer FRAMES = 64;
  localparam integer TOTAL = BINS * FRAMES;
  localparam integer PEAK_PHASE = 7311;
  localparam integer DELTA = (32 - PEAK_PHASE + BINS) % BINS;
  // Nonzero upper word and carry through the low word at the terminal end.
  localparam [63:0] FIRST_INDEX = 64'h00000001fff80000;
  localparam [63:0] END_INDEX = FIRST_INDEX + 64'd1280000;
  localparam integer REQUEST_POSITION = TOTAL / 2 + 13;

  reg clk = 0;
  always #5 clk = !clk;
  reg resetn = 0, acquisition_enable = 0, score_valid = 0;
  reg [63:0] score_start_index = 0;
  reg [14:0] score_phase = 0;
  reg [7:0] score_value = 0;
  reg stream_discontinuity = 0, stop_request = 0;
  reg map_read_request = 0, map_read_bank = 0, map_release = 0, map_release_bank = 0;
  reg [14:0] map_read_index = 0;
  wire [1:0] map_ready_mask;
  wire [31:0] map_generation_0, map_generation_1;
  wire [63:0] map_start_index_0, map_start_index_1;
  wire map_read_valid, map_read_error;
  wire [15:0] map_read_data;
  wire [31:0] accepted_score_count, discarded_score_count, discontinuity_abort_count;
  wire [31:0] map_publish_count, map_overrun_count, score_protocol_error_count;
  wire [31:0] map_arithmetic_overflow_count, map_read_error_count, map_release_error_count;
  wire map_counter_fault;
  wire stop_pending, stop_ack, stop_done, stop_complete, stop_failed, stop_has_map;
  wire [5:0] stop_failure_reason;
  wire [31:0] stop_generation;
  wire [63:0] stop_start_index, stop_end_index;
  reg [7:0] score_profile [0:BINS-1];
  string profile_path;
  integer ack_count = 0, publish_edges = 0, generated_scores = 0;
  integer observed_peak = 0, observed_peak_phase = -1, expected_word;
  reg reader_finished = 0;

  // Do not override any geometry parameter: use all ten physical segments
  // per bank, 11-bit segment addresses, 20,000 phases, and 64 tile frames.
  starlink_pss_phase_map #(.ENABLE_BOUNDARY_STOP(1)) dut (.*);

  task automatic fail(input string message);
    $display("MAP_STOP_PRODUCTION_FAIL %s", message);
    $fatal(1);
  endtask
  task automatic check_terminal;
    if (!stop_done || stop_pending || !stop_complete || stop_failed ||
        stop_failure_reason != 0 || !stop_has_map || stop_generation != 1 ||
        stop_start_index != FIRST_INDEX || stop_end_index != END_INDEX)
      fail("terminal generation/candidate interval/status mismatch");
  endtask
  task automatic check_counters;
    if (accepted_score_count != TOTAL || discarded_score_count != 0 ||
        discontinuity_abort_count != 0 || map_publish_count != 1 || map_overrun_count != 0 ||
        score_protocol_error_count != 0 || map_arithmetic_overflow_count != 0 ||
        map_read_error_count != 0 || map_release_error_count != 0)
      fail("healthy boundary changed real acceptance/loss/error counters");
  endtask

  always @(posedge clk) begin
    if (resetn && dut.publish_pending) publish_edges = publish_edges + 1;
    #1;
    if (resetn && stop_ack) begin
      ack_count = ack_count + 1;
      check_terminal();
      if (publish_edges != 1 || map_ready_mask != 1 ||
          dut.update_pending || dut.write_pending || dut.publish_pending)
        fail("ack was not after the final RAM write/ready publication");
    end
  end

  initial begin
    if (!$value$plusargs("profile=%s", profile_path)) fail("missing real M2 profile path");
    $readmemh(profile_path, score_profile);
    if (score_profile[32] !== 8'hff) fail("real M2 control peak is missing");
    repeat (8) @(negedge clk);
    resetn = 1;
    acquisition_enable = 1;
    repeat (BINS + 8) @(negedge clk);
    fork
      begin : continuous_source
        // Continue producing consecutive candidate scores throughout map
        // readout, release, and clearing. Parking must not consume even the
        // first score of another tile, nor count intentional tail as loss.
        while (!reader_finished) begin
          @(negedge clk);
          score_valid = 1;
          score_start_index = FIRST_INDEX + generated_scores;
          score_phase = generated_scores % BINS;
          score_value = score_profile[(generated_scores + DELTA) % BINS];
          stop_request = generated_scores == REQUEST_POSITION;
          generated_scores = generated_scores + 1;
        end
        @(negedge clk);
        score_valid = 0;
        stop_request = 0;
      end
      begin : retained_reader
        wait (stop_pending);
        if (accepted_score_count < REQUEST_POSITION || accepted_score_count >= TOTAL)
          fail("request was not accepted mid-tile");
        wait (stop_done);
        @(negedge clk);
        check_terminal();
        if (map_generation_0 != 1 || map_start_index_0 != FIRST_INDEX)
          fail("published bank metadata disagrees with terminal receipt");
        for (integer phase = 0; phase < BINS; phase = phase + 1) begin
          @(negedge clk);
          map_read_bank = 0;
          map_read_index = phase;
          map_read_request = 1;
          @(negedge clk);
          map_read_request = 0;
          @(negedge clk);
          expected_word = FRAMES * score_profile[(phase + DELTA) % BINS];
          if (!map_read_valid || map_read_error || map_read_data !== expected_word[15:0])
            fail("production segmented-bank exact word mismatch");
          if (phase == 0 || map_read_data > observed_peak) begin
            observed_peak = map_read_data;
            observed_peak_phase = phase;
          end
          check_terminal();
        end
        if (observed_peak_phase != PEAK_PHASE || observed_peak != 16320)
          fail("rotated M2 oracle peak changed");
        check_counters();
        @(negedge clk);
        map_release_bank = 0;
        map_release = 1;
        @(negedge clk);
        map_release = 0;
        repeat (BINS + 8) @(negedge clk);
        check_terminal();
        check_counters();
        if (map_ready_mask != 0 || ack_count != 1 || publish_edges != 1 ||
            generated_scores <= TOTAL + 3 * BINS)
          fail("release erased receipt or continued source admitted another tile");
        reader_finished = 1;
      end
    join
    $display("MAP_STOP_PRODUCTION_PASS bins=20000 frames=64 segments_per_bank=10 request_position=%0d exact_words=20000 accepted=%0d generated=%0d generation=%0d start=%016h end=%016h peak_phase=%0d core_only=1 no_radio_claim=1",
             REQUEST_POSITION, accepted_score_count, generated_scores, stop_generation,
             stop_start_index, stop_end_index, observed_peak_phase);
    $finish;
  end
  initial begin #50000000; fail("bounded production simulation timeout"); end
endmodule
