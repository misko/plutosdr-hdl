// Exact exponent-aware ratio preparation for normalized PSS power.
//
// The signed Q1.(DATA_WIDTH-1) IFFT correlation is returned to the CI16/Q1.15
// power scale by 2**(2 * (25 - DATA_WIDTH + Ef + Ei)). The denominator is the exact 38-bit
// sample energy times the frozen 31-bit coefficient energy.  A mathematical
// numerator wider than 69 bits saturates to all ones, which is exactly
// equivalent to numerator >= denominator for every representable denominator.

`timescale 1ns/1ps

module starlink_pss_score_prepare #(
  parameter [30:0] COEFFICIENT_ENERGY = 31'd1073742825,
  parameter integer RATIO_BITS = 69,
  parameter integer DATA_WIDTH = 24
) (
  input  wire                    clk,
  input  wire                    resetn,
  input  wire                    flush,

  input  wire                    input_valid,
  output wire                    input_ready,
  input  wire signed [DATA_WIDTH-1:0] input_correlation_i,
  input  wire signed [DATA_WIDTH-1:0] input_correlation_q,
  input  wire [37:0]             input_sample_energy,
  input  wire [4:0]              input_forward_exponent,
  input  wire [4:0]              input_inverse_exponent,
  input  wire [63:0]             input_start_index,

  output reg                     output_valid,
  input  wire                    output_ready,
  output reg [RATIO_BITS-1:0]    output_numerator,
  output reg [RATIO_BITS-1:0]    output_denominator,
  output reg [6:0]               output_power_shift,
  output reg [63:0]              output_start_index,
  output reg                     output_numerator_saturated,
  output reg                     output_denominator_zero,

  output reg                     accepted_pulse,
  output reg                     completed_pulse,
  output reg                     numerator_saturation_pulse,
  output reg                     denominator_zero_pulse
);

  localparam integer CORRELATION_POWER_BITS = 2 * DATA_WIDTH;
  localparam integer POWER_EXTENSION_BITS =
    RATIO_BITS - CORRELATION_POWER_BITS;
  localparam integer BASE_CORRELATION_SHIFT = 25 - DATA_WIDTH;

  reg product_valid;
  (* use_dsp = "yes" *)
  reg [CORRELATION_POWER_BITS-1:0] product_square_i;
  (* use_dsp = "yes" *)
  reg [CORRELATION_POWER_BITS-1:0] product_square_q;
  (* use_dsp = "no" *) reg [RATIO_BITS-1:0] product_denominator;
  reg [4:0] product_forward_exponent;
  reg [4:0] product_inverse_exponent;
  reg [63:0] product_start_index;

  reg sum_valid;
  reg [CORRELATION_POWER_BITS-1:0] sum_correlation_power;
  reg [RATIO_BITS-1:0] sum_denominator;
  reg [6:0] sum_power_shift;
  reg [63:0] sum_start_index;

  wire output_stage_ready;
  wire sum_stage_ready;
  wire product_stage_ready;
  wire input_accept;
  wire [RATIO_BITS-1:0] extended_correlation_power;
  wire shift_exceeds_ratio;
  wire shifted_power_loses_bits;
  wire numerator_overflow;
  wire [RATIO_BITS-1:0] shifted_correlation_power;

  // Deliberately do not reload the output register on the same edge that its
  // prior item is consumed.  The upstream 512-entry result FIFO absorbs this
  // harmless bubble, while the registered valid bit cuts the divider's ready
  // logic out of the wide shift/saturation register-enable cone.
  assign output_stage_ready = !output_valid;
  assign sum_stage_ready = !sum_valid || output_stage_ready;
  assign product_stage_ready = !product_valid || sum_stage_ready;
  assign input_ready = resetn && !flush && product_stage_ready;
  assign input_accept = input_valid && input_ready;

  assign extended_correlation_power =
    {{POWER_EXTENSION_BITS{1'b0}}, sum_correlation_power};
  assign shift_exceeds_ratio = sum_power_shift >= RATIO_BITS;
  assign shifted_power_loses_bits = shift_exceeds_ratio ?
    sum_correlation_power != 0 :
    (sum_correlation_power >> (RATIO_BITS - sum_power_shift)) != 0;
  assign numerator_overflow = sum_correlation_power != 0 &&
                              shifted_power_loses_bits;
  assign shifted_correlation_power =
    extended_correlation_power << sum_power_shift;

  initial begin
    if (RATIO_BITS < CORRELATION_POWER_BITS)
      $error("RATIO_BITS must retain the unshifted correlation power");
    if (COEFFICIENT_ENERGY == 0)
      $error("COEFFICIENT_ENERGY must be nonzero");
    if (DATA_WIDTH < 17 || DATA_WIDTH > 24)
      $error("DATA_WIDTH must lie in [17,24]");
  end

  always @(posedge clk) begin
    if (!resetn || flush) begin
      product_valid <= 1'b0;
      product_square_i <= 0;
      product_square_q <= 0;
      product_denominator <= 0;
      product_forward_exponent <= 0;
      product_inverse_exponent <= 0;
      product_start_index <= 0;
      sum_valid <= 1'b0;
      sum_correlation_power <= 0;
      sum_denominator <= 0;
      sum_power_shift <= 0;
      sum_start_index <= 0;
      output_valid <= 1'b0;
      output_numerator <= 0;
      output_denominator <= 0;
      output_power_shift <= 0;
      output_start_index <= 0;
      output_numerator_saturated <= 1'b0;
      output_denominator_zero <= 1'b0;
      accepted_pulse <= 1'b0;
      completed_pulse <= 1'b0;
      numerator_saturation_pulse <= 1'b0;
      denominator_zero_pulse <= 1'b0;
    end else begin
      accepted_pulse <= input_accept;
      completed_pulse <= 1'b0;
      numerator_saturation_pulse <= 1'b0;
      denominator_zero_pulse <= 1'b0;

      if (output_valid && output_ready)
        output_valid <= 1'b0;

      if (output_stage_ready) begin
        output_valid <= sum_valid;
        if (sum_valid) begin
          output_numerator <= numerator_overflow ?
                              {RATIO_BITS{1'b1}} :
                              shifted_correlation_power;
          output_denominator <= sum_denominator;
          output_power_shift <= sum_power_shift;
          output_start_index <= sum_start_index;
          output_numerator_saturated <= numerator_overflow;
          output_denominator_zero <= sum_denominator == 0;
          completed_pulse <= 1'b1;
          numerator_saturation_pulse <= numerator_overflow;
          denominator_zero_pulse <= sum_denominator == 0;
        end
      end

      if (sum_stage_ready) begin
        sum_valid <= product_valid;
        if (product_valid) begin
          sum_correlation_power <= product_square_i + product_square_q;
          sum_denominator <= product_denominator;
          sum_power_shift <=
            ({2'b00, product_forward_exponent} +
             {2'b00, product_inverse_exponent} +
             BASE_CORRELATION_SHIFT) << 1;
          sum_start_index <= product_start_index;
        end
      end

      if (product_stage_ready) begin
        product_valid <= input_accept;
        if (input_accept) begin
          product_square_i <=
            $signed(input_correlation_i) * $signed(input_correlation_i);
          product_square_q <=
            $signed(input_correlation_q) * $signed(input_correlation_q);
          product_denominator <= input_sample_energy * COEFFICIENT_ENERGY;
          product_forward_exponent <= input_forward_exponent;
          product_inverse_exponent <= input_inverse_exponent;
          product_start_index <= input_start_index;
        end
      end
    end
  end

endmodule
