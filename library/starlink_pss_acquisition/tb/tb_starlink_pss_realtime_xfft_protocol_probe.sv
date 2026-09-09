`timescale 1ns/1ps
// Pure observer/fixture driver. No adapter, CDC mailbox, production fault rule,
// output backpressure, or claim that this is an integrated transform service.
module tb_starlink_pss_realtime_xfft_protocol_probe;
  localparam integer RESET = 0, CONFIG = 1, IDLE = 2, INPUT = 3;
  localparam integer COMPUTE = 4, OUTPUT = 5, DRAIN = 6;
  reg clk = 0, aresetn = 0;
  always #2.5 clk = !clk;
  reg [7:0] config_data = 0;
  reg config_valid = 0;
  wire config_ready;
  reg [47:0] input_data = 0;
  reg input_valid = 0, input_last = 0;
  wire input_ready;
  wire [47:0] output_data;
  wire [23:0] output_user;
  wire output_valid, output_last;
  wire [7:0] status_data;
  wire status_valid, event_frame, event_last_unexpected, event_last_missing, event_input_halt;
  reg [31:0] samples [0:1405];
  reg [35:0] forward_values [0:1535], products [0:1535], inverse_values [0:1535];
  reg [4:0] forward_exponents [0:2], inverse_exponents [0:2];
  integer cycle_count = 0, phase = RESET, job_id = -1, fixture = 0;
  reg inverse = 0, starved = 0, job_active = 0;
  integer input_count = 0, output_count = 0, status_count = 0, frame_count = 0;
  integer value_mismatches = 0, metadata_mismatches = 0, tlast_events = 0;
  integer first_input_cycle = -1, first_status_cycle = -1, first_output_cycle = -1;
  integer first_gap_cycle = -1, first_gap_halt_cycle = -1, gap_demands = 0;
  integer halt_cycles [0:6], healthy_halt_cycles [0:6], starved_halt_cycles [0:6];
  integer total_healthy_jobs = 0, total_healthy_words = 0, reset_jobs = 0, no_reset_jobs = 0;
  integer starvation_value_mismatches = 0, starvation_output_count = 0;
  integer starvation_halts = 0, trace_file, k;
  reg [35:0] expected_word;
  reg [4:0] expected_exponent;

  starlink_pss_fft512_bfp18_rt_probe core (
    .aclk(clk), .aresetn(aresetn),
    .s_axis_config_tdata(config_data), .s_axis_config_tvalid(config_valid),
    .s_axis_config_tready(config_ready),
    .s_axis_data_tdata(input_data), .s_axis_data_tvalid(input_valid),
    .s_axis_data_tready(input_ready), .s_axis_data_tlast(input_last),
    .m_axis_data_tdata(output_data), .m_axis_data_tuser(output_user),
    .m_axis_data_tvalid(output_valid), .m_axis_data_tlast(output_last),
    .m_axis_status_tdata(status_data), .m_axis_status_tvalid(status_valid),
    .event_frame_started(event_frame), .event_tlast_unexpected(event_last_unexpected),
    .event_tlast_missing(event_last_missing), .event_data_in_channel_halt(event_input_halt)
  );

  always @(posedge clk) begin
    cycle_count = cycle_count + 1;
    if (cycle_count > 100000) $fatal(1, "realtime observer watchdog");
    $fdisplay(trace_file, "%0d,%0d,%0d,%0b,%0b,%0b,%0b,%0b,%0b,%0d,%0b,%0b,%h,%0b,%h,%h,%0b,%0b,%0b,%0b",
      cycle_count, job_id, phase, aresetn, config_valid, config_ready,
      input_valid, input_ready, input_last, input_count, output_valid, output_last,
      output_user, status_valid, status_data, output_data, event_frame,
      event_last_unexpected, event_last_missing, event_input_halt);
    if (aresetn && job_active) begin
      if (input_valid && input_ready) begin
        input_count = input_count + 1;
        if (first_input_cycle < 0) first_input_cycle = cycle_count;
      end
      if (phase == INPUT && first_input_cycle >= 0 && input_ready && !input_valid) begin
        gap_demands = gap_demands + 1;
        if (first_gap_cycle < 0) first_gap_cycle = cycle_count;
      end
      if (event_input_halt) begin
        halt_cycles[phase] = halt_cycles[phase] + 1;
        if (first_gap_cycle >= 0 && first_gap_halt_cycle < 0)
          first_gap_halt_cycle = cycle_count;
      end
      if (event_frame) frame_count = frame_count + 1;
      if (event_last_unexpected || event_last_missing) tlast_events = tlast_events + 1;
      if (status_valid) begin
        status_count = status_count + 1;
        if (first_status_cycle < 0) first_status_cycle = cycle_count;
        if (status_data !== {3'b0, expected_exponent})
          metadata_mismatches = metadata_mismatches + 1;
      end
      if (output_valid) begin
        if (first_output_cycle < 0) first_output_cycle = cycle_count;
        if (phase == COMPUTE) phase = OUTPUT;
        if (output_count < 512) begin
          expected_word = inverse ? inverse_values[fixture*512 + output_count] :
                                    forward_values[fixture*512 + output_count];
          if ({output_data[41:24], output_data[17:0]} !== expected_word)
            value_mismatches = value_mismatches + 1;
          if (output_user !== {3'b0, expected_exponent, 7'b0, 9'(output_count)} ||
              output_last !== (output_count == 511))
            metadata_mismatches = metadata_mismatches + 1;
        end else metadata_mismatches = metadata_mismatches + 1;
        output_count = output_count + 1;
      end
    end else if (aresetn && (output_valid || status_valid))
      $fatal(1, "unaccounted unbackpressured core output outside an observed job");
  end

  task automatic run_job(input integer next_job, input integer next_fixture,
                         input bit next_inverse, input bit reset_before, input bit inject_starvation);
    integer p, wait_start;
    reg [35:0] word_in;
    begin
      @(negedge clk);
      job_id = next_job; fixture = next_fixture; inverse = next_inverse;
      starved = inject_starvation; job_active = 1;
      expected_exponent = inverse ? inverse_exponents[fixture] : forward_exponents[fixture];
      input_count = 0; output_count = 0; status_count = 0; frame_count = 0;
      value_mismatches = 0; metadata_mismatches = 0; tlast_events = 0;
      first_input_cycle = -1; first_status_cycle = -1; first_output_cycle = -1;
      first_gap_cycle = -1; first_gap_halt_cycle = -1; gap_demands = 0;
      for (p = 0; p < 7; p = p + 1) halt_cycles[p] = 0;
      input_valid = 0; input_last = 0; config_valid = 0;
      if (reset_before) begin
        phase = RESET; aresetn = 0;
        repeat (6) @(negedge clk);
        aresetn = 1;
        repeat (8) @(negedge clk);
        reset_jobs = reset_jobs + 1;
      end else no_reset_jobs = no_reset_jobs + 1;
      phase = IDLE;
      repeat (20 + next_job) @(negedge clk);
      phase = CONFIG;
      config_data = inverse ? 8'h00 : 8'h01;
      config_valid = 1;
      @(posedge clk);
      while (!config_ready) @(posedge clk);
      @(negedge clk); config_valid = 0;
      phase = IDLE;
      repeat (24 + next_job) @(negedge clk);
      phase = INPUT;
      for (p = 0; p < 512; p = p + 1) begin
        word_in = inverse ? products[fixture*512+p] :
          {samples[fixture*447+p][31:16], 2'b00, samples[fixture*447+p][15:0], 2'b00};
        input_data = {6'b0, word_in[35:18], 6'b0, word_in[17:0]};
        input_last = p == 511;
        input_valid = 1;
        // Deliberately withhold 64 active-demand positions after 128 delivered
        // words. Poison the invalid payload so ignored TVALID cannot silently
        // masquerade as a numerically healthy fixture. This is an observation,
        // NOT the proposed production starvation detector or recovery policy.
        if (starved && p >= 128 && p < 192) begin
          if (frame_count == 0) $fatal(1, "starvation injection preceded active frame event");
          input_valid = 0;
          input_data = {6'b0, 18'h15555, 6'b0, 18'h2aaaa};
        end
        @(posedge clk);
        while (!input_ready) @(posedge clk);
        @(negedge clk);
      end
      input_valid = 0; input_last = 0;
      phase = COMPUTE;
      wait_start = cycle_count;
      while (output_count < 512 && cycle_count - wait_start < 5000) @(negedge clk);
      phase = DRAIN;
      repeat (48) @(negedge clk);
      $display("RT_XFFT_JOB job=%0d fixture=%0d inverse=%0d reset_before=%0d starved=%0d input_handshakes=%0d output_words=%0d statuses=%0d frames=%0d value_mismatches=%0d metadata_mismatches=%0d tlast_events=%0d first_input_cycle=%0d first_status_cycle=%0d first_output_cycle=%0d status_minus_first_data=%0d first_gap_cycle=%0d first_halt_after_gap=%0d gap_demands=%0d",
        job_id, fixture, inverse, reset_before, starved, input_count, output_count,
        status_count, frame_count, value_mismatches, metadata_mismatches, tlast_events,
        first_input_cycle, first_status_cycle, first_output_cycle,
        first_status_cycle - first_output_cycle, first_gap_cycle, first_gap_halt_cycle, gap_demands);
      for (p = 0; p < 7; p = p + 1) begin
        $display("RT_XFFT_HALT_PHASE job=%0d starved=%0d phase=%0d halt_cycles=%0d", job_id, starved, p, halt_cycles[p]);
        if (starved) starved_halt_cycles[p] = starved_halt_cycles[p] + halt_cycles[p];
        else healthy_halt_cycles[p] = healthy_halt_cycles[p] + halt_cycles[p];
      end
      if (!starved) begin
        if (input_count != 512 || output_count != 512 || status_count != 1 || frame_count != 1 ||
            value_mismatches || metadata_mismatches || tlast_events || gap_demands)
          $fatal(1, "realtime healthy fixture/lifecycle mismatch job=%0d", job_id);
        total_healthy_jobs = total_healthy_jobs + 1;
        total_healthy_words = total_healthy_words + output_count;
      end else begin
        starvation_value_mismatches = value_mismatches;
        starvation_output_count = output_count;
        for (p = 0; p < 7; p = p + 1) starvation_halts = starvation_halts + halt_cycles[p];
        if (gap_demands != 64) $fatal(1, "starvation probe failed to exercise 64 active-demand gaps");
      end
      job_active = 0;
    end
  endtask
  initial begin
    trace_file = $fopen("realtime_protocol_trace.csv", "w");
    if (!trace_file) $fatal(1, "cannot create protocol trace");
    $fdisplay(trace_file, "cycle,job,phase,resetn,config_valid,config_ready,input_valid,input_ready,input_last,input_handshakes,output_valid,output_last,output_user,status_valid,status_data,output_data,frame_event,last_unexpected,last_missing,input_halt");
    $readmemh("samples_ci16.mem", samples);
    $readmemh("forward_q17.mem", forward_values);
    $readmemh("product_q17.mem", products);
    $readmemh("inverse_q17.mem", inverse_values);
    $readmemh("forward_exponents.mem", forward_exponents);
    $readmemh("inverse_exponents.mem", inverse_exponents);
    for (k = 0; k < 7; k = k + 1) begin
      halt_cycles[k] = 0; healthy_halt_cycles[k] = 0; starved_halt_cycles[k] = 0;
    end
    run_job(0, 0, 0, 1, 0);
    run_job(1, 0, 1, 0, 0);
    run_job(2, 1, 0, 1, 0);
    run_job(3, 1, 1, 0, 0);
    run_job(4, 2, 0, 0, 0);
    run_job(5, 2, 1, 1, 0);
    run_job(6, 1, 0, 1, 1);
    run_job(7, 2, 1, 1, 0);
    if (total_healthy_jobs != 7 || total_healthy_words != 3584)
      $fatal(1, "realtime observer coverage mismatch");
    for (k = 0; k < 7; k = k + 1)
      $display("RT_XFFT_HALT_SUMMARY phase=%0d healthy_halt_cycles=%0d starved_halt_cycles=%0d", k, healthy_halt_cycles[k], starved_halt_cycles[k]);
    $display("REALTIME_XFFT_PROTOCOL_PROBE_PASS healthy_jobs=%0d exact_words=%0d reset_jobs=%0d no_reset_direction_jobs=%0d starvation_output_words=%0d starvation_value_mismatches=%0d starvation_halt_cycles=%0d SERVICE_UNQUALIFIED UNIVERSAL_HALT_RULE_UNQUALIFIED",
      total_healthy_jobs, total_healthy_words, reset_jobs, no_reset_jobs,
      starvation_output_count, starvation_value_mismatches, starvation_halts);
    $fclose(trace_file);
    $finish;
  end
endmodule
