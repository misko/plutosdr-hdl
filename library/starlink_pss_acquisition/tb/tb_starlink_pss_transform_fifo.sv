`timescale 1ns/1ps

module tb_starlink_pss_transform_fifo;

  localparam integer FIFO_DEPTH = 4;
  localparam integer TEST_WORDS = 512;

  reg clk = 1'b0;
  reg resetn = 1'b0;
  reg flush = 1'b0;
  reg input_valid = 1'b0;
  reg signed [17:0] input_i = 0;
  reg signed [17:0] input_q = 0;
  reg [8:0] input_position = 0;
  reg [4:0] input_block_exponent = 0;
  reg [63:0] input_block_start_index = 0;
  reg input_last = 1'b0;
  reg output_ready = 1'b0;

  wire input_ready;
  wire output_valid;
  wire signed [17:0] output_i;
  wire signed [17:0] output_q;
  wire [8:0] output_position;
  wire [4:0] output_block_exponent;
  wire [63:0] output_block_start_index;
  wire output_last;
  wire [2:0] stored_count;
  wire [2:0] maximum_stored_count;
  wire protocol_fault;

  integer accepted_count = 0;
  integer emitted_count = 0;
  integer cycle_count = 0;
  integer timeout = 0;
  integer ordinal = 0;
  reg scoreboard_enabled = 1'b0;
  reg stalled_last_cycle = 1'b0;
  reg [114:0] stalled_payload = 0;

  always #5 clk = ~clk;

  starlink_pss_transform_fifo #(
    .DATA_WIDTH(18),
    .FIFO_DEPTH(FIFO_DEPTH)
  ) dut (
    .clk(clk),
    .resetn(resetn),
    .flush(flush),
    .input_valid(input_valid),
    .input_ready(input_ready),
    .input_i(input_i),
    .input_q(input_q),
    .input_position(input_position),
    .input_block_exponent(input_block_exponent),
    .input_block_start_index(input_block_start_index),
    .input_last(input_last),
    .output_valid(output_valid),
    .output_ready(output_ready),
    .output_i(output_i),
    .output_q(output_q),
    .output_position(output_position),
    .output_block_exponent(output_block_exponent),
    .output_block_start_index(output_block_start_index),
    .output_last(output_last),
    .stored_count(stored_count),
    .maximum_stored_count(maximum_stored_count),
    .protocol_fault(protocol_fault)
  );

  task automatic fail(input string message);
    begin
      $display("TRANSFORM_FIFO_FAIL %0s accepted=%0d emitted=%0d stored=%0d cycle=%0d",
               message, accepted_count, emitted_count, stored_count,
               cycle_count);
      $fatal(1);
    end
  endtask

  task automatic drive_word(
    input integer position_value,
    input [63:0] block_start_value,
    input last_value
  );
    begin
      input_i = position_value - 256;
      input_q = 511 - position_value;
      input_position = position_value[8:0];
      input_block_exponent = 5'd9;
      input_block_start_index = block_start_value;
      input_last = last_value;
    end
  endtask

  task automatic pulse_flush;
    begin
      @(negedge clk);
      input_valid = 1'b0;
      output_ready = 1'b0;
      flush = 1'b1;
      @(negedge clk);
      flush = 1'b0;
      accepted_count = 0;
      emitted_count = 0;
      stalled_last_cycle = 1'b0;
    end
  endtask

  always @(posedge clk) begin
    cycle_count <= cycle_count + 1;

    if (resetn && scoreboard_enabled && stalled_last_cycle) begin
      if (!output_valid ||
          {output_last, output_block_start_index, output_block_exponent,
           output_position, output_q, output_i} !== stalled_payload)
        fail("output payload changed while stalled");
    end
    stalled_last_cycle <= resetn && scoreboard_enabled &&
                          output_valid && !output_ready;
    if (output_valid && !output_ready)
      stalled_payload <= {
        output_last, output_block_start_index, output_block_exponent,
        output_position, output_q, output_i
      };

    if (resetn && scoreboard_enabled && input_valid && input_ready)
      accepted_count <= accepted_count + 1;

    if (resetn && scoreboard_enabled && output_valid && output_ready) begin
      if (output_position !== emitted_count[8:0] ||
          $signed(output_i) !== $signed(emitted_count - 256) ||
          $signed(output_q) !== $signed(511 - emitted_count) ||
          output_block_exponent !== 5'd9 ||
          output_block_start_index !== 64'd123456 ||
          output_last !== (emitted_count == TEST_WORDS - 1))
        fail("FIFO ordering or payload mismatch");
      emitted_count <= emitted_count + 1;
    end
  end

  initial begin
    $dumpfile("build/tb_starlink_pss_transform_fifo.vcd");
    $dumpvars(0, tb_starlink_pss_transform_fifo);

    repeat (3) @(negedge clk);
    resetn = 1'b1;
    scoreboard_enabled = 1'b1;
    #1;

    // Fill all four registered storage positions while the output is stalled.
    output_ready = 1'b0;
    for (ordinal = 0; ordinal < FIFO_DEPTH; ordinal = ordinal + 1) begin
      if (!input_ready)
        fail("FIFO refused a word below declared capacity");
      drive_word(ordinal, 64'd123456, 1'b0);
      input_valid = 1'b1;
      @(negedge clk);
    end
    input_valid = 1'b0;
    repeat (2) @(negedge clk);
    if (stored_count !== FIFO_DEPTH || input_ready ||
        maximum_stored_count !== FIFO_DEPTH)
      fail("full-capacity ready/count mismatch");

    // Continue the same 512-word block with deterministic downstream stalls.
    output_ready = 1'b1;
    ordinal = FIFO_DEPTH;
    timeout = 0;
    while ((accepted_count < TEST_WORDS || emitted_count < TEST_WORDS) &&
           timeout < 4000) begin
      @(negedge clk);
      output_ready = (cycle_count % 11) < 8;
      if (ordinal < TEST_WORDS) begin
        drive_word(ordinal, 64'd123456, ordinal == TEST_WORDS - 1);
        input_valid = 1'b1;
        if (input_ready)
          ordinal = ordinal + 1;
      end else begin
        input_valid = 1'b0;
      end
      timeout = timeout + 1;
    end
    input_valid = 1'b0;
    output_ready = 1'b1;
    repeat (3) @(negedge clk);
    if (accepted_count != TEST_WORDS || emitted_count != TEST_WORDS ||
        stored_count != 0 || protocol_fault)
      fail("valid block did not drain exactly");

    // A position/TLAST violation must quarantine all output until flush.
    pulse_flush();
    drive_word(0, 64'd700, 1'b1);
    input_valid = 1'b1;
    @(negedge clk);
    input_valid = 1'b0;
    @(negedge clk);
    if (!protocol_fault || input_ready || output_valid)
      fail("malformed TLAST did not fail closed");

    // A changing 64-bit block identity must be caught at this boundary.
    pulse_flush();
    drive_word(0, 64'h0123_4567_89ab_cdef, 1'b0);
    input_valid = 1'b1;
    @(negedge clk);
    drive_word(1, 64'h8123_4567_89ab_cdef, 1'b0);
    @(negedge clk);
    input_valid = 1'b0;
    @(negedge clk);
    if (!protocol_fault || input_ready || output_valid)
      fail("block identity change did not fail closed");

    pulse_flush();
    @(negedge clk);
    if (protocol_fault || stored_count != 0 || !input_ready)
      fail("flush did not clear quarantine and occupancy");

    $display("TRANSFORM_FIFO_PASS words=%0d depth=%0d stalls=1 malformed=1 identity=1 flush=1",
             TEST_WORDS, FIFO_DEPTH);
    $finish;
  end

  initial begin
    #100000;
    fail("timeout");
  end

endmodule
