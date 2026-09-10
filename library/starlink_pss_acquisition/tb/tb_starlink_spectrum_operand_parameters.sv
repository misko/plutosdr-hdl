// Preflight only: inspect actual elaborated hierarchy, no product clocks.
`timescale 1ns/1ps
module tb_starlink_spectrum_operand_parameters;
  parameter integer REGISTER=0;
  starlink_pss_spectrum_product_operand_register #(
    .DATA_WIDTH(18), .REGISTER_OPERANDS(REGISTER), .BOUNDARY_ROUND_SAT(1)
  ) dut();
  initial begin
    if (REGISTER !== 0 && REGISTER !== 1) $fatal(1,"invalid probe REGISTER");
    if (dut.DATA_WIDTH !== 18 || dut.REGISTER_OPERANDS !== REGISTER ||
        dut.BOUNDARY_ROUND_SAT !== 1 || dut.arithmetic.DATA_WIDTH !== 18 ||
        dut.arithmetic.BOUNDARY_ROUND_SAT !== 1 ||
        $bits(dut.input_i) != 18 || $bits(dut.arithmetic.input_i) != 18)
      $fatal(1,"actual operand parameters differ");
    #1 $display("OPERAND_PARAMETERS_VERIFIED width=18 round=1 registered=%0d child_width=18 child_round=1 clocks=0",REGISTER);
    $finish(0);
  end
endmodule
