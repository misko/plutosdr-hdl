// OFFLINE_NOT_FFT: fixed accepted vectors and scripted protocol timing only.
// This is not an FFT computation, vendor model, or proof of reset flushing.
`timescale 1ns/1ps
module starlink_pss_fft512_bfp18_rt_candidate (
  input wire aclk,aresetn,
  input wire[7:0]s_axis_config_tdata,input wire s_axis_config_tvalid,
  output wire s_axis_config_tready,
  input wire[47:0]s_axis_data_tdata,input wire s_axis_data_tvalid,
  output wire s_axis_data_tready,input wire s_axis_data_tlast,
  output wire[47:0]m_axis_data_tdata,output wire[23:0]m_axis_data_tuser,
  output wire m_axis_data_tvalid,m_axis_data_tlast,
  output wire[7:0]m_axis_status_tdata,output wire m_axis_status_tvalid,
  output wire event_frame_started,event_tlast_unexpected,event_tlast_missing,event_data_in_channel_halt
);
  reg[35:0]forwards[0:1535],inverses[0:1535],products[0:1535];
  reg[31:0]samples[0:1405];reg[4:0]fe[0:2],ie[0:2];
  reg configured=0,inverse=0,gap_done=0;
  integer age=0,input_count=0,fixture=0,forward_configs=0,config_count=0;
  initial begin
    $readmemh("forward_q17.mem",forwards);$readmemh("inverse_q17.mem",inverses);
    $readmemh("product_q17.mem",products);$readmemh("samples_ci16.mem",samples);
    $readmemh("forward_exponents.mem",fe);$readmemh("inverse_exponents.mem",ie);
  end
  assign s_axis_config_tready=aresetn&&!configured;
  assign s_axis_data_tready=aresetn&&configured&&input_count<512&&!(input_count==1&&!gap_done);
  wire[8:0]ordinal=9'(age-1294);
  wire[35:0]word_out=inverse?inverses[fixture*512+ordinal]:forwards[fixture*512+ordinal];
  wire[4:0]exponent=inverse?ie[fixture]:fe[fixture];
  wire base_raw_valid=aresetn&&configured&&age>=1294&&age<=1805;
  wire extra_frame,extra_output,extra_status,extra_vendor;
  // Explicit test producer outputs; no DUT state/ownership is forced.
`ifdef RETAINED_FAULT_STIMULUS
  assign extra_frame=tb.inject_frame;assign extra_output=tb.inject_output;
  assign extra_status=tb.inject_status;assign extra_vendor=tb.inject_vendor;
`else
  assign extra_frame=0;assign extra_output=0;assign extra_status=0;assign extra_vendor=0;
`endif
  assign m_axis_data_tvalid=extra_output===1'b0 ? base_raw_valid : extra_output;
  assign m_axis_data_tlast=ordinal==511;
  assign m_axis_data_tdata={6'b0,word_out[35:18],6'b0,word_out[17:0]};
  assign m_axis_data_tuser={3'b0,exponent,7'b0,ordinal};
  assign m_axis_status_tvalid=extra_status===1'b0 ? (base_raw_valid&&ordinal==2) : extra_status;
  assign m_axis_status_tdata={3'b0,exponent};
  assign event_frame_started=extra_frame===1'b0 ?
    (s_axis_data_tvalid&&s_axis_data_tready&&input_count==0) : extra_frame;
  assign event_tlast_unexpected=0;assign event_tlast_missing=extra_vendor;assign event_data_in_channel_halt=0;
  reg[35:0]expected;
  always @(posedge aclk)begin
    if(!aresetn)begin configured<=0;age<=0;input_count<=0;gap_done<=0;end
    else begin
      if(s_axis_config_tvalid&&s_axis_config_tready)begin
        if(s_axis_config_tdata!==8'h01&&s_axis_config_tdata!==8'h00)$fatal(1,"script config packing");
        configured<=1;inverse<=!s_axis_config_tdata[0];age<=0;config_count=config_count+1;
        if(s_axis_config_tdata[0])begin fixture<=forward_configs%3;forward_configs=forward_configs+1;end
      end else if(configured)age<=age+1;
      if(configured&&input_count==1&&!gap_done)gap_done<=1;
      if(s_axis_data_tvalid&&s_axis_data_tready)begin
        expected=inverse?products[fixture*512+input_count]:
          {samples[fixture*447+input_count][31:16],2'b0,samples[fixture*447+input_count][15:0],2'b0};
        if(s_axis_data_tdata!=={6'b0,expected[35:18],6'b0,expected[17:0]}||
            s_axis_data_tlast!==(input_count==511))
          $fatal(1,"OFFLINE_NOT_FFT input mismatch phase=%0d fixture=%0d ordinal=%0d actual=%h expected=%h",inverse,fixture,input_count,s_axis_data_tdata,expected);
        input_count<=input_count+1;
      end
      if(base_raw_valid&&input_count!=512)$fatal(1,"script output before all inputs");
    end
  end
endmodule
