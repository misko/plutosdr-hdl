// SPDX-License-Identifier: GPL-2.0
// Experimental three-bank, one-core FFT/product/IFFT island. No receiver use.
// Actual banks: source CDC (slow->fast), private product (fast->fast), and
// inverse output CDC (fast->slow). No stored forward-result bank or copy.
// Forward ACK means an ACTUAL validated product bank has transferred ownership
// to the inverse scheduler; it does not mean that bank may be overwritten.
// Its own mailbox ACK still requires all 512 inverse input reads. Final inverse
// ACK still requires all 512 slow output reads before resetting the core.
`timescale 1ns/1ps
module starlink_pss_fft_bank_owned_slice #(
  parameter KERNEL_ROM_FILE = "upper_edge_pss_kernel_q17.mem"
) (
  input wire clk, resetn, fft_clk, fft_resetn,
  input wire input_valid,
  output wire input_ready,
  input wire [35:0] input_data,
  input wire [8:0] input_position,
  input wire input_last,
  input wire [63:0] input_block_start,
  output wire output_valid,
  input wire output_ready,
  output wire [35:0] output_data,
  output wire [8:0] output_position,
  output wire output_last,
  output wire [74:0] output_metadata,
  output wire fault
);
  (* ASYNC_REG = "TRUE" *) reg [1:0] slow_reset_fast, fast_reset_fast;
  (* ASYNC_REG = "TRUE" *) reg [1:0] slow_reset_slow, fast_reset_slow;
  always @(posedge fft_clk or negedge resetn)
    if (!resetn) slow_reset_fast <= 0; else slow_reset_fast <= {slow_reset_fast[0], 1'b1};
  always @(posedge fft_clk or negedge fft_resetn)
    if (!fft_resetn) fast_reset_fast <= 0; else fast_reset_fast <= {fast_reset_fast[0], 1'b1};
  always @(posedge clk or negedge resetn)
    if (!resetn) slow_reset_slow <= 0; else slow_reset_slow <= {slow_reset_slow[0], 1'b1};
  always @(posedge clk or negedge fft_resetn)
    if (!fft_resetn) fast_reset_slow <= 0; else fast_reset_slow <= {fast_reset_slow[0], 1'b1};
  wire fast_running = slow_reset_fast[1] && fast_reset_fast[1];
  wire slow_running = slow_reset_slow[1] && fast_reset_slow[1];
  wire source_ready, source_fault, source_valid, source_last, source_read_ready;
  wire [35:0] source_data;
  wire [8:0] source_position;
  wire [69:0] source_metadata;
  starlink_pss_block_mailbox #(.RESET_RELEASE_EXTERNAL(1)) source_bank (
    .input_clk(clk), .input_resetn(slow_running),
    .input_valid(input_valid && !fault), .input_ready(source_ready),
    .input_data(input_data), .input_position(input_position), .input_last(input_last),
    .input_metadata({1'b0, input_block_start, 5'b0}), .input_commit_authorized(1'b0),
    .input_fault(source_fault), .input_framing_fault_now(),
    .output_clk(fft_clk), .output_resetn(fast_running),
    .output_valid(source_valid), .output_ready(source_read_ready),
    .output_data(source_data), .output_position(source_position), .output_last(source_last),
    .output_metadata(source_metadata)
  );
  (* ASYNC_REG = "TRUE" *) reg [1:0] source_fault_fast, fast_fault_slow;
  reg fast_fault;
  always @(posedge fft_clk)
    if (!fast_running) source_fault_fast <= 0;
    else source_fault_fast <= {source_fault_fast[0], source_fault};
  always @(posedge clk)
    if (!slow_running) fast_fault_slow <= 0;
    else fast_fault_slow <= {fast_fault_slow[0], fast_fault};
  assign fault = source_fault || fast_fault_slow[1];
  assign input_ready = slow_running && source_ready && !fault;

  localparam [3:0] RESET0=0, RESET1=1, WAIT_BANK=2, INPUT_ADMIT=3,
    CONFIGURE=4, ENABLE_INPUT=5, RUN_JOB=6, ACK_DRAIN=7, QUARANTINE=8;
  reg [3:0] state;
  reg core_release, input_job_start, next_inverse;
  reg [69:0] engine_metadata;
  reg engine_input_reserved, engine_output_reserved, forward_committed;
  wire core_aresetn = fast_running && core_release;
  wire config_valid = state == CONFIGURE && core_aresetn && !fast_fault;
  wire config_ready;
  wire engine_input_enable = state == RUN_JOB && core_aresetn && !fast_fault;
  wire job_ready, result_busy, result_commit, result_fault;
  wire product_bank_valid, product_bank_last, product_bank_read_ready;
  wire [35:0] product_bank_data;
  wire [8:0] product_bank_position;
  wire [69:0] product_bank_metadata;
  wire selected_valid = next_inverse ? product_bank_valid : source_valid;
  wire [35:0] selected_data = next_inverse ? product_bank_data : source_data;
  wire [8:0] selected_position = next_inverse ? product_bank_position : source_position;
  wire selected_last = next_inverse ? product_bank_last : source_last;
  wire [69:0] selected_metadata = next_inverse ? product_bank_metadata : source_metadata;
  wire job_valid = state == WAIT_BANK && selected_valid && !fast_fault;
  wire job_accept = job_valid && job_ready;
  wire transport_ready, checked_input_complete, certified_input_beat, certified_input_complete;
  wire input_fault_now, input_guard_fault, duplicate_start_fault_now;
  wire [47:0] core_input_data, core_output_data;
  wire core_input_valid, core_input_ready, core_input_last;
  wire core_output_valid, core_output_last;
  wire [23:0] core_output_user;
  wire [7:0] core_status_data;
  wire core_status_valid, event_frame, event_last_unexpected, event_last_missing, event_input_halt;
  assign source_read_ready = !next_inverse && transport_ready && engine_input_enable;
  assign product_bank_read_ready = next_inverse && transport_ready && engine_input_enable;
  starlink_pss_realtime_input_guard #(.CHECK_INPUT_BLOCK_IDENTITY(1)) input_guard (
    .clk(fft_clk), .resetn(core_aresetn), .job_start(input_job_start),
    .job_descriptor(engine_metadata), .input_enable(engine_input_enable),
    .input_valid(selected_valid), .input_ready(), .input_transport_ready(transport_ready),
    .input_data(selected_data), .input_position(selected_position), .input_last(selected_last),
    .input_metadata(selected_metadata), .core_input_tdata(core_input_data),
    .core_input_tvalid(core_input_valid), .core_input_tready(core_input_ready),
    .core_input_tlast(core_input_last), .certified_input_beat(certified_input_beat),
    .certified_input_complete(certified_input_complete), .input_complete(checked_input_complete),
    .fault_now(input_fault_now), .duplicate_start_fault_now(duplicate_start_fault_now),
    .protocol_fault(input_guard_fault), .fault_reasons()
  );

  wire return_valid, return_private_valid, return_commit_valid, return_last;
  wire [35:0] return_data;
  wire [8:0] return_position;
  wire [74:0] return_metadata;
  wire kernel_ready, kernel_fault, joined_valid, joined_ready, joined_last;
  wire [17:0] joined_i, joined_q, kernel_i, kernel_q;
  wire [8:0] joined_position;
  wire [4:0] joined_exponent;
  wire [63:0] joined_start;
  wire product_valid, product_last, product_overflow;
  wire [17:0] product_i, product_q;
  wire [8:0] product_position;
  wire [4:0] product_exponent;
  wire [63:0] product_start;
  wire product_bank_ready, product_bank_fault, product_bank_framing_fault_now;
  wire output_bank_ready, output_bank_fault, output_bank_framing_fault_now;
  wire vendor_fault_now = event_last_unexpected || event_last_missing || event_input_halt;
  wire forward_handoff_identity = product_bank_metadata ==
    {1'b1, engine_metadata[68:5], return_metadata[4:0]};
  // The return exponent register is immutable after the forward guard commit.
  // A bank claiming ownership with the wrong descriptor cannot ACK that guard.
  wire handoff_fault_now = !next_inverse && forward_committed && product_bank_valid &&
    (!forward_handoff_identity || product_bank_position != 0 || product_bank_last);
  wire external_fault_now = input_fault_now || input_guard_fault || source_fault_fast[1] ||
    vendor_fault_now || fast_fault || kernel_fault || product_overflow || product_bank_fault ||
    product_bank_framing_fault_now || handoff_fault_now;
  wire forward_handoff_ack = forward_committed && product_bank_valid &&
    forward_handoff_identity && product_bank_position == 0 && !product_bank_last &&
    !external_fault_now && !result_fault;
  wire result_destination_ready = next_inverse ? output_bank_ready :
    (forward_committed ? forward_handoff_ack : (kernel_ready && product_bank_ready));
  wire destination_reserved = next_inverse ? output_bank_ready : product_bank_ready;
  // input_complete is already a registered per-core-epoch certificate. While
  // true, framing/delivery are impossible but a current duplicate job_start
  // remains an immediate fault. This fence is exactly the original full fence.
  wire final_fence = checked_input_complete && !input_guard_fault && !duplicate_start_fault_now;
  // An occupied return also excludes forward_committed: final commit clears
  // active on the same edge that sets that token. The full handoff comparator
  // remains on publication/ACK/quarantine; it cannot fault an occupied return.
  wire completed_input_fault_now = duplicate_start_fault_now || input_guard_fault ||
    source_fault_fast[1] || vendor_fault_now || fast_fault || kernel_fault ||
    product_overflow || product_bank_fault || product_bank_framing_fault_now;
  starlink_pss_realtime_result_guard #(.USE_COMPLETED_INPUT_FAULT(1)) result_guard (
    .clk(fft_clk), .resetn(fast_running), .job_valid(job_valid), .job_ready(job_ready),
    .job_descriptor(selected_metadata),
    .input_bank_reserved(state == WAIT_BANK ? selected_valid : engine_input_reserved),
    .output_bank_reserved(state == WAIT_BANK ? destination_reserved : engine_output_reserved),
    .certified_input_beat(certified_input_beat), .certified_input_complete(certified_input_complete),
    .final_fence_certified(final_fence), .external_fault_now(external_fault_now),
    .phase_input_fault_now(1'b0), .core_event_frame_started(event_frame),
    .completed_input_certified(checked_input_complete),
    .completed_input_fault_now(completed_input_fault_now),
    .core_output_tdata(core_output_data), .core_output_tuser(core_output_user),
    .core_output_tvalid(core_output_valid), .core_output_tlast(core_output_last),
    .core_status_tdata(core_status_data), .core_status_tvalid(core_status_valid),
    .mailbox_input_valid(return_valid), .mailbox_private_valid(return_private_valid),
    .mailbox_commit_valid(return_commit_valid), .mailbox_input_ready(result_destination_ready),
    .mailbox_input_fault(output_bank_fault || output_bank_framing_fault_now),
    .mailbox_input_data(return_data), .mailbox_input_position(return_position),
    .mailbox_input_last(return_last), .mailbox_input_metadata(return_metadata),
    .busy(result_busy), .commit_pulse(result_commit), .protocol_fault(result_fault), .fault_reasons()
  );
  // Nonfinal checked results may compute privately before independent status.
  // The final result is admitted ONLY on the original guard's qualified commit.
  starlink_pss_forward_kernel_join #(.KERNEL_ROM_FILE(KERNEL_ROM_FILE), .DATA_WIDTH(18)) joiner (
    .clk(fft_clk), .resetn(fast_running), .flush(1'b0),
    // Match the guard's exact retirement event, including a held final word.
    // An owned bank should remain ready, but a readiness fault/stall must never
    // let the joiner consume a word that the guard has not retired.
    .input_valid(return_valid && !next_inverse && !fast_fault),
    .input_ready(kernel_ready),
    .input_i(return_data[17:0]), .input_q(return_data[35:18]),
    .input_bin_index(return_position), .input_block_exponent(return_metadata[4:0]),
    .input_last(return_last), .input_block_start_index(return_metadata[73:10]),
    .output_valid(joined_valid), .output_ready(joined_ready),
    .output_i(joined_i), .output_q(joined_q), .output_kernel_i(kernel_i), .output_kernel_q(kernel_q),
    .output_bin_index(joined_position), .output_block_exponent(joined_exponent),
    .output_last(joined_last), .output_block_start_index(joined_start),
    .accepted_pulse(), .emitted_pulse(), .input_block_complete_pulse(),
    .sequence_error_pulse(), .metadata_error_pulse(), .protocol_fault(kernel_fault)
  );
  starlink_pss_spectrum_product #(.DATA_WIDTH(18)) product (
    .clk(fft_clk), .resetn(fast_running), .flush(1'b0),
    .input_valid(joined_valid && !fast_fault), .input_ready(joined_ready),
    .input_i(joined_i), .input_q(joined_q), .kernel_i(kernel_i), .kernel_q(kernel_q),
    .input_bin_index(joined_position), .input_block_exponent(joined_exponent),
    .input_last(joined_last), .input_block_start_index(joined_start),
    .output_valid(product_valid), .output_ready(product_bank_ready && !fast_fault),
    .output_i(product_i), .output_q(product_q), .output_bin_index(product_position),
    .output_block_exponent(product_exponent), .output_last(product_last),
    .output_block_start_index(product_start), .output_overflow(product_overflow), .overflow_pulse()
  );
  wire product_commit_authorized = forward_committed && !external_fault_now && !result_fault;
  starlink_pss_block_mailbox #(.RESET_RELEASE_EXTERNAL(1), .EXPLICIT_COMMIT(1)) product_bank (
    .input_clk(fft_clk), .input_resetn(fast_running),
    .input_valid(product_valid && !fast_fault), .input_ready(product_bank_ready),
    .input_commit_authorized(product_commit_authorized),
    .input_data({product_q, product_i}), .input_position(product_position), .input_last(product_last),
    .input_metadata({1'b1, product_start, product_exponent}),
    .input_fault(product_bank_fault), .input_framing_fault_now(product_bank_framing_fault_now),
    .output_clk(fft_clk), .output_resetn(fast_running),
    .output_valid(product_bank_valid), .output_ready(product_bank_read_ready),
    .output_data(product_bank_data), .output_position(product_bank_position),
    .output_last(product_bank_last), .output_metadata(product_bank_metadata)
  );
  wire slow_output_valid;
  assign output_valid = slow_running && slow_output_valid && !fault;
  starlink_pss_block_mailbox #(.METADATA_WIDTH(75), .RESET_RELEASE_EXTERNAL(1),
      .EXPLICIT_COMMIT(1)) output_bank (
    .input_clk(fft_clk), .input_resetn(fast_running),
    .input_valid(return_private_valid && next_inverse),
    .input_commit_authorized(return_commit_valid && next_inverse), .input_ready(output_bank_ready),
    .input_data(return_data), .input_position(return_position), .input_last(return_last),
    .input_metadata(return_metadata), .input_fault(output_bank_fault),
    .input_framing_fault_now(output_bank_framing_fault_now),
    .output_clk(clk), .output_resetn(slow_running),
    .output_valid(slow_output_valid), .output_ready(output_ready && !fault),
    .output_data(output_data), .output_position(output_position), .output_last(output_last),
    .output_metadata(output_metadata)
  );
  wire any_fast_fault = external_fault_now || result_fault || output_bank_fault;
  always @(posedge fft_clk)
    if (!fast_running) fast_fault <= 0;
    else if (any_fast_fault) fast_fault <= 1;
  always @(posedge fft_clk) begin
    if (!fast_running) begin
      state <= RESET0; core_release <= 0; input_job_start <= 0; next_inverse <= 0;
      engine_metadata <= 0; engine_input_reserved <= 0; engine_output_reserved <= 0;
      forward_committed <= 0;
    end else begin
      input_job_start <= 0;
      if (any_fast_fault) state <= QUARANTINE;
      else begin
        if (certified_input_complete) engine_input_reserved <= 0;
        if (return_commit_valid && result_destination_ready && !next_inverse)
          forward_committed <= 1;
        case (state)
          RESET0: begin core_release <= 0; state <= RESET1; end
          RESET1: begin core_release <= 0; state <= WAIT_BANK; end
          WAIT_BANK: if (job_accept) begin
            engine_metadata <= selected_metadata;
            engine_input_reserved <= 1; engine_output_reserved <= 1;
            core_release <= 1; input_job_start <= 1; state <= INPUT_ADMIT;
            // Product ownership survives clearing this completed-forward token.
            forward_committed <= 0;
          end
          INPUT_ADMIT: state <= CONFIGURE;
          CONFIGURE: if (config_valid && config_ready) state <= ENABLE_INPUT;
          ENABLE_INPUT: state <= RUN_JOB;
          RUN_JOB: if (result_commit) state <= ACK_DRAIN;
          ACK_DRAIN: if (!result_busy && result_destination_ready) begin
            engine_output_reserved <= 0; core_release <= 0;
            next_inverse <= !next_inverse; state <= RESET0;
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
