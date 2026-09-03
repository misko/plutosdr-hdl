`timescale 1ns/1ps

module tb_starlink_pss_forward_kernel_join;

  reg clk = 1'b0;
  reg resetn = 1'b0;
  reg flush = 1'b0;
  reg input_valid = 1'b0;
  reg signed [23:0] input_i = 0;
  reg signed [23:0] input_q = 0;
  reg [8:0] input_bin_index = 0;
  reg [4:0] input_block_exponent = 0;
  reg input_last = 1'b0;
  reg [63:0] input_block_start_index = 0;
  reg output_ready = 1'b1;
  reg automatic_stalls = 1'b0;
  reg suppress_expected_input = 1'b0;

  wire input_ready;
  wire output_valid;
  wire signed [23:0] output_i;
  wire signed [23:0] output_q;
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
  reg [47:0] expected_data [0:2047];
  reg [47:0] expected_kernel [0:2047];
  reg [8:0] expected_bin [0:2047];
  reg [4:0] expected_exponent [0:2047];
  reg expected_last [0:2047];
  reg [63:0] expected_start [0:2047];

  integer cycle_count = 0;
  integer write_count = 0;
  integer read_count = 0;
  integer verified_count = 0;
  integer position;
  integer accept_run = 0;
  integer longest_accept_run = 0;
  reg stalled_last_cycle = 1'b0;
  reg [174:0] stalled_payload = 0;

  always #5 clk = ~clk;

  starlink_pss_forward_kernel_join #(
    .KERNEL_ROM_FILE ("tb/upper_edge_pss_kernel_q23.mem")
  ) dut (
    .clk                       (clk),
    .resetn                    (resetn),
    .flush                     (flush),
    .input_valid               (input_valid),
    .input_ready               (input_ready),
    .input_i                   (input_i),
    .input_q                   (input_q),
    .input_bin_index           (input_bin_index),
    .input_block_exponent      (input_block_exponent),
    .input_last                (input_last),
    .input_block_start_index   (input_block_start_index),
    .output_valid              (output_valid),
    .output_ready              (output_ready),
    .output_i                  (output_i),
    .output_q                  (output_q),
    .output_kernel_i           (output_kernel_i),
    .output_kernel_q           (output_kernel_q),
    .output_bin_index          (output_bin_index),
    .output_block_exponent     (output_block_exponent),
    .output_last               (output_last),
    .output_block_start_index  (output_block_start_index),
    .accepted_pulse            (accepted_pulse),
    .emitted_pulse             (emitted_pulse),
    .input_block_complete_pulse(input_block_complete_pulse),
    .sequence_error_pulse      (sequence_error_pulse),
    .metadata_error_pulse      (metadata_error_pulse),
    .protocol_fault            (protocol_fault)
  );

  task automatic fail(input string message);
    begin
      $display("FORWARD_KERNEL_JOIN_FAIL %0s cycle=%0d queued=%0d verified=%0d",
               message, cycle_count, write_count - read_count, verified_count);
      $fatal(1);
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
      input_i = $signed(24'sd100000 + bin_index + exponent * 1000);
      input_q = -$signed(24'sd200000 + bin_index + exponent * 1000);
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

  task automatic apply_flush;
    begin
      @(negedge clk);
      input_valid = 1'b0;
      automatic_stalls = 1'b0;
      output_ready = 1'b1;
      flush = 1'b1;
      @(negedge clk);
      flush = 1'b0;
      @(negedge clk);
      if (protocol_fault || !input_ready || output_valid)
        fail("flush did not restore empty ready state");
    end
  endtask

  always @(negedge clk) begin
    if (automatic_stalls)
      output_ready = (cycle_count % 13) != 4 && (cycle_count % 17) != 8;
  end

  always @(posedge clk) begin
    cycle_count = cycle_count + 1;
    if (cycle_count > 20000)
      fail("simulation watchdog expired");

    if (!resetn || flush) begin
      write_count = 0;
      read_count = 0;
      accept_run = 0;
      stalled_last_cycle = 1'b0;
    end else begin
      if (stalled_last_cycle &&
          {output_q, output_i, output_kernel_q, output_kernel_i,
           output_bin_index, output_block_exponent, output_last,
           output_block_start_index} !== stalled_payload)
        fail("combined payload changed while stalled");
      stalled_last_cycle = output_valid && !output_ready;
      stalled_payload = {output_q, output_i, output_kernel_q, output_kernel_i,
                         output_bin_index, output_block_exponent, output_last,
                         output_block_start_index};

      if (output_valid && output_ready) begin
        if (read_count == write_count)
          fail("orphan combined output");
        if ({output_q, output_i} !== expected_data[read_count])
          fail("forward I/Q alignment mismatch");
        if ({output_kernel_q, output_kernel_i} !== expected_kernel[read_count])
          fail("kernel alignment mismatch");
        if (output_bin_index !== expected_bin[read_count] ||
            output_block_exponent !== expected_exponent[read_count] ||
            output_last !== expected_last[read_count] ||
            output_block_start_index !== expected_start[read_count])
          fail("metadata alignment mismatch");
        read_count = read_count + 1;
        verified_count = verified_count + 1;
      end

      if (input_valid && input_ready && !suppress_expected_input) begin
        expected_data[write_count] = {input_q, input_i};
        expected_kernel[write_count] = reference_memory[input_bin_index];
        expected_bin[write_count] = input_bin_index;
        expected_exponent[write_count] = input_block_exponent;
        expected_last[write_count] = input_last;
        expected_start[write_count] = input_block_start_index;
        write_count = write_count + 1;
      end

      if (input_valid && input_ready) begin
        accept_run = accept_run + 1;
        if (accept_run > longest_accept_run)
          longest_accept_run = accept_run;
      end else begin
        accept_run = 0;
      end
    end
  end

  initial begin
    $readmemh("tb/upper_edge_pss_kernel_q23.mem", reference_memory, 0, 511);
    repeat (4) @(posedge clk);
    @(negedge clk);
    resetn = 1'b1;
    repeat (2) @(negedge clk);

    send_block(64'd500000, 5'd3);
    automatic_stalls = 1'b1;
    send_block(64'd500447, 5'd11);
    finish_input();
    wait_for_drain();
    if (verified_count != 1024 || longest_accept_run < 512)
      fail("complete aligned-stream accounting mismatch");

    apply_flush();
    send_beat(9'd0, 5'd7, 64'd600000, 1'b0, 1'b0);
    send_beat(9'd1, 5'd8, 64'd600000, 1'b0, 1'b1);
    @(negedge clk);
    input_valid = 1'b0;
    suppress_expected_input = 1'b0;
    if (!protocol_fault || sequence_error_pulse || !metadata_error_pulse)
      fail("metadata fault did not quarantine the join");
    if (input_ready || output_valid)
      fail("faulted join did not close both interfaces");

    apply_flush();
    send_beat(9'd0, 5'd9, 64'd700000, 1'b0, 1'b0);
    finish_input();
    wait_for_drain();
    if (protocol_fault)
      fail("valid pair failed after recovery");

    $display("FORWARD_KERNEL_JOIN_PASS verified=%0d longest_accept_run=%0d stalls=1 metadata_fault=1 flush=1",
             verified_count, longest_accept_run);
    $finish;
  end

endmodule
