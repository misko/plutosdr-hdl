// SPDX-License-Identifier: GPL-2.0
//
// Stage-15 exact correlator with committed/cached coefficient energy and a
// sliding sample-energy window.  It is intentionally kept beside, rather than
// replacing, starlink_pss_raw_correlator so every legal tuple can be checked
// differentially while the optimized scheduler is developed.

`timescale 1ns/1ps

module starlink_pss_sliding_correlator (
  input  wire               i_clk,
  input  wire               i_reset,

  input  wire               i_coefficient_clear,
  input  wire               i_coefficient_valid,
  output wire               o_coefficient_ready,
  input  wire signed [15:0] i_coefficient_i,
  input  wire signed [15:0] i_coefficient_q,
  input  wire               i_coefficient_commit,
  output wire               o_coefficient_commit_ready,
  input  wire        [31:0] i_coefficient_generation,
  output reg                o_coefficient_commit_accepted,
  output reg                o_coefficient_commit_rejected,
  output reg                o_active_coefficient_valid,
  output reg         [31:0] o_active_coefficient_generation,
  output reg  signed [47:0] o_active_coefficient_energy,
  output wire         [6:0] o_shadow_coefficient_count,
  output wire               o_configuration_idle,

  input  wire               i_sample_clear,
  input  wire               i_sample_valid,
  output wire               o_sample_ready,
  input  wire signed [15:0] i_sample_i,
  input  wire signed [15:0] i_sample_q,
  input  wire        [63:0] i_sample_timestamp,
  output wire         [7:0] o_sample_count,

  input  wire               i_start,
  output wire               o_start_ready,
  output wire               o_busy,

  output wire               o_result_valid,
  input  wire               i_result_ready,
  output reg  signed  [6:0] o_result_lag,
  output reg         [63:0] o_result_timestamp,
  output reg         [31:0] o_result_coefficient_generation,
  output reg  signed [47:0] o_result_c_re,
  output reg  signed [47:0] o_result_c_im,
  output reg  signed [47:0] o_result_ex,
  output reg  signed [47:0] o_result_eh,
  output reg          [8:0] o_result_saturation_events,
  output reg                o_done,
  output reg         [31:0] o_bound_error_count
);

  localparam integer COEFFICIENT_COUNT = 66;
  localparam integer CAPTURE_COUNT = 130;
  localparam integer RESULT_COUNT = 65;

  localparam [3:0] STATE_IDLE               = 4'd0;
  localparam [3:0] STATE_COEFFICIENT_ENERGY = 4'd1;
  localparam [3:0] STATE_COEFFICIENT_CHECK  = 4'd2;
  localparam [3:0] STATE_COEFFICIENT_COPY   = 4'd3;
  localparam [3:0] STATE_SAMPLE_ENERGY      = 4'd4;
  localparam [3:0] STATE_CORRELATION        = 4'd5;
  localparam [3:0] STATE_FINALIZE           = 4'd6;
  localparam [3:0] STATE_EMIT               = 4'd7;
  localparam [3:0] STATE_SLIDE_ENERGY       = 4'd8;

  function automatic [31:0] increment_saturating_32;
    input [31:0] value;
    begin
      increment_saturating_32 = (&value) ? value : value + 1'b1;
    end
  endfunction

  reg [3:0] state;

  reg signed [15:0] shadow_coefficient_i_memory [0:COEFFICIENT_COUNT-1];
  reg signed [15:0] shadow_coefficient_q_memory [0:COEFFICIENT_COUNT-1];
  reg signed [15:0] active_coefficient_i_memory [0:COEFFICIENT_COUNT-1];
  reg signed [15:0] active_coefficient_q_memory [0:COEFFICIENT_COUNT-1];
  reg signed [15:0] sample_i_memory [0:CAPTURE_COUNT-1];
  reg signed [15:0] sample_q_memory [0:CAPTURE_COUNT-1];
  reg        [63:0] sample_timestamp_memory [0:CAPTURE_COUNT-1];
  reg        [31:0] sample_energy_memory [0:CAPTURE_COUNT-1];

  reg [6:0] shadow_coefficient_load_count;
  reg [7:0] sample_load_count;
  reg [6:0] coefficient_copy_count;
  reg [6:0] lag_index;
  reg [7:0] phase_issue_count;
  reg [7:0] phase_consume_count;
  reg [31:0] pending_coefficient_generation;

  reg signed [47:0] coefficient_energy_accumulator;
  reg signed [47:0] sample_energy_accumulator;
  reg signed [47:0] correlation_real_accumulator;
  reg signed [47:0] correlation_imag_accumulator;
  reg         [8:0] coefficient_saturation_count;
  reg         [8:0] sample_saturation_count;
  reg         [8:0] correlation_saturation_count;

  assign o_shadow_coefficient_count = shadow_coefficient_load_count;
  assign o_configuration_idle =
      (state == STATE_IDLE) && (sample_load_count == 0);
  assign o_sample_count = sample_load_count;
  assign o_busy = (state != STATE_IDLE);
  assign o_result_valid = (state == STATE_EMIT);

  assign o_coefficient_ready =
      (state == STATE_IDLE) && (sample_load_count == 0) &&
      (shadow_coefficient_load_count < COEFFICIENT_COUNT);
  assign o_coefficient_commit_ready =
      (state == STATE_IDLE) && (sample_load_count == 0) &&
      (shadow_coefficient_load_count == COEFFICIENT_COUNT);
  assign o_sample_ready =
      (state == STATE_IDLE) && o_active_coefficient_valid &&
      (shadow_coefficient_load_count == 0) &&
      (sample_load_count < CAPTURE_COUNT);
  assign o_start_ready =
      (state == STATE_IDLE) && o_active_coefficient_valid &&
      (shadow_coefficient_load_count == 0) &&
      (sample_load_count == CAPTURE_COUNT);

  wire [7:0] sample_memory_address =
      {1'b0, lag_index} + phase_issue_count;

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
            shadow_coefficient_i_memory[phase_issue_count][15],
            shadow_coefficient_i_memory[phase_issue_count]
          };
          multiplier_0_b = multiplier_0_a;
          multiplier_1_a = {
            shadow_coefficient_q_memory[phase_issue_count][15],
            shadow_coefficient_q_memory[phase_issue_count]
          };
          multiplier_1_b = multiplier_1_a;
        end
      end

      STATE_SAMPLE_ENERGY: begin
        if (phase_issue_count < CAPTURE_COUNT) begin
          multiplier_issue = 1'b1;
          multiplier_0_a = {
            sample_i_memory[phase_issue_count][15],
            sample_i_memory[phase_issue_count]
          };
          multiplier_0_b = multiplier_0_a;
          multiplier_1_a = {
            sample_q_memory[phase_issue_count][15],
            sample_q_memory[phase_issue_count]
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
            active_coefficient_i_memory[phase_issue_count][15],
            active_coefficient_i_memory[phase_issue_count]
          };
          multiplier_1_a = {
            sample_q_memory[sample_memory_address][15],
            sample_q_memory[sample_memory_address]
          };
          multiplier_1_b = {
            active_coefficient_q_memory[phase_issue_count][15],
            active_coefficient_q_memory[phase_issue_count]
          };
          multiplier_2_a =
              $signed({sample_i_memory[sample_memory_address][15],
                       sample_i_memory[sample_memory_address]}) +
              $signed({sample_q_memory[sample_memory_address][15],
                       sample_q_memory[sample_memory_address]});
          multiplier_2_b =
              $signed({active_coefficient_i_memory[phase_issue_count][15],
                       active_coefficient_i_memory[phase_issue_count]}) -
              $signed({active_coefficient_q_memory[phase_issue_count][15],
                       active_coefficient_q_memory[phase_issue_count]});
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

  wire signed [35:0] energy_addend =
      $signed({{2{multiplier_0_product[33]}}, multiplier_0_product}) +
      $signed({{2{multiplier_1_product[33]}}, multiplier_1_product});
  wire signed [35:0] correlation_real_addend = energy_addend;
  wire signed [35:0] correlation_imag_addend =
      $signed({{2{multiplier_2_product[33]}}, multiplier_2_product}) -
      $signed({{2{multiplier_0_product[33]}}, multiplier_0_product}) +
      $signed({{2{multiplier_1_product[33]}}, multiplier_1_product});

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

  // Phase-specific saturators deliberately trade a small amount of LUT area
  // for routed margin.  Sharing one 48-bit carry chain put the FSM decode and
  // a wide accumulator mux in front of that chain, making state rather than
  // arithmetic the limiting path in the complete Pluto shell.
  wire signed [47:0] coefficient_saturator_result;
  wire signed [47:0] sample_saturator_result;
  wire signed [47:0] correlation_real_saturator_result;
  wire signed [47:0] correlation_imag_saturator_result;
  wire coefficient_saturator_event;
  wire sample_saturator_event;
  wire correlation_real_saturator_event;
  wire correlation_imag_saturator_event;

  starlink_sat_add48 i_coefficient_saturator (
    .i_accumulator (coefficient_energy_accumulator),
    .i_addend      (tap_energy_addend),
    .o_result      (coefficient_saturator_result),
    .o_saturated   (coefficient_saturator_event)
  );

  starlink_sat_add48 i_sample_saturator (
    .i_accumulator (sample_energy_accumulator),
    .i_addend      (tap_energy_addend),
    .o_result      (sample_saturator_result),
    .o_saturated   (sample_saturator_event)
  );

  starlink_sat_add48 i_correlation_real_saturator (
    .i_accumulator (correlation_real_accumulator),
    .i_addend      (tap_correlation_real_addend),
    .o_result      (correlation_real_saturator_result),
    .o_saturated   (correlation_real_saturator_event)
  );

  starlink_sat_add48 i_correlation_imag_saturator (
    .i_accumulator (correlation_imag_accumulator),
    .i_addend      (tap_correlation_imag_addend),
    .o_result      (correlation_imag_saturator_result),
    .o_saturated   (correlation_imag_saturator_event)
  );

  wire [7:0] sliding_add_address =
      {1'b0, lag_index} + COEFFICIENT_COUNT;
  wire signed [49:0] sliding_energy_wide =
      $signed({{2{sample_energy_accumulator[47]}}, sample_energy_accumulator}) -
      $signed({18'd0, sample_energy_memory[lag_index]}) +
      $signed({18'd0, sample_energy_memory[sliding_add_address]});
  wire sliding_energy_bound_error =
      sliding_energy_wide[49] || (|sliding_energy_wide[48:47]);
  // Register the rare diagnostic event before it reaches the 32-bit
  // saturating counter.  The counter is observability only; keeping the
  // sliding-address/energy decision out of its carry/enable cone prevents a
  // diagnostic from becoming the 100 MHz tracking-engine critical path.
  reg sliding_energy_bound_error_pending;

  always @(posedge i_clk) begin
    if (i_reset) begin
      state <= STATE_IDLE;
      shadow_coefficient_load_count <= 7'd0;
      sample_load_count <= 8'd0;
      coefficient_copy_count <= 7'd0;
      lag_index <= 7'd0;
      phase_issue_count <= 8'd0;
      phase_consume_count <= 8'd0;
      pending_coefficient_generation <= 32'd0;
      coefficient_energy_accumulator <= 48'sd0;
      sample_energy_accumulator <= 48'sd0;
      correlation_real_accumulator <= 48'sd0;
      correlation_imag_accumulator <= 48'sd0;
      coefficient_saturation_count <= 9'd0;
      sample_saturation_count <= 9'd0;
      correlation_saturation_count <= 9'd0;
      o_coefficient_commit_accepted <= 1'b0;
      o_coefficient_commit_rejected <= 1'b0;
      o_active_coefficient_valid <= 1'b0;
      o_active_coefficient_generation <= 32'd0;
      o_active_coefficient_energy <= 48'sd0;
      o_result_lag <= 7'sd0;
      o_result_timestamp <= 64'd0;
      o_result_coefficient_generation <= 32'd0;
      o_result_c_re <= 48'sd0;
      o_result_c_im <= 48'sd0;
      o_result_ex <= 48'sd0;
      o_result_eh <= 48'sd0;
      o_result_saturation_events <= 9'd0;
      o_done <= 1'b0;
      o_bound_error_count <= 32'd0;
      sliding_energy_bound_error_pending <= 1'b0;
    end else begin
      o_coefficient_commit_accepted <= 1'b0;
      o_coefficient_commit_rejected <= 1'b0;
      o_done <= 1'b0;
      sliding_energy_bound_error_pending <= 1'b0;

      if (sliding_energy_bound_error_pending)
        o_bound_error_count <= increment_saturating_32(o_bound_error_count);

      case (state)
        STATE_IDLE: begin
          if (i_coefficient_clear) begin
            shadow_coefficient_load_count <= 7'd0;
          end else if (i_sample_clear) begin
            sample_load_count <= 8'd0;
          end else if (i_coefficient_commit && o_coefficient_commit_ready) begin
            state <= STATE_COEFFICIENT_ENERGY;
            phase_issue_count <= 8'd0;
            phase_consume_count <= 8'd0;
            coefficient_energy_accumulator <= 48'sd0;
            coefficient_saturation_count <= 9'd0;
            pending_coefficient_generation <= i_coefficient_generation;
          end else if (i_start && o_start_ready) begin
            state <= STATE_SAMPLE_ENERGY;
            lag_index <= 7'd0;
            phase_issue_count <= 8'd0;
            phase_consume_count <= 8'd0;
            sample_energy_accumulator <= 48'sd0;
            sample_saturation_count <= 9'd0;
          end else begin
            if (i_coefficient_valid && o_coefficient_ready) begin
              shadow_coefficient_i_memory[shadow_coefficient_load_count] <=
                  i_coefficient_i;
              shadow_coefficient_q_memory[shadow_coefficient_load_count] <=
                  i_coefficient_q;
              shadow_coefficient_load_count <=
                  shadow_coefficient_load_count + 1'b1;
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
            coefficient_energy_accumulator <= coefficient_saturator_result;
            coefficient_saturation_count <=
                coefficient_saturation_count + coefficient_saturator_event;
            phase_consume_count <= phase_consume_count + 1'b1;
            if (phase_consume_count == COEFFICIENT_COUNT-1)
              state <= STATE_COEFFICIENT_CHECK;
          end
        end

        STATE_COEFFICIENT_CHECK: begin
          if ((coefficient_energy_accumulator <= 0) ||
              (coefficient_energy_accumulator > 48'sh0000_7fff_ffff) ||
              (coefficient_saturation_count != 0)) begin
            state <= STATE_IDLE;
            shadow_coefficient_load_count <= 7'd0;
            o_coefficient_commit_rejected <= 1'b1;
          end else begin
            state <= STATE_COEFFICIENT_COPY;
            coefficient_copy_count <= 7'd0;
          end
        end

        STATE_COEFFICIENT_COPY: begin
          active_coefficient_i_memory[coefficient_copy_count] <=
              shadow_coefficient_i_memory[coefficient_copy_count];
          active_coefficient_q_memory[coefficient_copy_count] <=
              shadow_coefficient_q_memory[coefficient_copy_count];
          if (coefficient_copy_count == COEFFICIENT_COUNT-1) begin
            state <= STATE_IDLE;
            shadow_coefficient_load_count <= 7'd0;
            o_active_coefficient_valid <= 1'b1;
            o_active_coefficient_generation <= pending_coefficient_generation;
            o_active_coefficient_energy <= coefficient_energy_accumulator;
            o_coefficient_commit_accepted <= 1'b1;
          end else begin
            coefficient_copy_count <= coefficient_copy_count + 1'b1;
          end
        end

        STATE_SAMPLE_ENERGY: begin
          if (multiplier_issue)
            phase_issue_count <= phase_issue_count + 1'b1;
          if (tap_valid) begin
            sample_energy_memory[phase_consume_count] <= tap_energy_addend[31:0];
            if (phase_consume_count < COEFFICIENT_COUNT) begin
              sample_energy_accumulator <= sample_saturator_result;
              sample_saturation_count <=
                  sample_saturation_count + sample_saturator_event;
            end
            phase_consume_count <= phase_consume_count + 1'b1;
            if (phase_consume_count == CAPTURE_COUNT-1) begin
              state <= STATE_CORRELATION;
              phase_issue_count <= 8'd0;
              phase_consume_count <= 8'd0;
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
            correlation_real_accumulator <= correlation_real_saturator_result;
            correlation_imag_accumulator <= correlation_imag_saturator_result;
            correlation_saturation_count <=
                correlation_saturation_count +
                correlation_real_saturator_event +
                correlation_imag_saturator_event;
            phase_consume_count <= phase_consume_count + 1'b1;
            if (phase_consume_count == COEFFICIENT_COUNT-1)
              state <= STATE_FINALIZE;
          end
        end

        STATE_FINALIZE: begin
          state <= STATE_EMIT;
          o_result_lag <= $signed({1'b0, lag_index}) - 8'sd32;
          o_result_timestamp <= sample_timestamp_memory[lag_index];
          o_result_coefficient_generation <=
              o_active_coefficient_generation;
          o_result_c_re <= correlation_real_accumulator;
          o_result_c_im <= correlation_imag_accumulator;
          o_result_ex <= sample_energy_accumulator;
          o_result_eh <= o_active_coefficient_energy;
          o_result_saturation_events <=
              coefficient_saturation_count +
              sample_saturation_count + correlation_saturation_count;
        end

        STATE_EMIT: begin
          if (i_result_ready) begin
            if (lag_index == RESULT_COUNT-1) begin
              state <= STATE_IDLE;
              sample_load_count <= 8'd0;
              o_done <= 1'b1;
            end else begin
              state <= STATE_SLIDE_ENERGY;
            end
          end
        end

        STATE_SLIDE_ENERGY: begin
          if (sliding_energy_bound_error) begin
            sliding_energy_bound_error_pending <= 1'b1;
            sample_saturation_count <= sample_saturation_count + 1'b1;
          end
          sample_energy_accumulator <= sliding_energy_wide[47:0];
          lag_index <= lag_index + 1'b1;
          phase_issue_count <= 8'd0;
          phase_consume_count <= 8'd0;
          correlation_real_accumulator <= 48'sd0;
          correlation_imag_accumulator <= 48'sd0;
          correlation_saturation_count <= 9'd0;
          state <= STATE_CORRELATION;
        end

        default: begin
          state <= STATE_IDLE;
          shadow_coefficient_load_count <= 7'd0;
          sample_load_count <= 8'd0;
          o_active_coefficient_valid <= 1'b0;
        end
      endcase
    end
  end

endmodule
