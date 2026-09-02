`timescale 1ns/1ps

module tb_starlink_pss_ifft_qualifier;

  reg clk = 1'b0;
  reg resetn = 1'b0;
  reg flush = 1'b0;
  reg input_valid = 1'b0;
  reg signed [23:0] input_correlation_i = 0;
  reg signed [23:0] input_correlation_q = 0;
  reg [8:0] input_ifft_index = 0;
  reg [4:0] input_forward_exponent = 0;
  reg [4:0] input_inverse_exponent = 0;
  reg [63:0] input_block_start_index = 0;
  reg input_last = 1'b0;
  reg output_ready = 1'b0;

  wire input_ready;
  wire output_valid;
  wire signed [23:0] output_correlation_i;
  wire signed [23:0] output_correlation_q;
  wire [4:0] output_forward_exponent;
  wire [4:0] output_inverse_exponent;
  wire [63:0] output_start_index;
  wire output_block_last;
  wire accepted_pulse;
  wire discarded_prefix_pulse;
  wire emitted_pulse;
  wire sequence_error_pulse;
  wire metadata_error_pulse;
  wire protocol_fault;

  integer cycle_count = 0;
  integer accepted_count = 0;
  integer discarded_count = 0;
  integer emitted_count = 0;
  integer sequence_errors = 0;
  integer metadata_errors = 0;
  integer timeout = 0;
  integer block_number;
  integer ifft_index;
  integer expected_block;
  integer expected_index;
  reg monitor_stream = 1'b0;
  reg saw_backpressure = 1'b0;
  reg stalled_last_cycle = 1'b0;
  reg [122:0] stalled_payload;

  always #5 clk = ~clk;

  starlink_pss_ifft_qualifier dut (
    .clk                     (clk),
    .resetn                  (resetn),
    .flush                   (flush),
    .input_valid             (input_valid),
    .input_ready             (input_ready),
    .input_correlation_i     (input_correlation_i),
    .input_correlation_q     (input_correlation_q),
    .input_ifft_index        (input_ifft_index),
    .input_forward_exponent  (input_forward_exponent),
    .input_inverse_exponent  (input_inverse_exponent),
    .input_block_start_index (input_block_start_index),
    .input_last              (input_last),
    .output_valid            (output_valid),
    .output_ready            (output_ready),
    .output_correlation_i    (output_correlation_i),
    .output_correlation_q    (output_correlation_q),
    .output_forward_exponent (output_forward_exponent),
    .output_inverse_exponent (output_inverse_exponent),
    .output_start_index      (output_start_index),
    .output_block_last       (output_block_last),
    .accepted_pulse          (accepted_pulse),
    .discarded_prefix_pulse  (discarded_prefix_pulse),
    .emitted_pulse           (emitted_pulse),
    .sequence_error_pulse    (sequence_error_pulse),
    .metadata_error_pulse    (metadata_error_pulse),
    .protocol_fault          (protocol_fault)
  );

  task automatic fail(input string message);
    begin
      $display("IFFT_QUALIFIER_FAIL %0s cycle=%0d accepted=%0d discarded=%0d emitted=%0d",
               message, cycle_count, accepted_count, discarded_count,
               emitted_count);
      $fatal(1);
    end
  endtask

  task automatic send_item(
    input [8:0] item_index,
    input [63:0] item_block_start,
    input [4:0] item_forward_exponent,
    input [4:0] item_inverse_exponent,
    input item_last
  );
    begin
      @(negedge clk);
      input_ifft_index = item_index;
      input_block_start_index = item_block_start;
      input_forward_exponent = item_forward_exponent;
      input_inverse_exponent = item_inverse_exponent;
      input_correlation_i = $signed(item_index * 97 +
                                     item_block_start[15:0]);
      input_correlation_q = -$signed(item_index * 53 +
                                      item_block_start[15:0]);
      input_last = item_last;
      input_valid = 1'b1;
      begin : wait_for_accept
        forever begin
          @(posedge clk);
          if (input_ready)
            disable wait_for_accept;
        end
      end
      @(negedge clk);
      input_valid = 1'b0;
    end
  endtask

  task automatic pulse_flush;
    begin
      @(negedge clk);
      input_valid = 1'b0;
      flush = 1'b1;
      @(negedge clk);
      flush = 1'b0;
      #1;
    end
  endtask

  always @(posedge clk) begin
    cycle_count <= cycle_count + 1;
    if (cycle_count > 10000)
      fail("simulation watchdog expired");
    if (resetn && accepted_pulse)
      accepted_count <= accepted_count + 1;
    if (resetn && discarded_prefix_pulse)
      discarded_count <= discarded_count + 1;
    if (resetn && output_valid && output_ready)
      emitted_count <= emitted_count + 1;
    if (resetn && sequence_error_pulse)
      sequence_errors <= sequence_errors + 1;
    if (resetn && metadata_error_pulse)
      metadata_errors <= metadata_errors + 1;
    if (resetn && monitor_stream && input_valid && !input_ready)
      saw_backpressure <= 1'b1;

    if (resetn && monitor_stream && stalled_last_cycle) begin
      if (!output_valid ||
          {output_block_last, output_start_index,
           output_inverse_exponent, output_forward_exponent,
           output_correlation_q, output_correlation_i} !== stalled_payload)
        fail("output payload changed while stalled");
    end
    stalled_last_cycle <= resetn && monitor_stream &&
                          output_valid && !output_ready;
    if (output_valid && !output_ready)
      stalled_payload <= {
        output_block_last, output_start_index,
        output_inverse_exponent, output_forward_exponent,
        output_correlation_q, output_correlation_i
      };

    if (resetn && monitor_stream && output_valid && output_ready) begin
      expected_block = emitted_count / 447;
      expected_index = 65 + (emitted_count % 447);
      if (output_start_index !== 64'd1000 + expected_block * 447 +
                                  expected_index - 65)
        fail("absolute candidate-start mapping mismatch");
      if (output_correlation_i !==
          $signed(expected_index * 97 + 1000 + expected_block * 447) ||
          output_correlation_q !==
          -$signed(expected_index * 53 + 1000 + expected_block * 447))
        fail("correlation payload mismatch");
      if (output_forward_exponent !== 5'd3 + expected_block ||
          output_inverse_exponent !== 5'd7 + expected_block)
        fail("block exponent payload mismatch");
      if (output_block_last !== (expected_index == 511))
        fail("qualified block-last mismatch");
    end
  end

  initial begin
    $dumpfile("build/tb_starlink_pss_ifft_qualifier.vcd");
    $dumpvars(0, tb_starlink_pss_ifft_qualifier);

    repeat (3) @(negedge clk);
    resetn = 1'b1;
    monitor_stream = 1'b1;

    // Two exact contiguous overlap-save blocks, with downstream stalls.
    fork
      begin
        for (block_number = 0; block_number < 2;
             block_number = block_number + 1) begin
          for (ifft_index = 0; ifft_index < 512;
               ifft_index = ifft_index + 1) begin
            send_item(ifft_index[8:0], 64'd1000 + block_number * 447,
                      5'd3 + block_number, 5'd7 + block_number,
                      ifft_index == 511);
          end
        end
      end
      begin
        output_ready = 1'b1;
        while (emitted_count < 894) begin
          @(negedge clk);
          output_ready = (cycle_count % 13) < 8;
        end
        output_ready = 1'b1;
      end
    join

    timeout = 0;
    while (emitted_count < 894 && timeout < 1000) begin
      @(negedge clk);
      timeout = timeout + 1;
    end
    repeat (3) @(negedge clk);
    if (accepted_count != 1024 || discarded_count != 130 ||
        emitted_count != 894)
      fail("two-block accounting mismatch");
    if (!saw_backpressure)
      fail("test did not exercise output backpressure");
    if (protocol_fault || sequence_errors != 0 || metadata_errors != 0)
      fail("well-formed blocks raised a protocol fault");

    // A non-447 next block start must fault before it can emit anything.
    monitor_stream = 1'b0;
    send_item(9'd0, 64'd2000, 5'd1, 5'd2, 1'b0);
    repeat (2) @(negedge clk);
    if (!protocol_fault || metadata_errors != 1 || output_valid || input_ready)
      fail("block-stride metadata error did not latch and quarantine");

    // Flush is the sole recovery path. Then test an index discontinuity.
    pulse_flush();
    if (protocol_fault || !input_ready)
      fail("flush did not recover protocol state");
    send_item(9'd0, 64'd5000, 5'd4, 5'd6, 1'b0);
    send_item(9'd2, 64'd5000, 5'd4, 5'd6, 1'b0);
    repeat (2) @(negedge clk);
    if (!protocol_fault || sequence_errors != 1 || output_valid)
      fail("index discontinuity did not latch and quarantine");

    // Metadata must remain stable within a block.
    pulse_flush();
    send_item(9'd0, 64'd7000, 5'd8, 5'd9, 1'b0);
    send_item(9'd1, 64'd7000, 5'd10, 5'd9, 1'b0);
    repeat (2) @(negedge clk);
    if (!protocol_fault || metadata_errors != 2 || output_valid)
      fail("intra-block metadata change did not latch and quarantine");

    // TLAST is required only with index 511.
    pulse_flush();
    send_item(9'd0, 64'd9000, 5'd1, 5'd1, 1'b1);
    repeat (2) @(negedge clk);
    if (!protocol_fault || sequence_errors != 2 || output_valid)
      fail("early TLAST did not latch and quarantine");

    pulse_flush();
    if (protocol_fault || output_valid || !input_ready)
      fail("final flush did not return to idle");

    $display("IFFT_QUALIFIER_PASS blocks=2 accepted=1024 prefix_discarded=130 valid=894 mapping=1 stalls=1 sequence_faults=2 metadata_faults=2 flush=1");
    $finish;
  end

endmodule
