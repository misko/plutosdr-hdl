`timescale 1ns/1ps

module tb_starlink_pss_sliding_correlator;
  localparam integer BANK_SMALL = 0;
  localparam integer BANK_REAL = 1;
  localparam integer BANK_FULL_SCALE = 2;
  localparam integer BANK_ZERO = 3;
  localparam integer SAMPLES_ZERO = 0;
  localparam integer SAMPLES_REAL = 1;
  localparam integer SAMPLES_FULL_SCALE = 2;

  reg clk = 1'b0;
  always #5 clk = ~clk;
  integer cycle_count = 0;
  always @(posedge clk)
    cycle_count <= cycle_count + 1;

  reg reset;

  reg raw_coefficient_clear;
  reg raw_coefficient_valid;
  wire raw_coefficient_ready;
  reg signed [15:0] raw_coefficient_i;
  reg signed [15:0] raw_coefficient_q;
  reg raw_sample_clear;
  reg raw_sample_valid;
  wire raw_sample_ready;
  reg signed [15:0] raw_sample_i;
  reg signed [15:0] raw_sample_q;
  reg [63:0] raw_sample_timestamp;
  reg raw_start;
  wire raw_start_ready;
  wire raw_busy;
  wire raw_result_valid;
  reg raw_result_ready;
  wire signed [6:0] raw_result_lag;
  wire [63:0] raw_result_timestamp;
  wire signed [47:0] raw_result_c_re;
  wire signed [47:0] raw_result_c_im;
  wire signed [47:0] raw_result_ex;
  wire signed [47:0] raw_result_eh;
  wire [8:0] raw_result_saturation_events;
  wire raw_done;
  wire [6:0] raw_coefficient_count;
  wire [7:0] raw_sample_count;

  reg sliding_coefficient_clear;
  reg sliding_coefficient_valid;
  wire sliding_coefficient_ready;
  reg signed [15:0] sliding_coefficient_i;
  reg signed [15:0] sliding_coefficient_q;
  reg sliding_coefficient_commit;
  wire sliding_coefficient_commit_ready;
  reg [31:0] sliding_coefficient_generation;
  wire sliding_coefficient_commit_accepted;
  wire sliding_coefficient_commit_rejected;
  wire sliding_active_coefficient_valid;
  wire [31:0] sliding_active_coefficient_generation;
  wire signed [47:0] sliding_active_coefficient_energy;
  wire [6:0] sliding_shadow_coefficient_count;
  reg sliding_sample_clear;
  reg sliding_sample_valid;
  wire sliding_sample_ready;
  reg signed [15:0] sliding_sample_i;
  reg signed [15:0] sliding_sample_q;
  reg [63:0] sliding_sample_timestamp;
  wire [7:0] sliding_sample_count;
  reg sliding_start;
  wire sliding_start_ready;
  wire sliding_busy;
  wire sliding_result_valid;
  reg sliding_result_ready;
  wire signed [6:0] sliding_result_lag;
  wire [63:0] sliding_result_timestamp;
  wire [31:0] sliding_result_coefficient_generation;
  wire signed [47:0] sliding_result_c_re;
  wire signed [47:0] sliding_result_c_im;
  wire signed [47:0] sliding_result_ex;
  wire signed [47:0] sliding_result_eh;
  wire [8:0] sliding_result_saturation_events;
  wire sliding_done;
  wire [31:0] sliding_bound_error_count;

  starlink_pss_raw_correlator raw_dut (
    .i_clk                      (clk),
    .i_reset                    (reset),
    .i_coefficient_clear        (raw_coefficient_clear),
    .i_coefficient_valid        (raw_coefficient_valid),
    .o_coefficient_ready        (raw_coefficient_ready),
    .i_coefficient_i            (raw_coefficient_i),
    .i_coefficient_q            (raw_coefficient_q),
    .i_sample_clear             (raw_sample_clear),
    .i_sample_valid             (raw_sample_valid),
    .o_sample_ready             (raw_sample_ready),
    .i_sample_i                 (raw_sample_i),
    .i_sample_q                 (raw_sample_q),
    .i_sample_timestamp         (raw_sample_timestamp),
    .i_start                    (raw_start),
    .o_start_ready              (raw_start_ready),
    .o_busy                     (raw_busy),
    .o_result_valid             (raw_result_valid),
    .i_result_ready             (raw_result_ready),
    .o_result_lag               (raw_result_lag),
    .o_result_timestamp         (raw_result_timestamp),
    .o_result_c_re              (raw_result_c_re),
    .o_result_c_im              (raw_result_c_im),
    .o_result_ex                (raw_result_ex),
    .o_result_eh                (raw_result_eh),
    .o_result_saturation_events (raw_result_saturation_events),
    .o_done                     (raw_done),
    .o_coefficient_count        (raw_coefficient_count),
    .o_sample_count             (raw_sample_count)
  );

  starlink_pss_sliding_correlator sliding_dut (
    .i_clk                           (clk),
    .i_reset                         (reset),
    .i_coefficient_clear             (sliding_coefficient_clear),
    .i_coefficient_valid             (sliding_coefficient_valid),
    .o_coefficient_ready             (sliding_coefficient_ready),
    .i_coefficient_i                 (sliding_coefficient_i),
    .i_coefficient_q                 (sliding_coefficient_q),
    .i_coefficient_commit            (sliding_coefficient_commit),
    .o_coefficient_commit_ready      (sliding_coefficient_commit_ready),
    .i_coefficient_generation        (sliding_coefficient_generation),
    .o_coefficient_commit_accepted   (sliding_coefficient_commit_accepted),
    .o_coefficient_commit_rejected   (sliding_coefficient_commit_rejected),
    .o_active_coefficient_valid      (sliding_active_coefficient_valid),
    .o_active_coefficient_generation (sliding_active_coefficient_generation),
    .o_active_coefficient_energy     (sliding_active_coefficient_energy),
    .o_shadow_coefficient_count      (sliding_shadow_coefficient_count),
    .i_sample_clear                  (sliding_sample_clear),
    .i_sample_valid                  (sliding_sample_valid),
    .o_sample_ready                  (sliding_sample_ready),
    .i_sample_i                      (sliding_sample_i),
    .i_sample_q                      (sliding_sample_q),
    .i_sample_timestamp              (sliding_sample_timestamp),
    .o_sample_count                  (sliding_sample_count),
    .i_start                         (sliding_start),
    .o_start_ready                   (sliding_start_ready),
    .o_busy                          (sliding_busy),
    .o_result_valid                  (sliding_result_valid),
    .i_result_ready                  (sliding_result_ready),
    .o_result_lag                    (sliding_result_lag),
    .o_result_timestamp              (sliding_result_timestamp),
    .o_result_coefficient_generation (sliding_result_coefficient_generation),
    .o_result_c_re                   (sliding_result_c_re),
    .o_result_c_im                   (sliding_result_c_im),
    .o_result_ex                     (sliding_result_ex),
    .o_result_eh                     (sliding_result_eh),
    .o_result_saturation_events      (sliding_result_saturation_events),
    .o_done                          (sliding_done),
    .o_bound_error_count             (sliding_bound_error_count)
  );

  reg [31:0] real_samples [0:129];
  reg [63:0] real_timestamps [0:129];
  reg [31:0] real_coefficients [0:65];

  reg signed [6:0] golden_lag [0:64];
  reg [63:0] golden_timestamp [0:64];
  reg signed [47:0] golden_c_re [0:64];
  reg signed [47:0] golden_c_im [0:64];
  reg signed [47:0] golden_ex [0:64];
  reg signed [47:0] golden_eh [0:64];
  reg [8:0] golden_saturation_events [0:64];

  task automatic coefficient_value;
    input integer mode;
    input integer index;
    output reg signed [15:0] value_i;
    output reg signed [15:0] value_q;
    begin
      case (mode)
        BANK_SMALL: begin
          value_i = (index % 17) - 8;
          value_q = (index % 13) - 6;
        end
        BANK_REAL: begin
          value_i = $signed(real_coefficients[index][31:16]);
          value_q = $signed(real_coefficients[index][15:0]);
        end
        BANK_FULL_SCALE: begin
          value_i = -16'sd32768;
          value_q = -16'sd32768;
        end
        default: begin
          value_i = 16'sd0;
          value_q = 16'sd0;
        end
      endcase
    end
  endtask

  task automatic sample_value;
    input integer mode;
    input integer index;
    output reg signed [15:0] value_i;
    output reg signed [15:0] value_q;
    output reg [63:0] value_timestamp;
    begin
      case (mode)
        SAMPLES_REAL: begin
          value_i = $signed(real_samples[index][31:16]);
          value_q = $signed(real_samples[index][15:0]);
          value_timestamp = real_timestamps[index];
        end
        SAMPLES_FULL_SCALE: begin
          value_i = (index[0]) ? 16'sd32767 : -16'sd32768;
          value_q = (index[1]) ? -16'sd32768 : 16'sd32767;
          value_timestamp = 64'hffff_ffff_ffff_ff80 + index;
        end
        default: begin
          value_i = 16'sd0;
          value_q = 16'sd0;
          value_timestamp = 64'h8000_0000_0000_0100 - index;
        end
      endcase
    end
  endtask

  task automatic reset_duts;
    begin
      reset = 1'b1;
      repeat (5) @(posedge clk);
      @(negedge clk);
      reset = 1'b0;
      if (!raw_coefficient_ready || raw_sample_ready || raw_start_ready ||
          !sliding_coefficient_ready || sliding_sample_ready ||
          sliding_start_ready || sliding_active_coefficient_valid)
        $fatal(1, "reset did not restore both empty engines");
    end
  endtask

  task automatic load_raw_bank;
    input integer mode;
    integer index;
    reg signed [15:0] value_i;
    reg signed [15:0] value_q;
    begin
      @(negedge clk);
      raw_coefficient_clear = 1'b1;
      @(negedge clk);
      raw_coefficient_clear = 1'b0;
      #1;
      for (index = 0; index < 66; index = index + 1) begin
        coefficient_value(mode, index, value_i, value_q);
        if (!raw_coefficient_ready)
          $fatal(1, "raw coefficient ready dropped at %0d", index);
        raw_coefficient_i = value_i;
        raw_coefficient_q = value_q;
        raw_coefficient_valid = 1'b1;
        @(negedge clk);
        raw_coefficient_valid = 1'b0;
      end
      if (raw_coefficient_count != 66)
        $fatal(1, "raw bank did not load 66 taps");
    end
  endtask

  task automatic stage_sliding_bank;
    input integer mode;
    integer index;
    reg signed [15:0] value_i;
    reg signed [15:0] value_q;
    begin
      @(negedge clk);
      sliding_coefficient_clear = 1'b1;
      @(negedge clk);
      sliding_coefficient_clear = 1'b0;
      #1;
      for (index = 0; index < 66; index = index + 1) begin
        coefficient_value(mode, index, value_i, value_q);
        if (!sliding_coefficient_ready)
          $fatal(1, "sliding coefficient ready dropped at %0d", index);
        sliding_coefficient_i = value_i;
        sliding_coefficient_q = value_q;
        sliding_coefficient_valid = 1'b1;
        @(negedge clk);
        sliding_coefficient_valid = 1'b0;
      end
      if (!sliding_coefficient_commit_ready ||
          (sliding_shadow_coefficient_count != 66))
        $fatal(1, "sliding shadow bank did not reach commit-ready");
    end
  endtask

  task automatic commit_sliding_bank;
    input [31:0] generation;
    input integer expect_accept;
    integer timeout;
    begin
      sliding_coefficient_generation = generation;
      sliding_coefficient_commit = 1'b1;
      @(negedge clk);
      sliding_coefficient_commit = 1'b0;
      timeout = 0;
      while (!sliding_coefficient_commit_accepted &&
             !sliding_coefficient_commit_rejected && (timeout < 1000)) begin
        @(negedge clk);
        timeout = timeout + 1;
      end
      if (expect_accept) begin
        if (!sliding_coefficient_commit_accepted ||
            sliding_coefficient_commit_rejected ||
            !sliding_active_coefficient_valid ||
            (sliding_active_coefficient_generation != generation) ||
            (sliding_active_coefficient_energy <= 0))
          $fatal(1, "valid sliding coefficient commit was not activated");
      end else begin
        if (!sliding_coefficient_commit_rejected ||
            sliding_coefficient_commit_accepted)
          $fatal(1, "invalid sliding coefficient commit was not rejected");
      end
      @(negedge clk);
      if (sliding_coefficient_commit_accepted ||
          sliding_coefficient_commit_rejected ||
          (sliding_shadow_coefficient_count != 0))
        $fatal(1, "coefficient commit result was not a one-cycle pulse");
    end
  endtask

  task automatic load_raw_samples;
    input integer mode;
    integer index;
    reg signed [15:0] value_i;
    reg signed [15:0] value_q;
    reg [63:0] value_timestamp;
    begin
      for (index = 0; index < 130; index = index + 1) begin
        sample_value(mode, index, value_i, value_q, value_timestamp);
        if (!raw_sample_ready)
          $fatal(1, "raw sample ready dropped at %0d", index);
        raw_sample_i = value_i;
        raw_sample_q = value_q;
        raw_sample_timestamp = value_timestamp;
        raw_sample_valid = 1'b1;
        @(negedge clk);
        raw_sample_valid = 1'b0;
      end
      if (!raw_start_ready || (raw_sample_count != 130))
        $fatal(1, "raw sample image did not become start-ready");
    end
  endtask

  task automatic load_sliding_samples;
    input integer mode;
    integer index;
    reg signed [15:0] value_i;
    reg signed [15:0] value_q;
    reg [63:0] value_timestamp;
    begin
      for (index = 0; index < 130; index = index + 1) begin
        sample_value(mode, index, value_i, value_q, value_timestamp);
        if (!sliding_sample_ready)
          $fatal(1, "sliding sample ready dropped at %0d", index);
        sliding_sample_i = value_i;
        sliding_sample_q = value_q;
        sliding_sample_timestamp = value_timestamp;
        sliding_sample_valid = 1'b1;
        @(negedge clk);
        sliding_sample_valid = 1'b0;
      end
      if (!sliding_start_ready || (sliding_sample_count != 130))
        $fatal(1, "sliding sample image did not become start-ready");
    end
  endtask

  task automatic run_raw_collect;
    input integer add_stalls;
    output integer elapsed_cycles;
    integer index;
    integer start_cycle;
    integer stall_cycles;
    reg [7:0] lfsr;
    begin
      start_cycle = cycle_count;
      raw_start = 1'b1;
      @(negedge clk);
      raw_start = 1'b0;
      raw_result_ready = 1'b0;
      lfsr = 8'hb7;
      for (index = 0; index < 65; index = index + 1) begin
        while (!raw_result_valid)
          @(negedge clk);
        golden_lag[index] = raw_result_lag;
        golden_timestamp[index] = raw_result_timestamp;
        golden_c_re[index] = raw_result_c_re;
        golden_c_im[index] = raw_result_c_im;
        golden_ex[index] = raw_result_ex;
        golden_eh[index] = raw_result_eh;
        golden_saturation_events[index] = raw_result_saturation_events;
        stall_cycles = add_stalls ? (lfsr[2:0] % 4) : 0;
        lfsr = {lfsr[6:0], lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]};
        repeat (stall_cycles) begin
          @(negedge clk);
          if (!raw_result_valid ||
              (raw_result_lag !== golden_lag[index]) ||
              (raw_result_timestamp !== golden_timestamp[index]) ||
              (raw_result_c_re !== golden_c_re[index]) ||
              (raw_result_c_im !== golden_c_im[index]) ||
              (raw_result_ex !== golden_ex[index]) ||
              (raw_result_eh !== golden_eh[index]))
            $fatal(1, "raw tuple changed under backpressure");
        end
        raw_result_ready = 1'b1;
        @(negedge clk);
        raw_result_ready = 1'b0;
      end
      if (!raw_done || raw_busy || raw_result_valid)
        $fatal(1, "raw reference job did not finish cleanly");
      elapsed_cycles = cycle_count - start_cycle;
    end
  endtask

  task automatic run_sliding_compare;
    input [31:0] expected_generation;
    input integer add_stalls;
    output integer elapsed_cycles;
    integer index;
    integer start_cycle;
    integer stall_cycles;
    reg [7:0] lfsr;
    reg signed [6:0] held_lag;
    reg [63:0] held_timestamp;
    reg signed [47:0] held_c_re;
    reg signed [47:0] held_c_im;
    reg signed [47:0] held_ex;
    reg signed [47:0] held_eh;
    begin
      start_cycle = cycle_count;
      sliding_start = 1'b1;
      @(negedge clk);
      sliding_start = 1'b0;
      sliding_result_ready = 1'b0;
      lfsr = 8'h6d;
      for (index = 0; index < 65; index = index + 1) begin
        while (!sliding_result_valid)
          @(negedge clk);
        if ((sliding_result_lag !== golden_lag[index]) ||
            (sliding_result_timestamp !== golden_timestamp[index]) ||
            (sliding_result_coefficient_generation !== expected_generation) ||
            (sliding_result_c_re !== golden_c_re[index]) ||
            (sliding_result_c_im !== golden_c_im[index]) ||
            (sliding_result_ex !== golden_ex[index]) ||
            (sliding_result_eh !== golden_eh[index]) ||
            (sliding_result_saturation_events !==
             golden_saturation_events[index]))
          $fatal(1,
                 "differential tuple %0d mismatch lag=%0d/%0d ts=%h/%h re=%0d/%0d im=%0d/%0d Ex=%0d/%0d Eh=%0d/%0d sat=%0d/%0d gen=%0d/%0d",
                 index, sliding_result_lag, golden_lag[index],
                 sliding_result_timestamp, golden_timestamp[index],
                 sliding_result_c_re, golden_c_re[index],
                 sliding_result_c_im, golden_c_im[index],
                 sliding_result_ex, golden_ex[index],
                 sliding_result_eh, golden_eh[index],
                 sliding_result_saturation_events,
                 golden_saturation_events[index],
                 sliding_result_coefficient_generation, expected_generation);
        held_lag = sliding_result_lag;
        held_timestamp = sliding_result_timestamp;
        held_c_re = sliding_result_c_re;
        held_c_im = sliding_result_c_im;
        held_ex = sliding_result_ex;
        held_eh = sliding_result_eh;
        stall_cycles = add_stalls ? (lfsr[2:0] % 5) : 0;
        lfsr = {lfsr[6:0], lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]};
        repeat (stall_cycles) begin
          @(negedge clk);
          if (!sliding_result_valid ||
              (sliding_result_lag !== held_lag) ||
              (sliding_result_timestamp !== held_timestamp) ||
              (sliding_result_c_re !== held_c_re) ||
              (sliding_result_c_im !== held_c_im) ||
              (sliding_result_ex !== held_ex) ||
              (sliding_result_eh !== held_eh))
            $fatal(1, "sliding tuple changed under backpressure");
        end
        sliding_result_ready = 1'b1;
        @(negedge clk);
        sliding_result_ready = 1'b0;
      end
      if (!sliding_done || sliding_busy || sliding_result_valid ||
          (sliding_sample_count != 0))
        $fatal(1, "sliding job did not finish cleanly");
      elapsed_cycles = cycle_count - start_cycle;
    end
  endtask

  integer raw_cycles;
  integer sliding_cycles;
  integer raw_no_stall_cycles;
  integer sliding_no_stall_cycles;
  integer compared_jobs;
  reg signed [47:0] retained_energy;

  initial begin
    reset = 1'b0;
    raw_coefficient_clear = 1'b0;
    raw_coefficient_valid = 1'b0;
    raw_coefficient_i = 16'sd0;
    raw_coefficient_q = 16'sd0;
    raw_sample_clear = 1'b0;
    raw_sample_valid = 1'b0;
    raw_sample_i = 16'sd0;
    raw_sample_q = 16'sd0;
    raw_sample_timestamp = 64'd0;
    raw_start = 1'b0;
    raw_result_ready = 1'b0;
    sliding_coefficient_clear = 1'b0;
    sliding_coefficient_valid = 1'b0;
    sliding_coefficient_i = 16'sd0;
    sliding_coefficient_q = 16'sd0;
    sliding_coefficient_commit = 1'b0;
    sliding_coefficient_generation = 32'd0;
    sliding_sample_clear = 1'b0;
    sliding_sample_valid = 1'b0;
    sliding_sample_i = 16'sd0;
    sliding_sample_q = 16'sd0;
    sliding_sample_timestamp = 64'd0;
    sliding_start = 1'b0;
    sliding_result_ready = 1'b0;
    compared_jobs = 0;

    $readmemh("tb/real_071200_samples_ci16.mem", real_samples);
    $readmemh("tb/real_071200_timestamps.mem", real_timestamps);
    $readmemh("tb/upper_minus100k_coefficients_q15.mem", real_coefficients);

    reset_duts();

    // Stress the 38-bit legal Ex bound with signed CI16 endpoints while using
    // a small bank that satisfies the committed-Eh < 2^31 contract.
    load_raw_bank(BANK_SMALL);
    stage_sliding_bank(BANK_SMALL);
    commit_sliding_bank(32'd11, 1);
    load_raw_samples(SAMPLES_FULL_SCALE);
    load_sliding_samples(SAMPLES_FULL_SCALE);
    run_raw_collect(0, raw_cycles);
    run_sliding_compare(32'd11, 0, sliding_cycles);
    raw_no_stall_cycles = raw_cycles;
    sliding_no_stall_cycles = sliding_cycles;
    compared_jobs = compared_jobs + 1;
    if ((sliding_cycles >= raw_cycles) || (sliding_cycles > 5000))
      $fatal(1, "sliding schedule did not improve raw schedule raw=%0d sliding=%0d",
             raw_cycles, sliding_cycles);

    // Reuse the active/cached bank with deterministic output backpressure.
    load_raw_samples(SAMPLES_ZERO);
    load_sliding_samples(SAMPLES_ZERO);
    run_raw_collect(1, raw_cycles);
    run_sliding_compare(32'd11, 1, sliding_cycles);
    compared_jobs = compared_jobs + 1;

    // The frozen real bank and capture provide 65 more independent tuples.
    load_raw_bank(BANK_REAL);
    stage_sliding_bank(BANK_REAL);
    commit_sliding_bank(32'd12, 1);
    retained_energy = sliding_active_coefficient_energy;
    load_raw_samples(SAMPLES_REAL);
    load_sliding_samples(SAMPLES_REAL);
    run_raw_collect(1, raw_cycles);
    run_sliding_compare(32'd12, 1, sliding_cycles);
    compared_jobs = compared_jobs + 1;

    // Invalid shadow commits must not corrupt the already active real bank.
    stage_sliding_bank(BANK_FULL_SCALE);
    commit_sliding_bank(32'd13, 0);
    if (!sliding_active_coefficient_valid ||
        (sliding_active_coefficient_generation != 12) ||
        (sliding_active_coefficient_energy != retained_energy))
      $fatal(1, "over-energy rejection corrupted the active bank");
    load_raw_samples(SAMPLES_ZERO);
    load_sliding_samples(SAMPLES_ZERO);
    run_raw_collect(1, raw_cycles);
    run_sliding_compare(32'd12, 1, sliding_cycles);
    compared_jobs = compared_jobs + 1;

    stage_sliding_bank(BANK_ZERO);
    commit_sliding_bank(32'd14, 0);
    if (!sliding_active_coefficient_valid ||
        (sliding_active_coefficient_generation != 12) ||
        (sliding_active_coefficient_energy != retained_energy))
      $fatal(1, "zero-energy rejection corrupted the active bank");

    if ((compared_jobs != 4) || (sliding_bound_error_count != 0))
      $fatal(1, "differential qualification did not close cleanly");

    $display("SLIDING_CORRELATOR_PASS jobs=4 tuples=260 cached_eh_generations=2 rejected_commits=2 raw_no_stall_cycles=%0d sliding_no_stall_cycles=%0d bound_errors=0",
             raw_no_stall_cycles, sliding_no_stall_cycles);
    $finish;
  end

  integer watchdog_cycles = 0;
  always @(posedge clk) begin
    watchdog_cycles <= watchdog_cycles + 1;
    if (watchdog_cycles > 150000)
      $fatal(1, "sliding correlator testbench watchdog expired");
  end

endmodule
