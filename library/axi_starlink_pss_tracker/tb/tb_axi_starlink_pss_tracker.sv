`timescale 1ns/1ps

module tb_axi_starlink_pss_tracker #(
  parameter integer RATE_MSPS = 15
);

  localparam [63:0] TIMESTAMP_BASE = 64'h0000_0001_0000_0000;
  localparam [31:0] REQUEST_ID = 32'h6161_0001;
  localparam integer RATE_MULTIPLIER = RATE_MSPS / 15;
  localparam [63:0] CENTER_INDEX = 64'd256 * RATE_MULTIPLIER;
  localparam integer COEFFICIENT_COUNT = 66 * RATE_MULTIPLIER;
  localparam integer CAPTURE_COUNT = 130 * RATE_MULTIPLIER;
  localparam integer QUALIFIED_LAG_COUNT = 60 * RATE_MULTIPLIER + 1;
  localparam integer TRACK_LAST_LAG = 30 * RATE_MULTIPLIER;
  localparam integer ENABLE_INJECTION = (RATE_MSPS == 15) ? 1 : 0;

  reg sample_clk = 1'b0;
  reg s_axi_aclk = 1'b0;
  always #7 sample_clk = ~sample_clk;
  always #5 s_axi_aclk = ~s_axi_aclk;

  reg sample_reset = 1'b1;
  reg signed [15:0] sample_i = 16'sd0;
  reg signed [15:0] sample_q = 16'sd0;
  reg sample_strobe = 1'b0;
  reg sample_enable = 1'b0;
  reg [63:0] sample_index = 64'd0;
  reg [63:0] sample_timestamp = 64'd0;
  reg [63:0] next_sample_index = 64'd0;

  wire irq;
  reg s_axi_aresetn = 1'b0;
  reg s_axi_awvalid = 1'b0;
  reg [7:0] s_axi_awaddr = 8'd0;
  wire s_axi_awready;
  reg s_axi_wvalid = 1'b0;
  reg [31:0] s_axi_wdata = 32'd0;
  reg [3:0] s_axi_wstrb = 4'hf;
  wire s_axi_wready;
  wire s_axi_bvalid;
  wire [1:0] s_axi_bresp;
  reg s_axi_bready = 1'b0;
  reg s_axi_arvalid = 1'b0;
  reg [7:0] s_axi_araddr = 8'd0;
  wire s_axi_arready;
  wire s_axi_rvalid;
  wire [1:0] s_axi_rresp;
  wire [31:0] s_axi_rdata;
  reg s_axi_rready = 1'b0;

  reg [31:0] expected_word [0:25];
  reg [31:0] read_value;
  reg [63:0] current_index_snapshot;
  reg [63:0] telemetry_test_center_1;
  reg [63:0] telemetry_test_center_2;

  axi_starlink_pss_tracker #(
    .RATE_MSPS       (RATE_MSPS),
    .ENABLE_INJECTION (ENABLE_INJECTION)
  ) dut (
    .sample_clk        (sample_clk),
    .sample_reset      (sample_reset),
    .sample_i          (sample_i),
    .sample_q          (sample_q),
    .sample_strobe     (sample_strobe),
    .sample_enable     (sample_enable),
    .sample_index      (sample_index),
    .sample_timestamp  (sample_timestamp),
    .irq               (irq),
    .s_axi_aclk        (s_axi_aclk),
    .s_axi_aresetn     (s_axi_aresetn),
    .s_axi_awvalid     (s_axi_awvalid),
    .s_axi_awaddr      (s_axi_awaddr),
    .s_axi_awready     (s_axi_awready),
    .s_axi_wvalid      (s_axi_wvalid),
    .s_axi_wdata       (s_axi_wdata),
    .s_axi_wstrb       (s_axi_wstrb),
    .s_axi_wready      (s_axi_wready),
    .s_axi_bvalid      (s_axi_bvalid),
    .s_axi_bresp       (s_axi_bresp),
    .s_axi_bready      (s_axi_bready),
    .s_axi_arvalid     (s_axi_arvalid),
    .s_axi_araddr      (s_axi_araddr),
    .s_axi_arready     (s_axi_arready),
    .s_axi_rvalid      (s_axi_rvalid),
    .s_axi_rresp       (s_axi_rresp),
    .s_axi_rdata       (s_axi_rdata),
    .s_axi_rready      (s_axi_rready),
    .s_axi_awprot      (3'd0),
    .s_axi_arprot      (3'd0)
  );

  task automatic fail;
    input [1023:0] message;
    begin
      $display("AXI_TRACKER_FAIL %0s", message);
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
      for (tap = 0; tap < COEFFICIENT_COUNT; tap = tap + 1) begin
        value = first_index + tap;
        sum = sum + value * value + value * value;
      end
      expected_energy = sum[47:0];
    end
  endfunction

  task automatic axi_read;
    input [7:0] address;
    output [31:0] data;
    integer timeout;
    begin
      @(negedge s_axi_aclk);
      s_axi_araddr = address;
      s_axi_arvalid = 1'b1;
      s_axi_rready = 1'b1;
      timeout = 0;
      while (!s_axi_arready && timeout < 100) begin
        @(posedge s_axi_aclk);
        timeout = timeout + 1;
      end
      if (timeout == 100)
        fail("AXI read address timeout");
      @(negedge s_axi_aclk);
      s_axi_arvalid = 1'b0;
      timeout = 0;
      while (!s_axi_rvalid && timeout < 100) begin
        @(posedge s_axi_aclk);
        timeout = timeout + 1;
      end
      if (timeout == 100 || s_axi_rresp != 2'b00)
        fail("AXI read response timeout/error");
      data = s_axi_rdata;
      @(negedge s_axi_aclk);
      s_axi_rready = 1'b0;
    end
  endtask

  task automatic axi_write;
    input [7:0] address;
    input [31:0] data;
    integer timeout;
    begin
      @(negedge s_axi_aclk);
      s_axi_awaddr = address;
      s_axi_wdata = data;
      s_axi_awvalid = 1'b1;
      s_axi_wvalid = 1'b1;
      s_axi_bready = 1'b1;
      timeout = 0;
      while (!(s_axi_awready && s_axi_wready) && timeout < 100) begin
        @(posedge s_axi_aclk);
        timeout = timeout + 1;
      end
      if (timeout == 100)
        fail("AXI write address/data timeout");
      @(negedge s_axi_aclk);
      s_axi_awvalid = 1'b0;
      s_axi_wvalid = 1'b0;
      timeout = 0;
      while (!s_axi_bvalid && timeout < 100) begin
        @(posedge s_axi_aclk);
        timeout = timeout + 1;
      end
      if (timeout == 100 || s_axi_bresp != 2'b00)
        fail("AXI write response timeout/error");
      @(negedge s_axi_aclk);
      s_axi_bready = 1'b0;
    end
  endtask

  task automatic build_expected_packet;
    reg signed [47:0] winner_ex;
    integer winner_first_index;
    integer winner_numerator;
    begin
      winner_first_index = CENTER_INDEX + TRACK_LAST_LAG;
      winner_ex = expected_energy(winner_first_index);
      winner_numerator = 2 * winner_first_index * winner_first_index;
      expected_word[0] = 32'h3153_5350;
      expected_word[1] = 32'h1a01_0001;
      expected_word[2] = REQUEST_ID;
      expected_word[3] = CENTER_INDEX[31:0];
      expected_word[4] = CENTER_INDEX[63:32];
      expected_word[5] = (TIMESTAMP_BASE + CENTER_INDEX);
      expected_word[6] = (TIMESTAMP_BASE + CENTER_INDEX) >> 32;
      expected_word[7] = TRACK_LAST_LAG;
      expected_word[8] = TIMESTAMP_BASE + winner_first_index;
      expected_word[9] = (TIMESTAMP_BASE + winner_first_index) >> 32;
      expected_word[10] = 32'd77;
      expected_word[11] = winner_first_index;
      expected_word[12] = 32'd0;
      expected_word[13] = -winner_first_index;
      expected_word[14] = 32'hffff_ffff;
      expected_word[15] = winner_ex[31:0];
      expected_word[16] = {
        {16{winner_ex[47]}}, winner_ex[47:32]
      };
      expected_word[17] = 32'd1;
      expected_word[18] = 32'd0;
      expected_word[19] = 32'd0;
      expected_word[20] = winner_numerator;
      expected_word[21] = 32'd0;
      expected_word[22] = 32'd0;
      expected_word[23] = winner_ex[31:0];
      expected_word[24] = winner_ex[47:32];
      expected_word[25] = 32'd0;
    end
  endtask

  always @(negedge sample_clk) begin
    if (sample_reset || !sample_enable) begin
      sample_strobe = 1'b0;
      sample_index = 64'd0;
      sample_timestamp = 64'd0;
      sample_i = 16'sd0;
      sample_q = 16'sd0;
      next_sample_index = 64'd0;
    end else begin
      sample_strobe = 1'b1;
      sample_index = next_sample_index;
      sample_timestamp = TIMESTAMP_BASE + next_sample_index;
      sample_i = $signed(next_sample_index[15:0]);
      sample_q = -$signed(next_sample_index[15:0]);
      next_sample_index = next_sample_index + 1'b1;
    end
  end

  integer tap;
  integer timeout;
  integer word_index;
  initial begin
    $dumpfile("build/tb_axi_starlink_pss_tracker.vcd");
    $dumpvars(0, tb_axi_starlink_pss_tracker);
    build_expected_packet();

    repeat (6) @(posedge sample_clk);
    @(negedge sample_clk);
    sample_reset = 1'b0;
    @(negedge s_axi_aclk);
    s_axi_aresetn = 1'b1;
    repeat (8) @(posedge s_axi_aclk);

    axi_read(8'h00, read_value);
    if (read_value !== 32'h5053_5354)
      fail("identification mismatch");
    axi_read(8'h04, read_value);
    if (read_value !== ((RATE_MSPS == 15) ?
                        32'h0001_0002 : 32'h0001_0003))
      fail("version mismatch");
    axi_read(8'h08, read_value);
    if (read_value !== RATE_MSPS)
      fail("rate mismatch");
    axi_read(8'h0c, read_value);
    if (read_value !== ((RATE_MSPS == 15) ?
                        {8'd0, 8'd61, 8'd130, 8'd66} :
                        {5'd1, QUALIFIED_LAG_COUNT[7:0],
                         CAPTURE_COUNT[9:0], COEFFICIENT_COUNT[8:0]}))
      fail("geometry mismatch");
    axi_read(8'h10, read_value);
    if (read_value !== (ENABLE_INJECTION ?
                        32'h0000_003d : 32'h0000_001d))
      fail("capabilities mismatch");

    // Keep the sample stream idle while software configures the bank.  This
    // mirrors the intended bring-up sequence and avoids doing irrelevant
    // correlation work during the coefficient writes in the portable simulator.
    axi_write(8'h44, 32'h0000_0001); // Clear shadow coefficients.
    for (tap = 0; tap < COEFFICIENT_COUNT; tap = tap + 1)
      axi_write(8'h40, (tap == 0) ? 32'h0000_0001 : 32'd0);
    axi_write(8'h48, 32'd77);
    axi_write(8'h44, 32'h0000_0002); // Commit.

    timeout = 0;
    read_value = 32'd0;
    while ((read_value != 32'd77) && timeout < 2000) begin
      axi_read(8'h4c, read_value);
      timeout = timeout + 1;
    end
    if (timeout == 2000)
      fail("coefficient bank did not commit");
    axi_read(8'h60, read_value);
    if (read_value !== 32'd1)
      fail("active coefficient energy mismatch");

    @(negedge sample_clk);
    sample_enable = 1'b1;

    // The low-word read snapshots both halves for a coherent scheduling
    // reference even while the sample counter continues to advance.
    repeat (20) @(posedge sample_clk);
    axi_read(8'h18, current_index_snapshot[31:0]);
    axi_read(8'h1c, current_index_snapshot[63:32]);
    if (current_index_snapshot == 0 ||
        current_index_snapshot + 64 * RATE_MULTIPLIER > CENTER_INDEX)
      fail("Gray-synchronized scheduling reference is not safely in range");

    axi_write(8'h20, REQUEST_ID);
    axi_write(8'h24, CENTER_INDEX[31:0]);
    axi_write(8'h28, CENTER_INDEX[63:32]);
    axi_write(8'h2c, (TIMESTAMP_BASE + CENTER_INDEX));
    axi_write(8'h30, (TIMESTAMP_BASE + CENTER_INDEX) >> 32);
    axi_write(8'h34, 32'h0000_0001);

    timeout = 0;
    while (!irq && timeout < 100000 * RATE_MULTIPLIER) begin
      @(posedge s_axi_aclk);
      timeout = timeout + 1;
    end
    if (timeout == 100000 * RATE_MULTIPLIER)
      fail("exact winner interrupt did not assert");

    // Every packet read goes through the synchronous result RAM and delayed
    // AXI acknowledgement; reverse order proves random access to one bank.
    for (word_index = 25; word_index >= 0; word_index = word_index - 1) begin
      axi_write(8'h50, word_index);
      axi_read(8'h54, read_value);
      if (read_value !== expected_word[word_index]) begin
        $display("word=%0d expected=%08x actual=%08x",
                 word_index, expected_word[word_index], read_value);
        fail("published result packet mismatch");
      end
    end

    axi_read(8'hc4, read_value);
    if (read_value !== 32'd1)
      fail("reducer processed-job counter mismatch");
    axi_read(8'hc8, read_value);
    if (read_value !== 32'd1)
      fail("reducer emitted-result counter mismatch");
    axi_read(8'hd8, read_value);
    if (read_value !== 32'd1)
      fail("result published counter mismatch");
    axi_read(8'hcc, read_value);
    if (read_value !== 32'd0)
      fail("clean job reported invalid tuples");

    axi_write(8'h58, 32'h0000_0001);
    timeout = 0;
    while (irq && timeout < 100) begin
      @(posedge s_axi_aclk);
      timeout = timeout + 1;
    end
    if (timeout == 100)
      fail("result release did not clear the level interrupt");
    axi_read(8'he0, read_value);
    if (read_value !== 32'd1)
      fail("result consumed counter mismatch");

    // Sample-domain diagnostics are readable only after one explicit atomic
    // snapshot request; live binary counter reads remain forbidden.
    axi_write(8'h68, 32'h0000_0001);
    timeout = 0;
    read_value = 32'd0;
    while ((!read_value[0] || read_value[1]) && timeout < 1000) begin
      axi_read(8'h6c, read_value);
      timeout = timeout + 1;
    end
    if (timeout == 1000)
      fail("atomic telemetry snapshot timeout");
    axi_read(8'h70, read_value);
    if (read_value !== 32'd1)
      fail("telemetry generation mismatch");
    axi_read(8'h84, read_value);
    if (read_value !== 32'd1)
      fail("telemetry admitted counter mismatch");
    axi_read(8'h88, read_value);
    if (read_value !== 32'd1)
      fail("telemetry completed counter mismatch");
    axi_read(8'hac, read_value);
    if (read_value !== 32'd1)
      fail("telemetry capture-published counter mismatch");
    for (word_index = 8'h8c; word_index <= 8'ha8;
         word_index = word_index + 4) begin
      axi_read(word_index[7:0], read_value);
      if (read_value !== 32'd0)
        fail("clean telemetry snapshot accumulated an error counter");
    end
    for (word_index = 8'hb0; word_index <= 8'hb8;
         word_index = word_index + 4) begin
      axi_read(word_index[7:0], read_value);
      if (read_value !== 32'd0)
        fail("clean capture snapshot accumulated an error counter");
    end

    // Request another snapshot while a future candidate is live, then submit
    // a second candidate while telemetry is busy.  The first snapshot must
    // wait for candidate 2, must not include candidate 3, and must remain
    // immutable after candidate 3 completes.  A subsequent snapshot must then
    // include both.  This proves quiescing, deferred submission, and atomic RAM
    // publication under concurrent control traffic.
    axi_read(8'h18, current_index_snapshot[31:0]);
    axi_read(8'h1c, current_index_snapshot[63:32]);
    telemetry_test_center_1 =
        current_index_snapshot + 64'd512 * RATE_MULTIPLIER;
    telemetry_test_center_2 =
        telemetry_test_center_1 + 64'd384 * RATE_MULTIPLIER;

    axi_write(8'h20, 32'h6161_0002);
    axi_write(8'h24, telemetry_test_center_1[31:0]);
    axi_write(8'h28, telemetry_test_center_1[63:32]);
    axi_write(8'h2c, TIMESTAMP_BASE + telemetry_test_center_1);
    axi_write(8'h30, (TIMESTAMP_BASE + telemetry_test_center_1) >> 32);
    axi_write(8'h34, 32'h0000_0001);
    axi_write(8'h68, 32'h0000_0001);

    axi_read(8'h6c, read_value);
    if (!read_value[1] || read_value[0])
      fail("telemetry request did not enter busy/invalid state");

    axi_write(8'h20, 32'h6161_0003);
    axi_write(8'h24, telemetry_test_center_2[31:0]);
    axi_write(8'h28, telemetry_test_center_2[63:32]);
    axi_write(8'h2c, TIMESTAMP_BASE + telemetry_test_center_2);
    axi_write(8'h30, (TIMESTAMP_BASE + telemetry_test_center_2) >> 32);
    axi_write(8'h34, 32'h0000_0001);
    axi_read(8'h14, read_value);
    if (!read_value[2])
      fail("candidate submitted during telemetry was not deferred");

    timeout = 0;
    read_value = 32'd0;
    while ((!read_value[0] || read_value[1]) && timeout < 2000) begin
      axi_read(8'h6c, read_value);
      timeout = timeout + 1;
    end
    if (timeout == 2000)
      fail("busy telemetry snapshot did not drain the active candidate");
    axi_read(8'h70, read_value);
    if (read_value !== 32'd2)
      fail("concurrent telemetry generation mismatch");
    axi_read(8'h84, read_value);
    if (read_value !== 32'd2)
      fail("concurrent telemetry admitted counter is not atomic");
    axi_read(8'h88, read_value);
    if (read_value !== 32'd2)
      fail("concurrent telemetry completed counter is not atomic");
    axi_read(8'hac, read_value);
    if (read_value !== 32'd2)
      fail("concurrent telemetry published counter is not atomic");

    timeout = 0;
    read_value = 32'd0;
    while ((read_value != 32'd3) && timeout < 100000 * RATE_MULTIPLIER) begin
      axi_read(8'hbc, read_value);
      timeout = timeout + 1;
    end
    if (timeout == 100000 * RATE_MULTIPLIER)
      fail("candidate deferred by telemetry was lost or not consumed");
    axi_read(8'h84, read_value);
    if (read_value !== 32'd2)
      fail("published telemetry RAM changed without a new request");

    axi_write(8'h68, 32'h0000_0001);
    timeout = 0;
    read_value = 32'd0;
    while ((!read_value[0] || read_value[1]) && timeout < 2000) begin
      axi_read(8'h6c, read_value);
      timeout = timeout + 1;
    end
    if (timeout == 2000)
      fail("follow-up telemetry snapshot timeout");
    axi_read(8'h70, read_value);
    if (read_value !== 32'd3)
      fail("follow-up telemetry generation mismatch");
    axi_read(8'h84, read_value);
    if (read_value !== 32'd3)
      fail("deferred candidate missing from follow-up admitted count");
    axi_read(8'h88, read_value);
    if (read_value !== 32'd3)
      fail("deferred candidate missing from follow-up completed count");
    axi_read(8'hac, read_value);
    if (read_value !== 32'd3)
      fail("deferred candidate missing from follow-up published count");

    // A sample-domain reset must assert the common epoch and flush CPU-side
    // command/result state even though the external AXI reset stays released.
    @(negedge sample_clk);
    sample_reset = 1'b1;
    repeat (4) @(posedge s_axi_aclk);
    @(negedge sample_clk);
    sample_reset = 1'b0;
    sample_enable = 1'b1;
    repeat (8) @(posedge s_axi_aclk);
    axi_read(8'hd8, read_value);
    if (read_value !== 32'd0 || irq)
      fail("sample reset did not flush the coordinated epoch");

    $display("AXI_TRACKER_PASS rate=%0d taps=%0d lags=%0d winner_lag=%0d packet_words=26 telemetry=serial_bram concurrent_snapshot=1 deferred_candidate=1 irq=level reset_epoch=coordinated",
             RATE_MSPS, COEFFICIENT_COUNT, QUALIFIED_LAG_COUNT,
             TRACK_LAST_LAG);
    $finish;
  end

endmodule
