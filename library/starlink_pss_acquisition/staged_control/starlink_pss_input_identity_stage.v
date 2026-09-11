// SPDX-License-Identifier: GPL-2.0
// Experimental one-beat PRIVATE staging boundary, not an FFT validator.
// Identity is sampled with the payload at input acceptance. The consumer MUST
// combine output_identity_good with its position/TLAST/demand checks before
// certifying a beat to the FFT. output_valid alone is NOT certification.
// The admitted descriptor must belong to this input job at acceptance. Holding
// this register does not reserve the upstream bank; final-word bank ACK may
// precede FFT consumption only because the complete final beat is retained here.
// One slot permits simultaneous retire/refill; it cannot conceal upstream gaps
// once realtime FFT demand starts. Abort quarantines until coordinated reset.
`timescale 1ns/1ps
`default_nettype none
module starlink_pss_input_identity_stage (
  input wire clk, resetn, abort_epoch,
  input wire input_valid,
  output wire input_ready,
  input wire [35:0] input_data,
  input wire [8:0] input_position,
  input wire input_last,
  input wire [69:0] input_metadata, job_descriptor,
  output wire output_valid,
  input wire output_ready,
  output reg [35:0] output_data,
  output reg [8:0] output_position,
  output reg output_last, output_identity_good,
  output wire idle, fault
);
  reg full, fault_q;
  wire control_fault = (abort_epoch !== 1'b0) ||
    (input_valid !== 1'b0 && input_valid !== 1'b1) ||
    (output_ready !== 1'b0 && output_ready !== 1'b1);
  assign fault = resetn && (fault_q || control_fault);
  wire live = resetn && !fault;
  assign output_valid = live && full;
  assign input_ready = live && (!full || output_ready);
  assign idle = !full;
  wire take_input = input_valid && input_ready;
  wire take_output = output_valid && output_ready;
  // Unknown identity cannot certify delivery, including X==X and Z==Z.
  wire identity_good = (input_metadata == job_descriptor) === 1'b1;
  always @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      full<=0;fault_q<=0;output_data<=0;output_position<=0;
      output_last<=0;output_identity_good<=0;
    end else if (fault) begin
      full<=0;fault_q<=1;
    end else begin
      if (take_output) full<=0;
      // Input wins only for a real simultaneous retire/refill, never a stall.
      if (take_input) begin
        full<=1;output_data<=input_data;output_position<=input_position;
        output_last<=input_last;output_identity_good<=identity_good;
      end
    end
  end
endmodule
`default_nettype wire
