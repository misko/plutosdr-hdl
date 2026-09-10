// Real P1 controller/guards/joiner/ROM/product/banks, controlled identity actor.
// This is NOT actual FFT numerics, RF sensitivity, realtime capacity or timing.
`timescale 1ns/1ps
module tb_starlink_pss_checked_product_top #(parameter integer ENABLED=1, RESET_REFERENCE_PURGE=1);
  reg clk=0,fft_clk=0,resetn=0,fft_resetn=0,slow_clock_enable=1,fast_clock_enable=1;
  // Reset-only secondary oracle receives a DISTINCT held-reset provider.
  // Candidate raw resets/inputs/expected tuples are never changed by this.
  reg reference_extra_resetn=1;
  wire reference_fft_resetn=fft_resetn && reference_extra_resetn;
  always #5 if(slow_clock_enable)clk=~clk;
  always #2.857 if(fast_clock_enable)fft_clk=~fft_clk;
  reg input_valid=0,input_last=0,output_ready=1;
  reg [35:0] input_data=0;
  reg [8:0] input_position=0;
  reg [63:0] input_block_start=0;
  wire [1:0] input_ready,output_valid,output_last,fault;
  wire [35:0] output_data0,output_data1;
  wire [8:0] output_position0,output_position1;
  wire [74:0] output_metadata0,output_metadata1;
`define PARAMS .REGISTERED_SCHEDULING(1),.DISTRIBUTED_FAST_FAULT(1),.PER_CAUSE_FAULT_CDC(1), \
    .PRIVATE_NEXT_START_SCRATCH(1),.PRIVATE_ROM_READ_AHEAD(1),.PRIVATE_BLOCK_METADATA_READ_AHEAD(1), \
    .PRODUCER_LOCAL_FINAL_FENCE(1)
