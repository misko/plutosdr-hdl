`timescale 1ns/1ps

// Reuse the reachable fill/drain/stall/fault/flush workload, comparing every
// public output (including invalid payloads) to the pinned pre-storage-change
// RTL each clock. No force, private-state assignment or assumed BRAM latency.
module tb_starlink_pss_transform_fifo_storage #(
  parameter integer FIFO_DEPTH = 4
);
  localparam integer COUNT_BITS = $clog2(FIFO_DEPTH + 1);
  localparam integer OBS_BITS = 118 + 2 * COUNT_BITS;
  tb_starlink_pss_transform_fifo #(
    .FIFO_DEPTH(FIFO_DEPTH), .RESET_CYCLES(20)
  ) workload ();

  wire input_ready, output_valid, output_last, protocol_fault;
  wire signed [17:0] output_i, output_q;
  wire [8:0] output_position;
  wire [4:0] output_block_exponent;
  wire [63:0] output_block_start_index;
  wire [COUNT_BITS-1:0] stored_count, maximum_stored_count;
  integer checked_cycles = 0;
  wire [OBS_BITS-1:0] actual = {
    workload.input_ready, workload.output_valid, workload.output_i,
    workload.output_q, workload.output_position, workload.output_block_exponent,
    workload.output_block_start_index, workload.output_last,
    workload.stored_count, workload.maximum_stored_count, workload.protocol_fault
  };
  wire [OBS_BITS-1:0] expected = {
    input_ready, output_valid, output_i, output_q, output_position,
    output_block_exponent, output_block_start_index, output_last,
    stored_count, maximum_stored_count, protocol_fault
  };
  starlink_pss_transform_fifo_golden #(.FIFO_DEPTH(FIFO_DEPTH)) golden (
    .clk(workload.clk), .resetn(workload.resetn), .flush(workload.flush),
    .input_valid(workload.input_valid), .input_ready(input_ready),
    .input_i(workload.input_i), .input_q(workload.input_q),
    .input_position(workload.input_position),
    .input_block_exponent(workload.input_block_exponent),
    .input_block_start_index(workload.input_block_start_index),
    .input_last(workload.input_last),
    .output_valid(output_valid), .output_ready(workload.output_ready),
    .output_i(output_i), .output_q(output_q), .output_position(output_position),
    .output_block_exponent(output_block_exponent),
    .output_block_start_index(output_block_start_index), .output_last(output_last),
    .stored_count(stored_count), .maximum_stored_count(maximum_stored_count),
    .protocol_fault(protocol_fault)
  );
  always @(posedge workload.clk) begin
    #1;
    // After >100 ns of reset, also valid for the synthesized BRAM/GSR model.
    if (workload.cycle_count >= 15) begin
      if (actual !== expected)
        $fatal(1, "FIFO_STORAGE_EQUIVALENCE_FAIL cycle=%0d actual=%h expected=%h",
               workload.cycle_count, actual, expected);
      checked_cycles = checked_cycles + 1;
      if (checked_cycles == 512)
        $display("FIFO_STORAGE_EQUIVALENCE_WITNESS checked_cycles=512");
    end
  end
endmodule
