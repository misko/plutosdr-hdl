`timescale 1ns/1ps

module tb_starlink_pss_reduced_tracking_core;

  localparam [63:0] TIMESTAMP_BASE = 64'h0000_0001_0000_0000;
  localparam [31:0] REQUEST_ID = 32'h5151_0001;
  localparam [63:0] CENTER_INDEX = 64'd400;

  reg control_clk = 1'b0;
  reg sample_clk = 1'b0;
  reg engine_clk = 1'b0;
  always #6 control_clk = ~control_clk;
  always #7 sample_clk = ~sample_clk;
  always #5 engine_clk = ~engine_clk;

  reg resetn = 1'b0;

  reg candidate_submit = 1'b0;
  reg [31:0] candidate_request_id = 32'd0;
  reg [63:0] candidate_center_index = 64'd0;
  reg [63:0] candidate_center_timestamp = 64'd0;
  wire candidate_submit_ready;
  wire candidate_submit_accepted;
  wire [2:0] candidate_queue_room;
  wire [31:0] queue_overrun_count;

  reg sample_enable = 1'b0;
  reg sample_valid = 1'b0;
  reg [63:0] sample_index = 64'd0;
  reg [63:0] sample_timestamp = 64'd0;
  reg signed [15:0] sample_i = 16'sd0;
  reg signed [15:0] sample_q = 16'sd0;
  reg [63:0] next_sample_index = 64'd0;

  reg coefficient_clear = 1'b0;
  reg coefficient_valid = 1'b0;
  wire coefficient_ready;
  reg signed [15:0] coefficient_i = 16'sd0;
  reg signed [15:0] coefficient_q = 16'sd0;
  reg coefficient_commit = 1'b0;
  wire coefficient_commit_ready;
  reg [31:0] coefficient_generation = 32'd77;
  wire coefficient_commit_accepted;
  wire coefficient_commit_rejected;
  wire active_coefficient_valid;
  wire [31:0] active_coefficient_generation;
  wire signed [47:0] active_coefficient_energy;
  wire [6:0] shadow_coefficient_count;

  wire result_available;
  wire result_bank;
  reg [4:0] result_word_index = 5'd0;
  reg result_word_read = 1'b0;
  wire result_word_valid;
  wire [31:0] result_word_data;
  reg result_release = 1'b0;

  wire candidate_pending;
  wire capture_active;
  wire [31:0] admitted_count;
  wire [31:0] completed_capture_count;
  wire [31:0] rejected_count;
  wire [31:0] late_count;
  wire [31:0] duplicate_count;
  wire [31:0] overlap_count;
  wire [31:0] aborted_count;
  wire [31:0] valid_gap_abort_count;
  wire [31:0] index_jump_abort_count;
  wire [31:0] timestamp_abort_count;
  wire [1:0] capture_bank_free;
  wire [31:0] capture_published_count;
  wire [31:0] capture_abort_discard_count;
  wire [31:0] capture_buffer_overrun_count;
  wire [31:0] capture_protocol_error_count;
  wire [31:0] engine_consumed_count;
  wire [31:0] correlator_bound_error_count;
  wire [31:0] reducer_processed_job_count;
  wire [31:0] reducer_emitted_result_count;
  wire [31:0] reducer_invalid_tuple_count;
  wire [31:0] reducer_bound_error_count;
  wire [31:0] reducer_protocol_error_count;
  wire [1:0] result_bank_free;
  wire [31:0] result_published_count;
  wire [31:0] result_overrun_count;
  wire [31:0] result_consumed_count;

  reg [31:0] expected_word [0:25];

  starlink_pss_reduced_tracking_core dut (
    .i_control_clk                     (control_clk),
    .i_sample_clk                      (sample_clk),
    .i_engine_clk                      (engine_clk),
    .i_resetn                          (resetn),
    .i_candidate_submit                (candidate_submit),
    .i_candidate_request_id            (candidate_request_id),
    .i_candidate_center_index          (candidate_center_index),
    .i_candidate_center_timestamp      (candidate_center_timestamp),
    .o_candidate_submit_ready          (candidate_submit_ready),
    .o_candidate_submit_accepted       (candidate_submit_accepted),
    .o_candidate_queue_room            (candidate_queue_room),
    .o_queue_overrun_count             (queue_overrun_count),
    .i_sample_enable                   (sample_enable),
    .i_sample_valid                    (sample_valid),
    .i_sample_index                    (sample_index),
    .i_sample_timestamp                (sample_timestamp),
    .i_sample_i                        (sample_i),
    .i_sample_q                        (sample_q),
    .i_coefficient_clear               (coefficient_clear),
    .i_coefficient_valid               (coefficient_valid),
    .o_coefficient_ready               (coefficient_ready),
    .i_coefficient_i                   (coefficient_i),
    .i_coefficient_q                   (coefficient_q),
    .i_coefficient_commit              (coefficient_commit),
    .o_coefficient_commit_ready        (coefficient_commit_ready),
    .i_coefficient_generation          (coefficient_generation),
    .o_coefficient_commit_accepted     (coefficient_commit_accepted),
    .o_coefficient_commit_rejected     (coefficient_commit_rejected),
    .o_active_coefficient_valid        (active_coefficient_valid),
    .o_active_coefficient_generation   (active_coefficient_generation),
    .o_active_coefficient_energy       (active_coefficient_energy),
    .o_shadow_coefficient_count        (shadow_coefficient_count),
    .o_result_available                (result_available),
    .o_result_bank                     (result_bank),
    .i_result_word_index               (result_word_index),
    .i_result_word_read                (result_word_read),
    .o_result_word_valid               (result_word_valid),
    .o_result_word_data                (result_word_data),
    .i_result_release                  (result_release),
    .o_candidate_pending               (candidate_pending),
    .o_capture_active                  (capture_active),
    .o_admitted_count                  (admitted_count),
    .o_completed_capture_count         (completed_capture_count),
    .o_rejected_count                  (rejected_count),
    .o_late_count                      (late_count),
    .o_duplicate_count                 (duplicate_count),
    .o_overlap_count                   (overlap_count),
    .o_aborted_count                   (aborted_count),
    .o_valid_gap_abort_count           (valid_gap_abort_count),
    .o_index_jump_abort_count          (index_jump_abort_count),
    .o_timestamp_abort_count           (timestamp_abort_count),
    .o_capture_bank_free               (capture_bank_free),
    .o_capture_published_count         (capture_published_count),
    .o_capture_abort_discard_count     (capture_abort_discard_count),
    .o_capture_buffer_overrun_count    (capture_buffer_overrun_count),
    .o_capture_protocol_error_count    (capture_protocol_error_count),
    .o_engine_consumed_count           (engine_consumed_count),
    .o_correlator_bound_error_count    (correlator_bound_error_count),
    .o_reducer_processed_job_count     (reducer_processed_job_count),
    .o_reducer_emitted_result_count    (reducer_emitted_result_count),
    .o_reducer_invalid_tuple_count     (reducer_invalid_tuple_count),
    .o_reducer_bound_error_count       (reducer_bound_error_count),
    .o_reducer_protocol_error_count    (reducer_protocol_error_count),
    .o_result_bank_free                (result_bank_free),
    .o_result_published_count          (result_published_count),
    .o_result_overrun_count            (result_overrun_count),
    .o_result_consumed_count           (result_consumed_count)
  );

  task automatic fail;
    input [1023:0] message;
    begin
      $display("REDUCED_TRACKING_FAIL %0s", message);
      $fatal(1);
    end
  endtask

  function automatic signed [47:0] expected_energy;
    input integer first_index;
    integer tap;
    reg signed [63:0] sum;
    reg signed [63:0] value;
    begin
      sum = 64'sd0;
      for (tap = 0; tap < 66; tap = tap + 1) begin
        value = first_index + tap;
        sum = sum + value * value + value * value;
      end
      expected_energy = sum[47:0];
    end
  endfunction

  task automatic load_impulse_coefficient;
    integer tap;
    begin
      for (tap = 0; tap < 66; tap = tap + 1) begin
        @(negedge engine_clk);
        while (!coefficient_ready)
          @(negedge engine_clk);
        coefficient_valid = 1'b1;
        coefficient_i = (tap == 0) ? 16'sd1 : 16'sd0;
        coefficient_q = 16'sd0;
      end
      @(negedge engine_clk);
      coefficient_valid = 1'b0;
      coefficient_i = 16'sd0;
      coefficient_q = 16'sd0;
      while (!coefficient_commit_ready)
        @(negedge engine_clk);
      coefficient_commit = 1'b1;
      @(negedge engine_clk);
      coefficient_commit = 1'b0;
    end
  endtask

  task automatic submit_candidate;
    begin
      @(negedge control_clk);
      while (!candidate_submit_ready)
        @(negedge control_clk);
      candidate_request_id = REQUEST_ID;
      candidate_center_index = CENTER_INDEX;
      candidate_center_timestamp = TIMESTAMP_BASE + CENTER_INDEX;
      candidate_submit = 1'b1;
      @(negedge control_clk);
      candidate_submit = 1'b0;
    end
  endtask

  task automatic build_expected_packet;
    reg signed [47:0] winner_ex;
    begin
      winner_ex = expected_energy(432);
      expected_word[0] = 32'h3153_5350;
      expected_word[1] = 32'h1a01_0001;
      expected_word[2] = REQUEST_ID;
      expected_word[3] = CENTER_INDEX[31:0];
      expected_word[4] = CENTER_INDEX[63:32];
      expected_word[5] = (TIMESTAMP_BASE + CENTER_INDEX);
      expected_word[6] = (TIMESTAMP_BASE + CENTER_INDEX) >> 32;
      expected_word[7] = 32'd32;
      expected_word[8] = (TIMESTAMP_BASE + 64'd432);
      expected_word[9] = (TIMESTAMP_BASE + 64'd432) >> 32;
      expected_word[10] = 32'd77;
      expected_word[11] = 32'd432;
      expected_word[12] = 32'd0;
      expected_word[13] = -32'sd432;
      expected_word[14] = 32'hffff_ffff;
      expected_word[15] = winner_ex[31:0];
      expected_word[16] = {
        {16{winner_ex[47]}}, winner_ex[47:32]
      };
      expected_word[17] = 32'd1;
      expected_word[18] = 32'd0;
      expected_word[19] = 32'd0;
      expected_word[20] = 32'd373248;
      expected_word[21] = 32'd0;
      expected_word[22] = 32'd0;
      expected_word[23] = winner_ex[31:0];
      expected_word[24] = winner_ex[47:32];
      expected_word[25] = 32'd0;
    end
  endtask

  task automatic read_and_check_word;
    input integer word_index;
    begin
      @(negedge control_clk);
      result_word_index = word_index[4:0];
      result_word_read = 1'b1;
      @(posedge control_clk);
      #1;
      if (!result_word_valid)
        fail("result word response was not valid");
      if (result_word_data !== expected_word[word_index]) begin
        $display("word=%0d expected=%08x actual=%08x",
                 word_index, expected_word[word_index], result_word_data);
        fail("end-to-end result packet mismatch");
      end
      @(negedge control_clk);
      result_word_read = 1'b0;
    end
  endtask

  always @(negedge sample_clk) begin
    if (!resetn || !sample_enable) begin
      sample_valid = 1'b0;
      sample_index = 64'd0;
      sample_timestamp = 64'd0;
      sample_i = 16'sd0;
      sample_q = 16'sd0;
      next_sample_index = 64'd0;
    end else begin
      sample_valid = 1'b1;
      sample_index = next_sample_index;
      sample_timestamp = TIMESTAMP_BASE + next_sample_index;
      sample_i = $signed(next_sample_index[15:0]);
      sample_q = -$signed(next_sample_index[15:0]);
      next_sample_index = next_sample_index + 1'b1;
    end
  end

  integer timeout;
  integer word_index;
  initial begin
    $dumpfile("build/tb_starlink_pss_reduced_tracking_core.vcd");
    $dumpvars(0, tb_starlink_pss_reduced_tracking_core);
    build_expected_packet();

    repeat (8) @(posedge engine_clk);
    @(negedge engine_clk);
    resetn = 1'b1;
    repeat (12) @(posedge engine_clk);

    load_impulse_coefficient();
    timeout = 0;
    while (!coefficient_commit_accepted && (timeout < 1000)) begin
      @(posedge engine_clk);
      timeout = timeout + 1;
    end
    if (timeout == 1000 || !active_coefficient_valid ||
        active_coefficient_generation !== 32'd77 ||
        active_coefficient_energy !== 48'sd1 ||
        coefficient_commit_rejected)
      fail("impulse coefficient activation failed");

    @(negedge sample_clk);
    sample_enable = 1'b1;
    repeat (16) @(posedge sample_clk);
    submit_candidate();

    timeout = 0;
    while (!result_available && (timeout < 100000)) begin
      @(posedge control_clk);
      timeout = timeout + 1;
    end
    if (timeout == 100000)
      fail("normalized winner was not published");

    // Exercise nonsequential software access on the composed datapath.
    for (word_index = 25; word_index >= 0; word_index = word_index - 1)
      read_and_check_word(word_index);

    if (admitted_count !== 32'd1 ||
        completed_capture_count !== 32'd1 ||
        capture_published_count !== 32'd1 ||
        engine_consumed_count !== 32'd1 ||
        reducer_processed_job_count !== 32'd1 ||
        reducer_emitted_result_count !== 32'd1 ||
        result_published_count !== 32'd1 ||
        result_consumed_count !== 32'd0)
      fail("clean composition accounting mismatch before release");
    if (queue_overrun_count !== 32'd0 || rejected_count !== 32'd0 ||
        late_count !== 32'd0 || duplicate_count !== 32'd0 ||
        overlap_count !== 32'd0 || aborted_count !== 32'd0 ||
        valid_gap_abort_count !== 32'd0 ||
        index_jump_abort_count !== 32'd0 ||
        timestamp_abort_count !== 32'd0 ||
        capture_abort_discard_count !== 32'd0 ||
        capture_buffer_overrun_count !== 32'd0 ||
        capture_protocol_error_count !== 32'd0 ||
        correlator_bound_error_count !== 32'd0 ||
        reducer_invalid_tuple_count !== 32'd0 ||
        reducer_bound_error_count !== 32'd0 ||
        reducer_protocol_error_count !== 32'd0 ||
        result_overrun_count !== 32'd0)
      fail("clean composition accumulated an error counter");

    @(negedge control_clk);
    result_release = 1'b1;
    @(posedge control_clk);
    @(negedge control_clk);
    result_release = 1'b0;
    repeat (8) @(posedge engine_clk);
    if (result_consumed_count !== 32'd1 ||
        result_bank_free !== 2'b11 || result_available)
      fail("published winner bank was not released");

    $display("REDUCED_TRACKING_PASS jobs=1 tuples=65 winner_lag=32 packet_words=26 score=absC2_over_Ex");
    $finish;
  end

endmodule
