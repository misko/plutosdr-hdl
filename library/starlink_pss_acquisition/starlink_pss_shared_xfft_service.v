// SPDX-License-Identifier: GPL-2.0
// Experimental ONE-core 512-point BFP18 transform service. Slow-domain input
// metadata is {inverse, block_start[63:0], forward_exponent[4:0]}; output adds
// the measured transform exponent in bits [4:0]. The frozen XFFT arithmetic
// is unchanged. Complete-block RAM ownership crosses clocks in each direction.
// Selected only by the opt-in paired-receiver build; not hardware-qualified.
`timescale 1ns/1ps
module starlink_pss_shared_xfft_service (
  input wire clk,
  input wire resetn,
  input wire fft_clk,
  input wire fft_resetn,
  input wire input_valid,
  output wire input_ready,
  input wire [35:0] input_data,
  input wire [8:0] input_position,
  input wire input_last,
  input wire [69:0] input_metadata,
  output wire output_valid,
  input wire output_ready,
  output wire [35:0] output_data,
  output wire [8:0] output_position,
  output wire output_last,
  output wire [74:0] output_metadata,
  output wire service_fault
);
  (* ASYNC_REG = "TRUE" *) reg [1:0] slow_reset_fast_sync;
  (* ASYNC_REG = "TRUE" *) reg [1:0] fast_reset_fast_sync;
  always @(posedge fft_clk or negedge resetn)
    if (!resetn) slow_reset_fast_sync <= 0;
    else slow_reset_fast_sync <= {slow_reset_fast_sync[0], 1'b1};
  always @(posedge fft_clk or negedge fft_resetn)
    if (!fft_resetn) fast_reset_fast_sync <= 0;
    else fast_reset_fast_sync <= {fast_reset_fast_sync[0], 1'b1};
  wire fast_running = slow_reset_fast_sync[1] && fast_reset_fast_sync[1];
  (* ASYNC_REG = "TRUE" *) reg [1:0] slow_reset_slow_sync;
  (* ASYNC_REG = "TRUE" *) reg [1:0] fast_reset_slow_sync;
  always @(posedge clk or negedge resetn)
    if (!resetn) slow_reset_slow_sync <= 0;
    else slow_reset_slow_sync <= {slow_reset_slow_sync[0], 1'b1};
  always @(posedge clk or negedge fft_resetn)
    if (!fft_resetn) fast_reset_slow_sync <= 0;
    else fast_reset_slow_sync <= {fast_reset_slow_sync[0], 1'b1};
  wire slow_running = slow_reset_slow_sync[1] && fast_reset_slow_sync[1];

  wire input_mailbox_ready, input_mailbox_fault;
  wire fast_input_valid, fast_input_ready, fast_input_last;
  wire [35:0] fast_input_data;
  wire [8:0] fast_input_position;
  wire [69:0] fast_input_metadata;
  // The controller and BOTH mailboxes use one coherent release pair. Each
  // includes both raw epochs, rather than independently resynchronizing the
  // same launch reset into three physically distinct release chains.
  starlink_pss_block_mailbox #(.RESET_RELEASE_EXTERNAL(1)) input_mailbox (
    .input_clk(clk), .input_resetn(slow_running),
    .input_valid(input_valid && !service_fault), .input_ready(input_mailbox_ready),
    .input_data(input_data), .input_position(input_position), .input_last(input_last),
    .input_metadata(input_metadata), .input_fault(input_mailbox_fault),
    .output_clk(fft_clk), .output_resetn(fast_running),
    .output_valid(fast_input_valid), .output_ready(fast_input_ready),
    .output_data(fast_input_data), .output_position(fast_input_position),
    .output_last(fast_input_last), .output_metadata(fast_input_metadata)
  );

  reg engine_active;
  reg engine_input_closed;
  reg [69:0] engine_metadata;
  reg fast_fault;
  (* ASYNC_REG = "TRUE" *) reg [1:0] fast_fault_sync;
  always @(posedge clk)
    if (!slow_running) fast_fault_sync <= 0;
    else fast_fault_sync <= {fast_fault_sync[0], fast_fault};
  assign service_fault = input_mailbox_fault || fast_fault_sync[1];
  assign input_ready = slow_running && input_mailbox_ready && !service_fault;

  wire adapter_input_ready, adapter_fault;
  wire fast_output_valid, fast_output_last, output_mailbox_ready, output_mailbox_fault;
  wire [17:0] fast_output_i, fast_output_q;
  wire [8:0] fast_output_position;
  wire [4:0] fast_output_exponent;
  wire slow_output_valid;
  assign fast_input_ready = engine_active && !engine_input_closed && !fast_fault && adapter_input_ready;
  assign output_valid = slow_running && slow_output_valid && !service_fault;

  starlink_pss_block_mailbox #(
    .METADATA_WIDTH(75), .RESET_RELEASE_EXTERNAL(1)
  ) output_mailbox (
    .input_clk(fft_clk), .input_resetn(fast_running),
    .input_valid(fast_output_valid && !fast_fault), .input_ready(output_mailbox_ready),
    .input_data({fast_output_q, fast_output_i}), .input_position(fast_output_position),
    .input_last(fast_output_last), .input_metadata({engine_metadata, fast_output_exponent}),
    .input_fault(output_mailbox_fault), .output_clk(clk), .output_resetn(slow_running),
    .output_valid(slow_output_valid), .output_ready(output_ready && !service_fault),
    .output_data(output_data), .output_position(output_position),
    .output_last(output_last), .output_metadata(output_metadata)
  );
  // Start only with both a committed input block and exclusive output storage.
  // The next input block may be prefetched while the current FFT computes, but
  // cannot enter the adapter until this complete job has finished and reset.
  always @(posedge fft_clk) begin
    if (!fast_running) begin
      engine_active <= 0;
      engine_input_closed <= 0;
      fast_fault <= 0;
    end else if (adapter_fault || output_mailbox_fault ||
                 (fast_output_valid && !output_mailbox_ready)) begin
      engine_active <= 0;
      fast_fault <= 1;
    end else if (!engine_active && !fast_fault && fast_input_valid && output_mailbox_ready) begin
      engine_active <= 1;
      engine_input_closed <= 0;
      engine_metadata <= fast_input_metadata;
    end else if (engine_active) begin
      if (fast_input_valid && fast_input_ready && fast_input_last) engine_input_closed <= 1;
      if (fast_output_valid && fast_output_last) engine_active <= 0;
    end
  end

  wire core_aresetn;
  wire [7:0] unused_fixed_config;
  wire config_valid, config_ready, core_input_valid, core_input_ready, core_input_last;
  wire core_output_valid, core_output_ready, core_output_last;
  wire [47:0] core_input_data, core_output_data;
  wire [23:0] core_output_user;
  wire [7:0] core_status_data;
  wire core_status_valid, core_status_ready;
  wire event_frame, event_last_unexpected, event_last_missing;
  wire event_status_halt, event_input_halt, event_output_halt;
  starlink_pss_xfft_block_adapter #(
    .DATA_WIDTH(18), .FORWARD_TRANSFORM(1), .CHECK_INPUT_BLOCK_IDENTITY(0)
  ) adapter (
    .clk(fft_clk), .resetn(fast_running && engine_active), .flush(1'b0),
    .input_valid(fast_input_valid && engine_active && !engine_input_closed && !fast_fault),
    .input_ready(adapter_input_ready), .input_i(fast_input_data[17:0]),
    .input_q(fast_input_data[35:18]), .input_position(fast_input_position),
    .input_block_start_index(engine_metadata[68:5]), .input_last(fast_input_last),
    .output_valid(fast_output_valid), .output_ready(1'b1),
    .output_i(fast_output_i), .output_q(fast_output_q), .output_position(fast_output_position),
    .output_block_exponent(fast_output_exponent), .output_block_start_index(),
    .output_last(fast_output_last), .core_aresetn(core_aresetn),
    .core_config_tdata(unused_fixed_config), .core_config_tvalid(config_valid),
    .core_config_tready(config_ready), .core_input_tdata(core_input_data),
    .core_input_tvalid(core_input_valid), .core_input_tready(core_input_ready),
    .core_input_tlast(core_input_last), .core_output_tdata(core_output_data),
    .core_output_tuser(core_output_user), .core_output_tvalid(core_output_valid),
    .core_output_tready(core_output_ready), .core_output_tlast(core_output_last),
    .core_status_tdata(core_status_data), .core_status_tvalid(core_status_valid),
    .core_status_tready(core_status_ready), .core_event_frame_started(event_frame),
    .core_event_tlast_unexpected(event_last_unexpected), .core_event_tlast_missing(event_last_missing),
    .core_event_status_channel_halt(event_status_halt), .core_event_data_in_channel_halt(event_input_halt),
    .core_event_data_out_channel_halt(event_output_halt), .protocol_fault(adapter_fault)
  );
  // Each job resets/reconfigures the same core. The runtime direction is held
  // before adapter reset release and replaces ONLY the config direction bit.
  starlink_pss_fft512_bfp18 shared_xfft (
    .aclk(fft_clk), .aresetn(core_aresetn),
    .s_axis_config_tdata({7'b0, !engine_metadata[69]}),
    .s_axis_config_tvalid(config_valid), .s_axis_config_tready(config_ready),
    .s_axis_data_tdata(core_input_data), .s_axis_data_tvalid(core_input_valid),
    .s_axis_data_tready(core_input_ready), .s_axis_data_tlast(core_input_last),
    .m_axis_data_tdata(core_output_data), .m_axis_data_tuser(core_output_user),
    .m_axis_data_tvalid(core_output_valid), .m_axis_data_tready(core_output_ready),
    .m_axis_data_tlast(core_output_last), .m_axis_status_tdata(core_status_data),
    .m_axis_status_tvalid(core_status_valid), .m_axis_status_tready(core_status_ready),
    .event_frame_started(event_frame), .event_tlast_unexpected(event_last_unexpected),
    .event_tlast_missing(event_last_missing), .event_status_channel_halt(event_status_halt),
    .event_data_in_channel_halt(event_input_halt), .event_data_out_channel_halt(event_output_halt)
  );
endmodule
