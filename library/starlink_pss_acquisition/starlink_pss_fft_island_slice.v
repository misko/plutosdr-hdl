// SPDX-License-Identifier: GPL-2.0
// Experimental single-clock FFT/product/IFFT loop. No receiver instantiation.
// Retains the existing service's two full banks, checks and local toggle ACK.
// Outer CDC banks, overlap scheduling, energy/scoring and visit fencing are
// caller/integration work. This slice accepts only one correlation block at a
// time; input and output obey ready/valid. A flush purges the whole epoch.
`timescale 1ns/1ps
module starlink_pss_fft_island_slice #(
  parameter KERNEL_ROM_FILE = "upper_edge_pss_kernel_q17.mem"
) (
  input wire clk, resetn, flush,
  input wire input_valid,
  output wire input_ready,
  input wire [35:0] input_data,
  input wire [8:0] input_position,
  input wire input_last,
  input wire [63:0] input_block_start,
  output wire output_valid,
  input wire output_ready,
  output wire [35:0] output_data,
  output wire [8:0] output_position,
  output wire output_last,
  output wire [74:0] output_metadata,
  output wire fault,
  output wire busy
);
  wire epoch_resetn = resetn && !flush;
  reg active, loading, fault_latched;
  wire service_fault, kernel_fault, product_overflow, overflow_pulse;
  wire service_input_ready, service_output_valid, service_output_last;
  wire [35:0] service_output_data;
  wire [8:0] service_output_position;
  wire [74:0] service_output_metadata;
  wire inverse_result = service_output_metadata[74];
  wire joined_valid, joined_ready, joined_last, forward_ready;
  wire [17:0] joined_i, joined_q, kernel_i, kernel_q;
  wire [8:0] joined_position;
  wire [4:0] joined_exponent;
  wire [63:0] joined_start;
  wire product_valid, product_last;
  wire [17:0] product_i, product_q;
  wire [8:0] product_position;
  wire [4:0] product_exponent;
  wire [63:0] product_start;
  wire raw_grant = !active || loading;
  wire product_ready = !raw_grant && service_input_ready && !fault;
  assign fault = fault_latched || service_fault || kernel_fault || product_overflow;
  assign busy = active;
  assign input_ready = epoch_resetn && raw_grant && service_input_ready && !fault;
  assign output_valid = epoch_resetn && service_output_valid && inverse_result && !fault;
  assign output_data = service_output_data;
  assign output_position = service_output_position;
  assign output_last = service_output_last;
  assign output_metadata = service_output_metadata;

  always @(posedge clk) begin
    if (!epoch_resetn) begin
      active <= 0;
      loading <= 0;
      fault_latched <= 0;
    end else begin
      if (fault || overflow_pulse) fault_latched <= 1;
      if (input_valid && input_ready) begin
        active <= 1;
        loading <= !input_last;
      end
      if (output_valid && output_ready && output_last) active <= 0;
    end
  end

  starlink_pss_shared_realtime_xfft_service service (
    .clk(clk), .fft_clk(clk), .resetn(epoch_resetn), .fft_resetn(epoch_resetn),
    .input_valid(!fault && (raw_grant ? input_valid : product_valid)),
    .input_ready(service_input_ready),
    .input_data(raw_grant ? input_data : {product_q, product_i}),
    .input_position(raw_grant ? input_position : product_position),
    .input_last(raw_grant ? input_last : product_last),
    .input_metadata(raw_grant ? {1'b0, input_block_start, 5'b0} :
                               {1'b1, product_start, product_exponent}),
    .output_valid(service_output_valid),
    .output_ready(!fault && (inverse_result ? output_ready : forward_ready)),
    .output_data(service_output_data), .output_position(service_output_position),
    .output_last(service_output_last), .output_metadata(service_output_metadata),
    .service_fault(service_fault)
  );
  starlink_pss_forward_kernel_join #(.KERNEL_ROM_FILE(KERNEL_ROM_FILE), .DATA_WIDTH(18)) joiner (
    .clk(clk), .resetn(epoch_resetn), .flush(flush),
    .input_valid(service_output_valid && !inverse_result && !fault),
    .input_ready(forward_ready),
    .input_i(service_output_data[17:0]), .input_q(service_output_data[35:18]),
    .input_bin_index(service_output_position),
    .input_block_exponent(service_output_metadata[4:0]),
    .input_last(service_output_last), .input_block_start_index(service_output_metadata[73:10]),
    .output_valid(joined_valid), .output_ready(joined_ready),
    .output_i(joined_i), .output_q(joined_q), .output_kernel_i(kernel_i), .output_kernel_q(kernel_q),
    .output_bin_index(joined_position), .output_block_exponent(joined_exponent),
    .output_last(joined_last), .output_block_start_index(joined_start),
    .accepted_pulse(), .emitted_pulse(), .input_block_complete_pulse(),
    .sequence_error_pulse(), .metadata_error_pulse(), .protocol_fault(kernel_fault)
  );
  starlink_pss_spectrum_product #(.DATA_WIDTH(18)) product (
    .clk(clk), .resetn(epoch_resetn), .flush(flush),
    .input_valid(joined_valid && !fault), .input_ready(joined_ready),
    .input_i(joined_i), .input_q(joined_q), .kernel_i(kernel_i), .kernel_q(kernel_q),
    .input_bin_index(joined_position), .input_block_exponent(joined_exponent),
    .input_last(joined_last), .input_block_start_index(joined_start),
    .output_valid(product_valid), .output_ready(product_ready),
    .output_i(product_i), .output_q(product_q), .output_bin_index(product_position),
    .output_block_exponent(product_exponent), .output_last(product_last),
    .output_block_start_index(product_start), .output_overflow(product_overflow),
    .overflow_pulse(overflow_pulse)
  );
endmodule
