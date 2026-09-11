// SPDX-License-Identifier: GPL-2.0
// One PRIVATE word and identity certificate, not publication authority.
// reference_metadata is the consumer's held first-word metadata. When the
// consumer loads that reference, inhibit same-edge refill for ONE clock so
// the next comparison uses the registered reference, not a wide bypass mux.
// The consumer still checks ordinal/LAST and owns final commit/reset/ACK.
// Hold a final slot until actual publication or quarantine; do not drop it
// merely because an unpublished RAM rewrite was accepted by the consumer.
`timescale 1ns/1ps
`default_nettype none
module starlink_pss_product_identity_stage (
  input wire clk, resetn, abort_epoch,
  input wire input_valid,
  output wire input_ready,
  input wire [35:0] input_data,
  input wire [8:0] input_position,
  input wire input_last,
  input wire [69:0] input_metadata, reference_metadata,
  input wire reference_update,
  output wire output_valid,
  input wire output_ready,
  output reg [35:0] output_data,
  output reg [8:0] output_position,
  output reg output_last, output_identity_good,
  output reg [69:0] output_metadata,
  output wire idle, fault
);
  reg full, fault_q;
  wire control_fault = (abort_epoch !== 1'b0) ||
    (input_valid !== 1'b0 && input_valid !== 1'b1) ||
    (output_ready !== 1'b0 && output_ready !== 1'b1);
  assign fault = resetn && (fault_q || control_fault);
  wire live = resetn && !fault;
  assign output_valid = live && full;
  assign input_ready = live && (!full || (output_ready && (reference_update === 1'b0)));
  assign idle = !full;
  wire take_input = input_valid && input_ready;
  wire take_output = output_valid && output_ready;
  wire identity_good = (input_metadata == reference_metadata) === 1'b1;
  always @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      full<=0;fault_q<=0;output_data<=0;output_position<=0;
      output_last<=0;output_identity_good<=0;output_metadata<=0;
    end else if (fault) begin
      full<=0;fault_q<=1;
    end else begin
      if (take_output) full<=0;
      if (take_input) begin
        full<=1;output_data<=input_data;output_position<=input_position;
        output_last<=input_last;output_identity_good<=identity_good;
        output_metadata<=input_metadata;
      end
    end
  end
endmodule
`default_nettype wire
