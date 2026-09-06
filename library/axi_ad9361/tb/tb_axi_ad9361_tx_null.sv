`timescale 1ns/1ps

module tb_axi_ad9361_tx_null;

  reg          up_wreq = 1'b0;
  reg  [13:0]  up_waddr = 14'd0;
  wire         up_wack_1r1t;
  wire         up_wack_2r2t;
  reg          up_rreq = 1'b0;
  reg  [13:0]  up_raddr = 14'd0;
  wire [31:0]  up_rdata;
  wire         up_rack_1r1t;
  wire         up_rack_2r2t;

  axi_ad9361_tx_null #(
    .MODE_1R1T (1)
  ) dut_1r1t (
    .up_wreq (up_wreq),
    .up_waddr (up_waddr),
    .up_wack (up_wack_1r1t),
    .up_rreq (up_rreq),
    .up_raddr (up_raddr),
    .up_rdata (up_rdata),
    .up_rack (up_rack_1r1t)
  );

  axi_ad9361_tx_null #(
    .MODE_1R1T (0)
  ) dut_2r2t (
    .up_wreq (up_wreq),
    .up_waddr (up_waddr),
    .up_wack (up_wack_2r2t),
    .up_rreq (up_rreq),
    .up_raddr (up_raddr),
    .up_rdata (),
    .up_rack (up_rack_2r2t)
  );

  task automatic check_read;
    input [13:0] address;
    input expected_ack_1r1t;
    input expected_ack_2r2t;
    begin
      up_raddr = address;
      up_rreq = 1'b1;
      #1;
      if (up_rack_1r1t !== expected_ack_1r1t ||
          up_rack_2r2t !== expected_ack_2r2t || up_rdata !== 32'd0) begin
        $display("TX_NULL_READ_FAIL address=0x%04x ack_1r1t=%b expected_1r1t=%b ack_2r2t=%b expected_2r2t=%b data=0x%08x",
                 address, up_rack_1r1t, expected_ack_1r1t,
                 up_rack_2r2t, expected_ack_2r2t, up_rdata);
        $fatal(1);
      end
      up_rreq = 1'b0;
    end
  endtask

  task automatic check_write;
    input [13:0] address;
    input expected_ack_1r1t;
    input expected_ack_2r2t;
    begin
      up_waddr = address;
      up_wreq = 1'b1;
      #1;
      if (up_wack_1r1t !== expected_ack_1r1t ||
          up_wack_2r2t !== expected_ack_2r2t) begin
        $display("TX_NULL_WRITE_FAIL address=0x%04x ack_1r1t=%b expected_1r1t=%b ack_2r2t=%b expected_2r2t=%b",
                 address, up_wack_1r1t, expected_ack_1r1t,
                 up_wack_2r2t, expected_ack_2r2t);
        $fatal(1);
      end
      up_wreq = 1'b0;
    end
  endtask

  initial begin
    // ADC common, channel, and delay addresses must never be acknowledged by
    // the removed TX hierarchy. These are the reads Linux needs for version,
    // reset, PN status, and receive interface tuning.
    check_read(14'h0000, 1'b0, 1'b0);
    check_read(14'h0010, 1'b0, 1'b0);
    check_read(14'h0100, 1'b0, 1'b0);
    check_read(14'h0200, 1'b0, 1'b0);
    check_write(14'h0000, 1'b0, 1'b0);
    check_write(14'h0100, 1'b0, 1'b0);

    // Preserve bounded zero-valued responses for the former DAC common bank
    // and the two channels that exist in compile-time 1R1T mode.
    check_read(14'h1000, 1'b1, 1'b1);
    check_read(14'h107f, 1'b1, 1'b1);
    check_read(14'h1100, 1'b1, 1'b1);
    check_read(14'h111f, 1'b1, 1'b1);
    check_write(14'h1002, 1'b1, 1'b1);
    check_write(14'h1110, 1'b1, 1'b1);

    // Channels 2/3 and the disabled DAC delay bank remain absent in 1R1T.
    check_read(14'h1120, 1'b0, 1'b1);
    check_read(14'h1130, 1'b0, 1'b1);
    check_read(14'h113f, 1'b0, 1'b1);
    check_read(14'h1140, 1'b0, 1'b0);
    check_read(14'h1200, 1'b0, 1'b0);
    check_read(14'h1300, 1'b0, 1'b0);

    $display("AXI_AD9361_TX_NULL_TEST_PASS");
    $finish;
  end

endmodule
