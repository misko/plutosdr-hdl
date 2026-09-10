`timescale 1ns/1fs
// Independent frozen old joiner/ROM/product chain. No candidate predicates or
// bubbled payload feed the reference. Valid joiner payload and EVERY product
// output bit remain exact, including invalid-cycle held output and overflow.
module starlink_pss_payload_bubble_shadow #(
  parameter KERNEL_ROM_FILE = "upper_edge_pss_kernel_q17.mem"
) (
  input wire clk, resetn, flush, input_valid, product_enable, output_ready,
  input wire [17:0] input_i, input_q,
  input wire [8:0] input_position,
  input wire [4:0] input_exponent,
  input wire input_last,
  input wire [63:0] input_start,
  input wire [86:0] join_controls,
  input wire [71:0] join_payload,
  input wire [118:0] product_outputs,
  input wire [144:0] product_private,
  output integer checks = 0,
  output integer join_occupied = 0,
  output integer product_occupied = 0,
  output integer join_invalid_differences = 0,
  output integer product_invalid_differences = 0
);
  wire j_ready, j_valid, j_last, j_accept, j_emit, j_complete, j_sequence, j_metadata, j_fault;
  wire [17:0] j_i, j_q, j_ki, j_kq;
  wire [8:0] j_position;
  wire [4:0] j_exponent;
  wire [63:0] j_start;
  wire p_ready, p_valid, p_last, p_overflow, p_overflow_pulse;
  wire [17:0] p_i, p_q;
  wire [8:0] p_position;
  wire [4:0] p_exponent;
  wire [63:0] p_start;
  starlink_pss_forward_kernel_join_7ee87258_golden #(
    .KERNEL_ROM_FILE(KERNEL_ROM_FILE), .DATA_WIDTH(18)) old_join (
    .clk(clk), .resetn(resetn), .flush(flush), .input_valid(input_valid), .input_ready(j_ready),
    .input_i(input_i), .input_q(input_q), .input_bin_index(input_position),
    .input_block_exponent(input_exponent), .input_last(input_last), .input_block_start_index(input_start),
    .output_valid(j_valid), .output_ready(p_ready), .output_i(j_i), .output_q(j_q),
    .output_kernel_i(j_ki), .output_kernel_q(j_kq), .output_bin_index(j_position),
    .output_block_exponent(j_exponent), .output_last(j_last), .output_block_start_index(j_start),
    .accepted_pulse(j_accept), .emitted_pulse(j_emit), .input_block_complete_pulse(j_complete),
    .sequence_error_pulse(j_sequence), .metadata_error_pulse(j_metadata), .protocol_fault(j_fault)
  );
  starlink_pss_spectrum_product_7ee87258_golden #(.DATA_WIDTH(18)) old_product (
    .clk(clk), .resetn(resetn), .flush(flush), .input_valid(j_valid && product_enable),
    .input_ready(p_ready), .input_i(j_i), .input_q(j_q), .kernel_i(j_ki), .kernel_q(j_kq),
    .input_bin_index(j_position), .input_block_exponent(j_exponent), .input_last(j_last),
    .input_block_start_index(j_start), .output_valid(p_valid), .output_ready(output_ready),
    .output_i(p_i), .output_q(p_q), .output_bin_index(p_position),
    .output_block_exponent(p_exponent), .output_last(p_last), .output_block_start_index(p_start),
    .output_overflow(p_overflow), .overflow_pulse(p_overflow_pulse)
  );
  // Observe settled state, not transient delta ordering at an active edge.
  always @(negedge clk) begin
    #0.000001;
    if (resetn && !flush) begin
      checks = checks + 1;
      if (join_controls !== {j_ready, j_valid, j_position, j_exponent, j_last, j_start,
          j_accept, j_emit, j_complete, j_sequence, j_metadata, j_fault})
        $fatal(1, "PAYLOAD_JOIN_CONTROL_MISMATCH");
      if (join_payload[35:0] !== {j_ki, j_kq})
        $fatal(1, "PAYLOAD_JOIN_KERNEL_MISMATCH");
      if (j_valid) begin
        join_occupied = join_occupied + 1;
        if (join_payload !== {j_i, j_q, j_ki, j_kq})
          $fatal(1, "PAYLOAD_JOIN_OCCUPIED_MISMATCH");
      end else if (join_payload[71:36] !== {j_i, j_q})
        join_invalid_differences = join_invalid_differences + 1;
      if (product_outputs !== {p_ready, p_valid, p_i, p_q, p_position, p_exponent,
          p_last, p_start, p_overflow, p_overflow_pulse})
        $fatal(1, "PAYLOAD_PRODUCT_OUTPUT_MISMATCH");
      if (product_private[144] !== old_product.product_valid)
        $fatal(1, "PAYLOAD_PRODUCT_TOKEN_MISMATCH");
      if (old_product.product_valid) begin
        product_occupied = product_occupied + 1;
        if (product_private[143:0] !== {old_product.product_ii, old_product.product_qq,
            old_product.product_iq, old_product.product_qi})
          $fatal(1, "PAYLOAD_PRODUCT_OCCUPIED_MISMATCH");
      end else if (product_private[143:0] !== {old_product.product_ii, old_product.product_qq,
          old_product.product_iq, old_product.product_qi})
        product_invalid_differences = product_invalid_differences + 1;
    end
  end
endmodule
