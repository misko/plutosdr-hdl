`timescale 1ns/1ps

module tb_starlink_pss_score_divider;

  localparam integer MAX_VECTORS = 8192;

  reg clk = 1'b0;
  reg resetn = 1'b0;
  reg flush = 1'b0;
  reg input_valid = 1'b0;
  reg [68:0] input_numerator = 0;
  reg [68:0] input_denominator = 0;
  reg [63:0] input_start_index = 0;
  reg output_ready = 1'b0;

  wire input_ready;
  wire output_valid;
  wire [7:0] output_score;
  wire [63:0] output_start_index;
  wire output_denominator_zero;
  wire accepted_pulse;
  wire completed_pulse;
  wire zero_denominator_pulse;
  wire busy;

  reg [68:0] vector_numerator [0:MAX_VECTORS-1];
  reg [68:0] vector_denominator [0:MAX_VECTORS-1];
  reg [7:0] vector_score [0:MAX_VECTORS-1];
  integer vector_zero_denominator [0:MAX_VECTORS-1];

  integer vector_count = 0;
  integer sent_count = 0;
  integer received_count = 0;
  integer accepted_pulses = 0;
  integer completed_pulses = 0;
  integer expected_zero_denominator_count = 0;
  integer observed_zero_denominator_pulses = 0;
  integer cycle_count = 0;
  integer timeout = 0;
  integer vector_file;
  integer scan_result;
  integer load_index;
  reg scoring_enabled = 1'b0;
  reg backpressure_observed = 1'b0;
  reg stalled_last_cycle = 1'b0;
  reg [7:0] stalled_score;
  reg [63:0] stalled_start_index;
  reg stalled_denominator_zero;

  always #5 clk = ~clk;

  starlink_pss_score_divider dut (
    .clk                    (clk),
    .resetn                 (resetn),
    .flush                  (flush),
    .input_valid            (input_valid),
    .input_ready            (input_ready),
    .input_numerator        (input_numerator),
    .input_denominator      (input_denominator),
    .input_start_index      (input_start_index),
    .output_valid           (output_valid),
    .output_ready           (output_ready),
    .output_score           (output_score),
    .output_start_index     (output_start_index),
    .output_denominator_zero(output_denominator_zero),
    .accepted_pulse         (accepted_pulse),
    .completed_pulse        (completed_pulse),
    .zero_denominator_pulse (zero_denominator_pulse),
    .busy                   (busy)
  );

  task automatic fail(input string message);
    begin
      $display("SCORE_DIVIDER_FAIL %0s sent=%0d received=%0d cycle=%0d",
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
    if (resetn && scoring_enabled && accepted_pulse)
      accepted_pulses <= accepted_pulses + 1;
    if (resetn && scoring_enabled && completed_pulse)
      completed_pulses <= completed_pulses + 1;
    if (resetn && scoring_enabled && zero_denominator_pulse)
      observed_zero_denominator_pulses <=
        observed_zero_denominator_pulses + 1;

    if (resetn && scoring_enabled && stalled_last_cycle) begin
      if (!output_valid || output_score !== stalled_score ||
          output_start_index !== stalled_start_index ||
          output_denominator_zero !== stalled_denominator_zero)
        fail("output changed while stalled");
    end
    stalled_last_cycle <= resetn && scoring_enabled &&
                          output_valid && !output_ready;
    if (output_valid && !output_ready) begin
      stalled_score <= output_score;
      stalled_start_index <= output_start_index;
      stalled_denominator_zero <= output_denominator_zero;
    end

    if (resetn && scoring_enabled && output_valid && output_ready) begin
      if (received_count >= vector_count)
        fail("unexpected extra output");
      if (output_score !== vector_score[received_count])
        fail("exact rational score mismatch");
      if (output_start_index !== 64'd500000 + received_count)
        fail("start-index metadata mismatch");
      if (output_denominator_zero !==
          vector_zero_denominator[received_count][0])
        fail("zero-denominator metadata mismatch");
      received_count <= received_count + 1;
    end
  end

  initial begin
    $dumpfile("build/tb_starlink_pss_score_divider.vcd");
    $dumpvars(0, tb_starlink_pss_score_divider);

    vector_file = $fopen("build/starlink_pss_score_divider_vectors.txt", "r");
    if (vector_file == 0)
      fail("could not open generated vector file");
    scan_result = $fscanf(vector_file, "%d\n", vector_count);
    if (scan_result != 1 || vector_count <= 0 || vector_count > MAX_VECTORS)
      fail("invalid vector count");
    for (load_index = 0; load_index < vector_count;
         load_index = load_index + 1) begin
      scan_result = $fscanf(
        vector_file, "%h %h %h %d\n",
        vector_numerator[load_index], vector_denominator[load_index],
        vector_score[load_index], vector_zero_denominator[load_index]
      );
      if (scan_result != 4)
        fail("malformed vector file");
      expected_zero_denominator_count = expected_zero_denominator_count +
                                        vector_zero_denominator[load_index];
    end
    $fclose(vector_file);

    repeat (3) @(negedge clk);
    resetn = 1'b1;

    // A flush in the middle of the fixed eight-iteration calculation drops
    // the item without publishing a partial quotient.
    @(negedge clk);
    input_numerator = 69'd1234567;
    input_denominator = 69'd7654321;
    input_start_index = 64'd99;
    input_valid = 1'b1;
    @(negedge clk);
    input_valid = 1'b0;
    repeat (3) @(negedge clk);
    if (!busy)
      fail("flush sentinel did not enter calculation");
    flush = 1'b1;
    @(negedge clk);
    flush = 1'b0;
    if (busy || output_valid)
      fail("mid-calculation flush did not clear the lane");

    // Flush must also invalidate a completed result held by backpressure.
    @(negedge clk);
    input_numerator = 69'd1;
    input_denominator = 69'd2;
    input_start_index = 64'd100;
    input_valid = 1'b1;
    @(negedge clk);
    input_valid = 1'b0;
    timeout = 0;
    while (!output_valid && timeout < 20) begin
      @(negedge clk);
      timeout = timeout + 1;
    end
    if (!output_valid || output_score != 8'd128)
      fail("stalled-output sentinel mismatch");
    flush = 1'b1;
    @(negedge clk);
    flush = 1'b0;
    if (output_valid)
      fail("flush did not invalidate stalled result");

    scoring_enabled = 1'b1;
    timeout = 0;
    while (received_count < vector_count && timeout < 100000) begin
      @(negedge clk);
      output_ready = ((cycle_count % 23) < 16);
      if (sent_count < vector_count) begin
        input_valid = 1'b1;
        input_numerator = vector_numerator[sent_count];
        input_denominator = vector_denominator[sent_count];
        input_start_index = 64'd500000 + sent_count;
      end else begin
        input_valid = 1'b0;
      end
      timeout = timeout + 1;
    end
    @(negedge clk);
    input_valid = 1'b0;
    output_ready = 1'b1;
    repeat (3) @(negedge clk);

    if (sent_count != vector_count || received_count != vector_count)
      fail("vector stream did not drain exactly");
    if (accepted_pulses != vector_count || completed_pulses != vector_count)
      fail("calculation pulse accounting mismatch");
    if (observed_zero_denominator_pulses !=
        expected_zero_denominator_count)
      fail("zero-denominator pulse accounting mismatch");
    if (!backpressure_observed)
      fail("test did not exercise input backpressure");

    $display("SCORE_DIVIDER_PASS vectors=%0d iterations=8 exact_ties_even=1 backpressure=1 flush=1",
             vector_count);
    $finish;
  end

endmodule
