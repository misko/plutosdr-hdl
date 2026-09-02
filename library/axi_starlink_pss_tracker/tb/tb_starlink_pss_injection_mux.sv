`timescale 1ns/1ps

module tb_starlink_pss_injection_mux;

  localparam [31:0] FIXTURE_GENERATION = 32'h1a12_0001;
  localparam [63:0] FIRST_START = 64'd400;

  reg control_clk = 1'b0;
  reg sample_clk = 1'b0;
  always #5 control_clk = ~control_clk;
  always #7 sample_clk = ~sample_clk;

  reg control_resetn = 1'b0;
  reg sample_resetn = 1'b0;
  reg fixture_clear = 1'b0;
  reg fixture_write = 1'b0;
  reg [31:0] fixture_write_data = 32'd0;
  reg fixture_commit = 1'b0;
  reg [31:0] fixture_generation_stage = 32'd0;
  reg arm = 1'b0;
  reg [63:0] arm_start_stage = FIRST_START;
  reg [63:0] control_current_index = 64'd0;
  wire fixture_write_ready;
  wire arm_ready;
  wire [31:0] status;
  wire [31:0] last_completed_generation;

  reg signed [15:0] source_sample_i = 16'sd0;
  reg signed [15:0] source_sample_q = 16'sd0;
  reg source_sample_strobe = 1'b0;
  reg source_sample_enable = 1'b0;
  reg [63:0] source_sample_index = 64'd0;
  reg [63:0] source_sample_timestamp = 64'd0;
  wire signed [15:0] selected_sample_i;
  wire signed [15:0] selected_sample_q;
  wire selected_sample_strobe;
  wire selected_sample_enable;
  wire [63:0] selected_sample_index;
  wire [63:0] selected_sample_timestamp;
  wire selected_sample_injected;

  starlink_pss_injection_mux dut (
    .control_clk                (control_clk),
    .control_resetn             (control_resetn),
    .fixture_clear              (fixture_clear),
    .fixture_write              (fixture_write),
    .fixture_write_data         (fixture_write_data),
    .fixture_commit             (fixture_commit),
    .fixture_generation_stage   (fixture_generation_stage),
    .arm                        (arm),
    .arm_start_stage            (arm_start_stage),
    .control_current_index      (control_current_index),
    .fixture_write_ready        (fixture_write_ready),
    .arm_ready                  (arm_ready),
    .status                     (status),
    .last_completed_generation  (last_completed_generation),
    .sample_clk                 (sample_clk),
    .sample_resetn              (sample_resetn),
    .source_sample_i            (source_sample_i),
    .source_sample_q            (source_sample_q),
    .source_sample_strobe       (source_sample_strobe),
    .source_sample_enable       (source_sample_enable),
    .source_sample_index        (source_sample_index),
    .source_sample_timestamp    (source_sample_timestamp),
    .selected_sample_i          (selected_sample_i),
    .selected_sample_q          (selected_sample_q),
    .selected_sample_strobe     (selected_sample_strobe),
    .selected_sample_enable     (selected_sample_enable),
    .selected_sample_index      (selected_sample_index),
    .selected_sample_timestamp  (selected_sample_timestamp),
    .selected_sample_injected   (selected_sample_injected)
  );

  task automatic fail;
    input [1023:0] message;
    begin
      $display("INJECTION_MUX_FAIL %0s", message);
      $fatal(1);
    end
  endtask

  task automatic pulse_clear;
    begin
      @(negedge control_clk);
      fixture_clear = 1'b1;
      @(negedge control_clk);
      fixture_clear = 1'b0;
    end
  endtask

  task automatic pulse_commit;
    begin
      @(negedge control_clk);
      fixture_commit = 1'b1;
      @(negedge control_clk);
      fixture_commit = 1'b0;
    end
  endtask

  task automatic pulse_arm;
    begin
      @(negedge control_clk);
      arm = 1'b1;
      @(negedge control_clk);
      arm = 1'b0;
    end
  endtask

  task automatic write_fixture_word;
    input integer index;
    reg signed [15:0] word_i;
    reg signed [15:0] word_q;
    begin
      word_i = 16'sd1000 + index;
      word_q = -16'sd2000 - index;
      @(negedge control_clk);
      if (!fixture_write_ready)
        fail("fixture write unexpectedly not ready");
      fixture_write_data = {word_q, word_i};
      fixture_write = 1'b1;
      @(negedge control_clk);
      fixture_write = 1'b0;
    end
  endtask

  reg [63:0] next_source_index = 64'd0;
  reg introduce_gap_jump = 1'b0;
  reg gap_jump_done = 1'b0;
  always @(negedge sample_clk) begin
    if (!sample_resetn || !source_sample_enable) begin
      source_sample_strobe = 1'b0;
      source_sample_i = 16'sd0;
      source_sample_q = 16'sd0;
    end else begin
      if (introduce_gap_jump && !gap_jump_done &&
          next_source_index == arm_start_stage + 64'd10) begin
        next_source_index = next_source_index + 1'b1;
        gap_jump_done = 1'b1;
      end
      source_sample_strobe = 1'b1;
      source_sample_index = next_source_index;
      source_sample_timestamp = 64'h1234_0000_0000_0000 + next_source_index;
      source_sample_i = $signed(next_source_index[15:0]) + 16'sd7;
      source_sample_q = -$signed(next_source_index[15:0]) - 16'sd9;
      next_source_index = next_source_index + 1'b1;
    end
  end

  integer checked_injected = 0;
  integer checked_passthrough = 0;
  reg [31:0] positive_completed_generation = 32'd0;
  reg [63:0] checker_start = FIRST_START;
  integer fixture_offset;
  reg signed [15:0] expected_i;
  reg signed [15:0] expected_q;
  always @(negedge sample_clk) begin
    if (sample_resetn && selected_sample_enable && selected_sample_strobe) begin
      if (selected_sample_timestamp !==
          64'h1234_0000_0000_0000 + selected_sample_index)
        fail("timestamp/index pipeline mismatch");
      if (selected_sample_injected) begin
        fixture_offset = selected_sample_index - checker_start;
        if (fixture_offset < 0 || fixture_offset >= 130)
          fail("injection escaped its armed window");
        expected_i = 16'sd1000 + fixture_offset;
        expected_q = -16'sd2000 - fixture_offset;
        if (selected_sample_i !== expected_i ||
            selected_sample_q !== expected_q)
          fail("selected fixture sample mismatch");
        checked_injected = checked_injected + 1;
      end else begin
        expected_i = $signed(selected_sample_index[15:0]) + 16'sd7;
        expected_q = -$signed(selected_sample_index[15:0]) - 16'sd9;
        if (selected_sample_i !== expected_i ||
            selected_sample_q !== expected_q)
          fail("pass-through sample changed");
        checked_passthrough = checked_passthrough + 1;
      end
    end
  end

  integer index;
  integer timeout;
  initial begin
    repeat (6) @(posedge control_clk);
    @(negedge control_clk);
    control_resetn = 1'b1;
    @(negedge sample_clk);
    sample_resetn = 1'b1;

    // Incomplete fixtures must fail closed and remain visibly rejected.
    fixture_generation_stage = FIXTURE_GENERATION;
    pulse_commit();
    if (!status[5] || status[0])
      fail("incomplete fixture commit was not rejected");
    pulse_clear();
    if (status[5] || status[15:8] != 0)
      fail("legal clear did not reset fixture status");

    for (index = 0; index < 130; index = index + 1)
      write_fixture_word(index);
    if (status[15:8] != 130 || fixture_write_ready)
      fail("fixture load count/ready mismatch");
    pulse_commit();
    if (!status[0] || !status[1] || status[5])
      fail("complete fixture did not become arm-ready");

    source_sample_enable = 1'b1;
    pulse_arm();
    timeout = 0;
    while (!status[4] && timeout < 2000) begin
      @(posedge control_clk);
      timeout = timeout + 1;
    end
    if (timeout == 2000)
      fail("positive injection did not complete");
    if (checked_injected != 130 || status[6] || status[7])
      fail("positive injection count or terminal status mismatch");
    if (last_completed_generation != FIXTURE_GENERATION)
      fail("completed fixture generation mismatch");
    positive_completed_generation = last_completed_generation;

    // A command with less than the hardware's 64-accepted-sample lead is
    // rejected without entering pending or inflight state.
    control_current_index = next_source_index;
    arm_start_stage = next_source_index + 64'd32;
    pulse_arm();
    if (!status[5] || status[2] || status[7])
      fail("late arm was not rejected before crossing domains");

    // Clear and reload so the overlap rejection below is independently
    // observable rather than inheriting the late-command sticky bit.
    pulse_clear();
    for (index = 0; index < 130; index = index + 1)
      write_fixture_word(index);
    pulse_commit();
    if (!status[0] || status[5])
      fail("fixture reload after late rejection failed");

    // Reuse the immutable fixture, then skip one accepted index inside the
    // window. A second arm while the first is inflight must be rejected, and
    // the index jump must stop injection and expose a sticky mismatch.
    control_current_index = next_source_index;
    arm_start_stage = next_source_index + 64'd300;
    checker_start = arm_start_stage;
    introduce_gap_jump = 1'b1;
    pulse_arm();
    pulse_arm();
    if (!status[5])
      fail("overlapping arm was not rejected");
    timeout = 0;
    while (!status[6] && timeout < 2000) begin
      @(posedge control_clk);
      timeout = timeout + 1;
    end
    if (timeout == 2000 || !gap_jump_done || status[7])
      fail("index mismatch did not fail closed");

    if (checked_passthrough < 100)
      fail("insufficient pass-through coverage");
    $display("INJECTION_MUX_PASS fixture_samples=130 pass_through=%0d completion=1 incomplete_rejected=1 late_rejected=1 overlap_rejected=1 mismatch_fail_closed=1 generation=%08x",
             checked_passthrough, positive_completed_generation);
    $finish;
  end

endmodule
