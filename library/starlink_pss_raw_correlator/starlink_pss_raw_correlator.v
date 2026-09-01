// SPDX-License-Identifier: GPL-2.0
//
// First exact-PSS arithmetic milestone for the experimental RX-only branch.
// This is deliberately an engine-clock-only raw correlator.  It has no AXI,
// CDC, CFO/NCO, winner reduction, or connection to the Pluto sample path.
//
// Contract:
//   * load one sequential 66-tap signed CI16/Q1.15 coefficient bank;
//   * load exactly 130 signed CI16 samples and their raw 64-bit timestamps;
//   * emit 65 lags, -32 through +32, in ascending order;
//   * correlate sum(x * conj(h)) in ascending tap order;
//   * saturate C_re, C_im, Ex, and Eh to signed 48 bits after every tap; and
//   * report the stored timestamp belonging to each window's first tap.
//
// Exactly three registered signed multipliers are shared by coefficient
// energy, sample energy, and the three-product Gauss complex multiply.  There
// are intentionally no other multiplication operators in this module.

`timescale 1ns/1ps

module starlink_pss_raw_correlator (
  input  wire               i_clk,
  input  wire               i_reset,

  // Coefficients are accepted sequentially, tap 0 through tap 65.  Clear is
  // accepted only while idle and also discards any captured samples.
  input  wire               i_coefficient_clear,
  input  wire               i_coefficient_valid,
  output wire               o_coefficient_ready,
  input  wire signed [15:0] i_coefficient_i,
  input  wire signed [15:0] i_coefficient_q,

  // Samples are accepted sequentially, capture slot 0 through slot 129.
  // Each timestamp is stored, not reconstructed from engine latency.
  input  wire               i_sample_clear,
  input  wire               i_sample_valid,
  output wire               o_sample_ready,
  input  wire signed [15:0] i_sample_i,
  input  wire signed [15:0] i_sample_q,
  input  wire        [63:0] i_sample_timestamp,

  input  wire               i_start,
  output wire               o_start_ready,
  output wire               o_busy,

  output wire               o_result_valid,
  input  wire               i_result_ready,
  output reg  signed  [6:0] o_result_lag,
  output reg         [63:0] o_result_timestamp,
  output reg  signed [47:0] o_result_c_re,
  output reg  signed [47:0] o_result_c_im,
  output reg  signed [47:0] o_result_ex,
  output reg  signed [47:0] o_result_eh,
  output reg          [8:0] o_result_saturation_events,
  output reg                o_done,

  // Load-state visibility is useful to a later register wrapper and keeps
  // incomplete jobs fail-closed without adding an AXI policy here.
  output wire         [6:0] o_coefficient_count,
  output wire         [7:0] o_sample_count
);

  localparam integer COEFFICIENT_COUNT = 66;
  localparam integer CAPTURE_COUNT = 130;
  localparam integer RESULT_COUNT = 65;

  localparam [2:0] STATE_IDLE               = 3'd0;
  localparam [2:0] STATE_COEFFICIENT_ENERGY = 3'd1;
  localparam [2:0] STATE_SAMPLE_ENERGY      = 3'd2;
  localparam [2:0] STATE_CORRELATION        = 3'd3;
  localparam [2:0] STATE_FINALIZE           = 3'd4;
  localparam [2:0] STATE_EMIT               = 3'd5;

  reg [2:0] state;

  reg signed [15:0] coefficient_i_memory [0:COEFFICIENT_COUNT-1];
  reg signed [15:0] coefficient_q_memory [0:COEFFICIENT_COUNT-1];
  reg signed [15:0] sample_i_memory [0:CAPTURE_COUNT-1];
  reg signed [15:0] sample_q_memory [0:CAPTURE_COUNT-1];
  reg        [63:0] sample_timestamp_memory [0:CAPTURE_COUNT-1];

  reg [6:0] coefficient_load_count;
  reg [7:0] sample_load_count;
  reg [6:0] lag_index;

  reg [6:0] phase_issue_count;
  reg [6:0] phase_consume_count;

  reg signed [47:0] coefficient_energy_accumulator;
  reg signed [47:0] sample_energy_accumulator;
  reg signed [47:0] correlation_real_accumulator;
  reg signed [47:0] correlation_imag_accumulator;
  reg         [8:0] coefficient_saturation_count;
  reg         [8:0] sample_saturation_count;
  reg         [8:0] correlation_saturation_count;

  assign o_coefficient_count = coefficient_load_count;
  assign o_sample_count = sample_load_count;
  assign o_busy = (state != STATE_IDLE);
  assign o_result_valid = (state == STATE_EMIT);
  assign o_start_ready =
      (state == STATE_IDLE) &&
      !i_coefficient_clear && !i_sample_clear &&
      (coefficient_load_count == COEFFICIENT_COUNT) &&
      (sample_load_count == CAPTURE_COUNT);
  assign o_coefficient_ready =
      (state == STATE_IDLE) &&
      !i_coefficient_clear && !i_sample_clear && !i_start &&
      (coefficient_load_count < COEFFICIENT_COUNT);
  assign o_sample_ready =
      (state == STATE_IDLE) &&
      !i_coefficient_clear && !i_sample_clear && !i_start &&
      (coefficient_load_count == COEFFICIENT_COUNT) &&
      (sample_load_count < CAPTURE_COUNT);

  // Widen before adding: 64 + 65 reaches capture slot 129, which does not fit
  // in seven unsigned bits.
  wire [7:0] sample_memory_address =
      {1'b0, lag_index} + {1'b0, phase_issue_count};

  // One issue per engine clock.  An operand stage separates RAM/address logic
  // from the registered DSP output while preserving one-tap-per-clock issue
  // throughput.  During energy passes multiplier 2 is intentionally issued
  // with zero operands; it is the same physical DSP later used by the Gauss
  // loop, not an additional square multiplier.
  reg               multiplier_issue;
  reg signed [16:0] multiplier_0_a;
  reg signed [16:0] multiplier_0_b;
  reg signed [16:0] multiplier_1_a;
  reg signed [16:0] multiplier_1_b;
  reg signed [16:0] multiplier_2_a;
  reg signed [16:0] multiplier_2_b;

  always @* begin
    multiplier_issue = 1'b0;
    multiplier_0_a = 17'sd0;
    multiplier_0_b = 17'sd0;
    multiplier_1_a = 17'sd0;
    multiplier_1_b = 17'sd0;
    multiplier_2_a = 17'sd0;
    multiplier_2_b = 17'sd0;

    case (state)
      STATE_COEFFICIENT_ENERGY: begin
        if (phase_issue_count < COEFFICIENT_COUNT) begin
          multiplier_issue = 1'b1;
          multiplier_0_a = {
            coefficient_i_memory[phase_issue_count][15],
            coefficient_i_memory[phase_issue_count]
          };
          multiplier_0_b = multiplier_0_a;
          multiplier_1_a = {
            coefficient_q_memory[phase_issue_count][15],
            coefficient_q_memory[phase_issue_count]
          };
          multiplier_1_b = multiplier_1_a;
        end
      end

      STATE_SAMPLE_ENERGY: begin
        if (phase_issue_count < COEFFICIENT_COUNT) begin
          multiplier_issue = 1'b1;
          multiplier_0_a = {
            sample_i_memory[sample_memory_address][15],
            sample_i_memory[sample_memory_address]
          };
          multiplier_0_b = multiplier_0_a;
          multiplier_1_a = {
            sample_q_memory[sample_memory_address][15],
            sample_q_memory[sample_memory_address]
          };
          multiplier_1_b = multiplier_1_a;
        end
      end

      STATE_CORRELATION: begin
        if (phase_issue_count < COEFFICIENT_COUNT) begin
          multiplier_issue = 1'b1;
          multiplier_0_a = {
            sample_i_memory[sample_memory_address][15],
            sample_i_memory[sample_memory_address]
          };
          multiplier_0_b = {
            coefficient_i_memory[phase_issue_count][15],
            coefficient_i_memory[phase_issue_count]
          };
          multiplier_1_a = {
            sample_q_memory[sample_memory_address][15],
            sample_q_memory[sample_memory_address]
          };
          multiplier_1_b = {
            coefficient_q_memory[phase_issue_count][15],
            coefficient_q_memory[phase_issue_count]
          };
          multiplier_2_a =
              $signed({sample_i_memory[sample_memory_address][15],
                       sample_i_memory[sample_memory_address]}) +
              $signed({sample_q_memory[sample_memory_address][15],
                       sample_q_memory[sample_memory_address]});
          multiplier_2_b =
              $signed({coefficient_i_memory[phase_issue_count][15],
                       coefficient_i_memory[phase_issue_count]}) -
              $signed({coefficient_q_memory[phase_issue_count][15],
                       coefficient_q_memory[phase_issue_count]});
        end
      end

      default: begin
      end
    endcase
  end

  reg multiplier_operand_valid;
  reg multiplier_valid;
  reg signed [16:0] multiplier_0_a_registered;
  reg signed [16:0] multiplier_0_b_registered;
  reg signed [16:0] multiplier_1_a_registered;
  reg signed [16:0] multiplier_1_b_registered;
  reg signed [16:0] multiplier_2_a_registered;
  reg signed [16:0] multiplier_2_b_registered;
  (* use_dsp = "yes", keep = "true" *)
  reg signed [33:0] multiplier_0_product;
  (* use_dsp = "yes", keep = "true" *)
  reg signed [33:0] multiplier_1_product;
  (* use_dsp = "yes", keep = "true" *)
  reg signed [33:0] multiplier_2_product;

  always @(posedge i_clk) begin
    if (i_reset) begin
      multiplier_operand_valid <= 1'b0;
      multiplier_valid <= 1'b0;
      multiplier_0_a_registered <= 17'sd0;
      multiplier_0_b_registered <= 17'sd0;
      multiplier_1_a_registered <= 17'sd0;
      multiplier_1_b_registered <= 17'sd0;
      multiplier_2_a_registered <= 17'sd0;
      multiplier_2_b_registered <= 17'sd0;
      multiplier_0_product <= 34'sd0;
      multiplier_1_product <= 34'sd0;
      multiplier_2_product <= 34'sd0;
    end else begin
      multiplier_operand_valid <= multiplier_issue;
      multiplier_valid <= multiplier_operand_valid;
      if (multiplier_issue) begin
        multiplier_0_a_registered <= multiplier_0_a;
        multiplier_0_b_registered <= multiplier_0_b;
        multiplier_1_a_registered <= multiplier_1_a;
        multiplier_1_b_registered <= multiplier_1_b;
        multiplier_2_a_registered <= multiplier_2_a;
        multiplier_2_b_registered <= multiplier_2_b;
      end
      if (multiplier_operand_valid) begin
        multiplier_0_product <=
            multiplier_0_a_registered * multiplier_0_b_registered;
        multiplier_1_product <=
            multiplier_1_a_registered * multiplier_1_b_registered;
        multiplier_2_product <=
            multiplier_2_a_registered * multiplier_2_b_registered;
      end
    end
  end

  // Gauss reconstruction for x * conj(h):
  //   m0 = xi*hi, m1 = xq*hq, m2 = (xi+xq)*(hi-hq)
  //   C_re tap = m0+m1, C_im tap = m2-m0+m1
  wire signed [35:0] energy_addend =
      $signed({{2{multiplier_0_product[33]}}, multiplier_0_product}) +
      $signed({{2{multiplier_1_product[33]}}, multiplier_1_product});
  wire signed [35:0] correlation_real_addend =
      $signed({{2{multiplier_0_product[33]}}, multiplier_0_product}) +
      $signed({{2{multiplier_1_product[33]}}, multiplier_1_product});
  wire signed [35:0] correlation_imag_addend =
      $signed({{2{multiplier_2_product[33]}}, multiplier_2_product}) -
      $signed({{2{multiplier_0_product[33]}}, multiplier_0_product}) +
      $signed({{2{multiplier_1_product[33]}}, multiplier_1_product});

  // Register complete tap addends before the 48-bit saturation boundary.
  // Besides making "after tap" explicit, this keeps Gauss reconstruction out
  // of the saturating-accumulator timing path.
  reg tap_valid;
  reg signed [35:0] tap_energy_addend;
  reg signed [35:0] tap_correlation_real_addend;
  reg signed [35:0] tap_correlation_imag_addend;

  always @(posedge i_clk) begin
    if (i_reset) begin
      tap_valid <= 1'b0;
      tap_energy_addend <= 36'sd0;
      tap_correlation_real_addend <= 36'sd0;
      tap_correlation_imag_addend <= 36'sd0;
    end else begin
      tap_valid <= multiplier_valid;
      if (multiplier_valid) begin
        tap_energy_addend <= energy_addend;
        tap_correlation_real_addend <= correlation_real_addend;
        tap_correlation_imag_addend <= correlation_imag_addend;
      end
    end
  end

  reg signed [47:0] saturator_0_accumulator;
  reg signed [35:0] saturator_0_addend;
  reg signed [47:0] saturator_1_accumulator;
  reg signed [35:0] saturator_1_addend;
  wire signed [47:0] saturator_0_result;
  wire signed [47:0] saturator_1_result;
  wire saturator_0_event;
  wire saturator_1_event;

  always @* begin
    saturator_0_accumulator = 48'sd0;
    saturator_0_addend = 36'sd0;
    saturator_1_accumulator = 48'sd0;
    saturator_1_addend = 36'sd0;
    case (state)
      STATE_COEFFICIENT_ENERGY: begin
        saturator_0_accumulator = coefficient_energy_accumulator;
        saturator_0_addend = tap_energy_addend;
      end
      STATE_SAMPLE_ENERGY: begin
        saturator_0_accumulator = sample_energy_accumulator;
        saturator_0_addend = tap_energy_addend;
      end
      STATE_CORRELATION: begin
        saturator_0_accumulator = correlation_real_accumulator;
        saturator_0_addend = tap_correlation_real_addend;
        saturator_1_accumulator = correlation_imag_accumulator;
        saturator_1_addend = tap_correlation_imag_addend;
      end
      default: begin
      end
    endcase
  end

  starlink_sat_add48 i_saturator_0 (
    .i_accumulator (saturator_0_accumulator),
    .i_addend     (saturator_0_addend),
    .o_result     (saturator_0_result),
    .o_saturated  (saturator_0_event)
  );

  starlink_sat_add48 i_saturator_1 (
    .i_accumulator (saturator_1_accumulator),
    .i_addend     (saturator_1_addend),
    .o_result     (saturator_1_result),
    .o_saturated  (saturator_1_event)
  );

  always @(posedge i_clk) begin
    if (i_reset) begin
      state <= STATE_IDLE;
      coefficient_load_count <= 7'd0;
      sample_load_count <= 8'd0;
      lag_index <= 7'd0;
      phase_issue_count <= 7'd0;
      phase_consume_count <= 7'd0;
      coefficient_energy_accumulator <= 48'sd0;
      sample_energy_accumulator <= 48'sd0;
      correlation_real_accumulator <= 48'sd0;
      correlation_imag_accumulator <= 48'sd0;
      coefficient_saturation_count <= 9'd0;
      sample_saturation_count <= 9'd0;
      correlation_saturation_count <= 9'd0;
      o_result_lag <= 7'sd0;
      o_result_timestamp <= 64'd0;
      o_result_c_re <= 48'sd0;
      o_result_c_im <= 48'sd0;
      o_result_ex <= 48'sd0;
      o_result_eh <= 48'sd0;
      o_result_saturation_events <= 9'd0;
      o_done <= 1'b0;
    end else begin
      o_done <= 1'b0;

      case (state)
        STATE_IDLE: begin
          if (i_coefficient_clear) begin
            coefficient_load_count <= 7'd0;
            sample_load_count <= 8'd0;
          end else if (i_sample_clear) begin
            sample_load_count <= 8'd0;
          end else if (i_start && o_start_ready) begin
            state <= STATE_COEFFICIENT_ENERGY;
            lag_index <= 7'd0;
            phase_issue_count <= 7'd0;
            phase_consume_count <= 7'd0;
            coefficient_energy_accumulator <= 48'sd0;
            coefficient_saturation_count <= 9'd0;
          end else begin
            if (i_coefficient_valid && o_coefficient_ready) begin
              coefficient_i_memory[coefficient_load_count] <= i_coefficient_i;
              coefficient_q_memory[coefficient_load_count] <= i_coefficient_q;
              coefficient_load_count <= coefficient_load_count + 1'b1;
            end
            if (i_sample_valid && o_sample_ready) begin
              sample_i_memory[sample_load_count] <= i_sample_i;
              sample_q_memory[sample_load_count] <= i_sample_q;
              sample_timestamp_memory[sample_load_count] <= i_sample_timestamp;
              sample_load_count <= sample_load_count + 1'b1;
            end
          end
        end

        STATE_COEFFICIENT_ENERGY: begin
          if (multiplier_issue)
            phase_issue_count <= phase_issue_count + 1'b1;
          if (tap_valid) begin
            coefficient_energy_accumulator <= saturator_0_result;
            coefficient_saturation_count <=
                coefficient_saturation_count + saturator_0_event;
            phase_consume_count <= phase_consume_count + 1'b1;
            if (phase_consume_count == COEFFICIENT_COUNT-1) begin
              state <= STATE_SAMPLE_ENERGY;
              phase_issue_count <= 7'd0;
              phase_consume_count <= 7'd0;
              sample_energy_accumulator <= 48'sd0;
              sample_saturation_count <= 9'd0;
            end
          end
        end

        STATE_SAMPLE_ENERGY: begin
          if (multiplier_issue)
            phase_issue_count <= phase_issue_count + 1'b1;
          if (tap_valid) begin
            sample_energy_accumulator <= saturator_0_result;
            sample_saturation_count <=
                sample_saturation_count + saturator_0_event;
            phase_consume_count <= phase_consume_count + 1'b1;
            if (phase_consume_count == COEFFICIENT_COUNT-1) begin
              state <= STATE_CORRELATION;
              phase_issue_count <= 7'd0;
              phase_consume_count <= 7'd0;
              correlation_real_accumulator <= 48'sd0;
              correlation_imag_accumulator <= 48'sd0;
              correlation_saturation_count <= 9'd0;
            end
          end
        end

        STATE_CORRELATION: begin
          if (multiplier_issue)
            phase_issue_count <= phase_issue_count + 1'b1;
          if (tap_valid) begin
            correlation_real_accumulator <= saturator_0_result;
            correlation_imag_accumulator <= saturator_1_result;
            correlation_saturation_count <=
                correlation_saturation_count +
                saturator_0_event + saturator_1_event;
            phase_consume_count <= phase_consume_count + 1'b1;
            if (phase_consume_count == COEFFICIENT_COUNT-1) begin
              state <= STATE_FINALIZE;
            end
          end
        end

        // The final tap is first committed to the ordinary accumulators above.
        // Capturing the tuple one clock later keeps the 48-bit saturation carry
        // chain separate from the result's 9-bit saturation-count reduction.
        STATE_FINALIZE: begin
          state <= STATE_EMIT;
          o_result_lag <=
              $signed({1'b0, lag_index}) - 8'sd32;
          o_result_timestamp <= sample_timestamp_memory[lag_index];
          o_result_c_re <= correlation_real_accumulator;
          o_result_c_im <= correlation_imag_accumulator;
          o_result_ex <= sample_energy_accumulator;
          o_result_eh <= coefficient_energy_accumulator;
          o_result_saturation_events <=
              coefficient_saturation_count +
              sample_saturation_count +
              correlation_saturation_count;
        end

        STATE_EMIT: begin
          if (i_result_ready) begin
            if (lag_index == RESULT_COUNT-1) begin
              state <= STATE_IDLE;
              sample_load_count <= 8'd0;
              o_done <= 1'b1;
            end else begin
              state <= STATE_SAMPLE_ENERGY;
              lag_index <= lag_index + 1'b1;
              phase_issue_count <= 7'd0;
              phase_consume_count <= 7'd0;
              sample_energy_accumulator <= 48'sd0;
              sample_saturation_count <= 9'd0;
            end
          end
        end

        default: begin
          state <= STATE_IDLE;
          coefficient_load_count <= 7'd0;
          sample_load_count <= 8'd0;
        end
      endcase
    end
  end

endmodule
