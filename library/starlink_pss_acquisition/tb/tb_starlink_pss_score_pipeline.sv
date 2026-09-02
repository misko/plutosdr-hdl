`timescale 1ns/1ps

module tb_starlink_pss_score_pipeline;

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
  wire ratio_valid;
  wire ratio_ready;
  wire [68:0] ratio_numerator;
  wire [68:0] ratio_denominator;
  wire [63:0] ratio_start_index;
  wire ratio_numerator_saturated;
  wire output_valid;
  wire [7:0] output_score;
  wire [63:0] output_start_index;
  wire output_denominator_zero;

  reg [23:0] vector_correlation_i [0:MAX_VECTORS-1];
  reg [23:0] vector_correlation_q [0:MAX_VECTORS-1];
  reg [37:0] vector_energy [0:MAX_VECTORS-1];
  reg [4:0] vector_forward [0:MAX_VECTORS-1];
  reg [4:0] vector_inverse [0:MAX_VECTORS-1];
  reg [7:0] vector_score [0:MAX_VECTORS-1];
  integer vector_saturated [0:MAX_VECTORS-1];
  integer vector_denominator_zero [0:MAX_VECTORS-1];

  integer vector_count = 0;
  integer sent_count = 0;
  integer received_count = 0;
  integer observed_saturation_count = 0;
  integer expected_saturation_count = 0;
  integer expected_zero_denominator_count = 0;
  integer cycle_count = 0;
  integer timeout = 0;
  integer vector_file;
  integer scan_result;
  integer load_index;
  reg scoring_enabled = 1'b0;
  reg backpressure_observed = 1'b0;
  reg output_stall_observed = 1'b0;
  reg stalled_last_cycle = 1'b0;
  reg [72:0] stalled_payload;

  always #5 clk = ~clk;

  starlink_pss_score_prepare prepare (
    .clk                        (clk),
    .resetn                     (resetn),
    .flush                      (flush),
    .input_valid                (input_valid),
    .input_ready                (input_ready),
    .input_correlation_i        (input_correlation_i),
    .input_correlation_q        (input_correlation_q),
    .input_sample_energy        (input_sample_energy),
    .input_forward_exponent     (input_forward_exponent),
    .input_inverse_exponent     (input_inverse_exponent),
    .input_start_index          (input_start_index),
    .output_valid               (ratio_valid),
    .output_ready               (ratio_ready),
    .output_numerator           (ratio_numerator),
    .output_denominator         (ratio_denominator),
    .output_power_shift         (),
    .output_start_index         (ratio_start_index),
    .output_numerator_saturated (ratio_numerator_saturated),
    .output_denominator_zero    (),
    .accepted_pulse             (),
    .completed_pulse            (),
    .numerator_saturation_pulse (),
    .denominator_zero_pulse     ()
  );

  starlink_pss_score_lanes lanes (
    .clk                     (clk),
    .resetn                  (resetn),
    .flush                   (flush),
    .input_valid             (ratio_valid),
    .input_ready             (ratio_ready),
    .input_numerator         (ratio_numerator),
    .input_denominator       (ratio_denominator),
    .input_start_index       (ratio_start_index),
    .output_valid            (output_valid),
    .output_ready            (output_ready),
    .output_score            (output_score),
    .output_start_index      (output_start_index),
    .output_denominator_zero (output_denominator_zero),
    .accepted_pulse          (),
    .emitted_pulse           (),
    .lane_zero_busy          (),
    .lane_one_busy           (),
    .next_input_lane         (),
    .next_output_lane        ()
  );

  task automatic fail(input string message);
    begin
      $display("SCORE_PIPELINE_FAIL %0s sent=%0d received=%0d cycle=%0d",
               message, sent_count, received_count, cycle_count);
      $fatal(1);
    end
  endtask

  always @(posedge clk) begin
    cycle_count <= cycle_count + 1;
    if (cycle_count > 100000)
      fail("simulation watchdog expired");

    if (resetn && scoring_enabled && input_valid && !input_ready)
      backpressure_observed <= 1'b1;
    if (resetn && scoring_enabled && output_valid && !output_ready)
      output_stall_observed <= 1'b1;
    if (resetn && scoring_enabled && input_valid && input_ready)
      sent_count <= sent_count + 1;
    if (resetn && scoring_enabled && ratio_valid && ratio_ready &&
        ratio_numerator_saturated)
      observed_saturation_count <= observed_saturation_count + 1;

    if (resetn && scoring_enabled && stalled_last_cycle) begin
      if (!output_valid ||
          {output_denominator_zero, output_start_index, output_score} !==
          stalled_payload)
        fail("final score changed while stalled");
    end
    stalled_last_cycle <= resetn && scoring_enabled &&
                          output_valid && !output_ready;
    if (output_valid && !output_ready)
      stalled_payload <= {
        output_denominator_zero, output_start_index, output_score
      };

    if (resetn && scoring_enabled && output_valid && output_ready) begin
      if (received_count >= vector_count)
        fail("unexpected extra score");
      if (output_start_index !== 64'd5000000 + received_count)
        fail("score start-index ordering mismatch");
      if (output_score !== vector_score[received_count])
        fail("score differs from independent exact integer oracle");
      if (output_denominator_zero !==
          vector_denominator_zero[received_count][0])
        fail("zero-denominator metadata mismatch");
      received_count <= received_count + 1;
    end
  end

  initial begin
    $dumpfile("build/tb_starlink_pss_score_pipeline.vcd");
    $dumpvars(0, tb_starlink_pss_score_pipeline);

    vector_file = $fopen("build/starlink_pss_score_pipeline_vectors.txt", "r");
    if (vector_file == 0)
      fail("could not open generated vector file");
    scan_result = $fscanf(vector_file, "%d\n", vector_count);
    if (scan_result != 1 || vector_count <= 0 || vector_count > MAX_VECTORS)
      fail("invalid vector count");
    for (load_index = 0; load_index < vector_count;
         load_index = load_index + 1) begin
      scan_result = $fscanf(
        vector_file, "%h %h %h %h %h %h %d %d\n",
        vector_correlation_i[load_index], vector_correlation_q[load_index],
        vector_energy[load_index], vector_forward[load_index],
        vector_inverse[load_index], vector_score[load_index],
        vector_saturated[load_index],
        vector_denominator_zero[load_index]
      );
      if (scan_result != 8)
        fail("malformed vector file");
      expected_saturation_count = expected_saturation_count +
                                  vector_saturated[load_index];
      expected_zero_denominator_count = expected_zero_denominator_count +
                                        vector_denominator_zero[load_index];
    end
    $fclose(vector_file);

    repeat (3) @(negedge clk);
    resetn = 1'b1;
    output_ready = 1'b0;

    // Abort a live calculation spanning prepare and divider stages.
    @(negedge clk);
    input_correlation_i = 24'sd123456;
    input_correlation_q = -24'sd654321;
    input_sample_energy = 38'd987654321;
    input_forward_exponent = 5'd2;
    input_inverse_exponent = 5'd1;
    input_start_index = 64'd42;
    input_valid = 1'b1;
    @(negedge clk);
    input_valid = 1'b0;
    repeat (4) @(negedge clk);
    flush = 1'b1;
    @(negedge clk);
    flush = 1'b0;
    output_ready = 1'b1;
    repeat (12) @(negedge clk);
    if (output_valid)
      fail("flush allowed an aborted score to escape");

    scoring_enabled = 1'b1;
    timeout = 0;
    while (received_count < vector_count && timeout < 100000) begin
      @(negedge clk);
      output_ready = (cycle_count % 31) < 20;
      if (sent_count < vector_count) begin
        input_valid = 1'b1;
        input_correlation_i = vector_correlation_i[sent_count];
        input_correlation_q = vector_correlation_q[sent_count];
        input_sample_energy = vector_energy[sent_count];
        input_forward_exponent = vector_forward[sent_count];
        input_inverse_exponent = vector_inverse[sent_count];
        input_start_index = 64'd5000000 + sent_count;
      end else begin
        input_valid = 1'b0;
      end
      timeout = timeout + 1;
    end
    @(negedge clk);
    input_valid = 1'b0;
    output_ready = 1'b1;
    repeat (12) @(negedge clk);

    if (sent_count != vector_count || received_count != vector_count)
      fail("composed score stream did not drain exactly");
    if (observed_saturation_count != expected_saturation_count)
      fail("composed numerator-saturation count mismatch");
    if (!backpressure_observed || !output_stall_observed)
      fail("composed test missed a backpressure path");

    $display("SCORE_PIPELINE_PASS vectors=%0d independent_integer_oracle=1 exact_score=1 ordered_lanes=2 saturation=%0d denominator_zero=%0d stalls=1 flush=1",
             vector_count, expected_saturation_count,
             expected_zero_denominator_count);
    $finish;
  end

endmodule
