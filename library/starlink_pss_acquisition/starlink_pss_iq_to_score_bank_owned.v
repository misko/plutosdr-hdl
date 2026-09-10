// Additive experimental coarse pipeline. No receiver profile selects this top.
// Scheduler/energy/score arithmetic are unchanged; the three-bank island owns
// all forward/product/inverse transactions at fft_clk, including fault fences.
`timescale 1ns/1ps
module starlink_pss_iq_to_score_bank_owned #(
  parameter KERNEL_ROM_FILE = "upper_edge_pss_kernel_q17.mem",
  parameter [30:0] COEFFICIENT_ENERGY = 31'd1073742825,
  parameter integer DATA_WIDTH = 18
) (
  input wire clk, resetn, fft_clk, fft_resetn, enable, flush,
  input wire sample_valid, sample_gap,
  input wire signed [15:0] sample_i, sample_q,
  input wire [63:0] sample_index,
  output wire score_valid,
  input wire score_ready,
  output wire [7:0] score_value,
  output wire [63:0] score_start_index,
  output wire score_denominator_zero,
  output reg detector_fault,
  output wire scheduler_gap_pulse, scheduler_index_error_pulse,
  output wire scheduler_overflow_pulse,
  output wire forward_fft_fault, kernel_join_fault, product_overflow_fault,
  output wire inverse_fft_fault, forward_exponent_fault, candidate_path_fault,
  output wire [9:0] candidate_fifo_stored_count,
  output wire [9:0] candidate_fifo_maximum_stored_count
);
  reg pipeline_active;
  (* ASYNC_REG = "TRUE" *) reg [1:0] fft_reset_release_sync;
  always @(posedge clk or negedge fft_resetn)
    if (!fft_resetn) fft_reset_release_sync <= 0;
    else fft_reset_release_sync <= {fft_reset_release_sync[0], 1'b1};
  wire fft_reset_released = fft_reset_release_sync[1];
  wire effective_enable = enable && !detector_fault;
  wire scheduler_enable = effective_enable && !flush && pipeline_active;
  wire pipeline_resetn = pipeline_active;
  wire pipeline_flush = !pipeline_active;
  wire scheduler_flush_pulse;
  wire interfaces_open = resetn && effective_enable && pipeline_active &&
    !flush && fft_reset_released && !scheduler_flush_pulse && !pipeline_flush;
  wire scheduler_fft_valid, scheduler_fft_ready, scheduler_fft_last;
  wire signed [15:0] scheduler_fft_i, scheduler_fft_q;
  wire [8:0] scheduler_fft_position;
  wire [63:0] scheduler_fft_block_start;
  wire island_valid, island_fault;
  wire [35:0] island_data;
  wire [8:0] inverse_output_position;
  wire inverse_output_last;
  wire [74:0] island_metadata;
  wire inverse_descriptor_error = island_valid && !island_metadata[74];
  wire inverse_output_valid = island_valid && !inverse_descriptor_error;
  wire inverse_output_ready = 1'b1;
  wire signed [17:0] inverse_output_i = island_data[17:0];
  wire signed [17:0] inverse_output_q = island_data[35:18];
  wire [63:0] inverse_output_block_start = island_metadata[73:10];
  wire [4:0] inverse_forward_exponent = island_metadata[9:5];
  wire [4:0] inverse_output_exponent = island_metadata[4:0];
  reg inverse_stage_valid;
  reg signed [17:0] inverse_stage_i, inverse_stage_q;
  reg [8:0] inverse_stage_position;
  reg [4:0] inverse_stage_forward_exponent, inverse_stage_exponent;
  reg [63:0] inverse_stage_block_start;
  reg inverse_stage_last;
  wire candidate_ifft_ready;
  wire candidate_backpressure_fault = inverse_stage_valid && !candidate_ifft_ready;
  wire cache_lookup_valid_from_path, cache_lookup_ready_to_path;
  wire [63:0] cache_lookup_start_from_path;
  wire cache_output_valid, cache_output_ready;
  wire [37:0] cache_output_energy;
  wire [63:0] cache_output_start;
  wire cache_output_found, path_score_valid, path_fault;
  // Compatibility diagnostics: as in the shared-service experimental top,
  // forward_fft_fault means synchronized aggregate transform-island fault.
  // Kernel/product/exponent faults remain checked and sticky INSIDE island;
  // no unsynchronized fast-domain pulse is exported as a slow-domain cause.
  assign forward_fft_fault = island_fault;
  assign kernel_join_fault = 1'b0;
  assign product_overflow_fault = 1'b0;
  assign forward_exponent_fault = 1'b0;
  assign inverse_fft_fault = inverse_descriptor_error;
  assign candidate_path_fault = path_fault || candidate_backpressure_fault;
  assign score_valid = path_score_valid && interfaces_open;
  wire fault_event = island_fault || inverse_descriptor_error || path_fault ||
    candidate_backpressure_fault || scheduler_overflow_pulse ||
    (pipeline_active && !fft_reset_released);
  initial if (DATA_WIDTH != 18)
    $fatal(1, "generated bank-owned XFFT requires DATA_WIDTH=18");

  starlink_pss_overlap_scheduler scheduler (
    .clk(clk), .resetn(pipeline_resetn), .enable(scheduler_enable),
    .sample_valid(sample_valid), .sample_gap(sample_gap), .sample_i(sample_i),
    .sample_q(sample_q), .sample_index(sample_index),
    .fft_valid(scheduler_fft_valid), .fft_ready(scheduler_fft_ready),
    .fft_i(scheduler_fft_i), .fft_q(scheduler_fft_q),
    .fft_position(scheduler_fft_position), .fft_last(scheduler_fft_last),
    .fft_block_start_index(scheduler_fft_block_start),
    .flush_pulse(scheduler_flush_pulse), .gap_pulse(scheduler_gap_pulse),
    .index_error_pulse(scheduler_index_error_pulse),
    .overflow_pulse(scheduler_overflow_pulse), .block_queued_pulse(),
    .block_complete_pulse(), .busy(), .segment_sample_count(), .queued_block_count()
  );
  starlink_pss_energy_cache energy_cache (
    .clk(clk), .resetn(pipeline_resetn), .enable(effective_enable),
    .flush(pipeline_flush), .sample_valid(sample_valid), .sample_gap(sample_gap),
    .sample_i(sample_i), .sample_q(sample_q), .sample_index(sample_index),
    .lookup_valid(cache_lookup_valid_from_path), .lookup_ready(cache_lookup_ready_to_path),
    .lookup_start_index(cache_lookup_start_from_path), .output_valid(cache_output_valid),
    .output_ready(cache_output_ready), .output_energy(cache_output_energy),
    .output_start_index(cache_output_start), .output_found(cache_output_found),
    .energy_write_pulse(), .energy_write_value(), .energy_write_start_index(),
    .gap_pulse(), .index_error_pulse(), .restart_pulse(), .retention_miss_pulse(),
    .stored_energy_count(), .oldest_energy_start_index(), .newest_energy_start_index()
  );
  starlink_pss_fft_bank_owned_slice #(.KERNEL_ROM_FILE(KERNEL_ROM_FILE)) island (
    .clk(clk), .resetn(pipeline_resetn), .fft_clk(fft_clk), .fft_resetn(fft_resetn),
    .input_valid(scheduler_fft_valid), .input_ready(scheduler_fft_ready),
    .input_data({scheduler_fft_q, 2'b00, scheduler_fft_i, 2'b00}),
    .input_position(scheduler_fft_position), .input_last(scheduler_fft_last),
    .input_block_start(scheduler_fft_block_start), .output_valid(island_valid),
    .output_ready(inverse_output_ready), .output_data(island_data),
    .output_position(inverse_output_position), .output_last(inverse_output_last),
    .output_metadata(island_metadata), .fault(island_fault)
  );
  // Preserve the original non-backpressured inverse timing register and the
  // independent downstream 512-position/exponent/start/TLAST qualification.
  // The full 447-candidate burst fits the unchanged 512-entry candidate FIFO;
  // a violated bounded-ready contract faults instead of overwriting silently.
  always @(posedge clk) begin
    if (!pipeline_resetn) begin
      inverse_stage_valid <= 0;
      inverse_stage_i <= 0; inverse_stage_q <= 0; inverse_stage_position <= 0;
      inverse_stage_forward_exponent <= 0; inverse_stage_exponent <= 0;
      inverse_stage_block_start <= 0; inverse_stage_last <= 0;
    end else begin
      inverse_stage_valid <= inverse_output_valid;
      if (inverse_output_valid) begin
        inverse_stage_i <= inverse_output_i; inverse_stage_q <= inverse_output_q;
        inverse_stage_position <= inverse_output_position;
        inverse_stage_forward_exponent <= inverse_forward_exponent;
        inverse_stage_exponent <= inverse_output_exponent;
        inverse_stage_block_start <= inverse_output_block_start;
        inverse_stage_last <= inverse_output_last;
      end
    end
  end
  starlink_pss_candidate_score_path #(
    .COEFFICIENT_ENERGY(COEFFICIENT_ENERGY), .DATA_WIDTH(DATA_WIDTH)
  ) candidate_score_path (
    .clk(clk), .resetn(pipeline_resetn), .flush(pipeline_flush),
    .ifft_valid(inverse_stage_valid), .ifft_ready(candidate_ifft_ready),
    .ifft_correlation_i(inverse_stage_i), .ifft_correlation_q(inverse_stage_q),
    .ifft_index(inverse_stage_position), .forward_exponent(inverse_stage_forward_exponent),
    .inverse_exponent(inverse_stage_exponent), .block_start_index(inverse_stage_block_start),
    .ifft_last(inverse_stage_last), .cache_lookup_valid(cache_lookup_valid_from_path),
    .cache_lookup_ready(cache_lookup_ready_to_path),
    .cache_lookup_start_index(cache_lookup_start_from_path),
    .cache_output_valid(cache_output_valid), .cache_output_ready(cache_output_ready),
    .cache_output_energy(cache_output_energy), .cache_output_start_index(cache_output_start),
    .cache_output_found(cache_output_found), .score_valid(path_score_valid),
    .score_ready(score_ready), .score_value(score_value), .score_start_index(score_start_index),
    .score_denominator_zero(score_denominator_zero), .path_fault(path_fault),
    .ifft_protocol_fault(), .fifo_overflow_fault(), .energy_join_fault(),
    .fifo_stored_count(candidate_fifo_stored_count),
    .fifo_maximum_stored_count(candidate_fifo_maximum_stored_count)
  );
  // Retain legacy scheduler-gap restart (discard all retained transactions),
  // explicit enable/flush recovery and sticky detector-fault behavior.
  always @(posedge clk) begin
    if (!resetn || !enable || !fft_reset_released) pipeline_active <= 0;
    else if (flush || scheduler_flush_pulse || fault_event || detector_fault)
      pipeline_active <= 0;
    else pipeline_active <= 1;
    if (!resetn || !enable || flush) detector_fault <= 0;
    else if (fault_event) detector_fault <= 1;
  end
endmodule
