// Experimental shared-XFFT coarse acquisition. NOT selected by any receiver
// profile until numerical, sustained-capacity, full-fit/timing/CDC gates pass.
// The source/pilot/score domain stays at 100 MHz; only transform service is fast.
`timescale 1ns/1ps

module starlink_pss_iq_to_score_shared #(
  parameter KERNEL_ROM_FILE = "upper_edge_pss_kernel_q17.mem",
  parameter [30:0] COEFFICIENT_ENERGY = 31'd1073742825,
  parameter integer DATA_WIDTH = 18,
  parameter integer USE_REALTIME_XFFT = 0
) (
  input  wire                    clk,
  input  wire                    resetn,
  input  wire                    fft_clk,
  input  wire                    fft_resetn,
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

  wire forward_output_valid;
  wire forward_output_ready;
  wire signed [DATA_WIDTH-1:0] forward_output_i;
  wire signed [DATA_WIDTH-1:0] forward_output_q;
  wire [8:0] forward_output_position;
  wire [4:0] forward_output_exponent;
  wire [63:0] forward_output_block_start;
  wire forward_output_last;
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
  wire inverse_input_accept;
  wire transform_fifo_input_ready;
  wire inverse_stream_valid;
  wire inverse_stream_ready;
  wire signed [DATA_WIDTH-1:0] inverse_stream_i;
  wire signed [DATA_WIDTH-1:0] inverse_stream_q;
  wire [8:0] inverse_stream_position;
  wire [4:0] inverse_stream_forward_exponent;
  wire [63:0] inverse_stream_block_start;
  wire inverse_stream_last;
  wire transform_fifo_fault;
  wire inverse_forward_exponent_error_now;
  reg inverse_forward_exponent_seen;
  reg [4:0] inverse_forward_exponent;
  reg forward_exponent_fault_latched;

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
  (* ASYNC_REG = "TRUE" *) reg [1:0] fft_reset_release_sync;
  always @(posedge clk or negedge fft_resetn)
    if (!fft_resetn) fft_reset_release_sync <= 0;
    else fft_reset_release_sync <= {fft_reset_release_sync[0], 1'b1};
  wire fft_reset_released = fft_reset_release_sync[1];

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
                           !flush && fft_reset_released &&
                           !scheduler_flush_pulse && !pipeline_flush;

  assign product_overflow_fault = product_output_valid &&
                                  product_output_overflow;
  assign forward_exponent_fault = forward_exponent_fault_latched;
  assign inverse_input_valid = inverse_stream_valid &&
                               !inverse_forward_exponent_error_now;
  assign product_output_ready = product_output_overflow ? 1'b1 :
                                transform_fifo_input_ready;
  assign inverse_input_accept = inverse_input_valid && inverse_input_ready;
  assign inverse_stream_ready = inverse_forward_exponent_error_now ? 1'b1 :
                                inverse_input_ready;
  assign inverse_output_accept = inverse_output_valid && inverse_output_ready;

  // A following block may already be waiting in the registered transform
  // FIFO while the inverse core publishes the prior block.  Validate its
  // exponent lifecycle only when the inverse adapter can actually consume the
  // beat; otherwise a legitimate queued position zero would look like an
  // overlapping block.
  assign inverse_forward_exponent_error_now = inverse_stream_valid &&
    inverse_input_ready &&
    ((inverse_stream_position == 0) ? inverse_forward_exponent_seen :
     (!inverse_forward_exponent_seen ||
      inverse_stream_forward_exponent != inverse_forward_exponent));

  assign scheduler_fft_ready = forward_adapter_input_ready;

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
                       inverse_forward_exponent_error_now ||
                       forward_exponent_fault_latched ||
                       transform_fifo_fault || path_fault ||
                       candidate_backpressure_fault ||
                       scheduler_overflow_pulse ||
                       (pipeline_active && !fft_reset_released);

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

  // One in-flight block per direction preserves the existing exponent/energy
  // lifecycles. Once a block starts filling the mailbox its grant cannot change.
  reg grant_active, grant_inverse;
  reg forward_busy, inverse_busy;
  wire choose_inverse = grant_active ? grant_inverse :
      (inverse_stream_valid && !inverse_busy);
  wire choose_forward = grant_active ? !grant_inverse :
      (!choose_inverse && scheduler_fft_valid && !forward_busy);
  wire shared_input_ready, shared_output_valid, shared_output_last;
  wire [35:0] shared_output_data;
  wire [8:0] shared_output_position;
  wire [74:0] shared_output_metadata;
  wire shared_fault;
  wire shared_input_valid = choose_inverse ? inverse_input_valid :
      (choose_forward && scheduler_fft_valid);
  wire shared_input_last = choose_inverse ? inverse_stream_last : scheduler_fft_last;
  wire shared_input_accept = shared_input_valid && shared_input_ready;
  wire shared_output_inverse = shared_output_metadata[74];
  wire shared_exponent_error = shared_output_valid && shared_output_inverse &&
      shared_output_metadata[9:5] != inverse_forward_exponent;
  assign forward_adapter_input_ready = choose_forward && shared_input_ready;
  assign inverse_input_ready = choose_inverse && shared_input_ready;
  // The legacy forward fault port represents a shared-service fault in THIS
  // experimental composition only. No production health ABI is changed.
  assign forward_fft_fault = shared_fault || shared_exponent_error;
  assign inverse_fft_fault = 1'b0;
  assign forward_output_valid = shared_output_valid && !shared_output_inverse;
  assign inverse_output_valid = shared_output_valid && shared_output_inverse && !shared_exponent_error;
  assign forward_output_i = shared_output_data[17:0];
  assign forward_output_q = shared_output_data[35:18];
  assign inverse_output_i = shared_output_data[17:0];
  assign inverse_output_q = shared_output_data[35:18];
  assign forward_output_position = shared_output_position;
  assign inverse_output_position = shared_output_position;
  assign forward_output_last = shared_output_last;
  assign inverse_output_last = shared_output_last;
  assign forward_output_block_start = shared_output_metadata[73:10];
  assign inverse_output_block_start = shared_output_metadata[73:10];
  assign forward_output_exponent = shared_output_metadata[4:0];
  assign inverse_output_exponent = shared_output_metadata[4:0];
  // Explicit experimental selector; the original nonrealtime implementation
  // remains the default. Arithmetic and both sides of this interface are shared.
  generate if (USE_REALTIME_XFFT == 1) begin : realtime_transform
  starlink_pss_shared_realtime_xfft_service transform_service (
    .clk(clk), .resetn(pipeline_resetn), .fft_clk(fft_clk), .fft_resetn(fft_resetn),
    .input_valid(shared_input_valid), .input_ready(shared_input_ready),
    .input_data(choose_inverse ? {inverse_stream_q, inverse_stream_i} :
                                 {scheduler_fft_q, 2'b00, scheduler_fft_i, 2'b00}),
    .input_position(choose_inverse ? inverse_stream_position : scheduler_fft_position),
    .input_last(shared_input_last),
    .input_metadata(choose_inverse ?
      {1'b1, inverse_stream_block_start, inverse_stream_forward_exponent} :
      {1'b0, scheduler_fft_block_start, 5'b0}),
    .output_valid(shared_output_valid),
    .output_ready(shared_output_inverse ? inverse_output_ready : forward_output_ready),
    .output_data(shared_output_data), .output_position(shared_output_position),
    .output_last(shared_output_last), .output_metadata(shared_output_metadata),
    .service_fault(shared_fault)
  );
  end else begin : nonrealtime_transform
  starlink_pss_shared_xfft_service transform_service (
    .clk(clk), .resetn(pipeline_resetn), .fft_clk(fft_clk), .fft_resetn(fft_resetn),
    .input_valid(shared_input_valid), .input_ready(shared_input_ready),
    .input_data(choose_inverse ? {inverse_stream_q, inverse_stream_i} :
                                 {scheduler_fft_q, 2'b00, scheduler_fft_i, 2'b00}),
    .input_position(choose_inverse ? inverse_stream_position : scheduler_fft_position),
    .input_last(shared_input_last),
    .input_metadata(choose_inverse ?
      {1'b1, inverse_stream_block_start, inverse_stream_forward_exponent} :
      {1'b0, scheduler_fft_block_start, 5'b0}),
    .output_valid(shared_output_valid),
    .output_ready(shared_output_inverse ? inverse_output_ready : forward_output_ready),
    .output_data(shared_output_data), .output_position(shared_output_position),
    .output_last(shared_output_last), .output_metadata(shared_output_metadata),
    .service_fault(shared_fault)
  );
  end endgenerate
  initial begin
    if (USE_REALTIME_XFFT != 0 && USE_REALTIME_XFFT != 1)
      $fatal(1, "USE_REALTIME_XFFT must be 0 or 1");
  end
  always @(posedge clk) begin
    if (!pipeline_resetn) begin
      grant_active <= 0;
      grant_inverse <= 0;
      forward_busy <= 0;
      inverse_busy <= 0;
    end else begin
      if (shared_input_accept) begin
        grant_active <= !shared_input_last;
        if (!grant_active) begin
          grant_inverse <= choose_inverse;
          if (choose_inverse) inverse_busy <= 1;
          else forward_busy <= 1;
        end
      end
      if (forward_output_valid && forward_output_ready && forward_output_last) forward_busy <= 0;
      if (inverse_output_accept && inverse_output_last) inverse_busy <= 0;
    end
  end

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

  starlink_pss_transform_fifo #(
    .DATA_WIDTH(DATA_WIDTH)
  ) transform_fifo (
    .clk                      (clk),
    .resetn                   (pipeline_resetn),
    .flush                    (pipeline_flush),
    .input_valid              (product_output_valid &&
                               !product_output_overflow),
    .input_ready              (transform_fifo_input_ready),
    .input_i                  (product_output_i),
    .input_q                  (product_output_q),
    .input_position           (product_output_bin_index),
    .input_block_exponent     (product_output_exponent),
    .input_block_start_index  (product_output_block_start),
    .input_last               (product_output_last),
    .output_valid             (inverse_stream_valid),
    .output_ready             (inverse_stream_ready),
    .output_i                 (inverse_stream_i),
    .output_q                 (inverse_stream_q),
    .output_position          (inverse_stream_position),
    .output_block_exponent    (inverse_stream_forward_exponent),
    .output_block_start_index (inverse_stream_block_start),
    .output_last              (inverse_stream_last),
    .stored_count             (),
    .maximum_stored_count     (),
    .protocol_fault           (transform_fifo_fault)
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
    if (!resetn || !enable || !fft_reset_released)
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
        if (inverse_input_accept && inverse_stream_position == 0) begin
          inverse_forward_exponent_seen <= 1'b1;
          inverse_forward_exponent <= inverse_stream_forward_exponent;
        end
        if (inverse_forward_exponent_error_now)
          forward_exponent_fault_latched <= 1'b1;
        if (inverse_output_accept && inverse_output_last)
          inverse_forward_exponent_seen <= 1'b0;
      end
    end
  end

endmodule
