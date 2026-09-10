`timescale 1ns/1ps
module tb_starlink_pss_checked_product_read;
  reg clk=0,resetn=0;
  always #5 clk=~clk;
  reg admit_valid=0,raw_valid=0,raw_last=0,core_enable=0,core_ready=0;
  reg consumer_complete=0,release_valid=0;
  reg [1:0] admit_lease=0,raw_lease=0,release_lease=0;
  reg [74:0] admit_metadata=75'h123456789abcdef123,raw_metadata=0;
  reg [35:0] raw_data=0;
  reg [8:0] raw_position=0;
  reg [7:0] live_faults=0;
  wire admit_ready,raw_ready,core_valid,core_last,release_ready,released;
  wire active,prefetched,final_consumed,drained,private_take,core_take;
  wire validation_fault_now;
  wire [35:0] core_data;
  wire [8:0] core_position;
  wire [74:0] core_metadata;
  wire [15:0] fault_reasons;
  wire fault_token_valid;
  wire [8:0] fault_token_position;
  wire [1:0] fault_token_lease;
  starlink_pss_checked_product_read #(.CHECKED_PRODUCT_READ(1)) dut(.*);
  integer kind=0,bit_index=0,target=37,sent=0,received=0,cycle=0,first=-1,last=-1;
  integer jobs=0,stalls=0,full_stalls=0,burst_last=-1,burst_holes=0,observed_fault=0,gap_edges=0;
  reg score=0,stream=0,stalling=0;
  function [35:0] datum(input integer n,input integer job);
    datum=36'h123456789 ^ (n*37) ^ (job<<20);
  endfunction
  always @(posedge clk) begin
    cycle=cycle+1;
    if(resetn && score) begin
      if(dut.count>3) $fatal(1,"QUEUE_CREDIT_OVERFLOW");
      if(private_take) sent=sent+1;
      if(core_valid && !core_ready) stalls=stalls+1;
      if(raw_valid && !raw_ready) full_stalls=full_stalls+1;
      if(core_take) begin
        if((kind==1 || kind==8) && received>=target) $fatal(1,"UNCHECKED_TOKEN_ESCAPED");
        if(core_data!==datum(received,jobs) || core_position!==received[8:0] ||
           core_last!==(received==511) || core_metadata!==admit_metadata)
          $fatal(1,"CHECKED_TOKEN_DATA_IDENTITY_MISMATCH");
        if(first<0) first=cycle;
        last=cycle;
        if(kind==0 && burst_last>=0 && cycle!=burst_last+1) burst_holes=burst_holes+1;
        burst_last=cycle;
        received=received+1;
      end
      if(released && (!consumer_complete || received!=512 || dut.count!=0 || dut.observed!=0))
        $fatal(1,"EARLY_REUSE_BEFORE_ACTUAL_FINAL_DRAIN");
    end
  end
  task tick; begin @(posedge clk); #0.001; end endtask
  task reset_epoch;
    begin
      @(negedge clk); resetn=0;raw_valid=0;admit_valid=0;core_enable=0;
      core_ready=0;release_valid=0;consumer_complete=0;live_faults=0;score=0;
      repeat(3) tick(); @(negedge clk);resetn=1;tick();
    end
  endtask
  task admission;
    begin
      @(negedge clk);admit_valid=1;admit_lease=jobs[1:0];
      if(!admit_ready) $fatal(1,"ADMISSION_CAPACITY_MISSING");
      tick(); @(negedge clk);admit_valid=0;score=1;
      sent=0;received=0;first=-1;last=-1;burst_last=-1;burst_holes=0;
    end
  endtask
  task drive_word;
    begin
      raw_valid=sent<512;raw_data=datum(sent,jobs);raw_position=sent[8:0];
      raw_last=sent==511;raw_metadata=admit_metadata;raw_lease=admit_lease;
      if((kind==1 || kind==8) && sent==target) raw_metadata[bit_index]=!raw_metadata[bit_index];
      if(kind==2 && sent==target) begin
        case(bit_index)
          0:raw_position=raw_position+1'b1;
          1:raw_last=!raw_last;
          2:raw_lease=raw_lease+1'b1;
          3:raw_metadata=75'bx;
        endcase
      end
    end
  endtask
  initial begin
    if(!$value$plusargs("CASE=%d",kind)) kind=0;
    if(!$value$plusargs("BIT=%d",bit_index)) bit_index=0;
    if(!$value$plusargs("TARGET=%d",target)) target=37;
    reset_epoch();
    repeat(kind==0 ? 8 : 1) begin
      admission();
      begin : run_job
        integer watchdog;
        for(watchdog=0;watchdog<2400;watchdog=watchdog+1) begin
          @(negedge clk);
          drive_word();
          // Deliberately drain the standalone queue before the poisoned word.
          // This is a GOOD-tag property witness, not a realtime FFT service case.
          if(kind==8 && sent==target && gap_edges<6) begin
            raw_valid=0;gap_edges=gap_edges+1;
          end
          if(prefetched) core_enable=1;
          core_ready=core_enable;
          if(kind==3 && sent>=3 && sent<5) begin
            core_enable=0;core_ready=0;
            raw_metadata[bit_index]=!raw_metadata[bit_index];
          end
          if(kind==4 && core_position==511 && core_valid) core_ready=0;
          if(kind==5 && received==37) live_faults=8'b1<<bit_index;
          if(kind==6 && received>20 && received<24) core_ready=(watchdog%7)==0;
          if(kind==7 && dut.observed[1] && dut.taken[1] && sent>10) begin
            force dut.tag1=2'd3;
          end
          tick();
          if(fault_reasons!=0) begin observed_fault=1;disable run_job;end
          if(received==512) disable run_job;
          if(kind==4 && sent==512 && received==511) disable run_job;
        end
      end
      @(negedge clk);raw_valid=0;
      if(kind==1 || kind==2 || kind==3 || kind==5 || kind==7 || kind==8) begin
        if(!observed_fault) $fatal(1,"EXPECTED_CHECKED_READ_FAULT_MISSING");
        if((kind==1 || kind==8) && (!fault_reasons[2] || !fault_token_valid || fault_token_position!==target[8:0]))
          $fatal(1,"METADATA_FAULT_TAG_MISSING");
        if(kind==3 && (!fault_reasons[2] || full_stalls==0)) $fatal(1,"STALLED_OFFER_FAULT_MISSING");
        if(kind==5 && !fault_reasons[bit_index+8]) $fatal(1,"CURRENT_RAW_CAUSE_MISSING");
        if(kind==7 && !fault_reasons[6]) $fatal(1,"STALE_VERDICT_TAG_MISSING");
        repeat(5) tick();
        if(core_valid || released) $fatal(1,"POISON_ESCAPED");
        $display("CHECKED_READ_NEGATIVE_PASS case=%0d bit=%0d target=%0d sent=%0d received=%0d reasons=%h",kind,bit_index,target,sent,received,fault_reasons);
        $finish;
      end
      if(kind==4) begin
        core_ready=0;
        repeat(6) tick();
        if(released || drained || received!=511 || sent!=512) $fatal(1,"FINAL_PREFETCH_IS_NOT_CORE_DRAIN");
        @(negedge clk);core_ready=1;tick();
      end
      if(received!=512 || sent!=512 || fault_reasons!=0) $fatal(1,"HEALTHY_LIFETIME_INCOMPLETE");
      repeat(4) tick();
      if(drained || release_ready) $fatal(1,"MISSING_REAL_GUARD_CERTIFICATE_BYPASSED");
      @(negedge clk);consumer_complete=1;tick();
      if(!drained || !release_ready) $fatal(1,"COMPLETE_REFERENCE_DRAIN_MISSING");
      @(negedge clk);release_lease=admit_lease;release_valid=1;tick();
      @(negedge clk);release_valid=0;consumer_complete=0;score=0;
      if(active || !admit_ready) $fatal(1,"RELEASE_REUSE_MISSING");
      if(kind==0 && (last-first!=511 || burst_holes!=0)) $fatal(1,"THREE_SLOT_THROUGHPUT_FAILED");
      $display("CHECKED_READ_JOB job=%0d sent=%0d received=%0d span=%0d holes=%0d stalls=%0d",jobs,sent,received,last-first,burst_holes,stalls);
      jobs=jobs+1;
    end
    $display("CHECKED_READ_PASS case=%0d jobs=%0d full_stalls=%0d",kind,jobs,full_stalls);
    $finish;
  end
endmodule
