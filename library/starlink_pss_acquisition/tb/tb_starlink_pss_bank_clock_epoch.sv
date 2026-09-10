`timescale 1ns/1fs
// Actual generated clock and idle bank reset synchronizers. No payload/RF proof.
module tb_starlink_pss_bank_clock_epoch;
  reg clk = 0, resetn = 0, clock_resetn = 0, manual_fft_resetn = 1;
  always #5 clk = !clk;
  wire fft_clk, locked;
  wire fft_resetn = resetn && manual_fft_resetn && locked;
  wire input_ready, output_valid, fault;
  wire [35:0] output_data;
  wire [8:0] output_position;
  wire output_last;
  wire [74:0] output_metadata;
  integer epochs = 0, clock_edges = 0;
  realtime first_edge, elapsed, average_period;
  starlink_bank_clock175_candidate clock_source (
    .clk_in1(clk), .clk_out1(fft_clk), .resetn(clock_resetn), .locked(locked)
  );
  starlink_pss_fft_bank_owned_slice bank (
    .clk(clk), .resetn(resetn), .fft_clk(fft_clk), .fft_resetn(fft_resetn),
    .input_valid(1'b0), .input_ready(input_ready), .input_data(36'd0),
    .input_position(9'd0), .input_last(1'b0), .input_block_start(64'd0),
    .output_valid(output_valid), .output_ready(1'b1), .output_data(output_data),
    .output_position(output_position), .output_last(output_last),
    .output_metadata(output_metadata), .fault(fault)
  );
  task automatic fail(input string reason);
    $display("BANK_CLOCK_EPOCH_FAIL %s time_ns=%0.3f epochs=%0d", reason, $realtime, epochs);
    $fatal(1, "bank clock/epoch assertion failed");
  endtask
  initial begin
    #200000;
    fail("bounded clock lock/reset watchdog");
  end
  always @(posedge clk)
    if (resetn && (output_valid || fault)) fail("idle bank published data or faulted");
  always @(posedge fft_clk)
    if ((!locked || !manual_fft_resetn || !resetn) && bank.fast_running === 1'b1)
      fail("fast epoch released without clock lock and reset release");
  task automatic wait_healthy_epoch;
    wait(locked === 1'b1);
    wait(bank.fast_running === 1'b1 && bank.slow_running === 1'b1 && input_ready === 1'b1);
    repeat (8) @(posedge fft_clk);
    if (!locked || !fft_resetn || fault || output_valid) fail("unhealthy released epoch");
    epochs = epochs + 1;
    $display("BANK_CLOCK_EPOCH_READY epoch=%0d time_ns=%0.3f", epochs, $realtime);
  endtask
  task automatic check_reset_asserted;
    #0.002;
    if (bank.fast_running !== 0 || bank.slow_running !== 0 || input_ready !== 0 || output_valid !== 0)
      fail("bank reset did not assert after external epoch reset");
  endtask
  task automatic measure_clock;
    @(posedge fft_clk); first_edge = $realtime;
    repeat (1024) @(posedge fft_clk);
    elapsed = $realtime - first_edge;
    average_period = elapsed / 1024.0;
    // Frozen gate: average 175 MHz period within 5 ps, allowing primitive-model
    // time quantization. This is not a jitter/STA/board clock specification.
    if (average_period < 5.709285714 || average_period > 5.719285714)
      fail("generated average frequency differs from 175 MHz contract");
    clock_edges = clock_edges + 1024;
    $display("BANK_CLOCK_PERIOD_PASS epoch=%0d edges=1024 mean_period_ns=%0.9f", epochs, average_period);
  endtask
  initial begin
    repeat (20) @(negedge clk);
    resetn = 1; clock_resetn = 1;
    wait_healthy_epoch(); measure_clock();
    // Reset the MMCM independently. Its observed LOCKED drop (not an invented
    // same-edge drop) must asynchronously clear the actual bank reset fences.
    @(negedge clk); clock_resetn = 0;
    wait(locked === 1'b0); check_reset_asserted();
    repeat (20) @(negedge clk);
    clock_resetn = 1;
    wait_healthy_epoch(); measure_clock();
    // A separate FPGA epoch reset must work while the clock remains locked.
    @(negedge clk); manual_fft_resetn = 0;
    check_reset_asserted();
    if (!locked) fail("manual epoch reset unexpectedly reset the MMCM");
    repeat (20) @(negedge clk);
    manual_fft_resetn = 1;
    wait_healthy_epoch(); measure_clock();
    if (epochs != 3 || clock_edges != 3072) fail("incomplete clock/reset inventory");
    $display("BANK_CLOCK_EPOCH_PASS epochs=3 measured_edges=3072 mmcm_reset_lock_drop=1 manual_epoch_reset=1 actual_idle_bank=1 NO_PAYLOAD_PHYSICAL_OR_RADIO_CLAIM");
    $finish;
  end
endmodule
