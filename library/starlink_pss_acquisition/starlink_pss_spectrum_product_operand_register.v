// Standalone, default-off elastic operand boundary. Not integrated into bank.
// REGISTER_OPERANDS=1 adds exactly one no-stall clock of latency and one token
// of storage. It does not change multiplication, rounding or overflow semantics.
`timescale 1ns/1ps

module starlink_pss_spectrum_product_operand_register #(
  parameter integer DATA_WIDTH = 24,
  parameter integer REGISTER_OPERANDS = 0,
  parameter integer BOUNDARY_ROUND_SAT = 0
) (
  input wire clk,
  input wire resetn,
  input wire flush,
  input wire input_valid,
  output wire input_ready,
  input wire signed [DATA_WIDTH-1:0] input_i,
  input wire signed [DATA_WIDTH-1:0] input_q,
  input wire signed [DATA_WIDTH-1:0] kernel_i,
  input wire signed [DATA_WIDTH-1:0] kernel_q,
  input wire [8:0] input_bin_index,
  input wire [4:0] input_block_exponent,
  input wire input_last,
  input wire [63:0] input_block_start_index,
  output wire output_valid,
  input wire output_ready,
  output wire signed [DATA_WIDTH-1:0] output_i,
  output wire signed [DATA_WIDTH-1:0] output_q,
  output wire [8:0] output_bin_index,
  output wire [4:0] output_block_exponent,
  output wire output_last,
  output wire [63:0] output_block_start_index,
  output wire output_overflow,
  output wire overflow_pulse
);
  initial begin
    if (REGISTER_OPERANDS !== 0 && REGISTER_OPERANDS !== 1)
      $fatal(1, "REGISTER_OPERANDS must be zero or one");
    if ((DATA_WIDTH >= 1) !== 1'b1)
      $fatal(1, "DATA_WIDTH must be a positive integer");
  end

  wire core_valid, core_ready;
  wire signed [DATA_WIDTH-1:0] core_i, core_q, core_kernel_i, core_kernel_q;
  wire [8:0] core_bin;
  wire [4:0] core_exponent;
  wire core_last;
  wire [63:0] core_start;

  generate if (REGISTER_OPERANDS == 1) begin : registered_operands
    // Both complex operands and every metadata field share one ownership bit.
    // 4*DATA_WIDTH + 79 payload bits, plus one valid bit. No fall-through data.
    reg [4*DATA_WIDTH+79-1:0] payload;
    reg valid;
    wire ready = !valid || core_ready;
    assign input_ready = resetn && !flush && ready;
    assign core_valid = valid;
    assign {core_i, core_q, core_kernel_i, core_kernel_q,
            core_bin, core_exponent, core_last, core_start} = payload;

    always @(posedge clk) begin
      if (!resetn || flush) begin
        valid <= 1'b0;
        payload <= 0;
      end else if (ready) begin
        valid <= input_valid;
        if (input_valid)
          payload <= {input_i, input_q, kernel_i, kernel_q,
                      input_bin_index, input_block_exponent, input_last,
                      input_block_start_index};
      end
    end
  end else begin : passthrough
    assign input_ready = core_ready;
    assign core_valid = input_valid;
    assign {core_i, core_q, core_kernel_i, core_kernel_q,
            core_bin, core_exponent, core_last, core_start} =
           {input_i, input_q, kernel_i, kernel_q,
            input_bin_index, input_block_exponent, input_last,
            input_block_start_index};
  end endgenerate

  // Intentionally unchanged arithmetic implementation, including its optional
  // combinational rounding choice and insertion-time overflow_pulse contract.
  starlink_pss_spectrum_product #(
    .DATA_WIDTH(DATA_WIDTH), .BOUNDARY_ROUND_SAT(BOUNDARY_ROUND_SAT)
  ) arithmetic (
    .clk(clk), .resetn(resetn), .flush(flush),
    .input_valid(core_valid), .input_ready(core_ready),
    .input_i(core_i), .input_q(core_q),
    .kernel_i(core_kernel_i), .kernel_q(core_kernel_q),
    .input_bin_index(core_bin), .input_block_exponent(core_exponent),
    .input_last(core_last), .input_block_start_index(core_start),
    .output_valid(output_valid), .output_ready(output_ready),
    .output_i(output_i), .output_q(output_q),
    .output_bin_index(output_bin_index), .output_block_exponent(output_block_exponent),
    .output_last(output_last), .output_block_start_index(output_block_start_index),
    .output_overflow(output_overflow), .overflow_pulse(overflow_pulse)
  );
endmodule
