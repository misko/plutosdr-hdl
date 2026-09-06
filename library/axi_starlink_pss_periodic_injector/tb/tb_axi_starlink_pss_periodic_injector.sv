`timescale 1ns/1ps

module tb_axi_starlink_pss_periodic_injector;

  reg sample_clk = 1'b0;
  reg s_axi_aclk = 1'b0;
  always #7 sample_clk = ~sample_clk;
  always #5 s_axi_aclk = ~s_axi_aclk;

  reg sample_reset = 1'b1;
  reg signed [15:0] sample_i = 16'sd0;
  reg signed [15:0] sample_q = 16'sd0;
  reg sample_strobe = 1'b0;
  reg sample_enable = 1'b1;
  reg [63:0] sample_index = 64'd0;
  reg [63:0] sample_timestamp = 64'd0;
  wire signed [15:0] selected_sample_i;
  wire signed [15:0] selected_sample_q;
  wire selected_sample_strobe;
  wire selected_sample_enable;
  wire [63:0] selected_sample_index;
  wire [63:0] selected_sample_timestamp;
  wire selected_sample_substituted;
  wire selected_sample_fixture;

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

  axi_starlink_pss_periodic_injector dut (
    .sample_clk                 (sample_clk),
    .sample_reset               (sample_reset),
    .sample_i                   (sample_i),
    .sample_q                   (sample_q),
    .sample_strobe              (sample_strobe),
    .sample_enable              (sample_enable),
    .sample_index               (sample_index),
    .sample_timestamp           (sample_timestamp),
    .selected_sample_i          (selected_sample_i),
    .selected_sample_q          (selected_sample_q),
    .selected_sample_strobe     (selected_sample_strobe),
    .selected_sample_enable     (selected_sample_enable),
    .selected_sample_index      (selected_sample_index),
    .selected_sample_timestamp  (selected_sample_timestamp),
    .selected_sample_substituted(selected_sample_substituted),
    .selected_sample_fixture    (selected_sample_fixture),
    .s_axi_aclk                 (s_axi_aclk),
    .s_axi_aresetn              (s_axi_aresetn),
    .s_axi_awvalid              (s_axi_awvalid),
    .s_axi_awaddr               (s_axi_awaddr),
    .s_axi_awready              (s_axi_awready),
    .s_axi_wvalid               (s_axi_wvalid),
    .s_axi_wdata                (s_axi_wdata),
    .s_axi_wstrb                (s_axi_wstrb),
    .s_axi_wready               (s_axi_wready),
    .s_axi_bvalid               (s_axi_bvalid),
    .s_axi_bresp                (s_axi_bresp),
    .s_axi_bready               (s_axi_bready),
    .s_axi_arvalid              (s_axi_arvalid),
    .s_axi_araddr               (s_axi_araddr),
    .s_axi_arready              (s_axi_arready),
    .s_axi_rvalid               (s_axi_rvalid),
    .s_axi_rresp                (s_axi_rresp),
    .s_axi_rdata                (s_axi_rdata),
    .s_axi_rready               (s_axi_rready),
    .s_axi_awprot               (3'd0),
    .s_axi_arprot               (3'd0)
  );

  task automatic fail(input string message);
    begin
      $display("AXI_PERIODIC_INJECTOR_FAIL %0s index=%0d", message, sample_index);
      $fatal(1);
    end
  endtask

  task automatic axi_read(input [7:0] address, output [31:0] data);
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

  task automatic axi_write(input [7:0] address, input [31:0] data);
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

  reg [63:0] next_index = 64'd1000;
  always @(negedge sample_clk) begin
    if (sample_reset) begin
      sample_strobe = 1'b0;
    end else begin
      sample_strobe = 1'b1;
      sample_index = next_index;
      sample_timestamp = 64'h6200_0000_0000_0000 + next_index;
      sample_i = $signed(next_index[15:0]) + 16'sd3;
      sample_q = -$signed(next_index[15:0]) - 16'sd5;
      next_index = next_index + 1'b1;
    end
  end

  reg [63:0] armed_start = 64'd0;
  integer fixture_seen = 0;
  integer floor_seen = 0;
  integer fixture_offset;
  always @(negedge sample_clk) begin
    if (!sample_reset && selected_sample_strobe && selected_sample_enable) begin
      if (selected_sample_timestamp !==
          64'h6200_0000_0000_0000 + selected_sample_index)
        fail("selected metadata changed");
      if (armed_start != 0 && selected_sample_index >= armed_start &&
          selected_sample_index < armed_start + 200) begin
        if (!selected_sample_substituted)
          fail("armed sample was not substituted");
        fixture_offset = selected_sample_index - armed_start;
        if (fixture_offset < 130) begin
          if (!selected_sample_fixture ||
              selected_sample_i !== 16'sd7000 + fixture_offset ||
              selected_sample_q !== -16'sd8000 - fixture_offset)
            fail("AXI-loaded fixture sample mismatch");
          fixture_seen = fixture_seen + 1;
        end else begin
          if (selected_sample_fixture || selected_sample_i !== 16'sd1 ||
              selected_sample_q !== 16'sd0)
            fail("deterministic fill mismatch");
          floor_seen = floor_seen + 1;
        end
      end
    end
  end

  integer word_index;
  integer timeout;
  reg [31:0] value;
  reg [31:0] low;
  reg [31:0] high;
  reg signed [15:0] word_i;
  reg signed [15:0] word_q;
  initial begin
    repeat (8) @(posedge s_axi_aclk);
    @(negedge s_axi_aclk);
    s_axi_aresetn = 1'b1;
    repeat (4) @(posedge sample_clk);
    @(negedge sample_clk);
    sample_reset = 1'b0;
    repeat (12) @(posedge s_axi_aclk);

    axi_read(8'h00, value);
    if (value != 32'h5053_5349)
      fail("identification mismatch");
    axi_read(8'h04, value);
    if (value != 32'h0001_0000)
      fail("version mismatch");
    axi_read(8'h08, value);
    if (value != 32'h0000_000f)
      fail("capability mismatch");
    axi_read(8'h0c, value);
    if (value != {16'd130, 16'd130})
      fail("geometry mismatch");
    axi_read(8'h10, value);
    if (value != 20000)
      fail("period mismatch");
    axi_read(8'h3c, low);
    axi_read(8'h40, high);
    if ({high, low} != 64'd2580129)
      fail("last-offset mismatch");

    axi_write(8'h20, 32'd0);
    axi_read(8'h30, value);
    if (!value[5])
      fail("malformed control was not rejected");
    axi_write(8'h20, 32'd1);

    for (word_index = 0; word_index < 130; word_index = word_index + 1) begin
      word_i = 16'sd7000 + word_index;
      word_q = -16'sd8000 - word_index;
      axi_write(8'h1c, {word_q, word_i});
    end
    axi_write(8'h2c, 32'h1502_1001);
    axi_write(8'h20, 32'd2);
    axi_read(8'h30, value);
    if (!value[0] || value[1] || value[15:8] != 130 || value[6:5] != 0)
      fail("fixture commit status mismatch");

    axi_read(8'h14, low);
    axi_read(8'h18, high);
    armed_start = {high, low} + 64'd70000;
    axi_write(8'h24, armed_start[31:0]);
    axi_write(8'h28, armed_start[63:32]);
    timeout = 0;
    value = 0;
    while (!value[1] && timeout < 100) begin
      axi_read(8'h30, value);
      timeout = timeout + 1;
    end
    if (timeout == 100)
      fail("staged future start did not become arm-ready");
    axi_write(8'h20, 32'd4);
    timeout = 0;
    value = 0;
    while ((!value[7] || value[2]) && timeout < 100) begin
      axi_read(8'h30, value);
      timeout = timeout + 1;
    end
    if (timeout == 100 || value[6:5])
      fail("arm handshake failed");

    timeout = 0;
    while (floor_seen < 50 && timeout < 100000) begin
      @(posedge sample_clk);
      timeout = timeout + 1;
    end
    if (timeout == 100000 || fixture_seen != 130)
      fail("selected stream did not expose one complete fixture and fill");

    $display("AXI_PERIODIC_INJECTOR_PASS fixture=%0d floor=%0d start=%0d",
             fixture_seen, floor_seen, armed_start);
    $finish;
  end

endmodule
