`timescale 1ns/1ps
module tb;
reg clk=0,resetn=0,request=0,quarantine=0,consume=0;
reg [5:0] checks_good=0;
wire permit,snapshot_valid;
wire [5:0] snapshot_good;
starlink_pss_admission_retry_certificate #(.CHECKS(6)) dut(.*);
integer i,j,k,accepted=0,requests=0,unknowns=0;
reg [5:0] vector;
function automatic four(input integer n);
case(n%4)0:four=0;1:four=1;2:four=1'bx;3:four=1'bz;endcase
endfunction
task tick;begin #1;clk=1;#1;clk=0;#1;end endtask
task restart;begin
resetn=0;request=0;consume=0;quarantine=0;checks_good=0;
tick;resetn=1;tick;
if(permit!==0)$fatal(1,"reset granted");
end endtask
initial begin
for(i=0;i<4096;i=i+1)begin
restart;
for(j=0;j<6;j=j+1)vector[j]=four(i>>(j*2));
checks_good=vector;request=1;requests=requests+1;
#0.01;if(permit!==0)$fatal(1,"combinational grant before sampling");
tick;
if(permit!==(&vector===1'b1))$fatal(1,"sampled evidence acceptance mismatch");
if((^vector)===1'bx)unknowns=unknowns+1;
if(permit!==1)begin
repeat(3)begin tick;if(permit!==0)$fatal(1,"bad or unknown evidence granted");end
checks_good=6'b111111;
#0.01;if(permit!==0)$fatal(1,"retry bypassed sample");
tick;
if(permit!==1)$fatal(1,"rejected snapshot did not retry");
end
// Held good evidence is private. Live guard/current fault fencing is external.
checks_good=0;tick;
if(permit!==1 || snapshot_good!==6'b111111)$fatal(1,"good snapshot changed before consumption");
consume=1;checks_good=6'b111111;accepted=accepted+1;tick;
repeat(3)begin
if(permit!==0)$fatal(1,"consumed request granted twice");
tick;
end
consume=0;request=0;tick;
request=1;checks_good=0;tick;
if(permit!==0)$fatal(1,"cancelled request resurrected old evidence");
checks_good=6'b111111;tick;
if(permit!==1)$fatal(1,"fresh request not granted");
quarantine=1;#0.01;
if(permit!==0)$fatal(1,"current quarantine not fenced");
tick;quarantine=0;checks_good=0;tick;
if(permit!==0)$fatal(1,"quarantine resurrected prior good snapshot");
request=0;tick;
end
for(i=0;i<4;i=i+1)begin
restart;checks_good=6'b111111;request=1;tick;
if(permit!==1)$fatal(1,"control boundary setup");
case(i)
0:request=0;
1:resetn=0;
2:quarantine=1'bx;
3:quarantine=1'bz;
endcase
#0.01;if(permit===1)$fatal(1,"unknown or withdrawn control granted");
tick;restart;
end
if(requests!=4096 || accepted!=4096 || unknowns==0)$fatal(1,"vacuous campaign");
$display("RETRY_ADMISSION_COMPONENT_PASS vectors=4096 accepted_once=4096 control_boundaries=4");
$finish;
end
endmodule
