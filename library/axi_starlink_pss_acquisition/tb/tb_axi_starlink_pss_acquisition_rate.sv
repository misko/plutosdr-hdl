`timescale 1ns/1ps

module tb_axi_starlink_pss_acquisition_rate #(
  parameter integer INPUT_RATE_MSPS = 15
);

  localparam integer INPUT_COUNT = 500;
  localparam integer DDC_ENABLED = INPUT_RATE_MSPS != 15;

  reg sample_clk = 1'b0;
  reg s_axi_aclk = 1'b0;
  always #8 sample_clk = ~sample_clk;
  always #5 s_axi_aclk = ~s_axi_aclk;

  reg sample_reset = 1'b1;
  reg sample_strobe = 1'b0;
  reg sample_enable = 1'b0;
  reg sample_gap = 1'b0;
  reg signed [15:0] sample_i = 16'sd0;
  reg signed [15:0] sample_q = 16'sd0;
  reg [63:0] sample_index = 64'd0;
  wire irq;

  reg s_axi_aresetn = 1'b0;
  reg s_axi_awvalid = 1'b0;
  reg [7:0] s_axi_awaddr = 8'd0;
  wire s_axi_awready;
  reg s_axi_wvalid = 1'b0;
  reg [31:0] s_axi_wdata = 32'd0;
  reg [3:0] s_axi_wstrb = 4'd0;
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

  reg [96:0] input_memory [0:INPUT_COUNT-1];
  reg [96:0] expected_memory [0:249];
  reg [31:0] summary_memory [0:3];

  axi_starlink_pss_acquisition #(
    .SAMPLE_FIFO_ADDRESS_WIDTH(7),
    .INPUT_RATE_MSPS          (INPUT_RATE_MSPS)
  ) dut (
    .sample_clk     (sample_clk),
    .sample_reset   (sample_reset),
    .sample_strobe  (sample_strobe),
    .sample_enable  (sample_enable),
    .sample_gap     (sample_gap),
    .sample_i       (sample_i),
    .sample_q       (sample_q),
    .sample_index   (sample_index),
    .irq            (irq),
    .s_axi_aclk     (s_axi_aclk),
    .s_axi_aresetn  (s_axi_aresetn),
    .s_axi_awvalid  (s_axi_awvalid),
    .s_axi_awaddr   (s_axi_awaddr),
    .s_axi_awready  (s_axi_awready),
    .s_axi_wvalid   (s_axi_wvalid),
    .s_axi_wdata    (s_axi_wdata),
    .s_axi_wstrb    (s_axi_wstrb),
    .s_axi_wready   (s_axi_wready),
    .s_axi_bvalid   (s_axi_bvalid),
    .s_axi_bresp    (s_axi_bresp),
    .s_axi_bready   (s_axi_bready),
    .s_axi_arvalid  (s_axi_arvalid),
    .s_axi_araddr   (s_axi_araddr),
    .s_axi_arready  (s_axi_arready),
    .s_axi_rvalid   (s_axi_rvalid),
    .s_axi_rresp    (s_axi_rresp),
    .s_axi_rdata    (s_axi_rdata),
    .s_axi_rready   (s_axi_rready),
    .s_axi_awprot   (3'd0),
    .s_axi_arprot   (3'd0)
  );

  task automatic fail(input string message);
    begin
      $display("ACQUISITION_RATE_FAIL rate=%0d outputs=%0d %0s",
               INPUT_RATE_MSPS, observed_outputs, message);
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
        fail("AXI read-address timeout");
      @(negedge s_axi_aclk);
      s_axi_arvalid = 1'b0;
      timeout = 0;
      while (!s_axi_rvalid && timeout < 100) begin
        @(posedge s_axi_aclk);
        timeout = timeout + 1;
      end
      if (timeout == 100 || s_axi_rresp != 2'b00)
        fail("AXI read-response timeout/error");
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
      s_axi_wstrb = 4'hf;
      s_axi_awvalid = 1'b1;
      s_axi_wvalid = 1'b1;
      s_axi_bready = 1'b1;
      timeout = 0;
      while (!(s_axi_awready && s_axi_wready) && timeout < 100) begin
        @(posedge s_axi_aclk);
        timeout = timeout + 1;
      end
      if (timeout == 100)
        fail("AXI write-address/data timeout");
      @(negedge s_axi_aclk);
      s_axi_awvalid = 1'b0;
      s_axi_wvalid = 1'b0;
      timeout = 0;
      while (!s_axi_bvalid && timeout < 100) begin
        @(posedge s_axi_aclk);
        timeout = timeout + 1;
      end
      if (timeout == 100 || s_axi_bresp != 2'b00)
        fail("AXI write-response timeout/error");
      @(negedge s_axi_aclk);
      s_axi_bready = 1'b0;
    end
  endtask

  integer observed_outputs = 0;
  reg [96:0] expected_word;
  always @(negedge s_axi_aclk) begin
    if (s_axi_aresetn && dut.acquisition_sample_valid) begin
      if (DDC_ENABLED) begin
        if (observed_outputs >= summary_memory[0])
          fail("unexpected extra DDC output");
        expected_word = expected_memory[observed_outputs];
      end else begin
        if (observed_outputs >= INPUT_COUNT)
          fail("unexpected extra bypass output");
        expected_word = input_memory[observed_outputs];
      end
      if ({dut.acquisition_sample_gap, dut.acquisition_sample_index,
           dut.acquisition_sample_q, dut.acquisition_sample_i} !== expected_word) begin
        $display("ACQUISITION_RATE_MISMATCH expected=%025x actual=%025x",
                 expected_word,
                 {dut.acquisition_sample_gap, dut.acquisition_sample_index,
                  dut.acquisition_sample_q, dut.acquisition_sample_i});
        fail("rate-adapter payload mismatch");
      end
      observed_outputs = observed_outputs + 1;
    end
  end

  integer input_number;
  integer timeout;
  integer expected_output_count;
  reg [31:0] register_value;
  initial begin
    if (INPUT_RATE_MSPS == 60) begin
      $readmemh("../starlink_pss_acquisition/build/ddc_x4_input.mem", input_memory);
      $readmemh("../starlink_pss_acquisition/build/ddc_x4_upper_expected.mem", expected_memory);
      $readmemh("../starlink_pss_acquisition/build/ddc_x4_upper_summary.mem", summary_memory);
    end else begin
      $readmemh("../starlink_pss_acquisition/build/ddc_input.mem", input_memory);
      $readmemh("../starlink_pss_acquisition/build/ddc_upper_expected.mem", expected_memory);
      $readmemh("../starlink_pss_acquisition/build/ddc_upper_summary.mem", summary_memory);
    end
    expected_output_count = DDC_ENABLED ? summary_memory[0] : INPUT_COUNT;

    repeat (5) @(posedge s_axi_aclk);
    @(negedge s_axi_aclk);
    s_axi_aresetn = 1'b1;
    @(negedge sample_clk);
    sample_reset = 1'b0;
    repeat (6) @(posedge sample_clk);
    axi_write(8'h14, 32'd1);
    if (!dut.acquisition_enable)
      fail("AXI control did not enable acquisition");

    sample_enable = 1'b1;
    for (input_number = 0; input_number < INPUT_COUNT;
         input_number = input_number + 1) begin
      @(negedge sample_clk);
      if (dut.source_fifo_full)
        fail("source FIFO unexpectedly filled");
      sample_strobe = 1'b1;
      sample_gap = input_memory[input_number][96];
      sample_index = input_memory[input_number][95:32];
      sample_q = input_memory[input_number][31:16];
      sample_i = input_memory[input_number][15:0];
    end
    @(negedge sample_clk);
    sample_strobe = 1'b0;
    sample_enable = 1'b0;
    sample_gap = 1'b0;

    timeout = 0;
    while (observed_outputs != expected_output_count && timeout < 4000) begin
      @(negedge s_axi_aclk);
      timeout = timeout + 1;
    end
    if (timeout == 4000)
      fail("timed out waiting for adapted output stream");
    repeat (12) @(negedge s_axi_aclk);
    if (dut.ingress_dropped_sample_count != 0)
      fail("lossless wrapper test reported an ingress drop");

    axi_read(8'hb0, register_value);
    if (register_value != INPUT_RATE_MSPS)
      fail("INPUT_RATE_MSPS register mismatch");
    axi_read(8'he0, register_value);
    if (register_value != (DDC_ENABLED ? summary_memory[1] : 0))
      fail("DDC accepted counter register mismatch");
    axi_read(8'he4, register_value);
    if (register_value != (DDC_ENABLED ? summary_memory[0] : 0))
      fail("DDC emitted counter register mismatch");
    axi_read(8'he8, register_value);
    if (register_value != (DDC_ENABLED ? summary_memory[2] : 0))
      fail("DDC discontinuity counter register mismatch");
    axi_read(8'hec, register_value);
    if (register_value != (DDC_ENABLED ? summary_memory[3] : 0))
      fail("DDC saturation counter register mismatch");

    $display("ACQUISITION_RATE_PASS rate=%0d inputs=%0d outputs=%0d ddc=%0d drops=0",
             INPUT_RATE_MSPS, INPUT_COUNT, observed_outputs,
             DDC_ENABLED);
    $finish;
  end

endmodule
