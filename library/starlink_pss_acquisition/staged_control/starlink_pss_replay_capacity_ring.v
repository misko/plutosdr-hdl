// SPDX-License-Identifier: GPL-2.0
// Two alternating private replay slots. Wide payload write enables use only
// local capacity and the upstream private offer, never downstream READY.
// Current cancellation purges ownership and prevents all public output.
// A cancelled private write is unreachable until reset and fresh acceptance.
`timescale 1ns/1ps
module starlink_pss_replay_capacity_ring #(
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
  reg [1:0] count;
  reg read_slot,write_slot,fault_q;
  reg [WIDTH-1:0] slot0,slot1;
  wire control_bad=(abort_epoch !== 1'b0) || (cancel_now !== 1'b0) ||
    (input_valid !== 1'b0 && input_valid !== 1'b1) ||
    (output_ready !== 1'b0 && output_ready !== 1'b1) ||
    count>2;
  assign input_ready=resetn && !fault_q && count!=2;
  assign output_private_valid=resetn && !fault_q && count!=0 && !abort_epoch;
  assign fault=resetn && (fault_q || control_bad);
  assign output_valid=output_private_valid && !fault;
  assign output_data=read_slot?slot1:slot0;
  assign occupancy=count;
  assign empty=count==0;
  wire push=input_valid && input_ready;
  wire pop=output_private_valid && output_ready;
  initial if(WIDTH<1)$fatal(1,"replay ring requires positive width");
  always @(posedge clk or negedge resetn)begin
    if(!resetn)begin count<=0;read_slot<=0;write_slot<=0;fault_q<=0;end
    else if(fault_q || control_bad)begin count<=0;read_slot<=0;write_slot<=0;fault_q<=1;end
    else begin
      if(push)write_slot<=!write_slot;
      if(pop)read_slot<=!read_slot;
      case({push,pop})
        2'b10:count<=count+1'b1;
        2'b01:count<=count-1'b1;
        default:begin end
      endcase
    end
  end
  // No payload reset or downstream-capacity dependency. A cancelled edge may
  // alter private bytes, but clears count and latches fault before any reuse.
  always @(posedge clk)begin
    if(push && !write_slot)slot0<=input_data;
    if(push && write_slot)slot1<=input_data;
  end
endmodule
