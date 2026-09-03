`timescale 1ns/1ps

module tb_axi_starlink_pss_phase_map_sync_rate #(
  parameter integer INPUT_RATE_MSPS = 15
);

  localparam [30:0] COEFFICIENT_ENERGY =
      (INPUT_RATE_MSPS == 60) ? 31'd1073765335 :
      ((INPUT_RATE_MSPS == 30) ? 31'd1073744004 : 31'd1073742825);
  localparam integer DDC_ENABLED = INPUT_RATE_MSPS != 15;
  localparam [31:0] EXPECTED_VERSION = (INPUT_RATE_MSPS == 60) ?
      32'h0001_0003 :
      ((INPUT_RATE_MSPS == 30) ? 32'h0001_0002 : 32'h0001_0001);
  localparam [31:0] EXPECTED_DDC_CONFIG = (INPUT_RATE_MSPS == 60) ?
      32'h020f_0403 :
      ((INPUT_RATE_MSPS == 30) ? 32'h000f_0203 : 32'h000f_0202);
  localparam [31:0] EXPECTED_DDC_DELAY = (INPUT_RATE_MSPS == 60) ?
      32'd21 : ((INPUT_RATE_MSPS == 30) ? 32'd7 : 32'd0);
  localparam [255:0] EXPECTED_DDC_CONTRACT = (INPUT_RATE_MSPS == 60) ?
      256'h8e807d15d5372b0a9669d1190d899697e7c2911a73ddfb23095806c2a31de5b2 :
      256'h731426047077b036f9213db3574e4a556fd424b97a293843bd6ee085c2bf33af;

  reg clk = 1'b0;
  always #5 clk = ~clk;
  reg resetn = 1'b0;

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

  wire map_read_request;
  wire map_read_bank;
  wire [14:0] map_read_index;
  wire map_release;
  wire map_release_bank;
  wire acquisition_enable;
  wire acquisition_flush;
  wire irq;

  axi_starlink_pss_phase_map_sync #(
    .INPUT_RATE_MSPS    (INPUT_RATE_MSPS),
    .COEFFICIENT_ENERGY(COEFFICIENT_ENERGY)
  ) dut (
    .map_clk                              (clk),
    .map_reset                            (!resetn),
    .map_ready_mask                       (2'd0),
    .map_generation_0                     (32'd0),
    .map_generation_1                     (32'd0),
    .map_start_index_0                    (64'd0),
    .map_start_index_1                    (64'd0),
    .map_read_request                     (map_read_request),
    .map_read_bank                        (map_read_bank),
    .map_read_index                       (map_read_index),
    .map_read_valid                       (1'b0),
    .map_read_data                        (16'd0),
    .map_read_error                       (1'b0),
    .map_release                          (map_release),
    .map_release_bank                     (map_release_bank),
    .accepted_score_count                 (32'd0),
    .discarded_score_count                (32'd0),
    .discontinuity_abort_count            (32'd0),
    .map_publish_count                    (32'd0),
    .map_overrun_count                    (32'd0),
    .score_protocol_error_count           (32'd0),
    .map_arithmetic_overflow_count        (32'd0),
    .map_read_error_count                 (32'd0),
    .map_release_error_count              (32'd0),
    .detector_health_flags                (32'd0),
    .ingress_overflow_sticky              (1'b0),
    .ingress_dropped_sample_count         (32'd0),
    .ingress_fifo_level                   (16'd0),
    .ingress_maximum_fifo_level           (16'd0),
    .scheduler_gap_count                  (32'd0),
    .scheduler_index_error_count          (32'd0),
    .scheduler_overflow_count             (32'd0),
    .detector_fault_count                 (32'd0),
    .score_phase_index_discontinuity_count(32'd0),
    .score_denominator_zero_count         (32'd0),
    .candidate_fifo_stored_count          (10'd0),
    .candidate_fifo_maximum_stored_count  (10'd0),
    .ddc_accepted_sample_count            (32'd500),
    .ddc_emitted_sample_count             (32'd229),
    .ddc_discontinuity_count              (32'd3),
    .ddc_saturation_event_count           (32'd1),
    .acquisition_enable                   (acquisition_enable),
    .acquisition_flush                    (acquisition_flush),
    .irq                                  (irq),
    .s_axi_aclk                           (clk),
    .s_axi_aresetn                        (resetn),
    .s_axi_awvalid                        (s_axi_awvalid),
    .s_axi_awaddr                         (s_axi_awaddr),
    .s_axi_awready                        (s_axi_awready),
    .s_axi_wvalid                         (s_axi_wvalid),
    .s_axi_wdata                          (s_axi_wdata),
    .s_axi_wstrb                          (s_axi_wstrb),
    .s_axi_wready                         (s_axi_wready),
    .s_axi_bvalid                         (s_axi_bvalid),
    .s_axi_bresp                          (s_axi_bresp),
    .s_axi_bready                         (s_axi_bready),
    .s_axi_arvalid                        (s_axi_arvalid),
    .s_axi_araddr                         (s_axi_araddr),
    .s_axi_arready                        (s_axi_arready),
    .s_axi_rvalid                         (s_axi_rvalid),
    .s_axi_rresp                          (s_axi_rresp),
    .s_axi_rdata                          (s_axi_rdata),
    .s_axi_rready                         (s_axi_rready),
    .s_axi_awprot                         (3'd0),
    .s_axi_arprot                         (3'd0)
  );

  task automatic fail(input string message);
    begin
      $display("PSMA_RATE_FAIL rate=%0d %0s", INPUT_RATE_MSPS, message);
      $fatal(1);
    end
  endtask

  task automatic axi_read(input [7:0] address, output [31:0] data);
    integer timeout;
    begin
      @(negedge clk);
      s_axi_araddr = address;
      s_axi_arvalid = 1'b1;
      s_axi_rready = 1'b1;
      timeout = 0;
      while (!s_axi_arready && timeout < 100) begin
        @(posedge clk);
        timeout = timeout + 1;
      end
      if (timeout == 100)
        fail("AXI read-address timeout");
      @(negedge clk);
      s_axi_arvalid = 1'b0;
      timeout = 0;
      while (!s_axi_rvalid && timeout < 100) begin
        @(posedge clk);
        timeout = timeout + 1;
      end
      if (timeout == 100 || s_axi_rresp != 2'b00)
        fail("AXI read-response timeout/error");
      data = s_axi_rdata;
      @(negedge clk);
      s_axi_rready = 1'b0;
    end
  endtask

  task automatic axi_write(input [7:0] address, input [31:0] data);
    integer timeout;
    begin
      @(negedge clk);
      s_axi_awaddr = address;
      s_axi_wdata = data;
      s_axi_wstrb = 4'hf;
      s_axi_awvalid = 1'b1;
      s_axi_wvalid = 1'b1;
      s_axi_bready = 1'b1;
      timeout = 0;
      while (!(s_axi_awready && s_axi_wready) && timeout < 100) begin
        @(posedge clk);
        timeout = timeout + 1;
      end
      if (timeout == 100)
        fail("AXI write-address/data timeout");
      @(negedge clk);
      s_axi_awvalid = 1'b0;
      s_axi_wvalid = 1'b0;
      timeout = 0;
      while (!s_axi_bvalid && timeout < 100) begin
        @(posedge clk);
        timeout = timeout + 1;
      end
      if (timeout == 100 || s_axi_bresp != 2'b00)
        fail("AXI write-response timeout/error");
      @(negedge clk);
      s_axi_bready = 1'b0;
    end
  endtask

  task automatic expect_register(input [7:0] address, input [31:0] expected);
    reg [31:0] observed;
    begin
      axi_read(address, observed);
      if (observed !== expected) begin
        $display("PSMA_RATE_REGISTER address=0x%02x expected=0x%08x observed=0x%08x",
                 address, expected, observed);
        fail("register mismatch");
      end
    end
  endtask

  initial begin
    repeat (5) @(posedge clk);
    @(negedge clk);
    resetn = 1'b1;
    repeat (4) @(posedge clk);

    expect_register(8'h00, 32'h5053_4d41);
    expect_register(8'h04, EXPECTED_VERSION);
    expect_register(8'h10, DDC_ENABLED ? 32'h0000_007f : 32'h0000_003f);
    expect_register(8'hb0, INPUT_RATE_MSPS);
    expect_register(8'hb4, EXPECTED_DDC_CONFIG);
    expect_register(8'hb8, EXPECTED_DDC_DELAY);
    expect_register(8'hbc, {1'b0, COEFFICIENT_ENERGY});

    expect_register(8'hc0, DDC_ENABLED ? EXPECTED_DDC_CONTRACT[255:224] : 32'd0);
    expect_register(8'hc4, DDC_ENABLED ? EXPECTED_DDC_CONTRACT[223:192] : 32'd0);
    expect_register(8'hc8, DDC_ENABLED ? EXPECTED_DDC_CONTRACT[191:160] : 32'd0);
    expect_register(8'hcc, DDC_ENABLED ? EXPECTED_DDC_CONTRACT[159:128] : 32'd0);
    expect_register(8'hd0, DDC_ENABLED ? EXPECTED_DDC_CONTRACT[127:96] : 32'd0);
    expect_register(8'hd4, DDC_ENABLED ? EXPECTED_DDC_CONTRACT[95:64] : 32'd0);
    expect_register(8'hd8, DDC_ENABLED ? EXPECTED_DDC_CONTRACT[63:32] : 32'd0);
    expect_register(8'hdc, DDC_ENABLED ? EXPECTED_DDC_CONTRACT[31:0] : 32'd0);
    expect_register(8'he0, DDC_ENABLED ? 32'd500 : 32'd0);
    expect_register(8'he4, DDC_ENABLED ? 32'd229 : 32'd0);
    expect_register(8'he8, DDC_ENABLED ? 32'd3 : 32'd0);
    expect_register(8'hec, DDC_ENABLED ? 32'd1 : 32'd0);

    axi_write(8'h30, 32'd1);
    repeat (3) @(posedge clk);
    expect_register(8'h88, DDC_ENABLED ? 32'h0000_2000 : 32'd0);

    $display("PSMA_RATE_PASS rate=%0d version=%0d.%0d ddc=%0d energy=%0d",
             INPUT_RATE_MSPS, 1,
             INPUT_RATE_MSPS == 60 ? 3 : (INPUT_RATE_MSPS == 30 ? 2 : 1),
             DDC_ENABLED, COEFFICIENT_ENERGY);
    $finish;
  end

endmodule
