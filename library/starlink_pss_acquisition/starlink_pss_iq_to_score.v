// Complete continuous CI16-to-normalized-score acquisition pipeline.
//
// This composition time-shares one generated 512-point 18-bit XFFT v9.1 core
// between the forward and inverse transforms.  A one-RAMB18 spectrum buffer
// commits each complete forward product before the core is reset, reconfigured,
// and replayed in the inverse direction.  The 15 MS/s conditioned stream leaves
// enough cycles between overlap blocks for this serial schedule.  The raw
// accepted-sample stream still fans out to the overlap scheduler and exact
// energy cache, and remains non-backpressured.  Any component fault closes
// publication and disables acquisition until explicit flush or disable recovery.

`timescale 1ns/1ps

module starlink_pss_iq_to_score #(
  parameter KERNEL_ROM_FILE = "upper_edge_pss_kernel_q17.mem",
  parameter [30:0] COEFFICIENT_ENERGY = 31'd1073742825,
  parameter integer DATA_WIDTH = 18
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
  wire forward_adapter_input_ready;
  wire forward_input_block_complete_pulse;
  wire forward_output_block_complete_pulse;

  wire forward_output_valid;
  wire forward_output_ready;
  wire signed [DATA_WIDTH-1:0] forward_output_i;
  wire signed [DATA_WIDTH-1:0] forward_output_q;
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
  wire signed [DATA_WIDTH-1:0] joined_i;
  wire signed [DATA_WIDTH-1:0] joined_q;
  wire signed [DATA_WIDTH-1:0] joined_kernel_i;
  wire signed [DATA_WIDTH-1:0] joined_kernel_q;
  wire [8:0] joined_bin_index;
  wire [4:0] joined_forward_exponent;
  wire joined_last;
  wire [63:0] joined_block_start;

  wire product_output_valid;
  wire product_output_ready;
  wire signed [DATA_WIDTH-1:0] product_output_i;
  wire signed [DATA_WIDTH-1:0] product_output_q;
  wire [8:0] product_output_bin_index;
  wire [4:0] product_output_exponent;
  wire product_output_last;
  wire [63:0] product_output_block_start;
  wire product_output_overflow;
  wire product_overflow_pulse;

  wire inverse_input_ready;
  wire inverse_input_valid;
  wire signed [DATA_WIDTH-1:0] inverse_input_i;
  wire signed [DATA_WIDTH-1:0] inverse_input_q;
  wire [8:0] inverse_input_position;
  wire [4:0] inverse_forward_exponent;
  wire [63:0] inverse_input_block_start;
  wire inverse_input_last;

  wire inverse_output_valid;
  wire inverse_output_ready;
  wire signed [DATA_WIDTH-1:0] inverse_output_i;
  wire signed [DATA_WIDTH-1:0] inverse_output_q;
  wire [8:0] inverse_output_position;
  wire [4:0] inverse_output_exponent;
  wire [63:0] inverse_output_block_start;
  wire inverse_output_last;
  wire inverse_output_accept;
  reg inverse_stage_valid;
  reg signed [DATA_WIDTH-1:0] inverse_stage_i;
  reg signed [DATA_WIDTH-1:0] inverse_stage_q;
  reg [8:0] inverse_stage_position;
  reg [4:0] inverse_stage_forward_exponent;
  reg [4:0] inverse_stage_exponent;
  reg [63:0] inverse_stage_block_start;
  reg inverse_stage_last;
  wire candidate_ifft_ready;
  wire candidate_backpressure_fault;
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

  wire shared_core_aresetn;
  wire [7:0] shared_core_config_tdata;
  wire shared_core_config_tvalid;
  wire shared_core_config_tready;
  wire [47:0] shared_core_input_tdata;
  wire shared_core_input_tvalid;
  wire shared_core_input_tready;
  wire shared_core_input_tlast;
  wire [47:0] shared_core_output_tdata;
  wire [23:0] shared_core_output_tuser;
  wire shared_core_output_tvalid;
  wire shared_core_output_tready;
  wire shared_core_output_tlast;
  wire [7:0] shared_core_status_tdata;
  wire shared_core_status_tvalid;
  wire shared_core_status_tready;
  wire shared_core_event_frame_started;
  wire shared_core_event_tlast_unexpected;
  wire shared_core_event_tlast_missing;
  wire shared_core_event_status_channel_halt;
  wire shared_core_event_data_in_channel_halt;
  wire shared_core_event_data_out_channel_halt;

  reg processing_inverse;
  reg forward_input_closed;
  wire intermediate_input_ready;
  wire intermediate_write_complete_pulse;
  wire intermediate_read_complete_pulse;
  wire intermediate_protocol_fault;
  wire [9:0] intermediate_stored_count;
  wire intermediate_release;

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

  generate
    if (DATA_WIDTH != 18) begin : g_invalid_generated_xfft_width
      initial $fatal(1, "generated acquisition XFFT requires DATA_WIDTH=18");
    end
  endgenerate

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
  assign forward_exponent_fault = intermediate_protocol_fault;
  assign product_output_ready = product_output_overflow ? 1'b1 :
                                intermediate_input_ready;
  assign inverse_output_accept = inverse_output_valid && inverse_output_ready;
  assign intermediate_release = inverse_output_accept && inverse_output_last;

  assign scheduler_fft_ready = (!processing_inverse &&
                                !forward_input_closed) ?
                               forward_adapter_input_ready : 1'b0;

  assign cache_lookup_ready_to_path = cache_lookup_ready;
  assign cache_output_ready = cache_output_ready_from_path;
  // The generated inverse XFFT is a real-time boundary: downstream scoring
  // may not propagate backpressure into it.  The 512-entry candidate FIFO is
  // dimensioned to absorb the complete 447-result burst.  If that bounded
  // contract is ever violated, consume the XFFT beat, suppress it locally,
  // and quarantine the detector rather than stalling the transform.
  assign inverse_output_ready = 1'b1;
  assign candidate_backpressure_fault = inverse_stage_valid &&
                                         !candidate_ifft_ready;

  assign path_score_ready = score_ready;
  assign score_valid = path_score_valid && interfaces_open;

  assign fault_event = forward_fft_fault || kernel_join_fault ||
                       product_overflow_fault || inverse_fft_fault ||
                       intermediate_protocol_fault || path_fault ||
                       candidate_backpressure_fault ||
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
    .FORWARD_TRANSFORM (1),
    .DATA_WIDTH        (DATA_WIDTH)
  ) forward_adapter (
    .clk                            (clk),
    .resetn                         (pipeline_resetn && !processing_inverse),
    .flush                          (pipeline_flush),
    .input_valid                    (scheduler_fft_valid &&
                                     !forward_input_closed &&
                                     !processing_inverse),
    .input_ready                    (forward_adapter_input_ready),
    .input_i                        ({scheduler_fft_i,
                                      {(DATA_WIDTH-16){1'b0}}}),
    .input_q                        ({scheduler_fft_q,
                                      {(DATA_WIDTH-16){1'b0}}}),
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
    .input_block_complete_pulse     (forward_input_block_complete_pulse),
    .output_block_complete_pulse    (forward_output_block_complete_pulse),
    .protocol_error_pulse           (),
    .input_framing_error_pulse      (),
    .output_metadata_error_pulse    (),
    .status_error_pulse             (),
    .core_tlast_error_pulse         (),
    .core_data_in_halt_pulse        (),
    .core_data_out_halt_pulse       (),
    .protocol_fault                 (forward_fft_fault)
  );

  starlink_pss_forward_kernel_join #(
    .KERNEL_ROM_FILE (KERNEL_ROM_FILE),
    .DATA_WIDTH      (DATA_WIDTH)
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

  starlink_pss_spectrum_product #(
    .DATA_WIDTH(DATA_WIDTH)
  ) spectrum_product (
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

  starlink_pss_xfft_intermediate_buffer #(
    .DATA_WIDTH(DATA_WIDTH)
  ) intermediate_buffer (
    .clk                       (clk),
    .resetn                    (pipeline_resetn),
    .flush                     (pipeline_flush),
    .release_buffer            (intermediate_release),
    .input_valid               (product_output_valid &&
                                !product_output_overflow),
    .input_ready               (intermediate_input_ready),
    .input_i                   (product_output_i),
    .input_q                   (product_output_q),
    .input_position            (product_output_bin_index),
    .input_block_exponent      (product_output_exponent),
    .input_block_start_index   (product_output_block_start),
    .input_last                (product_output_last),
    .read_enable               (processing_inverse),
    .output_valid              (inverse_input_valid),
    .output_ready              (inverse_input_ready),
    .output_i                  (inverse_input_i),
    .output_q                  (inverse_input_q),
    .output_position           (inverse_input_position),
    .output_block_exponent     (inverse_forward_exponent),
    .output_block_start_index  (inverse_input_block_start),
    .output_last               (inverse_input_last),
    .write_complete_pulse      (intermediate_write_complete_pulse),
    .read_complete_pulse       (intermediate_read_complete_pulse),
    .protocol_error_pulse      (),
    .protocol_fault            (intermediate_protocol_fault),
    .stored_count              (intermediate_stored_count)
  );

  starlink_pss_xfft_block_adapter #(
    .FORWARD_TRANSFORM (0),
    .DATA_WIDTH        (DATA_WIDTH)
  ) inverse_adapter (
    .clk                            (clk),
    .resetn                         (pipeline_resetn && processing_inverse),
    .flush                          (pipeline_flush),
    .input_valid                    (inverse_input_valid),
    .input_ready                    (inverse_input_ready),
    .input_i                        (inverse_input_i),
    .input_q                        (inverse_input_q),
    .input_position                 (inverse_input_position),
    .input_block_start_index        (inverse_input_block_start),
    .input_last                     (inverse_input_last),
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

  // Only the active adapter can drive or observe the generated core.  The
  // inactive adapter is held in reset, and each direction change therefore
  // gives the XFFT a clean reset stretch followed by an explicit direction
  // configuration transaction.
  assign shared_core_aresetn = processing_inverse ?
      inverse_core_aresetn : forward_core_aresetn;
  assign shared_core_config_tdata = processing_inverse ?
      inverse_core_config_tdata : forward_core_config_tdata;
  assign shared_core_config_tvalid = processing_inverse ?
      inverse_core_config_tvalid : forward_core_config_tvalid;
  assign shared_core_input_tdata = processing_inverse ?
      inverse_core_input_tdata : forward_core_input_tdata;
  assign shared_core_input_tvalid = processing_inverse ?
      inverse_core_input_tvalid : forward_core_input_tvalid;
  assign shared_core_input_tlast = processing_inverse ?
      inverse_core_input_tlast : forward_core_input_tlast;
  assign shared_core_output_tready = processing_inverse ?
      inverse_core_output_tready : forward_core_output_tready;
  assign shared_core_status_tready = processing_inverse ?
      inverse_core_status_tready : forward_core_status_tready;

  assign forward_core_config_tready = !processing_inverse &&
                                      shared_core_config_tready;
  assign forward_core_input_tready = !processing_inverse &&
                                     shared_core_input_tready;
  assign inverse_core_config_tready = processing_inverse &&
                                      shared_core_config_tready;
  assign inverse_core_input_tready = processing_inverse &&
                                     shared_core_input_tready;

  assign forward_core_output_tdata = shared_core_output_tdata;
  assign forward_core_output_tuser = shared_core_output_tuser;
  assign forward_core_output_tvalid = !processing_inverse &&
                                      shared_core_output_tvalid;
  assign forward_core_output_tlast = shared_core_output_tlast;
  assign forward_core_status_tdata = shared_core_status_tdata;
  assign forward_core_status_tvalid = !processing_inverse &&
                                      shared_core_status_tvalid;
  assign forward_core_event_frame_started = !processing_inverse &&
      shared_core_event_frame_started;
  assign forward_core_event_tlast_unexpected = !processing_inverse &&
      shared_core_event_tlast_unexpected;
  assign forward_core_event_tlast_missing = !processing_inverse &&
      shared_core_event_tlast_missing;
  assign forward_core_event_status_channel_halt = !processing_inverse &&
      shared_core_event_status_channel_halt;
  assign forward_core_event_data_in_channel_halt = !processing_inverse &&
      shared_core_event_data_in_channel_halt;
  assign forward_core_event_data_out_channel_halt = !processing_inverse &&
      shared_core_event_data_out_channel_halt;

  assign inverse_core_output_tdata = shared_core_output_tdata;
  assign inverse_core_output_tuser = shared_core_output_tuser;
  assign inverse_core_output_tvalid = processing_inverse &&
                                      shared_core_output_tvalid;
  assign inverse_core_output_tlast = shared_core_output_tlast;
  assign inverse_core_status_tdata = shared_core_status_tdata;
  assign inverse_core_status_tvalid = processing_inverse &&
                                      shared_core_status_tvalid;
  assign inverse_core_event_frame_started = processing_inverse &&
      shared_core_event_frame_started;
  assign inverse_core_event_tlast_unexpected = processing_inverse &&
      shared_core_event_tlast_unexpected;
  assign inverse_core_event_tlast_missing = processing_inverse &&
      shared_core_event_tlast_missing;
  assign inverse_core_event_status_channel_halt = processing_inverse &&
      shared_core_event_status_channel_halt;
  assign inverse_core_event_data_in_channel_halt = processing_inverse &&
      shared_core_event_data_in_channel_halt;
  assign inverse_core_event_data_out_channel_halt = processing_inverse &&
      shared_core_event_data_out_channel_halt;

  starlink_pss_fft512_bfp18 shared_xfft (
    .aclk                          (clk),
    .aresetn                       (shared_core_aresetn),
    .s_axis_config_tdata           (shared_core_config_tdata),
    .s_axis_config_tvalid          (shared_core_config_tvalid),
    .s_axis_config_tready          (shared_core_config_tready),
    .s_axis_data_tdata             (shared_core_input_tdata),
    .s_axis_data_tvalid            (shared_core_input_tvalid),
    .s_axis_data_tready            (shared_core_input_tready),
    .s_axis_data_tlast             (shared_core_input_tlast),
    .m_axis_data_tdata             (shared_core_output_tdata),
    .m_axis_data_tuser             (shared_core_output_tuser),
    .m_axis_data_tvalid            (shared_core_output_tvalid),
    .m_axis_data_tready            (shared_core_output_tready),
    .m_axis_data_tlast             (shared_core_output_tlast),
    .m_axis_status_tdata           (shared_core_status_tdata),
    .m_axis_status_tvalid          (shared_core_status_tvalid),
    .m_axis_status_tready          (shared_core_status_tready),
    .event_frame_started           (shared_core_event_frame_started),
    .event_tlast_unexpected        (shared_core_event_tlast_unexpected),
    .event_tlast_missing           (shared_core_event_tlast_missing),
    .event_status_channel_halt     (shared_core_event_status_channel_halt),
    .event_data_in_channel_halt    (shared_core_event_data_in_channel_halt),
    .event_data_out_channel_halt   (shared_core_event_data_out_channel_halt)
  );

  starlink_pss_candidate_score_path #(
    .COEFFICIENT_ENERGY(COEFFICIENT_ENERGY),
    .DATA_WIDTH        (DATA_WIDTH)
  ) candidate_score_path (
    .clk                       (clk),
    .resetn                    (pipeline_resetn),
    .flush                     (pipeline_flush),
    // The explicit register boundary separates the XFFT adapter's complete
    // metadata qualification from this path's independent sequence checks.
    // The result FIFO is sized for the full 447-result burst, so this stage
    // sustains one result per clock without propagating ready into the XFFT.
    .ifft_valid                (inverse_stage_valid),
    .ifft_ready                (candidate_ifft_ready),
    .ifft_correlation_i        (inverse_stage_i),
    .ifft_correlation_q        (inverse_stage_q),
    .ifft_index                (inverse_stage_position),
    .forward_exponent          (inverse_stage_forward_exponent),
    .inverse_exponent          (inverse_stage_exponent),
    .block_start_index         (inverse_stage_block_start),
    .ifft_last                 (inverse_stage_last),
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

  assign candidate_path_fault = path_fault || candidate_backpressure_fault;

  // The generated inverse XFFT is never backpressured.  Its qualified output
  // is therefore captured into a one-beat elastic timing boundary on every
  // valid clock.  In normal operation the candidate path consumes the prior
  // beat on that same edge.  An unexpected stall is still fail-closed through
  // candidate_backpressure_fault instead of silently overwriting data.
  always @(posedge clk) begin
    if (!pipeline_resetn) begin
      inverse_stage_valid <= 1'b0;
      inverse_stage_i <= 0;
      inverse_stage_q <= 0;
      inverse_stage_position <= 0;
      inverse_stage_forward_exponent <= 0;
      inverse_stage_exponent <= 0;
      inverse_stage_block_start <= 0;
      inverse_stage_last <= 1'b0;
    end else begin
      inverse_stage_valid <= inverse_output_valid;
      if (inverse_output_valid) begin
        inverse_stage_i <= inverse_output_i;
        inverse_stage_q <= inverse_output_q;
        inverse_stage_position <= inverse_output_position;
        inverse_stage_forward_exponent <= inverse_forward_exponent;
        inverse_stage_exponent <= inverse_output_exponent;
        inverse_stage_block_start <= inverse_output_block_start;
        inverse_stage_last <= inverse_output_last;
      end
    end
  end

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
    end else begin
      if (fault_event)
        detector_fault <= 1'b1;
    end
  end

  // The forward adapter is closed as soon as its input block completes, so it
  // cannot begin another transform while the first block is still producing
  // spectrum data.  Once the committed product buffer is full, ownership of
  // the single XFFT moves to the inverse adapter.  The next forward block may
  // start only after the complete inverse output has been accepted.
  always @(posedge clk) begin
    if (!pipeline_resetn || pipeline_flush) begin
      processing_inverse <= 1'b0;
      forward_input_closed <= 1'b0;
    end else begin
      if (!processing_inverse && forward_input_block_complete_pulse)
        forward_input_closed <= 1'b1;

      if (!processing_inverse && intermediate_write_complete_pulse) begin
        processing_inverse <= 1'b1;
        forward_input_closed <= 1'b0;
      end else if (processing_inverse && intermediate_release) begin
        processing_inverse <= 1'b0;
        forward_input_closed <= 1'b0;
      end
    end
  end

endmodule
