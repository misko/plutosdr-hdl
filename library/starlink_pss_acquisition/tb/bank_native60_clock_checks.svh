// Ideal oscillator origin/cadence witnesses, independent of RATE parameters.
// Clocks continue after valid source-off and bank-local teardown.
  integer source_edges=0,fft_edges=0;
  realtime previous_source_edge=0,first_source_edge=0,first_source_fall=0;
  realtime previous_source_rise=0,observed_source_half=0,observed_source_period=0;
  realtime previous_fft_edge=0,first_fft_edge=0,first_fft_fall=0;
  realtime previous_fft_rise=0,observed_fft_half=0,observed_fft_period=0;
  realtime previous_control=0,observed_control=0;
  task automatic close_time(input realtime actual,input realtime expected);
    if(actual<expected-0.000001 || actual>expected+0.000001)
      fail($sformatf("clock/index timing actual_ns=%0.9f expected_ns=%0.9f",actual,expected));
  endtask
  always @(sample_clk) if($realtime>0) begin
    if(previous_source_edge==0) begin
      first_source_edge=$realtime; close_time(first_source_edge,10.433333);
    end else begin
      observed_source_half=$realtime-previous_source_edge;
      close_time(observed_source_half,8.333333);
    end
    previous_source_edge=$realtime;
  end
  always @(posedge sample_clk) begin
    source_edges=source_edges+1;
    if(previous_source_rise!=0) begin
      observed_source_period=$realtime-previous_source_rise;
      close_time(observed_source_period,16.666666);
    end
    previous_source_rise=$realtime;
  end
  always @(negedge sample_clk) if($realtime>0 && first_source_fall==0) begin
    first_source_fall=$realtime; close_time(first_source_fall,18.766666);
  end
  always @(fft_clk) if($realtime>0) begin
    if(previous_fft_edge==0) begin
      first_fft_edge=$realtime; close_time(first_fft_edge,4.157143);
    end else begin
      observed_fft_half=$realtime-previous_fft_edge;
      close_time(observed_fft_half,2.857143);
    end
    previous_fft_edge=$realtime;
  end
  always @(posedge fft_clk) begin
    fft_edges=fft_edges+1;
    if(previous_fft_rise!=0) begin
      observed_fft_period=$realtime-previous_fft_rise;
      close_time(observed_fft_period,5.714286);
    end
    previous_fft_rise=$realtime;
  end
  always @(negedge fft_clk) if($realtime>0 && first_fft_fall==0) begin
    first_fft_fall=$realtime; close_time(first_fft_fall,7.014286);
  end
  always @(posedge clk) begin
    if(previous_control!=0) begin
      observed_control=$realtime-previous_control; close_time(observed_control,10.0);
    end
    previous_control=$realtime;
  end
  task automatic report_clocks;
    $display("NATIVE60_CLOCK first_edge_fs=%0.0f first_fall_fs=%0.0f half_fs=%0.0f period_fs=%0.0f control_period_fs=%0.0f source_edges=%0d after_off_edges=%0d quiet_edges=%0d",
      first_source_edge*1000000.0,first_source_fall*1000000.0,observed_source_half*1000000.0,
      observed_source_period*1000000.0,observed_control*1000000.0,source_edges,source_edges-source_off_edge,quiet_edges);
    $display("HIGH_RATE60_FFT_CLOCK first_edge_fs=%0.0f first_fall_fs=%0.0f half_fs=%0.0f period_fs=%0.0f edges=%0d ideal_clock=1 mmcm_claim=0",
      first_fft_edge*1000000.0,first_fft_fall*1000000.0,observed_fft_half*1000000.0,observed_fft_period*1000000.0,fft_edges);
  endtask
