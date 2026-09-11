// SPDX-License-Identifier: GPL-2.0
// Private whole-block storage between realtime FFT return and kernel replay.
// Reserve BEFORE starting the FFT. Capture has no downstream READY dependency.
// seal_valid is a separate, same-epoch qualification from the result guard;
// correct local framing alone is NEVER permission to replay a block.
// The caller retains vendor/input/status/final-fence checks, immediate public
// fault vetoes, a bounded job watchdog and common epoch reset. This module does
// not provide CDC, RF timing accuracy, a second bank or publication authority.
`timescale 1ns/1ps
`default_nettype none
module starlink_pss_forward_return_bank #(
  parameter integer ADDRESS_WIDTH = 9
) (
  input wire clk, resetn, abort_epoch,
  input wire reserve_valid,
  output wire reserve_ready,
  input wire [69:0] reserve_descriptor,
  input wire capture_valid,
  output wire capture_ready,
  input wire [35:0] capture_data,
  input wire [ADDRESS_WIDTH-1:0] capture_position,
  input wire capture_last,
  input wire [4:0] capture_exponent,
  input wire [69:0] capture_descriptor,
  input wire seal_valid,
  output wire output_valid,
  input wire output_ready,
  output wire [35:0] output_data,
  output reg [ADDRESS_WIDTH-1:0] output_position,
  output wire output_last,
  output wire [4:0] output_exponent,
  output wire [69:0] output_descriptor,
  output reg done_pulse,
  output wire busy, fault
);
  localparam integer DEPTH = 1 << ADDRESS_WIDTH;
  localparam [1:0] IDLE=0, CAPTURE=1, WAIT_SEAL=2, REPLAY=3;
  reg [1:0] state;
  reg fault_q, replay_valid;
  reg [ADDRESS_WIDTH:0] write_count, read_count;
  reg [69:0] descriptor;
  reg [4:0] exponent;
  (* ram_style = "block" *) reg [35:0] payload [0:DEPTH-1];
  reg [35:0] read_data;
  initial if (ADDRESS_WIDTH < 2 || ADDRESS_WIDTH > 9)
    $fatal(1,"forward return bank requires 4..512 words");

  assign reserve_ready = resetn && !fault_q && !abort_epoch && state==IDLE;
  // Private capture capacity is strictly local; malformed input may write
  // private RAM on its rejection edge, but fault/reset suppresses all replay.
  assign capture_ready = resetn && !fault_q && !abort_epoch &&
    state==CAPTURE && write_count<DEPTH;
  wire capture_take = capture_valid && capture_ready;
  wire capture_final = capture_take && write_count==DEPTH-1;
  wire control_bad = (abort_epoch !== 1'b0) ||
    (reserve_valid !== 1'b0 && reserve_valid !== 1'b1) ||
    (capture_valid !== 1'b0 && capture_valid !== 1'b1) ||
    (seal_valid !== 1'b0 && seal_valid !== 1'b1) ||
    (state==REPLAY && output_ready !== 1'b0 && output_ready !== 1'b1);
  wire capture_bad = capture_valid && (!capture_ready ||
    ((capture_position == write_count[ADDRESS_WIDTH-1:0]) !== 1'b1) ||
    ((capture_last == (write_count==DEPTH-1)) !== 1'b1) ||
    ((capture_descriptor == descriptor) !== 1'b1) ||
    ((capture_exponent == capture_exponent) !== 1'b1) ||
    (write_count!=0 && ((capture_exponent == exponent) !== 1'b1)));
  wire seal_bad = seal_valid && !(state==WAIT_SEAL || capture_final);
  wire fault_now = control_bad || capture_bad || seal_bad;
  assign fault = resetn && (fault_q || fault_now);
  assign busy = state!=IDLE;
  assign output_valid = resetn && state==REPLAY && replay_valid && !fault;
  assign output_data = read_data;
  assign output_last = output_position==DEPTH-1;
  assign output_exponent = exponent;
  assign output_descriptor = descriptor;
  wire output_take = output_valid && output_ready;
  wire read_enable = resetn && state==REPLAY && !fault_q && !abort_epoch &&
    (!replay_valid || output_ready===1'b1) && read_count<DEPTH;

  // No reset on payload or read data: stale RAM is unreachable until a fresh
  // full capture and independent seal. Separate synchronous RAM read/write.
  always @(posedge clk)
    if (capture_take) payload[write_count[ADDRESS_WIDTH-1:0]] <= capture_data;
  always @(posedge clk)
    if (read_enable) read_data <= payload[read_count[ADDRESS_WIDTH-1:0]];

  // BEGIN PRIVATE CAPTURE PROGRESS
  // Match the already-private RAM write, even on a newly rejected word.
  // fault_q and state quarantine on that same edge; current fault still
  // suppresses replay immediately. Counter/exponent values are not valid
  // evidence after rejection and cannot be reused before common reset.
  always @(posedge clk or negedge resetn) begin
    if (!resetn) begin write_count<=0;exponent<=0;end
    else if (reserve_valid && reserve_ready) write_count<=0;
    else if (capture_take) begin
      write_count<=write_count+1'b1;
      if (write_count==0) exponent<=capture_exponent;
    end
  end
  // END PRIVATE CAPTURE PROGRESS

  always @(posedge clk or negedge resetn) begin
    if (!resetn) begin
      state<=IDLE;fault_q<=0;replay_valid<=0;read_count<=0;
      descriptor<=0;output_position<=0;done_pulse<=0;
    end else begin
      done_pulse<=0;
      if (fault_q || fault_now) begin
        state<=IDLE;fault_q<=1;replay_valid<=0;
      end else case (state)
        IDLE: if (reserve_valid && reserve_ready) begin
          descriptor<=reserve_descriptor;state<=CAPTURE;
          read_count<=0;replay_valid<=0;
        end
        CAPTURE: begin
          if (capture_take) begin
            if (capture_final) state<=WAIT_SEAL;
          end
          if (seal_valid && capture_final) state<=REPLAY;
        end
        WAIT_SEAL: if (seal_valid) state<=REPLAY;
        REPLAY: begin
          if (output_take) replay_valid<=0;
          if (read_enable) begin
            output_position<=read_count[ADDRESS_WIDTH-1:0];
            read_count<=read_count+1'b1;replay_valid<=1;
          end
          if (output_take && output_last) begin
            state<=IDLE;replay_valid<=0;done_pulse<=1;
          end
        end
      endcase
    end
  end
endmodule
`default_nettype wire
