`timescale 1ns/1ps

module tb_starlink_pss_capture_bridge;

  reg sample_clk = 1'b0;
  reg engine_clk = 1'b0;
  always #7 sample_clk = ~sample_clk;
  always #5 engine_clk = ~engine_clk;

  reg sample_resetn = 1'b0;
  reg engine_resetn = 1'b0;

  reg capture_valid = 1'b0;
  reg capture_start = 1'b0;
  reg capture_done = 1'b0;
  reg capture_abort = 1'b0;
  reg [7:0] capture_slot = 8'd0;
  reg [31:0] capture_request_id = 32'd0;
  reg [63:0] capture_center_index = 64'd0;
  reg [63:0] capture_center_timestamp = 64'd0;
  reg [63:0] capture_sample_timestamp = 64'd0;
  reg signed [15:0] capture_sample_i = 16'sd0;
  reg signed [15:0] capture_sample_q = 16'sd0;

  wire capture_ready;
  wire [1:0] capture_bank_free;
  wire [31:0] capture_published_count;
  wire [31:0] capture_abort_discard_count;
  wire [31:0] capture_buffer_overrun_count;
  wire [31:0] capture_protocol_error_count;

  reg engine_job_ready = 1'b0;
  wire engine_job_start;
  wire engine_job_done;
  wire [31:0] engine_request_id;
  wire [63:0] engine_center_index;
  wire [63:0] engine_center_timestamp;
  wire engine_sample_valid;
  reg engine_sample_ready = 1'b0;
  wire [7:0] engine_sample_slot;
  wire [63:0] engine_sample_timestamp;
  wire signed [15:0] engine_sample_i;
  wire signed [15:0] engine_sample_q;
  wire [31:0] engine_consumed_count;

  starlink_pss_capture_bridge dut (
    .i_sample_clk                    (sample_clk),
    .i_sample_resetn                 (sample_resetn),
    .i_capture_valid                 (capture_valid),
    .i_capture_start                 (capture_start),
    .i_capture_done                  (capture_done),
    .i_capture_abort                 (capture_abort),
    .i_capture_slot                  (capture_slot),
    .i_capture_request_id            (capture_request_id),
    .i_capture_center_index          (capture_center_index),
    .i_capture_center_timestamp      (capture_center_timestamp),
    .i_capture_sample_timestamp      (capture_sample_timestamp),
    .i_capture_sample_i              (capture_sample_i),
    .i_capture_sample_q              (capture_sample_q),
    .o_capture_ready                 (capture_ready),
    .o_capture_bank_free             (capture_bank_free),
    .o_capture_published_count       (capture_published_count),
    .o_capture_abort_discard_count   (capture_abort_discard_count),
    .o_capture_buffer_overrun_count  (capture_buffer_overrun_count),
    .o_capture_protocol_error_count  (capture_protocol_error_count),
    .i_engine_clk                    (engine_clk),
    .i_engine_resetn                 (engine_resetn),
    .i_engine_job_ready              (engine_job_ready),
    .o_engine_job_start              (engine_job_start),
    .o_engine_job_done               (engine_job_done),
    .o_engine_request_id             (engine_request_id),
    .o_engine_center_index           (engine_center_index),
    .o_engine_center_timestamp       (engine_center_timestamp),
    .o_engine_sample_valid           (engine_sample_valid),
    .i_engine_sample_ready           (engine_sample_ready),
    .o_engine_sample_slot            (engine_sample_slot),
    .o_engine_sample_timestamp       (engine_sample_timestamp),
    .o_engine_sample_i               (engine_sample_i),
    .o_engine_sample_q               (engine_sample_q),
    .o_engine_consumed_count         (engine_consumed_count)
  );

  integer expected_job_count = 0;
  integer observed_job_start_count = 0;
  integer observed_job_done_count = 0;
  integer observed_sample_count = 0;
  integer engine_cycle_count = 0;
  integer active_expected_job = -1;

  reg [31:0] expected_request_id [0:7];
  reg [63:0] expected_center_index [0:7];
  reg [63:0] expected_center_timestamp [0:7];
  reg [63:0] expected_sample_timestamp_base [0:7];
  integer expected_seed [0:7];

  task automatic fail;
    input [1023:0] message;
    begin
      $display("CAPTURE_BRIDGE_FAIL %0s", message);
      $fatal(1);
    end
  endtask

  task automatic add_expected_job;
    input [31:0] request_id;
    input [63:0] center_index;
    input [63:0] center_timestamp;
    input [63:0] sample_timestamp_base;
    input integer seed;
    begin
      expected_request_id[expected_job_count] = request_id;
      expected_center_index[expected_job_count] = center_index;
      expected_center_timestamp[expected_job_count] = center_timestamp;
      expected_sample_timestamp_base[expected_job_count] =
          sample_timestamp_base;
      expected_seed[expected_job_count] = seed;
      expected_job_count = expected_job_count + 1;
    end
  endtask

  task automatic clear_capture_inputs;
    begin
      capture_valid = 1'b0;
      capture_start = 1'b0;
      capture_done = 1'b0;
      capture_abort = 1'b0;
      capture_slot = 8'd0;
      capture_request_id = 32'd0;
      capture_center_index = 64'd0;
      capture_center_timestamp = 64'd0;
      capture_sample_timestamp = 64'd0;
      capture_sample_i = 16'sd0;
      capture_sample_q = 16'sd0;
    end
  endtask

  task automatic drive_capture;
    input [31:0] request_id;
    input [63:0] center_index;
    input [63:0] sample_timestamp_base;
    input integer seed;
    integer slot;
    begin
      for (slot = 0; slot < 130; slot = slot + 1) begin
        @(negedge sample_clk);
        capture_valid = 1'b1;
        capture_start = (slot == 0);
        capture_done = (slot == 129);
        capture_abort = 1'b0;
        capture_slot = slot[7:0];
        capture_request_id = request_id;
        capture_center_index = center_index;
        capture_center_timestamp = sample_timestamp_base + 64'd32;
        capture_sample_timestamp = sample_timestamp_base + slot;
        capture_sample_i = $signed(seed + slot);
        capture_sample_q = -$signed(seed + slot);
      end
      @(negedge sample_clk);
      clear_capture_inputs();
    end
  endtask

  task automatic drive_aborted_capture;
    integer slot;
    begin
      for (slot = 0; slot < 11; slot = slot + 1) begin
        @(negedge sample_clk);
        capture_valid = 1'b1;
        capture_start = (slot == 0);
        capture_done = 1'b0;
        capture_abort = 1'b0;
        capture_slot = slot[7:0];
        capture_request_id = 32'h0000_00a0;
        capture_center_index = 64'd900;
        capture_center_timestamp = 64'd5032;
        capture_sample_timestamp = 64'd5000 + slot;
        capture_sample_i = slot;
        capture_sample_q = -slot;
      end
      @(negedge sample_clk);
      capture_valid = 1'b1;
      capture_start = 1'b0;
      capture_done = 1'b0;
      capture_abort = 1'b1;
      capture_slot = 8'd11;
      capture_sample_timestamp = 64'd5011;
      capture_sample_i = 16'sd11;
      capture_sample_q = -16'sd11;
      @(negedge sample_clk);
      clear_capture_inputs();
    end
  endtask

  task automatic drive_malformed_capture;
    begin
      @(negedge sample_clk);
      capture_valid = 1'b1;
      capture_start = 1'b1;
      capture_done = 1'b0;
      capture_abort = 1'b0;
      capture_slot = 8'd0;
      capture_request_id = 32'h0000_00b0;
      capture_center_index = 64'd1900;
      capture_center_timestamp = 64'd6032;
      capture_sample_timestamp = 64'd6000;
      capture_sample_i = 16'sd1;
      capture_sample_q = -16'sd1;

      @(negedge sample_clk);
      capture_start = 1'b0;
      capture_slot = 8'd2;
      capture_sample_timestamp = 64'd6002;
      capture_sample_i = 16'sd2;
      capture_sample_q = -16'sd2;

      @(negedge sample_clk);
      capture_done = 1'b1;
      capture_slot = 8'd129;
      capture_sample_timestamp = 64'd6129;
      capture_sample_i = 16'sd129;
      capture_sample_q = -16'sd129;

      @(negedge sample_clk);
      clear_capture_inputs();
    end
  endtask

  always @(negedge engine_clk) begin
    if (!engine_resetn) begin
      engine_sample_ready = 1'b0;
      engine_cycle_count = 0;
    end else begin
      engine_cycle_count = engine_cycle_count + 1;
      // Deterministic backpressure crosses every slot and holds some outputs
      // for two engine clocks.
      engine_sample_ready = (engine_cycle_count % 7 != 0) &&
                            (engine_cycle_count % 7 != 1);
    end
  end

  always @(posedge engine_clk) begin
    if (engine_resetn) begin
      if (engine_job_start) begin
        if (observed_job_start_count >= expected_job_count)
          fail("unexpected engine job");
        active_expected_job = observed_job_start_count;
        if (engine_request_id !==
            expected_request_id[active_expected_job])
          fail("request ID/order mismatch");
        if (engine_center_index !==
            expected_center_index[active_expected_job])
          fail("center index mismatch");
        if (engine_center_timestamp !==
            expected_center_timestamp[active_expected_job])
          fail("center timestamp mismatch");
        observed_sample_count = 0;
        observed_job_start_count = observed_job_start_count + 1;
      end

      if (engine_sample_valid && engine_sample_ready) begin
        if (active_expected_job < 0)
          fail("sample appeared without a job");
        if (engine_sample_slot !== observed_sample_count[7:0])
          fail("sample slot mismatch");
        if (engine_sample_timestamp !==
            expected_sample_timestamp_base[active_expected_job] +
            observed_sample_count)
          fail("sample timestamp mismatch");
        if (engine_sample_i !==
            $signed(expected_seed[active_expected_job] +
                    observed_sample_count))
          fail("sample I mismatch");
        if (engine_sample_q !==
            -$signed(expected_seed[active_expected_job] +
                     observed_sample_count))
          fail("sample Q mismatch");
        observed_sample_count = observed_sample_count + 1;
      end

      if (engine_job_done) begin
        if (observed_sample_count != 130)
          fail("job did not contain exactly 130 accepted samples");
        observed_job_done_count = observed_job_done_count + 1;
        active_expected_job = -1;
      end
    end
  end

  integer timeout;
  initial begin
    $dumpfile("build/tb_starlink_pss_capture_bridge.vcd");
    $dumpvars(0, tb_starlink_pss_capture_bridge);

    repeat (5) @(posedge engine_clk);
    @(negedge sample_clk);
    sample_resetn = 1'b1;
    engine_resetn = 1'b1;
    repeat (12) @(posedge sample_clk);

    if (capture_bank_free !== 2'b11 || !capture_ready)
      fail("both banks were not free after coordinated reset");

    drive_aborted_capture();
    repeat (12) @(posedge sample_clk);
    if (capture_abort_discard_count !== 32'd1)
      fail("aborted capture was not counted exactly once");
    if (capture_published_count !== 32'd0 ||
        capture_bank_free !== 2'b11)
      fail("aborted capture leaked a descriptor or bank");

    drive_malformed_capture();
    repeat (12) @(posedge sample_clk);
    if (capture_protocol_error_count !== 32'd1)
      fail("malformed slot sequence was not counted exactly once");
    if (capture_published_count !== 32'd0 ||
        capture_bank_free !== 2'b11)
      fail("malformed capture leaked a descriptor or bank");

    add_expected_job(32'h1111_0001, 64'd10000, 64'd20032, 64'd20000, 100);
    drive_capture(32'h1111_0001, 64'd10000, 64'd20000, 100);
    add_expected_job(32'h2222_0002, 64'd20000, 64'd30032, 64'd30000, 300);
    drive_capture(32'h2222_0002, 64'd20000, 64'd30000, 300);
    repeat (12) @(posedge sample_clk);
    if (capture_published_count !== 32'd2 ||
        capture_bank_free !== 2'b00 || capture_ready)
      fail("two complete captures did not occupy both banks");

    // This complete scheduler-style image must be discarded atomically when
    // both banks are occupied; its samples may not overwrite either bank.
    drive_capture(32'h3333_0003, 64'd30000, 64'd40000, 500);
    repeat (4) @(posedge sample_clk);
    if (capture_buffer_overrun_count !== 32'd1 ||
        capture_published_count !== 32'd2)
      fail("buffer overrun was not counted and discarded exactly once");

    engine_job_ready = 1'b1;
    timeout = 0;
    while ((observed_job_done_count < 1) && (timeout < 3000)) begin
      @(posedge engine_clk);
      timeout = timeout + 1;
    end
    if (timeout == 3000)
      fail("first queued job did not drain");

    @(negedge engine_clk);
    engine_job_ready = 1'b0;
    repeat (10) @(posedge sample_clk);
    if (capture_bank_free == 2'b00)
      fail("consumed bank ownership did not return across CDC");

    add_expected_job(32'h4444_0004, 64'd40000, 64'd50032, 64'd50000, 700);
    drive_capture(32'h4444_0004, 64'd40000, 64'd50000, 700);
    repeat (8) @(posedge sample_clk);
    if (capture_published_count !== 32'd3)
      fail("returned bank was not reusable");

    engine_job_ready = 1'b1;
    timeout = 0;
    while ((observed_job_done_count < 3) && (timeout < 6000)) begin
      @(posedge engine_clk);
      timeout = timeout + 1;
    end
    if (timeout == 6000)
      fail("ordered queued jobs did not drain");
    if (observed_job_start_count != 3 || engine_consumed_count !== 32'd3)
      fail("engine job accounting mismatch");

    repeat (12) @(posedge sample_clk);
    if (capture_bank_free !== 2'b11)
      fail("both banks were not returned after drain");

    // Prove that coordinated reset flushes a published-but-unconsumed
    // descriptor and restores ownership without emitting stale data.
    engine_job_ready = 1'b0;
    drive_capture(32'h5555_0005, 64'd50000, 64'd60000, 900);
    repeat (8) @(posedge sample_clk);
    if (capture_published_count !== 32'd4)
      fail("pre-reset descriptor was not published");

    @(negedge sample_clk);
    sample_resetn = 1'b0;
    engine_resetn = 1'b0;
    repeat (6) @(posedge engine_clk);
    @(negedge sample_clk);
    sample_resetn = 1'b1;
    engine_resetn = 1'b1;
    repeat (12) @(posedge sample_clk);
    if (capture_published_count !== 32'd0 ||
        engine_consumed_count !== 32'd0 ||
        capture_bank_free !== 2'b11)
      fail("coordinated reset did not flush counts and ownership");

    // Monitor arrays continue after reset; only this wrap-valued descriptor is
    // added to the expected ordered stream.
    add_expected_job(
        32'hffff_0006,
        64'hffff_ffff_ffff_fff0,
        64'h8000_0000_0000_0020,
        64'h8000_0000_0000_0000,
        1100);
    drive_capture(
        32'hffff_0006,
        64'hffff_ffff_ffff_fff0,
        64'h8000_0000_0000_0000,
        1100);
    engine_job_ready = 1'b1;
    timeout = 0;
    while ((observed_job_done_count < 4) && (timeout < 3000)) begin
      @(posedge engine_clk);
      timeout = timeout + 1;
    end
    if (timeout == 3000)
      fail("post-reset wrap-valued job did not drain");

    if (observed_job_start_count != 4 || observed_job_done_count != 4)
      fail("unexpected final job counts");
    if (capture_buffer_overrun_count !== 32'd0 ||
        capture_abort_discard_count !== 32'd0 ||
        capture_protocol_error_count !== 32'd0)
      fail("post-reset clean campaign accumulated an error");

    $display("CAPTURE_BRIDGE_PASS ordered_jobs=%0d samples_per_job=130 pre_reset_overruns=1 abort_discards=1 protocol_discards=1",
             observed_job_done_count);
    $finish;
  end

endmodule
