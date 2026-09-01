`timescale 1ns/1ps

module tb_starlink_sat_add48;
  reg signed [47:0] accumulator;
  reg signed [35:0] addend;
  wire signed [47:0] result;
  wire saturated;

  starlink_sat_add48 dut (
    .i_accumulator (accumulator),
    .i_addend      (addend),
    .o_result      (result),
    .o_saturated   (saturated)
  );

  task automatic check_add;
    input signed [47:0] test_accumulator;
    input signed [35:0] test_addend;
    input signed [47:0] expected_result;
    input expected_saturated;
    begin
      accumulator = test_accumulator;
      addend = test_addend;
      #1;
      if ((result !== expected_result) ||
          (saturated !== expected_saturated)) begin
        $fatal(1,
               "sat-add mismatch acc=%0d add=%0d got=(%0d,%0d) expected=(%0d,%0d)",
               test_accumulator, test_addend, result, saturated,
               expected_result, expected_saturated);
      end
    end
  endtask

  initial begin
    accumulator = 48'sd0;
    addend = 36'sd0;

    check_add(48'sd10, -36'sd3, 48'sd7, 1'b0);
    check_add(48'sh7ffffffffffd, 36'sd2, 48'sh7fffffffffff, 1'b0);
    check_add(48'sh7ffffffffffd, 36'sd3, 48'sh7fffffffffff, 1'b1);
    check_add(48'sh7fffffffffff, 36'sd1, 48'sh7fffffffffff, 1'b1);
    // A later overflowing tap at an already saturated rail is another event,
    // matching the Python oracle's per-tap accounting.
    check_add(48'sh7fffffffffff, 36'sd7, 48'sh7fffffffffff, 1'b1);

    check_add(48'sh800000000002, -36'sd2, 48'sh800000000000, 1'b0);
    check_add(48'sh800000000002, -36'sd3, 48'sh800000000000, 1'b1);
    check_add(48'sh800000000000, -36'sd1, 48'sh800000000000, 1'b1);

    $display("SATURATION_PRIMITIVE_PASS boundary_vectors=8");
    $finish;
  end
endmodule
