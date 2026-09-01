`timescale 1ns/1ps

module tb_starlink_pss_candidate_scheduler;
  reg control_clk = 1'b0;
  always #5 control_clk = ~control_clk;

  reg sample_clk = 1'b0;
  reg sample_clock_run = 1'b1;
  always begin
    #7;
    if (sample_clock_run)
      sample_clk = ~sample_clk;
  end

  reg control_resetn;
  reg sample_resetn;
  reg candidate_submit;
  reg [31:0] candidate_request_id;
  reg [63:0] candidate_center_index;
  reg [63:0] candidate_center_timestamp;
  wire candidate_submit_ready;
  wire candidate_submit_accepted;
  wire [2:0] candidate_queue_room;
  wire [31:0] queue_overrun_count;

  reg sample_enable;
  reg sample_valid;
  reg [63:0] sample_index;
  reg [63:0] sample_timestamp;
  reg signed [15:0] sample_i;
  reg signed [15:0] sample_q;

  wire capture_valid;
  wire capture_start;
  wire capture_done;
  wire capture_abort;
  wire [7:0] capture_slot;
  wire [31:0] capture_request_id;
  wire [63:0] capture_center_index;
  wire [63:0] capture_center_timestamp;
  wire [63:0] capture_sample_index;
  wire [63:0] capture_sample_timestamp;
  wire signed [15:0] capture_sample_i;
  wire signed [15:0] capture_sample_q;
  wire candidate_pending;
  wire capture_active;
  wire [31:0] admitted_count;
  wire [31:0] completed_count;
  wire [31:0] rejected_count;
  wire [31:0] late_count;
  wire [31:0] duplicate_count;
  wire [31:0] overlap_count;
  wire [31:0] aborted_count;
  wire [31:0] valid_gap_abort_count;
  wire [31:0] index_jump_abort_count;
  wire [31:0] timestamp_abort_count;

  starlink_pss_candidate_scheduler dut (
    .i_control_clk                      (control_clk),
    .i_control_resetn                   (control_resetn),
    .i_candidate_submit                 (candidate_submit),
    .i_candidate_request_id             (candidate_request_id),
    .i_candidate_center_index           (candidate_center_index),
    .i_candidate_center_timestamp       (candidate_center_timestamp),
    .o_candidate_submit_ready           (candidate_submit_ready),
    .o_candidate_submit_accepted        (candidate_submit_accepted),
    .o_candidate_queue_room             (candidate_queue_room),
    .o_queue_overrun_count              (queue_overrun_count),
    .i_sample_clk                       (sample_clk),
    .i_sample_resetn                    (sample_resetn),
    .i_sample_enable                    (sample_enable),
    .i_sample_valid                     (sample_valid),
    .i_sample_index                     (sample_index),
    .i_sample_timestamp                 (sample_timestamp),
    .i_sample_i                         (sample_i),
    .i_sample_q                         (sample_q),
    .o_capture_valid                    (capture_valid),
    .o_capture_start                    (capture_start),
    .o_capture_done                     (capture_done),
    .o_capture_abort                    (capture_abort),
    .o_capture_slot                     (capture_slot),
    .o_capture_request_id               (capture_request_id),
    .o_capture_center_index             (capture_center_index),
    .o_capture_center_timestamp         (capture_center_timestamp),
    .o_capture_sample_index             (capture_sample_index),
    .o_capture_sample_timestamp         (capture_sample_timestamp),
    .o_capture_sample_i                 (capture_sample_i),
    .o_capture_sample_q                 (capture_sample_q),
    .o_candidate_pending                (candidate_pending),
    .o_capture_active                   (capture_active),
    .o_admitted_count                   (admitted_count),
    .o_completed_count                  (completed_count),
    .o_rejected_count                   (rejected_count),
    .o_late_count                       (late_count),
    .o_duplicate_count                  (duplicate_count),
    .o_overlap_count                    (overlap_count),
    .o_aborted_count                    (aborted_count),
    .o_valid_gap_abort_count            (valid_gap_abort_count),
    .o_index_jump_abort_count           (index_jump_abort_count),
    .o_timestamp_abort_count            (timestamp_abort_count)
  );

  function automatic [63:0] timestamp_for_index;
    input [63:0] index;
    begin
      timestamp_for_index = index ^ 64'hd39a_72c5_8000_011d;
    end
  endfunction

  function automatic [15:0] i_for_index;
    input [63:0] index;
    begin
      i_for_index = index[15:0] ^ 16'h55aa;
    end
  endfunction

  function automatic [15:0] q_for_index;
    input [63:0] index;
    begin
      q_for_index = index[31:16] ^ 16'ha55a;
    end
  endfunction

  reg drive_samples;
  reg inject_gap;
  reg inject_jump;
  reg [63:0] jump_amount;
  reg [63:0] next_drive_index;

  always @(negedge sample_clk) begin
    if (!sample_resetn || !drive_samples) begin
      sample_valid = 1'b0;
    end else if (inject_gap) begin
      sample_valid = 1'b0;
      inject_gap = 1'b0;
    end else begin
      if (inject_jump) begin
        next_drive_index = next_drive_index + jump_amount;
        inject_jump = 1'b0;
      end
      sample_valid = 1'b1;
      sample_index = next_drive_index;
      sample_timestamp = timestamp_for_index(next_drive_index);
      sample_i = $signed(i_for_index(next_drive_index));
      sample_q = $signed(q_for_index(next_drive_index));
      next_drive_index = next_drive_index + 1'b1;
    end
  end

  reg expected_capture;
  reg expected_bad_center_timestamp;
  reg [31:0] expected_request_id;
  reg [63:0] expected_center_index;
  integer capture_beat_count;
  integer observed_complete_jobs;
  integer observed_aborts;

  always @(negedge sample_clk) begin
    if (!sample_resetn) begin
      capture_beat_count = 0;
      observed_complete_jobs = 0;
      observed_aborts = 0;
    end else begin
      if (capture_valid) begin
        if (!expected_capture)
          $fatal(1, "unexpected capture beat request=%0d slot=%0d",
                 capture_request_id, capture_slot);
        if ((capture_request_id !== expected_request_id) ||
            (capture_center_index !== expected_center_index) ||
            (capture_slot !== capture_beat_count[7:0]) ||
            (capture_sample_index !==
             expected_center_index - 64'd32 + capture_beat_count) ||
            ($signed(capture_sample_i) !==
             $signed(i_for_index(capture_sample_index))) ||
            ($signed(capture_sample_q) !==
             $signed(q_for_index(capture_sample_index))))
          $fatal(1,
                 "capture tuple mismatch request=%0d slot=%0d index=%h expected_request=%0d expected_slot=%0d expected_index=%h",
                 capture_request_id, capture_slot, capture_sample_index,
                 expected_request_id, capture_beat_count,
                 expected_center_index - 64'd32 + capture_beat_count);
        if (!(capture_abort && expected_bad_center_timestamp) &&
            (capture_sample_timestamp !==
             timestamp_for_index(capture_sample_index)))
          $fatal(1, "capture timestamp mismatch at slot %0d", capture_slot);
        if ((capture_slot == 0) != capture_start)
          $fatal(1, "capture_start did not identify only slot zero");
        capture_beat_count = capture_beat_count + 1;
      end else if (capture_start) begin
        $fatal(1, "capture_start asserted without capture_valid");
      end

      if (capture_done) begin
        if (!capture_valid || (capture_beat_count != 130) || capture_abort)
          $fatal(1, "capture_done did not close exactly 130 beats");
        observed_complete_jobs = observed_complete_jobs + 1;
        capture_beat_count = 0;
        expected_capture = 1'b0;
        expected_bad_center_timestamp = 1'b0;
      end

      if (capture_abort) begin
        if (capture_done)
          $fatal(1, "capture cannot abort and complete together");
        observed_aborts = observed_aborts + 1;
        capture_beat_count = 0;
        expected_capture = 1'b0;
        expected_bad_center_timestamp = 1'b0;
      end
    end
  end

  task automatic pulse_candidate;
    input [31:0] request_id;
    input [63:0] center_index;
    input [63:0] center_timestamp;
    input integer expect_accept;
    begin
      @(negedge control_clk);
      candidate_request_id = request_id;
      candidate_center_index = center_index;
      candidate_center_timestamp = center_timestamp;
      candidate_submit = 1'b1;
      @(negedge control_clk);
      if (candidate_submit_accepted !== expect_accept[0])
        $fatal(1,
               "submission result mismatch request=%0d ready=%0d accepted=%0d expected=%0d",
               request_id, candidate_submit_ready,
               candidate_submit_accepted, expect_accept);
      candidate_submit = 1'b0;
    end
  endtask

  task automatic reset_domains;
    input [63:0] first_index;
    begin
      candidate_submit = 1'b0;
      drive_samples = 1'b0;
      inject_gap = 1'b0;
      inject_jump = 1'b0;
      jump_amount = 64'd0;
      sample_enable = 1'b0;
      expected_capture = 1'b0;
      expected_bad_center_timestamp = 1'b0;
      control_resetn = 1'b0;
      sample_resetn = 1'b0;
      repeat (5) @(posedge control_clk);
      repeat (5) @(posedge sample_clk);
      @(negedge control_clk);
      control_resetn = 1'b1;
      @(negedge sample_clk);
      next_drive_index = first_index;
      sample_resetn = 1'b1;
    end
  endtask

  task automatic begin_capture_expectation;
    input [31:0] request_id;
    input [63:0] center_index;
    input integer bad_center_timestamp;
    begin
      expected_capture = 1'b1;
      expected_request_id = request_id;
      expected_center_index = center_index;
      expected_bad_center_timestamp = bad_center_timestamp[0];
      capture_beat_count = 0;
    end
  endtask

  task automatic wait_sample_counter;
    input integer selector;
    input [31:0] expected;
    integer timeout;
    reg [31:0] observed;
    begin
      timeout = 0;
      observed = 32'hffff_ffff;
      while ((observed != expected) && (timeout < 20000)) begin
        @(negedge sample_clk);
        case (selector)
          0: observed = admitted_count;
          1: observed = completed_count;
          2: observed = rejected_count;
          3: observed = aborted_count;
          4: observed = valid_gap_abort_count;
          5: observed = index_jump_abort_count;
          6: observed = timestamp_abort_count;
          default: observed = 32'hffff_ffff;
        endcase
        timeout = timeout + 1;
      end
      if (observed != expected)
        $fatal(1, "counter selector %0d got %0d expected %0d",
               selector, observed, expected);
    end
  endtask

  reg [63:0] center_1;
  reg [63:0] center_2;
  reg [63:0] center_timestamp_bad;
  reg [63:0] center_gap_pending;
  reg [63:0] center_gap_active;
  reg [63:0] center_index_jump;
  reg [63:0] center_disable;
  integer queue_index;

  initial begin
    control_resetn = 1'b0;
    sample_resetn = 1'b0;
    candidate_submit = 1'b0;
    candidate_request_id = 32'd0;
    candidate_center_index = 64'd0;
    candidate_center_timestamp = 64'd0;
    sample_enable = 1'b0;
    sample_valid = 1'b0;
    sample_index = 64'd0;
    sample_timestamp = 64'd0;
    sample_i = 16'sd0;
    sample_q = 16'sd0;
    drive_samples = 1'b0;
    inject_gap = 1'b0;
    inject_jump = 1'b0;
    jump_amount = 64'd0;
    next_drive_index = 64'd0;
    expected_capture = 1'b0;
    expected_bad_center_timestamp = 1'b0;
    expected_request_id = 32'd0;
    expected_center_index = 64'd0;

    // The ADI FIFO's ADDRESS_WIDTH=3 contract has seven usable entries.
    // Freeze the destination clock, fill all seven, and prove one additional
    // MMIO pulse becomes exactly one overrun rather than a hidden command.
    reset_domains(64'd1000);
    @(negedge sample_clk);
    sample_clock_run = 1'b0;
    for (queue_index = 0; queue_index < 7; queue_index = queue_index + 1)
      pulse_candidate(32'd100 + queue_index, 64'd5000 + queue_index * 300,
                      timestamp_for_index(64'd5000 + queue_index * 300), 1);
    pulse_candidate(32'd199, 64'd9000, timestamp_for_index(64'd9000), 0);
    if ((queue_overrun_count != 1) || candidate_submit_ready ||
        (candidate_queue_room != 0))
      $fatal(1, "seven-entry FIFO/overrun contract failed");
    sample_clock_run = 1'b1;
    wait_sample_counter(2, 32'd7);
    wait_sample_counter(3, 32'd7);

    // Fresh counters for functional scheduling.  Two chronological commands
    // are submitted before the first capture, proving queued operation across
    // unrelated clocks and exact output ordering.
    reset_domains(64'd10000);
    sample_enable = 1'b1;
    drive_samples = 1'b1;
    repeat (8) @(negedge sample_clk);
    center_1 = next_drive_index + 64'd180;
    center_2 = center_1 + 64'd400;
    begin_capture_expectation(32'd1, center_1, 0);
    pulse_candidate(32'd1, center_1, timestamp_for_index(center_1), 1);
    pulse_candidate(32'd2, center_2, timestamp_for_index(center_2), 1);
    wait_sample_counter(1, 32'd1);
    begin_capture_expectation(32'd2, center_2, 0);
    wait_sample_counter(1, 32'd2);
    if ((admitted_count != 2) || (observed_complete_jobs != 2))
      $fatal(1, "queued chronological captures did not complete exactly");

    // Rejection priority is frozen: exact center duplicate, overlapping or
    // out-of-order window, then an otherwise nonoverlapping late request.
    pulse_candidate(32'd3, center_2, timestamp_for_index(center_2), 1);
    wait_sample_counter(2, 32'd1);
    if (duplicate_count != 1)
      $fatal(1, "duplicate request was not classified first");
    pulse_candidate(32'd4, center_2 + 64'd100,
                    timestamp_for_index(center_2 + 64'd100), 1);
    wait_sample_counter(2, 32'd2);
    if (overlap_count != 1)
      $fatal(1, "overlap request was not classified");
    pulse_candidate(32'd5, next_drive_index + 64'd40,
                    timestamp_for_index(next_drive_index + 64'd40), 1);
    wait_sample_counter(2, 32'd3);
    if (late_count != 1)
      $fatal(1, "insufficient-lead request was not classified late");

    // A center timestamp mismatch aborts after emitting the center beat.  The
    // downstream writer is required to discard all partial beats on abort.
    center_timestamp_bad = center_2 + 64'd300;
    begin_capture_expectation(32'd6, center_timestamp_bad, 1);
    pulse_candidate(32'd6, center_timestamp_bad,
                    timestamp_for_index(center_timestamp_bad) ^ 64'd1, 1);
    wait_sample_counter(6, 32'd1);

    // A valid gap must flush both a pending request and an active capture.
    center_gap_pending = center_timestamp_bad + 64'd300;
    pulse_candidate(32'd7, center_gap_pending,
                    timestamp_for_index(center_gap_pending), 1);
    wait_sample_counter(0, 32'd4);
    @(posedge sample_clk);
    inject_gap = 1'b1;
    wait_sample_counter(4, 32'd1);

    center_gap_active = center_gap_pending + 64'd300;
    begin_capture_expectation(32'd8, center_gap_active, 0);
    pulse_candidate(32'd8, center_gap_active,
                    timestamp_for_index(center_gap_active), 1);
    wait (capture_active);
    repeat (7) @(posedge sample_clk);
    inject_gap = 1'b1;
    wait_sample_counter(4, 32'd2);

    // A full-width accepted-index jump during capture is separately counted.
    center_index_jump = center_gap_active + 64'd300;
    begin_capture_expectation(32'd9, center_index_jump, 0);
    pulse_candidate(32'd9, center_index_jump,
                    timestamp_for_index(center_index_jump), 1);
    wait (capture_active);
    repeat (9) @(posedge sample_clk);
    inject_jump = 1'b1;
    jump_amount = 64'd3;
    wait_sample_counter(5, 32'd1);

    // Disable flushes an admitted request and drains later queued commands as
    // rejected/aborted work rather than silently retaining stale centers.
    center_disable = center_index_jump + 64'd300;
    pulse_candidate(32'd10, center_disable,
                    timestamp_for_index(center_disable), 1);
    wait_sample_counter(0, 32'd7);
    @(negedge sample_clk);
    sample_enable = 1'b0;
    wait_sample_counter(3, 32'd5);

    if ((completed_count != 2) || (rejected_count != 3) ||
        (late_count != 1) || (duplicate_count != 1) ||
        (overlap_count != 1) || (aborted_count != 5) ||
        (valid_gap_abort_count != 2) ||
        (index_jump_abort_count != 1) ||
        (timestamp_abort_count != 1) ||
        (queue_overrun_count != 0))
      $fatal(1,
             "functional counters mismatch admitted=%0d completed=%0d rejected=%0d late=%0d duplicate=%0d overlap=%0d aborted=%0d gap=%0d jump=%0d timestamp=%0d overrun=%0d",
             admitted_count, completed_count, rejected_count, late_count,
             duplicate_count, overlap_count, aborted_count,
             valid_gap_abort_count, index_jump_abort_count,
             timestamp_abort_count, queue_overrun_count);

    // A clean epoch independently proves modulo-2^64 ordering.  The command
    // is admitted before wrap, starts at zero, and ends at center+97.
    reset_domains(64'hffff_ffff_ffff_ff00);
    sample_enable = 1'b1;
    drive_samples = 1'b1;
    repeat (8) @(negedge sample_clk);
    begin_capture_expectation(32'd20, 64'h0000_0000_0000_0020, 0);
    pulse_candidate(32'd20, 64'h0000_0000_0000_0020,
                    timestamp_for_index(64'h0000_0000_0000_0020), 1);
    wait_sample_counter(1, 32'd1);
    if ((admitted_count != 1) || (completed_count != 1) ||
        (rejected_count != 0) || (aborted_count != 0) ||
        (observed_complete_jobs != 1))
      $fatal(1, "full-width wrap capture did not complete cleanly");

    $display("CANDIDATE_SCHEDULER_PASS queue_capacity=7 completed_captures=3 wrap_captures=1 rejected_classes=3 abort_classes=3");
    $finish;
  end

  integer watchdog_control_cycles = 0;
  always @(posedge control_clk) begin
    watchdog_control_cycles <= watchdog_control_cycles + 1;
    if (watchdog_control_cycles > 250000)
      $fatal(1, "candidate scheduler testbench watchdog expired");
  end

endmodule
