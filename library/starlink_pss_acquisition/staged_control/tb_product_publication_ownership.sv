// Same-clock, common-reset configuration of the actual product bank.
// Model only publication authorization; data and ownership RTL are unmodified.
module tb;
parameter integer AW=9;
localparam integer N=1<<AW;
reg clk=0;always #5 clk=~clk;
reg resetn=0,iv=0,last=0,cert=1,ordy=0,committed=1,other_fault=0;
reg handoff_bad=0,inverse=0;
reg[AW-1:0]pos=0;
reg[35:0]data=0;
reg[69:0]metadata=70'h123456780;
wire ready,ov;
wire original_auth=committed && !(other_fault || (!inverse && committed && ov && handoff_bad));
wire candidate_auth=committed && (ov === 1'b0) && !other_fault;
starlink_pss_product_mailbox_staged_identity #(.ADDRESS_WIDTH(AW),.RESET_RELEASE_EXTERNAL(1),.EXPLICIT_COMMIT(1)) original(
.input_clk(clk),.input_resetn(resetn),.input_valid(iv),.input_ready(ready),
.input_commit_authorized(original_auth),.input_data(data),.input_position(pos),.input_last(last),
.input_metadata(metadata),.input_metadata_certified(cert),.output_clk(clk),.output_resetn(resetn),
.output_valid(ov),.output_ready(ordy));
starlink_pss_product_mailbox_staged_identity #(.ADDRESS_WIDTH(AW),.RESET_RELEASE_EXTERNAL(1),.EXPLICIT_COMMIT(1)) candidate(
.input_clk(clk),.input_resetn(resetn),.input_valid(iv),
.input_commit_authorized(__AUTH__),.input_data(data),.input_position(pos),.input_last(last),
.input_metadata(metadata),.input_metadata_certified(cert),.output_clk(clk),.output_resetn(resetn),
.output_ready(ordy));
integer checks=0,reads=0,publishes=0,differences=0,n,f,cycles;
reg prior_request=0;
task compare;
begin
 if(resetn && ready===1 && ov!==0)$fatal(1,"writer/reader ownership overlap");
 if({original.input_ready,original.input_fault,original.output_valid,
     original.request_toggle,original.acknowledge_toggle,original.request_sync,original.acknowledge_sync,
     original.write_position,original.reading,original.read_all_loaded,original.read_valid,
     original.read_address} !==
    {candidate.input_ready,candidate.input_fault,candidate.output_valid,
     candidate.request_toggle,candidate.acknowledge_toggle,candidate.request_sync,candidate.acknowledge_sync,
     candidate.write_position,candidate.reading,candidate.read_all_loaded,candidate.read_valid,
     candidate.read_address})$fatal(1,"bank state mismatch");
 if(ov===1 && {original.output_data,original.output_position,original.output_last,original.output_metadata} !==
             {candidate.output_data,candidate.output_position,candidate.output_last,candidate.output_metadata})
   $fatal(1,"bank data mismatch");
 if(resetn && original_auth!==candidate_auth)differences=differences+1;
 checks=checks+1;
end
endtask
always @(posedge clk)begin
 compare;
 if(ov===1 && ordy===1)reads=reads+1;
 #0.001;compare;
 if(resetn && original.request_toggle!==prior_request)publishes=publishes+1;
 prior_request=original.request_toggle;
end
task reset;
begin
 @(negedge clk);resetn=0;iv=0;ordy=0;cert=1;other_fault=0;
 repeat(3)@(negedge clk);
 resetn=1;
end
endtask
function four(input integer v);
case(v&3)0:four=0;1:four=1;2:four=1'bx;3:four=1'bz;endcase
endfunction
initial begin
 reset;
 for(f=0;f<16;f=f+1)begin
  for(n=0;n<N;n=n+1)begin
   @(negedge clk);iv=1;pos=n;last=n==N-1;data=f*N+n;cert=1;
   other_fault=(n==N-1); // retain final word until current veto clears
   handoff_bad=1;committed=1;inverse=f&1;
  end
  repeat(3)@(negedge clk);
  other_fault=0;
  @(negedge clk);iv=0;ordy=0;
  repeat(8)@(negedge clk);
  cycles=0;
  while(ready!==1)begin
   ordy=(cycles%3)!=0;cycles=cycles+1;
   if(cycles>4*N+40)$fatal(1,"reader did not release");
   @(negedge clk);
  end
 end
 if(reads!=16*N || publishes!=16)$fatal(1,"full frame conservation");
 for(n=0;n<20000;n=n+1)begin
  @(negedge clk);
  resetn=(n%311)!=0;
  iv=four($random);ordy=four($random);cert=four($random);
  other_fault=four($random);committed=four($random);handoff_bad=four($random);inverse=four($random);
  pos=original.write_position;last=pos==N-1;data=$random;
 end
 reset;
 if(checks<40000 || differences==0)$fatal(1,"vacuous ownership comparison");
 $display("PRODUCT_OWNERSHIP_PASS aw=%0d checks=%0d reads=%0d publishes=%0d authorization_differences=%0d",AW,checks,reads,publishes,differences);
 $finish;
end
endmodule

