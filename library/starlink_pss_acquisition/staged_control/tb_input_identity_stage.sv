`timescale 1ns/1ps
module tb_input_identity_stage;
  reg clk=0,resetn=0,abort_epoch=0,input_valid=0,output_ready=0;
  reg [35:0] input_data=0;
  reg [8:0] input_position=0;
  reg input_last=0;
  reg [69:0] input_metadata=0,job_descriptor=0;
  wire input_ready,output_valid,output_last,output_identity_good,idle,fault;
  wire [35:0] output_data;
  wire [8:0] output_position;
  starlink_pss_input_identity_stage dut(.*);
  reg occupied=0;
  reg [35:0] saved_data;
  reg [8:0] saved_position;
  reg saved_last,saved_good;
  integer cycles=0,pushes=0,pops=0,discarded=0,refills=0,holds=0;
  integer b,k,n,before_push,before_pop,negative_identities=0,abort_cases=0;
  reg take_in,take_out;
  reg [31:0] random_state=32'h618aca21;
  localparam [69:0] DESCRIPTOR=70'h23456789abcdef0123;

  // Bit-wise independent oracle: an equal pair of unknowns is never evidence.
  function good_identity(input [69:0] lhs,input [69:0] rhs);
    integer bit_index;
    begin
      good_identity=1;
      for(bit_index=0;bit_index<70;bit_index=bit_index+1)
        if (!((lhs[bit_index]===1'b0 && rhs[bit_index]===1'b0) ||
              (lhs[bit_index]===1'b1 && rhs[bit_index]===1'b1))) good_identity=0;
    end
  endfunction

  task reset_stage;
    begin
      if(occupied)discarded=discarded+1;
      occupied=0;resetn=0;input_valid=0;output_ready=0;abort_epoch=0;
      #1;clk=1;#1;clk=0;#1;
      if(output_valid!==0 || input_ready!==0 || idle!==1 || fault!==0)
        $fatal(1,"reset did not purge/quiesce private stage");
      resetn=1;#1;
    end
  endtask

  task cycle;
    begin
      #1;
      if(fault!==0)$fatal(1,"unexpected fault");
      if(output_valid!==occupied || idle!==!occupied ||
         input_ready!==(!occupied || output_ready))$fatal(1,"occupancy/credit mismatch");
      if(occupied && {output_data,output_position,output_last,output_identity_good} !==
         {saved_data,saved_position,saved_last,saved_good})$fatal(1,"payload/identity mismatch");
      take_in=input_valid && input_ready;take_out=output_valid && output_ready;
      if(occupied && !output_ready)holds=holds+1;
      if(take_in && take_out)refills=refills+1;
      if(take_out)begin occupied=0;pops=pops+1;end
      if(take_in)begin
        occupied=1;pushes=pushes+1;saved_data=input_data;
        saved_position=input_position;saved_last=input_last;
        saved_good=good_identity(input_metadata,job_descriptor);
      end
      #1;clk=1;#1;clk=0;cycles=cycles+1;
      if(pushes-pops-discarded!=(occupied?1:0))$fatal(1,"accepted beat conservation");
      if(output_valid!==occupied)$fatal(1,"post-edge occupancy mismatch");
    end
  endtask

  task fill_one;
    begin
      job_descriptor=DESCRIPTOR;input_metadata=DESCRIPTOR;
      input_data=36'habcde1234;input_position=511;input_last=1;
      input_valid=1;output_ready=0;cycle;input_valid=0;
    end
  endtask

  initial begin
    reset_stage;
    before_push=pushes;before_pop=pops;
    input_valid=1;output_ready=1;job_descriptor=DESCRIPTOR;input_metadata=DESCRIPTOR;
    for(n=0;n<512;n=n+1)begin
      input_data={18'(n^18'h34567),18'(n)};input_position=n;input_last=n==511;cycle;
    end
    if(pushes-before_push!=512 || pops-before_pop!=511 || refills!=511)
      $fatal(1,"continuous 512-beat retire/refill failed");
    // Upstream may ACK its final word now, while the entire final beat remains
    // privately buffered. Change upstream buses/descriptor; held evidence must
    // still describe the accepted final word, not the next bank/job.
    input_valid=0;output_ready=0;
    for(n=0;n<200;n=n+1)begin
      input_data=n;input_metadata=n;job_descriptor=~DESCRIPTOR;
      input_position=0;input_last=0;cycle;
      if(output_position!==511 || output_last!==1 || output_identity_good!==1)
        $fatal(1,"last-word ownership did not remain in private stage");
    end
    output_ready=1;cycle;
    if(pops-before_pop!=512)$fatal(1,"final private word lost");
    $display("INPUT_STAGE_STREAM_PASS words=512 refills=511 final_stall=200");

    for(b=0;b<70;b=b+1)for(k=0;k<5;k=k+1)begin
      job_descriptor=DESCRIPTOR;input_metadata=DESCRIPTOR;
      case(k)
        0:input_metadata[b]=~DESCRIPTOR[b];
        1:input_metadata[b]=1'bx;
        2:input_metadata[b]=1'bz;
        3:begin input_metadata[b]=1'bx;job_descriptor[b]=1'bx;end
        4:begin input_metadata[b]=1'bz;job_descriptor[b]=1'bz;end
      endcase
      input_valid=1;output_ready=1;input_data=b*5+k;input_position=b;input_last=0;cycle;
      if(output_identity_good!==0)$fatal(1,"bad or unknown identity certified");
      negative_identities=negative_identities+1;
    end
    input_valid=0;cycle;
    $display("INPUT_STAGE_IDENTITY_PASS bits=70 cases=%0d unknown_equal_rejected=1",negative_identities);

    for(n=0;n<4096;n=n+1)begin
      random_state=random_state*32'd1664525+32'd1013904223;
      input_valid=random_state[29];output_ready=random_state[17];
      input_data={4'hf,random_state};input_position=random_state[8:0];
      input_last=random_state[21];job_descriptor=DESCRIPTOR;
      input_metadata=random_state[12]?DESCRIPTOR:~DESCRIPTOR;cycle;
    end
    input_valid=0;output_ready=1;cycle;
    $display("INPUT_STAGE_RANDOM_PASS cycles=4096 conservation=1 holds=%0d refills=%0d",holds,refills);

    // Every fail-closed control case starts with an occupied final-word slot.
    for(k=0;k<7;k=k+1)begin
      reset_stage;fill_one;
      case(k)
        0:abort_epoch=1;
        1:abort_epoch=1'bx;
        2:abort_epoch=1'bz;
        3:input_valid=1'bx;
        4:input_valid=1'bz;
        5:output_ready=1'bx;
        6:output_ready=1'bz;
      endcase
      #1;
      if(fault!==1 || input_ready!==0 || output_valid!==0)
        $fatal(1,"current abort/control fault did not veto private handshakes");
      clk=1;#1;clk=0;
      discarded=discarded+1;occupied=0;
      abort_epoch=0;input_valid=0;output_ready=1;#1;
      if(fault!==1 || output_valid!==0 || input_ready!==0 || idle!==1)
        $fatal(1,"quarantine did not persist until reset");
      abort_cases=abort_cases+1;
    end
    reset_stage;fill_one;reset_stage;
    if(output_valid!==0)$fatal(1,"stale final word after reset");
    fill_one;output_ready=1;cycle;
    if(pushes!=pops+discarded || occupied)$fatal(1,"final conservation/recovery failed");
    $display("INPUT_STAGE_PASS cycles=%0d pushes=%0d pops=%0d discarded=%0d abort_cases=%0d no_fft_or_route_claim",
      cycles,pushes,pops,discarded,abort_cases);
    $finish;
  end
  initial begin #1000000;$fatal(1,"bounded stage test timeout");end
endmodule
