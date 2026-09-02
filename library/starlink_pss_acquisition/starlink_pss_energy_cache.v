// Exact CI16 sliding energy and absolute-indexed retention for PSS scoring.
//
// Every contiguous 66-sample window produces sum(I**2 + Q**2) as an unsigned
// 38-bit value. Results are retained in an absolute-indexed circular BRAM so
// the later IFFT output stream can request its matching denominator without
// depending on transform latency. Gaps, index discontinuities, flush, and
// disable invalidate the complete window and cache state.

`timescale 1ns/1ps

module starlink_pss_energy_cache #(
  parameter integer WINDOW_SAMPLES = 66,
  parameter integer CACHE_ENTRIES = 2048,
  parameter integer CACHE_ADDRESS_BITS = $clog2(CACHE_ENTRIES),
  parameter integer WINDOW_COUNT_BITS = $clog2(WINDOW_SAMPLES + 1),
  parameter integer HISTORY_ADDRESS_BITS = $clog2(WINDOW_SAMPLES)
) (
  input  wire                            clk,
  input  wire                            resetn,
  input  wire                            enable,
  input  wire                            flush,

  input  wire                            sample_valid,
  input  wire                            sample_gap,
  input  wire signed [15:0]              sample_i,
  input  wire signed [15:0]              sample_q,
  input  wire [63:0]                     sample_index,

  input  wire                            lookup_valid,
  output wire                            lookup_ready,
  input  wire [63:0]                     lookup_start_index,
  output reg                             output_valid,
  input  wire                            output_ready,
  output wire [37:0]                     output_energy,
  output reg [63:0]                      output_start_index,
  output reg                             output_found,

  output reg                             energy_write_pulse,
  output reg [37:0]                      energy_write_value,
  output reg [63:0]                      energy_write_start_index,
  output reg                             gap_pulse,
  output reg                             index_error_pulse,
  output reg                             restart_pulse,
  output reg                             retention_miss_pulse,
  output reg [CACHE_ADDRESS_BITS:0]      stored_energy_count,
  output reg [63:0]                      oldest_energy_start_index,
  output reg [63:0]                      newest_energy_start_index
);

  (* use_dsp = "yes" *) reg [31:0] square_i;
  (* use_dsp = "yes" *) reg [31:0] square_q;
  reg square_valid;
  reg [63:0] square_sample_index;

  (* ram_style = "distributed" *)
  reg [31:0] power_history [0:WINDOW_SAMPLES-1];
  reg [HISTORY_ADDRESS_BITS-1:0] history_pointer;
  reg [WINDOW_COUNT_BITS-1:0] window_sample_count;
  reg [37:0] window_energy;

  (* ram_style = "block" *)
  reg [37:0] energy_memory [0:CACHE_ENTRIES-1];

  reg segment_active;
  reg [63:0] expected_sample_index;
  reg [37:0] energy_read_data;
  reg output_bypass_valid;
  reg [37:0] output_bypass_energy;

  wire input_restart;
  wire [31:0] square_power;
  wire [37:0] extended_square_power;
  wire [37:0] extended_oldest_power;
  wire [37:0] next_window_energy;
  wire energy_will_write;
  wire [63:0] next_energy_start_index;
  wire [CACHE_ADDRESS_BITS-1:0] energy_write_address;
  wire [CACHE_ADDRESS_BITS-1:0] lookup_address;
  wire lookup_hits_new_energy;
  wire lookup_in_retained_range;
  wire lookup_overwrite_collision;
  wire lookup_found_now;
  wire output_stage_ready;
  wire lookup_accept;

  assign input_restart = sample_valid &&
    (sample_gap || !segment_active ||
     sample_index != expected_sample_index);
  assign square_power = square_i + square_q;
  assign extended_square_power = {{6{1'b0}}, square_power};
  assign extended_oldest_power =
    {{6{1'b0}}, power_history[history_pointer]};
  assign next_window_energy =
    (window_sample_count < WINDOW_SAMPLES) ?
      window_energy + extended_square_power :
      window_energy + extended_square_power - extended_oldest_power;
  assign energy_will_write = enable && !flush && !input_restart &&
    square_valid && window_sample_count >= WINDOW_SAMPLES - 1;
  assign next_energy_start_index =
    square_sample_index - (WINDOW_SAMPLES - 1);
  assign energy_write_address =
    next_energy_start_index[CACHE_ADDRESS_BITS-1:0];
  assign lookup_address =
    lookup_start_index[CACHE_ADDRESS_BITS-1:0];

  assign lookup_hits_new_energy = energy_will_write &&
    lookup_start_index == next_energy_start_index;
  assign lookup_in_retained_range = stored_energy_count != 0 &&
    lookup_start_index >= oldest_energy_start_index &&
    lookup_start_index <= newest_energy_start_index;
  assign lookup_overwrite_collision = energy_will_write &&
    stored_energy_count == CACHE_ENTRIES &&
    lookup_start_index == oldest_energy_start_index &&
    !lookup_hits_new_energy;
  assign lookup_found_now = lookup_hits_new_energy ||
    (lookup_in_retained_range && !lookup_overwrite_collision);

  assign output_stage_ready = !output_valid || output_ready;
  assign lookup_ready = resetn && enable && !flush && !input_restart &&
    output_stage_ready;
  assign lookup_accept = lookup_valid && lookup_ready;
  assign output_energy = output_bypass_valid ?
                         output_bypass_energy : energy_read_data;

  always @(posedge clk) begin
    if (!resetn) begin
      square_i <= 0;
      square_q <= 0;
      square_valid <= 1'b0;
      square_sample_index <= 0;
      history_pointer <= 0;
      window_sample_count <= 0;
      window_energy <= 0;
      segment_active <= 1'b0;
      expected_sample_index <= 0;
      output_valid <= 1'b0;
      output_start_index <= 0;
      output_found <= 1'b0;
      output_bypass_valid <= 1'b0;
      output_bypass_energy <= 0;
      energy_write_pulse <= 1'b0;
      energy_write_value <= 0;
      energy_write_start_index <= 0;
      gap_pulse <= 1'b0;
      index_error_pulse <= 1'b0;
      restart_pulse <= 1'b0;
      retention_miss_pulse <= 1'b0;
      stored_energy_count <= 0;
      oldest_energy_start_index <= 0;
      newest_energy_start_index <= 0;
    end else if (!enable || flush) begin
      square_valid <= 1'b0;
      history_pointer <= 0;
      window_sample_count <= 0;
      window_energy <= 0;
      segment_active <= 1'b0;
      expected_sample_index <= 0;
      output_valid <= 1'b0;
      output_found <= 1'b0;
      output_bypass_valid <= 1'b0;
      energy_write_pulse <= 1'b0;
      gap_pulse <= 1'b0;
      index_error_pulse <= 1'b0;
      restart_pulse <= 1'b0;
      retention_miss_pulse <= 1'b0;
      stored_energy_count <= 0;
      oldest_energy_start_index <= 0;
      newest_energy_start_index <= 0;
    end else begin
      energy_write_pulse <= 1'b0;
      gap_pulse <= 1'b0;
      index_error_pulse <= 1'b0;
      restart_pulse <= 1'b0;
      retention_miss_pulse <= 1'b0;

      // Keep this as a pure synchronous read so the 2K-by-38 cache infers a
      // simple-dual-port block RAM. The independently registered bypass mux
      // below defines a same-address newest-value result.
      if (lookup_accept)
        energy_read_data <= energy_memory[lookup_address];

      if (output_stage_ready) begin
        output_valid <= lookup_accept;
        if (lookup_accept) begin
          output_bypass_valid <= lookup_hits_new_energy;
          output_bypass_energy <= next_window_energy;
          output_start_index <= lookup_start_index;
          output_found <= lookup_found_now;
          retention_miss_pulse <= !lookup_found_now;
        end else begin
          output_bypass_valid <= 1'b0;
          output_found <= 1'b0;
        end
      end

      square_valid <= sample_valid;
      if (sample_valid) begin
        square_i <= $signed(sample_i) * $signed(sample_i);
        square_q <= $signed(sample_q) * $signed(sample_q);
        square_sample_index <= sample_index;
        segment_active <= 1'b1;
        expected_sample_index <= sample_index + 1'b1;
      end

      if (input_restart) begin
        // Discard any previous segment item still in the square pipeline and
        // retain the current input as sample zero of the new segment.
        history_pointer <= 0;
        window_sample_count <= 0;
        window_energy <= 0;
        output_valid <= 1'b0;
        output_found <= 1'b0;
        output_bypass_valid <= 1'b0;
        stored_energy_count <= 0;
        oldest_energy_start_index <= 0;
        newest_energy_start_index <= 0;
        gap_pulse <= sample_gap;
        index_error_pulse <= segment_active && !sample_gap &&
                             sample_index != expected_sample_index;
        restart_pulse <= 1'b1;
      end else if (square_valid) begin
        power_history[history_pointer] <= square_power;
        if (history_pointer == WINDOW_SAMPLES - 1)
          history_pointer <= 0;
        else
          history_pointer <= history_pointer + 1'b1;

        window_energy <= next_window_energy;
        if (window_sample_count < WINDOW_SAMPLES)
          window_sample_count <= window_sample_count + 1'b1;

        if (energy_will_write) begin
          energy_memory[energy_write_address] <= next_window_energy;
          energy_write_pulse <= 1'b1;
          energy_write_value <= next_window_energy;
          energy_write_start_index <= next_energy_start_index;
          newest_energy_start_index <= next_energy_start_index;
          if (stored_energy_count == 0)
            oldest_energy_start_index <= next_energy_start_index;
          else if (stored_energy_count == CACHE_ENTRIES)
            oldest_energy_start_index <= oldest_energy_start_index + 1'b1;
          if (stored_energy_count < CACHE_ENTRIES)
            stored_energy_count <= stored_energy_count + 1'b1;
        end
      end
    end
  end

endmodule
