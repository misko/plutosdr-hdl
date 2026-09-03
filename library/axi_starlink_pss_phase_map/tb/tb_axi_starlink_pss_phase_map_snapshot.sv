`timescale 1ns/1ps

module tb_axi_starlink_pss_phase_map_snapshot;

  reg map_clk = 1'b0;
  reg s_axi_aclk = 1'b0;
  always #50 map_clk = ~map_clk;
  always #5 s_axi_aclk = ~s_axi_aclk;

  reg map_reset = 1'b1;
  reg [1:0] map_ready_mask = 2'b10;
  reg [31:0] map_generation_0 = 32'h1010_1010;
  reg [31:0] map_generation_1 = 32'h2020_2020;
  reg [63:0] map_start_index_0 = 64'h4040_4040_3030_3030;
  reg [63:0] map_start_index_1 = 64'h6060_6060_5050_5050;
  reg [31:0] accepted_score_count = 32'h7070_7070;
  reg [31:0] discarded_score_count = 32'h8080_8080;
  reg [31:0] discontinuity_abort_count = 32'h9090_9090;
  reg [31:0] map_publish_count = 32'ha0a0_a0a0;
  reg [31:0] map_overrun_count = 32'hb0b0_b0b0;
  reg [31:0] score_protocol_error_count = 32'hc0c0_c0c0;
  reg [31:0] map_arithmetic_overflow_count = 32'hd0d0_d0d0;
  reg [31:0] map_read_error_count = 32'he0e0_e0e0;
  reg [31:0] map_release_error_count = 32'hf0f0_f0f0;

  wire map_read_request;
  wire map_read_bank;
  wire [2:0] map_read_index;
  wire map_release;
  wire map_release_bank;
  wire acquisition_enable;
  wire acquisition_flush;
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

  reg [31:0] read_value;

  axi_starlink_pss_phase_map #(
    .PHASE_BINS       (8),
    .PHASE_INDEX_WIDTH(3),
    .TILE_FRAMES      (4),
    .MAP_WIDTH        (16)
  ) dut (
    .map_clk                       (map_clk),
    .map_reset                     (map_reset),
    .map_ready_mask                (map_ready_mask),
    .map_generation_0              (map_generation_0),
    .map_generation_1              (map_generation_1),
    .map_start_index_0             (map_start_index_0),
    .map_start_index_1             (map_start_index_1),
    .map_read_request              (map_read_request),
    .map_read_bank                 (map_read_bank),
    .map_read_index                (map_read_index),
    .map_read_valid                (1'b0),
    .map_read_data                 (16'd0),
    .map_read_error                (1'b0),
    .map_release                   (map_release),
    .map_release_bank              (map_release_bank),
    .accepted_score_count          (accepted_score_count),
    .discarded_score_count         (discarded_score_count),
    .discontinuity_abort_count     (discontinuity_abort_count),
    .map_publish_count             (map_publish_count),
    .map_overrun_count             (map_overrun_count),
    .score_protocol_error_count    (score_protocol_error_count),
    .map_arithmetic_overflow_count (map_arithmetic_overflow_count),
    .map_read_error_count          (map_read_error_count),
    .map_release_error_count       (map_release_error_count),
    .acquisition_enable            (acquisition_enable),
    .acquisition_flush             (acquisition_flush),
    .irq                           (irq),
    .s_axi_aclk                    (s_axi_aclk),
    .s_axi_aresetn                 (s_axi_aresetn),
    .s_axi_awvalid                 (s_axi_awvalid),
    .s_axi_awaddr                  (s_axi_awaddr),
    .s_axi_awready                 (s_axi_awready),
    .s_axi_wvalid                  (s_axi_wvalid),
    .s_axi_wdata                   (s_axi_wdata),
    .s_axi_wstrb                   (s_axi_wstrb),
    .s_axi_wready                  (s_axi_wready),
    .s_axi_bvalid                  (s_axi_bvalid),
    .s_axi_bresp                   (s_axi_bresp),
    .s_axi_bready                  (s_axi_bready),
    .s_axi_arvalid                 (s_axi_arvalid),
    .s_axi_araddr                  (s_axi_araddr),
    .s_axi_arready                 (s_axi_arready),
    .s_axi_rvalid                  (s_axi_rvalid),
    .s_axi_rresp                   (s_axi_rresp),
    .s_axi_rdata                   (s_axi_rdata),
    .s_axi_rready                  (s_axi_rready),
    .s_axi_awprot                  (3'd0),
    .s_axi_arprot                  (3'd0)
  );

  task automatic fail;
    input [1023:0] message;
    begin
      $display("AXI_PHASE_MAP_SNAPSHOT_FAIL %0s", message);
      $fatal(1);
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

  task automatic expect_read;
    input [7:0] address;
    input [31:0] expected;
    begin
      axi_read(address, read_value);
      if (read_value !== expected) begin
        $display(
          "AXI_PHASE_MAP_SNAPSHOT_WORD address=0x%02x expected=0x%08x actual=0x%08x",
          address, expected, read_value
        );
        fail("snapshot register mismatch");
      end
    end
  endtask

  task automatic wait_snapshot;
    integer timeout;
    begin
      timeout = 0;
      read_value = 0;
      while (!read_value[0] && timeout < 100) begin
        axi_read(8'h34, read_value);
        timeout = timeout + 1;
      end
      if (timeout == 100 || read_value[1])
        fail("snapshot did not complete");
    end
  endtask

  task automatic check_first_snapshot;
    begin
      expect_read(8'h3c, 32'h0000_0002);
      expect_read(8'h40, 32'h1010_1010);
      expect_read(8'h44, 32'h2020_2020);
      expect_read(8'h48, 32'h3030_3030);
      expect_read(8'h4c, 32'h4040_4040);
      expect_read(8'h50, 32'h5050_5050);
      expect_read(8'h54, 32'h6060_6060);
      expect_read(8'h58, 32'h7070_7070);
      expect_read(8'h5c, 32'h8080_8080);
      expect_read(8'h60, 32'h9090_9090);
      expect_read(8'h64, 32'ha0a0_a0a0);
      expect_read(8'h68, 32'hb0b0_b0b0);
      expect_read(8'h6c, 32'hc0c0_c0c0);
      expect_read(8'h70, 32'hd0d0_d0d0);
      expect_read(8'h74, 32'he0e0_e0e0);
      expect_read(8'h78, 32'hf0f0_f0f0);
    end
  endtask

  task automatic check_second_snapshot;
    begin
      expect_read(8'h3c, 32'h0000_0001);
      expect_read(8'h40, 32'h1111_1111);
      expect_read(8'h44, 32'h2222_2222);
      expect_read(8'h48, 32'h3333_3333);
      expect_read(8'h4c, 32'h4444_4444);
      expect_read(8'h50, 32'h5555_5555);
      expect_read(8'h54, 32'h6666_6666);
      expect_read(8'h58, 32'h7777_7777);
      expect_read(8'h5c, 32'h8888_8888);
      expect_read(8'h60, 32'h9999_9999);
      expect_read(8'h64, 32'haaaa_aaaa);
      expect_read(8'h68, 32'hbbbb_bbbb);
      expect_read(8'h6c, 32'hcccc_cccc);
      expect_read(8'h70, 32'hdddd_dddd);
      expect_read(8'h74, 32'heeee_eeee);
      expect_read(8'h78, 32'hffff_ffff);
    end
  endtask

  initial begin
    repeat (3) @(posedge map_clk);
    @(negedge map_clk);
    map_reset = 1'b0;
    @(negedge s_axi_aclk);
    s_axi_aresetn = 1'b1;
    repeat (10) @(posedge s_axi_aclk);

    // The second request must be counted, not overwrite the in-flight toggle.
    axi_write(8'h30, 32'd1);
    axi_write(8'h30, 32'd1);
    wait (dut.snapshot_response_toggle == 1'b1);

    // Mutate every live source immediately after capture.  The first AXI
    // snapshot must remain the old coherent set until explicitly refreshed.
    map_ready_mask = 2'b01;
    map_generation_0 = 32'h1111_1111;
    map_generation_1 = 32'h2222_2222;
    map_start_index_0 = 64'h4444_4444_3333_3333;
    map_start_index_1 = 64'h6666_6666_5555_5555;
    accepted_score_count = 32'h7777_7777;
    discarded_score_count = 32'h8888_8888;
    discontinuity_abort_count = 32'h9999_9999;
    map_publish_count = 32'haaaa_aaaa;
    map_overrun_count = 32'hbbbb_bbbb;
    score_protocol_error_count = 32'hcccc_cccc;
    map_arithmetic_overflow_count = 32'hdddd_dddd;
    map_read_error_count = 32'heeee_eeee;
    map_release_error_count = 32'hffff_ffff;

    wait_snapshot();
    expect_read(8'h38, 32'd1);
    expect_read(8'h84, 32'd1);
    check_first_snapshot();

    axi_write(8'h30, 32'd1);
    wait_snapshot();
    expect_read(8'h38, 32'd2);
    expect_read(8'h84, 32'd1);
    check_second_snapshot();

    $display(
      "AXI_PHASE_MAP_SNAPSHOT_PASS words=16 coherent_sets=2 request_overruns=1 map_hz=10000000 axi_hz=100000000"
    );
    $finish;
  end

endmodule
