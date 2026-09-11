// SPDX-License-Identifier: GPL-2.0
// Logical integration of staged ownership with the real explicit-commit RAM.
// The testbench is the command arbiter; no full FFT/controller or physical CDC claim.
`timescale 1ns/1ps
module tb;
  parameter integer CANCEL_CASE=0, STALL_CYCLES=17;
  reg clk=0,output_clk=0;
  always #2.857 clk=~clk;
  always #5 output_clk=~output_clk;
  reg input_resetn=0,output_resetn=0,abort_epoch=0;
  wire resetn=input_resetn && output_resetn;
  reg command_valid=0,response_ready=0;
  reg [1:0] command_opcode=0;
  reg [31:0] command_tag=0;
  reg [69:0] command_descriptor=0;
  wire command_ready,response_valid,fault,tags_exhausted,lookup_found,lookup_committed;
  wire [1:0] response_opcode,occupied,committed;
  wire [31:0] response_tag;
  wire [69:0] lookup_descriptor;
  wire lookup_valid=output_valid;
  wire [31:0] lookup_tag=output_metadata;
  starlink_pss_descriptor_commands ledger(.*);

  reg input_valid=0,input_last=0,replay_request=0;
  reg [35:0] input_data=0;
  reg [8:0] input_position=0;
  reg [31:0] input_metadata=0;
  wire input_ready,input_fault,input_framing_fault_now;
  wire output_valid,output_last,owner_request,owner_ack_sync;
  wire [35:0] output_data;
  wire [8:0] output_position;
  wire [31:0] output_metadata;
  reg output_ready=0,drain_enable=0;
  // This candidate binding deliberately requires BOTH a successful staged
  // response and a replayed final payload beat. The bench supplies the arbiter.
  wire input_commit_authorized=replay_request && response_valid && response_opcode==1 && !fault;
  starlink_pss_mailbox_owner_view #(.EXPLICIT_COMMIT(1),.METADATA_WIDTH(32)) bank (
    .input_clk(clk),.input_resetn(input_resetn),.input_valid(input_valid),
    .input_commit_authorized(input_commit_authorized),.input_ready(input_ready),
    .input_data(input_data),.input_position(input_position),.input_last(input_last),
    .input_metadata(input_metadata),.input_fault(input_fault),
    .input_framing_fault_now(input_framing_fault_now),.output_clk(output_clk),
    .output_resetn(output_resetn),.output_valid(output_valid),.output_ready(output_ready),
    .output_data(output_data),.output_position(output_position),.output_last(output_last),
    .output_metadata(output_metadata),.owner_request(owner_request),.owner_ack_sync(owner_ack_sync),
    .writer_reset_idle(),.reader_reset_idle()
  );

  reg [69:0] descriptors[0:1];
  reg [31:0] seeds[0:1];
  integer reads[0:1];
  integer slow_cycles=0,publications=0;
  reg previous_request=0;
  reg publication_observed=0;
  reg [31:0] published_tag=0;
  function [35:0] word(input integer tag,input integer position);
    word=36'h55aa98765 ^ (seeds[tag]*36'h1234567) ^ position;
  endfunction
  always @(negedge output_clk) begin
    slow_cycles=slow_cycles+1;
    output_ready=drain_enable && slow_cycles%5!=0;
  end
  always @(posedge output_clk) begin
    if (resetn && output_valid && output_ready) begin
      if(output_metadata>1) $fatal(1,"unknown output tag");
      if(reads[output_metadata]>=512 || output_position!==reads[output_metadata][8:0] ||
         output_last!==(reads[output_metadata]==511) ||
         output_data!==word(output_metadata,reads[output_metadata]))
        $fatal(1,"payload/order mismatch tag=%0d position=%0d",output_metadata,output_position);
      if(lookup_found!==1 || lookup_committed!==1 || lookup_descriptor!==descriptors[output_metadata])
        $fatal(1,"descriptor not retained through real read");
      reads[output_metadata]=reads[output_metadata]+1;
    end
  end
  always @(posedge clk) begin
    #0.2;
    if(!resetn) begin previous_request=0;publication_observed=0;end
    else if(owner_request!==previous_request) begin
      publications=publications+1;previous_request=owner_request;
      publication_observed=1;published_tag=input_metadata;
    end
    if(resetn && publication_observed && owner_request===owner_ack_sync && reads[published_tag]!=512)
      $fatal(1,"ACK before final consumer transfer");
  end

  task reset_all;
    begin
      @(negedge clk);input_resetn=0;output_resetn=0;
      command_valid=0;response_ready=0;input_valid=0;replay_request=0;
      abort_epoch=0;drain_enable=0;
      repeat(5) @(negedge output_clk);
      reads[0]=0;reads[1]=0;
      input_resetn=1;output_resetn=1;
      repeat(5) @(negedge clk);
      if(input_ready!==1 || fault!==0 || occupied!==0) $fatal(1,"reset recovery not idle");
    end
  endtask
  task start_command(input [1:0] op,input [31:0] tag,input [69:0] descriptor);
    begin
      @(negedge clk);command_valid=1;command_opcode=op;command_tag=tag;
      command_descriptor=descriptor;response_ready=0;
      @(posedge clk);
      while(command_ready!==1) @(posedge clk);
      #0.1;
      @(negedge clk);command_valid=0;
    end
  endtask
  task await_response(input [1:0] op,input [31:0] tag);
    begin
      while(response_valid!==1) @(negedge clk);
      if(response_opcode!==op || response_tag!==tag || fault!==0)
        $fatal(1,"wrong staged response");
    end
  endtask
  task consume_response;
    begin
      @(negedge clk);response_ready=1;
      @(posedge clk);#0.1;
      @(negedge clk);response_ready=0;
    end
  endtask
  task allocate(input integer tag);
    begin
      start_command(0,0,descriptors[tag]);await_response(0,tag);consume_response;
    end
  endtask
  task write_private(input integer tag);
    integer position;
    begin
      for(position=0;position<512;position=position+1) begin
        @(negedge clk);input_valid=1;input_position=position;
        input_last=position==511;input_data=word(tag,position);input_metadata=tag;
        while(input_ready!==1) @(negedge clk);
        #0.1;if(input_framing_fault_now!==0) $fatal(1,"private framing error");
        @(posedge clk);#0.1;
      end
      @(negedge clk);input_valid=0;
    end
  endtask
  task publish(input integer tag);
    reg old_request;
    begin
      old_request=owner_request;
      start_command(1,tag,0);await_response(1,tag);
      repeat(8) begin
        @(negedge clk);
        if(owner_request!==old_request || output_valid!==0) $fatal(1,"certificate alone published data");
      end
      // An authorized pulse without a final valid beat must do nothing.
      replay_request=1;
      @(posedge clk);#0.1;
      if(owner_request!==old_request || input_fault!==0) $fatal(1,"commit-only pulse changed ownership");
      @(negedge clk);input_valid=1;input_position=511;input_last=1;
      input_data=word(tag,511);input_metadata=tag;response_ready=1;
      #0.1;if(input_ready!==1 || input_framing_fault_now!==0) $fatal(1,"final replay invalid");
      @(posedge clk);#0.1;
      if(owner_request!==!old_request || input_ready!==0) $fatal(1,"final replay did not publish exactly once");
      @(negedge clk);input_valid=0;replay_request=0;response_ready=0;
    end
  endtask
  task drain_and_release(input integer tag);
    begin
      repeat(STALL_CYCLES) begin
        @(negedge output_clk);
        if(input_ready!==0 || reads[tag]!=0) $fatal(1,"bank released during reader stall");
      end
      drain_enable=1;
      while(reads[tag]!=512) @(negedge clk);
      drain_enable=0;
      // No ledger release is requested before the real mailbox ACK crosses back.
      while(input_ready!==1 || owner_request!==owner_ack_sync) @(negedge clk);
      if(committed[tag]!==1 || occupied[tag]!==1) $fatal(1,"descriptor released before reader ACK");
      start_command(2,tag,0);await_response(2,tag);consume_response;
    end
  endtask

  initial begin
    descriptors[0]=70'h20000123456789abcd;descriptors[1]=70'h10000fedcba9876543;
    seeds[0]=7;seeds[1]=13;reads[0]=0;reads[1]=0;
    reset_all;
    allocate(0);write_private(0);allocate(1);
    repeat(23) begin
      @(negedge clk);
      if(output_valid!==0 || owner_request!==0 || input_ready!==1)
        $fatal(1,"private block leaked before validation");
    end
    if(CANCEL_CASE!=0) begin
      if(CANCEL_CASE==2) start_command(1,0,0);
      else if(CANCEL_CASE==3) begin start_command(1,0,0);await_response(1,0);end
      abort_epoch=1;
      repeat(5) @(negedge clk);
      replay_request=1;input_valid=1;input_position=511;input_last=1;input_data=word(0,511);
      repeat(5) begin
        @(negedge clk);
        if(fault!==1 || response_valid!==0 || input_commit_authorized!==0 || owner_request!==0 || output_valid!==0)
          $fatal(1,"aborted command published old payload");
      end
      reset_all;
      descriptors[0]=70'h30000aaaaaaaaaaaaa;seeds[0]=99;
      allocate(0);write_private(0);publish(0);drain_and_release(0);
      if(publications!=1 || reads[0]!=512 || occupied!==0) $fatal(1,"fresh epoch did not recover");
      $display("MAILBOX_COMPOSITION_PASS cancel=%0d publications=1 words=512",CANCEL_CASE);
    end else begin
      publish(0);drain_and_release(0);
      if(occupied!==2) $fatal(1,"independent queued descriptor was lost");
      write_private(1);publish(1);drain_and_release(1);
      if(publications!=2 || reads[0]!=512 || reads[1]!=512 || occupied!==0 || fault!==0 || input_fault!==0)
        $fatal(1,"two real payload transactions did not complete");
      $display("MAILBOX_COMPOSITION_PASS cancel=0 publications=2 words=1024");
    end
    $finish(0);
  end
  initial begin #1000000;$fatal(1,"mailbox composition timeout");end
endmodule
