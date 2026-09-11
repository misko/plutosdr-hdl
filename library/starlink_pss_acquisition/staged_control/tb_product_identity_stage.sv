`timescale 1ns/1ps
// Component boundary with the actual product mailbox and original comparator
// as an independent same-input witness. No FFT, CDC or RF throughput claim.
module tb;
  reg clk=0,resetn=0,abort_epoch=0;
  always #5 clk=~clk;
  reg input_valid=0,input_last=0,publish_enable=1,allow_write=1,reader_ready=0;
  reg [35:0] input_data=0;
  reg [8:0] input_position=0;
  reg [69:0] input_metadata=0;
  wire input_ready,staged_valid,staged_ready,staged_last,identity_good,stage_idle,stage_fault;
  wire [35:0] staged_data;
  wire [8:0] staged_position;
  wire [69:0] staged_metadata,held_metadata;
  wire metadata_load,bank_ready,bank_fault,framing_fault,read_valid,read_last,request,ack;
  wire [35:0] read_data;
  wire [8:0] read_position;
  wire [69:0] read_metadata;
  wire [69:0] reference_metadata=metadata_load ? staged_metadata : held_metadata;
  wire bank_commit=publish_enable && !stage_fault && !bank_fault && (framing_fault===1'b0);
  wire bank_valid=staged_valid && allow_write;
  // Rewriting private LAST is not consuming the slot. Retire it only when
  // the bank's final publication is actually authorized; a fault cancels it.
  assign staged_ready=bank_ready && allow_write && ((staged_last===1'b0) || bank_commit);
  starlink_pss_product_identity_stage stage(
    .clk(clk),.resetn(resetn),.abort_epoch(abort_epoch || bank_fault),
    .input_valid(input_valid),.input_ready(input_ready),.input_data(input_data),
    .input_position(input_position),.input_last(input_last),.input_metadata(input_metadata),
    .reference_metadata(reference_metadata),
    .output_valid(staged_valid),.output_ready(staged_ready),
    .output_data(staged_data),.output_position(staged_position),.output_last(staged_last),
    .output_identity_good(identity_good),.output_metadata(staged_metadata),.idle(stage_idle),.fault(stage_fault));
  starlink_pss_product_mailbox_staged_identity #(.RESET_RELEASE_EXTERNAL(1),.EXPLICIT_COMMIT(1)) bank(
    .input_clk(clk),.input_resetn(resetn),.input_valid(bank_valid),.input_commit_authorized(bank_commit),
    .input_ready(bank_ready),.input_data(staged_data),.input_position(staged_position),
    .input_last(staged_last),.input_metadata(staged_metadata),.input_metadata_certified(identity_good),
    .writer_identity_metadata(held_metadata),.writer_identity_load(metadata_load),
    .input_fault(bank_fault),.input_framing_fault_now(framing_fault),
    .output_clk(clk),.output_resetn(resetn),.output_valid(read_valid),.output_ready(reader_ready),
    .output_data(read_data),.output_position(read_position),.output_last(read_last),.output_metadata(read_metadata),
    .owner_request(request),.owner_ack_sync(ack),.writer_reset_idle(),.reader_reset_idle());
  wire original_ready,original_fault,original_framing,original_valid,original_last,original_request,original_ack;
  wire [35:0] original_data;
  wire [8:0] original_position;
  wire [69:0] original_metadata;
  starlink_pss_mailbox_owner_view #(.RESET_RELEASE_EXTERNAL(1),.EXPLICIT_COMMIT(1)) original(
    .input_clk(clk),.input_resetn(resetn),.input_valid(bank_valid),.input_commit_authorized(bank_commit),
    .input_ready(original_ready),.input_data(staged_data),.input_position(staged_position),
    .input_last(staged_last),.input_metadata(staged_metadata),.input_fault(original_fault),
    .input_framing_fault_now(original_framing),.output_clk(clk),.output_resetn(resetn),
    .output_valid(original_valid),.output_ready(reader_ready),.output_data(original_data),
    .output_position(original_position),.output_last(original_last),.output_metadata(original_metadata),
    .owner_request(original_request),.owner_ack_sync(original_ack),.writer_reset_idle(),.reader_reset_idle());
  reg compare_original=1;
  integer pushes=0,pops=0,reads=0,refills=0,hold_checks=0,oracle_checks=0,total_reads=0,reference_updates=0;
  integer good_blocks=0,bad_metadata=0,bad_framing=0,reset_cases=0;
  reg [69:0] block_metadata;
  reg held=0;
  reg [116:0] held_word;
  always @(posedge clk) begin
    if(!resetn)begin pushes=0;pops=0;reads=0;held=0;end
    else begin
      if(held && !stage_fault)begin
        if(!staged_valid || {staged_data,staged_position,staged_last,staged_metadata,identity_good}!==held_word)
          $fatal(1,"private word/certificate changed during stall");
        hold_checks=hold_checks+1;
      end
      held=staged_valid && !staged_ready && !stage_fault;
      held_word={staged_data,staged_position,staged_last,staged_metadata,identity_good};
      if(input_valid && input_ready)pushes=pushes+1;
      if(staged_valid && staged_ready)pops=pops+1;
      if(metadata_load)begin
        if(!input_ready)$fatal(1,"first-word reference update inserted a refill pause");
        reference_updates=reference_updates+1;
      end
      if(input_valid && input_ready && staged_valid && staged_ready)refills=refills+1;
      if(read_valid && reader_ready)begin
        if(read_position!==reads || read_data!==(36'h100000000+reads) ||
           read_last!==(reads==511) || read_metadata!==block_metadata)
          $fatal(1,"published product payload/metadata/order mismatch");
        reads=reads+1;total_reads=total_reads+1;
      end
      if(compare_original)begin
        oracle_checks=oracle_checks+1;
        if({bank_ready,bank_fault,framing_fault,read_valid,request,ack} !==
           {original_ready,original_fault,original_framing,original_valid,original_request,original_ack})
          $fatal(1,"actual original mailbox control mismatch");
        if(read_valid && {read_data,read_position,read_last,read_metadata} !==
            {original_data,original_position,original_last,original_metadata})
          $fatal(1,"actual original mailbox read mismatch");
      end
    end
  end
  task reset_epoch;
    begin
      @(negedge clk);resetn=0;input_valid=0;abort_epoch=0;reader_ready=0;
      publish_enable=1;allow_write=1;compare_original=1;
      repeat(3)@(negedge clk);
      resetn=1;block_metadata=70'h2123456789abcdef;
      repeat(2)@(negedge clk);
    end
  endtask
  task word(input integer position,input integer corruption,input integer bit_number);
    begin
      @(negedge clk);input_valid=1;input_position=position;input_last=position==511;
      input_data=36'h100000000+position;input_metadata=block_metadata;
      case(corruption)
        1:input_metadata[bit_number]=!input_metadata[bit_number];
        2:input_metadata[bit_number]=1'bx;
        3:input_metadata[bit_number]=1'bz;
        4:input_position=position+1;
        5:input_last=!input_last;
      endcase
      @(posedge clk);while(input_ready!==1)@(posedge clk);
      #0.01;
    end
  endtask
  task stop_source;
    begin @(negedge clk);input_valid=0;input_metadata=70'h3fffffffffffffffff;end
  endtask
  task finish_block;
    begin
      reader_ready=1;
      while(reads!=512 || !bank_ready)@(negedge clk);
      repeat(3)@(negedge clk);
      if(pushes!=512 || pops!=512 || bank_fault || stage_fault || !stage_idle || request!==ack)
        $fatal(1,"product block conservation/release mismatch");
      good_blocks=good_blocks+1;
    end
  endtask
  task good_block(input integer hold_final);
    integer p;
    begin
      reset_epoch;if(hold_final)publish_enable=0;
      for(p=0;p<512;p=p+1)word(p,0,0);
      stop_source;
      if(hold_final)begin
        while(!staged_valid || !staged_last)@(negedge clk);
        repeat(200)begin
          @(negedge clk);
          if(!staged_valid || request || read_valid || pops!=511 || bank_fault)
            $fatal(1,"unpublished final slot was dropped or published early");
        end
        publish_enable=1;
      end
      finish_block;
    end
  endtask
  task stalled_block;
    integer position,cycle;
    begin
      reset_epoch;
      fork
        begin
          for(position=0;position<512;position=position+1)begin
            word(position,0,0);
            if(position%19==5)begin stop_source;repeat(2)@(negedge clk);end
          end
          stop_source;
        end
        begin
          for(cycle=0;cycle<1600;cycle=cycle+1)begin
            @(negedge clk);#0.002;allow_write=(cycle%17)>=3;
          end
          allow_write=1;
        end
      join
      finish_block;
    end
  endtask
  integer p,b,k,position,variant,location;
  initial begin
    good_block(0);good_block(1);stalled_block;
    for(location=0;location<2;location=location+1)
    for(b=0;b<70;b=b+1)for(k=1;k<=3;k=k+1)begin
      reset_epoch;compare_original=k==1;
      position=location==0 ? 1 : 511;
      for(p=0;p<=position;p=p+1)word(p,p==position ? k : 0,b);
      stop_source;repeat(5)@(negedge clk);
      if(!bank_fault || !stage_fault || request || read_valid || reads!=0)
        $fatal(1,"bad/unknown identity escaped quarantine");
      bad_metadata=bad_metadata+1;
    end
    for(variant=0;variant<6;variant=variant+1)begin
      reset_epoch;position=variant/2==0 ? 0 : variant/2==1 ? 255 : 511;
      for(p=0;p<=position;p=p+1)word(p,p==position ? 4+(variant%2) : 0,0);
      stop_source;repeat(5)@(negedge clk);
      if(!bank_fault || !stage_fault || request || read_valid)$fatal(1,"bad position/LAST published");
      bad_framing=bad_framing+1;
    end
    for(variant=0;variant<8;variant=variant+1)begin
      reset_epoch;publish_enable=0;
      for(p=0;p<512;p=p+1)word(p,0,0);
      stop_source;while(!staged_valid || !staged_last)@(negedge clk);
      if(variant==0)begin resetn=0;#0.01;if(staged_valid || !stage_idle)$fatal(1,"reset kept private final");end
      else begin
        case(variant)
          1:abort_epoch=1;
          2:abort_epoch=1'bx;
          3:abort_epoch=1'bz;
          4:input_valid=1'bx;
          5:input_valid=1'bz;
          6:force staged_ready=1'bx;
          7:force staged_ready=1'bz;
        endcase
        #0.01;if(!stage_fault || staged_valid)$fatal(1,"abort/unknown control failed closed");
      end
      repeat(5)@(negedge clk);
      if(request || read_valid)$fatal(1,"cancelled final published");
      release staged_ready;
      reset_cases=reset_cases+1;good_block(0);
    end
    good_block(0);
    if(refills<511 || hold_checks<200 || oracle_checks<1000)$fatal(1,"component coverage missing");
    $display("PRODUCT_IDENTITY_COMPONENT_PASS good_blocks=%0d bad_metadata=%0d bad_framing=%0d resets=%0d reads=%0d refills=%0d holds=%0d oracle=%0d updates=%0d",good_blocks,bad_metadata,bad_framing,reset_cases,total_reads,refills,hold_checks,oracle_checks,reference_updates);
    $finish;
  end
  initial begin #10000000;$fatal(1,"product identity component deadline");end
endmodule
