`timescale 1ns/1ps
module tb_input_identity_checker;
  reg clk=0;always #5 clk=~clk;
  reg resetn=0,abort_epoch=0,job_start=0,input_enable=0,core_ready=0;
  reg src_valid=0,src_last=0;
  reg [35:0] src_data=0;
  reg [8:0] src_position=0;
  reg [69:0] src_metadata=0,descriptor=70'h23456789abcdef0123;
  wire src_ready,st_valid,st_last,st_identity,st_fault,st_idle,transport_ready;
  wire [35:0] st_data;
  wire [8:0] st_position;
  wire [47:0] core_data;
  wire core_valid,core_last,certified,complete_beat,input_complete,fault_now,protocol_fault;
  wire [2:0] reasons,events;
  integer source_count=0,delivered=0,healthy_jobs=0,rejected_jobs=0;
  integer k,n,which_error=-1,bad_position=-1;
  reg healthy=1;
  starlink_pss_input_identity_stage stage (
    .clk(clk),.resetn(resetn),.abort_epoch(abort_epoch || protocol_fault),
    .input_valid(src_valid),.input_ready(src_ready),.input_data(src_data),
    .input_position(src_position),.input_last(src_last),.input_metadata(src_metadata),
    .job_descriptor(descriptor),.output_valid(st_valid),.output_ready(transport_ready),
    .output_data(st_data),.output_position(st_position),.output_last(st_last),
    .output_identity_good(st_identity),.idle(st_idle),.fault(st_fault)
  );
  starlink_pss_realtime_input_guard_staged_identity #(.LOCAL_FIRST_ADMISSION(1)) checker_dut (
    .clk(clk),.resetn(resetn),.job_start(job_start),.job_descriptor(descriptor),
    .input_enable(input_enable),.input_valid(st_valid),.input_ready(),
    .input_transport_ready(transport_ready),.input_data(st_data),
    .input_position(st_position),.input_last(st_last),.input_metadata(70'b0),
    .input_identity_good(st_identity),.core_input_tdata(core_data),
    .core_input_tvalid(core_valid),.core_input_tready(core_ready),
    .core_input_tlast(core_last),.certified_input_beat(certified),
    .certified_input_complete(complete_beat),.input_complete(input_complete),
    .fault_now(fault_now),.duplicate_start_fault_now(),.fault_events_now(events),
    .protocol_fault(protocol_fault),.fault_reasons(reasons)
  );
  always @(posedge clk) if(resetn)begin
    if(src_valid && src_ready)source_count=source_count+1;
    if(certified)begin
      if(core_data!=={6'b0,18'(delivered^18'h34567),6'b0,18'(delivered)} ||
         core_last!==(delivered==511))$fatal(1,"buffered checker data/order/TLAST");
      if(complete_beat!==(delivered==511))$fatal(1,"early/late input completion");
      delivered=delivered+1;
    end
    if(healthy && (fault_now || protocol_fault || st_fault))$fatal(1,"healthy job faulted");
    if(healthy && (source_count-delivered<0 || source_count-delivered>1))
      $fatal(1,"pipeline accepted/certified conservation");
  end
  task reset_job;
    begin
      @(negedge clk);resetn=0;src_valid=0;job_start=0;input_enable=0;core_ready=0;abort_epoch=0;
      repeat(3)@(negedge clk);
      source_count=0;delivered=0;healthy=1;which_error=-1;bad_position=-1;
      resetn=1;job_start=1;
      @(negedge clk);job_start=0;input_enable=1;core_ready=1;
    end
  endtask
  task send_words(input integer count);
    integer word_index;
    begin
      for(word_index=0;word_index<count;word_index=word_index+1)begin
        @(negedge clk);
        src_valid=1;src_data={18'(word_index^18'h34567),18'(word_index)};
        src_position=word_index;src_last=word_index==511;src_metadata=descriptor;
        if(word_index==bad_position)case(which_error)
          0:src_metadata[37]=~descriptor[37];
          1:src_metadata[69]=1'bx;
          2:src_position=word_index+1;
          3:src_last=!src_last;
        endcase
        #1;while(!src_ready)begin @(negedge clk);#1;end
        @(posedge clk);#1;
      end
      @(negedge clk);src_valid=0;
    end
  endtask
  task finish_healthy;
    begin
      wait(input_complete===1);repeat(3)@(negedge clk);
      if(source_count!=512 || delivered!=512 || !st_idle || fault_now || protocol_fault)
        $fatal(1,"complete buffered job/release failed");
      healthy_jobs=healthy_jobs+1;
    end
  endtask
  initial begin
    reset_job;send_words(512);finish_healthy;
    // Real-time checker permits core waitstates, not missing demanded samples.
    reset_job;
    fork
      send_words(512);
      begin for(n=0;n<750;n=n+1)begin @(negedge clk);core_ready=(n%7)!=3;end core_ready=1;end
    join
    finish_healthy;
    $display("INPUT_CHECKER_STREAM_PASS jobs=2 words=1024 core_waitstates=1");

    for(k=0;k<8;k=k+1)begin
      reset_job;healthy=0;which_error=k/2;bad_position=(k%2)?511:7;
      send_words(bad_position+1);
      wait(protocol_fault===1);@(negedge clk);
      if(delivered!=bad_position || input_complete || !reasons[1])
        $fatal(1,"bad staged identity/ordinal/TLAST reached certified stream");
      rejected_jobs=rejected_jobs+1;
    end
    reset_job;healthy=0;send_words(3);wait(protocol_fault===1);@(negedge clk);
    if(delivered!=3 || !reasons[0])$fatal(1,"stage hid realtime delivery gap");
    rejected_jobs=rejected_jobs+1;
    $display("INPUT_CHECKER_REJECTION_PASS malformed=8 gap=1 exact_prefix=1");

    // Stop demand after upstream accepts LAST but before FFT consumes it.
    reset_job;
    fork
      send_words(512);
      begin wait(source_count==512);@(negedge clk);core_ready=0;end
    join
    if(delivered!=511 || input_complete || !st_valid || st_position!=511)
      $fatal(1,"no retained final beat before FFT completion");
    repeat(100)@(negedge clk);
    if(delivered!=511 || input_complete)$fatal(1,"stalled final beat certified early");
    reset_job;
    if(st_valid || input_complete)$fatal(1,"stale staged word after shared reset");
    send_words(512);finish_healthy;
    $display("INPUT_CHECKER_PASS healthy_jobs=%0d rejected_jobs=%0d final_reset=1 no_actual_fft_or_route_claim",healthy_jobs,rejected_jobs);
    $finish;
  end
  initial begin #1000000;$fatal(1,"bounded staged checker timeout");end
endmodule
