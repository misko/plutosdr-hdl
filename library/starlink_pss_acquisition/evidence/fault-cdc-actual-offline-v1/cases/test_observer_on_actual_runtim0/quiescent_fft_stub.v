module starlink_pss_fft512_bfp18_rt_candidate (
input aclk, aresetn, input [7:0] s_axis_config_tdata, input s_axis_config_tvalid,
output s_axis_config_tready, input [47:0] s_axis_data_tdata, input s_axis_data_tvalid,
output s_axis_data_tready, input s_axis_data_tlast,
output [47:0] m_axis_data_tdata, output [23:0] m_axis_data_tuser,
output m_axis_data_tvalid, m_axis_data_tlast, output [7:0] m_axis_status_tdata,
output m_axis_status_tvalid, event_frame_started, event_tlast_unexpected,
event_tlast_missing, event_data_in_channel_halt);
assign s_axis_config_tready=1; assign s_axis_data_tready=1;
assign m_axis_data_tdata=0; assign m_axis_data_tuser=0; assign m_axis_data_tvalid=0;
assign m_axis_data_tlast=0; assign m_axis_status_tdata=0; assign m_axis_status_tvalid=0;
assign event_frame_started=0; assign event_tlast_unexpected=0;
assign event_tlast_missing=0; assign event_data_in_channel_halt=0;
endmodule
