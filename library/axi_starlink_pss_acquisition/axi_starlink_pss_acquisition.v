// SPDX-License-Identifier: GPL-2.0
//
// Complete read-only 15/30/60 MS/s acquisition boundary for the Pluto RX shell.
//
// The source stream is observed without ready/backpressure. A loss-detecting
// dual-clock FIFO crosses accepted CI16 samples into the 100 MHz AXI/acquisition
// domain, where the continuous XFFT score path fills immutable phase maps. The
// PSMA bridge is the only processor interface.

`timescale 1ns/1ps

module axi_starlink_pss_acquisition #(
  parameter integer SAMPLE_FIFO_ADDRESS_WIDTH = 7,
  parameter integer INPUT_RATE_MSPS = 15
) (
  input  wire                 sample_clk,
  input  wire                 sample_reset,
  input  wire                 sample_strobe,
  input  wire                 sample_enable,
  input  wire                 sample_gap,
  input  wire signed [15:0]   sample_i,
  input  wire signed [15:0]   sample_q,
  input  wire [63:0]          sample_index,

  output wire                 irq,

  input  wire                 s_axi_aclk,
  input  wire                 s_axi_aresetn,
  input  wire                 s_axi_awvalid,
  input  wire [7:0]           s_axi_awaddr,
  output wire                 s_axi_awready,
  input  wire                 s_axi_wvalid,
  input  wire [31:0]          s_axi_wdata,
  input  wire [3:0]           s_axi_wstrb,
  output wire                 s_axi_wready,
  output wire                 s_axi_bvalid,
  output wire [1:0]           s_axi_bresp,
  input  wire                 s_axi_bready,
  input  wire                 s_axi_arvalid,
  input  wire [7:0]           s_axi_araddr,
  output wire                 s_axi_arready,
  output wire                 s_axi_rvalid,
  output wire [1:0]           s_axi_rresp,
  output wire [31:0]          s_axi_rdata,
  input  wire                 s_axi_rready,
  input  wire [2:0]           s_axi_awprot,
  input  wire [2:0]           s_axi_arprot
);

  // Convert the shell's active-high sample reset into a registered,
  // asynchronously asserted and synchronously released active-low reset. The
  // CDC block then combines this source epoch with the independent AXI epoch.
  (* ASYNC_REG = "TRUE", SHREG_EXTRACT = "NO" *)
  reg [1:0] sample_reset_release;
  always @(posedge sample_clk or posedge sample_reset) begin
    if (sample_reset)
      sample_reset_release <= 2'b00;
    else
      sample_reset_release <= {sample_reset_release[0], 1'b1};
  end

  wire source_resetn = sample_reset_release[1];
  wire source_sample_valid = sample_strobe && sample_enable;
  wire source_fifo_full;
  wire ingress_sample_valid;
  wire ingress_sample_gap;
  wire signed [15:0] ingress_sample_i;
  wire signed [15:0] ingress_sample_q;
  wire [63:0] ingress_sample_index;
  wire [31:0] ingress_dropped_sample_count;
  wire ingress_overflow_sticky;
  wire [SAMPLE_FIFO_ADDRESS_WIDTH:0] ingress_fifo_level;
  wire [SAMPLE_FIFO_ADDRESS_WIDTH:0] ingress_maximum_fifo_level;

  starlink_pss_sample_cdc #(
    .FIFO_ADDRESS_WIDTH(SAMPLE_FIFO_ADDRESS_WIDTH)
  ) sample_cdc (
    .source_clk                 (sample_clk),
    .source_resetn              (source_resetn),
    .source_sample_valid        (source_sample_valid),
    .source_sample_gap          (sample_gap),
    .source_sample_i            (sample_i),
    .source_sample_q            (sample_q),
    .source_sample_index        (sample_index),
    .source_fifo_full           (source_fifo_full),
    .acquisition_clk            (s_axi_aclk),
    .acquisition_resetn         (s_axi_aresetn),
    .acquisition_sample_valid   (ingress_sample_valid),
    .acquisition_sample_gap     (ingress_sample_gap),
    .acquisition_sample_i       (ingress_sample_i),
    .acquisition_sample_q       (ingress_sample_q),
    .acquisition_sample_index   (ingress_sample_index),
    .dropped_sample_count       (ingress_dropped_sample_count),
    .overflow_sticky            (ingress_overflow_sticky),
    .fifo_level                 (ingress_fifo_level),
    .maximum_fifo_level         (ingress_maximum_fifo_level)
  );

  wire acquisition_enable;
  wire acquisition_flush;
  wire [1:0] map_ready_mask;
  wire [31:0] map_generation_0;
  wire [31:0] map_generation_1;
  wire [63:0] map_start_index_0;
  wire [63:0] map_start_index_1;
  wire map_read_request;
  wire map_read_bank;
  wire [14:0] map_read_index;
  wire map_read_valid;
  wire [15:0] map_read_data;
  wire map_read_error;
  wire map_release;
  wire map_release_bank;
  wire [9:0] candidate_fifo_stored_count;
  wire [9:0] candidate_fifo_maximum_stored_count;
  wire [31:0] detector_health_flags;
  wire [31:0] scheduler_gap_count;
  wire [31:0] scheduler_index_error_count;
  wire [31:0] scheduler_overflow_count;
  wire [31:0] detector_fault_count;
  wire [31:0] score_phase_index_discontinuity_count;
  wire [31:0] score_denominator_zero_count;
  wire [31:0] accepted_score_count;
  wire [31:0] discarded_score_count;
  wire [31:0] discontinuity_abort_count;
  wire [31:0] map_publish_count;
  wire [31:0] map_overrun_count;
  wire [31:0] score_protocol_error_count;
  wire [31:0] map_arithmetic_overflow_count;
  wire [31:0] map_read_error_count;
  wire [31:0] map_release_error_count;

  wire acquisition_sample_valid;
  wire acquisition_sample_gap;
  wire signed [15:0] acquisition_sample_i;
  wire signed [15:0] acquisition_sample_q;
  wire [63:0] acquisition_sample_index;
  wire [31:0] ddc_accepted_sample_count;
  wire [31:0] ddc_emitted_sample_count;
  wire [31:0] ddc_discontinuity_count;
  wire [31:0] ddc_saturation_event_count;

  localparam ACQUISITION_KERNEL_ROM_FILE =
      (INPUT_RATE_MSPS == 60) ?
      "upper_edge_pss60_x4_ddc_kernel_q17.mem" :
      ((INPUT_RATE_MSPS == 30) ?
       "upper_edge_pss30_x2_ddc_kernel_q17.mem" :
       "upper_edge_pss_kernel_q17.mem");
  localparam [30:0] ACQUISITION_COEFFICIENT_ENERGY =
      (INPUT_RATE_MSPS == 60) ? 31'd1073765335 :
      ((INPUT_RATE_MSPS == 30) ? 31'd1073744004 : 31'd1073742825);

  generate
    if ((INPUT_RATE_MSPS != 15) && (INPUT_RATE_MSPS != 30) &&
        (INPUT_RATE_MSPS != 60)) begin : g_invalid_rate
      initial $fatal(1, "INPUT_RATE_MSPS must be 15, 30, or 60");
    end

    if (INPUT_RATE_MSPS == 15) begin : g_rate_15
      assign acquisition_sample_valid = ingress_sample_valid;
      assign acquisition_sample_gap = ingress_sample_gap;
      assign acquisition_sample_i = ingress_sample_i;
      assign acquisition_sample_q = ingress_sample_q;
      assign acquisition_sample_index = ingress_sample_index;
      assign ddc_accepted_sample_count = 32'd0;
      assign ddc_emitted_sample_count = 32'd0;
      assign ddc_discontinuity_count = 32'd0;
      assign ddc_saturation_event_count = 32'd0;
    end else if (INPUT_RATE_MSPS == 30) begin : g_rate_30
      starlink_pss_x2_ddc #(
        .EDGE_UPPER(1)
      ) acquisition_ddc (
        .clk                    (s_axi_aclk),
        .resetn                 (s_axi_aresetn),
        .enable                 (acquisition_enable),
        .flush                  (acquisition_flush),
        .input_valid            (ingress_sample_valid),
        .input_gap              (ingress_sample_gap),
        .input_i                (ingress_sample_i),
        .input_q                (ingress_sample_q),
        .input_index            (ingress_sample_index),
        .output_enable          (),
        .output_valid           (acquisition_sample_valid),
        .output_gap             (acquisition_sample_gap),
        .output_i               (acquisition_sample_i),
        .output_q               (acquisition_sample_q),
        .output_index           (acquisition_sample_index),
        .accepted_sample_count  (ddc_accepted_sample_count),
        .emitted_sample_count   (ddc_emitted_sample_count),
        .discontinuity_count    (ddc_discontinuity_count),
        .saturation_event_count (ddc_saturation_event_count)
      );
    end else begin : g_rate_60
      wire stage_30_valid;
      wire stage_30_gap;
      wire signed [15:0] stage_30_i;
      wire signed [15:0] stage_30_q;
      wire [63:0] stage_30_index;
      wire [31:0] stage_60_accepted_count;
      wire [31:0] stage_60_emitted_count;
      wire [31:0] stage_60_discontinuity_count;
      wire [31:0] stage_60_saturation_count;
      wire [31:0] stage_30_accepted_count;
      wire [31:0] stage_30_emitted_count;
      wire [31:0] stage_30_discontinuity_count;
      wire [31:0] stage_30_saturation_count;
      wire [32:0] saturation_sum =
          {1'b0, stage_60_saturation_count} +
          {1'b0, stage_30_saturation_count};

      // Both stages use the same absolute-index Fs/4 mixer and half-band FIR.
      // The first translates and decimates 60->30 MS/s; the second performs
      // the already-qualified 30->15 MS/s operation.  The final index k maps
      // exactly to raw source center 4*k (21 raw input samples of latency).
      starlink_pss_x2_ddc #(
        .EDGE_UPPER(1)
      ) acquisition_ddc_60_to_30 (
        .clk                    (s_axi_aclk),
        .resetn                 (s_axi_aresetn),
        .enable                 (acquisition_enable),
        .flush                  (acquisition_flush),
        .input_valid            (ingress_sample_valid),
        .input_gap              (ingress_sample_gap),
        .input_i                (ingress_sample_i),
        .input_q                (ingress_sample_q),
        .input_index            (ingress_sample_index),
        .output_enable          (),
        .output_valid           (stage_30_valid),
        .output_gap             (stage_30_gap),
        .output_i               (stage_30_i),
        .output_q               (stage_30_q),
        .output_index           (stage_30_index),
        .accepted_sample_count  (stage_60_accepted_count),
        .emitted_sample_count   (stage_60_emitted_count),
        .discontinuity_count    (stage_60_discontinuity_count),
        .saturation_event_count (stage_60_saturation_count)
      );

      starlink_pss_x2_ddc #(
        .EDGE_UPPER(1)
      ) acquisition_ddc_30_to_15 (
        .clk                    (s_axi_aclk),
        .resetn                 (s_axi_aresetn),
        .enable                 (acquisition_enable),
        .flush                  (acquisition_flush),
        .input_valid            (stage_30_valid),
        .input_gap              (stage_30_gap),
        .input_i                (stage_30_i),
        .input_q                (stage_30_q),
        .input_index            (stage_30_index),
        .output_enable          (),
        .output_valid           (acquisition_sample_valid),
        .output_gap             (acquisition_sample_gap),
        .output_i               (acquisition_sample_i),
        .output_q               (acquisition_sample_q),
        .output_index           (acquisition_sample_index),
        .accepted_sample_count  (stage_30_accepted_count),
        .emitted_sample_count   (stage_30_emitted_count),
        .discontinuity_count    (stage_30_discontinuity_count),
        .saturation_event_count (stage_30_saturation_count)
      );

      assign ddc_accepted_sample_count = stage_60_accepted_count;
      assign ddc_emitted_sample_count = stage_30_emitted_count;
      assign ddc_discontinuity_count = stage_30_discontinuity_count;
      assign ddc_saturation_event_count = saturation_sum[32] ?
          32'hffff_ffff : saturation_sum[31:0];

      wire unused_stage_counters = ^{
        stage_60_emitted_count, stage_60_discontinuity_count,
        stage_30_accepted_count
      };
    end
  endgenerate

  starlink_pss_iq_to_phase_map #(
    .KERNEL_ROM_FILE   (ACQUISITION_KERNEL_ROM_FILE),
    .COEFFICIENT_ENERGY(ACQUISITION_COEFFICIENT_ENERGY)
  ) acquisition (
    .clk                                  (s_axi_aclk),
    .resetn                               (s_axi_aresetn),
    .enable                               (acquisition_enable),
    .flush                                (acquisition_flush),
    .sample_valid                         (acquisition_sample_valid),
    .sample_gap                           (acquisition_sample_gap),
    .sample_i                             (acquisition_sample_i),
    .sample_q                             (acquisition_sample_q),
    .sample_index                         (acquisition_sample_index),
    .map_ready_mask                       (map_ready_mask),
    .map_generation_0                     (map_generation_0),
    .map_generation_1                     (map_generation_1),
    .map_start_index_0                    (map_start_index_0),
    .map_start_index_1                    (map_start_index_1),
    .map_read_request                     (map_read_request),
    .map_read_bank                        (map_read_bank),
    .map_read_index                       (map_read_index),
    .map_read_valid                       (map_read_valid),
    .map_read_data                        (map_read_data),
    .map_read_error                       (map_read_error),
    .map_release                          (map_release),
    .map_release_bank                     (map_release_bank),
    .score_valid                          (),
    .score_value                          (),
    .score_start_index                    (),
    .score_phase                          (),
    .score_denominator_zero               (),
    .detector_fault                       (),
    .scheduler_gap_pulse                  (),
    .scheduler_index_error_pulse          (),
    .scheduler_overflow_pulse             (),
    .forward_fft_fault                    (),
    .kernel_join_fault                    (),
    .product_overflow_fault               (),
    .inverse_fft_fault                    (),
    .forward_exponent_fault               (),
    .candidate_path_fault                 (),
    .candidate_fifo_stored_count          (candidate_fifo_stored_count),
    .candidate_fifo_maximum_stored_count  (candidate_fifo_maximum_stored_count),
    .score_phase_index_discontinuity_count(score_phase_index_discontinuity_count),
    .scheduler_gap_count                  (scheduler_gap_count),
    .scheduler_index_error_count          (scheduler_index_error_count),
    .scheduler_overflow_count             (scheduler_overflow_count),
    .detector_fault_count                 (detector_fault_count),
    .score_denominator_zero_count         (score_denominator_zero_count),
    .detector_health_flags                (detector_health_flags),
    .accepted_score_count                 (accepted_score_count),
    .discarded_score_count                (discarded_score_count),
    .discontinuity_abort_count            (discontinuity_abort_count),
    .map_publish_count                    (map_publish_count),
    .map_overrun_count                    (map_overrun_count),
    .score_protocol_error_count           (score_protocol_error_count),
    .map_arithmetic_overflow_count        (map_arithmetic_overflow_count),
    .map_read_error_count                 (map_read_error_count),
    .map_release_error_count              (map_release_error_count)
  );

  axi_starlink_pss_phase_map_sync #(
    .INPUT_RATE_MSPS    (INPUT_RATE_MSPS),
    .COEFFICIENT_ENERGY(ACQUISITION_COEFFICIENT_ENERGY)
  ) phase_map_control (
    .map_clk                              (s_axi_aclk),
    .map_reset                            (!s_axi_aresetn),
    .map_ready_mask                       (map_ready_mask),
    .map_generation_0                     (map_generation_0),
    .map_generation_1                     (map_generation_1),
    .map_start_index_0                    (map_start_index_0),
    .map_start_index_1                    (map_start_index_1),
    .map_read_request                     (map_read_request),
    .map_read_bank                        (map_read_bank),
    .map_read_index                       (map_read_index),
    .map_read_valid                       (map_read_valid),
    .map_read_data                        (map_read_data),
    .map_read_error                       (map_read_error),
    .map_release                          (map_release),
    .map_release_bank                     (map_release_bank),
    .accepted_score_count                 (accepted_score_count),
    .discarded_score_count                (discarded_score_count),
    .discontinuity_abort_count            (discontinuity_abort_count),
    .map_publish_count                    (map_publish_count),
    .map_overrun_count                    (map_overrun_count),
    .score_protocol_error_count           (score_protocol_error_count),
    .map_arithmetic_overflow_count        (map_arithmetic_overflow_count),
    .map_read_error_count                 (map_read_error_count),
    .map_release_error_count              (map_release_error_count),
    .detector_health_flags                (detector_health_flags),
    .ingress_overflow_sticky              (ingress_overflow_sticky),
    .ingress_dropped_sample_count         (ingress_dropped_sample_count),
    .ingress_fifo_level                   ({{(15-SAMPLE_FIFO_ADDRESS_WIDTH){1'b0}}, ingress_fifo_level}),
    .ingress_maximum_fifo_level           ({{(15-SAMPLE_FIFO_ADDRESS_WIDTH){1'b0}}, ingress_maximum_fifo_level}),
    .scheduler_gap_count                  (scheduler_gap_count),
    .scheduler_index_error_count          (scheduler_index_error_count),
    .scheduler_overflow_count             (scheduler_overflow_count),
    .detector_fault_count                 (detector_fault_count),
    .score_phase_index_discontinuity_count(score_phase_index_discontinuity_count),
    .score_denominator_zero_count         (score_denominator_zero_count),
    .candidate_fifo_stored_count          (candidate_fifo_stored_count),
    .candidate_fifo_maximum_stored_count  (candidate_fifo_maximum_stored_count),
    .ddc_accepted_sample_count            (ddc_accepted_sample_count),
    .ddc_emitted_sample_count             (ddc_emitted_sample_count),
    .ddc_discontinuity_count              (ddc_discontinuity_count),
    .ddc_saturation_event_count           (ddc_saturation_event_count),
    .acquisition_enable                   (acquisition_enable),
    .acquisition_flush                    (acquisition_flush),
    .irq                                  (irq),
    .s_axi_aclk                           (s_axi_aclk),
    .s_axi_aresetn                        (s_axi_aresetn),
    .s_axi_awvalid                        (s_axi_awvalid),
    .s_axi_awaddr                         (s_axi_awaddr),
    .s_axi_awready                        (s_axi_awready),
    .s_axi_wvalid                         (s_axi_wvalid),
    .s_axi_wdata                          (s_axi_wdata),
    .s_axi_wstrb                          (s_axi_wstrb),
    .s_axi_wready                         (s_axi_wready),
    .s_axi_bvalid                         (s_axi_bvalid),
    .s_axi_bresp                          (s_axi_bresp),
    .s_axi_bready                         (s_axi_bready),
    .s_axi_arvalid                        (s_axi_arvalid),
    .s_axi_araddr                         (s_axi_araddr),
    .s_axi_arready                        (s_axi_arready),
    .s_axi_rvalid                         (s_axi_rvalid),
    .s_axi_rresp                          (s_axi_rresp),
    .s_axi_rdata                          (s_axi_rdata),
    .s_axi_rready                         (s_axi_rready),
    .s_axi_awprot                         (s_axi_awprot),
    .s_axi_arprot                         (s_axi_arprot)
  );

endmodule
