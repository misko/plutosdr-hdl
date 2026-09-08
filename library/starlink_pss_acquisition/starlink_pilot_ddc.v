// SPDX-License-Identifier: GPL-2.0
// Experimental canonical 15 -> 2.5 MS/s pilot exporter. Not yet attached to
// receiver/DMA. All indexes remain in the canonical 15 MS/s coordinate.
`timescale 1ns/1ps
module starlink_pilot_ddc #(
  parameter integer FIFO_ADDRESS_BITS = 7,
  parameter MIXER_FILE = "pilot_mixer_q16.mem",
  parameter HALFBAND_FILE = "pilot_halfband2_q17.mem",
  parameter FIR3_FILE = "pilot_fir3_q17.mem"
) (
  input wire clk,
  input wire resetn,
  input wire flush,
  input wire edge_upper,
  input wire [31:0] visit_id,
  input wire input_valid,
  input wire input_gap,
  input wire signed [15:0] input_i,
  input wire signed [15:0] input_q,
  input wire [63:0] input_index,
  input wire input_support_valid,
  output wire output_valid,
  output wire signed [15:0] output_i,
  output wire signed [15:0] output_q,
  output wire [63:0] output_index,
  output wire [31:0] output_visit_id,
  output wire output_support_valid,
  output reg [63:0] accepted_sample_count,
  output reg [63:0] emitted_sample_count,
  output reg [31:0] saturation_event_count,
  output reg [FIFO_ADDRESS_BITS:0] fifo_high_water,
  output reg [7:0] sticky_fault,
  output reg halted
);
  localparam integer FIFO_DEPTH = 1 << FIFO_ADDRESS_BITS;
  generate if (FIFO_ADDRESS_BITS < 2 || FIFO_ADDRESS_BITS > 10) begin : g_bad_depth
    initial $fatal(1, "FIFO_ADDRESS_BITS must be between 2 and 10");
  end endgenerate

  reg locked, epoch_edge;
  reg [31:0] epoch_visit;
  reg [63:0] expected_index, head_index;
  reg [1:0] head_phase;
  reg [FIFO_ADDRESS_BITS-1:0] write_pointer, read_pointer;
  reg [FIFO_ADDRESS_BITS:0] fifo_count;
  reg [2:0] cooldown;
  reg pace_long;
  wire hb_halted, hb_sticky;
  wire fir_halted;
  wire [2:0] fir_sticky;
  wire sub_halted = hb_halted || fir_halted;
  wire pop_wanted = resetn && !flush && !halted && !sub_halted &&
      fifo_count != 0 && cooldown == 0;
  wire bad_index = input_valid &&
      ((&input_index) || (locked && input_index != expected_index));
  wire overflow = input_valid && fifo_count == FIFO_DEPTH && !pop_wanted;
  wire bad_config = locked && ((edge_upper != epoch_edge) || (visit_id != epoch_visit));
  wire [7:0] faults_now = {
    fir_halted && fir_sticky[2], fir_halted && fir_sticky[1],
    fir_halted && fir_sticky[0], hb_halted,
    input_gap, bad_config, overflow, bad_index
  };
  wire run = resetn && !flush && !halted && faults_now == 0;
  wire accept = run && input_valid;
  wire pop = run && pop_wanted;
  wire pipe_flush = flush || halted || faults_now != 0;

  // Small, explicitly bounded modulo-three reduction. Do not synthesize a
  // 64-bit generic divider to seed the absolute decimation phase.
  function automatic [1:0] mod3_byte;
    input [7:0] value;
    reg [3:0] sum;
    begin
      sum = {2'd0, value[1:0]} + {2'd0, value[3:2]} +
            {2'd0, value[5:4]} + {2'd0, value[7:6]};
      case (sum)
        0, 3, 6, 9, 12: mod3_byte = 0;
        1, 4, 7, 10: mod3_byte = 1;
        default: mod3_byte = 2;
      endcase
    end
  endfunction
  function automatic [1:0] phase_from_index;
    input [63:0] value;
    reg [63:0] half_index;
    reg [4:0] sum;
    integer byte_index;
    begin
      half_index = value >> 1;
      sum = 0;
      for (byte_index = 0; byte_index < 8; byte_index = byte_index + 1)
        sum = sum + {3'd0, mod3_byte(half_index[8*byte_index +: 8])};
      case (sum)
        0, 3, 6, 9, 12, 15: phase_from_index = 0;
        1, 4, 7, 10, 13, 16: phase_from_index = 1;
        default: phase_from_index = 2;
      endcase
    end
  endfunction

  (* ram_style = "block" *) reg [32:0] fifo_memory [0:FIFO_DEPTH-1];
  reg [32:0] read_data;
  reg [63:0] read_index;
  reg [1:0] read_phase;
  reg read_valid;
  always @(posedge clk) begin
    if (accept) fifo_memory[write_pointer] <= {input_support_valid, input_q, input_i};
    if (pop) read_data <= fifo_memory[read_pointer];
  end

  // LUT stores {Q18(-sin), Q18(cos)} with 16 fractional bits.
  (* rom_style = "distributed" *) reg [35:0] mixer [0:63];
  initial $readmemh(MIXER_FILE, mixer);
  wire [5:0] twelve_n = (read_index[5:0] << 3) + (read_index[5:0] << 2);
  wire [5:0] phase = epoch_edge ? twelve_n : -(twelve_n + read_index[5:0]);
  wire signed [17:0] rotation_i = mixer[phase][17:0];
  wire signed [17:0] rotation_q = mixer[phase][35:18];
  wire signed [15:0] source_i = read_data[15:0];
  wire signed [15:0] source_q = read_data[31:16];
  (* use_dsp = "yes" *) reg signed [33:0] product_ic, product_qs, product_is, product_qc;
  reg signed [34:0] sum_i, sum_q;
  reg multiply_valid, sum_valid, mixed_valid;
  reg signed [15:0] mixed_i, mixed_q;
  reg [1:0] mixed_saturations;
  reg [63:0] mixed_index;
  reg [1:0] mixed_phase;
  reg mixed_support;
  always @(posedge clk) begin
    product_ic <= source_i * rotation_i;
    product_qs <= source_q * rotation_q;
    product_is <= source_i * rotation_q;
    product_qc <= source_q * rotation_i;
    sum_i <= $signed({product_ic[33], product_ic}) - $signed({product_qs[33], product_qs});
    sum_q <= $signed({product_is[33], product_is}) + $signed({product_qc[33], product_qc});
  end
  function automatic [16:0] quantize_q16;
    input signed [34:0] value;
    reg [34:0] magnitude;
    reg [19:0] rounded;
    begin
      magnitude = value[34] ? -value : value;
      rounded = {1'b0, magnitude[34:16]} +
          ((magnitude[15:0] > 16'h8000) ||
           ((magnitude[15:0] == 16'h8000) && magnitude[16]));
      if (value[34]) begin
        if (rounded > 32768) quantize_q16 = {1'b1, 16'h8000};
        else quantize_q16 = {1'b0, -rounded[15:0]};
      end else begin
        if (rounded > 32767) quantize_q16 = {1'b1, 16'h7fff};
        else quantize_q16 = {1'b0, rounded[15:0]};
      end
    end
  endfunction
  wire [16:0] quantized_i = quantize_q16(sum_i);
  wire [16:0] quantized_q = quantize_q16(sum_q);
  always @(posedge clk) begin
    mixed_i <= quantized_i[15:0];
    mixed_q <= quantized_q[15:0];
    mixed_saturations <= {1'b0, quantized_i[16]} + {1'b0, quantized_q[16]};
    mixed_index <= read_index;
    mixed_phase <= read_phase;
    mixed_support <= read_data[32];
  end

  wire hb_valid, hb_support;
  wire signed [15:0] hb_i, hb_q;
  wire [63:0] hb_index;
  wire [1:0] hb_phase, hb_saturations;
  wire fir_valid;
  wire [1:0] fir_saturations;
  starlink_pilot_halfband2 #(.COEFFICIENT_FILE(HALFBAND_FILE)) halfband (
    .clk(clk), .resetn(resetn), .flush(pipe_flush),
    .input_valid(mixed_valid), .input_i(mixed_i), .input_q(mixed_q),
    .input_index(mixed_index), .input_phase(mixed_phase),
    .input_support_valid(mixed_support),
    .output_valid(hb_valid), .output_i(hb_i), .output_q(hb_q),
    .output_index(hb_index), .output_phase(hb_phase),
    .output_support_valid(hb_support), .output_saturations(hb_saturations),
    .sticky_overrun(hb_sticky), .halted(hb_halted)
  );
  starlink_pilot_fir3 #(.COEFFICIENT_FILE(FIR3_FILE)) fir3 (
    .clk(clk), .resetn(resetn), .flush(pipe_flush),
    .input_valid(hb_valid), .input_i(hb_i), .input_q(hb_q),
    .input_index(hb_index), .input_phase(hb_phase), .input_support_valid(hb_support),
    .output_valid(fir_valid), .output_i(output_i), .output_q(output_q),
    .output_index(output_index), .output_support_valid(output_support_valid),
    .output_saturations(fir_saturations), .sticky_fault(fir_sticky), .halted(fir_halted)
  );
  assign output_valid = fir_valid && run;
  assign output_visit_id = epoch_visit;
  wire [3:0] clip_increment =
      (mixed_valid ? {2'd0, mixed_saturations} : 4'd0) +
      (hb_valid ? {2'd0, hb_saturations} : 4'd0) +
      (fir_valid ? {2'd0, fir_saturations} : 4'd0);
  wire [32:0] clips_next = {1'b0, saturation_event_count} + clip_increment;

  always @(posedge clk) begin
    if (!resetn) begin
      accepted_sample_count <= 0;
      emitted_sample_count <= 0;
      saturation_event_count <= 0;
      fifo_high_water <= 0;
      sticky_fault <= 0;
      halted <= 0;
    end else begin
      if (accept && !(&accepted_sample_count)) accepted_sample_count <= accepted_sample_count + 1'b1;
      if (output_valid && !(&emitted_sample_count)) emitted_sample_count <= emitted_sample_count + 1'b1;
      if (run) saturation_event_count <= clips_next[32] ? 32'hffffffff : clips_next[31:0];
      if (fifo_count > fifo_high_water) fifo_high_water <= fifo_count;
      if (flush) halted <= 0;
      else if (!halted && faults_now != 0) begin
        sticky_fault <= sticky_fault | faults_now;
        halted <= 1;
      end
    end
    if (!run) begin
      locked <= 0;
      epoch_edge <= 0;
      epoch_visit <= 0;
      expected_index <= 0;
      head_index <= 0;
      head_phase <= 0;
      write_pointer <= 0;
      read_pointer <= 0;
      fifo_count <= 0;
      cooldown <= 0;
      pace_long <= 0;
      read_index <= 0;
      read_phase <= 0;
      read_valid <= 0;
      multiply_valid <= 0;
      sum_valid <= 0;
      mixed_valid <= 0;
    end else begin
      read_valid <= pop;
      multiply_valid <= read_valid;
      sum_valid <= multiply_valid;
      mixed_valid <= sum_valid;
      if (cooldown != 0) cooldown <= cooldown - 1'b1;
      case ({accept, pop})
        2'b10: fifo_count <= fifo_count + 1'b1;
        2'b01: fifo_count <= fifo_count - 1'b1;
        default: ;
      endcase
      if (accept) begin
        locked <= 1;
        expected_index <= input_index + 1'b1;
        write_pointer <= write_pointer + 1'b1;
        if (!locked) begin
          head_index <= input_index;
          head_phase <= phase_from_index(input_index);
          epoch_edge <= edge_upper;
          epoch_visit <= visit_id;
        end
      end
      if (pop) begin
        read_pointer <= read_pointer + 1'b1;
        read_index <= head_index;
        read_phase <= head_phase;
        head_index <= head_index + 1'b1;
        if (head_index[0]) head_phase <= head_phase == 2 ? 0 : head_phase + 1'b1;
        cooldown <= pace_long ? 6 : 5;
        pace_long <= !pace_long;
      end
    end
  end
endmodule
