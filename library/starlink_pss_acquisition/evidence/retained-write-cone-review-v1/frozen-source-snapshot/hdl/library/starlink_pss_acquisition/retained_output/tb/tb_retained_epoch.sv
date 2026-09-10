// Actual mailbox reset state, paused slow clock, no hierarchy writes.
`timescale 1ns/1fs
module tb;
  parameter integer SIDE=0;
  parameter real PHASE=1.3;
  reg slow_clk=0,fast_clk=0,run_slow=1,resetn=0,fft_resetn=0;
  always #2.857143 fast_clk=~fast_clk;
  initial begin #(PHASE);forever begin #5;if(run_slow)slow_clk=~slow_clk;end end
  retained_clock_witness #(.SLOW_PHASE(PHASE)) clocks(.fast_clk(fast_clk),.slow_clk(slow_clk),.slow_clock_enabled(run_slow));
  reg[1:0]sf=0,ff=0,ss=0,fs=0;
  always @(posedge fast_clk or negedge resetn)if(!resetn)sf<=0;else sf<={sf[0],1'b1};
  always @(posedge fast_clk or negedge fft_resetn)if(!fft_resetn)ff<=0;else ff<={ff[0],1'b1};
  always @(posedge slow_clk or negedge resetn)if(!resetn)ss<=0;else ss<={ss[0],1'b1};
  always @(posedge slow_clk or negedge fft_resetn)if(!fft_resetn)fs<=0;else fs<={fs[0],1'b1};
  wire outer_fast_running=sf[1]&&ff[1],outer_slow_running=ss[1]&&fs[1];
  wire slow_running,fast_running,writer_idle,reader_idle;
  starlink_pss_retained_epoch_barrier barrier(.*,
    .slow_mailboxes_reset_idle(writer_idle),.fast_mailboxes_reset_idle(reader_idle));
  reg input_valid=0,input_last=0;reg[35:0]input_data=0;reg[8:0]input_position=0;
  reg[69:0]input_metadata=0;wire input_ready,input_fault,input_framing_fault_now;
  reg output_ready=0;wire output_valid,output_last;wire[35:0]output_data;
  wire[8:0]output_position;wire[69:0]output_metadata;wire owner_request,owner_ack_sync;
  starlink_pss_mailbox_owner_view #(.RESET_RELEASE_EXTERNAL(1)) bank(
    .input_clk(slow_clk),.input_resetn(slow_running),.output_clk(fast_clk),.output_resetn(fast_running),
    .input_commit_authorized(1'b0),.writer_reset_idle(writer_idle),.reader_reset_idle(reader_idle),.*);
  integer epoch,k,accepted=0,slow_edges=0,resume_edge;
  always @(posedge slow_clk)slow_edges=slow_edges+1;
  always @(posedge fast_clk)if(fast_running&&output_valid&&output_ready)begin
    if(output_position!==9'(accepted)||output_data!==36'(20000+accepted)||
      output_metadata!==70'd2||output_last!==(accepted==511))$fatal(1,"fresh epoch payload/identity");
    accepted=accepted+1;
  end
  initial begin
    repeat(5)@(negedge fast_clk);resetn=1;fft_resetn=1;
    for(epoch=1;epoch<=2;epoch=epoch+1)begin
      wait(slow_running&&fast_running);
      for(k=0;k<512;k=k+1)begin
        @(negedge slow_clk);input_valid=1;input_data=epoch*10000+k;input_position=9'(k);
        input_last=k==511;input_metadata=epoch;
        do @(posedge slow_clk);while(input_ready!==1);
      end
      @(negedge slow_clk);input_valid=0;
      wait(output_valid);
      if(epoch==1)begin
        // Old full source remains unconsumed. Stop slow low, reset either side.
        @(negedge slow_clk);run_slow=0;
        @(negedge fast_clk);if(SIDE==0)resetn=0;else fft_resetn=0;
        #0.001;if(fast_running!==0||slow_running!==0)$fatal(1,"raw closure not immediate");
        repeat(4)@(negedge fast_clk);resetn=1;fft_resetn=1;
        repeat(20)begin @(negedge fast_clk);if(fast_running!==0||slow_running!==0)$fatal(1,"stale purge ACK rearmed while paused");end
        resume_edge=slow_edges;run_slow=1;
        wait(fast_running);
        if(slow_edges-resume_edge<4||output_valid!==0||bank.request_toggle!==0||input_fault!==0)
          $fatal(1,"fresh purge barrier or stale source");
      end else begin output_ready=1;wait(accepted==512);end
    end
    repeat(6)@(negedge fast_clk);
    if(input_fault!==0||owner_request!==owner_ack_sync)$fatal(1,"fresh final ACK");
    $display("OFFLINE_PASS paused slow reset side=%0d fresh_source_words=%0d",SIDE,accepted);$finish;
  end
  initial begin #100000;$fatal(1,"epoch barrier timeout");end
endmodule
