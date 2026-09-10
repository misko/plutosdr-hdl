// Actual fixed generated FFT and unchanged arithmetic; isolated, no RF evidence.
`timescale 1ns/1ps
module tb_starlink_pss_fft_island_slice;
  reg clk = 0;
  always #2.5 clk = !clk;
  reg resetn = 0, flush = 0, input_valid = 0, input_last = 0;
  reg [35:0] input_data = 0;
  reg [8:0] input_position = 0;
  reg [63:0] input_block_start = 0;
  wire input_ready, output_valid, output_last, fault, busy;
  wire [35:0] output_data;
  wire [8:0] output_position;
  wire [74:0] output_metadata;
  integer cycle = 0, profile = 0, fixture = 0, current_case = 0;
  // READY is derived from this counter; change it off the sampling edge.
  always @(negedge clk) cycle = cycle + 1;
  reg reader_enable = 1, expect_result = 1, expect_fault = 0;
  wire output_ready = reader_enable &&
    (profile == 0 || (profile == 1 && cycle % 2 == 0) ||
     (profile == 2 && cycle % 17 < 13 && cycle % 2 == 0));
  starlink_pss_fft_island_slice dut (.*);
  reg [31:0] samples [0:1405];
  reg [35:0] forwards [0:1535], products [0:1535], inverses [0:1535];
  reg [4:0] forward_exponents [0:2], inverse_exponents [0:2];
  integer output_words = 0, complete_blocks = 0, exact_forward = 0, exact_product = 0;
  integer total_exact_inverse = 0, healthy_blocks = 0, fault_cases = 0, purge_cases = 0;
  integer trace, first_input_cycle = 0, last_output_cycle = 0;
  integer p, run_index, n, waited, phase;
  reg previous_core_resetn = 0;
  always @(posedge clk) begin
    if (cycle > 800000) $fatal(1, "island bench watchdog");
    $fdisplay(trace, "%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
      cycle, current_case, profile, resetn && !flush, dut.service.state,
      dut.service.core_aresetn, dut.service.job_accept,
      dut.service.config_valid && dut.service.config_ready,
      dut.service.engine_metadata[69], dut.service.certified_input_beat,
      dut.service.core_output_valid, dut.service.core_status_valid,
      dut.service.return_commit_valid && dut.service.output_mailbox_ready,
      dut.service.result_busy, input_valid && input_ready,
      dut.service_output_valid && dut.service.output_ready,
      dut.product_valid && dut.product_ready,
      output_valid && output_ready, output_last, fault);
    if (resetn && !flush) begin
      if (!expect_fault && fault) $fatal(1, "unexpected island fault case=%0d", current_case);
      if (input_valid && input_ready && input_position == 0) first_input_cycle = cycle;
      if (!expect_fault && dut.service_output_valid && dut.service.output_ready &&
          !dut.inverse_result) begin
        if (dut.service_output_data !== forwards[fixture*512+dut.service_output_position] ||
            dut.service_output_metadata[4:0] !== forward_exponents[fixture])
          $fatal(1, "forward reference mismatch");
        exact_forward = exact_forward + 1;
      end
      if (!expect_fault && dut.product_valid && dut.product_ready) begin
        if ({dut.product_q, dut.product_i} !== products[fixture*512+dut.product_position] ||
            dut.product_exponent !== forward_exponents[fixture])
          $fatal(1, "product reference mismatch");
        exact_product = exact_product + 1;
      end
      if (output_valid && output_ready) begin
        if (!expect_result || expect_fault) $fatal(1, "invalid epoch published inverse result");
        if (output_data !== inverses[fixture*512+output_words] ||
            output_position !== 9'(output_words) || output_last !== (output_words == 511) ||
            output_metadata !== {1'b1, input_block_start, forward_exponents[fixture], inverse_exponents[fixture]})
          $fatal(1, "inverse payload/order/descriptor/exponent mismatch case=%0d p=%0d gotpos=%0d got=%h expected=%h metadata=%h", current_case, output_words,
            output_position, output_data, inverses[fixture*512+output_words], output_metadata);
        total_exact_inverse = total_exact_inverse + 1;
        if (output_last) begin
          output_words = 0;
          complete_blocks = complete_blocks + 1;
          healthy_blocks = healthy_blocks + 1;
          last_output_cycle = cycle;
          $display("ISLAND_BLOCK case=%0d profile=%0d fixture=%0d first_input=%0d last_output=%0d inclusive_cycles=%0d",
            current_case, profile, fixture, first_input_cycle, cycle, cycle-first_input_cycle+1);
        end else output_words = output_words + 1;
      end
    end
  end
  task automatic tick;
    @(posedge clk); #0.1;
  endtask
  task automatic purge(input bit use_flush);
    @(negedge clk);
    input_valid = 0;
    if (use_flush) flush = 1; else resetn = 0;
    repeat (12) tick();
    @(negedge clk); flush = 0; resetn = 1;
    output_words = 0; complete_blocks = 0;
    repeat (16) tick();
    if (fault || busy || output_valid) $fatal(1, "purge leaked stale epoch");
    expect_fault = 0; expect_result = 1;
  endtask
  task automatic send_block;
    integer word_index;
    for (word_index = 0; word_index < 512; word_index = word_index + 1) begin
      @(negedge clk);
      input_valid = 1; input_position = word_index; input_last = word_index == 511;
      input_data = {samples[fixture*447+word_index][31:16], 2'b00,
                    samples[fixture*447+word_index][15:0], 2'b00};
      @(posedge clk);
      while (!input_ready) @(posedge clk);
      if (profile == 2 && word_index % 13 == 0) begin
        @(negedge clk); input_valid = 0;
        repeat (3) tick();
      end
    end
    @(negedge clk); input_valid = 0;
  endtask
  task automatic await_idle;
    integer timeout;
    timeout = 0;
    while ((busy || dut.service.state != dut.service.WAIT_BANK) && timeout < 40000) begin
      tick(); timeout = timeout + 1;
    end
    if (timeout == 40000 || fault || output_words != 0) $fatal(1, "block/ACK failed to drain");
  endtask
  task automatic await_fault;
    repeat (16) tick();
    if (!fault || output_valid) $fatal(1, "fault did not quarantine slice");
    repeat (32) tick();
    if (!fault || output_valid) $fatal(1, "fault quarantine not sticky");
    fault_cases = fault_cases + 1;
  endtask
  initial begin
    trace = $fopen("fft_island_trace.csv", "w");
    $fdisplay(trace, "cycle,case,profile,epoch,state,core_resetn,admit,config,inverse,core_input,core_output,status,commit,result_busy,raw_input,service_output,product,output,last,fault");
    $readmemh("samples_ci16.mem", samples);
    $readmemh("forward_q17.mem", forwards);
    $readmemh("product_q17.mem", products);
    $readmemh("inverse_q17.mem", inverses);
    $readmemh("forward_exponents.mem", forward_exponents);
    $readmemh("inverse_exponents.mem", inverse_exponents);
    for (run_index = 0; run_index < 3; run_index = run_index + 1) begin
      profile = run_index; purge(0);
      for (n = 0; n < 6; n = n + 1) begin
        current_case = current_case + 1;
        fixture = n % 3; input_block_start = 64'h200000000 + n*447;
        send_block(); await_idle();
      end
    end
    // Legitimate source gap/flush or reset cancels a partially processed block.
    // Recovery requires a new complete overlap block and a new identity epoch.
    for (phase = 0; phase < 4; phase = phase + 1) begin
      current_case = current_case + 1; profile = 0; purge(0);
      fixture = 1; input_block_start = 64'h300000000;
      expect_result = 0; send_block();
      wait(dut.service.certified_input_beat && dut.service.engine_metadata[69] == (phase >= 2));
      repeat (32) tick();
      purge(phase % 2); purge_cases = purge_cases + 1;
      current_case = current_case + 1; fixture = 2; input_block_start = 64'h400000000;
      send_block(); await_idle();
    end
    // Missing active realtime delivery is a fault, unlike a pre-admission gap.
    current_case = current_case + 1; purge(0); expect_fault = 1; expect_result = 0;
    fixture = 0; send_block();
    wait(dut.service.certified_input_beat);
    repeat (128) tick();
    @(negedge clk); force dut.service.fast_input_valid = 0;
    repeat (2) tick();
    release dut.service.fast_input_valid;
    await_fault();
    // Final-cycle raw vendor fault must veto private result publication.
    current_case = current_case + 1; purge(0); expect_fault = 1; expect_result = 0;
    send_block();
    wait(dut.service.return_commit_valid && dut.service.engine_metadata[69]);
    force dut.service.event_last_missing = 1;
    #0.1;
    if (dut.service.return_commit_valid || output_valid) $fatal(1, "final fault missed commit veto");
    tick(); release dut.service.event_last_missing;
    await_fault();
    // Malformed input ordinal cannot publish its initial bank.
    current_case = current_case + 1; purge(0); expect_fault = 1; expect_result = 0;
    @(negedge clk); input_valid = 1; input_position = 1; input_last = 0;
    tick(); @(negedge clk); input_valid = 0;
    await_fault();
    // A fault after commit, while final output is stalled, stays observable.
    current_case = current_case + 1; purge(0); expect_fault = 1; expect_result = 0;
    reader_enable = 0; send_block();
    wait(dut.service.result_guard.awaiting_ack && dut.service.engine_metadata[69]);
    @(negedge clk); force dut.service.event_last_missing = 1;
    tick(); release dut.service.event_last_missing;
    await_fault(); reader_enable = 1;
    current_case = current_case + 1; purge(0); fixture = 2; input_block_start = 64'h500000000;
    send_block(); await_idle();
    $display("FFT_ISLAND_SLICE_PASS healthy_blocks=%0d exact_inverse_words=%0d exact_forward_words=%0d exact_product_words=%0d purge_cases=%0d fault_cases=%0d",
      healthy_blocks, total_exact_inverse, exact_forward, exact_product, purge_cases, fault_cases);
    $fclose(trace); $finish;
  end
endmodule
