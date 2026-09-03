// Complete continuous CI16-to-normalized-score acquisition pipeline.
//
// This composition owns one generated forward and one generated inverse
// 512-point XFFT v9.1 core.  The raw accepted-sample stream fans out to the
// overlap scheduler and exact energy cache.  FFT output is paired with the
// hash-locked upper-edge kernel, multiplied, transformed back, and qualified
// into 447 exact normalized scores per complete block.  The full-rate CI16
// source remains non-backpressured.  Any component fault closes publication
// and disables acquisition until explicit flush or disable recovery.

`timescale 1ns/1ps

module starlink_pss_iq_to_score #(
  parameter KERNEL_ROM_FILE = "upper_edge_pss_kernel_q23.mem"
) (
  input  wire                    clk,
  input  wire                    resetn,
  input  wire                    enable,
  input  wire                    flush,

  input  wire                    sample_valid,
  input  wire                    sample_gap,
  input  wire signed [15:0]      sample_i,
  input  wire signed [15:0]      sample_q,
  input  wire [63:0]             sample_index,

  output wire                    score_valid,
  input  wire                    score_ready,
  output wire [7:0]              score_value,
  output wire [63:0]             score_start_index,
  output wire                    score_denominator_zero,

  output reg                     detector_fault,
  output wire                    scheduler_gap_pulse,
  output wire                    scheduler_index_error_pulse,
  output wire                    scheduler_overflow_pulse,
  output wire                    forward_fft_fault,
  output wire                    kernel_join_fault,
  output wire                    product_overflow_fault,
  output wire                    inverse_fft_fault,
  output wire                    forward_exponent_fault,
  output wire                    candidate_path_fault,
  output wire [9:0]              candidate_fifo_stored_count,
  output wire [9:0]              candidate_fifo_maximum_stored_count
);

  wire effective_enable;
  wire scheduler_enable;
  wire scheduler_flush_pulse;
  wire pipeline_resetn;
  wire pipeline_flush;
  wire fault_event;
  reg pipeline_active;

  wire scheduler_fft_valid;
  wire scheduler_fft_ready;
  wire signed [15:0] scheduler_fft_i;
  wire signed [15:0] scheduler_fft_q;
  wire [8:0] scheduler_fft_position;
  wire scheduler_fft_last;
  wire [63:0] scheduler_fft_block_start;

  wire forward_output_valid;
  wire forward_output_ready;
  wire signed [23:0] forward_output_i;
  wire signed [23:0] forward_output_q;
  wire [8:0] forward_output_position;
  wire [4:0] forward_output_exponent;
  wire [63:0] forward_output_block_start;
  wire forward_output_last;
  wire forward_core_aresetn;
  wire [7:0] forward_core_config_tdata;
  wire forward_core_config_tvalid;
  wire forward_core_config_tready;
  wire [47:0] forward_core_input_tdata;
  wire forward_core_input_tvalid;
  wire forward_core_input_tready;
  wire forward_core_input_tlast;
  wire [47:0] forward_core_output_tdata;
  wire [23:0] forward_core_output_tuser;
  wire forward_core_output_tvalid;
  wire forward_core_output_tready;
  wire forward_core_output_tlast;
  wire [7:0] forward_core_status_tdata;
  wire forward_core_status_tvalid;
  wire forward_core_status_tready;
  wire forward_core_event_frame_started;
  wire forward_core_event_tlast_unexpected;
  wire forward_core_event_tlast_missing;
  wire forward_core_event_status_channel_halt;
  wire forward_core_event_data_in_channel_halt;
  wire forward_core_event_data_out_channel_halt;

  wire joined_valid;
  wire joined_ready;
  wire signed [23:0] joined_i;
  wire signed [23:0] joined_q;
  wire signed [23:0] joined_kernel_i;
  wire signed [23:0] joined_kernel_q;
  wire [8:0] joined_bin_index;
  wire [4:0] joined_forward_exponent;
  wire joined_last;
  wire [63:0] joined_block_start;

  wire product_output_valid;
  wire product_output_ready;
  wire signed [23:0] product_output_i;
  wire signed [23:0] product_output_q;
  wire [8:0] product_output_bin_index;
  wire [4:0] product_output_exponent;
  wire product_output_last;
  wire [63:0] product_output_block_start;
  wire product_output_overflow;
  wire product_overflow_pulse;

  wire inverse_input_ready;
  wire inverse_input_valid;
  wire inverse_input_accept;
  wire inverse_forward_exponent_error_now;
  reg inverse_forward_exponent_seen;
  reg [4:0] inverse_forward_exponent;
  reg forward_exponent_fault_latched;

  wire inverse_output_valid;
  wire inverse_output_ready;
  wire signed [23:0] inverse_output_i;
  wire signed [23:0] inverse_output_q;
  wire [8:0] inverse_output_position;
  wire [4:0] inverse_output_exponent;
  wire [63:0] inverse_output_block_start;
  wire inverse_output_last;
  wire inverse_output_accept;
  wire candidate_ifft_ready;
  wire inverse_core_aresetn;
  wire [7:0] inverse_core_config_tdata;
  wire inverse_core_config_tvalid;
  wire inverse_core_config_tready;
  wire [47:0] inverse_core_input_tdata;
  wire inverse_core_input_tvalid;
  wire inverse_core_input_tready;
  wire inverse_core_input_tlast;
  wire [47:0] inverse_core_output_tdata;
  wire [23:0] inverse_core_output_tuser;
  wire inverse_core_output_tvalid;
  wire inverse_core_output_tready;
  wire inverse_core_output_tlast;
  wire [7:0] inverse_core_status_tdata;
  wire inverse_core_status_tvalid;
  wire inverse_core_status_tready;
  wire inverse_core_event_frame_started;
  wire inverse_core_event_tlast_unexpected;
  wire inverse_core_event_tlast_missing;
  wire inverse_core_event_status_channel_halt;
  wire inverse_core_event_data_in_channel_halt;
  wire inverse_core_event_data_out_channel_halt;

  wire cache_lookup_valid_from_path;
  wire cache_lookup_ready_to_path;
  wire [63:0] cache_lookup_start_from_path;
  wire cache_lookup_ready;
  wire cache_output_valid;
  wire cache_output_ready_from_path;
  wire cache_output_ready;
  wire [37:0] cache_output_energy;
  wire [63:0] cache_output_start;
  wire cache_output_found;

  wire path_score_valid;
  wire path_score_ready;
  wire path_fault;
  wire interfaces_open;

  assign effective_enable = enable && !detector_fault;
  assign scheduler_enable = effective_enable && !flush &&
                            pipeline_active;
  assign pipeline_resetn = pipeline_active;
  assign pipeline_flush = !pipeline_active;
  // Constituent blocks suppress the malformed beat locally.  Keep the global
  // quarantine registered through detector_fault and out of the internal
  // ready chain; pipeline_resetn clears every retained transaction on the next
  // clock instead of creating a full-pipeline ready/fault/ready path.
  assign interfaces_open = resetn && effective_enable && pipeline_active &&
                           !flush &&
                           !scheduler_flush_pulse && !pipeline_flush;

  assign product_overflow_fault = product_output_valid &&
                                  product_output_overflow;
  assign forward_exponent_fault = forward_exponent_fault_latched;
  assign inverse_input_valid = product_output_valid &&
                               !product_output_overflow &&
                               !inverse_forward_exponent_error_now;
  assign product_output_ready = (product_output_overflow ||
                                 inverse_forward_exponent_error_now) ? 1'b1 :
                                inverse_input_ready;
  assign inverse_input_accept = inverse_input_valid && inverse_input_ready;
  assign inverse_output_accept = inverse_output_valid && inverse_output_ready;

  assign inverse_forward_exponent_error_now = product_output_valid &&
    !product_output_overflow &&
    ((product_output_bin_index == 0) ? inverse_forward_exponent_seen :
     (!inverse_forward_exponent_seen ||
      product_output_exponent != inverse_forward_exponent));

  assign cache_lookup_ready_to_path = cache_lookup_ready;
  assign cache_output_ready = cache_output_ready_from_path;
  assign inverse_output_ready = candidate_ifft_ready;

  assign path_score_ready = score_ready;
  assign score_valid = path_score_valid && interfaces_open;

  assign fault_event = forward_fft_fault || kernel_join_fault ||
                       product_overflow_fault || inverse_fft_fault ||
                       inverse_forward_exponent_error_now ||
                       forward_exponent_fault_latched || path_fault ||
                       scheduler_overflow_pulse;

  starlink_pss_overlap_scheduler scheduler (
    .clk                     (clk),
    .resetn                  (pipeline_resetn),
    .enable                  (scheduler_enable),
    .sample_valid            (sample_valid),
    .sample_gap              (sample_gap),
    .sample_i                (sample_i),
    .sample_q                (sample_q),
    .sample_index            (sample_index),
    .fft_valid               (scheduler_fft_valid),
    .fft_ready               (scheduler_fft_ready),
    .fft_i                   (scheduler_fft_i),
    .fft_q                   (scheduler_fft_q),
    .fft_position            (scheduler_fft_position),
    .fft_last                (scheduler_fft_last),
    .fft_block_start_index   (scheduler_fft_block_start),
    .flush_pulse             (scheduler_flush_pulse),
    .gap_pulse               (scheduler_gap_pulse),
    .index_error_pulse       (scheduler_index_error_pulse),
    .overflow_pulse          (scheduler_overflow_pulse),
    .block_queued_pulse      (),
    .block_complete_pulse    (),
    .busy                    (),
    .segment_sample_count    (),
    .queued_block_count      ()
  );

  starlink_pss_energy_cache energy_cache (
    .clk                       (clk),
    .resetn                    (pipeline_resetn),
    .enable                    (effective_enable),
    .flush                     (pipeline_flush),
    .sample_valid              (sample_valid),
    .sample_gap                (sample_gap),
    .sample_i                  (sample_i),
    .sample_q                  (sample_q),
    .sample_index              (sample_index),
    .lookup_valid              (cache_lookup_valid_from_path),
    .lookup_ready              (cache_lookup_ready),
    .lookup_start_index        (cache_lookup_start_from_path),
    .output_valid              (cache_output_valid),
    .output_ready              (cache_output_ready),
    .output_energy             (cache_output_energy),
    .output_start_index        (cache_output_start),
    .output_found              (cache_output_found),
    .energy_write_pulse        (),
    .energy_write_value        (),
    .energy_write_start_index  (),
    .gap_pulse                 (),
    .index_error_pulse         (),
    .restart_pulse             (),
    .retention_miss_pulse      (),
    .stored_energy_count       (),
    .oldest_energy_start_index (),
    .newest_energy_start_index ()
  );

  starlink_pss_xfft_block_adapter #(
    .FORWARD_TRANSFORM (1)
  ) forward_adapter (
    .clk                            (clk),
    .resetn                         (pipeline_resetn),
    .flush                          (pipeline_flush),
    .input_valid                    (scheduler_fft_valid),
    .input_ready                    (scheduler_fft_ready),
    .input_i                        ({scheduler_fft_i, 8'b0}),
    .input_q                        ({scheduler_fft_q, 8'b0}),
    .input_position                 (scheduler_fft_position),
    .input_block_start_index        (scheduler_fft_block_start),
    .input_last                     (scheduler_fft_last),
    .output_valid                   (forward_output_valid),
    .output_ready                   (forward_output_ready),
    .output_i                       (forward_output_i),
    .output_q                       (forward_output_q),
    .output_position                (forward_output_position),
    .output_block_exponent          (forward_output_exponent),
    .output_block_start_index       (forward_output_block_start),
    .output_last                    (forward_output_last),
    .core_aresetn                   (forward_core_aresetn),
    .core_config_tdata              (forward_core_config_tdata),
    .core_config_tvalid             (forward_core_config_tvalid),
    .core_config_tready             (forward_core_config_tready),
    .core_input_tdata               (forward_core_input_tdata),
    .core_input_tvalid              (forward_core_input_tvalid),
    .core_input_tready              (forward_core_input_tready),
    .core_input_tlast               (forward_core_input_tlast),
    .core_output_tdata              (forward_core_output_tdata),
    .core_output_tuser              (forward_core_output_tuser),
    .core_output_tvalid             (forward_core_output_tvalid),
    .core_output_tready             (forward_core_output_tready),
    .core_output_tlast              (forward_core_output_tlast),
    .core_status_tdata              (forward_core_status_tdata),
    .core_status_tvalid             (forward_core_status_tvalid),
    .core_status_tready             (forward_core_status_tready),
    .core_event_frame_started       (forward_core_event_frame_started),
    .core_event_tlast_unexpected    (forward_core_event_tlast_unexpected),
    .core_event_tlast_missing       (forward_core_event_tlast_missing),
    .core_event_status_channel_halt (forward_core_event_status_channel_halt),
    .core_event_data_in_channel_halt(forward_core_event_data_in_channel_halt),
    .core_event_data_out_channel_halt(forward_core_event_data_out_channel_halt),
    .configured_pulse               (),
    .input_block_complete_pulse     (),
    .output_block_complete_pulse    (),
    .protocol_error_pulse           (),
    .input_framing_error_pulse      (),
    .output_metadata_error_pulse    (),
    .status_error_pulse             (),
    .core_tlast_error_pulse         (),
    .core_data_in_halt_pulse        (),
    .core_data_out_halt_pulse       (),
    .protocol_fault                 (forward_fft_fault)
  );

  starlink_pss_fft512_bfp24 forward_xfft (
    .aclk                          (clk),
    .aresetn                       (forward_core_aresetn),
    .s_axis_config_tdata           (forward_core_config_tdata),
    .s_axis_config_tvalid          (forward_core_config_tvalid),
    .s_axis_config_tready          (forward_core_config_tready),
    .s_axis_data_tdata             (forward_core_input_tdata),
    .s_axis_data_tvalid            (forward_core_input_tvalid),
    .s_axis_data_tready            (forward_core_input_tready),
    .s_axis_data_tlast             (forward_core_input_tlast),
    .m_axis_data_tdata             (forward_core_output_tdata),
    .m_axis_data_tuser             (forward_core_output_tuser),
    .m_axis_data_tvalid            (forward_core_output_tvalid),
    .m_axis_data_tready            (forward_core_output_tready),
    .m_axis_data_tlast             (forward_core_output_tlast),
    .m_axis_status_tdata           (forward_core_status_tdata),
    .m_axis_status_tvalid          (forward_core_status_tvalid),
    .m_axis_status_tready          (forward_core_status_tready),
    .event_frame_started           (forward_core_event_frame_started),
    .event_tlast_unexpected        (forward_core_event_tlast_unexpected),
    .event_tlast_missing           (forward_core_event_tlast_missing),
    .event_status_channel_halt     (forward_core_event_status_channel_halt),
    .event_data_in_channel_halt    (forward_core_event_data_in_channel_halt),
    .event_data_out_channel_halt   (forward_core_event_data_out_channel_halt)
  );

  starlink_pss_forward_kernel_join #(
    .KERNEL_ROM_FILE (KERNEL_ROM_FILE)
  ) forward_kernel_join (
    .clk                       (clk),
    .resetn                    (pipeline_resetn),
    .flush                     (pipeline_flush),
    .input_valid               (forward_output_valid),
    .input_ready               (forward_output_ready),
    .input_i                   (forward_output_i),
    .input_q                   (forward_output_q),
    .input_bin_index           (forward_output_position),
    .input_block_exponent      (forward_output_exponent),
    .input_last                (forward_output_last),
    .input_block_start_index   (forward_output_block_start),
    .output_valid              (joined_valid),
    .output_ready              (joined_ready),
    .output_i                  (joined_i),
    .output_q                  (joined_q),
    .output_kernel_i           (joined_kernel_i),
    .output_kernel_q           (joined_kernel_q),
    .output_bin_index          (joined_bin_index),
    .output_block_exponent     (joined_forward_exponent),
    .output_last               (joined_last),
    .output_block_start_index  (joined_block_start),
    .accepted_pulse            (),
    .emitted_pulse             (),
    .input_block_complete_pulse(),
    .sequence_error_pulse      (),
    .metadata_error_pulse      (),
    .protocol_fault            (kernel_join_fault)
  );

  starlink_pss_spectrum_product spectrum_product (
    .clk                      (clk),
    .resetn                   (pipeline_resetn),
    .flush                    (pipeline_flush),
    .input_valid              (joined_valid),
    .input_ready              (joined_ready),
    .input_i                  (joined_i),
    .input_q                  (joined_q),
    .kernel_i                 (joined_kernel_i),
    .kernel_q                 (joined_kernel_q),
    .input_bin_index          (joined_bin_index),
    .input_block_exponent     (joined_forward_exponent),
    .input_last               (joined_last),
    .input_block_start_index  (joined_block_start),
    .output_valid             (product_output_valid),
    .output_ready             (product_output_ready),
    .output_i                 (product_output_i),
    .output_q                 (product_output_q),
    .output_bin_index         (product_output_bin_index),
    .output_block_exponent    (product_output_exponent),
    .output_last              (product_output_last),
    .output_block_start_index (product_output_block_start),
    .output_overflow          (product_output_overflow),
    .overflow_pulse           (product_overflow_pulse)
  );

  starlink_pss_xfft_block_adapter #(
    .FORWARD_TRANSFORM (0)
  ) inverse_adapter (
    .clk                            (clk),
    .resetn                         (pipeline_resetn),
    .flush                          (pipeline_flush),
    .input_valid                    (inverse_input_valid),
    .input_ready                    (inverse_input_ready),
    .input_i                        (product_output_i),
    .input_q                        (product_output_q),
    .input_position                 (product_output_bin_index),
    .input_block_start_index        (product_output_block_start),
    .input_last                     (product_output_last),
    .output_valid                   (inverse_output_valid),
    .output_ready                   (inverse_output_ready),
    .output_i                       (inverse_output_i),
    .output_q                       (inverse_output_q),
    .output_position                (inverse_output_position),
    .output_block_exponent          (inverse_output_exponent),
    .output_block_start_index       (inverse_output_block_start),
    .output_last                    (inverse_output_last),
    .core_aresetn                   (inverse_core_aresetn),
    .core_config_tdata              (inverse_core_config_tdata),
    .core_config_tvalid             (inverse_core_config_tvalid),
    .core_config_tready             (inverse_core_config_tready),
    .core_input_tdata               (inverse_core_input_tdata),
    .core_input_tvalid              (inverse_core_input_tvalid),
    .core_input_tready              (inverse_core_input_tready),
    .core_input_tlast               (inverse_core_input_tlast),
    .core_output_tdata              (inverse_core_output_tdata),
    .core_output_tuser              (inverse_core_output_tuser),
    .core_output_tvalid             (inverse_core_output_tvalid),
    .core_output_tready             (inverse_core_output_tready),
    .core_output_tlast              (inverse_core_output_tlast),
    .core_status_tdata              (inverse_core_status_tdata),
    .core_status_tvalid             (inverse_core_status_tvalid),
    .core_status_tready             (inverse_core_status_tready),
    .core_event_frame_started       (inverse_core_event_frame_started),
    .core_event_tlast_unexpected    (inverse_core_event_tlast_unexpected),
    .core_event_tlast_missing       (inverse_core_event_tlast_missing),
    .core_event_status_channel_halt (inverse_core_event_status_channel_halt),
    .core_event_data_in_channel_halt(inverse_core_event_data_in_channel_halt),
    .core_event_data_out_channel_halt(inverse_core_event_data_out_channel_halt),
    .configured_pulse               (),
    .input_block_complete_pulse     (),
    .output_block_complete_pulse    (),
    .protocol_error_pulse           (),
    .input_framing_error_pulse      (),
    .output_metadata_error_pulse    (),
    .status_error_pulse             (),
    .core_tlast_error_pulse         (),
    .core_data_in_halt_pulse        (),
    .core_data_out_halt_pulse       (),
    .protocol_fault                 (inverse_fft_fault)
  );

  starlink_pss_fft512_bfp24 inverse_xfft (
    .aclk                          (clk),
    .aresetn                       (inverse_core_aresetn),
    .s_axis_config_tdata           (inverse_core_config_tdata),
    .s_axis_config_tvalid          (inverse_core_config_tvalid),
    .s_axis_config_tready          (inverse_core_config_tready),
    .s_axis_data_tdata             (inverse_core_input_tdata),
    .s_axis_data_tvalid            (inverse_core_input_tvalid),
    .s_axis_data_tready            (inverse_core_input_tready),
    .s_axis_data_tlast             (inverse_core_input_tlast),
    .m_axis_data_tdata             (inverse_core_output_tdata),
    .m_axis_data_tuser             (inverse_core_output_tuser),
    .m_axis_data_tvalid            (inverse_core_output_tvalid),
    .m_axis_data_tready            (inverse_core_output_tready),
    .m_axis_data_tlast             (inverse_core_output_tlast),
    .m_axis_status_tdata           (inverse_core_status_tdata),
    .m_axis_status_tvalid          (inverse_core_status_tvalid),
    .m_axis_status_tready          (inverse_core_status_tready),
    .event_frame_started           (inverse_core_event_frame_started),
    .event_tlast_unexpected        (inverse_core_event_tlast_unexpected),
    .event_tlast_missing           (inverse_core_event_tlast_missing),
    .event_status_channel_halt     (inverse_core_event_status_channel_halt),
    .event_data_in_channel_halt    (inverse_core_event_data_in_channel_halt),
    .event_data_out_channel_halt   (inverse_core_event_data_out_channel_halt)
  );

  starlink_pss_candidate_score_path candidate_score_path (
    .clk                       (clk),
    .resetn                    (pipeline_resetn),
    .flush                     (pipeline_flush),
    .ifft_valid                (inverse_output_valid),
    .ifft_ready                (candidate_ifft_ready),
    .ifft_correlation_i        (inverse_output_i),
    .ifft_correlation_q        (inverse_output_q),
    .ifft_index                (inverse_output_position),
    .forward_exponent          (inverse_forward_exponent),
    .inverse_exponent          (inverse_output_exponent),
    .block_start_index         (inverse_output_block_start),
    .ifft_last                 (inverse_output_last),
    .cache_lookup_valid        (cache_lookup_valid_from_path),
    .cache_lookup_ready        (cache_lookup_ready_to_path),
    .cache_lookup_start_index  (cache_lookup_start_from_path),
    .cache_output_valid        (cache_output_valid),
    .cache_output_ready        (cache_output_ready_from_path),
    .cache_output_energy       (cache_output_energy),
    .cache_output_start_index  (cache_output_start),
    .cache_output_found        (cache_output_found),
    .score_valid               (path_score_valid),
    .score_ready               (path_score_ready),
    .score_value               (score_value),
    .score_start_index         (score_start_index),
    .score_denominator_zero    (score_denominator_zero),
    .path_fault                (path_fault),
    .ifft_protocol_fault       (),
    .fifo_overflow_fault       (),
    .energy_join_fault         (),
    .fifo_stored_count         (candidate_fifo_stored_count),
    .fifo_maximum_stored_count (candidate_fifo_maximum_stored_count)
  );

  assign candidate_path_fault = path_fault;

  // Reset, enable, flush, scheduler restart, and detector faults are lifecycle
  // controls rather than datapath flow control.  Suppress publication in the
  // assertion cycle, then use this registered active state as the sole reset
  // source for every retained detector transaction.  This keeps high-fanout
  // external control inputs out of the complete FIFO/ready chain.
  always @(posedge clk) begin
    if (!resetn || !enable)
      pipeline_active <= 1'b0;
    else if (flush || scheduler_flush_pulse || fault_event || detector_fault)
      pipeline_active <= 1'b0;
    else
      pipeline_active <= 1'b1;
  end

  always @(posedge clk) begin
    if (!resetn || !enable || flush) begin
      detector_fault <= 1'b0;
      inverse_forward_exponent_seen <= 1'b0;
      inverse_forward_exponent <= 0;
      forward_exponent_fault_latched <= 1'b0;
    end else begin
      if (fault_event)
        detector_fault <= 1'b1;

      if (pipeline_flush) begin
        inverse_forward_exponent_seen <= 1'b0;
        inverse_forward_exponent <= 0;
        forward_exponent_fault_latched <= 1'b0;
      end else begin
        if (inverse_input_accept) begin
          if (product_output_bin_index == 0) begin
            inverse_forward_exponent_seen <= 1'b1;
            inverse_forward_exponent <= product_output_exponent;
          end
        end
        if (inverse_forward_exponent_error_now)
          forward_exponent_fault_latched <= 1'b1;
        if (inverse_output_accept && inverse_output_last)
          inverse_forward_exponent_seen <= 1'b0;
      end
    end
  end

endmodule
