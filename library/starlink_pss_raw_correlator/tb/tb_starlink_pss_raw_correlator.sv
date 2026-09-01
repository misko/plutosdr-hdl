`timescale 1ns/1ps

module tb_starlink_pss_raw_correlator;
  localparam integer MODE_ZERO = 0;
  localparam integer MODE_FULL_SCALE = 1;
  localparam integer MODE_TIE = 2;
  localparam integer MODE_REAL = 3;

  reg clk = 1'b0;
  always #5 clk = ~clk;

  reg reset;
  reg coefficient_clear;
  reg coefficient_valid;
  wire coefficient_ready;
  reg signed [15:0] coefficient_i;
  reg signed [15:0] coefficient_q;
  reg sample_clear;
  reg sample_valid;
  wire sample_ready;
  reg signed [15:0] sample_i;
  reg signed [15:0] sample_q;
  reg [63:0] sample_timestamp;
  reg start;
  wire start_ready;
  wire busy;
  wire result_valid;
  reg result_ready;
  wire signed [6:0] result_lag;
  wire [63:0] result_timestamp;
  wire signed [47:0] result_c_re;
  wire signed [47:0] result_c_im;
  wire signed [47:0] result_ex;
  wire signed [47:0] result_eh;
  wire [8:0] result_saturation_events;
  wire done;
  wire [6:0] coefficient_count;
  wire [7:0] sample_count;

  reg [31:0] real_samples [0:129];
  reg [63:0] real_timestamps [0:129];
  reg [31:0] real_coefficients [0:65];
  integer golden_file;
  integer header_status;
  reg [1023:0] golden_header;

  // Deliberately nonmonotonic raw timestamps.  The first values exercise the
  // unsigned-64 MSB and both sides of the wrap boundary; every slot remains
  // unique so an address shift cannot masquerade as correct timestamp storage.
  function automatic [63:0] adversarial_timestamp;
    input integer index;
    begin
      case (index % 8)
        0: adversarial_timestamp = 64'hffff_ffff_ffff_fffe - index;
        1: adversarial_timestamp = 64'h8000_0000_0000_0000 + index;
        2: adversarial_timestamp = 64'h0000_0001_0000_0000 - index;
        3: adversarial_timestamp = 64'hffff_ffff_ffff_0000 + index;
        4: adversarial_timestamp = 64'h7fff_ffff_ffff_ffff - index;
        5: adversarial_timestamp = 64'h0000_0000_0000_0001 + index;
        6: adversarial_timestamp = 64'hffff_ffff_0000_0000 + index;
        default:
          adversarial_timestamp = 64'h8000_0000_ffff_ffff - index;
      endcase
    end
  endfunction

  starlink_pss_raw_correlator dut (
    .i_clk                      (clk),
    .i_reset                    (reset),
    .i_coefficient_clear        (coefficient_clear),
    .i_coefficient_valid        (coefficient_valid),
    .o_coefficient_ready        (coefficient_ready),
    .i_coefficient_i            (coefficient_i),
    .i_coefficient_q            (coefficient_q),
    .i_sample_clear             (sample_clear),
    .i_sample_valid             (sample_valid),
    .o_sample_ready             (sample_ready),
    .i_sample_i                 (sample_i),
    .i_sample_q                 (sample_q),
    .i_sample_timestamp         (sample_timestamp),
    .i_start                    (start),
    .o_start_ready              (start_ready),
    .o_busy                     (busy),
    .o_result_valid             (result_valid),
    .i_result_ready             (result_ready),
    .o_result_lag               (result_lag),
    .o_result_timestamp         (result_timestamp),
    .o_result_c_re              (result_c_re),
    .o_result_c_im              (result_c_im),
    .o_result_ex                (result_ex),
    .o_result_eh                (result_eh),
    .o_result_saturation_events (result_saturation_events),
    .o_done                     (done),
    .o_coefficient_count        (coefficient_count),
    .o_sample_count             (sample_count)
  );

  task automatic reset_dut;
    begin
      reset = 1'b1;
      repeat (4) @(posedge clk);
      @(negedge clk);
      reset = 1'b0;
      if (start_ready || busy || result_valid || done ||
          !coefficient_ready || sample_ready ||
          (coefficient_count != 0) || (sample_count != 0))
        $fatal(1, "reset did not restore an empty idle engine");
    end
  endtask

  task automatic pulse_rejected_start;
    input integer expected_coefficient_count;
    input integer expected_sample_count;
    begin
      @(negedge clk);
      if (start_ready)
        $fatal(1, "premature start unexpectedly reported ready");
      start = 1'b1;
      #1;
      if (coefficient_ready || sample_ready)
        $fatal(1, "a presented premature start did not close load readiness");
      @(negedge clk);
      start = 1'b0;
      #1;
      if (busy || result_valid || done ||
          (coefficient_count != expected_coefficient_count) ||
          (sample_count != expected_sample_count))
        $fatal(1, "premature start changed engine state");
    end
  endtask

  task automatic load_protocol_coefficients_back_to_back;
    integer index;
    begin
      @(negedge clk);
      coefficient_clear = 1'b1;
      #1;
      if (coefficient_ready || sample_ready || start_ready)
        $fatal(1, "coefficient clear did not close all request readiness");
      @(negedge clk);
      coefficient_clear = 1'b0;
      coefficient_valid = 1'b1;
      for (index = 0; index < 66; index = index + 1) begin
        coefficient_i = 16'sd1;
        coefficient_q = -16'sd1;
        #1;
        if (!coefficient_ready)
          $fatal(1, "back-to-back coefficient ready dropped at tap %0d", index);
        @(negedge clk);
      end
      coefficient_valid = 1'b0;
      #1;
      if ((coefficient_count != 66) || coefficient_ready ||
          !sample_ready || start_ready)
        $fatal(1, "back-to-back 66-tap coefficient load contract failed");

      // A 67th poison tap must be rejected and must not wrap onto tap zero.
      coefficient_i = -16'sd32768;
      coefficient_q = 16'sd32767;
      coefficient_valid = 1'b1;
      if (coefficient_ready)
        $fatal(1, "67th coefficient was advertised as acceptable");
      @(negedge clk);
      coefficient_valid = 1'b0;
      #1;
      if ((coefficient_count != 66) || coefficient_ready || !sample_ready)
        $fatal(1, "67th coefficient changed the completed bank");
    end
  endtask

  task automatic load_protocol_samples_back_to_back;
    integer index;
    begin
      sample_valid = 1'b1;
      for (index = 0; index < 130; index = index + 1) begin
        sample_i = 16'sd0;
        sample_q = 16'sd0;
        sample_timestamp = adversarial_timestamp(index);
        #1;
        if (!sample_ready)
          $fatal(1, "back-to-back sample ready dropped at slot %0d", index);
        @(negedge clk);
      end
      sample_valid = 1'b0;
      #1;
      if ((sample_count != 130) || sample_ready || !start_ready)
        $fatal(1, "back-to-back 130-sample load contract failed");

      // A 131st poison beat must be rejected.  A wrap or overwrite would also
      // make the subsequently checked all-zero arithmetic job fail.
      sample_i = 16'sd32767;
      sample_q = -16'sd32768;
      sample_timestamp = 64'h0123_4567_89ab_cdef;
      sample_valid = 1'b1;
      if (sample_ready)
        $fatal(1, "131st sample was advertised as acceptable");
      @(negedge clk);
      sample_valid = 1'b0;
      #1;
      if ((sample_count != 130) || sample_ready || !start_ready)
        $fatal(1, "131st sample changed the completed capture");
    end
  endtask

  task automatic clear_and_load_coefficients;
    input integer mode;
    integer index;
    begin
      @(negedge clk);
      coefficient_clear = 1'b1;
      @(negedge clk);
      coefficient_clear = 1'b0;
      if ((coefficient_count != 0) || (sample_count != 0))
        $fatal(1, "coefficient clear did not discard the complete job image");

      for (index = 0; index < 66; index = index + 1) begin
        @(negedge clk);
        if (!coefficient_ready)
          $fatal(1, "coefficient ready dropped before tap %0d", index);
        case (mode)
          MODE_ZERO: begin
            coefficient_i = 16'sd1;
            coefficient_q = -16'sd1;
          end
          MODE_FULL_SCALE: begin
            coefficient_i = 16'sd32767;
            coefficient_q = 16'sd32767;
          end
          MODE_TIE: begin
            case (index % 3)
              0: begin
                // The clipped endpoint from the oracle's Q15 tie vector.
                coefficient_i = 16'sd32767;
                coefficient_q = -16'sd32768;
              end
              1: begin
                coefficient_i = 16'sd0;
                coefficient_q = 16'sd2;
              end
              default: begin
                coefficient_i = 16'sd0;
                coefficient_q = -16'sd2;
              end
            endcase
          end
          default: begin
            coefficient_i = $signed(real_coefficients[index][31:16]);
            coefficient_q = $signed(real_coefficients[index][15:0]);
          end
        endcase
        coefficient_valid = 1'b1;
        @(negedge clk);
        coefficient_valid = 1'b0;
      end
      #1;
      if ((coefficient_count != 66) || !sample_ready || start_ready)
        $fatal(1, "exact 66-tap coefficient load contract failed");
    end
  endtask

  task automatic load_samples;
    input integer mode;
    integer index;
    begin
      for (index = 0; index < 130; index = index + 1) begin
        @(negedge clk);
        if (!sample_ready)
          $fatal(1, "sample ready dropped before capture slot %0d", index);
        if ((index == 129) && start_ready)
          $fatal(1, "engine accepted a start with only 129 samples");
        case (mode)
          MODE_ZERO: begin
            sample_i = 16'sd0;
            sample_q = 16'sd0;
            sample_timestamp = 64'd1000 + index;
          end
          MODE_FULL_SCALE: begin
            sample_i = 16'sd32767;
            sample_q = -16'sd32768;
            sample_timestamp = 64'd2000 + index;
          end
          MODE_TIE: begin
            sample_i = 16'sd7;
            sample_q = -16'sd11;
            sample_timestamp = 64'd3000 + index;
          end
          default: begin
            sample_i = $signed(real_samples[index][31:16]);
            sample_q = $signed(real_samples[index][15:0]);
            sample_timestamp = real_timestamps[index];
          end
        endcase
        sample_valid = 1'b1;
        @(negedge clk);
        sample_valid = 1'b0;
      end
      #1;
      if ((sample_count != 130) || !start_ready)
        $fatal(1, "exact 130-sample load contract failed");
    end
  endtask

  task automatic pulse_start;
    begin
      @(negedge clk);
      if (!start_ready)
        $fatal(1, "start was not ready for a fully loaded job");
      start = 1'b1;
      @(negedge clk);
      start = 1'b0;
      if (!busy || start_ready)
        $fatal(1, "start did not enter the busy state");
    end
  endtask

  task automatic exercise_sample_clear;
    integer index;
    begin
      sample_valid = 1'b1;
      for (index = 0; index < 11; index = index + 1) begin
        sample_i = index;
        sample_q = -index;
        sample_timestamp = 64'h8000_0000_0000_0100 - index;
        #1;
        if (!sample_ready)
          $fatal(1, "sample ready dropped during partial capture at slot %0d", index);
        @(negedge clk);
      end
      sample_valid = 1'b0;
      #1;
      if ((coefficient_count != 66) || (sample_count != 11) || start_ready)
        $fatal(1, "partial sample image did not stop start acceptance");
      pulse_rejected_start(66, 11);

      @(negedge clk);
      sample_clear = 1'b1;
      #1;
      if (coefficient_ready || sample_ready || start_ready)
        $fatal(1, "sample clear did not close all request readiness");
      @(negedge clk);
      sample_clear = 1'b0;
      #1;
      if ((coefficient_count != 66) || (sample_count != 0) ||
          coefficient_ready || !sample_ready || start_ready)
        $fatal(1, "sample clear did not retain only the complete bank");
    end
  endtask

  task automatic pulse_busy_start;
    begin
      repeat (4) @(negedge clk);
      if (!busy || start_ready || result_valid)
        $fatal(1, "engine left processing before busy-start test");
      start = 1'b1;
      #1;
      if (start_ready || coefficient_ready || sample_ready)
        $fatal(1, "busy start was advertised as acceptable");
      @(negedge clk);
      start = 1'b0;
      #1;
      if (!busy || start_ready || result_valid ||
          (coefficient_count != 66) || (sample_count != 130))
        $fatal(1, "busy start disturbed the active job");
    end
  endtask

  task automatic check_protocol_job;
    integer index;
    integer stall_cycles;
    reg [7:0] stall_lfsr;
    reg signed [6:0] held_lag;
    reg [63:0] held_timestamp;
    reg signed [47:0] held_re;
    reg signed [47:0] held_im;
    reg signed [47:0] held_ex;
    reg signed [47:0] held_eh;
    reg [8:0] held_saturation_events;
    begin
      // Ready is already high when the first eight tuples become valid.  The
      // remaining tuples see deterministic pseudo-random output stalls.
      result_ready = 1'b1;
      pulse_start();
      pulse_busy_start();
      stall_lfsr = 8'ha7;

      for (index = 0; index < 65; index = index + 1) begin
        while (!result_valid)
          @(negedge clk);

        if (($signed(result_lag) !== (index - 32)) ||
            (result_timestamp !== adversarial_timestamp(index)) ||
            ($signed(result_c_re) !== 0) ||
            ($signed(result_c_im) !== 0) ||
            ($signed(result_ex) !== 0) ||
            ($signed(result_eh) !== 132) ||
            (result_saturation_events !== 0)) begin
          $fatal(1,
                 "protocol result %0d mismatch lag=%0d ts=%h re=%0d im=%0d Ex=%0d Eh=%0d sat=%0d",
                 index, result_lag, result_timestamp, result_c_re, result_c_im,
                 result_ex, result_eh, result_saturation_events);
        end

        if (index < 8) begin
          if (!result_ready)
            $fatal(1, "ready-held-high phase unexpectedly deasserted");
          @(negedge clk);
          if (index == 7)
            result_ready = 1'b0;
        end else begin
          held_lag = result_lag;
          held_timestamp = result_timestamp;
          held_re = result_c_re;
          held_im = result_c_im;
          held_ex = result_ex;
          held_eh = result_eh;
          held_saturation_events = result_saturation_events;
          stall_cycles = stall_lfsr[2:0] % 5;
          stall_lfsr = {
            stall_lfsr[6:0],
            stall_lfsr[7] ^ stall_lfsr[5] ^
            stall_lfsr[4] ^ stall_lfsr[3]
          };
          repeat (stall_cycles) begin
            @(negedge clk);
            if (!result_valid || result_ready ||
                (result_lag !== held_lag) ||
                (result_timestamp !== held_timestamp) ||
                (result_c_re !== held_re) ||
                (result_c_im !== held_im) ||
                (result_ex !== held_ex) ||
                (result_eh !== held_eh) ||
                (result_saturation_events !== held_saturation_events))
              $fatal(1, "protocol result changed during deterministic stall");
          end
          result_ready = 1'b1;
          @(negedge clk);
          result_ready = 1'b0;
        end
      end

      #1;
      if (!done || result_valid || busy || (sample_count != 0) ||
          (coefficient_count != 66))
        $fatal(1, "protocol job did not finish cleanly");
      @(negedge clk);
      if (done)
        $fatal(1, "protocol job done must be a single engine-clock pulse");
    end
  endtask

  task automatic reset_during_processing;
    begin
      if ((coefficient_count != 66) || (sample_count != 0))
        $fatal(1, "processing-reset test did not inherit a retained bank");
      load_samples(MODE_ZERO);
      result_ready = 1'b0;
      pulse_start();
      repeat (12) @(negedge clk);
      if (!busy || result_valid)
        $fatal(1, "processing-reset test did not reach an active arithmetic pass");
      reset_dut();
    end
  endtask

  task automatic reset_during_output;
    begin
      clear_and_load_coefficients(MODE_ZERO);
      load_samples(MODE_ZERO);
      result_ready = 1'b0;
      pulse_start();
      while (!result_valid)
        @(negedge clk);
      if (!busy || ($signed(result_lag) != -32))
        $fatal(1, "output-reset test did not reach the first held tuple");
      repeat (2) @(negedge clk);
      if (!result_valid)
        $fatal(1, "output-reset tuple was not held before reset");
      reset_dut();
    end
  endtask

  task automatic check_job;
    input integer mode;
    integer index;
    integer scan_count;
    integer expected_lag;
    longint signed expected_timestamp;
    longint signed expected_re;
    longint signed expected_im;
    longint signed expected_ex;
    longint signed expected_eh;
    integer expected_saturation_events;
    reg signed [6:0] held_lag;
    reg [63:0] held_timestamp;
    reg signed [47:0] held_re;
    reg signed [47:0] held_im;
    reg signed [47:0] held_ex;
    reg signed [47:0] held_eh;
    reg [8:0] held_saturation_events;
    begin
      pulse_start();
      result_ready = 1'b0;
      for (index = 0; index < 65; index = index + 1) begin
        while (!result_valid)
          @(negedge clk);

        case (mode)
          MODE_ZERO: begin
            expected_lag = index - 32;
            expected_timestamp = 1000 + index;
            expected_re = 0;
            expected_im = 0;
            expected_ex = 0;
            expected_eh = 132;
            expected_saturation_events = 0;
          end
          MODE_FULL_SCALE: begin
            expected_lag = index - 32;
            expected_timestamp = 2000 + index;
            expected_re = -2162622;
            expected_im = -141727432770;
            expected_ex = 141729595458;
            expected_eh = 141725270148;
            expected_saturation_events = 0;
          end
          MODE_TIE: begin
            expected_lag = index - 32;
            expected_timestamp = 3000 + index;
            expected_re = 12975974;
            expected_im = -2883342;
            expected_ex = 11220;
            expected_eh = 47243198662;
            expected_saturation_events = 0;
          end
          default: begin
            scan_count = $fscanf(
                golden_file, "%d %d %d %d %d %d %d\n",
                expected_lag, expected_timestamp, expected_re, expected_im,
                expected_ex, expected_eh, expected_saturation_events);
            if (scan_count != 7)
              $fatal(1, "could not read real golden tuple %0d", index);
          end
        endcase

        if (($signed(result_lag) !== expected_lag) ||
            (result_timestamp !== expected_timestamp) ||
            ($signed(result_c_re) !== expected_re) ||
            ($signed(result_c_im) !== expected_im) ||
            ($signed(result_ex) !== expected_ex) ||
            ($signed(result_eh) !== expected_eh) ||
            (result_saturation_events !== expected_saturation_events)) begin
          $fatal(1,
                 "result %0d mismatch got lag=%0d ts=%0d re=%0d im=%0d Ex=%0d Eh=%0d sat=%0d expected lag=%0d ts=%0d re=%0d im=%0d Ex=%0d Eh=%0d sat=%0d",
                 index, result_lag, result_timestamp, result_c_re, result_c_im,
                 result_ex, result_eh, result_saturation_events,
                 expected_lag, expected_timestamp, expected_re, expected_im,
                 expected_ex, expected_eh, expected_saturation_events);
        end

        if (index == 0) begin
          held_lag = result_lag;
          held_timestamp = result_timestamp;
          held_re = result_c_re;
          held_im = result_c_im;
          held_ex = result_ex;
          held_eh = result_eh;
          held_saturation_events = result_saturation_events;
          repeat (3) begin
            @(negedge clk);
            if (!result_valid ||
                (result_lag !== held_lag) ||
                (result_timestamp !== held_timestamp) ||
                (result_c_re !== held_re) ||
                (result_c_im !== held_im) ||
                (result_ex !== held_ex) ||
                (result_eh !== held_eh) ||
                (result_saturation_events !== held_saturation_events))
              $fatal(1, "result changed under output backpressure");
          end
        end

        result_ready = 1'b1;
        @(negedge clk);
        result_ready = 1'b0;
      end
      if (!done || result_valid || busy || (sample_count != 0) ||
          (coefficient_count != 66))
        $fatal(1, "job did not finish cleanly while retaining its bank");
      @(negedge clk);
      if (done)
        $fatal(1, "done must be a single engine-clock pulse");
    end
  endtask

  initial begin
    reset = 1'b0;
    coefficient_clear = 1'b0;
    coefficient_valid = 1'b0;
    coefficient_i = 16'sd0;
    coefficient_q = 16'sd0;
    sample_clear = 1'b0;
    sample_valid = 1'b0;
    sample_i = 16'sd0;
    sample_q = 16'sd0;
    sample_timestamp = 64'd0;
    start = 1'b0;
    result_ready = 1'b0;

    $readmemh("tb/real_071200_samples_ci16.mem", real_samples);
    $readmemh("tb/real_071200_timestamps.mem", real_timestamps);
    $readmemh("tb/upper_minus100k_coefficients_q15.mem", real_coefficients);

    reset_dut();

    // Adversarial interface qualification: rejected starts and over-capacity
    // beats, back-to-back loading, sample-only clear, raw timestamp storage,
    // ready held high, and deterministic pseudo-random output stalls.
    pulse_rejected_start(0, 0);
    load_protocol_coefficients_back_to_back();
    exercise_sample_clear();
    load_protocol_samples_back_to_back();
    check_protocol_job();

    // Synchronous reset must empty the engine both while arithmetic is active
    // and while a completed tuple is being held under output backpressure.
    reset_during_processing();
    reset_during_output();

    clear_and_load_coefficients(MODE_ZERO);
    load_samples(MODE_ZERO);
    check_job(MODE_ZERO);
    // A completed job discards only samples, so the same bank can be reused.
    load_samples(MODE_ZERO);
    check_job(MODE_ZERO);

    clear_and_load_coefficients(MODE_FULL_SCALE);
    load_samples(MODE_FULL_SCALE);
    check_job(MODE_FULL_SCALE);

    // All 65 windows tie exactly.  This exercises signed endpoint and
    // ties-to-even-derived Q15 values while proving deterministic lag order.
    clear_and_load_coefficients(MODE_TIE);
    load_samples(MODE_TIE);
    check_job(MODE_TIE);

    clear_and_load_coefficients(MODE_REAL);
    load_samples(MODE_REAL);
    golden_file = $fopen("tb/real_071200_golden_tuples.txt", "r");
    if (golden_file == 0)
      $fatal(1, "could not open the frozen real golden tuples");
    // Skip the single provenance header line.
    header_status = $fgets(golden_header, golden_file);
    if (header_status == 0)
      $fatal(1, "could not read the real golden tuple header");
    check_job(MODE_REAL);
    $fclose(golden_file);

    $display("RAW_CORRELATOR_PASS completed_jobs=6 reset_aborts=2 results=390 real_capture_lags=65");
    $finish;
  end

  integer watchdog_cycles = 0;
  always @(posedge clk) begin
    watchdog_cycles <= watchdog_cycles + 1;
    if (watchdog_cycles > 100000)
      $fatal(1, "raw correlator testbench watchdog expired");
  end
endmodule
