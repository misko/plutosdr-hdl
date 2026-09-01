`timescale 1ns/1ps

module tb_starlink_pss_tracking_core;

  localparam [63:0] TIMESTAMP_BASE = 64'h0000_0001_0000_0000;

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

  wire result_valid;
  reg result_ready = 1'b0;
  wire [31:0] result_request_id;
  wire [63:0] result_center_index;
  wire [63:0] result_center_timestamp;
  wire signed [6:0] result_lag;
  wire [63:0] result_timestamp;
  wire [31:0] result_coefficient_generation;
  wire signed [47:0] result_c_re;
  wire signed [47:0] result_c_im;
  wire signed [47:0] result_ex;
  wire signed [47:0] result_eh;
  wire [8:0] result_saturation_events;

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
  wire [31:0] bound_error_count;

  starlink_pss_tracking_core dut (
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
    .o_result_valid                    (result_valid),
    .i_result_ready                    (result_ready),
    .o_result_request_id               (result_request_id),
    .o_result_center_index             (result_center_index),
    .o_result_center_timestamp         (result_center_timestamp),
    .o_result_lag                      (result_lag),
    .o_result_timestamp                (result_timestamp),
    .o_result_coefficient_generation   (result_coefficient_generation),
    .o_result_c_re                     (result_c_re),
    .o_result_c_im                     (result_c_im),
    .o_result_ex                       (result_ex),
    .o_result_eh                       (result_eh),
    .o_result_saturation_events        (result_saturation_events),
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
    .o_bound_error_count               (bound_error_count)
  );

  task automatic fail;
    input [1023:0] message;
    begin
      $display("TRACKING_CORE_FAIL %0s", message);
      $fatal(1);
    end
  endtask

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
    input [31:0] request_id;
    input [63:0] center_index;
    begin
      @(negedge control_clk);
      while (!candidate_submit_ready)
        @(negedge control_clk);
      candidate_request_id = request_id;
      candidate_center_index = center_index;
      candidate_center_timestamp = TIMESTAMP_BASE + center_index;
      candidate_submit = 1'b1;
      @(negedge control_clk);
      candidate_submit = 1'b0;
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

  integer result_cycle_count = 0;
  always @(negedge engine_clk) begin
    if (!resetn) begin
      result_ready = 1'b0;
      result_cycle_count = 0;
    end else begin
      result_cycle_count = result_cycle_count + 1;
      result_ready = (result_cycle_count % 11 != 0) &&
                     (result_cycle_count % 11 != 1) &&
                     (result_cycle_count % 11 != 2);
    end
  end

  integer observed_result_count = 0;
  integer expected_job;
  integer expected_result_index;
  integer expected_lag;
  integer expected_first_index;
  reg [31:0] expected_request;
  reg [63:0] expected_center;

  always @(posedge engine_clk) begin
    if (resetn && result_valid && result_ready) begin
      expected_job = observed_result_count / 65;
      expected_result_index = observed_result_count % 65;
      expected_lag = expected_result_index - 32;
      expected_center = (expected_job == 0) ? 64'd400 : 64'd596;
      expected_request = (expected_job == 0) ?
          32'h1111_0001 : 32'h2222_0002;
      expected_first_index = expected_center + expected_lag;

      if (expected_job > 1)
        fail("buffer-overrun capture produced results");
      if (result_request_id !== expected_request)
        fail("result request/order mismatch");
      if (result_center_index !== expected_center)
        fail("result center index mismatch");
      if (result_center_timestamp !== TIMESTAMP_BASE + expected_center)
        fail("result center timestamp mismatch");
      if (result_lag !== expected_lag)
        fail("result lag mismatch");
      if (result_timestamp !== TIMESTAMP_BASE + expected_first_index)
        fail("stored first-tap timestamp mismatch");
      if (result_coefficient_generation !== 32'd77)
        fail("coefficient generation mismatch");
      if (result_c_re !== expected_first_index)
        fail("impulse-bank real correlation mismatch");
      if (result_c_im !== -expected_first_index)
        fail("impulse-bank imaginary correlation mismatch");
      if (result_ex !== expected_energy(expected_first_index))
        fail("sliding sample energy mismatch");
      if (result_eh !== 48'sd1)
        fail("cached coefficient energy mismatch");
      if (result_saturation_events !== 9'd0)
        fail("legal tuple reported saturation");

      observed_result_count = observed_result_count + 1;
    end
  end

  integer timeout;
  initial begin
    $dumpfile("build/tb_starlink_pss_tracking_core.vcd");
    $dumpvars(0, tb_starlink_pss_tracking_core);

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
    if (timeout == 1000)
      fail("coefficient commit did not complete");
    if (!active_coefficient_valid ||
        active_coefficient_generation !== 32'd77 ||
        active_coefficient_energy !== 48'sd1 ||
        coefficient_commit_rejected)
      fail("impulse coefficient activation mismatch");

    @(negedge sample_clk);
    sample_enable = 1'b1;
    repeat (16) @(posedge sample_clk);

    submit_candidate(32'h1111_0001, 64'd400);
    // The 196-sample center spacing is legal and leaves 65 samples of lead
    // when each queued successor is admitted.  At this deliberately
    // accelerated test cadence, it also fills both banks before the first
    // 130-beat engine copy can return ownership.
    submit_candidate(32'h2222_0002, 64'd596);
    submit_candidate(32'h3333_0003, 64'd792);

    timeout = 0;
    while ((observed_result_count < 130) && (timeout < 30000)) begin
      @(posedge engine_clk);
      timeout = timeout + 1;
    end
    if (timeout == 30000)
      fail("two published jobs did not produce 130 tuples");

    repeat (1000) @(posedge engine_clk);
    if (observed_result_count != 130)
      fail("dropped third job later leaked a result");

    if (admitted_count !== 32'd3 || completed_capture_count !== 32'd3)
      fail("scheduler did not complete all three commanded windows");
    if (capture_published_count !== 32'd2 ||
        capture_buffer_overrun_count !== 32'd1 ||
        engine_consumed_count !== 32'd2)
      fail("double-buffer publication accounting mismatch");
    if (queue_overrun_count !== 32'd0 || rejected_count !== 32'd0 ||
        late_count !== 32'd0 || duplicate_count !== 32'd0 ||
        overlap_count !== 32'd0 || aborted_count !== 32'd0 ||
        valid_gap_abort_count !== 32'd0 ||
        index_jump_abort_count !== 32'd0 ||
        timestamp_abort_count !== 32'd0 ||
        capture_abort_discard_count !== 32'd0 ||
        capture_protocol_error_count !== 32'd0 ||
        bound_error_count !== 32'd0)
      fail("clean end-to-end run accumulated an error counter");
    if (capture_bank_free !== 2'b11)
      fail("capture banks were not returned after processing");

    $display("TRACKING_CORE_PASS commands=3 published_jobs=2 dropped_jobs=1 tuples=130 clocks=3 cached_eh=1 sliding_ex=1");
    $finish;
  end

endmodule
