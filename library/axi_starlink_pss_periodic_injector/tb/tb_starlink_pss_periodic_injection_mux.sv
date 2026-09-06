`timescale 1ns/1ps

module tb_starlink_pss_periodic_injection_mux;

  localparam [31:0] GENERATION = 32'h1502_0001;
  localparam [63:0] START_INDEX = 64'd66017;
  localparam integer SAMPLE_COUNT = 130;
  localparam integer PERIOD_SAMPLES = 20000;
  localparam integer REPEAT_COUNT = 130;
  localparam integer LAST_OFFSET =
      (REPEAT_COUNT - 1) * PERIOD_SAMPLES + SAMPLE_COUNT - 1;

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
  reg [63:0] arm_start_stage = START_INDEX;
  reg [63:0] control_current_index = 64'd0;
  wire fixture_write_ready;
  wire arm_ready;
  wire [31:0] status;
  wire [31:0] last_completed_generation;
  wire [31:0] last_completed_repetitions;

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
  wire selected_sample_substituted;
  wire selected_sample_fixture;

  starlink_pss_periodic_injection_mux dut (
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
    .last_completed_repetitions (last_completed_repetitions),
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
    .selected_sample_substituted(selected_sample_substituted),
    .selected_sample_fixture    (selected_sample_fixture)
  );

  task automatic fail(input string message);
    begin
      $display("PERIODIC_INJECTION_FAIL %0s source=%0d selected=%0d status=%08x",
               message, source_sample_index, selected_sample_index, status);
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

  task automatic write_fixture_word(input integer index);
    reg signed [15:0] word_i;
    reg signed [15:0] word_q;
    begin
      word_i = 16'sd4000 + index;
      word_q = -16'sd5000 - index;
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
  always @(negedge sample_clk) begin
    if (!sample_resetn || !source_sample_enable) begin
      source_sample_strobe = 1'b0;
      source_sample_i = 16'sd0;
      source_sample_q = 16'sd0;
    end else begin
      source_sample_strobe = 1'b1;
      source_sample_index = next_source_index;
      source_sample_timestamp = 64'h5100_0000_0000_0000 + next_source_index;
      source_sample_i = $signed(next_source_index[15:0]) + 16'sd17;
      source_sample_q = -$signed(next_source_index[15:0]) - 16'sd23;
      control_current_index = next_source_index;
      next_source_index = next_source_index + 1'b1;
    end
  end

  integer substituted_count = 0;
  integer fixture_sample_count = 0;
  integer fill_sample_count = 0;
  integer passthrough_count = 0;
  integer relative_index;
  integer period_position;
  reg signed [15:0] expected_i;
  reg signed [15:0] expected_q;
  always @(negedge sample_clk) begin
    if (sample_resetn && selected_sample_enable && selected_sample_strobe) begin
      if (selected_sample_timestamp !==
          64'h5100_0000_0000_0000 + selected_sample_index)
        fail("source-derived timestamp/index changed");
      if (selected_sample_index >= START_INDEX &&
          selected_sample_index <= START_INDEX + LAST_OFFSET) begin
        relative_index = selected_sample_index - START_INDEX;
        period_position = relative_index % PERIOD_SAMPLES;
        if (!selected_sample_substituted)
          fail("qualification interval was not substituted");
        substituted_count = substituted_count + 1;
        if (period_position < SAMPLE_COUNT) begin
          expected_i = 16'sd4000 + period_position;
          expected_q = -16'sd5000 - period_position;
          if (!selected_sample_fixture || selected_sample_i !== expected_i ||
              selected_sample_q !== expected_q)
            fail("periodic fixture sample mismatch");
          fixture_sample_count = fixture_sample_count + 1;
        end else begin
          if (selected_sample_fixture || selected_sample_i !== 16'sd1 ||
              selected_sample_q !== 16'sd0)
            fail("inter-fixture interval was not the deterministic floor");
          fill_sample_count = fill_sample_count + 1;
        end
      end else begin
        expected_i = $signed(selected_sample_index[15:0]) + 16'sd17;
        expected_q = -$signed(selected_sample_index[15:0]) - 16'sd23;
        if (selected_sample_substituted || selected_sample_fixture ||
            selected_sample_i !== expected_i || selected_sample_q !== expected_q)
          fail("pass-through sample changed outside the armed interval");
        passthrough_count = passthrough_count + 1;
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

    fixture_generation_stage = GENERATION;
    pulse_commit();
    if (!status[5] || status[0])
      fail("incomplete fixture commit was not rejected");
    pulse_clear();

    for (index = 0; index < SAMPLE_COUNT; index = index + 1)
      write_fixture_word(index);
    pulse_commit();
    if (!status[0] || !arm_ready || status[5])
      fail("complete fixture did not become arm-ready");

    source_sample_enable = 1'b1;
    pulse_arm();
    timeout = 0;
    while (!status[4] && timeout < 5000000) begin
      @(posedge control_clk);
      timeout = timeout + 1;
    end
    if (timeout == 5000000)
      fail("periodic qualification sequence did not complete");
    repeat (8) @(posedge sample_clk);

    if (status[7] || status[6] || status[5] || status[3] || status[2])
      fail("positive terminal status is not clean");
    if (last_completed_generation != GENERATION ||
        last_completed_repetitions != REPEAT_COUNT)
      fail("completion identity or repetition count mismatch");
    if (substituted_count != LAST_OFFSET + 1 ||
        fixture_sample_count != SAMPLE_COUNT * REPEAT_COUNT ||
        fill_sample_count !=
            (PERIOD_SAMPLES - SAMPLE_COUNT) * (REPEAT_COUNT - 1))
      fail("periodic substitution counts mismatch");
    if (passthrough_count < 100)
      fail("insufficient pass-through coverage");

    $display("PERIODIC_INJECTION_PASS repetitions=%0d fixture_samples=%0d fill_samples=%0d substituted=%0d pass_through=%0d start=%0d last=%0d",
             last_completed_repetitions, fixture_sample_count,
             fill_sample_count, substituted_count, passthrough_count,
             START_INDEX, START_INDEX + LAST_OFFSET);
    $finish;
  end

endmodule
