// Test-only exact original L1 clock model. Not measured hardware cadence.
`timescale 1ns/1fs
module retained_clock_witness #(parameter real SLOW_PHASE=1.3)(
  input wire fast_clk,slow_clk,slow_clock_enabled
);
  time previous_fast=0,previous_slow=0,stamp;
  integer fast_edges=0,slow_edges=0,pauses=0,last_enabled_pauses=0;
  always @(negedge slow_clock_enabled)pauses=pauses+1;
  always @(posedge fast_clk or negedge fast_clk)if($realtime>0)begin
    stamp=time'($realtime*1000000.0);
    if(fast_edges==0)begin
      if(stamp!=2857143||fast_clk!==1)$fatal(1,"original175 first edge");
    end else if(stamp-previous_fast!=2857143)$fatal(1,"original175 half period");
    previous_fast=stamp;fast_edges=fast_edges+1;
  end
  always @(posedge slow_clk or negedge slow_clk)if($realtime>0)begin
    stamp=time'($realtime*1000000.0);
    if(slow_edges==0)begin
      if(stamp!=time'((SLOW_PHASE+5.0)*1000000.0)||slow_clk!==1)$fatal(1,"original100 first edge");
    end else begin
      if((stamp-time'(SLOW_PHASE*1000000.0))%5000000!=0)$fatal(1,"original100 edge grid");
      if(stamp-previous_slow!=5000000&&pauses<=last_enabled_pauses)$fatal(1,"original100 unpaused half period");
    end
    if(slow_clock_enabled===1)last_enabled_pauses=pauses;
    else if(slow_clock_enabled!==0)$fatal(1,"unknown slow clock gate");
    previous_slow=stamp;slow_edges=slow_edges+1;
  end
  final begin
    if(fast_edges<2||slow_edges<2)$fatal(1,"missing clock observations");
    $display("OFFLINE_CLOCK fast_half_fs=2857143 slow_half_fs=5000000 fast_edges=%0d slow_edges=%0d pauses=%0d",fast_edges,slow_edges,pauses);
  end
endmodule
