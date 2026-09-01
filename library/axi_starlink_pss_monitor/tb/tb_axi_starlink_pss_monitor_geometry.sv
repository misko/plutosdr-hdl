`timescale 1ns/1ps

module tb_axi_starlink_pss_monitor_geometry;

  axi_starlink_pss_monitor #(.RATE_MSPS(15)) dut_15 ();
  axi_starlink_pss_monitor #(.RATE_MSPS(30)) dut_30 ();
  axi_starlink_pss_monitor #(.RATE_MSPS(60)) dut_60 ();

  initial begin
    if (dut_15.GEOMETRY != 32'h00e88408)
      $fatal(1, "15 MS/s geometry register encoding mismatch");
    if (dut_30.GEOMETRY != 32'h01d10810)
      $fatal(1, "30 MS/s geometry register encoding mismatch");
    if (dut_60.GEOMETRY != 32'h03a21020)
      $fatal(1, "60 MS/s geometry register encoding mismatch");
    $display("PASS axi_starlink_pss_monitor 15/30/60 geometry encoding");
    $finish;
  end

endmodule
