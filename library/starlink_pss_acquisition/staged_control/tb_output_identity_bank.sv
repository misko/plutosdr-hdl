`timescale 1ns/1ps
`default_nettype none
module tb #(parameter integer CASE=0);
  reg clk=0,slow=0,resetn=0;always #3 clk=~clk;always #5 slow=~slow;
  reg valid=0,last=0,allow_commit=0,abort_epoch=0;
  reg [35:0] data=0;reg [8:0] position=0;reg [36:0] metadata=0;
  wire ready,stage_valid,stage_last,stage_good,stage_idle,stage_fault;
  wire [35:0] stage_data;wire [8:0] stage_position;wire [69:0] stage_metadata;
  wire bank_ready,bank_fault,framing_fault,request,ack,writer_load;
  wire [36:0] writer_metadata;
  wire consume=(bank_ready===1'b1) && !bank_fault && !stage_fault &&
    ((stage_last===1'b0) || (allow_commit && framing_fault===1'b0));
  starlink_pss_product_identity_split_capacity stage (
    .clk(clk),.resetn(resetn),.abort_epoch(abort_epoch || bank_fault),
    .input_valid(valid),.input_ready(ready),.input_data(data),.input_position(position),.input_last(last),
    .input_metadata({33'b0,metadata}),
    .reference_metadata({33'b0,(writer_load?stage_metadata[36:0]:writer_metadata)}),
    .output_valid(stage_valid),.output_ready(consume),.refill_capacity(bank_ready && !bank_fault),
    .output_data(stage_data),.output_position(stage_position),.output_last(stage_last),
    .output_identity_good(stage_good),.output_metadata(stage_metadata),.idle(stage_idle),.fault(stage_fault));
  wire out_valid,out_last;wire [35:0] out_data;wire [8:0] out_position;wire [36:0] out_metadata;
  reg out_ready=0;integer slow_cycles=0,reads=0,writes=0,held=0;
  reg bad_certificate=0;reg certificate_value=1;
  wire bank_certificate=bad_certificate && stage_last ? certificate_value:stage_good;
  starlink_pss_output_mailbox_staged_identity #(.METADATA_WIDTH(37),.RESET_RELEASE_EXTERNAL(1),.EXPLICIT_COMMIT(1)) bank (
    .input_clk(clk),.input_resetn(resetn),.input_valid(stage_valid),.input_ready(bank_ready),
    .input_commit_authorized(allow_commit && !stage_fault && framing_fault===1'b0),
    .input_data(stage_data),.input_position(stage_position),.input_last(stage_last),
    .input_metadata(stage_metadata[36:0]),.input_metadata_certified(bank_certificate),
    .writer_identity_metadata(writer_metadata),.writer_identity_load(writer_load),
    .input_fault(bank_fault),.input_framing_fault_now(framing_fault),
    .output_clk(slow),.output_resetn(resetn),.output_valid(out_valid),.output_ready(out_ready),
    .output_data(out_data),.output_position(out_position),.output_last(out_last),.output_metadata(out_metadata),
    .owner_request(request),.owner_ack_sync(ack),.writer_reset_idle(),.reader_reset_idle());
  localparam [36:0] HEADER=37'h1a5a5a5a5a;
  function automatic [35:0] sample(input integer n);sample=36'h876500000+n*37;endfunction
  always @(negedge slow)begin slow_cycles=slow_cycles+1;out_ready=slow_cycles%7>2;end
  always @(posedge slow)if(resetn && out_valid && out_ready)begin
    if(reads>=512 || out_data!==sample(reads) || out_position!==9'(reads) || out_last!==(reads==511) || out_metadata!==HEADER)
      $fatal(1,"staged output bank numerical/identity mismatch read=%0d",reads);
    reads=reads+1;
  end
  always @(posedge clk)if(resetn)begin
    if(stage_valid && bank_ready)writes=writes+1;
    if(stage_valid && stage_last && !allow_commit && !bank_fault && !stage_fault)held=held+1;
  end
  task automatic reset_all;
    begin
      @(negedge clk);resetn=0;valid=0;allow_commit=0;abort_epoch=0;bad_certificate=0;
      repeat(10)@(negedge clk);
      reads=0;writes=0;held=0;resetn=1;
      repeat(4)@(negedge clk);
      if(request!==0 || ack!==0 || out_valid || stage_valid)$fatal(1,"stale reset state");
    end
  endtask
  task automatic send(input integer kind,count);
    integer n;
    begin
      for(n=0;n<count;n=n+1)begin
        @(negedge clk);valid=1;data=sample(n);position=n;last=n==511;metadata=HEADER;
        if(kind==1 && n==256)metadata=HEADER^37'h10000;
        if(kind==2 && n==511)metadata=HEADER^37'h1000000000;
        if(kind==3 && n==256)position=0;
        if(kind==4 && n==256)last=1;
        @(posedge clk);while(ready!==1)@(posedge clk);#0.001;
      end
      @(negedge clk);valid=0;
    end
  endtask
  task automatic finish_good;
    begin
      repeat(32)begin @(negedge clk);if(request || out_valid || reads)$fatal(1,"unpublished final escaped");end
      if(held<30 || !stage_valid || !stage_last || stage_data!==sample(511))$fatal(1,"held final inventory");
      allow_commit=1;
      while(reads!=512 || request!==ack)@(negedge clk);
      repeat(20)@(negedge clk);
      if(bank_fault || stage_fault || stage_valid || out_valid)$fatal(1,"healthy final/ACK state");
    end
  endtask
  initial begin
    reset_all;
    if(CASE==0)begin send(0,512);finish_good;end
    else begin
      if(CASE>=5 && CASE<=7)begin
        bad_certificate=1;
        case(CASE)5:certificate_value=0;6:certificate_value=1'bx;7:certificate_value=1'bz;endcase
      end
      send(CASE,(CASE==1 || CASE==3 || CASE==4)?257:512);
      if(CASE==8)abort_epoch=1;
      if(CASE!=9)begin
        repeat(10)@(negedge clk);
        if((!bank_fault && !stage_fault) || request || out_valid || reads)$fatal(1,"bad block not fenced case=%0d",CASE);
      end else begin
        repeat(10)@(negedge clk);
        if(!stage_valid || !stage_last || request || reads)$fatal(1,"reset final premise");
      end
      reset_all;repeat(20)@(negedge clk);
      if(request || out_valid || reads)$fatal(1,"stale output after recovery");
      send(0,512);finish_good;
    end
    $display("OUTPUT_IDENTITY_BANK_PASS case=%0d fresh_reads=512 held=%0d real_ack=1",CASE,held);$finish;
  end
  initial begin #200000;$fatal(1,"output identity bank timeout case=%0d",CASE);end
endmodule
`default_nettype wire
