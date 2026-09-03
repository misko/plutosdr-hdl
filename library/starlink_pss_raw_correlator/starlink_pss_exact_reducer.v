// SPDX-License-Identifier: GPL-2.0
//
// Exact normalized-score reducer for an ordered raw-tuple stream.  The score
// is |C|^2/(Ex*Eh).  In one-bank tracking mode Eh is constant for the complete
// job and is cancelled exactly, reducing the denominator to Ex.  Validation
// modes retain Ex*Eh.  Winner comparison uses exact rational cross-products
// at the proved Stage-15 bounds (77-bit numerator, 69-bit denominator, and
// 146-bit cross-product).  One right-shifting bit-serial multiplier is shared
// by both squares, optional Ex*Eh, and both ratio cross-products.  It contains
// no multiplication operator and therefore cannot silently add DSPs.

`timescale 1ns/1ps

module starlink_pss_exact_reducer #(
  parameter integer RATE_MULTIPLIER = 1
) (
  input  wire                i_clk,
  input  wire                i_reset,

  input  wire                i_tuple_valid,
  output wire                o_tuple_ready,
  input  wire                i_tuple_first,
  input  wire                i_tuple_last,
  input  wire                i_include_eh,
  input  wire         [31:0] i_request_id,
  input  wire         [63:0] i_center_index,
  input  wire         [63:0] i_center_timestamp,
  input  wire signed [$clog2(64 * RATE_MULTIPLIER + 1)-1:0] i_lag,
  input  wire         [63:0] i_timestamp,
  input  wire         [31:0] i_coefficient_generation,
  input  wire signed  [47:0] i_c_re,
  input  wire signed  [47:0] i_c_im,
  input  wire signed  [47:0] i_ex,
  input  wire signed  [47:0] i_eh,
  input  wire          [8:0] i_saturation_events,

  output reg                 o_result_valid,
  input  wire                i_result_ready,
  output wire                o_result_score_valid,
  output wire                o_result_includes_eh,
  output wire         [31:0] o_result_request_id,
  output wire         [63:0] o_result_center_index,
  output wire         [63:0] o_result_center_timestamp,
  output wire signed [$clog2(64 * RATE_MULTIPLIER + 1)-1:0] o_result_lag,
  output wire         [63:0] o_result_timestamp,
  output wire         [31:0] o_result_coefficient_generation,
  output wire signed  [47:0] o_result_c_re,
  output wire signed  [47:0] o_result_c_im,
  output wire signed  [47:0] o_result_ex,
  output wire signed  [47:0] o_result_eh,
  output wire          [8:0] o_result_saturation_events,
  output wire         [76:0] o_result_score_numerator,
  output wire         [68:0] o_result_score_denominator,

  output reg          [31:0] o_processed_job_count,
  output reg          [31:0] o_emitted_result_count,
  output reg          [31:0] o_invalid_tuple_count,
  output reg          [31:0] o_bound_error_count,
  output reg          [31:0] o_protocol_error_count
);

  localparam integer LAG_WIDTH = $clog2(64 * RATE_MULTIPLIER + 1);
  localparam signed [LAG_WIDTH-1:0] FIRST_LAG =
      -30 * RATE_MULTIPLIER;
  localparam signed [LAG_WIDTH-1:0] LAST_LAG =
      30 * RATE_MULTIPLIER;

  generate
    if ((RATE_MULTIPLIER != 1) && (RATE_MULTIPLIER != 2) &&
        (RATE_MULTIPLIER != 4)) begin : g_invalid_rate_multiplier
      initial $fatal(1, "RATE_MULTIPLIER must be 1, 2, or 4");
    end
  endgenerate

  localparam [3:0] STATE_IDLE       = 4'd0;
  localparam [3:0] STATE_SQUARE_RE  = 4'd1;
  localparam [3:0] STATE_SQUARE_IM  = 4'd2;
  localparam [3:0] STATE_DENOMINATOR = 4'd3;
  localparam [3:0] STATE_PREPARE    = 4'd4;
  localparam [3:0] STATE_LEFT       = 4'd5;
  localparam [3:0] STATE_RIGHT      = 4'd6;
  localparam [3:0] STATE_DECIDE     = 4'd7;
  localparam [3:0] STATE_ACCEPT     = 4'd8;
  localparam [3:0] STATE_ACCEPT_BAD = 4'd9;
  localparam [3:0] STATE_OUTPUT     = 4'd10;
  localparam [3:0] STATE_MAGNITUDE  = 4'd11;
  localparam [3:0] STATE_LOAD_SQUARE = 4'd12;
  localparam [3:0] STATE_COMPARE    = 4'd13;

  function automatic [31:0] increment_saturating_32;
    input [31:0] value;
    begin
      increment_saturating_32 = (&value) ? value : value + 1'b1;
    end
  endfunction

  reg [3:0] state;
  reg job_active;
  reg drop_until_last;
  reg job_include_eh;
  reg signed [LAG_WIDTH-1:0] expected_lag;
  reg current_is_better;

  reg [6:0] multiply_bit_index;
  reg [146:0] multiply_work;
  reg [76:0] multiply_multiplicand;
  reg [76:0] real_square;
  reg [76:0] current_magnitude_squared;
  reg [68:0] current_denominator;
  reg [145:0] left_cross_product;

  // Ex is the repeated multiplicand in validation mode and therefore gets an
  // explicit timing register.  Every other tuple field remains stable until
  // o_tuple_ready and is either shifted into a local register or copied only
  // when a winner is selected.
  reg [37:0] working_ex;

  reg winner_valid;
  reg [76:0] winner_magnitude_squared;
  reg [68:0] winner_denominator;
  reg [31:0] winner_request_id;
  reg [63:0] winner_center_index;
  reg [63:0] winner_center_timestamp;
  reg signed [LAG_WIDTH-1:0] winner_lag;
  reg [63:0] winner_timestamp;
  reg [31:0] winner_coefficient_generation;
  reg signed [47:0] winner_c_re;
  reg signed [47:0] winner_c_im;
  reg signed [47:0] winner_ex;
  reg signed [47:0] winner_eh;
  reg [8:0] winner_saturation_events;

  wire [47:0] absolute_c_re_wide = i_c_re[47] ?
      (~i_c_re[47:0] + 48'd1) : i_c_re[47:0];
  wire [47:0] absolute_c_im_wide = i_c_im[47] ?
      (~i_c_im[47:0] + 48'd1) : i_c_im[47:0];
  wire [37:0] absolute_c_re = absolute_c_re_wide[37:0];
  wire [37:0] absolute_c_im = absolute_c_im_wide[37:0];

  // Standard add/shift multiplication.  The 69-bit multiplier is held in the
  // low portion of multiply_work and shifted right while the 78-bit upper
  // accumulator is updated.  All five exact products use this same datapath.
  wire [77:0] multiply_accumulator = multiply_work[146:69];
  wire [77:0] multiply_addend = multiply_work[0] ?
      {1'b0, multiply_multiplicand} : 78'd0;
  wire [77:0] multiply_accumulator_next =
      multiply_accumulator + multiply_addend;
  wire [146:0] multiply_work_next = {
    1'b0, multiply_accumulator_next, multiply_work[68:1]
  };

  wire correlation_bound_legal =
      (i_c_re[47:38] == {10{i_c_re[38]}}) &&
      (i_c_im[47:38] == {10{i_c_im[38]}});
  wire energy_bound_legal =
      !(|i_ex[47:38]) && !(|i_eh[47:31]);

  wire tuple_score_legal =
      (i_ex > 48'sd0) && (i_eh > 48'sd0) &&
      (i_saturation_events == 9'd0) &&
      correlation_bound_legal && energy_bound_legal;

  wire expected_last = (i_lag == LAST_LAG);
  wire tuple_position_legal = !job_active ?
      (i_tuple_first && !i_tuple_last && (i_lag == FIRST_LAG)) :
      (!i_tuple_first && (i_lag == expected_lag) &&
       (i_tuple_last == expected_last) &&
       (i_include_eh == job_include_eh));

  assign o_tuple_ready =
      ((state == STATE_IDLE) && drop_until_last) ||
      (state == STATE_ACCEPT) || (state == STATE_ACCEPT_BAD);

  // STATE_OUTPUT protects the retained winner until the consumer accepts it,
  // so the publication view can alias that bank instead of duplicating a
  // second full-width packet in flip-flops.
  assign o_result_score_valid = winner_valid;
  assign o_result_includes_eh = job_include_eh;
  assign o_result_request_id = winner_request_id;
  assign o_result_center_index = winner_center_index;
  assign o_result_center_timestamp = winner_center_timestamp;
  assign o_result_lag = winner_lag;
  assign o_result_timestamp = winner_timestamp;
  assign o_result_coefficient_generation = winner_coefficient_generation;
  assign o_result_c_re = winner_c_re;
  assign o_result_c_im = winner_c_im;
  assign o_result_ex = winner_ex;
  assign o_result_eh = winner_eh;
  assign o_result_saturation_events = winner_saturation_events;
  assign o_result_score_numerator = winner_magnitude_squared;
  assign o_result_score_denominator = winner_denominator;

  always @(posedge i_clk) begin
    if (i_reset) begin
      state <= STATE_IDLE;
      job_active <= 1'b0;
      drop_until_last <= 1'b0;
      job_include_eh <= 1'b0;
      expected_lag <= FIRST_LAG;
      current_is_better <= 1'b0;
      multiply_bit_index <= 7'd0;
      multiply_work <= 147'd0;
      multiply_multiplicand <= 77'd0;
      real_square <= 77'd0;
      current_magnitude_squared <= 77'd0;
      current_denominator <= 69'd0;
      left_cross_product <= 146'd0;
      working_ex <= 38'd0;
      winner_valid <= 1'b0;
      winner_magnitude_squared <= 77'd0;
      winner_denominator <= 69'd0;
      winner_request_id <= 32'd0;
      winner_center_index <= 64'd0;
      winner_center_timestamp <= 64'd0;
      winner_lag <= {LAG_WIDTH{1'b0}};
      winner_timestamp <= 64'd0;
      winner_coefficient_generation <= 32'd0;
      winner_c_re <= 48'sd0;
      winner_c_im <= 48'sd0;
      winner_ex <= 48'sd0;
      winner_eh <= 48'sd0;
      winner_saturation_events <= 9'd0;
      o_result_valid <= 1'b0;
      o_processed_job_count <= 32'd0;
      o_emitted_result_count <= 32'd0;
      o_invalid_tuple_count <= 32'd0;
      o_bound_error_count <= 32'd0;
      o_protocol_error_count <= 32'd0;
    end else begin
      case (state)
        STATE_IDLE: begin
          if (drop_until_last) begin
            if (i_tuple_valid && o_tuple_ready && i_tuple_last)
              drop_until_last <= 1'b0;
          end else if (i_tuple_valid) begin
            if (!tuple_position_legal) begin
              o_protocol_error_count <=
                  increment_saturating_32(o_protocol_error_count);
              job_active <= 1'b0;
              winner_valid <= 1'b0;
              drop_until_last <= !i_tuple_last;
              state <= STATE_ACCEPT_BAD;
            end else begin
              if (!job_active) begin
                job_active <= 1'b1;
                job_include_eh <= i_include_eh;
                winner_valid <= 1'b0;
              end
              if (!i_tuple_last)
                expected_lag <= i_lag + 1'b1;
              working_ex <= i_ex[37:0];
              state <= STATE_LOAD_SQUARE;
            end
          end
        end

        STATE_LOAD_SQUARE: begin
          multiply_work <= {78'd0, 31'd0, absolute_c_re};
          multiply_multiplicand <= {39'd0, absolute_c_re};
          multiply_bit_index <= 7'd68;
          state <= STATE_SQUARE_RE;
        end

        STATE_SQUARE_RE: begin
          if (multiply_bit_index == 0) begin
            real_square <= multiply_work_next[76:0];
            multiply_work <= {78'd0, 31'd0, absolute_c_im};
            multiply_multiplicand <= {39'd0, absolute_c_im};
            multiply_bit_index <= 7'd68;
            state <= STATE_SQUARE_IM;
          end else begin
            multiply_work <= multiply_work_next;
            multiply_bit_index <= multiply_bit_index - 1'b1;
          end
        end

        STATE_SQUARE_IM: begin
          if (multiply_bit_index == 0) begin
            current_magnitude_squared <= multiply_work_next[76:0];
            multiply_work <= multiply_work_next;
            state <= STATE_MAGNITUDE;
          end else begin
            multiply_work <= multiply_work_next;
            multiply_bit_index <= multiply_bit_index - 1'b1;
          end
        end

        STATE_MAGNITUDE: begin
          current_magnitude_squared <=
              real_square + current_magnitude_squared;
          if (i_include_eh) begin
            multiply_work <= {78'd0, 38'd0, i_eh[30:0]};
            multiply_multiplicand <= {39'd0, working_ex};
            multiply_bit_index <= 7'd68;
            state <= STATE_DENOMINATOR;
          end else begin
            current_denominator <= {31'd0, working_ex};
            state <= STATE_PREPARE;
          end
        end

        STATE_DENOMINATOR: begin
          if (multiply_bit_index == 0) begin
            current_denominator <= multiply_work_next[68:0];
            multiply_work <= multiply_work_next;
            state <= STATE_PREPARE;
          end else begin
            multiply_work <= multiply_work_next;
            multiply_bit_index <= multiply_bit_index - 1'b1;
          end
        end

        STATE_PREPARE: begin
          if (!tuple_score_legal) begin
            current_is_better <= 1'b0;
            o_invalid_tuple_count <=
                increment_saturating_32(o_invalid_tuple_count);
            if (!correlation_bound_legal || !energy_bound_legal)
              o_bound_error_count <=
                  increment_saturating_32(o_bound_error_count);
            state <= STATE_DECIDE;
          end else if (i_tuple_first || !winner_valid) begin
            current_is_better <= 1'b1;
            state <= STATE_DECIDE;
          end else begin
            multiply_work <= {78'd0, winner_denominator};
            multiply_multiplicand <= current_magnitude_squared;
            multiply_bit_index <= 7'd68;
            state <= STATE_LEFT;
          end
        end

        STATE_LEFT: begin
          if (multiply_bit_index == 0) begin
            left_cross_product <= multiply_work_next[145:0];
            multiply_work <= {78'd0, current_denominator};
            multiply_multiplicand <= winner_magnitude_squared;
            multiply_bit_index <= 7'd68;
            state <= STATE_RIGHT;
          end else begin
            multiply_work <= multiply_work_next;
            multiply_bit_index <= multiply_bit_index - 1'b1;
          end
        end

        STATE_RIGHT: begin
          if (multiply_bit_index == 0) begin
            multiply_work <= multiply_work_next;
            state <= STATE_COMPARE;
          end else begin
            multiply_work <= multiply_work_next;
            multiply_bit_index <= multiply_bit_index - 1'b1;
          end
        end

        STATE_COMPARE: begin
          // Strict greater-than deliberately retains the earliest tuple on an
          // exact rational tie.  The final product is registered before the
          // comparison, so only one wide carry structure is timed per cycle.
          current_is_better <=
              (left_cross_product > multiply_work[145:0]);
          state <= STATE_DECIDE;
        end

        STATE_DECIDE: begin
          if (current_is_better) begin
            winner_valid <= 1'b1;
            winner_magnitude_squared <= current_magnitude_squared;
            winner_denominator <= current_denominator;
            winner_request_id <= i_request_id;
            winner_center_index <= i_center_index;
            winner_center_timestamp <= i_center_timestamp;
            winner_lag <= i_lag;
            winner_timestamp <= i_timestamp;
            winner_coefficient_generation <= i_coefficient_generation;
            winner_c_re <= i_c_re;
            winner_c_im <= i_c_im;
            winner_ex <= i_ex;
            winner_eh <= i_eh;
            winner_saturation_events <= i_saturation_events;
          end

          if (i_tuple_last) begin
            if (!current_is_better && !winner_valid) begin
              // Preserve job identity even when every tuple is invalid; the
              // score-valid bit remains low and all measurement fields are
              // canonical zero.
              winner_request_id <= i_request_id;
              winner_center_index <= i_center_index;
              winner_center_timestamp <= i_center_timestamp;
              winner_lag <= {LAG_WIDTH{1'b0}};
              winner_timestamp <= 64'd0;
              winner_coefficient_generation <= i_coefficient_generation;
              winner_c_re <= 48'sd0;
              winner_c_im <= 48'sd0;
              winner_ex <= 48'sd0;
              winner_eh <= 48'sd0;
              winner_saturation_events <= 9'd0;
              winner_magnitude_squared <= 77'd0;
              winner_denominator <= 69'd0;
            end
            o_processed_job_count <=
                increment_saturating_32(o_processed_job_count);
          end
          state <= STATE_ACCEPT;
        end

        STATE_ACCEPT: begin
          if (i_tuple_valid && o_tuple_ready) begin
            if (i_tuple_last) begin
              job_active <= 1'b0;
              o_result_valid <= 1'b1;
              state <= STATE_OUTPUT;
            end else begin
              state <= STATE_IDLE;
            end
          end
        end

        STATE_ACCEPT_BAD: begin
          if (i_tuple_valid && o_tuple_ready)
            state <= STATE_IDLE;
        end

        STATE_OUTPUT: begin
          if (o_result_valid && i_result_ready) begin
            o_result_valid <= 1'b0;
            o_emitted_result_count <=
                increment_saturating_32(o_emitted_result_count);
            state <= STATE_IDLE;
          end
        end

        default: begin
          state <= STATE_IDLE;
          job_active <= 1'b0;
          drop_until_last <= 1'b0;
          winner_valid <= 1'b0;
          o_result_valid <= 1'b0;
        end
      endcase
    end
  end

endmodule
