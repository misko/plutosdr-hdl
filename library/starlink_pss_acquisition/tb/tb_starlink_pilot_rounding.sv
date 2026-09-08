// Direct arithmetic boundary checks, independent of whether a filter fixture
// happens to produce an exact half-way or saturation-threshold accumulator.
`timescale 1ns/1ps
module tb_starlink_pilot_rounding;
  starlink_pilot_ddc dut (.clk(1'b0), .resetn(1'b0), .flush(1'b1),
    .edge_upper(1'b1), .visit_id(32'd1), .input_valid(1'b0), .input_gap(1'b0),
    .input_i(16'sd0), .input_q(16'sd0), .input_index(64'd0),
    .input_support_valid(1'b0));
  integer fd, fields, mode, count;
  reg signed [43:0] value;
  reg [16:0] expected, actual;
  initial begin
    fd = $fopen("rounding.txt", "r");
    if (!fd) $fatal(1, "cannot open rounding vectors");
    count = 0;
    while (!$feof(fd)) begin
      fields = $fscanf(fd, "%d %h %h\n", mode, value, expected);
      if (fields != 3) $fatal(1, "malformed rounding vector");
      case (mode)
        0: actual = dut.quantize_q16(value[34:0]);
        1: actual = dut.halfband.quantize_q17(value[38:0]);
        2: actual = dut.fir3.quantize_q17(value);
        default: $fatal(1, "invalid rounding mode");
      endcase
      if (actual !== expected)
        $fatal(1, "rounding mismatch mode=%0d value=%0d got=%h expected=%h",
               mode, value, actual, expected);
      count = count + 1;
    end
    $fclose(fd);
    $display("PILOT_ROUNDING_PASS count=%0d", count);
    $finish(0);
  end
endmodule
