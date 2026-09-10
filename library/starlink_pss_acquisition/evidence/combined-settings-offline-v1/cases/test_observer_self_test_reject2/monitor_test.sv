`timescale 1ns/1fs
module monitor_test;
reg clk=0; always #3 clk=!clk;
reg [63:0] a=0,b=0,sa=0,sb=0;
reg ca=0,cb=0,active_job=0,final_slot=0,current_fault=0,owned=0,stall=0,running=0;
wire [31:0] checks,active_checks,consumed,differences,final_faults,owned_stalls,reset_owned;
integer i;
starlink_pss_exact_control_actual_compare #(.WIDTH(64)) dut(.clk(clk), .actual_public(a),
.reference_public(b), .actual_consume(ca), .reference_consume(cb), .actual_scratch(sa),
.reference_scratch(sb), .active_job(active_job), .final_slot(final_slot), .current_fault(current_fault),
.owned_bank(owned), .stalled_bank(stall), .running(running), .checks(checks), .active_checks(active_checks),
.consumed_identities(consumed), .private_differences(differences), .final_fault_edges(final_faults),
.owned_stall_edges(owned_stalls), .reset_owned_edges(reset_owned));
initial begin
repeat(3) @(negedge clk);
for(i=0;i<64;i=i+1) begin
  #0.1; a=64'b1<<i; b=a; sa=a; sb=~a;
  active_job=i[0]; owned=1; stall=1; running=i[0]; final_slot=1;current_fault=1;
  if(2==1) b=~a;
  @(posedge clk); #0.1;
  @(negedge clk); #0.1; ca=1; cb=1; sb=sa;
  if(2==2) cb=0;
  if(2==3) sb=~sa;
  @(posedge clk); #0.1;
  @(negedge clk); #0.1;ca=0;cb=0;
end
if(!checks || !active_checks || consumed!=64 || !differences || !final_faults || !owned_stalls || !reset_owned)
  $fatal(1,"observer self-test coverage missing");
$display("EXACT_ACTUAL_OBSERVER_SELF_TEST_PASS no_fft=1");$finish;
end
endmodule
