`timescale 1ns/1ps

module tb_starlink_pss_m2_phase_matrix;

  localparam integer PHASE_BINS = 20000;
  localparam integer PHASE_INDEX_WIDTH = 15;
  localparam integer TILE_FRAMES = 64;
  localparam integer TILE_SCORES = PHASE_BINS * TILE_FRAMES;
  localparam [63:0] FIRST_SCORE_INDEX = 64'd10000000;

  reg clk = 1'b0;
  always #5 clk = ~clk;
  reg resetn = 1'b0;
  reg enable = 1'b0;
  reg flush = 1'b0;
  reg raw_score_valid = 1'b0;
  reg [63:0] raw_score_start_index = FIRST_SCORE_INDEX;
  reg [7:0] raw_score_value = 8'd0;
  reg stream_discontinuity = 1'b0;

  wire tagged_valid;
  wire [63:0] tagged_start_index;
  wire [PHASE_INDEX_WIDTH-1:0] tagged_phase;
  wire [7:0] tagged_value;
  wire tagged_stream_discontinuity;
  wire phase_discontinuity;
  wire [1:0] map_ready_mask;
  wire [31:0] map_generation_0;
  wire [31:0] map_generation_1;
  wire [63:0] map_start_index_0;
  wire [63:0] map_start_index_1;
  reg map_read_request = 1'b0;
  reg map_read_bank = 1'b0;
  reg [PHASE_INDEX_WIDTH-1:0] map_read_index = 0;
  wire map_read_valid;
  wire [15:0] map_read_data;
  wire map_read_error;
  reg map_release = 1'b0;
  reg map_release_bank = 1'b0;
  wire [31:0] accepted_score_count;
  wire [31:0] discarded_score_count;
  wire [31:0] discontinuity_abort_count;
  wire [31:0] map_publish_count;
  wire [31:0] map_overrun_count;
  wire [31:0] score_protocol_error_count;
  wire [31:0] map_arithmetic_overflow_count;
  wire [31:0] map_read_error_count;
  wire [31:0] map_release_error_count;

  reg [7:0] score_profile [0:PHASE_BINS-1];

  starlink_pss_score_phase_tagger #(
    .PHASE_BINS       (PHASE_BINS),
    .PHASE_INDEX_WIDTH(PHASE_INDEX_WIDTH),
    .SCORE_WIDTH      (8)
  ) tagger (
    .clk                         (clk),
    .resetn                      (resetn),
    .enable                      (enable),
    .flush                       (flush),
    .score_valid                 (raw_score_valid),
    .score_start_index           (raw_score_start_index),
    .score_value                 (raw_score_value),
    .stream_discontinuity        (stream_discontinuity),
    .tagged_valid                (tagged_valid),
    .tagged_start_index          (tagged_start_index),
    .tagged_phase                (tagged_phase),
    .tagged_value                (tagged_value),
    .tagged_stream_discontinuity (tagged_stream_discontinuity),
    .accepted_pulse              (),
    .index_discontinuity_pulse   (phase_discontinuity)
  );

  starlink_pss_phase_map #(
    .PHASE_BINS               (PHASE_BINS),
    .PHASE_INDEX_WIDTH        (PHASE_INDEX_WIDTH),
    .TILE_FRAMES              (TILE_FRAMES),
    .TILE_FRAME_WIDTH         (6),
    .SCORE_WIDTH              (8),
    .MAP_WIDTH                (16),
    .MAP_SEGMENT_ADDRESS_WIDTH(11),
    .MAP_SEGMENT_COUNT        (10),
    .MAP_SEGMENT_INDEX_WIDTH  (4)
  ) phase_map (
    .clk                          (clk),
    .resetn                       (resetn),
    .acquisition_enable           (enable),
    .score_valid                  (tagged_valid),
    .score_start_index            (tagged_start_index),
    .score_phase                  (tagged_phase),
    .score_value                  (tagged_value),
    .stream_discontinuity         (tagged_stream_discontinuity),
    .map_ready_mask               (map_ready_mask),
    .map_generation_0             (map_generation_0),
    .map_generation_1             (map_generation_1),
    .map_start_index_0            (map_start_index_0),
    .map_start_index_1            (map_start_index_1),
    .map_read_request             (map_read_request),
    .map_read_bank                (map_read_bank),
    .map_read_index               (map_read_index),
    .map_read_valid               (map_read_valid),
    .map_read_data                (map_read_data),
    .map_read_error               (map_read_error),
    .map_release                  (map_release),
    .map_release_bank             (map_release_bank),
    .accepted_score_count         (accepted_score_count),
    .discarded_score_count        (discarded_score_count),
    .discontinuity_abort_count    (discontinuity_abort_count),
    .map_publish_count            (map_publish_count),
    .map_overrun_count            (map_overrun_count),
    .score_protocol_error_count   (score_protocol_error_count),
    .map_arithmetic_overflow_count(map_arithmetic_overflow_count),
    .map_read_error_count         (map_read_error_count),
    .map_release_error_count      (map_release_error_count)
  );

  task automatic fail(input string message);
    begin
      $display("M2_PHASE_MATRIX_FAIL %0s accepted=%0d maps=%0d ready=%0b",
               message, accepted_score_count, map_publish_count, map_ready_mask);
      $fatal(1);
    end
  endtask

  task automatic read_map_word(
    input integer bank,
    input integer phase,
    output [15:0] value
  );
    begin
      @(negedge clk);
      map_read_bank = bank[0];
      map_read_index = phase[PHASE_INDEX_WIDTH-1:0];
      map_read_request = 1'b1;
      @(negedge clk);
      map_read_request = 1'b0;
      @(negedge clk);
      if (!map_read_valid || map_read_error)
        fail("map read failed");
      value = map_read_data;
    end
  endtask

  integer running_score = 0;
  task automatic drive_tile(input integer expected_peak_phase);
    integer phase;
    integer profile_index;
    integer delta;
    begin
      delta = (32 - expected_peak_phase + PHASE_BINS) % PHASE_BINS;
      for (phase = 0; phase < TILE_SCORES; phase = phase + 1) begin
        profile_index = (phase + delta) % PHASE_BINS;
        @(negedge clk);
        raw_score_valid = 1'b1;
        raw_score_start_index = FIRST_SCORE_INDEX + running_score;
        raw_score_value = score_profile[profile_index];
        running_score = running_score + 1;
      end
      @(negedge clk);
      raw_score_valid = 1'b0;
    end
  endtask

  integer expected_generation = 1;
  task automatic check_and_release_tile(input integer expected_peak_phase);
    integer timeout;
    integer bank;
    integer phase;
    integer profile_index;
    integer delta;
    integer expected_value;
    integer observed_peak;
    integer observed_peak_phase;
    reg [15:0] value;
    reg [63:0] expected_start;
    begin
      timeout = 0;
      while (map_ready_mask == 0 && timeout < 100000) begin
        @(posedge clk);
        timeout = timeout + 1;
      end
      if (timeout == 100000)
        fail("map publication timeout");
      bank = map_ready_mask[0] ? 0 : 1;
      expected_start = FIRST_SCORE_INDEX +
          (expected_generation - 1) * TILE_SCORES;
      if ((!bank && (map_generation_0 != expected_generation ||
                     map_start_index_0 != expected_start)) ||
          (bank && (map_generation_1 != expected_generation ||
                    map_start_index_1 != expected_start)))
        fail("map identity mismatch");

      delta = (32 - expected_peak_phase + PHASE_BINS) % PHASE_BINS;
      observed_peak = 0;
      observed_peak_phase = -1;
      for (phase = 0; phase < PHASE_BINS; phase = phase + 1) begin
        read_map_word(bank, phase, value);
        profile_index = (phase + delta) % PHASE_BINS;
        expected_value = TILE_FRAMES * score_profile[profile_index];
        if (value !== expected_value[15:0])
          fail("exact phase-map word mismatch");
        if (phase == 0 || value > observed_peak) begin
          observed_peak = value;
          observed_peak_phase = phase;
        end
      end
      if (observed_peak_phase != expected_peak_phase || observed_peak != 16320) begin
        $display("M2_PHASE_PEAK_MISMATCH expected_phase=%0d observed_phase=%0d observed_value=%0d delta=%0d",
                 expected_peak_phase, observed_peak_phase, observed_peak, delta);
        fail("phase-map peak timing mismatch");
      end

      @(negedge clk);
      map_release_bank = bank[0];
      map_release = 1'b1;
      @(negedge clk);
      map_release = 1'b0;
      repeat (PHASE_BINS + 8) @(posedge clk);
      expected_generation = expected_generation + 1;
      $display("M2_PHASE_CASE_PASS phase=%0d peak=%0d bank=%0d",
               expected_peak_phase, observed_peak, bank);
    end
  endtask

  initial begin
    $readmemh("../axi_starlink_pss_periodic_injector/tb/m2_period_scores_u8.mem",
              score_profile);
    if (score_profile[32] != 8'hff)
      fail("score profile control peak is absent");

    repeat (8) @(posedge clk);
    @(negedge clk);
    resetn = 1'b1;
    enable = 1'b1;
    repeat (PHASE_BINS + 8) @(posedge clk);

    drive_tile(0);
    check_and_release_tile(0);
    drive_tile(PHASE_BINS - 1);
    check_and_release_tile(PHASE_BINS - 1);
    drive_tile(7311);
    check_and_release_tile(7311);

    if (phase_discontinuity || accepted_score_count != 3 * TILE_SCORES ||
        discarded_score_count != 0 || discontinuity_abort_count != 0 ||
        map_publish_count != 3 || map_overrun_count != 0 ||
        score_protocol_error_count != 0 ||
        map_arithmetic_overflow_count != 0 || map_read_error_count != 0 ||
        map_release_error_count != 0 || map_ready_mask != 0)
      fail("M2 phase matrix telemetry is not clean");

    $display("M2_PHASE_MATRIX_PASS cases=3 exact_words=60000 accepted=%0d maps=%0d",
             accepted_score_count, map_publish_count);
    $finish;
  end

endmodule
