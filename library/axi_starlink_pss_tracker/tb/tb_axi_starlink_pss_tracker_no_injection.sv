`timescale 1ns/1ps

module tb_axi_starlink_pss_tracker_no_injection;

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
  wire signed [15:0] selected_sample_i;
  wire signed [15:0] selected_sample_q;
  wire selected_sample_strobe;
  wire selected_sample_enable;
  wire [63:0] selected_sample_index;
  wire [63:0] selected_sample_timestamp;
  wire selected_sample_injected;
  wire irq;

  reg s_axi_aresetn = 1'b0;
  reg s_axi_awvalid = 1'b0;
  reg [7:0] s_axi_awaddr = 8'd0;
  wire s_axi_awready;
  reg s_axi_wvalid = 1'b0;
  reg [31:0] s_axi_wdata = 32'd0;
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
  reg [31:0] read_value;

  axi_starlink_pss_tracker #(
    .ENABLE_INJECTION (0)
  ) dut (
    .sample_clk                (sample_clk),
    .sample_reset              (sample_reset),
    .sample_i                  (sample_i),
    .sample_q                  (sample_q),
    .sample_strobe             (sample_strobe),
    .sample_enable             (sample_enable),
    .sample_index              (sample_index),
    .sample_timestamp          (sample_timestamp),
    .selected_sample_i         (selected_sample_i),
    .selected_sample_q         (selected_sample_q),
    .selected_sample_strobe    (selected_sample_strobe),
    .selected_sample_enable    (selected_sample_enable),
    .selected_sample_index     (selected_sample_index),
    .selected_sample_timestamp (selected_sample_timestamp),
    .selected_sample_injected  (selected_sample_injected),
    .irq                       (irq),
    .s_axi_aclk                (s_axi_aclk),
    .s_axi_aresetn             (s_axi_aresetn),
    .s_axi_awvalid             (s_axi_awvalid),
    .s_axi_awaddr              (s_axi_awaddr),
    .s_axi_awready             (s_axi_awready),
    .s_axi_wvalid              (s_axi_wvalid),
    .s_axi_wdata               (s_axi_wdata),
    .s_axi_wstrb               (4'hf),
    .s_axi_wready              (s_axi_wready),
    .s_axi_bvalid              (s_axi_bvalid),
    .s_axi_bresp               (s_axi_bresp),
    .s_axi_bready              (s_axi_bready),
    .s_axi_arvalid             (s_axi_arvalid),
    .s_axi_araddr              (s_axi_araddr),
    .s_axi_arready             (s_axi_arready),
    .s_axi_rvalid              (s_axi_rvalid),
    .s_axi_rresp               (s_axi_rresp),
    .s_axi_rdata               (s_axi_rdata),
    .s_axi_rready              (s_axi_rready),
    .s_axi_awprot              (3'd0),
    .s_axi_arprot              (3'd0)
  );

  task automatic fail;
    input [1023:0] message;
    begin
      $display("AXI_TRACKER_NO_INJECTION_FAIL %0s", message);
      $fatal(1);
    end
  endtask

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

  initial begin
    repeat (5) @(posedge s_axi_aclk);
    s_axi_aresetn = 1'b1;
    repeat (5) @(posedge sample_clk);
    sample_reset = 1'b0;
    repeat (8) @(posedge s_axi_aclk);

    sample_i = -16'sd1234;
    sample_q = 16'sd2345;
    sample_strobe = 1'b1;
    sample_enable = 1'b1;
    sample_index = 64'h1234_5678_9abc_def0;
    sample_timestamp = 64'h0fed_cba9_8765_4321;
    #1;
    if (selected_sample_i !== sample_i || selected_sample_q !== sample_q ||
        selected_sample_strobe !== sample_strobe ||
        selected_sample_enable !== sample_enable ||
        selected_sample_index !== sample_index ||
        selected_sample_timestamp !== sample_timestamp ||
        selected_sample_injected !== 1'b0)
      fail("disabled injection path is not transparent");

    axi_read(8'h10, read_value);
    if (read_value !== 32'h0000_001d)
      fail("capability bit still advertises injection");

    axi_write(8'hec, 32'h89ab_cdef);
    axi_write(8'hf0, 32'h0123_4567);
    axi_write(8'hf4, 32'hfeed_beef);
    axi_write(8'he4, 32'h1357_2468);
    axi_write(8'he8, 32'h0000_0007);
    axi_read(8'hec, read_value);
    if (read_value !== 32'd0)
      fail("disabled injection start-low register retained state");
    axi_read(8'hf0, read_value);
    if (read_value !== 32'd0)
      fail("disabled injection start-high register retained state");
    axi_read(8'hf4, read_value);
    if (read_value !== 32'd0)
      fail("disabled injection generation register retained state");
    axi_read(8'hf8, read_value);
    if (read_value !== 32'd0)
      fail("disabled injection status is nonzero");
    axi_read(8'hfc, read_value);
    if (read_value !== 32'd0)
      fail("disabled injection completion generation is nonzero");

    $display("AXI_TRACKER_NO_INJECTION_PASS direct_path=1 capability=0000001d registers_zero=1");
    $finish;
  end

endmodule
