// Experimental RX-only coarse correlator. No ready/backpressure output.
// One accepted CI16 sample per >=17 clocks; intended 2.5 MS/s at 100 MHz.
// 16 chronological complex Q15 coefficients, packed {Q,I}, conjugated in MAC.
// Outputs exact unscaled signed correlation and unsigned input window energy.
// Normalization, phase folding, CDC and IIO integration are separate stages.
module starlink_coarse25_mac #(
  parameter COEFFICIENT_FILE = "coarse25_q15.mem"
) (
  input wire clk,
  input wire reset,
  input wire sample_valid,
  input wire signed [15:0] sample_i,
  input wire signed [15:0] sample_q,
  input wire [63:0] sample_index,
  output reg result_valid,
  output reg signed [36:0] result_re,
  output reg signed [36:0] result_im,
  output reg [35:0] result_energy,
  output reg [63:0] result_first_index,
  output reg gap,
  output reg overrun
);
  reg signed [15:0] history_i [0:15];
  reg signed [15:0] history_q [0:15];
  reg [31:0] coefficients [0:15];
  initial $readmemh(COEFFICIENT_FILE, coefficients);
  reg [4:0] history_count;
  reg have_index;
  reg [63:0] last_index;
  reg busy;
  reg [3:0] tap;
  reg signed [36:0] sum_re, sum_im;
  reg [35:0] sum_energy;
  reg [63:0] pending_first_index;

  wire signed [15:0] xi = history_i[15-tap];
  wire signed [15:0] xq = history_q[15-tap];
  wire signed [15:0] hi = coefficients[tap][15:0];
  wire signed [15:0] hq = coefficients[tap][31:16];
  (* use_dsp = "yes" *) wire signed [31:0] ii = xi * hi;
  (* use_dsp = "yes" *) wire signed [31:0] qq = xq * hq;
  (* use_dsp = "yes" *) wire signed [31:0] qi = xq * hi;
  (* use_dsp = "yes" *) wire signed [31:0] iq = xi * hq;
  (* use_dsp = "yes" *) wire signed [31:0] energy_i = xi * xi;
  (* use_dsp = "yes" *) wire signed [31:0] energy_q = xq * xq;
  wire signed [36:0] next_re = sum_re + {{5{ii[31]}},ii} + {{5{qq[31]}},qq};
  wire signed [36:0] next_im = sum_im + {{5{qi[31]}},qi} - {{5{iq[31]}},iq};
  wire [35:0] next_energy = sum_energy + {4'b0,energy_i} + {4'b0,energy_q};
  wire discontinuity = have_index && (sample_index != last_index + 64'd1);
  integer n;

  always @(posedge clk) begin
    result_valid <= 0;
    gap <= 0;
    overrun <= 0;
    if (reset) begin
      history_count <= 0;
      have_index <= 0;
      last_index <= 0;
      busy <= 0;
      tap <= 0;
      sum_re <= 0;
      sum_im <= 0;
      sum_energy <= 0;
      pending_first_index <= 0;
      result_re <= 0;
      result_im <= 0;
      result_energy <= 0;
      result_first_index <= 0;
      for (n=0; n<16; n=n+1) begin
        history_i[n] <= 0;
        history_q[n] <= 0;
      end
    end else if (sample_valid) begin
      have_index <= 1;
      last_index <= sample_index;
      if (busy || discontinuity) begin
        // Abandon all partial arithmetic; current input starts a new epoch.
        // IQ transport is independent and is never stalled by this condition.
        gap <= discontinuity;
        overrun <= busy;
        busy <= 0;
        history_count <= 1;
        history_i[0] <= sample_i;
        history_q[0] <= sample_q;
        for (n=1; n<16; n=n+1) begin
          history_i[n] <= 0;
          history_q[n] <= 0;
        end
      end else begin
        history_i[0] <= sample_i;
        history_q[0] <= sample_q;
        for (n=1; n<16; n=n+1) begin
          history_i[n] <= history_i[n-1];
          history_q[n] <= history_q[n-1];
        end
        if (history_count < 16) history_count <= history_count + 1'b1;
        if (history_count >= 15) begin
          busy <= 1;
          tap <= 0;
          sum_re <= 0;
          sum_im <= 0;
          sum_energy <= 0;
          pending_first_index <= sample_index - 64'd15;
        end
      end
    end else if (busy) begin
      sum_re <= next_re;
      sum_im <= next_im;
      sum_energy <= next_energy;
      if (tap == 15) begin
        busy <= 0;
        result_valid <= 1;
        result_re <= next_re;
        result_im <= next_im;
        result_energy <= next_energy;
        result_first_index <= pending_first_index;
      end else tap <= tap + 1'b1;
    end
  end
endmodule
