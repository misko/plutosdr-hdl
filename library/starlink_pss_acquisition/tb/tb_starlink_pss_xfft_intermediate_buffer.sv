`timescale 1ns/1ps

module tb_starlink_pss_xfft_intermediate_buffer;

  reg clk = 1'b0;
  reg resetn = 1'b0;
  reg flush = 1'b0;
  reg release_buffer = 1'b0;
  reg input_valid = 1'b0;
  wire input_ready;
  reg signed [17:0] input_i = 18'sd0;
  reg signed [17:0] input_q = 18'sd0;
  reg [8:0] input_position = 9'd0;
  reg [4:0] input_block_exponent = 5'd0;
  reg [63:0] input_block_start_index = 64'd0;
  reg input_last = 1'b0;
  reg read_enable = 1'b0;
  wire output_valid;
  reg output_ready = 1'b0;
  wire signed [17:0] output_i;
  wire signed [17:0] output_q;
  wire [8:0] output_position;
  wire [4:0] output_block_exponent;
  wire [63:0] output_block_start_index;
  wire output_last;
  wire write_complete_pulse;
  wire read_complete_pulse;
  wire protocol_error_pulse;
  wire protocol_fault;
  wire [9:0] stored_count;

  integer sent = 0;
  integer received = 0;
  integer write_pulses = 0;
  integer read_pulses = 0;
  integer stall_cycles = 0;
  integer read_cycles = 0;

  always #5 clk = ~clk;

  starlink_pss_xfft_intermediate_buffer dut (
    .clk(clk),
    .resetn(resetn),
    .flush(flush),
    .release_buffer(release_buffer),
    .input_valid(input_valid),
    .input_ready(input_ready),
    .input_i(input_i),
    .input_q(input_q),
    .input_position(input_position),
    .input_block_exponent(input_block_exponent),
    .input_block_start_index(input_block_start_index),
    .input_last(input_last),
    .read_enable(read_enable),
    .output_valid(output_valid),
    .output_ready(output_ready),
    .output_i(output_i),
    .output_q(output_q),
    .output_position(output_position),
    .output_block_exponent(output_block_exponent),
    .output_block_start_index(output_block_start_index),
    .output_last(output_last),
    .write_complete_pulse(write_complete_pulse),
    .read_complete_pulse(read_complete_pulse),
    .protocol_error_pulse(protocol_error_pulse),
    .protocol_fault(protocol_fault),
    .stored_count(stored_count)
  );

  task automatic fail(input string message);
    begin
      $display("XFFT_INTERMEDIATE_BUFFER_FAIL %s", message);
      $finish;
    end
  endtask

  always @(posedge clk) begin
    if (write_complete_pulse)
      write_pulses <= write_pulses + 1;
    if (read_complete_pulse)
      read_pulses <= read_pulses + 1;

    if (output_valid && !read_enable)
      fail("output escaped while reading disabled");

    if (output_valid && !output_ready)
      stall_cycles <= stall_cycles + 1;

    if (output_valid && output_ready) begin
      if (output_position !== received[8:0])
        fail("output position mismatch");
      if ($signed(output_i) !== $signed(received - 256))
        fail("output I mismatch");
      if ($signed(output_q) !== $signed(511 - received))
        fail("output Q mismatch");
      if (output_block_exponent !== 5'd7)
        fail("output exponent mismatch");
      if (output_block_start_index !== 64'd123456)
        fail("output block identity mismatch");
      if (output_last !== (received == 511))
        fail("output TLAST mismatch");
      received <= received + 1;
    end
  end

  initial begin
    repeat (4) @(posedge clk);
    resetn <= 1'b1;
    repeat (2) @(posedge clk);

    for (sent = 0; sent < 512; sent = sent + 1) begin
      input_i <= sent - 256;
      input_q <= 511 - sent;
      input_position <= sent[8:0];
      input_block_exponent <= 5'd7;
      input_block_start_index <= 64'd123456;
      input_last <= (sent == 511);
      input_valid <= 1'b1;
      do @(posedge clk); while (!input_ready);
      input_valid <= 1'b0;
      if ((sent % 13) == 0)
        @(posedge clk);
    end

    @(posedge clk);
    #1;
    if (stored_count !== 10'd512 || write_pulses !== 1)
      fail("complete block was not committed exactly once");
    if (output_valid)
      fail("buffer published before read enable");

    read_enable <= 1'b1;
    output_ready <= 1'b1;
    while (received < 512) begin
      @(posedge clk);
      read_cycles = read_cycles + 1;
      if ((read_cycles % 17) == 8)
        output_ready <= 1'b0;
      else
        output_ready <= 1'b1;
    end
    output_ready <= 1'b0;
    repeat (2) @(posedge clk);
    if (read_pulses !== 1)
      fail("read completion did not pulse exactly once");
    if (stall_cycles == 0)
      fail("output backpressure was not exercised");

    release_buffer <= 1'b1;
    @(posedge clk);
    release_buffer <= 1'b0;
    read_enable <= 1'b0;
    @(posedge clk);
    if (stored_count !== 10'd0 || !input_ready || protocol_fault)
      fail("release did not return the buffer to empty");

    input_valid <= 1'b1;
    input_position <= 9'd0;
    input_last <= 1'b1;
    @(posedge clk);
    input_valid <= 1'b0;
    @(posedge clk);
    if (!protocol_fault || !protocol_error_pulse)
      fail("malformed first beat did not fail closed");

    flush <= 1'b1;
    @(posedge clk);
    flush <= 1'b0;
    @(posedge clk);
    if (protocol_fault || stored_count !== 10'd0)
      fail("flush did not clear quarantine");

    $display("XFFT_INTERMEDIATE_BUFFER_PASS words=%0d stalls=%0d atomic_commit=1 malformed=1 release=1",
             received, stall_cycles);
    $finish;
  end

  initial begin
    #500000;
    fail("timeout");
  end

endmodule
