// SPDX-License-Identifier: GPL-2.0
// Synthesizable adapter + real dual-clock payload RAM. The bench supplies only
// allocation, private samples and validated completion, never ledger commands.
// No actual FFT completion validator or physical CDC qualification is implied.
`timescale 1ns/1ps
module tb;
  parameter integer CANCEL_CASE=0, STALL_CYCLES=17;
  reg clk=0, output_clk=0;
  always #2.857 clk=~clk;
  always #5 output_clk=~output_clk;
  reg resetn=0,abort_epoch=0;
  reg allocate_valid=0,allocated_ready=0,complete_valid=0;
  reg [69:0] allocate_descriptor=0;
  reg [31:0] complete_tag=0;
  reg [35:0] complete_final_data=0;
  wire allocate_ready,allocated_valid,complete_ready,replay_valid,replay_ready;
  wire [31:0] allocated_tag,replay_tag,released_tag;
  wire [35:0] replay_data;
  wire publication_busy,published_valid,released_valid,lookup_found,lookup_committed,tags_exhausted,fault;
  wire [69:0] lookup_descriptor;
  wire [1:0] occupied,committed;
  wire lookup_valid=output_valid;
  wire [31:0] lookup_tag=output_metadata;
  wire bank_request,bank_ack_sync,bank_fault;
  starlink_pss_staged_mailbox_control dut(.*);

  reg private_valid=0,private_last=0,allow_replay=0;
  reg [35:0] private_data=0;
  reg [8:0] private_position=0;
  reg [31:0] private_tag=0;
  wire input_ready,input_framing_fault_now;
  wire input_valid=replay_valid ? allow_replay : private_valid;
  wire [35:0] input_data=replay_valid ? replay_data : private_data;
  wire [8:0] input_position=replay_valid ? 9'd511 : private_position;
  wire input_last=replay_valid ? 1'b1 : private_last;
  wire [31:0] input_metadata=replay_valid ? replay_tag : private_tag;
  assign replay_ready=allow_replay && input_ready;
  wire output_valid,output_last;
  wire [35:0] output_data;
  wire [8:0] output_position;
  wire [31:0] output_metadata;
  reg output_ready=0,drain_enable=0;
  starlink_pss_mailbox_owner_view #(.EXPLICIT_COMMIT(1),.METADATA_WIDTH(32)) bank (
    .input_clk(clk),.input_resetn(resetn),.input_valid(input_valid),
    .input_commit_authorized(replay_valid && allow_replay),.input_ready(input_ready),
    .input_data(input_data),.input_position(input_position),.input_last(input_last),
    .input_metadata(input_metadata),.input_fault(bank_fault),
    .input_framing_fault_now(input_framing_fault_now),.output_clk(output_clk),
    .output_resetn(resetn),.output_valid(output_valid),.output_ready(output_ready),
    .output_data(output_data),.output_position(output_position),.output_last(output_last),
    .output_metadata(output_metadata),.owner_request(bank_request),.owner_ack_sync(bank_ack_sync),
    .writer_reset_idle(),.reader_reset_idle()
  );
  reg [69:0] descriptors[0:2];
  reg [31:0] seeds[0:2];
  integer reads[0:2];
  integer publications=0,releases=0,slow_cycles=0;
  reg previous_request=0;
  function [35:0] word(input integer tag,input integer position);
    word=36'h55aa98765 ^ (seeds[tag]*36'h1234567) ^ position;
  endfunction
  always @(negedge output_clk) begin
    slow_cycles=slow_cycles+1;output_ready=drain_enable && slow_cycles%5!=0;
  end
  always @(posedge output_clk) begin
    if(resetn && !fault && output_valid && output_ready) begin
      if(output_metadata>2) $fatal(1,"unknown output tag");
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
    if(!resetn) previous_request=0;
    else begin
      if(bank_request!==previous_request) begin
        publications=publications+1;previous_request=bank_request;
        if(committed==0 || fault) $fatal(1,"publication without ownership");
      end
      if(released_valid) begin
        if(released_tag>2 || reads[released_tag]!=512 || bank_request!==bank_ack_sync)
          $fatal(1,"release before real reader ACK");
        releases=releases+1;
      end
      if(published_valid && (publications!=releases+1 || bank_request===bank_ack_sync))
        $fatal(1,"publication receipt without actual bank transfer");
    end
  end
  task reset_all;
    integer i;
    begin
      @(negedge clk);resetn=0;abort_epoch=0;allocate_valid=0;allocated_ready=0;
      complete_valid=0;private_valid=0;allow_replay=0;drain_enable=0;
      repeat(5) @(negedge output_clk);
      for(i=0;i<3;i=i+1) reads[i]=0;
      publications=0;releases=0;resetn=1;
      repeat(5) @(negedge clk);
      if(input_ready!==1 || fault!==0 || occupied!==0) $fatal(1,"reset not idle");
    end
  endtask
  task request_allocation(input integer tag);
    begin
      @(negedge clk);allocate_valid=1;allocate_descriptor=descriptors[tag];
      @(posedge clk);while(allocate_ready!==1) @(posedge clk);
      @(negedge clk);allocate_valid=0;
    end
  endtask
  task consume_allocation(input integer tag);
    begin
      while(allocated_valid!==1) @(negedge clk);
      if(allocated_tag!==tag) $fatal(1,"allocation tag mismatch");
      allocated_ready=1;@(posedge clk);@(negedge clk);allocated_ready=0;
    end
  endtask
  task write_private(input integer tag);
    integer position;
    begin
      if(publication_busy) $fatal(1,"writer attempted occupied bank");
      for(position=0;position<512;position=position+1) begin
        @(negedge clk);private_valid=1;private_position=position;
        private_last=position==511;private_data=word(tag,position);private_tag=tag;
        @(posedge clk);while(input_ready!==1) @(posedge clk);
      end
      @(negedge clk);private_valid=0;
    end
  endtask
  task complete_block(input integer tag);
    begin
      @(negedge clk);complete_valid=1;complete_tag=tag;complete_final_data=word(tag,511);
      @(posedge clk);while(complete_ready!==1) @(posedge clk);
      @(negedge clk);complete_valid=0;
    end
  endtask
  task await_replay;
    integer cycles;
    begin
      cycles=0;
      while(replay_valid!==1 && cycles<40) begin @(negedge clk);cycles=cycles+1;end
      if(replay_valid!==1) $fatal(1,"COMMIT blocked behind allocation");
    end
  endtask
  task publish_and_drain(input integer tag);
    integer cycles;
    reg old_request;
    begin
      await_replay;
      old_request=bank_request;
      repeat(STALL_CYCLES) begin
        @(negedge clk);
        if(replay_valid!==1 || replay_tag!==tag || replay_data!==word(tag,511) ||
           bank_request!==old_request || output_valid!==0)
          $fatal(1,"held replay changed or prematurely published");
      end
      allow_replay=1;@(posedge clk);@(negedge clk);allow_replay=0;
      if(bank_request!==!old_request || input_ready!==0) $fatal(1,"replay did not transfer ownership");
      repeat(STALL_CYCLES+20) begin
        @(negedge output_clk);
        if(!publication_busy || releases!=tag || reads[tag]!=0)
          $fatal(1,"release during consumer backpressure");
      end
      drain_enable=1;
      while(reads[tag]!=512) @(negedge clk);
      drain_enable=0;cycles=0;
      while(publication_busy && cycles<40) begin @(negedge clk);cycles=cycles+1;end
      if(publication_busy || releases!=tag+1 || fault) $fatal(1,"RELEASE blocked behind allocation");
    end
  endtask
  initial begin
    descriptors[0]=70'h20000123456789abcd;descriptors[1]=70'h10000fedcba9876543;
    descriptors[2]=70'h30000a55a5aa5f00f0;seeds[0]=7;seeds[1]=13;seeds[2]=29;
    reset_all;
    request_allocation(0);consume_allocation(0);write_private(0);
    request_allocation(1);
    while(allocated_valid!==1) @(negedge clk);
    // Hold result #1, and request #2 while both descriptors are occupied.
    // Neither can prevent publication/release of job #0.
    allocate_valid=1;allocate_descriptor=descriptors[2];
    repeat(9) begin
      @(negedge clk);
      if(allocate_ready || output_valid || bank_request) $fatal(1,"full allocation/private publication violation");
    end
    complete_block(0);
    if(CANCEL_CASE!=0) begin
      if(CANCEL_CASE==2) begin
        while(dut.ledger.pending!==1) @(negedge clk);
      end else if(CANCEL_CASE>=3) await_replay;
      if(CANCEL_CASE==4) begin
        allow_replay=1;@(posedge clk);@(negedge clk);allow_replay=0;
      end
      abort_epoch=1;#0.1;
      if(!fault || replay_valid || allocated_valid || allocate_ready || complete_ready || released_valid)
        $fatal(1,"abort did not immediately fence adapter");
      repeat(20) begin
        @(negedge clk);
        if(replay_valid || released_valid || releases!=0 || publications!=(CANCEL_CASE==4))
          $fatal(1,"aborted work escaped quarantine");
      end
      reset_all;descriptors[0]=70'h35555aaaaaaaaaaaaa;seeds[0]=99;
      request_allocation(0);consume_allocation(0);write_private(0);complete_block(0);publish_and_drain(0);
      if(publications!=1 || releases!=1 || occupied!==0) $fatal(1,"fresh epoch recovery failed");
      $display("STAGED_ADAPTER_PASS cancel=%0d publications=1 words=512",CANCEL_CASE);
    end else begin
      publish_and_drain(0);
      if(allocated_valid!==1 || allocated_tag!==1 || occupied!==2) $fatal(1,"held second descriptor was lost");
      consume_allocation(1);
      @(posedge clk);while(allocate_ready!==1) @(posedge clk);
      @(negedge clk);allocate_valid=0;
      consume_allocation(2);
      write_private(1);complete_block(1);publish_and_drain(1);
      write_private(2);complete_block(2);publish_and_drain(2);
      if(publications!=3 || releases!=3 || occupied!==0 || bank_fault || fault)
        $fatal(1,"three transactions failed");
      $display("STAGED_ADAPTER_PASS cancel=0 publications=3 words=1536");
    end
    $finish(0);
  end
  initial begin #1000000;$fatal(1,"adapter watchdog expired");end
endmodule
