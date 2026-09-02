`timescale 1ns/1ps

module tb_starlink_pss_score_prepare;

  localparam integer MAX_VECTORS = 8192;

  reg clk = 1'b0;
  reg resetn = 1'b0;
  reg flush = 1'b0;
  reg input_valid = 1'b0;
  reg signed [23:0] input_correlation_i = 0;
  reg signed [23:0] input_correlation_q = 0;
  reg [37:0] input_sample_energy = 0;
  reg [4:0] input_forward_exponent = 0;
  reg [4:0] input_inverse_exponent = 0;
  reg [63:0] input_start_index = 0;
  reg output_ready = 1'b0;

  wire input_ready;
  wire output_valid;
  wire [68:0] output_numerator;
  wire [68:0] output_denominator;
  wire [6:0] output_power_shift;
  wire [63:0] output_start_index;
  wire output_numerator_saturated;
  wire output_denominator_zero;
  wire accepted_pulse;
  wire completed_pulse;
  wire numerator_saturation_pulse;
  wire denominator_zero_pulse;

  reg [23:0] vector_correlation_i [0:MAX_VECTORS-1];
  reg [23:0] vector_correlation_q [0:MAX_VECTORS-1];
  reg [37:0] vector_energy [0:MAX_VECTORS-1];
  reg [4:0] vector_forward [0:MAX_VECTORS-1];
  reg [4:0] vector_inverse [0:MAX_VECTORS-1];
  reg [68:0] vector_numerator [0:MAX_VECTORS-1];
  reg [68:0] vector_denominator [0:MAX_VECTORS-1];
  reg [6:0] vector_shift [0:MAX_VECTORS-1];
  integer vector_saturated [0:MAX_VECTORS-1];
  integer vector_denominator_zero [0:MAX_VECTORS-1];

  integer vector_count = 0;
  integer sent_count = 0;
  integer received_count = 0;
  integer accepted_pulses = 0;
  integer completed_pulses = 0;
  integer expected_saturation_count = 0;
  integer observed_saturation_pulses = 0;
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
  reg [68:0] stalled_numerator;
  reg [68:0] stalled_denominator;
  reg [6:0] stalled_shift;
  reg [63:0] stalled_start_index;
  reg stalled_saturated;
  reg stalled_denominator_zero;

  always #5 clk = ~clk;

  starlink_pss_score_prepare dut (
    .clk                         (clk),
    .resetn                      (resetn),
    .flush                       (flush),
    .input_valid                 (input_valid),
    .input_ready                 (input_ready),
    .input_correlation_i         (input_correlation_i),
    .input_correlation_q         (input_correlation_q),
    .input_sample_energy         (input_sample_energy),
    .input_forward_exponent      (input_forward_exponent),
    .input_inverse_exponent      (input_inverse_exponent),
    .input_start_index           (input_start_index),
    .output_valid                (output_valid),
    .output_ready                (output_ready),
    .output_numerator            (output_numerator),
    .output_denominator          (output_denominator),
    .output_power_shift          (output_power_shift),
    .output_start_index          (output_start_index),
    .output_numerator_saturated  (output_numerator_saturated),
    .output_denominator_zero     (output_denominator_zero),
    .accepted_pulse              (accepted_pulse),
    .completed_pulse             (completed_pulse),
    .numerator_saturation_pulse  (numerator_saturation_pulse),
    .denominator_zero_pulse      (denominator_zero_pulse)
  );

  task automatic fail(input string message);
    begin
      $display("SCORE_PREPARE_FAIL %0s sent=%0d received=%0d cycle=%0d",
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
    if (resetn && scoring_enabled && numerator_saturation_pulse)
      observed_saturation_pulses <= observed_saturation_pulses + 1;
    if (resetn && scoring_enabled && denominator_zero_pulse)
      observed_zero_denominator_pulses <=
        observed_zero_denominator_pulses + 1;

    if (resetn && scoring_enabled && stalled_last_cycle) begin
      if (!output_valid || output_numerator !== stalled_numerator ||
          output_denominator !== stalled_denominator ||
          output_power_shift !== stalled_shift ||
          output_start_index !== stalled_start_index ||
          output_numerator_saturated !== stalled_saturated ||
          output_denominator_zero !== stalled_denominator_zero)
        fail("output changed while stalled");
    end
    stalled_last_cycle <= resetn && scoring_enabled &&
                          output_valid && !output_ready;
    if (output_valid && !output_ready) begin
      stalled_numerator <= output_numerator;
      stalled_denominator <= output_denominator;
      stalled_shift <= output_power_shift;
      stalled_start_index <= output_start_index;
      stalled_saturated <= output_numerator_saturated;
      stalled_denominator_zero <= output_denominator_zero;
    end

    if (resetn && scoring_enabled && output_valid && output_ready) begin
      if (received_count >= vector_count)
        fail("unexpected extra output");
      if (output_numerator !== vector_numerator[received_count])
        fail("exact scaled numerator mismatch");
      if (output_denominator !== vector_denominator[received_count])
        fail("exact energy/coefficient denominator mismatch");
      if (output_power_shift !== vector_shift[received_count])
        fail("power-of-two exponent restoration mismatch");
      if (output_start_index !== 64'd700000 + received_count)
        fail("start-index metadata mismatch");
      if (output_numerator_saturated !== vector_saturated[received_count][0])
        fail("numerator saturation metadata mismatch");
      if (output_denominator_zero !==
          vector_denominator_zero[received_count][0])
        fail("zero-denominator metadata mismatch");
      received_count <= received_count + 1;
    end
  end

  initial begin
    $dumpfile("build/tb_starlink_pss_score_prepare.vcd");
    $dumpvars(0, tb_starlink_pss_score_prepare);

    vector_file = $fopen("build/starlink_pss_score_prepare_vectors.txt", "r");
    if (vector_file == 0)
      fail("could not open generated vector file");
    scan_result = $fscanf(vector_file, "%d\n", vector_count);
    if (scan_result != 1 || vector_count <= 0 || vector_count > MAX_VECTORS)
      fail("invalid vector count");
    for (load_index = 0; load_index < vector_count;
         load_index = load_index + 1) begin
      scan_result = $fscanf(
        vector_file, "%h %h %h %h %h %h %h %h %d %d\n",
        vector_correlation_i[load_index], vector_correlation_q[load_index],
        vector_energy[load_index], vector_forward[load_index],
        vector_inverse[load_index], vector_numerator[load_index],
        vector_denominator[load_index], vector_shift[load_index],
        vector_saturated[load_index],
        vector_denominator_zero[load_index]
      );
      if (scan_result != 10)
        fail("malformed vector file");
      expected_saturation_count = expected_saturation_count +
                                  vector_saturated[load_index];
      expected_zero_denominator_count = expected_zero_denominator_count +
                                        vector_denominator_zero[load_index];
    end
    $fclose(vector_file);

    repeat (3) @(negedge clk);
    resetn = 1'b1;

    // Flush an item while it occupies the middle elastic stage.
    @(negedge clk);
    input_correlation_i = 24'sd1234;
    input_correlation_q = -24'sd5678;
    input_sample_energy = 38'd987654;
    input_forward_exponent = 5'd1;
    input_inverse_exponent = 5'd2;
    input_start_index = 64'd99;
    input_valid = 1'b1;
    @(negedge clk);
    input_valid = 1'b0;
    @(negedge clk);
    flush = 1'b1;
    @(negedge clk);
    flush = 1'b0;
    if (output_valid)
      fail("pipeline flush published a partial ratio");

    // Flush must also invalidate a completed result held by backpressure.
    @(negedge clk);
    input_correlation_i = 24'sd1;
    input_correlation_q = 24'sd0;
    input_sample_energy = 38'd1;
    input_forward_exponent = 0;
    input_inverse_exponent = 0;
    input_start_index = 64'd100;
    input_valid = 1'b1;
    @(negedge clk);
    input_valid = 1'b0;
    timeout = 0;
    while (!output_valid && timeout < 10) begin
      @(negedge clk);
      timeout = timeout + 1;
    end
    if (!output_valid || output_numerator != 69'd4 ||
        output_denominator != 69'd1073742825)
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
      output_ready = ((cycle_count % 29) < 19);
      if (sent_count < vector_count) begin
        input_valid = 1'b1;
        input_correlation_i = vector_correlation_i[sent_count];
        input_correlation_q = vector_correlation_q[sent_count];
        input_sample_energy = vector_energy[sent_count];
        input_forward_exponent = vector_forward[sent_count];
        input_inverse_exponent = vector_inverse[sent_count];
        input_start_index = 64'd700000 + sent_count;
      end else begin
        input_valid = 1'b0;
      end
      timeout = timeout + 1;
    end
    @(negedge clk);
    input_valid = 1'b0;
    output_ready = 1'b1;
    repeat (4) @(negedge clk);

    if (sent_count != vector_count || received_count != vector_count)
      fail("vector stream did not drain exactly");
    if (accepted_pulses != vector_count || completed_pulses != vector_count)
      fail("pipeline pulse accounting mismatch");
    if (observed_saturation_pulses != expected_saturation_count)
      fail("numerator-saturation pulse accounting mismatch");
    if (observed_zero_denominator_pulses !=
        expected_zero_denominator_count)
      fail("zero-denominator pulse accounting mismatch");
    if (!backpressure_observed)
      fail("test did not exercise input backpressure");

    $display("SCORE_PREPARE_PASS vectors=%0d exact_ratio=1 saturation=%0d denominator_zero=%0d backpressure=1 flush=1",
             vector_count, expected_saturation_count,
             expected_zero_denominator_count);
    $finish;
  end

endmodule
