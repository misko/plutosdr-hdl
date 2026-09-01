`timescale 1ns/1ps

module tb_axi_starlink_pss_monitor;

  localparam integer RATE_MSPS = 15;
  localparam integer DELAY_SAMPLES = 8;
  localparam integer CYCLIC_PREFIX_SAMPLES = 2;
  localparam integer SYMBOL_SAMPLES = 66;
  localparam integer OUTPUT_LATENCY = 2;

  reg                  adc_clk = 1'b0;
  reg                  adc_reset = 1'b1;
  reg signed [15:0]    adc_i = 16'sd0;
  reg signed [15:0]    adc_q = 16'sd0;
  reg                  adc_valid = 1'b0;
  reg                  adc_enable = 1'b0;
  reg [63:0]           adc_sample_index = 64'd0;

  reg                  s_axi_aclk = 1'b0;
  reg                  s_axi_aresetn = 1'b0;
  reg                  s_axi_awvalid = 1'b0;
  reg [6:0]            s_axi_awaddr = 7'd0;
  wire                 s_axi_awready;
  reg                  s_axi_wvalid = 1'b0;
  reg [31:0]           s_axi_wdata = 32'd0;
  reg [3:0]            s_axi_wstrb = 4'hf;
  wire                 s_axi_wready;
  wire                 s_axi_bvalid;
  wire [1:0]           s_axi_bresp;
  reg                  s_axi_bready = 1'b0;
  reg                  s_axi_arvalid = 1'b0;
  reg [6:0]            s_axi_araddr = 7'd0;
  wire                 s_axi_arready;
  wire                 s_axi_rvalid;
  wire [1:0]           s_axi_rresp;
  wire [31:0]          s_axi_rdata;
  reg                  s_axi_rready = 1'b0;

  reg [31:0] projected_pss [0:SYMBOL_SAMPLES-1];
  reg [31:0] noise_state;
  integer n;
  integer k;
  integer candidate_events_seen;
  reg [63:0] observed_candidate_index;
  reg [82:0] observed_candidate_num;
  reg [81:0] observed_candidate_den;

  reg [31:0] read_value;
  reg [31:0] generation_before;
  reg [31:0] generation_after;
  reg [63:0] register_event_count;
  reg [63:0] register_sample_index;
  reg [82:0] register_metric_num;
  reg [81:0] register_metric_den;

  always #7 adc_clk = ~adc_clk;
  always #5 s_axi_aclk = ~s_axi_aclk;

  axi_starlink_pss_monitor #(
    .RATE_MSPS(RATE_MSPS),
    .THRESHOLD_Q15(24576),
    .MIN_WINDOW_ENERGY(41'd1)
  ) dut (
    .sample_clk(adc_clk),
    .sample_reset(adc_reset),
    .sample_i(adc_i),
    .sample_q(adc_q),
    .sample_strobe(adc_valid),
    .sample_enable(adc_enable),
    .sample_index(adc_sample_index),
    .s_axi_aclk(s_axi_aclk),
    .s_axi_aresetn(s_axi_aresetn),
    .s_axi_awvalid(s_axi_awvalid),
    .s_axi_awaddr(s_axi_awaddr),
    .s_axi_awready(s_axi_awready),
    .s_axi_wvalid(s_axi_wvalid),
    .s_axi_wdata(s_axi_wdata),
    .s_axi_wstrb(s_axi_wstrb),
    .s_axi_wready(s_axi_wready),
    .s_axi_bvalid(s_axi_bvalid),
    .s_axi_bresp(s_axi_bresp),
    .s_axi_bready(s_axi_bready),
    .s_axi_arvalid(s_axi_arvalid),
    .s_axi_araddr(s_axi_araddr),
    .s_axi_arready(s_axi_arready),
    .s_axi_rvalid(s_axi_rvalid),
    .s_axi_rresp(s_axi_rresp),
    .s_axi_rdata(s_axi_rdata),
    .s_axi_rready(s_axi_rready),
    .s_axi_awprot(3'd0),
    .s_axi_arprot(3'd0)
  );

  function integer base_i;
    input integer position;
    begin
      case (position % 8)
        0: base_i = 12000;
        1: base_i = 5000;
        2: base_i = -9000;
        3: base_i = -13000;
        4: base_i = -6000;
        5: base_i = 8000;
        6: base_i = 14000;
        default: base_i = 3000;
      endcase
    end
  endfunction

  function integer base_q;
    input integer position;
    begin
      case (position % 8)
        0: base_q = 3000;
        1: base_q = 13000;
        2: base_q = 10000;
        3: base_q = -2000;
        4: base_q = -12000;
        5: base_q = -10000;
        6: base_q = 4000;
        default: base_q = 15000;
      endcase
    end
  endfunction

  function integer pss_i;
    input integer position;
    integer base_position;
    begin
      if (position < CYCLIC_PREFIX_SAMPLES) begin
        base_position = DELAY_SAMPLES - CYCLIC_PREFIX_SAMPLES + position;
        pss_i = -base_i(base_position);
      end else begin
        base_position = (position - CYCLIC_PREFIX_SAMPLES) % DELAY_SAMPLES;
        pss_i = base_i(base_position);
      end
    end
  endfunction

  function integer pss_q;
    input integer position;
    integer base_position;
    begin
      if (position < CYCLIC_PREFIX_SAMPLES) begin
        base_position = DELAY_SAMPLES - CYCLIC_PREFIX_SAMPLES + position;
        pss_q = -base_q(base_position);
      end else begin
        base_position = (position - CYCLIC_PREFIX_SAMPLES) % DELAY_SAMPLES;
        pss_q = base_q(base_position);
      end
    end
  endfunction

  function integer wrong_i;
    input integer position;
    integer code_position;
    begin
      code_position = position % (DELAY_SAMPLES + 1);
      case (((code_position * code_position * 3) +
             (code_position * 11) + 5) % 8)
        0: wrong_i = 11000;
        1: wrong_i = -11000;
        2: wrong_i = 4000;
        3: wrong_i = -4000;
        4: wrong_i = 9000;
        5: wrong_i = -9000;
        6: wrong_i = 2000;
        default: wrong_i = -2000;
      endcase
    end
  endfunction

  function integer wrong_q;
    input integer position;
    integer code_position;
    begin
      code_position = position % (DELAY_SAMPLES + 1);
      case (((code_position * code_position * 5) +
             (code_position * 7) + 3) % 8)
        0: wrong_q = -3000;
        1: wrong_q = 13000;
        2: wrong_q = -13000;
        3: wrong_q = 6000;
        4: wrong_q = -6000;
        5: wrong_q = 10000;
        6: wrong_q = -10000;
        default: wrong_q = 3000;
      endcase
    end
  endfunction

  // Candidate signals are stable for a complete ADC clock interval after the
  // detector's registered pulse, so the falling edge observes the new values.
  always @(negedge adc_clk) begin
    if (dut.candidate_valid_s) begin
      candidate_events_seen = candidate_events_seen + 1;
      observed_candidate_index = dut.candidate_sample_index_s;
      observed_candidate_num = dut.candidate_metric_num_s;
      observed_candidate_den = dut.candidate_metric_den_s;
    end
  end

  task automatic drive_sample;
    input integer sample_i;
    input integer sample_q;
    input [63:0] sample_index;
    input integer sample_valid;
    input integer sample_enable;
    begin
      @(negedge adc_clk);
      adc_i = sample_i;
      adc_q = sample_q;
      adc_sample_index = sample_index;
      adc_valid = sample_valid[0];
      adc_enable = sample_enable[0];
      @(posedge adc_clk);
    end
  endtask

  task automatic reset_all;
    begin
      @(negedge adc_clk);
      adc_reset = 1'b1;
      adc_valid = 1'b0;
      adc_enable = 1'b0;
      adc_i = 16'sd0;
      adc_q = 16'sd0;
      adc_sample_index = 64'd0;
      s_axi_aresetn = 1'b0;
      s_axi_arvalid = 1'b0;
      s_axi_rready = 1'b0;
      s_axi_awvalid = 1'b0;
      s_axi_wvalid = 1'b0;
      s_axi_bready = 1'b0;
      repeat (4) @(posedge adc_clk);
      repeat (3) @(posedge s_axi_aclk);
      @(negedge adc_clk);
      adc_reset = 1'b0;
      adc_enable = 1'b1;
      @(negedge s_axi_aclk);
      s_axi_aresetn = 1'b1;
      candidate_events_seen = 0;
      observed_candidate_index = 64'd0;
      observed_candidate_num = 83'd0;
      observed_candidate_den = 82'd0;
    end
  endtask

  task automatic require_no_candidate;
    input [8*48-1:0] scenario;
    begin
      if (candidate_events_seen != 0)
        $fatal(1, "unexpected candidate in %0s", scenario);
    end
  endtask

  task automatic axi_read;
    input [6:0] address;
    output [31:0] data;
    integer timeout;
    begin
      @(negedge s_axi_aclk);
      s_axi_araddr = address;
      s_axi_arvalid = 1'b1;
      s_axi_rready = 1'b1;
      timeout = 0;
      while (!s_axi_arready && timeout < 80) begin
        @(posedge s_axi_aclk);
        timeout = timeout + 1;
      end
      if (timeout >= 80)
        $fatal(1, "AXI read address handshake timeout at 0x%02x", address);
      @(negedge s_axi_aclk);
      s_axi_arvalid = 1'b0;
      timeout = 0;
      while (!s_axi_rvalid && timeout < 80) begin
        @(posedge s_axi_aclk);
        timeout = timeout + 1;
      end
      if (timeout >= 80)
        $fatal(1, "AXI read data timeout at 0x%02x", address);
      if (s_axi_rresp != 2'b00)
        $fatal(1, "AXI read response error at 0x%02x", address);
      data = s_axi_rdata;
      @(negedge s_axi_aclk);
      s_axi_rready = 1'b0;
    end
  endtask

  task automatic axi_write;
    input [6:0] address;
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
      while (!(s_axi_awready && s_axi_wready) && timeout < 80) begin
        @(posedge s_axi_aclk);
        timeout = timeout + 1;
      end
      if (timeout >= 80)
        $fatal(1, "AXI write handshake timeout at 0x%02x", address);
      @(negedge s_axi_aclk);
      s_axi_awvalid = 1'b0;
      s_axi_wvalid = 1'b0;
      timeout = 0;
      while (!s_axi_bvalid && timeout < 80) begin
        @(posedge s_axi_aclk);
        timeout = timeout + 1;
      end
      if (timeout >= 80)
        $fatal(1, "AXI write response timeout at 0x%02x", address);
      if (s_axi_bresp != 2'b00)
        $fatal(1, "AXI write response error at 0x%02x", address);
      @(negedge s_axi_aclk);
      s_axi_bready = 1'b0;
    end
  endtask

  initial begin
    $readmemh("tb/projected_pss_15_lower_ci16.mem", projected_pss);
    noise_state = 32'h1ace_b00c;
    candidate_events_seen = 0;

    // All-zero input is rejected by the energy floor.
    reset_all();
    for (n = 0; n < SYMBOL_SAMPLES * 2; n = n + 1)
      drive_sample(0, 0, 64'd1000 + n, 1, 1);
    for (n = 0; n < OUTPUT_LATENCY; n = n + 1)
      drive_sample(0, 0, 64'd1000 + SYMBOL_SAMPLES * 2 + n, 1, 1);
    @(negedge adc_clk);
    #1;
    require_no_candidate("zero input");

    // Deterministic wideband-like noise is not lag-8 coherent at threshold.
    reset_all();
    for (n = 0; n < SYMBOL_SAMPLES * 4; n = n + 1) begin
      noise_state = {noise_state[30:0], noise_state[31] ^ noise_state[21] ^
                     noise_state[1] ^ noise_state[0]};
      k = $signed(noise_state[15:0]) >>> 2;
      noise_state = {noise_state[30:0], noise_state[31] ^ noise_state[21] ^
                     noise_state[1] ^ noise_state[0]};
      drive_sample(k, $signed(noise_state[15:0]) >>> 2,
                   64'd10000 + n, 1, 1);
    end
    for (n = 0; n < OUTPUT_LATENCY; n = n + 1) begin
      noise_state = {noise_state[30:0], noise_state[31] ^ noise_state[21] ^
                     noise_state[1] ^ noise_state[0]};
      k = $signed(noise_state[15:0]) >>> 2;
      noise_state = {noise_state[30:0], noise_state[31] ^ noise_state[21] ^
                     noise_state[1] ^ noise_state[0]};
      drive_sample(k, $signed(noise_state[15:0]) >>> 2,
                   64'd10000 + SYMBOL_SAMPLES * 4 + n, 1, 1);
    end
    @(negedge adc_clk);
    #1;
    require_no_candidate("deterministic noise");

    // A high-energy waveform with period D+1 must not qualify.
    reset_all();
    for (n = 0; n < SYMBOL_SAMPLES * 3; n = n + 1)
      drive_sample(wrong_i(n), wrong_q(n), 64'd20000 + n, 1, 1);
    for (n = 0; n < OUTPUT_LATENCY; n = n + 1)
      drive_sample(wrong_i(SYMBOL_SAMPLES * 3 + n),
                   wrong_q(SYMBOL_SAMPLES * 3 + n),
                   64'd20000 + SYMBOL_SAMPLES * 3 + n, 1, 1);
    @(negedge adc_clk);
    #1;
    require_no_candidate("wrong period");

    // Valid gaps pause history and the metric pipeline while enable remains
    // asserted.  A structurally complete symbol split by a gap still arrives.
    reset_all();
    for (n = 0; n < SYMBOL_SAMPLES / 2; n = n + 1)
      drive_sample(pss_i(n), pss_q(n), 64'd30000 + n, 1, 1);
    repeat (5)
      drive_sample(0, 0, 64'd30000 + SYMBOL_SAMPLES / 2, 0, 1);
    for (n = SYMBOL_SAMPLES / 2; n < SYMBOL_SAMPLES; n = n + 1)
      drive_sample(pss_i(n), pss_q(n), 64'd30000 + n, 1, 1);
    for (n = 0; n < OUTPUT_LATENCY; n = n + 1)
      drive_sample(base_i(n), base_q(n),
                   64'd30000 + SYMBOL_SAMPLES + n, 1, 1);
    @(negedge adc_clk);
    #1;
    if (candidate_events_seen != 1 || observed_candidate_index != 64'd30000)
      $fatal(1, "enabled valid gap failed: events=%0d index=%0d valid=%b count=%0d dcount=%0d s0=%b s1=%b",
             candidate_events_seen, observed_candidate_index,
             dut.candidate_valid_s,
             dut.i_candidate_detector.correlation_count,
             dut.i_candidate_detector.delay_count,
             dut.i_candidate_detector.metric_stage0_valid,
             dut.i_candidate_detector.metric_stage1_valid);

    // Disable is a hard boundary, even when valid remains asserted.
    reset_all();
    for (n = 0; n < SYMBOL_SAMPLES - 1; n = n + 1)
      drive_sample(pss_i(n), pss_q(n), 64'd40000 + n, 1, 1);
    drive_sample(0, 0, 64'd40000 + SYMBOL_SAMPLES - 1, 1, 0);
    for (n = 0; n < SYMBOL_SAMPLES - 1; n = n + 1)
      drive_sample(pss_i(n), pss_q(n), 64'd40000 + SYMBOL_SAMPLES + n, 1, 1);
    require_no_candidate("disable boundary");

    // A timestamp discontinuity flushes otherwise valid fragments.
    reset_all();
    for (n = 0; n < SYMBOL_SAMPLES / 2; n = n + 1)
      drive_sample(pss_i(n), pss_q(n), 64'd50000 + n, 1, 1);
    for (n = 0; n < SYMBOL_SAMPLES - 1; n = n + 1)
      drive_sample(pss_i(n), pss_q(n), 64'd60000 + n, 1, 1);
    require_no_candidate("timestamp discontinuity");

    // Characterization fixture: the exact lower-edge projected PSS has lag-8
    // metric about 0.429 and therefore intentionally does not cross the frozen
    // diagnostic threshold 0.75.  This test prevents accidental overclaiming.
    reset_all();
    for (n = 0; n < SYMBOL_SAMPLES; n = n + 1)
      drive_sample($signed(projected_pss[n][31:16]),
                   $signed(projected_pss[n][15:0]),
                   64'd70000 + n, 1, 1);
    for (n = 0; n < OUTPUT_LATENCY; n = n + 1)
      drive_sample(wrong_i(n), wrong_q(n),
                   64'd70000 + SYMBOL_SAMPLES + n, 1, 1);
    @(negedge adc_clk);
    #1;
    require_no_candidate("exact projected PSS at threshold 0.75");

    // Verify the immutable register contract before producing a positive event.
    reset_all();
    axi_read(7'h00, read_value);
    if (read_value != 32'h50535343) $fatal(1, "identity mismatch");
    axi_read(7'h04, read_value);
    if (read_value != 32'h00010000) $fatal(1, "version mismatch");
    axi_read(7'h08, read_value);
    if (read_value != 32'd15) $fatal(1, "rate mismatch");
    axi_read(7'h0c, read_value);
    if (read_value != 32'd24576) $fatal(1, "threshold mismatch");
    axi_read(7'h10, read_value);
    if (read_value != 32'd1) $fatal(1, "minimum energy low mismatch");
    axi_read(7'h14, read_value);
    if (read_value != 32'd0) $fatal(1, "minimum energy high mismatch");
    axi_read(7'h18, read_value);
    if (read_value != 32'h00e88408) $fatal(1, "geometry mismatch");
    axi_read(7'h1c, read_value);
    if (read_value != 32'h00005352) $fatal(1, "metric width mismatch");
    axi_read(7'h20, read_value);
    if (read_value != 32'd0) $fatal(1, "generation did not reset");
    axi_read(7'h7c, read_value);
    if (read_value != 32'd0) $fatal(1, "reserved read was not zero");

    // Writes are acknowledged but cannot alter the fixed detector policy.
    axi_write(7'h0c, 32'd1);
    axi_read(7'h0c, read_value);
    if (read_value != 32'd24576) $fatal(1, "read-only threshold changed");

    // One complete structural candidate verifies the detector, bundled CDC,
    // 83/82-bit payload preservation, event accounting, and AXI register map.
    for (n = 0; n < SYMBOL_SAMPLES; n = n + 1)
      drive_sample(pss_i(n), pss_q(n), 64'd1000000 + n, 1, 1);
    for (n = 0; n < OUTPUT_LATENCY; n = n + 1)
      drive_sample(base_i(n), base_q(n),
                   64'd1000000 + SYMBOL_SAMPLES + n, 1, 1);
    @(negedge adc_clk);
    #1;
    if (candidate_events_seen != 1)
      $fatal(1, "expected one structural candidate, got %0d",
             candidate_events_seen);
    if (observed_candidate_index != 64'd1000000)
      $fatal(1, "candidate index mismatch");
    // Independent integer reference for this mixed-sign structural window:
    // C_re=9,991,000,000, C_im=0 and E0=E1=10,883,000,000.
    if (observed_candidate_num != 83'h569482acccfb81000)
      $fatal(1, "candidate numerator differs from the golden model");
    if (observed_candidate_den != 82'h66bae4da008bd9000)
      $fatal(1, "candidate denominator differs from the golden model");

    repeat (12) @(posedge s_axi_aclk);

    // Software seqlock procedure: read generation, all payload words, then
    // generation again and only accept when the values match.
    axi_read(7'h20, generation_before);
    axi_read(7'h24, register_event_count[31:0]);
    axi_read(7'h28, register_event_count[63:32]);
    axi_read(7'h2c, register_sample_index[31:0]);
    axi_read(7'h30, register_sample_index[63:32]);
    axi_read(7'h34, register_metric_num[31:0]);
    axi_read(7'h38, register_metric_num[63:32]);
    axi_read(7'h3c, read_value);
    register_metric_num[82:64] = read_value[18:0];
    if (read_value[31:19] != 0) $fatal(1, "numerator padding was nonzero");
    axi_read(7'h40, register_metric_den[31:0]);
    axi_read(7'h44, register_metric_den[63:32]);
    axi_read(7'h48, read_value);
    register_metric_den[81:64] = read_value[17:0];
    if (read_value[31:18] != 0) $fatal(1, "denominator padding was nonzero");
    axi_read(7'h20, generation_after);

    if (generation_before == 0 || generation_before != generation_after)
      $fatal(1, "inconsistent seqlock generation");
    if (register_event_count != 64'd1)
      $fatal(1, "event count mismatch");
    if (register_sample_index != observed_candidate_index)
      $fatal(1, "CDC sample index mismatch");
    if (register_metric_num != observed_candidate_num)
      $fatal(1, "CDC numerator mismatch");
    if (register_metric_den != observed_candidate_den)
      $fatal(1, "CDC denominator mismatch");

    $display("PASS axi_starlink_pss_monitor map/detector/CDC");
    $finish;
  end

endmodule
