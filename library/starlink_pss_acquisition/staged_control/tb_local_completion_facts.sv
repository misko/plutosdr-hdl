`timescale 1ns/1ps
`default_nettype none
module tb;
  reg clk=0;always #5 clk=~clk;
  reg resetn=0,quarantine=0,consume=0,enable_request=0;
  reg [3:0] state=0;
  reg [41:0] facts={42{1'b1}};
  reg [5:0] preflight=0;
  wire preparing=(state==9 || state==10);
  wire request=(state==7) && enable_request;
  wire [41:0] checks={facts[41:32],~(preparing?preflight:6'b0),facts[25:0]};
  wire [35:0] compressed={checks[41:32],checks[25:0]};
  wire old_permit,new_permit,old_valid,new_valid;
  wire [41:0] old_good;
  wire [35:0] new_good;
  starlink_pss_admission_certificate #(.CHECKS(42)) reference (
    .clk(clk),.resetn(resetn),.request(request),.quarantine(quarantine),.consume(consume),
    .checks_good(checks),.permit(old_permit),.snapshot_valid(old_valid),.snapshot_good(old_good));
  starlink_pss_admission_certificate #(.CHECKS(36),.PRIVATE_FACT_CAPTURE(1)) candidate (
    .clk(clk),.resetn(resetn),.request(request),.quarantine(quarantine),.consume(consume),
    .checks_good(compressed),.permit(new_permit),.snapshot_valid(new_valid),.snapshot_good(new_good));
  wire [41:0] expanded={new_good[35:26],6'b111111,new_good[25:0]};
  integer checks_count=0,owned=0,permits=0,differences=0,n,b,v,phase,k;
  reg [31:0] random_state=32'hca5a6371;
  task automatic compare;
    begin
      if({old_permit,old_valid,reference.consumed}!=={new_permit,new_valid,candidate.consumed})
        $fatal(1,"certificate controls differ state=%h request=%b",state,request);
      if(old_valid===1'b1)begin
        if(old_good!==expanded)$fatal(1,"owned facts differ state=%h",state);
        owned=owned+1;
      end else if(old_good!==expanded)differences=differences+1;
      if(old_permit===1'b1)permits=permits+1;
      checks_count=checks_count+1;
    end
  endtask
  task automatic step;
    begin #1;compare;@(posedge clk);#1;compare;@(negedge clk);end
  endtask
  task automatic clear;
    begin resetn=0;quarantine=0;consume=0;enable_request=0;state=0;step;resetn=1;end
  endtask
  initial begin
    @(negedge clk);step;
    // Every hardware state, each check bit and 0/1/X/Z, held/consumed/cancelled.
    for(phase=0;phase<16;phase=phase+1)
      for(b=0;b<42;b=b+1)for(v=0;v<4;v=v+1)begin
        clear;state=phase;enable_request=1;facts={42{1'b1}};preflight=0;
        case(v)0:facts[b]=0;1:facts[b]=1;2:facts[b]=1'bx;3:facts[b]=1'bz;endcase
        if(b>=26 && b<=31)preflight[b-26]=~facts[b];
        step;facts=0;preflight=6'bxxxxxx;step;consume=1;step;
        quarantine=1;step;quarantine=0;step;
      end
    // Unknown state must not introduce new permits. Include all X/Z placements.
    for(b=0;b<4;b=b+1)for(v=0;v<2;v=v+1)begin
      clear;state=7;state[b]=v?1'bz:1'bx;enable_request=1;facts={42{1'b1}};preflight=6'bxxxxxx;
      step;step;consume=1;step;clear;
    end
    for(n=0;n<20000;n=n+1)begin
      random_state={random_state[30:0],random_state[31]^random_state[21]^random_state[1]^random_state[0]};
      state=random_state[3:0];resetn=|random_state[8:5];quarantine=&random_state[12:9];
      consume=random_state[13];enable_request=random_state[14];preflight=random_state[20:15];
      facts={random_state,random_state[9:0]};step;
    end
    if(checks_count<70000 || owned<100 || permits<10 || differences<100)
      $fatal(1,"local completion coverage missing");
    $display("LOCAL_COMPLETION_UNIT_PASS checks=%0d owned=%0d permits=%0d private_differences=%0d",checks_count,owned,permits,differences);$finish;
  end
endmodule
`default_nettype wire
