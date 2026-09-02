`timescale 1ns/1ps

module tb_starlink_pss_overlap_scheduler_lifecycle;

  reg clk = 1'b0;
  reg resetn = 1'b0;

  reg q_enable = 1'b0;
  reg q_sample_valid = 1'b0;
  reg q_sample_gap = 1'b0;
  reg signed [15:0] q_sample_i = 0;
  reg signed [15:0] q_sample_q = 0;
  reg [63:0] q_sample_index = 0;
  reg q_fft_ready = 1'b0;
  wire q_fft_valid;
  wire signed [15:0] q_fft_i;
  wire signed [15:0] q_fft_q;
  wire [8:0] q_fft_position;
  wire q_fft_last;
  wire [63:0] q_fft_block_start_index;
  wire q_flush_pulse;
  wire q_gap_pulse;
  wire q_index_error_pulse;
  wire q_overflow_pulse;
  wire q_block_queued_pulse;
  wire q_block_complete_pulse;
  wire q_busy;
  wire [63:0] q_segment_sample_count;
  wire [1:0] q_queued_block_count;

  reg r_enable = 1'b0;
  reg r_sample_valid = 1'b0;
  reg signed [15:0] r_sample_i = 0;
  reg signed [15:0] r_sample_q = 0;
  reg [63:0] r_sample_index = 0;
  reg r_fft_ready = 1'b0;
  wire r_fft_valid;
  wire signed [15:0] r_fft_i;
  wire signed [15:0] r_fft_q;
  wire [8:0] r_fft_position;
  wire r_fft_last;
  wire [63:0] r_fft_block_start_index;
  wire r_flush_pulse;
  wire r_gap_pulse;
  wire r_index_error_pulse;
  wire r_overflow_pulse;
  wire r_block_queued_pulse;
  wire r_block_complete_pulse;
  wire r_busy;
  wire [63:0] r_segment_sample_count;
  wire [3:0] r_queued_block_count;

  integer sample_number;
  integer timeout;
  integer q_observed_blocks = 0;
  integer q_observed_position = 0;
  integer q_flush_pulses = 0;
  integer q_gap_pulses = 0;
  integer q_index_error_pulses = 0;
  integer q_overflow_pulses = 0;
  integer q_queued_pulses = 0;
  integer q_complete_pulses = 0;
  integer r_observed_blocks = 0;
  integer r_observed_position = 0;
  integer r_flush_pulses = 0;
  integer r_overflow_pulses = 0;
  integer r_queued_pulses = 0;
  integer r_complete_pulses = 0;
  reg [63:0] q_expected_starts [0:5];

  always #5 clk = ~clk;

  // A shallow queue reaches descriptor overflow before retention overflow.
  starlink_pss_overlap_scheduler #(
    .FFT_SAMPLES      (16),
    .OVERLAP_SAMPLES  (5),
    .RING_SAMPLES     (64),
    .BLOCK_QUEUE_DEPTH(2)
  ) queue_dut (
    .clk                   (clk),
    .resetn                (resetn),
    .enable                (q_enable),
    .sample_valid          (q_sample_valid),
    .sample_gap            (q_sample_gap),
    .sample_i              (q_sample_i),
    .sample_q              (q_sample_q),
    .sample_index          (q_sample_index),
    .fft_valid             (q_fft_valid),
    .fft_ready             (q_fft_ready),
    .fft_i                 (q_fft_i),
    .fft_q                 (q_fft_q),
    .fft_position          (q_fft_position),
    .fft_last              (q_fft_last),
    .fft_block_start_index (q_fft_block_start_index),
    .flush_pulse           (q_flush_pulse),
    .gap_pulse             (q_gap_pulse),
    .index_error_pulse     (q_index_error_pulse),
    .overflow_pulse        (q_overflow_pulse),
    .block_queued_pulse    (q_block_queued_pulse),
    .block_complete_pulse  (q_block_complete_pulse),
    .busy                  (q_busy),
    .segment_sample_count  (q_segment_sample_count),
    .queued_block_count    (q_queued_block_count)
  );

  // A deeper queue isolates the ring-retention fail-closed path.
  starlink_pss_overlap_scheduler #(
    .FFT_SAMPLES      (8),
    .OVERLAP_SAMPLES  (3),
    .RING_SAMPLES     (16),
    .BLOCK_QUEUE_DEPTH(8)
  ) retention_dut (
    .clk                   (clk),
    .resetn                (resetn),
    .enable                (r_enable),
    .sample_valid          (r_sample_valid),
    .sample_gap            (1'b0),
    .sample_i              (r_sample_i),
    .sample_q              (r_sample_q),
    .sample_index          (r_sample_index),
    .fft_valid             (r_fft_valid),
    .fft_ready             (r_fft_ready),
    .fft_i                 (r_fft_i),
    .fft_q                 (r_fft_q),
    .fft_position          (r_fft_position),
    .fft_last              (r_fft_last),
    .fft_block_start_index (r_fft_block_start_index),
    .flush_pulse           (r_flush_pulse),
    .gap_pulse             (r_gap_pulse),
    .index_error_pulse     (r_index_error_pulse),
    .overflow_pulse        (r_overflow_pulse),
    .block_queued_pulse    (r_block_queued_pulse),
    .block_complete_pulse  (r_block_complete_pulse),
    .busy                  (r_busy),
    .segment_sample_count  (r_segment_sample_count),
    .queued_block_count    (r_queued_block_count)
  );

  task automatic fail(input string message);
    begin
      $display("OVERLAP_LIFECYCLE_FAIL %0s", message);
      $fatal(1);
    end
  endtask

  function automatic [15:0] encoded_i(input [63:0] index);
    encoded_i = index[15:0];
  endfunction

  function automatic [15:0] encoded_q(input [63:0] index);
    encoded_q = ~index[15:0];
  endfunction

  task automatic reset_both;
    begin
      @(negedge clk);
      resetn = 1'b0;
      q_enable = 1'b0;
      q_sample_valid = 1'b0;
      q_sample_gap = 1'b0;
      r_enable = 1'b0;
      r_sample_valid = 1'b0;
      repeat (2) @(negedge clk);
      resetn = 1'b1;
    end
  endtask

  task automatic q_send(input [63:0] index, input gap);
    begin
      @(negedge clk);
      q_sample_index = index;
      q_sample_i = index[15:0];
      q_sample_q = ~index[15:0];
      q_sample_gap = gap;
      q_sample_valid = 1'b1;
      @(negedge clk);
      q_sample_valid = 1'b0;
      q_sample_gap = 1'b0;
    end
  endtask

  task automatic r_send(input [63:0] index);
    begin
      @(negedge clk);
      r_sample_index = index;
      r_sample_i = index[15:0];
      r_sample_q = ~index[15:0];
      r_sample_valid = 1'b1;
      @(negedge clk);
      r_sample_valid = 1'b0;
    end
  endtask

  task automatic wait_q_idle;
    begin
      timeout = 0;
      while (q_busy && timeout < 2000) begin
        @(negedge clk);
        timeout = timeout + 1;
      end
      if (timeout == 2000)
        fail("queue DUT did not drain");
      repeat (2) @(negedge clk);
    end
  endtask

  task automatic wait_r_idle;
    begin
      timeout = 0;
      while (r_busy && timeout < 2000) begin
        @(negedge clk);
        timeout = timeout + 1;
      end
      if (timeout == 2000)
        fail("retention DUT did not drain");
      repeat (2) @(negedge clk);
    end
  endtask

  always @(posedge clk) begin
    if (resetn) begin
      if (q_flush_pulse)
        q_flush_pulses <= q_flush_pulses + 1;
      if (q_gap_pulse)
        q_gap_pulses <= q_gap_pulses + 1;
      if (q_index_error_pulse)
        q_index_error_pulses <= q_index_error_pulses + 1;
      if (q_overflow_pulse)
        q_overflow_pulses <= q_overflow_pulses + 1;
      if (q_block_queued_pulse)
        q_queued_pulses <= q_queued_pulses + 1;
      if (q_block_complete_pulse)
        q_complete_pulses <= q_complete_pulses + 1;

      if (q_fft_valid && q_fft_ready) begin
        if (q_observed_blocks > 5)
          fail("unexpected queue-DUT block");
        if (q_fft_block_start_index !== q_expected_starts[q_observed_blocks])
          fail("queue-DUT block start mismatch");
        if (q_fft_position !== q_observed_position)
          fail("queue-DUT position mismatch");
        if (q_fft_i !== encoded_i(q_expected_starts[q_observed_blocks] +
                                  q_observed_position) ||
            q_fft_q !== encoded_q(q_expected_starts[q_observed_blocks] +
                                  q_observed_position))
          fail("queue-DUT sample mismatch");
        if (q_fft_last !== (q_observed_position == 15))
          fail("queue-DUT last mismatch");
        if (q_observed_position == 15) begin
          q_observed_position <= 0;
          q_observed_blocks <= q_observed_blocks + 1;
        end else begin
          q_observed_position <= q_observed_position + 1;
        end
      end

      if (r_flush_pulse)
        r_flush_pulses <= r_flush_pulses + 1;
      if (r_overflow_pulse)
        r_overflow_pulses <= r_overflow_pulses + 1;
      if (r_block_queued_pulse)
        r_queued_pulses <= r_queued_pulses + 1;
      if (r_block_complete_pulse)
        r_complete_pulses <= r_complete_pulses + 1;

      if (r_fft_valid && r_fft_ready) begin
        if (r_observed_blocks != 0)
          fail("unexpected retention-DUT block");
        if (r_fft_block_start_index !== 64'd8016)
          fail("retention-DUT restart index mismatch");
        if (r_fft_position !== r_observed_position)
          fail("retention-DUT position mismatch");
        if (r_fft_i !== encoded_i(64'd8016 + r_observed_position) ||
            r_fft_q !== encoded_q(64'd8016 + r_observed_position))
          fail("retention-DUT sample mismatch");
        if (r_fft_last !== (r_observed_position == 7))
          fail("retention-DUT last mismatch");
        if (r_observed_position == 7) begin
          r_observed_position <= 0;
          r_observed_blocks <= r_observed_blocks + 1;
        end else begin
          r_observed_position <= r_observed_position + 1;
        end
      end
    end
  end

  initial begin
    $dumpfile("build/tb_starlink_pss_overlap_scheduler_lifecycle.vcd");
    $dumpvars(0, tb_starlink_pss_overlap_scheduler_lifecycle);

    q_expected_starts[0] = 64'd1000;
    q_expected_starts[1] = 64'd1011;
    q_expected_starts[2] = 64'd2000;
    q_expected_starts[3] = 64'd3048;
    q_expected_starts[4] = 64'd5000;
    q_expected_starts[5] = 64'd7000;

    reset_both();

    // Normal overlap cadence: starts 0 and 11 from 27 retained samples.
    q_enable = 1'b1;
    q_fft_ready = 1'b1;
    for (sample_number = 0; sample_number < 27; sample_number = sample_number + 1)
      q_send(64'd1000 + sample_number, 1'b0);
    wait_q_idle();

    // Disable aborts a presented but unaccepted frame. Re-enable starts with
    // empty history, so only the subsequent complete frame may be observed.
    reset_both();
    q_enable = 1'b1;
    q_fft_ready = 1'b0;
    for (sample_number = 0; sample_number < 16; sample_number = sample_number + 1)
      q_send(64'd1500 + sample_number, 1'b0);
    timeout = 0;
    while (!q_fft_valid && timeout < 100) begin
      @(negedge clk);
      timeout = timeout + 1;
    end
    if (timeout == 100)
      fail("disable test never presented an FFT sample");
    q_enable = 1'b0;
    repeat (2) @(negedge clk);
    q_enable = 1'b1;
    q_fft_ready = 1'b1;
    for (sample_number = 0; sample_number < 16; sample_number = sample_number + 1)
      q_send(64'd2000 + sample_number, 1'b0);
    wait_q_idle();

    // With ready held low, one active frame plus two queued descriptors fill
    // all capacity. The next descriptor fails closed and its final input
    // sample becomes sample zero of a fresh segment.
    reset_both();
    q_enable = 1'b1;
    q_fft_ready = 1'b0;
    for (sample_number = 0; sample_number < 49; sample_number = sample_number + 1)
      q_send(64'd3000 + sample_number, 1'b0);
    repeat (2) @(negedge clk);
    if (q_overflow_pulses != 1 || q_segment_sample_count != 1)
      fail("descriptor overflow did not restart at its current sample");
    q_fft_ready = 1'b1;
    for (sample_number = 49; sample_number < 64; sample_number = sample_number + 1)
      q_send(64'd3000 + sample_number, 1'b0);
    wait_q_idle();

    // Absolute-index jumps and explicit gap tags independently invalidate
    // partial histories and retain the current sample as the new origin.
    reset_both();
    q_enable = 1'b1;
    q_fft_ready = 1'b1;
    for (sample_number = 0; sample_number < 8; sample_number = sample_number + 1)
      q_send(64'd4000 + sample_number, 1'b0);
    q_send(64'd5000, 1'b0);
    for (sample_number = 1; sample_number < 16; sample_number = sample_number + 1)
      q_send(64'd5000 + sample_number, 1'b0);
    wait_q_idle();

    reset_both();
    q_enable = 1'b1;
    q_fft_ready = 1'b1;
    for (sample_number = 0; sample_number < 8; sample_number = sample_number + 1)
      q_send(64'd6000 + sample_number, 1'b0);
    q_send(64'd7000, 1'b1);
    for (sample_number = 1; sample_number < 16; sample_number = sample_number + 1)
      q_send(64'd7000 + sample_number, 1'b0);
    wait_q_idle();

    // This second geometry has enough descriptor slots that the oldest
    // unread frame reaches ring retention first.
    reset_both();
    r_enable = 1'b1;
    r_fft_ready = 1'b0;
    for (sample_number = 0; sample_number < 17; sample_number = sample_number + 1)
      r_send(64'd8000 + sample_number);
    repeat (2) @(negedge clk);
    if (r_overflow_pulses != 1 || r_segment_sample_count != 1)
      fail("ring retention overflow did not restart at its current sample");
    r_fft_ready = 1'b1;
    for (sample_number = 17; sample_number < 24; sample_number = sample_number + 1)
      r_send(64'd8000 + sample_number);
    wait_r_idle();

    if (q_observed_blocks != 6 || q_observed_position != 0 ||
        q_complete_pulses != 6)
      fail("queue-DUT completed-block accounting mismatch");
    if (q_flush_pulses != 4 || q_gap_pulses != 1 ||
        q_index_error_pulses != 1 || q_overflow_pulses != 1)
      fail("queue-DUT lifecycle event accounting mismatch");
    if (q_queued_pulses != 10)
      fail("queue-DUT queued-block accounting mismatch");
    if (r_observed_blocks != 1 || r_observed_position != 0 ||
        r_flush_pulses != 1 || r_overflow_pulses != 1 ||
        r_queued_pulses != 3 || r_complete_pulses != 1)
      fail("retention-DUT lifecycle accounting mismatch");
    if (r_gap_pulse || r_index_error_pulse || r_queued_block_count != 0)
      fail("retention-DUT unexpected residual status");

    $display("OVERLAP_LIFECYCLE_PASS disable_abort=1 queue_overflow_restart=1 retention_overflow_restart=1 index_restart=1 gap_restart=1");
    $finish;
  end

endmodule
