// SPDX-License-Identifier: GPL-2.0
// ISOLATED SYNTHESIZABLE CANDIDATE. No production instantiation/default change.
// One 512-point complex BFP18 realtime FFT, two persistent block mailboxes,
// separately checked input delivery and private-before-commit output storage.
// Metadata/layout/arithmetic match the nonrealtime service. Physical timing,
// sustained acquisition capacity and top-level receiver qualification remain open.
`timescale 1ns/1ps
module starlink_pss_shared_realtime_xfft_service (
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
  // Same coherent common-epoch release topology as the existing service.
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
  // Source-domain sticky faults cross as levels; never OR an asynchronous slow
  // fault directly into a fast same-cycle publication cone. A malformed input
  // mailbox block cannot publish its ownership toggle in the first place.
  (* ASYNC_REG = "TRUE" *) reg [1:0] input_fault_fast_sync;
  always @(posedge fft_clk)
    if (!fast_running) input_fault_fast_sync <= 0;
    else input_fault_fast_sync <= {input_fault_fast_sync[0], input_mailbox_fault};
  reg fast_fault;
  (* ASYNC_REG = "TRUE" *) reg [1:0] fast_fault_sync;
  always @(posedge clk)
    if (!slow_running) fast_fault_sync <= 0;
    else fast_fault_sync <= {fast_fault_sync[0], fast_fault};
  assign service_fault = input_mailbox_fault || fast_fault_sync[1];
  assign input_ready = slow_running && input_mailbox_ready && !service_fault;

  localparam [3:0] RESET0 = 0, RESET1 = 1, WAIT_BANK = 2, INPUT_ADMIT = 3,
    CONFIGURE = 4, ENABLE_INPUT = 5, RUN_JOB = 6, ACK_DRAIN = 7, QUARANTINE = 8;
  reg [3:0] state;
  reg core_release, input_job_start;
  reg [69:0] engine_metadata;
  reg engine_input_reserved, engine_output_reserved;
  wire job_ready, result_busy, result_commit, result_fault;
  wire job_valid = state == WAIT_BANK && fast_input_valid && !fast_fault;
  wire job_accept = job_valid && job_ready;
  wire core_aresetn = fast_running && core_release;
  wire config_valid = state == CONFIGURE && core_aresetn && !fast_fault;
  wire config_ready;
  wire engine_input_enable = state == RUN_JOB && core_aresetn && !fast_fault;
  wire checker_ready, input_transport_ready, checked_input_complete;
  wire certified_input_beat, certified_input_complete, input_fault_now, input_guard_fault;
  wire [47:0] core_input_data, core_output_data;
  wire core_input_valid, core_input_ready, core_input_last;
  wire core_output_valid, core_output_last;
  wire [23:0] core_output_user;
  wire [7:0] core_status_data;
  wire core_status_valid, event_frame, event_last_unexpected, event_last_missing, event_input_halt;
  // Explicitly metadata-independent mailbox retirement; all validation remains
  // in the checker, including malformed presented input while core READY is low.
  assign fast_input_ready = input_transport_ready && engine_input_enable;
  // As in the original shared adapter, the REAL committed mailbox has already
  // checked every word's block identity and holds one immutable descriptor.
  // Keep its checks unchanged; avoid a redundant 70-bit checker identity copy.
  // The checker still validates each delivered ordinal/TLAST and active demand.
  starlink_pss_realtime_input_guard #(.CHECK_INPUT_BLOCK_IDENTITY(0)) input_guard (
    .clk(fft_clk), .resetn(core_aresetn), .job_start(input_job_start),
    .job_descriptor(engine_metadata), .input_enable(engine_input_enable),
    .input_valid(fast_input_valid), .input_ready(checker_ready),
    .input_transport_ready(input_transport_ready), .input_data(fast_input_data),
    .input_position(fast_input_position), .input_last(fast_input_last),
    .input_metadata(fast_input_metadata), .core_input_tdata(core_input_data),
    .core_input_tvalid(core_input_valid), .core_input_tready(core_input_ready),
    .core_input_tlast(core_input_last), .certified_input_beat(certified_input_beat),
    .certified_input_complete(certified_input_complete), .input_complete(checked_input_complete),
    .fault_now(input_fault_now), .protocol_fault(input_guard_fault), .fault_reasons()
  );

  wire output_mailbox_ready, output_mailbox_fault, output_mailbox_framing_fault_now;
  wire return_valid, return_private_valid, return_last;
  wire [35:0] return_data;
  wire [8:0] return_position;
  wire [74:0] return_metadata;
  wire vendor_fault_now = event_last_unexpected || event_last_missing || event_input_halt;
  wire external_fault_now = input_fault_now || input_guard_fault ||
    input_fault_fast_sync[1] || vendor_fault_now || fast_fault;
  // Cause coverage, NOT a guessed vendor-event latency fence: the input checker
  // has certified all 512 correctly framed/identified actual deliveries and
  // locally faults a missing active demand immediately. These checks exclude
  // the documented starvation/TLAST causes before their delayed reports.
  // The result guard independently requires 512 checked outputs, exactly one
  // frame and matching independent status. Raw vendor faults remain direct
  // commit vetoes AND sticky observations through compute, output and ACK drain.
  // This reasoning and its integration still require independent qualification.
  wire final_fence = checked_input_complete && !input_guard_fault && !input_fault_now;
  starlink_pss_realtime_result_guard result_guard (
    .clk(fft_clk), .resetn(fast_running), .job_valid(job_valid), .job_ready(job_ready),
    .job_descriptor(fast_input_metadata),
    .input_bank_reserved(state == WAIT_BANK ? fast_input_valid : engine_input_reserved),
    .output_bank_reserved(state == WAIT_BANK ? output_mailbox_ready : engine_output_reserved),
    .certified_input_beat(certified_input_beat),
    .certified_input_complete(certified_input_complete), .final_fence_certified(final_fence),
    .external_fault_now(external_fault_now), .core_event_frame_started(event_frame),
    .core_output_tdata(core_output_data), .core_output_tuser(core_output_user),
    .core_output_tvalid(core_output_valid), .core_output_tlast(core_output_last),
    .core_status_tdata(core_status_data), .core_status_tvalid(core_status_valid),
    .mailbox_input_valid(return_valid), .mailbox_private_valid(return_private_valid),
    .mailbox_input_ready(output_mailbox_ready),
    .mailbox_input_fault(output_mailbox_fault || output_mailbox_framing_fault_now),
    .mailbox_input_data(return_data),
    .mailbox_input_position(return_position), .mailbox_input_last(return_last),
    .mailbox_input_metadata(return_metadata), .busy(result_busy),
    .commit_pulse(result_commit), .protocol_fault(result_fault), .fault_reasons()
  );
  wire slow_output_valid;
  assign output_valid = slow_running && slow_output_valid && !service_fault;
  // Only private bank writes bypass the current-cycle validation cone. Final
  // authorization and guard retirement retain the exact same qualified valid.
  starlink_pss_block_mailbox #(.METADATA_WIDTH(75), .RESET_RELEASE_EXTERNAL(1),
    .EXPLICIT_COMMIT(1)) output_mailbox (
    .input_clk(fft_clk), .input_resetn(fast_running), .input_valid(return_private_valid),
    .input_commit_authorized(return_valid),
    .input_ready(output_mailbox_ready), .input_data(return_data),
    .input_position(return_position), .input_last(return_last),
    .input_metadata(return_metadata), .input_fault(output_mailbox_fault),
    .input_framing_fault_now(output_mailbox_framing_fault_now),
    .output_clk(clk), .output_resetn(slow_running), .output_valid(slow_output_valid),
    .output_ready(output_ready && !service_fault), .output_data(output_data),
    .output_position(output_position), .output_last(output_last), .output_metadata(output_metadata)
  );

  wire any_fast_fault = external_fault_now || result_fault || output_mailbox_fault;
  always @(posedge fft_clk)
    if (!fast_running) fast_fault <= 0;
    else if (any_fast_fault) fast_fault <= 1;
  always @(posedge fft_clk) begin
    if (!fast_running) begin
      state <= RESET0;
      core_release <= 0;
      input_job_start <= 0;
      engine_metadata <= 0;
      engine_input_reserved <= 0;
      engine_output_reserved <= 0;
    end else begin
      input_job_start <= 0;
      if (any_fast_fault) begin
        // Keep the input/core epoch alive for fault observation; only the common
        // service reset clears quarantine. A per-job reset cannot forgive it.
        state <= QUARANTINE;
      end else begin
        if (certified_input_complete) engine_input_reserved <= 0;
        case (state)
          RESET0: begin core_release <= 0; state <= RESET1; end
          RESET1: begin core_release <= 0; state <= WAIT_BANK; end
          WAIT_BANK: if (job_accept) begin
            engine_metadata <= fast_input_metadata;
            engine_input_reserved <= 1;
            engine_output_reserved <= 1;
            core_release <= 1;
            // Registered token: result admission N, checker admission N+1.
            input_job_start <= 1;
            state <= INPUT_ADMIT;
          end
          INPUT_ADMIT: state <= CONFIGURE;
          CONFIGURE: if (config_valid && config_ready) state <= ENABLE_INPUT;
          ENABLE_INPUT: state <= RUN_JOB;
          RUN_JOB: if (result_commit) state <= ACK_DRAIN;
          ACK_DRAIN: if (!result_busy && output_mailbox_ready) begin
            engine_output_reserved <= 0;
            core_release <= 0;
            state <= RESET0;
          end
          QUARANTINE: state <= QUARANTINE;
          default: state <= QUARANTINE;
        endcase
      end
    end
  end
  starlink_pss_fft512_bfp18_rt_candidate shared_xfft (
    .aclk(fft_clk), .aresetn(core_aresetn),
    .s_axis_config_tdata({7'b0, !engine_metadata[69]}),
    .s_axis_config_tvalid(config_valid), .s_axis_config_tready(config_ready),
    .s_axis_data_tdata(core_input_data), .s_axis_data_tvalid(core_input_valid),
    .s_axis_data_tready(core_input_ready), .s_axis_data_tlast(core_input_last),
    .m_axis_data_tdata(core_output_data), .m_axis_data_tuser(core_output_user),
    .m_axis_data_tvalid(core_output_valid), .m_axis_data_tlast(core_output_last),
    .m_axis_status_tdata(core_status_data), .m_axis_status_tvalid(core_status_valid),
    .event_frame_started(event_frame), .event_tlast_unexpected(event_last_unexpected),
    .event_tlast_missing(event_last_missing), .event_data_in_channel_halt(event_input_halt)
  );
endmodule
