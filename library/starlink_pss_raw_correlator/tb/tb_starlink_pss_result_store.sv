`timescale 1ns/1ps

module tb_starlink_pss_result_store;

  reg engine_clk = 1'b0;
  reg control_clk = 1'b0;
  always #5 engine_clk = ~engine_clk;
  always #7 control_clk = ~control_clk;

  reg engine_resetn = 1'b0;
  reg control_resetn = 1'b0;

  reg result_valid = 1'b0;
  wire result_ready;
  reg result_score_valid = 1'b0;
  reg result_includes_eh = 1'b0;
  reg [31:0] result_request_id = 32'd0;
  reg [63:0] result_center_index = 64'd0;
  reg [63:0] result_center_timestamp = 64'd0;
  reg signed [6:0] result_lag = 7'sd0;
  reg [63:0] result_timestamp = 64'd0;
  reg [31:0] result_coefficient_generation = 32'd0;
  reg signed [47:0] result_c_re = 48'sd0;
  reg signed [47:0] result_c_im = 48'sd0;
  reg signed [47:0] result_ex = 48'sd0;
  reg signed [47:0] result_eh = 48'sd0;
  reg [8:0] result_saturation_events = 9'd0;
  reg [76:0] result_score_numerator = 77'd0;
  reg [68:0] result_score_denominator = 69'd0;

  wire [1:0] result_bank_free;
  wire [31:0] result_published_count;
  wire [31:0] result_overrun_count;

  wire control_result_available;
  wire control_result_bank;
  reg [4:0] control_word_index = 5'd0;
  reg control_word_read = 1'b0;
  wire control_word_valid;
  wire [31:0] control_word_data;
  reg control_result_release = 1'b0;
  wire [31:0] control_consumed_count;

  reg [31:0] expected_word [0:5][0:25];

  starlink_pss_result_store dut (
    .i_engine_clk                       (engine_clk),
    .i_engine_resetn                    (engine_resetn),
    .i_result_valid                     (result_valid),
    .o_result_ready                     (result_ready),
    .i_result_score_valid               (result_score_valid),
    .i_result_includes_eh               (result_includes_eh),
    .i_result_request_id                (result_request_id),
    .i_result_center_index              (result_center_index),
    .i_result_center_timestamp          (result_center_timestamp),
    .i_result_lag                       (result_lag),
    .i_result_timestamp                 (result_timestamp),
    .i_result_coefficient_generation    (result_coefficient_generation),
    .i_result_c_re                      (result_c_re),
    .i_result_c_im                      (result_c_im),
    .i_result_ex                        (result_ex),
    .i_result_eh                        (result_eh),
    .i_result_saturation_events         (result_saturation_events),
    .i_result_score_numerator           (result_score_numerator),
    .i_result_score_denominator         (result_score_denominator),
    .o_result_bank_free                 (result_bank_free),
    .o_result_published_count           (result_published_count),
    .o_result_overrun_count             (result_overrun_count),
    .i_control_clk                      (control_clk),
    .i_control_resetn                   (control_resetn),
    .o_control_result_available         (control_result_available),
    .o_control_result_bank              (control_result_bank),
    .i_control_word_index               (control_word_index),
    .i_control_word_read                (control_word_read),
    .o_control_word_valid               (control_word_valid),
    .o_control_word_data                (control_word_data),
    .i_control_result_release           (control_result_release),
    .o_control_consumed_count           (control_consumed_count)
  );

  task automatic fail;
    input [1023:0] message;
    begin
      $display("RESULT_STORE_FAIL %0s", message);
      $fatal(1);
    end
  endtask

  task automatic load_payload;
    input integer job;
    begin
      result_score_valid = (job != 4);
      result_includes_eh = job[0];
      result_request_id = 32'h1000_0100 + job;
      result_center_index = 64'h0123_4567_89ab_c000 + job;
      result_center_timestamp = 64'h1020_3040_5060_7000 + job;
      result_lag = -7'sd32 + job;
      result_timestamp = 64'h8877_6655_4433_2200 + job;
      result_coefficient_generation = 32'ha500_0000 + job;
      result_c_re = -48'sd100000 - job;
      result_c_im = 48'sh0000_1234_5000 + job;
      result_ex = 48'sh0000_2345_6000 + job;
      result_eh = 48'sh0000_3456_7000 + job;
      result_saturation_events = job;
      result_score_numerator = 77'h1234_5678_9abc_def0 + job;
      result_score_denominator = 69'h0fed_cba9_8765_4321 + job;
    end
  endtask

  task automatic snapshot_expected;
    input integer job;
    begin
      expected_word[job][0] = 32'h3153_5350;
      expected_word[job][1] = {
        5'd26, 3'd0, 8'd1, 14'd0,
        result_includes_eh, result_score_valid
      };
      expected_word[job][2] = result_request_id;
      expected_word[job][3] = result_center_index[31:0];
      expected_word[job][4] = result_center_index[63:32];
      expected_word[job][5] = result_center_timestamp[31:0];
      expected_word[job][6] = result_center_timestamp[63:32];
      expected_word[job][7] = {{25{result_lag[6]}}, result_lag};
      expected_word[job][8] = result_timestamp[31:0];
      expected_word[job][9] = result_timestamp[63:32];
      expected_word[job][10] = result_coefficient_generation;
      expected_word[job][11] = result_c_re[31:0];
      expected_word[job][12] = {
        {16{result_c_re[47]}}, result_c_re[47:32]
      };
      expected_word[job][13] = result_c_im[31:0];
      expected_word[job][14] = {
        {16{result_c_im[47]}}, result_c_im[47:32]
      };
      expected_word[job][15] = result_ex[31:0];
      expected_word[job][16] = {
        {16{result_ex[47]}}, result_ex[47:32]
      };
      expected_word[job][17] = result_eh[31:0];
      expected_word[job][18] = {
        {16{result_eh[47]}}, result_eh[47:32]
      };
      expected_word[job][19] = {23'd0, result_saturation_events};
      expected_word[job][20] = result_score_numerator[31:0];
      expected_word[job][21] = result_score_numerator[63:32];
      expected_word[job][22] = {
        19'd0, result_score_numerator[76:64]
      };
      expected_word[job][23] = result_score_denominator[31:0];
      expected_word[job][24] = result_score_denominator[63:32];
      expected_word[job][25] = {
        27'd0, result_score_denominator[68:64]
      };
    end
  endtask

  task automatic send_result;
    input integer job;
    begin
      @(negedge engine_clk);
      load_payload(job);
      snapshot_expected(job);
      result_valid = 1'b1;
      while (!result_ready)
        @(negedge engine_clk);
      @(posedge engine_clk);
      @(negedge engine_clk);
      result_valid = 1'b0;
    end
  endtask

  task automatic wait_for_control_result;
    integer timeout;
    begin
      timeout = 0;
      while (!control_result_available && timeout < 100) begin
        @(posedge control_clk);
        timeout = timeout + 1;
      end
      if (timeout == 100)
        fail("published descriptor did not cross to control clock");
    end
  endtask

  task automatic read_and_check_word;
    input integer job;
    input integer word_index;
    begin
      @(negedge control_clk);
      control_word_index = word_index[4:0];
      control_word_read = 1'b1;
      @(posedge control_clk);
      #1;
      if (!control_word_valid)
        fail("control read response did not assert valid");
      if (control_word_data !== expected_word[job][word_index]) begin
        $display("word=%0d expected=%08x actual=%08x",
                 word_index, expected_word[job][word_index],
                 control_word_data);
        fail("packet word mismatch");
      end
      @(negedge control_clk);
      control_word_read = 1'b0;
    end
  endtask

  task automatic check_packet_forward;
    input integer job;
    integer word_index;
    begin
      for (word_index = 0; word_index < 26;
           word_index = word_index + 1)
        read_and_check_word(job, word_index);
    end
  endtask

  task automatic check_packet_reverse;
    input integer job;
    integer word_index;
    begin
      for (word_index = 25; word_index >= 0;
           word_index = word_index - 1)
        read_and_check_word(job, word_index);
    end
  endtask

  task automatic release_control_result;
    begin
      @(negedge control_clk);
      control_result_release = 1'b1;
      @(posedge control_clk);
      @(negedge control_clk);
      control_result_release = 1'b0;
    end
  endtask

  integer timeout;
  initial begin
    $dumpfile("build/tb_starlink_pss_result_store.vcd");
    $dumpvars(0, tb_starlink_pss_result_store);

    repeat (6) @(posedge engine_clk);
    @(negedge engine_clk);
    engine_resetn = 1'b1;
    control_resetn = 1'b1;
    repeat (8) @(posedge engine_clk);
    if (result_bank_free !== 2'b11 ||
        result_published_count !== 32'd0 ||
        result_overrun_count !== 32'd0 || control_result_available)
      fail("coordinated reset did not initialize the store");

    fork
      send_result(0);
      begin
        // The first packet takes 26 engine writes.  No descriptor may become
        // visible while a deliberately sampled prefix is still incomplete.
        repeat (8) begin
          @(posedge control_clk);
          if (control_result_available)
            fail("partially written packet became visible");
        end
      end
    join
    send_result(1);
    repeat (8) @(posedge engine_clk);
    if (result_bank_free !== 2'b00 ||
        result_published_count !== 32'd2)
      fail("two packets did not occupy both banks");

    // Both banks remain owned even though one descriptor has crossed.  The
    // third producer handshake must drop one complete packet immediately.
    send_result(2);
    repeat (3) @(posedge engine_clk);
    if (result_overrun_count !== 32'd1 ||
        result_published_count !== 32'd2) begin
      $display("published=%0d overruns=%0d banks=%b",
               result_published_count, result_overrun_count,
               result_bank_free);
      fail("full-store overrun was not counted atomically");
    end

    wait_for_control_result();
    check_packet_reverse(0);
    release_control_result();
    wait_for_control_result();
    check_packet_forward(1);
    release_control_result();

    timeout = 0;
    while ((result_bank_free != 2'b11) && (timeout < 100)) begin
      @(posedge engine_clk);
      timeout = timeout + 1;
    end
    if (timeout == 100 || control_consumed_count !== 32'd2)
      fail("released banks did not return across CDC");

    // A returned bank must be reusable without leaking the previous packet.
    send_result(3);
    wait_for_control_result();
    check_packet_reverse(3);
    release_control_result();

    timeout = 0;
    while ((result_bank_free != 2'b11) && (timeout < 100)) begin
      @(posedge engine_clk);
      timeout = timeout + 1;
    end
    if (timeout == 100)
      fail("reused bank was not returned");

    // Publish but do not release one packet.  Coordinated reset must flush its
    // descriptor, counters, read-valid state, and ownership without exposing
    // stale RAM contents.
    send_result(4);
    wait_for_control_result();
    @(negedge engine_clk);
    engine_resetn = 1'b0;
    control_resetn = 1'b0;
    repeat (6) @(posedge control_clk);
    @(negedge engine_clk);
    engine_resetn = 1'b1;
    control_resetn = 1'b1;
    repeat (10) @(posedge engine_clk);
    if (result_bank_free !== 2'b11 || control_result_available ||
        control_word_valid || result_published_count !== 32'd0 ||
        result_overrun_count !== 32'd0 ||
        control_consumed_count !== 32'd0)
      fail("coordinated reset did not flush publication state");

    send_result(5);
    wait_for_control_result();
    check_packet_forward(5);
    release_control_result();

    $display("RESULT_STORE_PASS packet_words=26 banks=2 pre_reset_published=4 pre_reset_overruns=1 post_reset_published=1");
    $finish;
  end

endmodule
