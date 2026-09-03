`timescale 1ns/1ps

module tb_starlink_pss_score_phase_tagger;

  localparam integer PHASE_BINS = 8;
  localparam integer PHASE_INDEX_WIDTH = 3;

  reg clk = 1'b0;
  reg resetn = 1'b0;
  reg enable = 1'b0;
  reg flush = 1'b0;
  reg score_valid = 1'b0;
  reg [63:0] score_start_index = 64'd0;
  reg [7:0] score_value = 8'd0;
  reg stream_discontinuity = 1'b0;

  wire tagged_valid;
  wire [63:0] tagged_start_index;
  wire [PHASE_INDEX_WIDTH-1:0] tagged_phase;
  wire [7:0] tagged_value;
  wire tagged_stream_discontinuity;
  wire accepted_pulse;
  wire index_discontinuity_pulse;

  integer accepted_count = 0;
  integer discontinuity_count = 0;

  always #5 clk = ~clk;

  starlink_pss_score_phase_tagger #(
    .PHASE_BINS       (PHASE_BINS),
    .PHASE_INDEX_WIDTH(PHASE_INDEX_WIDTH),
    .SCORE_WIDTH      (8)
  ) dut (
    .clk                         (clk),
    .resetn                      (resetn),
    .enable                      (enable),
    .flush                       (flush),
    .score_valid                 (score_valid),
    .score_start_index           (score_start_index),
    .score_value                 (score_value),
    .stream_discontinuity        (stream_discontinuity),
    .tagged_valid                (tagged_valid),
    .tagged_start_index          (tagged_start_index),
    .tagged_phase                (tagged_phase),
    .tagged_value                (tagged_value),
    .tagged_stream_discontinuity (tagged_stream_discontinuity),
    .accepted_pulse              (accepted_pulse),
    .index_discontinuity_pulse   (index_discontinuity_pulse)
  );

  task automatic fail(input string message);
    begin
      $display("SCORE_PHASE_TAGGER_FAIL %0s accepted=%0d discontinuities=%0d",
               message, accepted_count, discontinuity_count);
      $fatal(1);
    end
  endtask

  task automatic send_and_expect(
    input [63:0] index,
    input [7:0] value,
    input [PHASE_INDEX_WIDTH-1:0] expected_phase
  );
    begin
      @(negedge clk);
      score_start_index = index;
      score_value = value;
      score_valid = 1'b1;
      #1;
      if (!tagged_valid || !accepted_pulse || tagged_stream_discontinuity)
        fail("valid consecutive score was not published");
      if (tagged_start_index !== index || tagged_value !== value ||
          tagged_phase !== expected_phase)
        fail("tagged payload mismatch");
      @(negedge clk);
      score_valid = 1'b0;
      accepted_count = accepted_count + 1;
    end
  endtask

  task automatic send_index_jump(input [63:0] index);
    begin
      @(negedge clk);
      score_start_index = index;
      score_value = 8'haa;
      score_valid = 1'b1;
      #1;
      if (tagged_valid || accepted_pulse ||
          !tagged_stream_discontinuity || !index_discontinuity_pulse)
        fail("index jump did not fail closed");
      @(negedge clk);
      score_valid = 1'b0;
      discontinuity_count = discontinuity_count + 1;
    end
  endtask

  initial begin
    repeat (3) @(negedge clk);
    resetn = 1'b1;
    enable = 1'b1;

    send_and_expect(64'd100, 8'd10, 3'd0);
    send_and_expect(64'd101, 8'd11, 3'd1);

    // Valid-time gaps do not break accepted-index continuity.
    repeat (5) @(negedge clk);
    send_and_expect(64'd102, 8'd12, 3'd2);
    send_and_expect(64'd103, 8'd13, 3'd3);
    send_and_expect(64'd104, 8'd14, 3'd4);
    send_and_expect(64'd105, 8'd15, 3'd5);
    send_and_expect(64'd106, 8'd16, 3'd6);
    send_and_expect(64'd107, 8'd17, 3'd7);
    send_and_expect(64'd108, 8'd18, 3'd0);

    // The bad score is suppressed; the following consecutive score restarts
    // at phase zero using the bad score only as a continuity anchor.
    send_index_jump(64'd200);
    send_and_expect(64'd201, 8'd21, 3'd0);
    send_and_expect(64'd202, 8'd22, 3'd1);

    // An explicit source discontinuity suppresses a simultaneous score and
    // makes the next score the new phase-zero origin.
    @(negedge clk);
    score_start_index = 64'd203;
    score_valid = 1'b1;
    stream_discontinuity = 1'b1;
    #1;
    if (tagged_valid || !tagged_stream_discontinuity ||
        index_discontinuity_pulse)
      fail("explicit discontinuity was not distinguished from an index jump");
    @(negedge clk);
    score_valid = 1'b0;
    stream_discontinuity = 1'b0;
    discontinuity_count = discontinuity_count + 1;
    send_and_expect(64'd500, 8'd50, 3'd0);

    // Disable and flush each discard activity and restart the phase origin.
    @(negedge clk);
    enable = 1'b0;
    score_valid = 1'b1;
    #1;
    if (tagged_valid || tagged_stream_discontinuity)
      fail("disabled tagger published activity");
    @(negedge clk);
    score_valid = 1'b0;
    enable = 1'b1;
    send_and_expect(64'd700, 8'd70, 3'd0);

    @(negedge clk);
    flush = 1'b1;
    score_valid = 1'b1;
    #1;
    if (tagged_valid || tagged_stream_discontinuity)
      fail("flush did not suppress score activity");
    @(negedge clk);
    flush = 1'b0;
    score_valid = 1'b0;
    send_and_expect(64'd900, 8'd90, 3'd0);

    if (accepted_count != 14 || discontinuity_count != 2)
      fail("unexpected final event counts");

    $display("SCORE_PHASE_TAGGER_PASS accepted=%0d wraps=1 valid_gaps=1 index_rebase=1 explicit_discontinuity=1 disable_restart=1 flush_restart=1",
             accepted_count);
    $finish;
  end

endmodule