`define PORTS(I) .clk(clk),.resetn(resetn),.fft_clk(fft_clk),.fft_resetn(I==0 ? reference_fft_resetn : fft_resetn), \
    .input_valid(input_valid),.input_ready(input_ready[I]),.input_data(input_data), \
    .input_position(input_position),.input_last(input_last),.input_block_start(input_block_start), \
    .output_valid(output_valid[I]),.output_ready(output_ready),.output_data(output_data``I), \
    .output_position(output_position``I),.output_last(output_last[I]),.output_metadata(output_metadata``I),.fault(fault[I])
  starlink_pss_fft_bank_owned_product_fence #(`PARAMS) reference_top (`PORTS(0));
  starlink_pss_fft_bank_owned_checked_product #(`PARAMS,.CHECKED_PRODUCT_BANK(ENABLED)) dut (`PORTS(1));
`undef PARAMS
`undef PORTS
  reg [120:0] trace0[0:4095],trace1[0:4095];
  reg [35:0] independently_expected_payload[0:511];
  initial $readmemh("actor_expected_product.mem",independently_expected_payload);
  reg [63:0] independently_expected_start;
  integer count0=0,count1=0,compared=0,fast_cycles=0,kind=0,bit_index=0,target=0;
  integer starts=0,acknowledgments=0,seals=0,publications=0,core_beats=0,releases=0;
  integer start_cycle=-1,ack_cycle=-1,first_inverse=-1,last_inverse=-1;
  reg [74:0] changed_head;
  reg [69:0] changed_product;
  reg [1:0] changed_lease;
  integer fence_cycle=0;
  integer prejoin_held_edges=0;
  reg fast_rejoined=0;
  reg raw_corruption=0;
  integer forward_start_cycle=0,product_final_cycle=0,seal_cycle=0,publish_cycle=0;
  integer inverse_start_cycle=0,job_first_inverse=0,job_last_inverse=0;
  integer reference_tick=0,reference_forward=0,reference_final=0,reference_inverse=0,reference_first=0,reference_job=0;
  always @(posedge fft_clk)begin
    reference_tick=reference_tick+1;
    if(reference_top.input_job_start && !reference_top.held_phase)reference_forward=reference_tick;
    if(reference_top.product_valid && reference_top.product_bank_ready && !reference_top.fast_fault && reference_top.product_last)
      reference_final=reference_tick;
    if(reference_top.input_job_start && reference_top.held_phase)reference_inverse=reference_tick;
    if(reference_top.certified_input_beat && reference_top.held_phase)begin
      if(reference_top.product_bank_position==0)reference_first=reference_tick;
      if(reference_top.product_bank_position==511)begin
        reference_job=reference_job+1;
        $display("CHECKED_TOP_REFERENCE_LATENCY job=%0d forward_start=%0d product_final=%0d inverse_start=%0d core_first=%0d core_last=%0d",reference_job,reference_forward,reference_final,reference_inverse,reference_first,reference_tick);
      end
    end
  end
  always @(posedge clk)if(resetn && fft_resetn)begin
    if(output_valid[0] && output_ready)begin
      trace0[count0]={output_metadata0,output_last[0],output_position0,output_data0};count0=count0+1;
    end
    if(output_valid[1] && output_ready)begin
      independently_expected_start = kind>=9 ? 64'd447 : (count1/512)*64'd447;
      if({output_metadata1,output_last[1],output_position1,output_data1} !==
          {1'b1,independently_expected_start,10'b0,(count1%512==511),9'(count1%512),independently_expected_payload[count1%512]})
        $fatal(1,"CHECKED_TOP_INDEPENDENT_ACTOR_TUPLE_CHANGED index=%0d",count1);
      trace1[count1]={output_metadata1,output_last[1],output_position1,output_data1};count1=count1+1;
    end
    while(compared<count0 && compared<count1)begin
      if(trace0[compared]!==trace1[compared])$fatal(1,"CHECKED_TOP_ACCEPTED_OUTPUT_CHANGED index=%0d reference=%h candidate=%h ref_descriptor=%h candidate_descriptor=%h",compared,trace0[compared],trace1[compared],reference_top.engine_metadata,dut.engine_metadata);
      compared=compared+1;
    end
  end
  always @(posedge fft_clk)begin
    fast_cycles=fast_cycles+1;
    if(fast_cycles>30000)$fatal(1,"CHECKED_TOP_WATCHDOG state=%0d fault=%b ref_state=%0d ref_input=%h ref_result=%h ref_preflight=%h candidate_count=%0d reference_count=%0d",dut.state,fault,reference_top.state,reference_top.input_guard.fault_reasons,reference_top.result_guard.fault_reasons,reference_top.epoch_preflight_reasons,count1,count0);
    if(resetn && fft_resetn)begin
      if(dut.input_job_start)begin starts=starts+1;start_cycle=fast_cycles;end
      if(kind==0 && (dut.fast_fault || reference_top.fast_fault))
        $fatal(1,"CHECKED_TOP_HEALTHY_FAULT state=%0d input=%h result=%h preflight=%h",dut.state,
          dut.input_guard.fault_reasons,dut.result_guard.fault_reasons,dut.epoch_preflight_reasons);
    end
  end
  generate if(ENABLED)begin : monitor
    integer tick=0;
    always @(posedge fft_clk)begin
      tick=tick+1;
      if(dut.fast_running)begin
      if(dut.checked_product_bank.private_take !==
         (dut.product_valid === 1'b1 && (dut.product_bank_ready && !dut.fast_fault) === 1'b1))
        $fatal(1,"CHECKED_TOP_ACTUAL_PRODUCT_HANDSHAKE_CHANGED");
      if(dut.checked_product_bank.core_take !== (dut.certified_input_beat && dut.held_phase))
        $fatal(1,"CHECKED_TOP_CORE_CERTIFICATE_CHANGED");
      if(dut.checked_product_bank.actual_handoff)begin
        acknowledgments=acknowledgments+1;ack_cycle=tick;
        if(!dut.checked_product_bank.ack_binding || !dut.product_guard_ack_event)
          $fatal(1,"CHECKED_TOP_UNBOUND_ACK");
      end
      if(dut.input_job_start && !dut.held_phase)forward_start_cycle=tick;
      if(dut.input_job_start && dut.held_phase)inverse_start_cycle=tick;
      if(dut.checked_product_bank.private_take && dut.product_last)product_final_cycle=tick;
      if(dut.checked_product_bank.seal)begin seals=seals+1;seal_cycle=tick;end
      if(dut.checked_product_bank.publication)begin publications=publications+1;publish_cycle=tick;end
      if(dut.job_accept && !dut.next_inverse && dut.checked_product_bank.issuer_events[0])
        $fatal(1,"CHECKED_TOP_LEGAL_FORWARD_ADMISSION_REJECTED");
      if(dut.return_commit_valid && dut.result_destination_ready && !dut.next_inverse && dut.checked_product_bank.issuer_events[1])
        $fatal(1,"CHECKED_TOP_REAL_GUARD_COMPLETION_REJECTED");
      if(dut.certified_input_beat && dut.held_phase)begin
        core_beats=core_beats+1;if(first_inverse<0)first_inverse=fast_cycles;last_inverse=fast_cycles;
        if(dut.product_bank_position==0)job_first_inverse=tick;
        job_last_inverse=tick;
        if(raw_corruption && dut.product_bank_position>=target)
          $fatal(1,"CHECKED_TOP_BAD_RAW_TOKEN_DELIVERED");
      end
      if(dut.checked_product_bank.lease_release)begin
        releases=releases+1;
        if(!dut.checked_input_complete || !dut.checked_product_bank.adapter.reader.drained)
          $fatal(1,"CHECKED_TOP_EARLY_LEASE_RELEASE");
        $display("CHECKED_TOP_LATENCY job=%0d forward_start=%0d product_final=%0d seal=%0d publication=%0d ack=%0d inverse_start=%0d core_first=%0d core_last=%0d release=%0d",releases,forward_start_cycle,product_final_cycle,seal_cycle,publish_cycle,ack_cycle,inverse_start_cycle,job_first_inverse,job_last_inverse,tick);
      end
      if(dut.input_job_start && dut.held_phase && !dut.product_start_binding)
        $fatal(1,"CHECKED_TOP_UNBOUND_START");
    end
    end
  end endgenerate
  initial begin
    if(!$value$plusargs("CASE=%d",kind))kind=0;
    if(!$value$plusargs("BIT=%d",bit_index))bit_index=0;
    if(!$value$plusargs("TARGET=%d",target))target=0;
    repeat(8)@(negedge clk);resetn=1;fft_resetn=1;
    for(integer job=0;job<(kind==0 ? 4 : 1);job=job+1)begin
      wait(input_ready===2'b11);@(negedge clk);
      input_block_start=job*447;
      for(integer n=0;n<512;n=n+1)begin
        input_valid=1;input_position=n;input_last=n==511;
        input_data={18'(n%17-8),18'(n%23-11)};
        @(negedge clk);
      end
      input_valid=0;input_last=0;
    end
    if(kind!=0)wait(1'b0); // Additive negative epochs own their terminal only.
    wait(compared==2048);repeat(150)@(negedge clk);
    if(fault || count0!=2048 || count1!=2048 || starts!=8)
      $fatal(1,"CHECKED_TOP_COMPLETION_COUNTS");
    if(ENABLED && (acknowledgments!=4 || seals!=4 || publications!=4 || releases!=4 || core_beats!=2048))
      $fatal(1,"CHECKED_TOP_OWNERSHIP_COUNTS");
    $display("CHECKED_PRODUCT_TOP_CONTROL_PASS enabled=%0d compared=%0d starts=%0d ack=%0d seals=%0d publications=%0d core=%0d releases=%0d control_actor_not_fft=1",ENABLED,compared,starts,acknowledgments,seals,publications,core_beats,releases);
    $finish;
  end
  generate if(ENABLED)begin : hazards
    task quarantine_no_inverse;
      begin
        repeat(8)@(negedge fft_clk);
        if(!dut.fast_fault || starts!=1 || core_beats!=0 || releases!=0 || publications>1 ||
            dut.input_job_start || dut.config_valid || dut.product_bank_read_ready || dut.output_valid)
          $fatal(1,"CHECKED_TOP_BINDING_ESCAPE kind=%0d bit=%0d target=%0d starts=%0d",kind,bit_index,target,starts);
        $display("CHECKED_TOP_REJECT_PASS kind=%0d bit=%0d target=%0d starts=%0d ack=%0d releases=%0d current=%0d control_actor_not_fft=1",kind,bit_index,target,starts,acknowledgments,releases,fence_cycle);
        $finish;
      end
    endtask
    task wait_boundary;
      begin
        case(target)
          0:wait(dut.product_handoff_capacity);
          1:wait(dut.state==dut.VERIFY_LEASE && dut.held_phase);
          2:wait(dut.state==dut.ARM_JOB && dut.held_phase && !dut.admission_receipt);
          3:wait(dut.state==dut.ARM_JOB && dut.held_phase && dut.admission_receipt);
          4:wait(dut.input_job_start_private && dut.held_phase);
          5:wait(dut.completion_accept && !dut.next_inverse);
          6:wait(dut.completion_receipt && !dut.next_inverse);
          7:wait(dut.checked_product_bank.seal);
          8:wait(dut.checked_product_bank.publication);
          9:wait(dut.product_valid && dut.product_last);
          default:$fatal(1,"CHECKED_TOP_BAD_BOUNDARY");
        endcase
        @(negedge fft_clk);
        if(core_beats || starts!=1)$fatal(1,"CHECKED_TOP_BOUNDARY_LATE");
      end
    endtask
    initial begin
      wait(resetn && fft_resetn);
      if(kind==1)begin
        wait(dut.product_valid && dut.product_position==target);@(negedge fft_clk);
        force dut.product_bank_ready=1'b0;
        repeat(3)begin
          #0.001;
          if(dut.checked_product_bank.private_take || dut.product.output_ready)
            $fatal(1,"CHECKED_TOP_FORCED_READY_TAKE");
          @(negedge fft_clk);
        end
        release dut.product_bank_ready;
        if(target==511)begin
          wait(compared==512);repeat(20)@(negedge fft_clk);
          if(fault || starts!=2 || acknowledgments!=1 || releases!=1)
            $fatal(1,"CHECKED_TOP_FINAL_READY_RECOVERY");
          $display("CHECKED_TOP_READY_PASS target=%0d compared=%0d outcome=complete control_actor_not_fft=1",target,compared);
          $finish;
        end else begin
          repeat(20)@(negedge fft_clk);
          if(!dut.fast_fault || publications || releases || core_beats)
            $fatal(1,"CHECKED_TOP_INTERIOR_READY_QUARANTINE");
          $display("CHECKED_TOP_READY_PASS target=%0d compared=%0d outcome=quarantine control_actor_not_fft=1",target,compared);
          $finish;
        end
      end
      if(kind==2 || kind==3 || kind==4 || kind==11 || kind==13 || kind==14)begin
        wait_boundary();
        if(kind==2 || kind==13 || kind==14)begin
          changed_head=dut.product_head_metadata ^ (75'b1<<bit_index);
          if(kind==13)changed_head[bit_index]=1'bx;
          if(kind==14)changed_head[bit_index]=1'bz;
          force dut.product_head_metadata=changed_head;
        end else if(kind==3)begin
          changed_lease=dut.product_head_lease ^ (2'b1<<bit_index);
          force dut.product_head_lease=changed_lease;
        end else if(kind==4)force dut.checked_product_bank.bound_receipt=1'b0;
        else force dut.product_head_owned_good=1'b0;
        #0.001;
        if(target==0 && (dut.checked_product_bank.actual_handoff || dut.product_guard_ack_event))
          $fatal(1,"CHECKED_TOP_CURRENT_UNBOUND_ACK");
        if(target==4 && dut.input_job_start)$fatal(1,"CHECKED_TOP_CURRENT_UNBOUND_START");
        fence_cycle=1;
        quarantine_no_inverse();
      end
      if(kind==5)begin
        wait_boundary();
        case(bit_index)
          0:force dut.core_output_valid=1'b1;
          1:force dut.core_status_valid=1'b1;
          2:force dut.event_frame=1'b1;
          3:force dut.certified_input_beat=1'b1;
          4:force dut.certified_input_complete=1'b1;
          5:force dut.event_input_halt=1'b1;
          6:force dut.product_overflow=1'b1;
          7:force dut.source_fault_fast=2'b11;
          8:force dut.input_guard_fault=1'b1;
          9:force dut.input_fault_now=1'b1;
          10:force dut.duplicate_start_fault_now=1'b1;
          default:$fatal(1,"CHECKED_TOP_BAD_CURRENT_CAUSE");
        endcase
        #0.001;
        if(dut.product_guard_ack_event || dut.checked_product_bank.actual_handoff ||
            dut.checked_product_bank.publication || dut.checked_product_bank.lease_release ||
            dut.return_commit_valid)
          $fatal(1,"CHECKED_TOP_CURRENT_RAW_ESCAPE");
        fence_cycle=1;
        quarantine_no_inverse();
      end
      if(kind==6)begin
        wait(dut.checked_product_bank.adapter.bank_valid && dut.checked_product_bank.adapter.bank_position==target);
        @(negedge fft_clk);
        if(target==3 && dut.checked_product_bank.adapter.bank_ready)
          $fatal(1,"CHECKED_TOP_RAW_STALL_NOT_REACHED");
        changed_head=dut.checked_product_bank.adapter.bank_metadata ^ (75'b1<<bit_index);
        force dut.checked_product_bank.adapter.bank_metadata=changed_head;
        raw_corruption=1;
        repeat(10)@(negedge fft_clk);
        if(!dut.fast_fault || !dut.checked_product_bank.reader_reasons[2] || releases ||
           dut.output_valid || dut.checked_product_bank.core_take || core_beats>target)
          $fatal(1,"CHECKED_TOP_RAW_READER_ESCAPE bit=%0d target=%0d core=%0d",bit_index,target,core_beats);
        $display("CHECKED_TOP_RAW_READ_PASS bit=%0d target=%0d core=%0d reason=%h control_actor_not_fft=1",bit_index,target,core_beats,dut.checked_product_bank.reader_reasons);
        $finish;
      end
      if(kind==7 || kind==8)begin
        wait(dut.product_valid && dut.product_position==target);@(negedge fft_clk);
        if(kind==7)begin
          changed_product=dut.checked_product_bank.adapter.product_metadata ^ (70'b1<<bit_index);
          force dut.checked_product_bank.adapter.product_metadata=changed_product;
        end else if(bit_index==0)force dut.checked_product_bank.adapter.product_position=9'd12;
        else if(target==511)force dut.checked_product_bank.adapter.product_last=1'b0;
        else force dut.checked_product_bank.adapter.product_last=1'b1;
        repeat(12)@(negedge fft_clk);
        if(!dut.fast_fault || publications || acknowledgments || releases || core_beats ||
          dut.return_commit_valid || dut.checked_product_bank.publication)
          $fatal(1,"CHECKED_TOP_BAD_PRODUCER_PUBLICATION");
        if(kind==8 && target==37 && bit_index==1 && dut.checked_product_bank.adapter.forward_completion)
          $fatal(1,"CHECKED_TOP_EARLY_LAST_FALSE_COMPLETION");
        $display("CHECKED_TOP_RAW_PRODUCT_PASS kind=%0d bit=%0d target=%0d bank_reason=%h issuer_reason=%h control_actor_not_fft=1",kind,bit_index,target,dut.checked_product_bank.bank_reasons,dut.checked_product_bank.issuer_reasons);
        $finish;
      end
      if(kind==9 || kind==10)begin
        case(target)
          0:wait(dut.source_bank.request_toggle);
          1:wait(dut.certified_input_beat && !dut.held_phase && dut.source_position==37);
          2:wait(dut.product_valid && dut.product_position==37);
          3:wait(dut.product_bound_receipt);
          4:wait(dut.certified_input_beat && dut.held_phase && dut.product_bank_position==37);
          default:$fatal(1,"CHECKED_TOP_BAD_RESET_PHASE");
        endcase
        @(negedge clk);
        if(kind==10)begin
          if(!dut.source_ready)$fatal(1,"CHECKED_TOP_POISON_WRITER_NOT_READY");
          input_valid=1;input_position=37;input_last=0;
          @(negedge clk);input_valid=0;
          if(!dut.source_fault)$fatal(1,"CHECKED_TOP_POISON_NOT_REACHED");
        end
        slow_clock_enable=0;
        if(RESET_REFERENCE_PURGE)reference_extra_resetn=0;
        if(bit_index==0)fft_resetn=0;else resetn=0;
        repeat(4)@(negedge fft_clk);
        resetn=1;fft_resetn=1;
        wait(dut.fast_running);
        repeat(8)begin
          @(negedge fft_clk);
          if(dut.source_epoch_open || dut.source_valid || dut.source_fault_fast ||
             dut.checked_product_bank.origin_valid || dut.product_bound_receipt ||
             dut.checked_product_bank.private_take || dut.checked_product_bank.publication ||
             dut.input_job_start || dut.config_valid || dut.product_bank_read_ready)
            $fatal(1,"CHECKED_TOP_PAUSED_SLOW_REOPENED kind=%0d reset=%0d target=%0d",kind,bit_index,target);
          if(kind==10 && !dut.source_fault)$fatal(1,"CHECKED_TOP_OLD_SOURCE_POISON_NOT_RETAINED");
        end
        slow_clock_enable=1;
        if(RESET_REFERENCE_PURGE)begin
          repeat(4)@(negedge clk);
          reference_extra_resetn=1;
        end
        wait(dut.source_epoch_open && dut.slow_running && input_ready===2'b11);
        @(negedge clk);
        count0=0;count1=0;compared=0;starts=0;acknowledgments=0;seals=0;publications=0;releases=0;core_beats=0;
        input_block_start=447;
        for(integer n=0;n<512;n=n+1)begin
          input_valid=1;input_position=n;input_last=n==511;input_data={18'(n%17-8),18'(n%23-11)};
          @(negedge clk);
        end
        input_valid=0;input_last=0;
        wait(compared==512);repeat(20)@(negedge clk);
        if(fault || starts!=2 || acknowledgments!=1 || releases!=1 || core_beats!=512)
          $fatal(1,"CHECKED_TOP_RESET_RECOVERY_FAILED");
        $display("CHECKED_TOP_RESET_PASS kind=%0d reset=%0d target=%0d paused_edges=8 compared=%0d starts=%0d ack=%0d releases=%0d independent_expected=512 secondary_reference_reset_provider=%0d control_actor_not_fft=1",kind,bit_index,target,compared,starts,acknowledgments,releases,RESET_REFERENCE_PURGE);
        $finish;
      end
      if(kind==12 || kind==15)begin
        wait(dut.product_valid && dut.product_position==target);@(negedge fft_clk);
        if(kind==12)begin
          if(bit_index==0)force dut.product_bank_ready=1'bx;
          else force dut.product_bank_ready=1'bz;
        end else begin
          force dut.product_bank_ready=1'b0;
          if(bit_index==0)force dut.product_valid=1'bx;
          else force dut.product_valid=1'bz;
        end
        #0.001;
        if(!dut.checked_product_bank.issuer_events[7] || !dut.external_fault_now ||
            dut.checked_product_bank.private_take || dut.checked_product_bank.publication)
          $fatal(1,"CHECKED_TOP_UNKNOWN_PRODUCT_CURRENT_ESCAPE");
        repeat(8)@(negedge fft_clk);
        if(!dut.fast_fault || !dut.checked_product_bank.issuer_reasons[7] || publications || acknowledgments || releases)
          $fatal(1,"CHECKED_TOP_UNKNOWN_PRODUCT_STICKY_ESCAPE");
        $display("CHECKED_TOP_UNKNOWN_PRODUCT_PASS kind=%0d value=%0d target=%0d current=1 sticky=1 control_actor_not_fft=1",kind,bit_index,target);
        $finish;
      end
      if(kind==17 || kind==18)begin
        // Forward activity, no inverse-output owner. The unchanged output CDC
        // is not claimed to solve arbitrary paused-fast published-output reset.
        wait(dut.product_valid && dut.product_position==37);@(negedge fft_clk);
        if(dut.next_inverse || dut.output_bank.request_toggle)
          $fatal(1,"CHECKED_TOP_FAST_PAUSE_WRONG_PHASE");
        fast_clock_enable=0;reference_extra_resetn=0;
        if(bit_index==0)fft_resetn=0;else resetn=0;
        repeat(4)@(negedge clk);resetn=1;fft_resetn=1;
        wait(input_ready[1]===1'b1);@(negedge clk);
        count0=0;count1=0;compared=0;starts=0;acknowledgments=0;seals=0;publications=0;releases=0;core_beats=0;
        input_block_start=447;
        for(integer n=0;n<512;n=n+1)begin
          if(!fast_rejoined && (dut.source_epoch_open || dut.source_valid || dut.checked_product_bank.publication || dut.output_valid))
            $fatal(1,"CHECKED_TOP_PREJOIN_SOURCE_ESCAPE");
          input_valid=1;input_position=n;input_last=n==511;input_data={18'(n%17-8),18'(n%23-11)};
          if(input_ready[1]!==1'b1)begin
            if(kind==17)$fatal(1,"CHECKED_TOP_PREJOIN_SOURCE_NOT_ACCEPTED n=%0d req=%b ack_sync=%b fast_ack=%b write=%0d epoch=%b fault=%b",n,dut.source_bank.request_toggle,dut.source_bank.acknowledge_sync,dut.source_bank.acknowledge_toggle,dut.source_bank.write_position,dut.source_epoch_open,dut.source_fault);
            if(n!=2 || fast_rejoined || dut.source_bank.write_position!=2 ||
               dut.source_bank.request_toggle!==1'b0 || dut.source_bank.acknowledge_sync!==2'b11 ||
               dut.source_bank.acknowledge_toggle!==1'b1)
              $fatal(1,"CHECKED_TOP_PREJOIN_STALL_PREMISE_MISSING");
            repeat(8)begin
              @(negedge clk);prejoin_held_edges=prejoin_held_edges+1;
              if(input_ready[1]!==1'b0 || dut.source_bank.write_position!=2 ||
                 dut.source_bank.request_toggle || dut.source_fault || dut.source_valid ||
                 dut.source_epoch_open || dut.checked_product_bank.publication || dut.output_valid ||
                 input_position!=2 || input_data!=={18'(2%17-8),18'(2%23-11)} || input_block_start!=447)
                $fatal(1,"CHECKED_TOP_PREJOIN_HELD_PREFIX_CHANGED");
            end
            fast_clock_enable=1;fast_rejoined=1;
            wait(input_ready[1]===1'b1);
          end
          @(posedge clk);
          if(input_ready[1]!==1'b1)$fatal(1,"CHECKED_TOP_PREJOIN_RESUMED_ACCEPT_MISSING");
          @(negedge clk);
        end
        input_valid=0;input_last=0;
        if(!fast_rejoined || prejoin_held_edges!=8 || dut.source_fault)
          $fatal(1,"CHECKED_TOP_PREJOIN_RESUME_PREMISE_MISSING");
        wait(count1==512);repeat(20)@(negedge clk);
        if(dut.fault || starts!=2 || acknowledgments!=1 || releases!=1 || core_beats!=512 || count0)
          $fatal(1,"CHECKED_TOP_PREJOIN_RECOVERY_FAILED");
        $display("CHECKED_TOP_PREJOIN_HELD_PASS reset=%0d accepted_while_fast_paused=2 held_edges=%0d accepted_total=512 independent_expected=512 starts=%0d ack=%0d releases=%0d secondary_reference_held_reset=1 control_actor_not_fft=1",bit_index,prejoin_held_edges,starts,acknowledgments,releases);
        $finish;
      end
    end
  end endgenerate
  `include "checked_product_default_observer.svh"
endmodule
