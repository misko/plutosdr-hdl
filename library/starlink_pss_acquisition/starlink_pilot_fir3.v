// SPDX-License-Identifier: GPL-2.0
// Experimental pilot exporter: 7.5 -> 2.5 MS/s, symmetric 255-tap Q17 FIR.
// Eight time-shared multipliers, four dual-port RAM banks. Not yet integrated
// with the receiver, DMA, or hop controller. See PILOT_DDC.md for the contract.
`timescale 1ns/1ps

module starlink_pilot_fir3 #(
  parameter COEFFICIENT_FILE = "pilot_fir3_q17.mem"
) (
  input wire clk,
  input wire resetn,
  input wire flush,
  input wire input_valid,
  input wire signed [15:0] input_i,
  input wire signed [15:0] input_q,
  input wire [63:0] input_index,
  input wire [1:0] input_phase,
  input wire input_support_valid,
  output reg output_valid,
  output reg signed [15:0] output_i,
  output reg signed [15:0] output_q,
  output reg [63:0] output_index,
  output reg output_support_valid,
  output reg [1:0] output_saturations,
  output reg [2:0] sticky_fault,
  output reg halted
);
  // index is the absolute canonical 15 MS/s index: even and advancing by two.
  // phase is (index / 2) mod 3, supplied without a wide modulo operator here.
  // A flush fences all in-flight work and clears histories, NOT sticky faults.
  reg locked;
  reg [63:0] expected_index;
  reg [1:0] expected_phase;
  reg [8:0] write_address;
  reg [7:0] history_count;
  reg [7:0] support_count;
  reg busy;
  reg issuing;
  reg [4:0] issue_row;
  reg [8:0] job_address;
  reg [7:0] job_history;
  reg [63:0] job_index;
  reg job_support;

  wire bad_index = input_valid &&
      (input_index[0] || (locked && input_index != expected_index));
  wire bad_phase = input_valid &&
      ((input_phase == 3) || (locked && input_phase != expected_phase));
  wire overrun = input_valid && (input_phase == 0) && busy;
  wire fault_now = bad_index || bad_phase || overrun;
  wire run = resetn && !flush && !halted && !fault_now;
  wire accept = run && input_valid;
  wire start_job = accept && (input_phase == 0);
  // Incoming samples own port A for one cycle; issue pauses, never the ADC.
  wire issue = run && issuing && !input_valid;

  wire [8:0] address_a [0:3];
  wire [8:0] address_b [0:3];
  wire [7:0] tap_a [0:3];
  wire [7:0] tap_b [0:3];
  wire [6:0] bank_address_a [0:3];
  wire [6:0] bank_address_b [0:3];
  wire [31:0] bank_data_a [0:3];
  wire [31:0] bank_data_b [0:3];
  reg [3:0] pad_a;
  reg [3:0] pad_b;

  genvar lane;
  generate for (lane = 0; lane < 4; lane = lane + 1) begin : g_bank
    localparam [1:0] BANK = lane;
    // Each side is a permutation of all four banks, so no replication or
    // third memory port is required. 512 entries prevent the live writer
    // from overwriting the oldest part of a 255-sample window still in use.
    wire [1:0] lane_a = job_address[1:0] - BANK;
    wire [1:0] lane_b = BANK - job_address[1:0] + 2'd2;
    assign tap_a[lane] = {1'b0, issue_row, 2'b00} + lane;
    assign tap_b[lane] = 8'd254 - tap_a[lane];
    assign address_a[lane] = job_address - tap_a[lane];
    assign address_b[lane] = job_address - tap_b[lane];
    assign bank_address_a[lane] = address_a[lane_a][8:2];
    assign bank_address_b[lane] = address_b[lane_b][8:2];

    (* ram_style = "block" *) reg [31:0] memory [0:127];
    reg [31:0] read_a;
    reg [31:0] read_b;
    always @(posedge clk) begin
      if (accept && write_address[1:0] == BANK)
        memory[write_address[8:2]] <= {input_q, input_i};
      else if (issue)
        read_a <= memory[bank_address_a[lane]];
    end
    always @(posedge clk) begin
      if (issue)
        read_b <= memory[bank_address_b[lane]];
    end
    assign bank_data_a[lane] = read_a;
    assign bank_data_b[lane] = read_b;
  end endgenerate

  (* rom_style = "distributed" *) reg signed [17:0] coefficient [0:127];
  initial $readmemh(COEFFICIENT_FILE, coefficient);
  reg signed [17:0] coefficient_read [0:3];
  reg signed [17:0] coefficient_pair [0:3];
  reg signed [16:0] pair_i [0:3];
  reg signed [16:0] pair_q [0:3];
  (* use_dsp = "yes" *) reg signed [34:0] product_i [0:3];
  (* use_dsp = "yes" *) reg signed [34:0] product_q [0:3];
  reg signed [41:0] accumulator_i [0:3];
  reg signed [41:0] accumulator_q [0:3];
  reg read_valid, pair_valid, product_valid;
  reg read_first, pair_first, product_first;
  reg read_last, pair_last, product_last;
  reg sum_valid;
  reg signed [43:0] total_i, total_q;
  reg total_valid;
  reg [63:0] total_index;
  reg total_support;

  generate for (lane = 0; lane < 4; lane = lane + 1) begin : g_mac
    wire [1:0] bank_a = job_address[1:0] - lane;
    wire [1:0] bank_b = job_address[1:0] - 2'd2 + lane;
    wire signed [15:0] a_i = pad_a[lane] ? 16'sd0 : bank_data_a[bank_a][15:0];
    wire signed [15:0] a_q = pad_a[lane] ? 16'sd0 : bank_data_a[bank_a][31:16];
    wire signed [15:0] b_i = pad_b[lane] ? 16'sd0 : bank_data_b[bank_b][15:0];
    wire signed [15:0] b_q = pad_b[lane] ? 16'sd0 : bank_data_b[bank_b][31:16];
    always @(posedge clk) begin
      if (issue) begin
        coefficient_read[lane] <= coefficient[{issue_row, 2'b00} + lane];
        pad_a[lane] <= tap_a[lane] >= job_history;
        pad_b[lane] <= (tap_b[lane] >= job_history) || (tap_a[lane] == 127);
      end
      // Arithmetic runs without stage-specific enables for tighter packing.
      coefficient_pair[lane] <= coefficient_read[lane];
      pair_i[lane] <= $signed({a_i[15], a_i}) + $signed({b_i[15], b_i});
      pair_q[lane] <= $signed({a_q[15], a_q}) + $signed({b_q[15], b_q});
      product_i[lane] <= pair_i[lane] * coefficient_pair[lane];
      product_q[lane] <= pair_q[lane] * coefficient_pair[lane];
      if (product_valid) begin
        if (product_first) begin
          accumulator_i[lane] <= {{7{product_i[lane][34]}}, product_i[lane]};
          accumulator_q[lane] <= {{7{product_q[lane][34]}}, product_q[lane]};
        end else begin
          accumulator_i[lane] <= accumulator_i[lane] +
              {{7{product_i[lane][34]}}, product_i[lane]};
          accumulator_q[lane] <= accumulator_q[lane] +
              {{7{product_q[lane][34]}}, product_q[lane]};
        end
      end
    end
  end endgenerate

  // {saturated, CI16}; signed magnitude, nearest with ties to even.
  function automatic [16:0] quantize_q17;
    input signed [43:0] value;
    reg [43:0] magnitude;
    reg [27:0] rounded;
    begin
      magnitude = value[43] ? -value : value;
      rounded = {1'b0, magnitude[43:17]} +
          ((magnitude[16:0] > 17'h10000) ||
           ((magnitude[16:0] == 17'h10000) && magnitude[17]));
      if (value[43]) begin
        if (rounded > 32768) quantize_q17 = {1'b1, 16'h8000};
        else quantize_q17 = {1'b0, -rounded[15:0]};
      end else begin
        if (rounded > 32767) quantize_q17 = {1'b1, 16'h7fff};
        else quantize_q17 = {1'b0, rounded[15:0]};
      end
    end
  endfunction
  wire [16:0] quantized_i = quantize_q17(total_i);
  wire [16:0] quantized_q = quantize_q17(total_q);

  always @(posedge clk) begin
    total_i <= $signed({{2{accumulator_i[0][41]}}, accumulator_i[0]})
        + $signed({{2{accumulator_i[1][41]}}, accumulator_i[1]})
        + $signed({{2{accumulator_i[2][41]}}, accumulator_i[2]})
        + $signed({{2{accumulator_i[3][41]}}, accumulator_i[3]});
    total_q <= $signed({{2{accumulator_q[0][41]}}, accumulator_q[0]})
        + $signed({{2{accumulator_q[1][41]}}, accumulator_q[1]})
        + $signed({{2{accumulator_q[2][41]}}, accumulator_q[2]})
        + $signed({{2{accumulator_q[3][41]}}, accumulator_q[3]});
    if (sum_valid) begin
      total_index <= job_index;
      total_support <= job_support;
    end
    output_i <= quantized_i[15:0];
    output_q <= quantized_q[15:0];
    output_index <= total_index;
    output_support_valid <= total_support;
    output_saturations <= {1'b0, quantized_i[16]} + {1'b0, quantized_q[16]};
  end

  always @(posedge clk) begin
    if (!resetn) begin
      sticky_fault <= 0;
      halted <= 0;
    end else begin
      if (flush) halted <= 0;
      else if (!halted && fault_now) begin
        sticky_fault <= sticky_fault | {overrun, bad_phase, bad_index};
        halted <= 1;
      end
    end
    if (!run) begin
      locked <= 0;
      expected_index <= 0;
      expected_phase <= 0;
      write_address <= 0;
      history_count <= 0;
      support_count <= 0;
      busy <= 0;
      issuing <= 0;
      issue_row <= 0;
      job_address <= 0;
      job_history <= 0;
      job_index <= 0;
      job_support <= 0;
      read_valid <= 0;
      pair_valid <= 0;
      product_valid <= 0;
      read_first <= 0;
      pair_first <= 0;
      product_first <= 0;
      read_last <= 0;
      pair_last <= 0;
      product_last <= 0;
      sum_valid <= 0;
      total_valid <= 0;
      output_valid <= 0;
    end else begin
      read_valid <= issue;
      read_first <= issue_row == 0;
      read_last <= issue_row == 31;
      pair_valid <= read_valid;
      pair_first <= read_first;
      pair_last <= read_last;
      product_valid <= pair_valid;
      product_first <= pair_first;
      product_last <= pair_last;
      sum_valid <= product_valid && product_last;
      total_valid <= sum_valid;
      output_valid <= total_valid;
      if (sum_valid) busy <= 0;
      if (accept) begin
        locked <= 1;
        expected_index <= input_index + 2;
        expected_phase <= input_phase == 2 ? 0 : input_phase + 1'b1;
        write_address <= write_address + 1'b1;
        if (history_count != 255) history_count <= history_count + 1'b1;
        if (!input_support_valid) support_count <= 0;
        else if (support_count != 255) support_count <= support_count + 1'b1;
      end
      if (start_job) begin
        busy <= 1;
        issuing <= 1;
        issue_row <= 0;
        job_address <= write_address;
        job_history <= history_count == 255 ? 255 : history_count + 1'b1;
        job_index <= input_index;
        job_support <= input_support_valid && support_count >= 254;
      end else if (issue) begin
        if (issue_row == 31) issuing <= 0;
        else issue_row <= issue_row + 1'b1;
      end
    end
  end
endmodule
