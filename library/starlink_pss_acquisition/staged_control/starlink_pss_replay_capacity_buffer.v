// SPDX-License-Identifier: GPL-2.0
// Two private replay words. Input capacity depends only on registered occupancy,
// never current downstream READY. At one occupied word, simultaneous push/pop
// sustains one word per clock. A full queue stalls input for its first drain edge.
// Current cancellation suppresses public output immediately and purges occupancy
// on this edge. Private bookkeeping may consume the old head on that edge only;
// caller must retain same-edge bank publication vetoes and common epoch reset.
// An input handshake on a newly rejected edge is discarded, never published.
`timescale 1ns/1ps
module starlink_pss_replay_capacity_buffer #(
  parameter integer WIDTH=121
)(
  input wire clk,resetn,abort_epoch,cancel_now,
  input wire input_valid,
  output wire input_ready,
  input wire [WIDTH-1:0] input_data,
  output wire output_valid,output_private_valid,
  input wire output_ready,
  output wire [WIDTH-1:0] output_data,
  output wire [1:0] occupancy,
  output wire empty,fault
);
  reg head_valid,tail_valid,fault_q;
  reg [WIDTH-1:0] head_data,tail_data;
  wire control_bad=(abort_epoch !== 1'b0) || (cancel_now !== 1'b0) ||
    (input_valid !== 1'b0 && input_valid !== 1'b1) ||
    (output_ready !== 1'b0 && output_ready !== 1'b1) ||
    (tail_valid && !head_valid);
  assign input_ready=resetn && !fault_q && !tail_valid;
  assign output_private_valid=resetn && !fault_q && head_valid && !abort_epoch;
  assign fault=resetn && (fault_q || control_bad);
  assign output_valid=output_private_valid && !fault;
  assign output_data=head_data;
  assign occupancy={1'b0,head_valid}+{1'b0,tail_valid};
  assign empty=!head_valid && !tail_valid;
  wire push=input_valid && input_ready;
  wire pop=output_private_valid && output_ready;
  initial if(WIDTH<1)$fatal(1,"replay buffer requires positive width");
  always @(posedge clk or negedge resetn)begin
    if(!resetn)begin head_valid<=0;tail_valid<=0;fault_q<=0;end
    else if(fault_q || control_bad)begin head_valid<=0;tail_valid<=0;fault_q<=1;end
    else begin
      case({push,pop})
        2'b10:begin
          if(head_valid)tail_valid<=1;
          else head_valid<=1;
        end
        2'b01:begin
          if(tail_valid)tail_valid<=0;
          else head_valid<=0;
        end
        default:begin end
      endcase
    end
  end
  // Payload has no reset. Empty/fault ownership makes stale contents unreachable.
  always @(posedge clk)begin
    if(push)begin
      if(head_valid && !pop)tail_data<=input_data;
      else head_data<=input_data;
    end
    if(pop && tail_valid)head_data<=tail_data;
  end
endmodule
