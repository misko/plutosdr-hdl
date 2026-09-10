// OFFLINE CONTROL ACTOR, NOT an FFT/BFP numeric implementation or vendor model.
// Records512 real accepted inputs then emits the same payloads after8 clocks.
// Config, realtime demand, event, exponent/status and output timing are explicit.
`timescale 1ns/1ps
module starlink_pss_fft512_bfp18_rt_candidate (
  input wire aclk,aresetn,
  input wire [7:0] s_axis_config_tdata,
  input wire s_axis_config_tvalid,
  output wire s_axis_config_tready,
  input wire [47:0] s_axis_data_tdata,
  input wire s_axis_data_tvalid,
  output wire s_axis_data_tready,
  input wire s_axis_data_tlast,
  output reg [47:0] m_axis_data_tdata=0,
  output reg [23:0] m_axis_data_tuser=0,
  output reg m_axis_data_tvalid=0,m_axis_data_tlast=0,
  output reg [7:0] m_axis_status_tdata=0,
  output reg m_axis_status_tvalid=0,event_frame_started=0,
  output reg event_tlast_unexpected=0,event_tlast_missing=0,event_data_in_channel_halt=0
);
  reg configured=0;
  reg [9:0] inputs=0,outputs=0;
  reg [3:0] delay_count=0;
  reg [47:0] words[0:511];
  assign s_axis_config_tready=aresetn && !configured;
  assign s_axis_data_tready=aresetn && configured && inputs<512;
  always @(posedge aclk)begin
    if(!aresetn)begin
      configured<=0;inputs<=0;outputs<=0;delay_count<=0;
      m_axis_data_tvalid<=0;m_axis_data_tlast<=0;m_axis_status_tvalid<=0;
      m_axis_data_tdata<=0;m_axis_data_tuser<=0;m_axis_status_tdata<=0;
      event_frame_started<=0;event_tlast_unexpected<=0;event_tlast_missing<=0;
      event_data_in_channel_halt<=0;
    end else begin
      m_axis_data_tvalid<=0;m_axis_status_tvalid<=0;event_frame_started<=0;
      if(s_axis_config_tvalid && s_axis_config_tready)configured<=1;
      if(s_axis_data_tready && s_axis_data_tvalid)begin
        words[inputs]<=s_axis_data_tdata;
        event_frame_started<=inputs==0;
        if(s_axis_data_tlast && inputs!=511)event_tlast_unexpected<=1;
        if(!s_axis_data_tlast && inputs==511)event_tlast_missing<=1;
        inputs<=inputs+1'b1;
      end
      if(s_axis_data_tready && inputs!=0 && !s_axis_data_tvalid)event_data_in_channel_halt<=1;
      if(inputs==512 && delay_count!=8)delay_count<=delay_count+1'b1;
      if(inputs==512 && delay_count==8 && outputs<512)begin
        m_axis_data_tdata<=words[outputs];m_axis_data_tuser<={15'b0,outputs[8:0]};
        m_axis_data_tvalid<=1;m_axis_data_tlast<=outputs==511;
        m_axis_status_tvalid<=outputs==2;m_axis_status_tdata<=0;outputs<=outputs+1'b1;
      end
    end
  end
endmodule
