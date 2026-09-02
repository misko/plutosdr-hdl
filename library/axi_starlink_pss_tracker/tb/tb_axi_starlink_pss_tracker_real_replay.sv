`timescale 1ns/1ps

module tb_axi_starlink_pss_tracker_real_replay;

  localparam integer WINDOW_COUNT = 210;
  localparam integer CAPTURE_SAMPLES = 130;
  localparam integer PACKET_WORDS = 26;
  localparam [31:0] INJECTION_GENERATION = 32'h1a12_0001;
  localparam [31:0] COEFFICIENT_GENERATION = 32'h0712_0001;
  localparam [63:0] FIRST_CENTER_INDEX = 64'd128;
  localparam [63:0] CENTER_STRIDE = 64'd225;

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
  wire selected_sample_injected;
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

  reg [31:0] coefficient_words [0:65];
  reg [31:0] replay_samples [0:WINDOW_COUNT*CAPTURE_SAMPLES-1];
  reg [31:0] expected_packets [0:WINDOW_COUNT*PACKET_WORDS-1];
  reg [31:0] read_value;
  reg [31:0] sample_word;
  reg [63:0] center_index;
  reg [63:0] center_timestamp;

  axi_starlink_pss_tracker dut (
    .sample_clk        (sample_clk),
    .sample_reset      (sample_reset),
    .sample_i          (sample_i),
    .sample_q          (sample_q),
    .sample_strobe     (sample_strobe),
    .sample_enable     (sample_enable),
    .sample_index      (sample_index),
    .sample_timestamp  (sample_timestamp),
    .selected_sample_injected (selected_sample_injected),
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
      $display("AXI_REAL_REPLAY_FAIL %0s", message);
      $fatal(1);
    end
  endtask

  task automatic axi_read;
    input [7:0] address;
    output [31:0] data;
    integer wait_cycles;
    begin
      @(negedge s_axi_aclk);
      s_axi_araddr = address;
      s_axi_arvalid = 1'b1;
      s_axi_rready = 1'b1;
      wait_cycles = 0;
      while (!s_axi_arready && wait_cycles < 100) begin
        @(posedge s_axi_aclk);
        wait_cycles = wait_cycles + 1;
      end
      if (wait_cycles == 100)
        fail("AXI read address timeout");
      @(negedge s_axi_aclk);
      s_axi_arvalid = 1'b0;
      wait_cycles = 0;
      while (!s_axi_rvalid && wait_cycles < 100) begin
        @(posedge s_axi_aclk);
        wait_cycles = wait_cycles + 1;
      end
      if (wait_cycles == 100 || s_axi_rresp != 2'b00)
        fail("AXI read response timeout/error");
      data = s_axi_rdata;
      @(negedge s_axi_aclk);
      s_axi_rready = 1'b0;
    end
  endtask

  task automatic axi_write;
    input [7:0] address;
    input [31:0] data;
    integer wait_cycles;
    begin
      @(negedge s_axi_aclk);
      s_axi_awaddr = address;
      s_axi_wdata = data;
      s_axi_awvalid = 1'b1;
      s_axi_wvalid = 1'b1;
      s_axi_bready = 1'b1;
      wait_cycles = 0;
      while (!(s_axi_awready && s_axi_wready) && wait_cycles < 100) begin
        @(posedge s_axi_aclk);
        wait_cycles = wait_cycles + 1;
      end
      if (wait_cycles == 100)
        fail("AXI write address/data timeout");
      @(negedge s_axi_aclk);
      s_axi_awvalid = 1'b0;
      s_axi_wvalid = 1'b0;
      wait_cycles = 0;
      while (!s_axi_bvalid && wait_cycles < 100) begin
        @(posedge s_axi_aclk);
        wait_cycles = wait_cycles + 1;
      end
      if (wait_cycles == 100 || s_axi_bresp != 2'b00)
        fail("AXI write response timeout/error");
      @(negedge s_axi_aclk);
      s_axi_bready = 1'b0;
    end
  endtask

  task automatic drive_sample;
    input [31:0] packed_iq;
    input [63:0] timestamp;
    begin
      @(negedge sample_clk);
      sample_strobe = 1'b1;
      sample_index = next_sample_index;
      sample_timestamp = timestamp;
      sample_i = $signed(packed_iq[31:16]);
      sample_q = $signed(packed_iq[15:0]);
      next_sample_index = next_sample_index + 1'b1;
    end
  endtask

  integer tap;
  integer job;
  integer filler;
  integer sample_number;
  integer word_index;
  integer timeout;
  integer injected_sample_count = 0;

  always @(negedge sample_clk) begin
    if (selected_sample_injected)
      injected_sample_count = injected_sample_count + 1;
  end

  initial begin
    $readmemh(
        "../starlink_pss_raw_correlator/tb/upper_minus100k_coefficients_q15.mem",
        coefficient_words);
    $readmemh("tb/real_071200_wrapper_samples_ci16.mem", replay_samples);
    $readmemh("tb/real_071200_wrapper_packets.mem", expected_packets);

    repeat (8) @(posedge s_axi_aclk);
    @(negedge sample_clk);
    sample_reset = 1'b0;
    @(negedge s_axi_aclk);
    s_axi_aresetn = 1'b1;
    repeat (12) @(posedge s_axi_aclk);

    axi_read(8'h00, read_value);
    if (read_value !== 32'h5053_5354)
      fail("identification mismatch");
    axi_read(8'h04, read_value);
    if (read_value !== 32'h0001_0002)
      fail("version mismatch");
    axi_read(8'h08, read_value);
    if (read_value !== 32'd15)
      fail("rate mismatch");
    axi_read(8'h0c, read_value);
    if (read_value !== {8'd0, 8'd61, 8'd130, 8'd66})
      fail("geometry mismatch");
    axi_read(8'h10, read_value);
    if (read_value !== 32'h0000_003d)
      fail("capabilities mismatch");

    axi_write(8'h44, 32'h0000_0001);
    for (tap = 0; tap < 66; tap = tap + 1) begin
      // The retained memory file is {I,Q}; the AXI register is {Q,I}.
      axi_write(8'h40, {
        coefficient_words[tap][15:0], coefficient_words[tap][31:16]
      });
    end
    axi_write(8'h48, COEFFICIENT_GENERATION);
    axi_write(8'h44, 32'h0000_0002);
    timeout = 0;
    read_value = 32'd0;
    while (read_value != COEFFICIENT_GENERATION && timeout < 3000) begin
      axi_read(8'h4c, read_value);
      timeout = timeout + 1;
    end
    if (timeout == 3000)
      fail("coefficient bank did not commit");
    axi_read(8'h60, read_value);
    if (read_value !== expected_packets[17])
      fail("active coefficient energy low word mismatch");
    axi_read(8'h64, read_value);
    if (read_value !== expected_packets[18])
      fail("active coefficient energy high word mismatch");

    // Freeze the first retained 130-sample window into the ABI 1.2 accepted-
    // sample injection bank. The retained file is {I,Q}; the injection data
    // register, like the coefficient register, is {Q,I}.
    axi_write(8'he8, 32'h0000_0001);
    for (sample_number = 0; sample_number < CAPTURE_SAMPLES;
         sample_number = sample_number + 1) begin
      sample_word = replay_samples[sample_number];
      axi_write(8'he4, {sample_word[15:0], sample_word[31:16]});
    end
    axi_write(8'hf4, INJECTION_GENERATION);
    axi_write(8'he8, 32'h0000_0002);
    axi_write(8'hec, FIRST_CENTER_INDEX - 32);
    axi_write(8'hf0, 32'd0);
    axi_read(8'hf8, read_value);
    if (!read_value[0] || !read_value[1] || read_value[15:8] != 130 ||
        read_value[6:5] != 0)
      fail("injection fixture did not commit cleanly");
    axi_write(8'he8, 32'h0000_0004);

    sample_enable = 1'b1;
    center_timestamp = {
      expected_packets[6], expected_packets[5]
    };
    // Establish an accepted scheduling reference at index zero.  It is the
    // first of 128 contiguous synthetic timestamps leading into window zero.
    drive_sample(32'd0, center_timestamp - 64'd128);
    @(negedge sample_clk);
    sample_strobe = 1'b0;
    repeat (8) @(posedge s_axi_aclk);

    for (job = 0; job < WINDOW_COUNT; job = job + 1) begin
      center_index = FIRST_CENTER_INDEX + CENTER_STRIDE * job;
      center_timestamp = {
        expected_packets[job*PACKET_WORDS + 6],
        expected_packets[job*PACKET_WORDS + 5]
      };
      if (next_sample_index !== center_index - 64'd127)
        fail("synthetic sample scheduling index drifted");

      axi_write(8'h20, expected_packets[job*PACKET_WORDS + 2]);
      axi_write(8'h24, center_index[31:0]);
      axi_write(8'h28, center_index[63:32]);
      axi_write(8'h2c, center_timestamp[31:0]);
      axi_write(8'h30, center_timestamp[63:32]);
      axi_write(8'h34, 32'h0000_0001);

      // Keep every accepted beat consecutive while capture is active.  The 95
      // zero fillers provide ample scheduling/CDC lead; the next
      // 130 beats are the retained p-32..p+97 recording window.
      for (filler = 0; filler < 95; filler = filler + 1)
        drive_sample(32'd0, center_timestamp - 64'd127 + filler);
      for (sample_number = 0; sample_number < CAPTURE_SAMPLES;
           sample_number = sample_number + 1) begin
        // Window zero reaches the tracker only through the injection mux;
        // subsequent windows retain the historical direct replay path.
        sample_word = (job == 0) ? 32'd0 :
            replay_samples[job*CAPTURE_SAMPLES + sample_number];
        drive_sample(sample_word, center_timestamp - 64'd32 + sample_number);
      end
      @(negedge sample_clk);
      sample_strobe = 1'b0;

      timeout = 0;
      while (!irq && timeout < 200000) begin
        @(posedge s_axi_aclk);
        timeout = timeout + 1;
      end
      if (timeout == 200000)
        fail("real-window result timeout");
      axi_read(8'h5c, read_value);
      if (!read_value[0] || read_value[28:24] != 5'd26)
        fail("published result status mismatch");

      for (word_index = 0; word_index < PACKET_WORDS;
           word_index = word_index + 1) begin
        axi_write(8'h50, word_index);
        axi_read(8'h54, read_value);
        if (read_value !== expected_packets[job*PACKET_WORDS + word_index]) begin
          $display(
              "job=%0d word=%0d expected=%08x actual=%08x",
              job, word_index,
              expected_packets[job*PACKET_WORDS + word_index], read_value);
          fail("real-window packet mismatch");
        end
      end

      axi_write(8'h58, 32'h0000_0001);
      timeout = 0;
      while (irq && timeout < 1000) begin
        @(posedge s_axi_aclk);
        timeout = timeout + 1;
      end
      if (timeout == 1000)
        fail("result release timeout");

      // The reducer may publish before the raw trace drains +31/+32.  Wait for
      // raw-engine ownership to close before scheduling the next window.
      timeout = 0;
      read_value = 32'd0;
      while (read_value != job + 1 && timeout < 2000) begin
        axi_read(8'hbc, read_value);
        timeout = timeout + 1;
      end
      if (timeout == 2000)
        fail("raw engine did not retire the complete trace job");

      if (job == 0) begin
        timeout = 0;
        read_value = 32'd0;
        while (!read_value[4] && timeout < 1000) begin
          axi_read(8'hf8, read_value);
          timeout = timeout + 1;
        end
        if (timeout == 1000 || read_value[7:5] != 0)
          fail("injection did not complete without mismatch/rejection");
        axi_read(8'hfc, read_value);
        if (read_value !== INJECTION_GENERATION ||
            injected_sample_count != CAPTURE_SAMPLES)
          fail("injection completion generation/count mismatch");
      end
    end

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

    for (word_index = 8'h80; word_index <= 8'he0;
         word_index = word_index + 4) begin
      axi_read(word_index[7:0], read_value);
      case (word_index)
        8'h84, 8'h88, 8'hac, 8'hbc, 8'hc4, 8'hc8, 8'hd8, 8'he0:
          if (read_value !== WINDOW_COUNT)
            fail("clean replay completion counter mismatch");
        default:
          if (read_value !== 32'd0)
            fail("clean replay accumulated an error counter");
      endcase
    end

    $display("AXI_REAL_REPLAY_PASS windows=210 fixed_float_lag_matches=210 injected_window0_samples=130 direct_windows=209 raw_samples=27300 packet_words=5460 aperture=-30..30 errors=0");
    $finish;
  end

endmodule
