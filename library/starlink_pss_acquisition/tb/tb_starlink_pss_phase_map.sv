`timescale 1ns/1ps

module tb_starlink_pss_phase_map;

  localparam integer PHASE_BINS = 8;
  localparam integer PHASE_INDEX_WIDTH = 3;
  localparam integer TILE_FRAMES = 4;
  localparam integer TILE_FRAME_WIDTH = 2;

  reg clk = 1'b0;
  reg resetn = 1'b0;
  reg acquisition_enable = 1'b0;
  reg score_valid = 1'b0;
  reg [63:0] score_start_index = 64'd0;
  reg [PHASE_INDEX_WIDTH-1:0] score_phase = 0;
  reg [7:0] score_value = 0;
  reg stream_discontinuity = 1'b0;
  reg map_read_request = 1'b0;
  reg map_read_bank = 1'b0;
  reg [PHASE_INDEX_WIDTH-1:0] map_read_index = 0;
  reg map_release = 1'b0;
  reg map_release_bank = 1'b0;

  wire [1:0] map_ready_mask;
  wire [31:0] map_generation_0;
  wire [31:0] map_generation_1;
  wire [63:0] map_start_index_0;
  wire [63:0] map_start_index_1;
  wire map_read_valid;
  wire [15:0] map_read_data;
  wire map_read_error;
  wire [31:0] accepted_score_count;
  wire [31:0] discarded_score_count;
  wire [31:0] discontinuity_abort_count;
  wire [31:0] map_publish_count;
  wire [31:0] map_overrun_count;
  wire [31:0] score_protocol_error_count;
  wire [31:0] map_arithmetic_overflow_count;
  wire [31:0] map_read_error_count;
  wire [31:0] map_release_error_count;

  always #5 clk = ~clk;

  starlink_pss_phase_map #(
    .PHASE_BINS       (PHASE_BINS),
    .PHASE_INDEX_WIDTH(PHASE_INDEX_WIDTH),
    .TILE_FRAMES      (TILE_FRAMES),
    .TILE_FRAME_WIDTH (TILE_FRAME_WIDTH),
    .SCORE_WIDTH      (8),
    .MAP_WIDTH        (16),
    .MAP_SEGMENT_ADDRESS_WIDTH(3),
    .MAP_SEGMENT_COUNT(1),
    .MAP_SEGMENT_INDEX_WIDTH(1)
  ) dut (
    .clk                          (clk),
    .resetn                       (resetn),
    .acquisition_enable           (acquisition_enable),
    .score_valid                  (score_valid),
    .score_start_index            (score_start_index),
    .score_phase                  (score_phase),
    .score_value                  (score_value),
    .stream_discontinuity         (stream_discontinuity),
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
      $display("PHASE_MAP_FAIL %0s", message);
      $fatal(1);
    end
  endtask

  task automatic send_score(
    input [63:0] index,
    input [PHASE_INDEX_WIDTH-1:0] phase,
    input [7:0] value
  );
    begin
      @(negedge clk);
      score_start_index = index;
      score_phase = phase;
      score_value = value;
      score_valid = 1'b1;
      @(negedge clk);
      score_valid = 1'b0;
    end
  endtask

  task automatic read_and_expect(
    input bank,
    input [PHASE_INDEX_WIDTH-1:0] index,
    input [15:0] expected
  );
    begin
      @(negedge clk);
      map_read_bank = bank;
      map_read_index = index;
      map_read_request = 1'b1;
      @(negedge clk);
      map_read_request = 1'b0;
      @(negedge clk);
      if (!map_read_valid || map_read_error)
        fail("valid published-map read was rejected");
      if (map_read_data !== expected) begin
        $display("PHASE_MAP_MISMATCH bank=%0d index=%0d got=%0d expected=%0d",
                 bank, index, map_read_data, expected);
        fail("published map data mismatch");
      end
    end
  endtask

  task automatic release_bank(input bank);
    begin
      @(negedge clk);
      map_release_bank = bank;
      map_release = 1'b1;
      @(negedge clk);
      map_release = 1'b0;
    end
  endtask

  integer frame;
  integer phase;
  reg [63:0] base_index;

  initial begin
    $dumpfile("build/tb_starlink_pss_phase_map.vcd");
    $dumpvars(0, tb_starlink_pss_phase_map);

    repeat (3) @(negedge clk);
    resetn = 1'b1;
    acquisition_enable = 1'b1;
    repeat (12) @(negedge clk);

    // Eight back-to-back frames exercise a tile boundary with no idle score
    // cycle.  The first tile sums biases 1..4, and the second 10..13.
    base_index = 64'd1000;
    fork
      begin : produce_two_tiles
        @(negedge clk);
        score_valid = 1'b1;
        for (frame = 0; frame < 2 * TILE_FRAMES; frame = frame + 1) begin
          for (phase = 0; phase < PHASE_BINS; phase = phase + 1) begin
            score_start_index = base_index + frame * PHASE_BINS + phase;
            score_phase = phase;
            score_value = (frame < TILE_FRAMES) ?
                (frame + 1 + phase) :
                (10 + frame - TILE_FRAMES + phase);
            @(negedge clk);
          end
        end
        score_valid = 1'b0;
      end
      begin : read_first_while_filling_second
        wait (map_ready_mask[0]);
        read_and_expect(1'b0, 3, 16'd22);
      end
    join
    repeat (3) @(negedge clk);
    if (map_ready_mask !== 2'b11 || map_publish_count != 2)
      fail("two contiguous complete tiles did not publish both banks");
    if (map_generation_0 != 1 || map_start_index_0 != base_index)
      fail("first map metadata mismatch");
    if (map_generation_1 != 2 ||
        map_start_index_1 != base_index + TILE_FRAMES * PHASE_BINS)
      fail("second map metadata mismatch");
    if (map_overrun_count != 1)
      fail("two-full-bank condition was not counted once");
    for (phase = 0; phase < PHASE_BINS; phase = phase + 1)
      read_and_expect(1'b0, phase, 10 + 4 * phase);
    for (phase = 0; phase < PHASE_BINS; phase = phase + 1)
      read_and_expect(1'b1, phase, 46 + 4 * phase);

    // A read and release of the same immutable bank in one cycle is
    // deliberately rejected instead of relying on RAM collision behavior.
    @(negedge clk);
    map_read_bank = 1'b1;
    map_read_index = 0;
    map_read_request = 1'b1;
    map_release_bank = 1'b1;
    map_release = 1'b1;
    @(negedge clk);
    map_read_request = 1'b0;
    map_release = 1'b0;
    @(negedge clk);
    if (!map_read_error || map_read_error_count != 1)
      fail("same-cycle map read and release did not fail closed");

    // Releasing bank zero clears it.  A nonzero-phase score while the bank is
    // becoming available is discarded; the next phase zero begins a tile.
    release_bank(1'b0);
    repeat (10) @(negedge clk);
    send_score(64'd2999, 3'd7, 8'd200);
    base_index = 64'd3000;
    for (phase = 0; phase < PHASE_BINS; phase = phase + 1)
      send_score(base_index + phase, phase, 1 + phase);
    send_score(base_index + PHASE_BINS, 3'd0, 8'd2);

    // An explicit gap invalidates the partial map and forces a full clear.
    @(negedge clk);
    stream_discontinuity = 1'b1;
    @(negedge clk);
    stream_discontinuity = 1'b0;
    repeat (2) @(negedge clk);
    if (discontinuity_abort_count != 1)
      fail("stream discontinuity did not abort the partial tile");

    // Only published banks may be read or released.
    @(negedge clk);
    map_read_bank = 1'b0;
    map_read_index = 0;
    map_read_request = 1'b1;
    @(negedge clk);
    map_read_request = 1'b0;
    @(negedge clk);
    if (!map_read_error || map_read_error_count != 2)
      fail("unpublished bank read did not fail closed");

    release_bank(1'b0);
    if (map_release_error_count != 1)
      fail("unpublished bank release did not fail closed");

    // Disabling acquisition immediately after the final score must not strand
    // or erase a tile which is already complete and waiting in DRAIN.
    repeat (12) @(negedge clk);
    base_index = 64'd4000;
    for (frame = 0; frame < TILE_FRAMES; frame = frame + 1)
      for (phase = 0; phase < PHASE_BINS; phase = phase + 1)
        send_score(base_index + frame * PHASE_BINS + phase,
                   phase, frame + 1 + phase);
    acquisition_enable = 1'b0;
    repeat (3) @(negedge clk);
    if (map_publish_count != 3 || map_ready_mask == 2'b00)
      fail("disable at DRAIN stranded a complete tile");

    if (score_protocol_error_count != 0 ||
        map_arithmetic_overflow_count != 0)
      fail("unexpected protocol or arithmetic error");
    if (accepted_score_count != 105)
      fail("accepted score accounting mismatch");
    if (discarded_score_count < 1)
      fail("discarded score accounting did not advance");

    $display("PHASE_MAP_PASS bins=8 frames=4 ping_pong=1 complete_only=1 gap_abort=1 fail_closed_read=1 accepted=%0d discarded=%0d",
             accepted_score_count, discarded_score_count);
    $finish;
  end

endmodule
