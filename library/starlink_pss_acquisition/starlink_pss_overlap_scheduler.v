// Continuous overlap-save input scheduler for Starlink PSS acquisition.
//
// This block is deliberately independent of any FFT implementation. It
// accepts a gap-tagged, non-backpressured CI16 stream, retains samples in a
// power-of-two ring, and emits complete overlapping FFT input frames through a
// conventional ready/valid interface. Any continuity or retention failure
// aborts the partial frame and starts a fresh segment with the current sample.

`timescale 1ns/1ps

module starlink_pss_overlap_scheduler #(
  parameter integer FFT_SAMPLES = 512,
  parameter integer OVERLAP_SAMPLES = 65,
  parameter integer RING_SAMPLES = 2048,
  parameter integer BLOCK_QUEUE_DEPTH = 4
) (
  input  wire         clk,
  input  wire         resetn,
  input  wire         enable,

  input  wire         sample_valid,
  input  wire         sample_gap,
  input  wire signed [15:0] sample_i,
  input  wire signed [15:0] sample_q,
  input  wire [63:0]  sample_index,

  output reg          fft_valid,
  input  wire         fft_ready,
  output reg signed [15:0] fft_i,
  output reg signed [15:0] fft_q,
  output reg  [8:0]   fft_position,
  output reg          fft_last,
  output reg  [63:0]  fft_block_start_index,

  output reg          flush_pulse,
  output reg          gap_pulse,
  output reg          index_error_pulse,
  output reg          overflow_pulse,
  output reg          block_queued_pulse,
  output reg          block_complete_pulse,
  output wire         busy,
  output wire [63:0]  segment_sample_count,
  output wire [$clog2(BLOCK_QUEUE_DEPTH + 1)-1:0] queued_block_count
);

  localparam integer STRIDE_SAMPLES = FFT_SAMPLES - OVERLAP_SAMPLES;
  localparam integer RING_ADDRESS_WIDTH = $clog2(RING_SAMPLES);
  localparam integer POSITION_WIDTH = $clog2(FFT_SAMPLES + 1);
  localparam integer QUEUE_COUNT_WIDTH = $clog2(BLOCK_QUEUE_DEPTH + 1);

  (* ram_style = "block" *) reg signed [15:0] sample_i_memory [0:RING_SAMPLES-1];
  (* ram_style = "block" *) reg signed [15:0] sample_q_memory [0:RING_SAMPLES-1];

  reg [RING_ADDRESS_WIDTH-1:0] write_pointer;
  reg [63:0] segment_samples;
  reg [63:0] expected_sample_index;
  reg        history_valid;
  reg [POSITION_WIDTH-1:0] samples_to_next_block;

  reg [RING_ADDRESS_WIDTH-1:0] next_block_start_pointer;
  reg [63:0] next_block_start_index;

  reg [RING_ADDRESS_WIDTH-1:0] queue_start_pointer [0:BLOCK_QUEUE_DEPTH-1];
  reg [63:0] queue_start_index [0:BLOCK_QUEUE_DEPTH-1];
  reg [QUEUE_COUNT_WIDTH-1:0] queue_count;

  reg active_block;
  reg [RING_ADDRESS_WIDTH-1:0] active_start_pointer;
  reg [63:0] active_start_index;
  reg [POSITION_WIDTH-1:0] read_issue_position;

  integer queue_slot;

  wire pop_descriptor;
  wire block_ready_on_sample;
  wire [QUEUE_COUNT_WIDTH-1:0] queue_count_after_pop;
  wire required_block_present;
  wire [RING_ADDRESS_WIDTH-1:0] earliest_required_pointer;
  wire retention_overflow;
  wire queue_overflow;
  wire index_error;
  wire restart_segment;
  wire issue_read;
  wire memory_write_enable;
  wire [RING_ADDRESS_WIDTH-1:0] memory_write_address;
  wire memory_read_enable;
  wire [RING_ADDRESS_WIDTH-1:0] read_address;

  assign pop_descriptor = !active_block && !fft_valid && (queue_count != 0);
  assign queue_count_after_pop = queue_count - (pop_descriptor ? 1'b1 : 1'b0);
  assign block_ready_on_sample = sample_valid && history_valid &&
    !sample_gap && !index_error && (samples_to_next_block == 1);
  assign required_block_present = active_block || (queue_count != 0);
  assign earliest_required_pointer = active_block ? active_start_pointer :
    queue_start_pointer[0];
  assign retention_overflow = sample_valid && history_valid &&
    required_block_present && (write_pointer == earliest_required_pointer);
  assign queue_overflow = block_ready_on_sample &&
    (queue_count_after_pop >= BLOCK_QUEUE_DEPTH);
  assign index_error = sample_valid && history_valid &&
    (sample_index != expected_sample_index);
  assign restart_segment = sample_valid &&
    (!history_valid || sample_gap || index_error || retention_overflow ||
      queue_overflow);
  assign issue_read = active_block &&
    (read_issue_position < FFT_SAMPLES) && (!fft_valid || fft_ready);
  assign memory_write_enable = resetn && enable && sample_valid;
  assign memory_write_address = restart_segment ?
    {RING_ADDRESS_WIDTH{1'b0}} : write_pointer;
  assign memory_read_enable = enable && !restart_segment && issue_read;
  assign read_address = active_start_pointer + read_issue_position;

  assign busy = active_block || fft_valid || (queue_count != 0);
  assign segment_sample_count = segment_samples;
  assign queued_block_count = queue_count;

  initial begin
    if (FFT_SAMPLES < 2) begin
      $fatal(1, "FFT_SAMPLES must be at least two");
    end
    if (OVERLAP_SAMPLES < 1 || OVERLAP_SAMPLES >= FFT_SAMPLES) begin
      $fatal(1, "OVERLAP_SAMPLES must lie in [1, FFT_SAMPLES)");
    end
    if (RING_SAMPLES < FFT_SAMPLES ||
        (RING_SAMPLES & (RING_SAMPLES - 1)) != 0) begin
      $fatal(1,
             "RING_SAMPLES must be a power of two containing one FFT frame");
    end
    if (BLOCK_QUEUE_DEPTH < 1) begin
      $fatal(1, "BLOCK_QUEUE_DEPTH must be positive");
    end
    if (FFT_SAMPLES > 512) begin
      $fatal(1,
             "the nine-bit fft_position port supports at most 512 samples");
    end
  end

  // Keep the CI16 ring's two simple-dual-port memories in an inference-safe
  // form: one write site and one registered read site for each component.
  always @(posedge clk) begin
    if (memory_write_enable) begin
      sample_i_memory[memory_write_address] <= sample_i;
      sample_q_memory[memory_write_address] <= sample_q;
    end
    if (memory_read_enable) begin
      fft_i <= sample_i_memory[read_address];
      fft_q <= sample_q_memory[read_address];
    end
  end

  always @(posedge clk) begin
    if (!resetn) begin
      write_pointer <= 0;
      segment_samples <= 0;
      expected_sample_index <= 0;
      history_valid <= 1'b0;
      samples_to_next_block <= FFT_SAMPLES;
      next_block_start_pointer <= 0;
      next_block_start_index <= 0;
      queue_count <= 0;
      active_block <= 1'b0;
      active_start_pointer <= 0;
      active_start_index <= 0;
      read_issue_position <= 0;
      fft_valid <= 1'b0;
      fft_position <= 0;
      fft_last <= 1'b0;
      fft_block_start_index <= 0;
      flush_pulse <= 1'b0;
      gap_pulse <= 1'b0;
      index_error_pulse <= 1'b0;
      overflow_pulse <= 1'b0;
      block_queued_pulse <= 1'b0;
      block_complete_pulse <= 1'b0;
    end else begin
      flush_pulse <= 1'b0;
      gap_pulse <= 1'b0;
      index_error_pulse <= 1'b0;
      overflow_pulse <= 1'b0;
      block_queued_pulse <= 1'b0;
      block_complete_pulse <= 1'b0;

      if (!enable) begin
        if (history_valid || active_block || fft_valid || (queue_count != 0)) begin
          flush_pulse <= 1'b1;
        end
        write_pointer <= 0;
        segment_samples <= 0;
        history_valid <= 1'b0;
        samples_to_next_block <= FFT_SAMPLES;
        next_block_start_pointer <= 0;
        next_block_start_index <= 0;
        queue_count <= 0;
        active_block <= 1'b0;
        read_issue_position <= 0;
        fft_valid <= 1'b0;
        fft_last <= 1'b0;
      end else if (restart_segment) begin
        if (history_valid || active_block || fft_valid || (queue_count != 0)) begin
          flush_pulse <= 1'b1;
        end
        if (sample_gap) begin
          gap_pulse <= 1'b1;
        end
        if (index_error && !sample_gap) begin
          index_error_pulse <= 1'b1;
        end
        if (retention_overflow || queue_overflow) begin
          overflow_pulse <= 1'b1;
        end

        write_pointer <= 1;
        segment_samples <= 1;
        expected_sample_index <= sample_index + 1'b1;
        history_valid <= 1'b1;
        samples_to_next_block <= FFT_SAMPLES - 1;
        next_block_start_pointer <= 0;
        next_block_start_index <= sample_index;
        queue_count <= 0;
        active_block <= 1'b0;
        read_issue_position <= 0;
        fft_valid <= 1'b0;
        fft_last <= 1'b0;
      end else begin
        if (fft_valid && fft_ready) begin
          fft_valid <= 1'b0;
          if (fft_last) begin
            active_block <= 1'b0;
            fft_last <= 1'b0;
            block_complete_pulse <= 1'b1;
          end
        end

        if (issue_read) begin
          fft_position <= read_issue_position;
          fft_last <= (read_issue_position == FFT_SAMPLES - 1);
          fft_block_start_index <= active_start_index;
          fft_valid <= 1'b1;
          read_issue_position <= read_issue_position + 1'b1;
        end

        if (pop_descriptor) begin
          active_block <= 1'b1;
          active_start_pointer <= queue_start_pointer[0];
          active_start_index <= queue_start_index[0];
          read_issue_position <= 0;
          for (queue_slot = 0;
               queue_slot < BLOCK_QUEUE_DEPTH - 1;
               queue_slot = queue_slot + 1) begin
            queue_start_pointer[queue_slot] <= queue_start_pointer[queue_slot + 1];
            queue_start_index[queue_slot] <= queue_start_index[queue_slot + 1];
          end
        end

        if (sample_valid) begin
          write_pointer <= write_pointer + 1'b1;
          segment_samples <= segment_samples + 1'b1;
          expected_sample_index <= sample_index + 1'b1;

          if (block_ready_on_sample) begin
            queue_start_pointer[queue_count_after_pop] <= next_block_start_pointer;
            queue_start_index[queue_count_after_pop] <= next_block_start_index;
            next_block_start_pointer <= next_block_start_pointer + STRIDE_SAMPLES;
            next_block_start_index <= next_block_start_index + STRIDE_SAMPLES;
            samples_to_next_block <= STRIDE_SAMPLES;
            block_queued_pulse <= 1'b1;
          end else begin
            samples_to_next_block <= samples_to_next_block - 1'b1;
          end
        end

        case ({block_ready_on_sample, pop_descriptor})
          2'b10: queue_count <= queue_count + 1'b1;
          2'b01: queue_count <= queue_count - 1'b1;
          default: queue_count <= queue_count;
        endcase
      end
    end
  end

endmodule
