`timescale 1ns/1ps

module tb_starlink_pss_spectrum_product;

  localparam integer MAX_VECTORS = 8192;

  reg clk = 1'b0;
  reg resetn = 1'b0;
  reg flush = 1'b0;
  reg input_valid = 1'b0;
  reg signed [23:0] input_i = 0;
  reg signed [23:0] input_q = 0;
  reg signed [23:0] kernel_i = 0;
  reg signed [23:0] kernel_q = 0;
  reg [8:0] input_bin_index = 0;
  reg [4:0] input_block_exponent = 0;
  reg input_last = 1'b0;
  reg [63:0] input_block_start_index = 0;
  reg output_ready = 1'b0;

  wire input_ready;
  wire output_valid;
  wire signed [23:0] output_i;
  wire signed [23:0] output_q;
  wire [8:0] output_bin_index;
  wire [4:0] output_block_exponent;
  wire output_last;
  wire [63:0] output_block_start_index;
  wire output_overflow;
  wire overflow_pulse;

  reg [23:0] vector_input_i [0:MAX_VECTORS-1];
  reg [23:0] vector_input_q [0:MAX_VECTORS-1];
  reg [23:0] vector_kernel_i [0:MAX_VECTORS-1];
  reg [23:0] vector_kernel_q [0:MAX_VECTORS-1];
  reg [23:0] vector_output_i [0:MAX_VECTORS-1];
  reg [23:0] vector_output_q [0:MAX_VECTORS-1];
  integer vector_overflow [0:MAX_VECTORS-1];

  integer vector_count = 0;
  integer sent_count = 0;
  integer received_count = 0;
  integer expected_overflow_count = 0;
  integer observed_overflow_pulses = 0;
  integer cycle_count = 0;
  integer timeout = 0;
  integer vector_file;
  integer scan_result;
  integer load_index;
  reg scoring_enabled = 1'b0;
  reg backpressure_observed = 1'b0;
  reg stalled_last_cycle = 1'b0;
  reg signed [23:0] stalled_i;
  reg signed [23:0] stalled_q;
  reg [8:0] stalled_bin_index;
  reg [4:0] stalled_block_exponent;
  reg stalled_last;
  reg [63:0] stalled_block_start_index;
  reg stalled_overflow;

  always #5 clk = ~clk;

  starlink_pss_spectrum_product dut (
    .clk                      (clk),
    .resetn                   (resetn),
    .flush                    (flush),
    .input_valid              (input_valid),
    .input_ready              (input_ready),
    .input_i                  (input_i),
    .input_q                  (input_q),
    .kernel_i                 (kernel_i),
    .kernel_q                 (kernel_q),
    .input_bin_index          (input_bin_index),
    .input_block_exponent     (input_block_exponent),
    .input_last               (input_last),
    .input_block_start_index  (input_block_start_index),
    .output_valid             (output_valid),
    .output_ready             (output_ready),
    .output_i                 (output_i),
    .output_q                 (output_q),
    .output_bin_index         (output_bin_index),
    .output_block_exponent    (output_block_exponent),
    .output_last              (output_last),
    .output_block_start_index (output_block_start_index),
    .output_overflow          (output_overflow),
    .overflow_pulse           (overflow_pulse)
  );

  task automatic fail(input string message);
    begin
      $display("SPECTRUM_PRODUCT_FAIL %0s sent=%0d received=%0d cycle=%0d",
               message, sent_count, received_count, cycle_count);
      $fatal(1);
    end
  endtask

  always @(posedge clk) begin
    cycle_count <= cycle_count + 1;

    if (resetn && scoring_enabled && input_valid && !input_ready)
      backpressure_observed <= 1'b1;

    if (resetn && scoring_enabled && input_valid && input_ready)
      sent_count <= sent_count + 1;

    if (resetn && scoring_enabled && overflow_pulse)
      observed_overflow_pulses <= observed_overflow_pulses + 1;

    if (resetn && scoring_enabled && stalled_last_cycle) begin
      if (!output_valid || output_i !== stalled_i || output_q !== stalled_q ||
          output_bin_index !== stalled_bin_index ||
          output_block_exponent !== stalled_block_exponent ||
          output_last !== stalled_last ||
          output_block_start_index !== stalled_block_start_index ||
          output_overflow !== stalled_overflow)
        fail("output changed while stalled");
    end

    stalled_last_cycle <= resetn && scoring_enabled &&
                          output_valid && !output_ready;
    if (output_valid && !output_ready) begin
      stalled_i <= output_i;
      stalled_q <= output_q;
      stalled_bin_index <= output_bin_index;
      stalled_block_exponent <= output_block_exponent;
      stalled_last <= output_last;
      stalled_block_start_index <= output_block_start_index;
      stalled_overflow <= output_overflow;
    end

    if (resetn && scoring_enabled && output_valid && output_ready) begin
      if (received_count >= vector_count)
        fail("unexpected extra output");
      if (output_i !== vector_output_i[received_count] ||
          output_q !== vector_output_q[received_count])
        fail("bit-exact complex product mismatch");
      if (output_overflow !== vector_overflow[received_count][0])
        fail("overflow flag mismatch");
      if (output_bin_index !== (received_count % 512))
        fail("bin index metadata mismatch");
      if (output_block_exponent !== ((received_count * 7) % 32))
        fail("block exponent metadata mismatch");
      if (output_last !== ((received_count % 512) == 511))
        fail("last metadata mismatch");
      if (output_block_start_index !==
          64'd100000 + (received_count / 512) * 447)
        fail("block start metadata mismatch");
      received_count <= received_count + 1;
    end
  end

  initial begin
    $dumpfile("build/tb_starlink_pss_spectrum_product.vcd");
    $dumpvars(0, tb_starlink_pss_spectrum_product);

    vector_file = $fopen("build/starlink_pss_spectrum_product_vectors.txt", "r");
    if (vector_file == 0)
      fail("could not open generated vector file");
    scan_result = $fscanf(vector_file, "%d\n", vector_count);
    if (scan_result != 1 || vector_count <= 0 || vector_count > MAX_VECTORS)
      fail("invalid vector count");
    for (load_index = 0; load_index < vector_count;
         load_index = load_index + 1) begin
      scan_result = $fscanf(
        vector_file, "%h %h %h %h %h %h %d\n",
        vector_input_i[load_index], vector_input_q[load_index],
        vector_kernel_i[load_index], vector_kernel_q[load_index],
        vector_output_i[load_index], vector_output_q[load_index],
        vector_overflow[load_index]
      );
      if (scan_result != 7)
        fail("malformed vector file");
      expected_overflow_count = expected_overflow_count +
                                vector_overflow[load_index];
    end
    $fclose(vector_file);

    repeat (3) @(negedge clk);
    resetn = 1'b1;

    // Prove that flush removes a result already resident at a stalled output.
    @(negedge clk);
    input_i = 24'sd12345;
    input_q = -24'sd23456;
    kernel_i = 24'sd34567;
    kernel_q = -24'sd45678;
    input_valid = 1'b1;
    @(negedge clk);
    if (!input_ready)
      fail("flush sentinel was not accepted");
    input_valid = 1'b0;
    timeout = 0;
    while (!output_valid && timeout < 16) begin
      @(negedge clk);
      timeout = timeout + 1;
    end
    if (!output_valid)
      fail("flush sentinel did not reach stalled output");
    flush = 1'b1;
    @(negedge clk);
    flush = 1'b0;
    if (output_valid)
      fail("flush did not invalidate stalled output");

    scoring_enabled = 1'b1;
    timeout = 0;
    while (received_count < vector_count && timeout < 100000) begin
      @(negedge clk);
      output_ready = ((cycle_count % 19) < 12);
      if (sent_count < vector_count) begin
        input_valid = 1'b1;
        input_i = vector_input_i[sent_count];
        input_q = vector_input_q[sent_count];
        kernel_i = vector_kernel_i[sent_count];
        kernel_q = vector_kernel_q[sent_count];
        input_bin_index = sent_count % 512;
        input_block_exponent = (sent_count * 7) % 32;
        input_last = ((sent_count % 512) == 511);
        input_block_start_index = 64'd100000 +
                                  (sent_count / 512) * 447;
      end else begin
        input_valid = 1'b0;
      end
      timeout = timeout + 1;
    end
    @(negedge clk);
    input_valid = 1'b0;
    output_ready = 1'b1;
    repeat (3) @(negedge clk);

    if (received_count != vector_count || sent_count != vector_count)
      fail("stream did not drain exactly");
    if (!backpressure_observed)
      fail("test did not exercise input backpressure");
    if (observed_overflow_pulses != expected_overflow_count)
      fail("overflow pulse accounting mismatch");

    $display("SPECTRUM_PRODUCT_PASS vectors=%0d overflow_vectors=%0d backpressure=1 flush=1",
             vector_count, expected_overflow_count);
    $finish;
  end

endmodule
