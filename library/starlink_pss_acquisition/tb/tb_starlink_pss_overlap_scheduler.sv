`timescale 1ns/1ps

module tb_starlink_pss_overlap_scheduler;

  localparam integer FFT_SAMPLES = 512;
  localparam integer OVERLAP_SAMPLES = 65;
  localparam integer STRIDE_SAMPLES = FFT_SAMPLES - OVERLAP_SAMPLES;
  localparam integer FIRST_SEGMENT_SAMPLES = 3500;
  localparam integer FIRST_SEGMENT_BLOCKS = 7;

  reg clk = 1'b0;
  reg resetn = 1'b0;
  reg enable = 1'b0;
  reg sample_valid = 1'b0;
  reg sample_gap = 1'b0;
  reg signed [15:0] sample_i = 0;
  reg signed [15:0] sample_q = 0;
  reg [63:0] sample_index = 0;
  reg fft_ready = 1'b0;

  wire fft_valid;
  wire signed [15:0] fft_i;
  wire signed [15:0] fft_q;
  wire [8:0] fft_position;
  wire fft_last;
  wire [63:0] fft_block_start_index;
  wire flush_pulse;
  wire gap_pulse;
  wire index_error_pulse;
  wire overflow_pulse;
  wire block_queued_pulse;
  wire block_complete_pulse;
  wire busy;
  wire [63:0] segment_sample_count;
  wire [2:0] queued_block_count;

  integer cycle_count = 0;
  integer observed_blocks = 0;
  integer observed_position = 0;
  integer queued_pulses = 0;
  integer complete_pulses = 0;
  integer flush_pulses = 0;
  integer gap_pulses = 0;
  integer index_error_pulses = 0;
  integer overflow_pulses = 0;
  integer sample_number;
  integer timeout;
  reg [63:0] expected_starts [0:FIRST_SEGMENT_BLOCKS];
  reg stalled_last_cycle = 1'b0;
  reg signed [15:0] stalled_i;
  reg signed [15:0] stalled_q;
  reg [8:0] stalled_position;
  reg stalled_last;
  reg [63:0] stalled_start;

  always #5 clk = ~clk;

  starlink_pss_overlap_scheduler dut (
    .clk                   (clk),
    .resetn                (resetn),
    .enable                (enable),
    .sample_valid          (sample_valid),
    .sample_gap            (sample_gap),
    .sample_i              (sample_i),
    .sample_q              (sample_q),
    .sample_index          (sample_index),
    .fft_valid             (fft_valid),
    .fft_ready             (fft_ready),
    .fft_i                 (fft_i),
    .fft_q                 (fft_q),
    .fft_position          (fft_position),
    .fft_last              (fft_last),
    .fft_block_start_index (fft_block_start_index),
    .flush_pulse           (flush_pulse),
    .gap_pulse             (gap_pulse),
    .index_error_pulse     (index_error_pulse),
    .overflow_pulse        (overflow_pulse),
    .block_queued_pulse    (block_queued_pulse),
    .block_complete_pulse  (block_complete_pulse),
    .busy                  (busy),
    .segment_sample_count  (segment_sample_count),
    .queued_block_count    (queued_block_count)
  );

  task automatic fail(input string message);
    begin
      $display("OVERLAP_SCHEDULER_FAIL %0s", message);
      $fatal(1);
    end
  endtask

  function automatic [15:0] encoded_i(input [63:0] index);
    encoded_i = index[15:0];
  endfunction

  function automatic [15:0] encoded_q(input [63:0] index);
    encoded_q = ~index[15:0];
  endfunction

  task automatic send_sample(
    input [63:0] index,
    input gap,
    input integer idle_cycles
  );
    begin
      @(negedge clk);
      sample_index = index;
      sample_i = index[15:0];
      sample_q = ~index[15:0];
      sample_gap = gap;
      sample_valid = 1'b1;
      @(negedge clk);
      sample_valid = 1'b0;
      sample_gap = 1'b0;
      repeat (idle_cycles) @(negedge clk);
    end
  endtask

  always @(negedge clk) begin
    if (!resetn || !enable)
      fft_ready <= 1'b0;
    else
      // Deliberate stalls prove that the output obeys ready/valid while the
      // 15 MS/s-equivalent input cadence remains non-backpressured.
      fft_ready <= ((cycle_count % 11) != 3) &&
                   ((cycle_count % 17) != 5);
  end

  always @(posedge clk) begin
    cycle_count <= cycle_count + 1;

    if (block_queued_pulse)
      queued_pulses <= queued_pulses + 1;
    if (block_complete_pulse)
      complete_pulses <= complete_pulses + 1;
    if (flush_pulse)
      flush_pulses <= flush_pulses + 1;
    if (gap_pulse)
      gap_pulses <= gap_pulses + 1;
    if (index_error_pulse)
      index_error_pulses <= index_error_pulses + 1;
    if (overflow_pulse)
      overflow_pulses <= overflow_pulses + 1;

    if (resetn && stalled_last_cycle) begin
      if (!fft_valid || fft_i !== stalled_i || fft_q !== stalled_q ||
          fft_position !== stalled_position || fft_last !== stalled_last ||
          fft_block_start_index !== stalled_start)
        fail("FFT output changed while stalled");
    end

    stalled_last_cycle <= resetn && fft_valid && !fft_ready;
    if (fft_valid && !fft_ready) begin
      stalled_i <= fft_i;
      stalled_q <= fft_q;
      stalled_position <= fft_position;
      stalled_last <= fft_last;
      stalled_start <= fft_block_start_index;
    end

    if (resetn && fft_valid && fft_ready) begin
      if (observed_blocks > FIRST_SEGMENT_BLOCKS)
        fail("unexpected extra FFT block");
      if (fft_block_start_index !== expected_starts[observed_blocks]) begin
        $display("START_MISMATCH block=%0d got=%0d expected=%0d",
                 observed_blocks, fft_block_start_index,
                 expected_starts[observed_blocks]);
        fail("FFT block start index mismatch");
      end
      if (fft_position !== observed_position[8:0])
        fail("FFT position is not consecutive");
      if (fft_i !== encoded_i(expected_starts[observed_blocks] +
                              observed_position))
        fail("FFT I sample mismatch");
      if (fft_q !== encoded_q(expected_starts[observed_blocks] +
                              observed_position))
        fail("FFT Q sample mismatch");
      if (fft_last !== (observed_position == FFT_SAMPLES - 1))
        fail("FFT last marker mismatch");

      if (observed_position == FFT_SAMPLES - 1) begin
        observed_blocks <= observed_blocks + 1;
        observed_position <= 0;
      end else begin
        observed_position <= observed_position + 1;
      end
    end
  end

  initial begin
    $dumpfile("build/tb_starlink_pss_overlap_scheduler.vcd");
    $dumpvars(0, tb_starlink_pss_overlap_scheduler);

    for (sample_number = 0;
         sample_number < FIRST_SEGMENT_BLOCKS;
         sample_number = sample_number + 1)
      expected_starts[sample_number] = 64'd10000 +
                                       sample_number * STRIDE_SAMPLES;
    expected_starts[FIRST_SEGMENT_BLOCKS] = 64'd50000;

    repeat (3) @(negedge clk);
    resetn = 1'b1;
    enable = 1'b1;

    // Alternate six- and seven-clock sample periods, close to 15 MS/s at
    // 100 MHz, while output stalls occur independently.
    for (sample_number = 0;
         sample_number < FIRST_SEGMENT_SAMPLES;
         sample_number = sample_number + 1)
      send_sample(64'd10000 + sample_number, 1'b0,
                  (sample_number & 1) ? 5 : 4);

    timeout = 0;
    while ((observed_blocks != FIRST_SEGMENT_BLOCKS || busy) && timeout < 50000) begin
      @(negedge clk);
      timeout = timeout + 1;
    end
    if (timeout == 50000)
      fail("timed out draining first segment");

    // An explicit gap after an incomplete history must make the gap-tagged
    // sample the first sample of the new segment and emit no partial block.
    for (sample_number = 0; sample_number < 100; sample_number = sample_number + 1)
      send_sample(64'd10000 + FIRST_SEGMENT_SAMPLES + sample_number,
                  1'b0, 0);
    send_sample(64'd50000, 1'b1, 0);
    for (sample_number = 1; sample_number < 600; sample_number = sample_number + 1)
      send_sample(64'd50000 + sample_number, 1'b0, 0);

    timeout = 0;
    while ((observed_blocks != FIRST_SEGMENT_BLOCKS + 1 || busy) &&
           timeout < 10000) begin
      @(negedge clk);
      timeout = timeout + 1;
    end
    if (timeout == 10000)
      fail("timed out draining post-gap segment");
    repeat (3) @(negedge clk);

    if (observed_position != 0 || queued_pulses != 8 ||
        complete_pulses != 8)
      fail("block accounting mismatch");
    if (flush_pulses != 1 || gap_pulses != 1 ||
        index_error_pulses != 0 || overflow_pulses != 0)
      fail("continuity event accounting mismatch");
    if (queued_block_count != 0 || segment_sample_count != 600)
      fail("final queue or segment count mismatch");

    $display("OVERLAP_SCHEDULER_PASS fft=%0d overlap=%0d stride=%0d blocks=%0d backpressure=1 gap_restart=1",
             FFT_SAMPLES, OVERLAP_SAMPLES, STRIDE_SAMPLES, observed_blocks);
    $finish;
  end

endmodule
