// Elastic fixed-point complex spectrum product for Starlink PSS acquisition.
//
// The forward-XFFT and precomputed-kernel components are both signed
// Q1.(DATA_WIDTH-1). Their complex product is divided by 2**DATA_WIDTH: the
// fractional bits plus the frozen one-bit safety shift. Rounding is signed
// round-to-nearest,
// ties-to-even. The three-stage pipeline accepts one bin per clock, propagates
// block metadata unchanged, and holds every output stable under backpressure.

`timescale 1ns/1ps

module starlink_pss_spectrum_product #(
  parameter integer DATA_WIDTH = 24
) (
  input  wire                 clk,
  input  wire                 resetn,
  input  wire                 flush,

  input  wire                 input_valid,
  output wire                 input_ready,
  input  wire signed [DATA_WIDTH-1:0] input_i,
  input  wire signed [DATA_WIDTH-1:0] input_q,
  input  wire signed [DATA_WIDTH-1:0] kernel_i,
  input  wire signed [DATA_WIDTH-1:0] kernel_q,
  input  wire [8:0]           input_bin_index,
  input  wire [4:0]           input_block_exponent,
  input  wire                 input_last,
  input  wire [63:0]          input_block_start_index,

  output reg                  output_valid,
  input  wire                 output_ready,
  output reg signed [DATA_WIDTH-1:0] output_i,
  output reg signed [DATA_WIDTH-1:0] output_q,
  output reg [8:0]            output_bin_index,
  output reg [4:0]            output_block_exponent,
  output reg                  output_last,
  output reg [63:0]           output_block_start_index,
  output reg                  output_overflow,
  output reg                  overflow_pulse
);

  localparam integer PRODUCT_WIDTH = 2 * DATA_WIDTH;
  localparam integer SUM_WIDTH = PRODUCT_WIDTH + 1;
  localparam integer ROUND_SHIFT = DATA_WIDTH;
  localparam signed [SUM_WIDTH:0] COMPONENT_MAX = {
    {(SUM_WIDTH+1-DATA_WIDTH){1'b0}},
    1'b0, {(DATA_WIDTH-1){1'b1}}
  };
  localparam signed [SUM_WIDTH:0] COMPONENT_MIN = {
    {(SUM_WIDTH+1-DATA_WIDTH){1'b1}},
    1'b1, {(DATA_WIDTH-1){1'b0}}
  };

  (* use_dsp = "yes" *) reg signed [PRODUCT_WIDTH-1:0] product_ii;
  (* use_dsp = "yes" *) reg signed [PRODUCT_WIDTH-1:0] product_qq;
  (* use_dsp = "yes" *) reg signed [PRODUCT_WIDTH-1:0] product_iq;
  (* use_dsp = "yes" *) reg signed [PRODUCT_WIDTH-1:0] product_qi;
  reg product_valid;
  reg [8:0] product_bin_index;
  reg [4:0] product_block_exponent;
  reg product_last;
  reg [63:0] product_block_start_index;

  reg signed [SUM_WIDTH-1:0] sum_real;
  reg signed [SUM_WIDTH-1:0] sum_imag;
  reg sum_valid;
  reg [8:0] sum_bin_index;
  reg [4:0] sum_block_exponent;
  reg sum_last;
  reg [63:0] sum_block_start_index;

  wire output_stage_ready;
  wire sum_stage_ready;
  wire product_stage_ready;
  wire [DATA_WIDTH:0] rounded_real;
  wire [DATA_WIDTH:0] rounded_imag;

  assign output_stage_ready = !output_valid || output_ready;
  assign sum_stage_ready = !sum_valid || output_stage_ready;
  assign product_stage_ready = !product_valid || sum_stage_ready;
  assign input_ready = resetn && !flush && product_stage_ready;
  assign rounded_real = round_and_saturate(sum_real);
  assign rounded_imag = round_and_saturate(sum_imag);

  // The MSB is the overflow flag; the remaining bits are the saturated
  // Q1.(DATA_WIDTH-1) result.
  function automatic [DATA_WIDTH:0] round_and_saturate;
    input signed [SUM_WIDTH-1:0] value;
    reg signed [SUM_WIDTH-1:0] quotient;
    reg [ROUND_SHIFT-1:0] remainder;
    reg increment;
    reg signed [SUM_WIDTH:0] rounded;
    begin
      quotient = value >>> ROUND_SHIFT;
      remainder = value[ROUND_SHIFT-1:0];
      increment = (remainder > {1'b1, {(ROUND_SHIFT-1){1'b0}}}) ||
        ((remainder == {1'b1, {(ROUND_SHIFT-1){1'b0}}}) && quotient[0]);
      rounded = $signed({quotient[SUM_WIDTH-1], quotient}) + increment;
      if (rounded > COMPONENT_MAX)
        round_and_saturate = {
          1'b1, 1'b0, {(DATA_WIDTH-1){1'b1}}
        };
      else if (rounded < COMPONENT_MIN)
        round_and_saturate = {
          1'b1, 1'b1, {(DATA_WIDTH-1){1'b0}}
        };
      else
        round_and_saturate = {1'b0, rounded[DATA_WIDTH-1:0]};
    end
  endfunction

  always @(posedge clk) begin
    if (!resetn || flush) begin
      product_valid <= 1'b0;
      sum_valid <= 1'b0;
      output_valid <= 1'b0;
      product_ii <= 0;
      product_qq <= 0;
      product_iq <= 0;
      product_qi <= 0;
      product_bin_index <= 0;
      product_block_exponent <= 0;
      product_last <= 1'b0;
      product_block_start_index <= 0;
      sum_real <= 0;
      sum_imag <= 0;
      sum_bin_index <= 0;
      sum_block_exponent <= 0;
      sum_last <= 1'b0;
      sum_block_start_index <= 0;
      output_i <= 0;
      output_q <= 0;
      output_bin_index <= 0;
      output_block_exponent <= 0;
      output_last <= 1'b0;
      output_block_start_index <= 0;
      output_overflow <= 1'b0;
      overflow_pulse <= 1'b0;
    end else begin
      overflow_pulse <= 1'b0;

      if (output_stage_ready) begin
        output_valid <= sum_valid;
        if (sum_valid) begin
          output_i <= rounded_real[DATA_WIDTH-1:0];
          output_q <= rounded_imag[DATA_WIDTH-1:0];
          output_bin_index <= sum_bin_index;
          output_block_exponent <= sum_block_exponent;
          output_last <= sum_last;
          output_block_start_index <= sum_block_start_index;
          output_overflow <= rounded_real[DATA_WIDTH] ||
                             rounded_imag[DATA_WIDTH];
          overflow_pulse <= rounded_real[DATA_WIDTH] ||
                            rounded_imag[DATA_WIDTH];
        end else begin
          output_overflow <= 1'b0;
        end
      end

      if (sum_stage_ready) begin
        sum_valid <= product_valid;
        if (product_valid) begin
          sum_real <= $signed({product_ii[PRODUCT_WIDTH-1], product_ii}) -
                      $signed({product_qq[PRODUCT_WIDTH-1], product_qq});
          sum_imag <= $signed({product_iq[PRODUCT_WIDTH-1], product_iq}) +
                      $signed({product_qi[PRODUCT_WIDTH-1], product_qi});
          sum_bin_index <= product_bin_index;
          sum_block_exponent <= product_block_exponent;
          sum_last <= product_last;
          sum_block_start_index <= product_block_start_index;
        end
      end

      if (product_stage_ready) begin
        product_valid <= input_valid;
        if (input_valid) begin
          product_ii <= input_i * kernel_i;
          product_qq <= input_q * kernel_q;
          product_iq <= input_i * kernel_q;
          product_qi <= input_q * kernel_i;
          product_bin_index <= input_bin_index;
          product_block_exponent <= input_block_exponent;
          product_last <= input_last;
          product_block_start_index <= input_block_start_index;
        end
      end
    end
  end

endmodule
