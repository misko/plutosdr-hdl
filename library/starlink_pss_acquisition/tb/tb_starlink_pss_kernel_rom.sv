`timescale 1ns/1ps

module tb_starlink_pss_kernel_rom;

  reg clk = 1'b0;
  reg resetn = 1'b0;
  reg flush = 1'b0;
  reg input_valid = 1'b0;
  reg [8:0] input_bin_index = 0;
  reg [4:0] input_block_exponent = 0;
  reg input_last = 1'b0;
  reg [63:0] input_block_start_index = 0;
  reg output_ready = 1'b1;
  reg suppress_expected_input = 1'b0;
  reg automatic_stalls = 1'b0;

  wire input_ready;
  wire output_valid;
  wire signed [23:0] output_kernel_i;
  wire signed [23:0] output_kernel_q;
  wire [8:0] output_bin_index;
  wire [4:0] output_block_exponent;
  wire output_last;
  wire [63:0] output_block_start_index;
  wire accepted_pulse;
  wire emitted_pulse;
  wire input_block_complete_pulse;
  wire sequence_error_pulse;
  wire metadata_error_pulse;
  wire protocol_fault;

  reg [47:0] reference_memory [0:511];
  reg [47:0] expected_kernel [0:4095];
  reg [8:0] expected_bin [0:4095];
  reg [4:0] expected_exponent [0:4095];
  reg expected_last [0:4095];
  reg [63:0] expected_block_start [0:4095];

  integer cycle_count = 0;
  integer write_count = 0;
  integer read_count = 0;
  integer verified_count = 0;
  integer block_complete_count = 0;
  integer position;
  integer accept_run = 0;
  integer longest_accept_run = 0;
  reg stalled_last_cycle = 1'b0;
  reg [126:0] stalled_payload = 0;

  always #5 clk = ~clk;

  starlink_pss_kernel_rom #(
    .ROM_FILE ("tb/upper_edge_pss_kernel_q23.mem")
  ) dut (
    .clk                      (clk),
    .resetn                   (resetn),
    .flush                    (flush),
    .input_valid              (input_valid),
    .input_ready              (input_ready),
    .input_bin_index          (input_bin_index),
    .input_block_exponent     (input_block_exponent),
    .input_last               (input_last),
    .input_block_start_index  (input_block_start_index),
    .output_valid             (output_valid),
    .output_ready             (output_ready),
    .output_kernel_i          (output_kernel_i),
    .output_kernel_q          (output_kernel_q),
    .output_bin_index         (output_bin_index),
    .output_block_exponent    (output_block_exponent),
    .output_last              (output_last),
    .output_block_start_index (output_block_start_index),
    .accepted_pulse           (accepted_pulse),
    .emitted_pulse            (emitted_pulse),
    .input_block_complete_pulse(input_block_complete_pulse),
    .sequence_error_pulse     (sequence_error_pulse),
    .metadata_error_pulse     (metadata_error_pulse),
    .protocol_fault           (protocol_fault)
  );

  task automatic fail(input string message);
    begin
      $display("KERNEL_ROM_FAIL %0s cycle=%0d queued=%0d verified=%0d",
               message, cycle_count, write_count - read_count, verified_count);
      $fatal(1);
    end
  endtask

  task automatic apply_flush;
    begin
      @(negedge clk);
      input_valid = 1'b0;
      suppress_expected_input = 1'b0;
      automatic_stalls = 1'b0;
      output_ready = 1'b1;
      flush = 1'b1;
      @(negedge clk);
      flush = 1'b0;
      @(negedge clk);
      if (protocol_fault || !input_ready || output_valid)
        fail("flush did not restore an empty, ready interface");
    end
  endtask

  task automatic send_beat(
    input [8:0] bin_index,
    input [4:0] exponent,
    input [63:0] block_start,
    input last,
    input suppress_expected
  );
    begin
      @(negedge clk);
      input_bin_index = bin_index;
      input_block_exponent = exponent;
      input_block_start_index = block_start;
      input_last = last;
      suppress_expected_input = suppress_expected;
      input_valid = 1'b1;
      begin : wait_for_accept
        forever begin
          @(posedge clk);
          if (input_ready)
            disable wait_for_accept;
        end
      end
    end
  endtask

  task automatic finish_input;
    begin
      @(negedge clk);
      input_valid = 1'b0;
      suppress_expected_input = 1'b0;
    end
  endtask

  task automatic send_block(
    input [63:0] block_start,
    input [4:0] exponent
  );
    begin
      for (position = 0; position < 512; position = position + 1)
        send_beat(position[8:0], exponent, block_start, position == 511, 1'b0);
      finish_input();
    end
  endtask

  task automatic wait_for_drain;
    begin
      begin : draining
        forever begin
          @(negedge clk);
          if (read_count == write_count && !output_valid)
            disable draining;
        end
      end
    end
  endtask

  task automatic expect_fault(
    input expected_sequence_error,
    input expected_metadata_error,
    input string description
  );
    begin
      @(negedge clk);
      input_valid = 1'b0;
      suppress_expected_input = 1'b0;
      if (!protocol_fault)
        fail({description, ": protocol fault did not latch"});
      if (sequence_error_pulse !== expected_sequence_error)
        fail({description, ": sequence pulse mismatch"});
      if (metadata_error_pulse !== expected_metadata_error)
        fail({description, ": metadata pulse mismatch"});
      if (input_ready || output_valid)
        fail({description, ": quarantined interface remained active"});
      repeat (3) @(posedge clk);
      if (!protocol_fault || input_ready || output_valid)
        fail({description, ": quarantine was not sticky"});
    end
  endtask

  always @(negedge clk) begin
    if (automatic_stalls)
      output_ready = (cycle_count % 19) != 7 && (cycle_count % 23) != 11;
  end

  always @(posedge clk) begin
    cycle_count = cycle_count + 1;
    if (cycle_count > 30000)
      fail("simulation watchdog expired");

    if (!resetn || flush) begin
      write_count = 0;
      read_count = 0;
      stalled_last_cycle = 1'b0;
      accept_run = 0;
    end else begin
      if (stalled_last_cycle &&
          {output_kernel_q, output_kernel_i, output_bin_index,
           output_block_exponent, output_last,
           output_block_start_index} !== stalled_payload)
        fail("output payload changed while stalled");
      stalled_last_cycle = output_valid && !output_ready;
      stalled_payload = {output_kernel_q, output_kernel_i, output_bin_index,
                         output_block_exponent, output_last,
                         output_block_start_index};

      if (output_valid && output_ready) begin
        if (read_count == write_count)
          fail("orphan output");
        if ({output_kernel_q, output_kernel_i} !== expected_kernel[read_count])
          fail("coefficient mismatch");
        if (output_bin_index !== expected_bin[read_count] ||
            output_block_exponent !== expected_exponent[read_count] ||
            output_last !== expected_last[read_count] ||
            output_block_start_index !== expected_block_start[read_count])
          fail("output metadata mismatch");
        read_count = read_count + 1;
        verified_count = verified_count + 1;
      end

      if (input_valid && input_ready && !suppress_expected_input) begin
        expected_kernel[write_count] = reference_memory[input_bin_index];
        expected_bin[write_count] = input_bin_index;
        expected_exponent[write_count] = input_block_exponent;
        expected_last[write_count] = input_last;
        expected_block_start[write_count] = input_block_start_index;
        write_count = write_count + 1;
      end

      if (input_valid && input_ready) begin
        accept_run = accept_run + 1;
        if (accept_run > longest_accept_run)
          longest_accept_run = accept_run;
      end else begin
        accept_run = 0;
      end

      if (input_block_complete_pulse)
        block_complete_count = block_complete_count + 1;
    end
  end

  initial begin
    $readmemh("tb/upper_edge_pss_kernel_q23.mem", reference_memory, 0, 511);

    repeat (4) @(posedge clk);
    @(negedge clk);
    resetn = 1'b1;
    repeat (2) @(negedge clk);
    if (!input_ready)
      fail("interface did not become ready after reset");

    // Two complete frames prove exact address mapping, the 447-sample block
    // stride, sustained one-bin-per-clock service, and elastic stalls.
    send_block(64'd100000, 5'd7);
    automatic_stalls = 1'b1;
    send_block(64'd100447, 5'd12);
    finish_input();
    wait_for_drain();
    automatic_stalls = 1'b0;
    output_ready = 1'b1;
    if (verified_count != 1024 || block_complete_count != 2)
      fail("complete-block accounting mismatch");
    if (longest_accept_run < 512)
      fail("one-bin-per-clock throughput was not demonstrated");

    // Wrong index at block start.
    apply_flush();
    send_beat(9'd1, 5'd3, 64'd200000, 1'b0, 1'b1);
    expect_fault(1'b1, 1'b0, "wrong first bin");

    // Early TLAST.
    apply_flush();
    send_beat(9'd0, 5'd3, 64'd200000, 1'b1, 1'b1);
    expect_fault(1'b1, 1'b0, "early TLAST");

    // Exponent must remain fixed throughout a block.
    apply_flush();
    send_beat(9'd0, 5'd3, 64'd200000, 1'b0, 1'b0);
    send_beat(9'd1, 5'd4, 64'd200000, 1'b0, 1'b1);
    expect_fault(1'b0, 1'b1, "changed exponent");

    // Absolute block identity must remain fixed throughout a block.
    apply_flush();
    send_beat(9'd0, 5'd3, 64'd200000, 1'b0, 1'b0);
    send_beat(9'd1, 5'd3, 64'd200001, 1'b0, 1'b1);
    expect_fault(1'b0, 1'b1, "changed block start");

    // The next FFT block must advance by exactly 512 - 65 = 447 samples.
    apply_flush();
    send_block(64'd300000, 5'd5);
    wait_for_drain();
    send_beat(9'd0, 5'd6, 64'd300448, 1'b0, 1'b1);
    expect_fault(1'b0, 1'b1, "wrong next-block stride");

    apply_flush();
    send_beat(9'd0, 5'd9, 64'd400000, 1'b0, 1'b0);
    finish_input();
    wait_for_drain();
    if (protocol_fault)
      fail("valid lookup failed after final recovery");

    $display("KERNEL_ROM_PASS verified=%0d complete_blocks=%0d longest_accept_run=%0d",
             verified_count, block_complete_count, longest_accept_run);
    $finish;
  end

endmodule
