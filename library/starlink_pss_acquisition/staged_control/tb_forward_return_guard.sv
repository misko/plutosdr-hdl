// Integration contract: real result-guard RTL plus real bank RTL. Raw FFT
// events and product-bank ACK are driven by this fixture, not vendor IP.
`timescale 1ns/1ps
module tb #(parameter integer GUARD_MODE=0);
  reg clk=0,resetn=0,abort_epoch=0,reserve_valid=0,job_valid=0;
  always #5 clk=~clk;
  reg input_beat=0,input_complete=0,frame=0,raw_valid=0,raw_last=0,status_valid=0,fence=1;
  reg [47:0] raw_data=0;
  reg [23:0] raw_user=0;
  reg [7:0] status_data=8'd7;
  reg replay_ready=0,product_owned=0,committed=0,completed_input=0;
  wire bank_reserve_ready,bank_capture_ready,bank_busy,bank_fault,bank_valid,bank_last,bank_done;
  wire [35:0] bank_data;
  wire [8:0] bank_position;
  wire [4:0] bank_exponent;
  wire [69:0] bank_descriptor;
  wire guard_job_ready,guard_busy,guard_fault,guard_commit,guard_await_ack,guard_ack;
  wire [74:0] guard_metadata;
  localparam [69:0] DESCRIPTOR=70'h1a5a5a5a5a5a5a0000;
  wire wait_product=committed || guard_commit;
  // Raw capture capacity drops after word 511, BEFORE the held guard LAST
  // can qualify. Use exclusive ownership here, not bank_capture_ready.
  wire guard_sink_ready=wait_product ? product_owned : (bank_busy && !bank_fault);
  always @(posedge clk or negedge resetn)
    if(!resetn)committed<=0;else if(guard_commit)committed<=1;
  always @(posedge clk or negedge resetn)
    if(!resetn)completed_input<=0;else if(input_complete)completed_input<=1;
  starlink_pss_result_guard_owner_view #(
    .USE_COMPLETED_INPUT_FAULT(GUARD_MODE),.REQUIRE_KNOWN_COMPLETED_INPUT(GUARD_MODE),
    .USE_FORWARD_RETIREMENT(GUARD_MODE)) guard(
    .clk(clk),.resetn(resetn),.job_valid(job_valid),.job_ready(guard_job_ready),
    .private_descriptor_offer(job_valid),.job_descriptor(DESCRIPTOR),
    .input_bank_reserved(1'b1),.output_bank_reserved(bank_busy),
    .certified_input_beat(input_beat),.certified_input_complete(input_complete),
    .offered_input_beat(input_beat),.offered_input_complete(input_complete),
    .final_fence_certified(fence),.external_fault_now(abort_epoch || bank_fault),
    .phase_input_fault_now(1'b0),.completed_input_certified(completed_input),
    .completed_input_fault_now(abort_epoch || bank_fault || input_beat || input_complete),.preflight_fault_evidence_now(1'b0),
    .core_event_frame_started(frame),.core_output_tdata(raw_data),.core_output_tuser(raw_user),
    .core_output_tvalid(raw_valid),.core_output_tlast(raw_last),
    .core_status_tdata(status_data),.core_status_tvalid(status_valid),
    .mailbox_input_ready(guard_sink_ready),.mailbox_input_fault(bank_fault),
    .inverse_phase(1'b0),.forward_mailbox_fault(bank_fault),
    .mailbox_input_metadata(guard_metadata),.busy(guard_busy),.protocol_fault(guard_fault),
    .commit_pulse(guard_commit),.owner_awaiting_ack(guard_await_ack),.owner_ack_accept(guard_ack));
  starlink_pss_forward_return_bank bank(
    .clk(clk),.resetn(resetn),.abort_epoch(abort_epoch || guard_fault),
    .reserve_valid(reserve_valid),.reserve_ready(bank_reserve_ready),.reserve_descriptor(DESCRIPTOR),
    .capture_valid(raw_valid),.capture_ready(bank_capture_ready),
    .capture_data({raw_data[41:24],raw_data[17:0]}),.capture_position(raw_user[8:0]),
    .capture_last(raw_last),.capture_exponent(raw_user[20:16]),.capture_descriptor(guard_metadata[74:5]),
    .seal_valid(guard_commit),.output_valid(bank_valid),.output_ready(replay_ready),
    .output_data(bank_data),.output_position(bank_position),.output_last(bank_last),
    .output_exponent(bank_exponent),.output_descriptor(bank_descriptor),
    .done_pulse(bank_done),.busy(bank_busy),.fault(bank_fault));
  integer popped=0,case_id=0,commits=0,acks=0,cycles=0;
  function automatic [35:0] word(input integer n);word=36'h800000001 ^ (n*32'h12479);endfunction
  always @(posedge clk)begin
    cycles=cycles+1;
    if(resetn)begin
      if(guard_commit)commits=commits+1;
      if(guard_ack)begin
        if(!product_owned)$fatal(1,"guard ACK before actual product ownership");
        acks=acks+1;
      end
      if(bank_valid)begin
        if(!committed && !guard_commit)$fatal(1,"replay before guard qualification");
        if(bank_data!==word(popped) || bank_position!==9'(popped) || bank_last!==(popped==511) ||
           bank_exponent!==5'd7 || bank_descriptor!==DESCRIPTOR)$fatal(1,"guard/bank payload mismatch");
        if(replay_ready)popped=popped+1;
      end
    end
  end
  task automatic step;begin @(posedge clk);#1;@(negedge clk);end endtask
  task automatic clear_epoch;
    begin
      resetn=0;abort_epoch=0;reserve_valid=0;job_valid=0;input_beat=0;input_complete=0;
      frame=0;raw_valid=0;raw_last=0;status_valid=0;fence=1;replay_ready=0;product_owned=0;
      repeat(3)step;resetn=1;step;popped=0;commits=0;acks=0;
    end
  endtask
  task automatic capture_job(input integer mode);
    reg [35:0] value;
    begin
      if(!bank_reserve_ready)$fatal(1,"bank unavailable before job");
      reserve_valid=1;step;reserve_valid=0;
      if(!guard_job_ready)$fatal(1,"owned bank did not admit guard");
      job_valid=1;step;job_valid=0;
      for(integer n=0;n<512;n=n+1)begin
        input_beat=1;input_complete=n==511;frame=n==0;step;
      end
      input_beat=0;input_complete=0;frame=0;
      if(mode==2)fence=0;
      for(integer n=0;n<512;n=n+1)begin
        value=word(n);raw_data={6'b0,value[35:18],6'b0,value[17:0]};
        raw_user={3'b0,5'd7,7'b0,9'(n)};raw_valid=1;raw_last=n==511;
        status_valid=mode!=1 && n==511;step;
      end
      raw_valid=0;raw_last=0;status_valid=0;
      #1;
      if(bank_capture_ready || !guard_sink_ready || !bank_busy)
        $fatal(1,"qualified-final readiness raw=%b sink=%b busy=%b bank_fault=%b guard_fault=%b reasons=%h",bank_capture_ready,guard_sink_ready,bank_busy,bank_fault,guard_fault,guard.fault_reasons);
      if(mode==1 || mode==2)begin
        repeat(17)begin step;if(guard_commit || bank_valid || guard_fault || bank_fault)
          $fatal(1,"late qualification was lost or bypassed");end
        if(mode==1)begin status_valid=1;step;status_valid=0;end
        else fence=1;
      end
    end
  endtask
  task automatic finish_job(input integer hold_product);
    integer timeout;
    begin
      timeout=0;
      while(!committed && timeout<100)begin step;timeout=timeout+1;end
      if(!committed || guard_fault || bank_fault)$fatal(1,"qualified seal was not observed");
      repeat(9)begin step;if(!guard_busy || !guard_await_ack || acks!=0)
        $fatal(1,"guard retired before replay/product completion");end
      timeout=0;replay_ready=1;
      while(!bank_done && timeout<2000)begin
        replay_ready=(timeout%5)!=0;step;timeout=timeout+1;
      end
      replay_ready=0;
      if(!bank_done || popped!=512 || commits!=1 || guard_fault || bank_fault)
        $fatal(1,"guard/bank failed to complete exactly once");
      repeat(hold_product)begin step;if(!guard_busy || acks!=0 || guard_job_ready)
        $fatal(1,"drained bank released guard before product ACK");end
      product_owned=1;step;product_owned=0;step;
      if(guard_busy || acks!=1 || guard_fault || bank_fault)$fatal(1,"actual product ACK not honored");
    end
  endtask
  initial begin
    if(!$value$plusargs("CASE=%d",case_id))case_id=0;
    clear_epoch;capture_job(case_id<3?case_id:0);
    if(case_id==4)begin
      abort_epoch=1;#1;if(bank_valid)$fatal(1,"final-edge fault leaked replay");
      repeat(3)step;
      if(!guard_fault || !bank_fault || bank_valid)$fatal(1,"final fault not quarantined");
      clear_epoch;capture_job(1);
    end
    if(case_id==5)begin
      repeat(8)step;
      if(!bank_valid || !guard_busy)$fatal(1,"held replay reset setup missing");
      clear_epoch;capture_job(2);
    end
    finish_job(case_id==3?64:3);
    $display("FORWARD_RETURN_GUARD_PASS case=%0d reads=512 commits=1 acks=1 late_final_ready=1 product_ack_required=1 mode=%0d cycles=%0d",case_id,GUARD_MODE,cycles);
    $finish;
  end
  initial begin #1000000;$fatal(1,"guard/bank deadline");end
endmodule
