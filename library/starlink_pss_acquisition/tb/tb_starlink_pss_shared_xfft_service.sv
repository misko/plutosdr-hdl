`timescale 1ns/1ps
// Both mailbox crossings plus the real generated XFFT, using independently
// frozen forward/product/inverse vectors. Not a full acquisition capacity gate.
module tb_starlink_pss_shared_xfft_service;
  parameter integer MAIN_JOBS = 6;
  reg clk = 0, fft_clk = 0, resetn = 0, fft_resetn = 0;
  always #5 clk = !clk;
  initial begin #1.3; forever #2.5 fft_clk = !fft_clk; end
  reg input_valid = 0, output_ready = 0, expect_fault = 0;
  reg [35:0] input_data = 0;
  reg [8:0] input_position = 0;
  reg input_last = 0;
  reg [69:0] input_metadata = 0;
  wire input_ready, output_valid, output_last, service_fault;
  wire [35:0] output_data;
  wire [8:0] output_position;
  wire [74:0] output_metadata;
  reg [31:0] samples [0:1405];
  reg [35:0] forward_values [0:1535], products [0:1535], inverse_values [0:1535];
  reg [4:0] forward_exponents [0:2], inverse_exponents [0:2];
  integer cycle_count = 0, output_job = 0, output_word = 0, checked_words = 0;
  integer job, position, fixture, previous_pair_cycle = 0, maximum_pair_cycles = 0;
  reg stalled = 0;
  reg [120:0] stalled_word;
  starlink_pss_shared_xfft_service dut (.*);

  function automatic [69:0] tag(input integer job_id);
    reg [63:0] start_index;
    begin
      start_index = 64'd1000000 + (job_id / 2) * 447;
      tag = {job_id[0], start_index, forward_exponents[(job_id / 2) % 3]};
    end
  endfunction
  always @(negedge clk) output_ready = (cycle_count % 19 != 7 && cycle_count % 19 != 8);
  always @(posedge clk) begin
    cycle_count = cycle_count + 1;
    if (cycle_count > 3000 * (MAIN_JOBS + 10)) $fatal(1, "shared mailbox service watchdog");
    if (!resetn || !fft_resetn) stalled = 0;
    else begin
      if (service_fault && !expect_fault) $fatal(1, "unexpected transform service fault");
      if (stalled && (!output_valid ||
          {output_metadata, output_last, output_position, output_data} !== stalled_word))
        $fatal(1, "stalled transform output changed");
      stalled = output_valid && !output_ready;
      stalled_word = {output_metadata, output_last, output_position, output_data};
      if (output_valid && output_ready) begin
        fixture = (output_job / 2) % 3;
        if (output_data !== (output_job % 2 ? inverse_values[fixture*512 + output_word] :
                                           forward_values[fixture*512 + output_word]) ||
            output_metadata[74:5] !== tag(output_job) ||
            output_metadata[4:0] !== (output_job % 2 ? inverse_exponents[fixture] :
                                                     forward_exponents[fixture]) ||
            output_position !== output_word || output_last !== (output_word == 511))
          $fatal(1, "transform mismatch job=%0d position=%0d got=%h tag=%h",
                 output_job, output_word, output_data, output_metadata);
        checked_words = checked_words + 1;
        if (output_word == 511) begin
          $display("SHARED_MAILBOX_JOB job=%0d cycle=%0d", output_job, cycle_count);
          if (output_job % 2 && output_job < MAIN_JOBS) begin
            if (previous_pair_cycle) begin
              $display("SHARED_MAILBOX_PAIR_INTERVAL slow_cycles=%0d", cycle_count - previous_pair_cycle);
              if (cycle_count - previous_pair_cycle > maximum_pair_cycles)
                maximum_pair_cycles = cycle_count - previous_pair_cycle;
            end
            previous_pair_cycle = cycle_count;
          end
          output_job = output_job + 1;
          output_word = 0;
        end else output_word = output_word + 1;
      end
    end
  end
  task automatic send_job(input integer job_id);
    integer p, f;
    begin
      f = (job_id / 2) % 3;
      for (p = 0; p < 512; p = p + 1) begin
        @(negedge clk);
        input_valid = 1;
        input_position = p;
        input_last = p == 511;
        input_metadata = tag(job_id);
        input_data = job_id % 2 ? products[f*512+p] :
          {samples[f*447+p][31:16], 2'b00, samples[f*447+p][15:0], 2'b00};
        @(posedge clk);
        while (!input_ready) @(posedge clk);
      end
      @(negedge clk); input_valid = 0;
    end
  endtask
  task automatic recover(input bit fast_side);
    begin
      @(negedge clk);
      if (fast_side) fft_resetn = 0;
      else resetn = 0;
      repeat (8) @(negedge clk);
      if (fast_side) fft_resetn = 1;
      else resetn = 1;
      repeat (12) @(negedge clk);
      if (service_fault || output_valid || !input_ready) $fatal(1, "service recovery failed");
      expect_fault = 0;
    end
  endtask
  initial begin
    $readmemh("samples_ci16.mem", samples);
    $readmemh("forward_q17.mem", forward_values);
    $readmemh("product_q17.mem", products);
    $readmemh("inverse_q17.mem", inverse_values);
    $readmemh("forward_exponents.mem", forward_exponents);
    $readmemh("inverse_exponents.mem", inverse_exponents);
    repeat (8) @(negedge clk);
    resetn = 1;
    fft_resetn = 1;
    if (MAIN_JOBS < 6 || MAIN_JOBS % 2) $fatal(1, "requires an even number of at least six jobs");
    for (job = 0; job < MAIN_JOBS; job = job + 1) send_job(job);
    while (output_job < MAIN_JOBS) @(negedge clk);
    repeat (12) @(negedge clk);
    expect_fault = 1;
    // Inject a real adapter fault AFTER partial output has entered the return
    // mailbox. That incomplete transform must never become host-visible.
    fork
      send_job(MAIN_JOBS);
      begin
        wait (dut.fast_output_valid && dut.fast_output_position == 10);
        @(negedge fft_clk);
        force dut.adapter.protocol_fault = 1;
        repeat (12) @(negedge clk);
        if (!service_fault || output_valid || input_ready || output_job != MAIN_JOBS)
          $fatal(1, "in-flight FFT fault was not fenced");
        release dut.adapter.protocol_fault;
      end
    join
    recover(0);
    send_job(MAIN_JOBS);
    while (output_job < MAIN_JOBS + 1) @(negedge clk);
    repeat (12) @(negedge clk);
    expect_fault = 1;
    input_position = 1; input_last = 0; input_valid = 1;
    @(negedge clk); input_valid = 0;
    repeat (12) @(negedge clk);
    if (!service_fault || output_valid || input_ready) $fatal(1, "framing fault was not fenced");
    recover(1);
    send_job(MAIN_JOBS + 1);
    while (output_job < MAIN_JOBS + 2) @(negedge clk);
    repeat (20) @(negedge clk);
    if (checked_words != (MAIN_JOBS + 2) * 512 || output_valid || service_fault)
      $fatal(1, "final service count");
    if (maximum_pair_cycles > 2980) $fatal(1, "saturated service misses nominal pair budget");
    $display("SHARED_XFFT_MAILBOX_PASS jobs=%0d exact_words=%0d max_saturated_pair_cycles=%0d slow_mhz=100 fft_mhz=200 stalls=1 in_flight_fft_fault=1 framing_fault=1 independent_reset_recovery=2 RECEIVER_UNQUALIFIED",
             MAIN_JOBS + 2, checked_words, maximum_pair_cycles);
    $finish(0);
  end
endmodule
