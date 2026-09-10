// OFFLINE ONLY. This is NOT an FFT implementation or vendor timing model.
// It accepts one synthetic frame then returns 512 zero words at a deliberately
// slow, controllable cadence. Only bank/guard ownership is tested with it.
`timescale 1ns/1ps
module starlink_pss_fft512_bfp18_rt_candidate (
  input wire aclk, aresetn,
  input wire [7:0] s_axis_config_tdata,
  input wire s_axis_config_tvalid,
  output wire s_axis_config_tready,
  input wire [47:0] s_axis_data_tdata,
  input wire s_axis_data_tvalid,
  output wire s_axis_data_tready,
  input wire s_axis_data_tlast,
  output reg [47:0] m_axis_data_tdata=0,
  output reg [23:0] m_axis_data_tuser=0,
  output reg m_axis_data_tvalid=0, m_axis_data_tlast=0,
  output reg [7:0] m_axis_status_tdata=0,
  output reg m_axis_status_tvalid=0,
  output reg event_frame_started=0,
  output wire event_tlast_unexpected, event_tlast_missing, event_data_in_channel_halt
);
  localparam integer OFFLINE_NOT_FFT=1;
  reg pause_outputs=0, inject_missing=0, hold_status=0;
  integer input_count=0, output_count=0, cadence=0;
  reg returning=0, configured=0, status_pending=0;
  assign s_axis_config_tready=aresetn;
  assign s_axis_data_tready=aresetn && configured && input_count<512;
  assign event_tlast_missing=inject_missing;
  assign event_tlast_unexpected=1'b0;
  assign event_data_in_channel_halt=1'b0;
  always @(posedge aclk) begin
    if(!aresetn) begin
      input_count<=0; output_count<=0; cadence<=0; returning<=0; configured<=0; status_pending<=0;
      m_axis_data_tdata<=0; m_axis_data_tuser<=0; m_axis_data_tvalid<=0;
      m_axis_data_tlast<=0; m_axis_status_tdata<=0; m_axis_status_tvalid<=0; event_frame_started<=0;
    end else begin
      m_axis_data_tvalid<=0; m_axis_status_tvalid<=0; event_frame_started<=0;
      if(status_pending && !hold_status) begin
        m_axis_status_tvalid<=1; m_axis_status_tdata<=0; status_pending<=0;
      end
      if(s_axis_config_tvalid && s_axis_config_tready) begin
        if(s_axis_config_tdata[7:1] !== 0) $fatal(1,"OFFLINE_CONFIG_RESERVED_BITS");
        configured<=1;
      end
      if(s_axis_data_tvalid && s_axis_data_tready) begin
        if(s_axis_data_tlast !== (input_count==511)) $fatal(1,"OFFLINE_INPUT_FRAMING");
        if(s_axis_data_tdata !== 0) $fatal(1,"OFFLINE_FIXTURE_IS_ZERO_ONLY_NOT_FFT");
        if(input_count==0) event_frame_started<=1;
        input_count<=input_count+1;
        if(input_count==511) begin returning<=1; cadence<=0; end
      end
      if(returning && !pause_outputs) begin
        cadence<=cadence+1;
        if(cadence==7) begin
          cadence<=0; m_axis_data_tvalid<=1; m_axis_data_tlast<=(output_count==511);
          m_axis_data_tuser<={15'b0,9'(output_count)}; m_axis_data_tdata<=0;
          output_count<=output_count+1;
          if(output_count==511) begin
            returning<=0; m_axis_status_tdata<=0;
            if(hold_status) status_pending<=1;
            else m_axis_status_tvalid<=1;
          end
        end
      end
    end
  end
endmodule
