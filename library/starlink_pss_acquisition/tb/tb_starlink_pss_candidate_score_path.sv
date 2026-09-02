`timescale 1ns/1ps

module tb_starlink_pss_candidate_score_path;

  localparam integer FFT_POINTS = 512;
  localparam integer VALID_RESULTS = 447;
  localparam integer MAX_RESULTS = 512;
  localparam [63:0] BASE_INDEX = 64'd100000;

  reg clk = 1'b0;
  reg resetn = 1'b0;
  reg flush = 1'b0;
  reg ifft_valid = 1'b0;
  reg signed [23:0] ifft_correlation_i = 0;
  reg signed [23:0] ifft_correlation_q = 0;
  reg [8:0] ifft_index = 0;
  reg [4:0] forward_exponent = 0;
  reg [4:0] inverse_exponent = 0;
  reg [63:0] block_start_index = 0;
  reg ifft_last = 1'b0;
  reg score_ready = 1'b0;
  reg sample_valid = 1'b0;
  reg sample_gap = 1'b0;
  reg signed [15:0] sample_i = 0;
  reg signed [15:0] sample_q = 0;
  reg [63:0] sample_index = 0;

  wire ifft_ready;
  wire cache_lookup_valid;
  wire cache_lookup_ready;
  wire [63:0] cache_lookup_start_index;
  wire cache_output_valid;
  wire cache_output_ready;
  wire [37:0] cache_output_energy;
  wire [63:0] cache_output_start_index;
  wire cache_output_found;
  wire score_valid;
  wire [7:0] score_value;
  wire [63:0] score_start_index;
  wire score_denominator_zero;
  wire path_fault;
  wire ifft_protocol_fault;
  wire fifo_overflow_fault;
  wire energy_join_fault;
  wire [9:0] fifo_stored_count;
  wire [9:0] fifo_maximum_stored_count;

  reg [63:0] vector_start_index [0:MAX_RESULTS-1];
  reg [37:0] vector_energy [0:MAX_RESULTS-1];
  reg [7:0] vector_score [0:MAX_RESULTS-1];

  integer vector_count = 0;
  integer received_count = 0;
  integer cycle_count = 0;
  integer vector_file;
  integer scan_result;
  integer load_index;
  integer offset;
  integer timeout;
  integer good_maximum_occupancy = 0;
  reg monitor_scores = 1'b0;
  reg stalled_last_cycle = 1'b0;
  reg [72:0] stalled_payload;

  always #5 clk = ~clk;

  function automatic signed [15:0] encoded_sample_i(input integer item);
    encoded_sample_i = item * 31 - 7000;
  endfunction

  function automatic signed [15:0] encoded_sample_q(input integer item);
    encoded_sample_q = 9000 - item * 29;
  endfunction

  function automatic signed [23:0] encoded_correlation_i(input integer item);
    encoded_correlation_i = -8000000 + item * 30000;
  endfunction

  function automatic signed [23:0] encoded_correlation_q(input integer item);
    encoded_correlation_q = 7000000 - item * 25000;
  endfunction

  starlink_pss_energy_cache energy_cache (
    .clk                       (clk),
    .resetn                    (resetn),
    .enable                    (1'b1),
    .flush                     (flush),
    .sample_valid              (sample_valid),
    .sample_gap                (sample_gap),
    .sample_i                  (sample_i),
    .sample_q                  (sample_q),
    .sample_index              (sample_index),
    .lookup_valid              (cache_lookup_valid),
    .lookup_ready              (cache_lookup_ready),
    .lookup_start_index        (cache_lookup_start_index),
    .output_valid              (cache_output_valid),
    .output_ready              (cache_output_ready),
    .output_energy             (cache_output_energy),
    .output_start_index        (cache_output_start_index),
    .output_found              (cache_output_found),
    .energy_write_pulse        (),
    .energy_write_value        (),
    .energy_write_start_index  (),
    .gap_pulse                 (),
    .index_error_pulse         (),
    .restart_pulse             (),
    .retention_miss_pulse      (),
    .stored_energy_count       (),
    .oldest_energy_start_index (),
    .newest_energy_start_index ()
  );

  starlink_pss_candidate_score_path score_path (
    .clk                         (clk),
    .resetn                      (resetn),
    .flush                       (flush),
    .ifft_valid                  (ifft_valid),
    .ifft_ready                  (ifft_ready),
    .ifft_correlation_i          (ifft_correlation_i),
    .ifft_correlation_q          (ifft_correlation_q),
    .ifft_index                  (ifft_index),
    .forward_exponent            (forward_exponent),
    .inverse_exponent            (inverse_exponent),
    .block_start_index           (block_start_index),
    .ifft_last                   (ifft_last),
    .cache_lookup_valid          (cache_lookup_valid),
    .cache_lookup_ready          (cache_lookup_ready),
    .cache_lookup_start_index    (cache_lookup_start_index),
    .cache_output_valid          (cache_output_valid),
    .cache_output_ready          (cache_output_ready),
    .cache_output_energy         (cache_output_energy),
    .cache_output_start_index    (cache_output_start_index),
    .cache_output_found          (cache_output_found),
    .score_valid                 (score_valid),
    .score_ready                 (score_ready),
    .score_value                 (score_value),
    .score_start_index           (score_start_index),
    .score_denominator_zero      (score_denominator_zero),
    .path_fault                  (path_fault),
    .ifft_protocol_fault         (ifft_protocol_fault),
    .fifo_overflow_fault         (fifo_overflow_fault),
    .energy_join_fault           (energy_join_fault),
    .fifo_stored_count           (fifo_stored_count),
    .fifo_maximum_stored_count   (fifo_maximum_stored_count)
  );

  task automatic fail(input string message);
    begin
      $display("CANDIDATE_SCORE_PATH_FAIL %0s cycle=%0d received=%0d fifo=%0d max=%0d fault=%b",
               message, cycle_count, received_count, fifo_stored_count,
               fifo_maximum_stored_count, path_fault);
      $fatal(1);
    end
  endtask

  task automatic pulse_flush;
    begin
      @(negedge clk);
      ifft_valid = 1'b0;
      sample_valid = 1'b0;
      flush = 1'b1;
      @(negedge clk);
      flush = 1'b0;
      #1;
    end
  endtask

  always @(posedge clk) begin
    cycle_count <= cycle_count + 1;
    if (cycle_count > 30000)
      fail("simulation watchdog expired");

    if (resetn && monitor_scores && stalled_last_cycle) begin
      if (!score_valid ||
          {score_denominator_zero, score_start_index, score_value} !==
          stalled_payload)
        fail("score changed while stalled");
    end
    stalled_last_cycle <= resetn && monitor_scores &&
                          score_valid && !score_ready;
    if (score_valid && !score_ready)
      stalled_payload <= {
        score_denominator_zero, score_start_index, score_value
      };

    if (resetn && monitor_scores && score_valid && score_ready) begin
      if (received_count >= vector_count)
        fail("unexpected extra score");
      if (score_start_index !== vector_start_index[received_count] ||
          score_value !== vector_score[received_count])
        fail("real-cache integration differs from exact oracle");
      if (score_denominator_zero)
        fail("nonzero integration energy reported a zero denominator");
      received_count <= received_count + 1;
    end
  end

  initial begin
    $dumpfile("build/tb_starlink_pss_candidate_score_path.vcd");
    $dumpvars(0, tb_starlink_pss_candidate_score_path);

    vector_file = $fopen(
      "build/starlink_pss_candidate_score_path_vectors.txt", "r"
    );
    if (vector_file == 0)
      fail("could not open generated integration vectors");
    scan_result = $fscanf(vector_file, "%d\n", vector_count);
    if (scan_result != 1 || vector_count != VALID_RESULTS)
      fail("invalid integration vector count");
    for (load_index = 0; load_index < vector_count;
         load_index = load_index + 1) begin
      scan_result = $fscanf(
        vector_file, "%h %h %h\n",
        vector_start_index[load_index], vector_energy[load_index],
        vector_score[load_index]
      );
      if (scan_result != 3)
        fail("malformed integration vector file");
    end
    $fclose(vector_file);

    repeat (3) @(negedge clk);
    resetn = 1'b1;

    // Precompute all 447 exact 66-sample windows in the real energy cache.
    @(negedge clk);
    sample_valid = 1'b1;
    for (offset = 0; offset < FFT_POINTS; offset = offset + 1) begin
      sample_index = BASE_INDEX + offset;
      sample_i = encoded_sample_i(offset);
      sample_q = encoded_sample_q(offset);
      sample_gap = 1'b0;
      @(negedge clk);
    end
    sample_valid = 1'b0;
    repeat (4) @(negedge clk);

    // The IFFT source is deliberately dense. The complete block must enter
    // on consecutive clocks while the FIFO decouples the slower score lanes.
    score_ready = 1'b1;
    monitor_scores = 1'b1;
    ifft_valid = 1'b1;
    for (offset = 0; offset < FFT_POINTS; offset = offset + 1) begin
      ifft_index = offset[8:0];
      ifft_correlation_i = encoded_correlation_i(offset);
      ifft_correlation_q = encoded_correlation_q(offset);
      forward_exponent = 5'd2;
      inverse_exponent = 5'd2;
      block_start_index = BASE_INDEX;
      ifft_last = offset == FFT_POINTS - 1;
      #1;
      if (!ifft_ready)
        fail("dense 512-result IFFT block was backpressured");
      @(negedge clk);
    end
    ifft_valid = 1'b0;

    timeout = 0;
    while (received_count < vector_count && timeout < 5000) begin
      @(negedge clk);
      score_ready = (cycle_count % 23) < 16;
      timeout = timeout + 1;
    end
    score_ready = 1'b1;
    repeat (12) @(negedge clk);
    if (received_count != VALID_RESULTS)
      fail("one-block score stream did not drain exactly");
    if (path_fault || ifft_protocol_fault || fifo_overflow_fault ||
        energy_join_fault)
      fail("well-formed integrated block raised a fault");
    if (fifo_stored_count != 0 || fifo_maximum_stored_count < 300 ||
        fifo_maximum_stored_count >= 512)
      fail("integrated FIFO occupancy was not bounded as expected");
    good_maximum_occupancy = fifo_maximum_stored_count;

    // Flush both scorer and cache, then omit energy. The first qualified
    // candidate must cause a cache-miss quarantine and cannot become score 0.
    monitor_scores = 1'b0;
    pulse_flush();
    if (path_fault || !ifft_ready)
      fail("flush did not recover integrated path");
    ifft_valid = 1'b1;
    for (offset = 0; offset <= 66 && !path_fault; offset = offset + 1) begin
      ifft_index = offset[8:0];
      ifft_correlation_i = encoded_correlation_i(offset);
      ifft_correlation_q = encoded_correlation_q(offset);
      forward_exponent = 5'd2;
      inverse_exponent = 5'd2;
      block_start_index = 64'd200000;
      ifft_last = 1'b0;
      begin : wait_for_fault_input_accept
        forever begin
          @(posedge clk);
          if (ifft_ready || path_fault)
            disable wait_for_fault_input_accept;
        end
      end
      @(negedge clk);
    end
    ifft_valid = 1'b0;
    timeout = 0;
    while (!path_fault && timeout < 30) begin
      @(negedge clk);
      timeout = timeout + 1;
    end
    if (!path_fault || !energy_join_fault || score_valid || ifft_ready)
      fail("missing energy did not fail closed before score publication");

    pulse_flush();
    if (path_fault || score_valid || !ifft_ready)
      fail("final flush did not return composed path to idle");

    $display("CANDIDATE_SCORE_PATH_PASS ifft=512 qualified=447 exact_cache_join=1 exact_scores=1 dense_input=1 fifo_max=%0d miss_quarantine=1 flush=1",
             good_maximum_occupancy);
    $finish;
  end

endmodule
