`timescale 1ns/1ps

module tb_starlink_pss_exact_reducer;

  reg clk = 1'b0;
  always #5 clk = ~clk;

  reg reset = 1'b1;
  reg tuple_valid = 1'b0;
  wire tuple_ready;
  reg tuple_first = 1'b0;
  reg tuple_last = 1'b0;
  reg include_eh = 1'b0;
  reg [31:0] request_id = 32'd0;
  reg [63:0] center_index = 64'd0;
  reg [63:0] center_timestamp = 64'd0;
  reg signed [6:0] lag = 7'sd0;
  reg [63:0] timestamp = 64'd0;
  reg [31:0] coefficient_generation = 32'd0;
  reg signed [47:0] c_re = 48'sd0;
  reg signed [47:0] c_im = 48'sd0;
  reg signed [47:0] ex = 48'sd0;
  reg signed [47:0] eh = 48'sd0;
  reg [8:0] saturation_events = 9'd0;

  wire result_valid;
  reg result_ready = 1'b0;
  wire result_score_valid;
  wire result_includes_eh;
  wire [31:0] result_request_id;
  wire [63:0] result_center_index;
  wire [63:0] result_center_timestamp;
  wire signed [6:0] result_lag;
  wire [63:0] result_timestamp;
  wire [31:0] result_coefficient_generation;
  wire signed [47:0] result_c_re;
  wire signed [47:0] result_c_im;
  wire signed [47:0] result_ex;
  wire signed [47:0] result_eh;
  wire [8:0] result_saturation_events;
  wire [76:0] result_score_numerator;
  wire [68:0] result_score_denominator;
  wire [31:0] processed_job_count;
  wire [31:0] emitted_result_count;
  wire [31:0] invalid_tuple_count;
  wire [31:0] bound_error_count;
  wire [31:0] protocol_error_count;

  starlink_pss_exact_reducer dut (
    .i_clk                         (clk),
    .i_reset                       (reset),
    .i_tuple_valid                 (tuple_valid),
    .o_tuple_ready                 (tuple_ready),
    .i_tuple_first                 (tuple_first),
    .i_tuple_last                  (tuple_last),
    .i_include_eh                  (include_eh),
    .i_request_id                  (request_id),
    .i_center_index                (center_index),
    .i_center_timestamp            (center_timestamp),
    .i_lag                         (lag),
    .i_timestamp                   (timestamp),
    .i_coefficient_generation      (coefficient_generation),
    .i_c_re                        (c_re),
    .i_c_im                        (c_im),
    .i_ex                          (ex),
    .i_eh                          (eh),
    .i_saturation_events           (saturation_events),
    .o_result_valid                (result_valid),
    .i_result_ready                (result_ready),
    .o_result_score_valid          (result_score_valid),
    .o_result_includes_eh          (result_includes_eh),
    .o_result_request_id           (result_request_id),
    .o_result_center_index         (result_center_index),
    .o_result_center_timestamp     (result_center_timestamp),
    .o_result_lag                  (result_lag),
    .o_result_timestamp            (result_timestamp),
    .o_result_coefficient_generation(result_coefficient_generation),
    .o_result_c_re                 (result_c_re),
    .o_result_c_im                 (result_c_im),
    .o_result_ex                   (result_ex),
    .o_result_eh                   (result_eh),
    .o_result_saturation_events    (result_saturation_events),
    .o_result_score_numerator      (result_score_numerator),
    .o_result_score_denominator    (result_score_denominator),
    .o_processed_job_count         (processed_job_count),
    .o_emitted_result_count        (emitted_result_count),
    .o_invalid_tuple_count         (invalid_tuple_count),
    .o_bound_error_count           (bound_error_count),
    .o_protocol_error_count        (protocol_error_count)
  );

  task automatic fail;
    input [1023:0] message;
    begin
      $display("EXACT_REDUCER_FAIL %0s", message);
      $fatal(1);
    end
  endtask

  function automatic [47:0] absolute48;
    input signed [47:0] value;
    begin
      absolute48 = value[47] ? (~value[47:0] + 48'd1) : value[47:0];
    end
  endfunction

  function automatic [76:0] magnitude_squared;
    input signed [47:0] value_re;
    input signed [47:0] value_im;
    reg [47:0] magnitude_re;
    reg [47:0] magnitude_im;
    reg [75:0] square_re;
    reg [75:0] square_im;
    begin
      magnitude_re = absolute48(value_re);
      magnitude_im = absolute48(value_im);
      square_re = magnitude_re * magnitude_re;
      square_im = magnitude_im * magnitude_im;
      magnitude_squared = {1'b0, square_re} + {1'b0, square_im};
    end
  endfunction

  reg reference_valid;
  reg reference_include_eh;
  reg [76:0] reference_numerator;
  reg [68:0] reference_denominator;
  reg signed [6:0] reference_lag;
  reg [63:0] reference_timestamp;
  reg [31:0] reference_generation;
  reg signed [47:0] reference_c_re;
  reg signed [47:0] reference_c_im;
  reg signed [47:0] reference_ex;
  reg signed [47:0] reference_eh;
  reg [8:0] reference_saturation;

  task automatic reference_clear;
    input mode_include_eh;
    begin
      reference_valid = 1'b0;
      reference_include_eh = mode_include_eh;
      reference_numerator = 77'd0;
      reference_denominator = 69'd0;
      reference_lag = 7'sd0;
      reference_timestamp = 64'd0;
      reference_generation = 32'd0;
      reference_c_re = 48'sd0;
      reference_c_im = 48'sd0;
      reference_ex = 48'sd0;
      reference_eh = 48'sd0;
      reference_saturation = 9'd0;
    end
  endtask

  task automatic reference_consider;
    reg [76:0] candidate_numerator;
    reg [68:0] candidate_denominator;
    reg [145:0] candidate_cross;
    reg [145:0] winner_cross;
    begin
      if ((ex > 0) && (eh > 0) && (saturation_events == 0) &&
          (c_re[47:38] == {10{c_re[38]}}) &&
          (c_im[47:38] == {10{c_im[38]}}) &&
          !(|ex[47:38]) && !(|eh[47:31])) begin
        candidate_numerator = magnitude_squared(c_re, c_im);
        candidate_denominator = include_eh ?
            ($unsigned(ex[37:0]) * $unsigned(eh[30:0])) :
            {31'd0, ex[37:0]};
        candidate_cross = candidate_numerator * reference_denominator;
        winner_cross = reference_numerator * candidate_denominator;
        if (!reference_valid || (candidate_cross > winner_cross)) begin
          reference_valid = 1'b1;
          reference_numerator = candidate_numerator;
          reference_denominator = candidate_denominator;
          reference_lag = lag;
          reference_timestamp = timestamp;
          reference_generation = coefficient_generation;
          reference_c_re = c_re;
          reference_c_im = c_im;
          reference_ex = ex;
          reference_eh = eh;
          reference_saturation = saturation_events;
        end
      end
    end
  endtask

  task automatic submit_current_tuple;
    integer wait_cycles;
    begin
      reference_consider();
      @(negedge clk);
      tuple_valid = 1'b1;
      wait_cycles = 0;
      while (!tuple_ready) begin
        @(negedge clk);
        wait_cycles = wait_cycles + 1;
        if (wait_cycles > 500)
          fail("tuple processing exceeded bounded latency");
      end
      @(negedge clk);
      tuple_valid = 1'b0;
      tuple_first = 1'b0;
      tuple_last = 1'b0;
    end
  endtask

  task automatic check_result;
    input [31:0] expected_request_id;
    input [63:0] expected_center_index;
    input [63:0] expected_center_timestamp;
    reg [611:0] held_result;
    integer stall_cycle;
    begin
      result_ready = 1'b0;
      while (!result_valid)
        @(negedge clk);
      held_result = {
        result_score_valid,
        result_includes_eh,
        result_request_id,
        result_center_index,
        result_center_timestamp,
        result_lag,
        result_timestamp,
        result_coefficient_generation,
        result_c_re,
        result_c_im,
        result_ex,
        result_eh,
        result_saturation_events,
        result_score_numerator,
        result_score_denominator
      };
      for (stall_cycle = 0; stall_cycle < 7; stall_cycle = stall_cycle + 1) begin
        @(negedge clk);
        if (!result_valid || held_result !== {
            result_score_valid,
            result_includes_eh,
            result_request_id,
            result_center_index,
            result_center_timestamp,
            result_lag,
            result_timestamp,
            result_coefficient_generation,
            result_c_re,
            result_c_im,
            result_ex,
            result_eh,
            result_saturation_events,
            result_score_numerator,
            result_score_denominator
          })
          fail("published result changed under backpressure");
      end

      if (result_request_id !== expected_request_id ||
          result_center_index !== expected_center_index ||
          result_center_timestamp !== expected_center_timestamp ||
          result_score_valid !== reference_valid ||
          result_includes_eh !== reference_include_eh)
        fail("result job metadata or validity mismatch");

      if (reference_valid) begin
        if (result_lag !== reference_lag ||
            result_timestamp !== reference_timestamp ||
            result_coefficient_generation !== reference_generation ||
            result_c_re !== reference_c_re ||
            result_c_im !== reference_c_im ||
            result_ex !== reference_ex || result_eh !== reference_eh ||
            result_saturation_events !== reference_saturation ||
            result_score_numerator !== reference_numerator ||
            result_score_denominator !== reference_denominator)
          fail("exact winner packet mismatch");
      end else if (result_score_numerator != 0 ||
                   result_score_denominator != 0)
        fail("invalid job published a nonzero score");

      result_ready = 1'b1;
      @(negedge clk);
      result_ready = 1'b0;
      while (result_valid)
        @(negedge clk);
    end
  endtask

  task automatic drive_job;
    input integer pattern;
    input mode_include_eh;
    input [31:0] job_request;
    input [63:0] job_center;
    integer tuple_index;
    integer signed_lag;
    begin
      reference_clear(mode_include_eh);
      for (tuple_index = 0; tuple_index < 65;
           tuple_index = tuple_index + 1) begin
        signed_lag = tuple_index - 32;
        tuple_first = (tuple_index == 0);
        tuple_last = (tuple_index == 64);
        include_eh = mode_include_eh;
        request_id = job_request;
        center_index = job_center;
        center_timestamp = 64'h9000_0000_0000_0000 + job_center;
        lag = signed_lag;
        timestamp = 64'h1000_0000_0000_0000 + job_center + signed_lag;
        coefficient_generation = 32'd1000 + tuple_index;
        saturation_events = 9'd0;

        case (pattern)
          0: begin
            c_re = 48'sd10 + tuple_index;
            c_im = -48'sd3;
            ex = 48'sd1000 + tuple_index;
            eh = 48'sd300;
            if (signed_lag == 5) begin
              c_re = 48'sd1000;
              c_im = 48'sd0;
              ex = 48'sd100;
            end else if (signed_lag == 6) begin
              c_re = 48'sd2000;
              c_im = 48'sd0;
              ex = 48'sd500;
            end
          end

          1: begin
            c_re = 48'sd100;
            c_im = 48'sd0;
            ex = 48'sd100;
            eh = 48'sd100;
            if (signed_lag == -5) begin
              c_re = 48'sd1000;
              eh = 48'sd1000;
            end else if (signed_lag == 7) begin
              c_re = 48'sd800;
              eh = 48'sd100;
            end
          end

          2: begin
            c_re = 48'sd12345;
            c_im = -48'sd6789;
            ex = 48'sd54321;
            eh = 48'sd1234;
          end

          3: begin
            c_re = 48'sd20;
            c_im = 48'sd10;
            ex = 48'sd100;
            eh = 48'sd200;
            if ((tuple_index % 3) == 0)
              ex = 48'sd0;
            else if ((tuple_index % 3) == 1)
              eh = 48'sd0;
            else
              saturation_events = 9'd1;
            if (tuple_index == 0) begin
              c_re = 48'sd1 <<< 40;
              ex = 48'sd100;
            end else if (tuple_index == 1) begin
              ex = 48'sd1 <<< 40;
              eh = 48'sd200;
            end else if (tuple_index == 2) begin
              eh = 48'sd1 <<< 35;
              saturation_events = 9'd0;
            end
          end

          default: begin
            c_re = (48'sd1 <<< 37) - tuple_index;
            c_im = -((48'sd1 <<< 36) + tuple_index);
            ex = (48'sd1 <<< 37) - (tuple_index * 17);
            eh = (48'sd1 <<< 30) - (tuple_index * 3);
          end
        endcase

        submit_current_tuple();
      end
      check_result(job_request, job_center,
          64'h9000_0000_0000_0000 + job_center);
    end
  endtask

  integer malformed_index;
  initial begin
    $dumpfile("build/tb_starlink_pss_exact_reducer.vcd");
    $dumpvars(0, tb_starlink_pss_exact_reducer);

    repeat (5) @(negedge clk);
    reset = 1'b0;

    drive_job(0, 1'b0, 32'h1000_0001, 64'd400);
    drive_job(1, 1'b1, 32'h1000_0002, 64'd800);
    drive_job(2, 1'b1, 32'h1000_0003, 64'd1200);
    drive_job(3, 1'b1, 32'h1000_0004, 64'd1600);
    drive_job(4, 1'b1, 32'h1000_0005, 64'd2000);

    // One malformed first lag starts a single fail-closed discard episode.
    // The remaining tuples are accepted only to drain through the last marker.
    reference_clear(1'b0);
    for (malformed_index = 0; malformed_index < 65;
         malformed_index = malformed_index + 1) begin
      tuple_first = (malformed_index == 0);
      tuple_last = (malformed_index == 64);
      include_eh = 1'b0;
      request_id = 32'hdead_0001;
      center_index = 64'd2400;
      center_timestamp = 64'd2400;
      lag = malformed_index - 31;
      timestamp = malformed_index;
      coefficient_generation = 32'd1;
      c_re = 48'sd1;
      c_im = 48'sd0;
      ex = 48'sd1;
      eh = 48'sd1;
      saturation_events = 9'd0;
      @(negedge clk);
      tuple_valid = 1'b1;
      while (!tuple_ready)
        @(negedge clk);
      @(negedge clk);
      tuple_valid = 1'b0;
    end

    repeat (20) @(negedge clk);
    if (result_valid)
      fail("malformed job published a result");
    if (processed_job_count != 5 || emitted_result_count != 5 ||
        invalid_tuple_count != 65 || bound_error_count != 3 ||
        protocol_error_count != 1)
      fail("final reducer counters mismatch");

    $display("EXACT_REDUCER_PASS jobs=%0d emitted=%0d invalid=%0d bound=%0d protocol=%0d",
        processed_job_count, emitted_result_count,
        invalid_tuple_count, bound_error_count, protocol_error_count);
    $finish;
  end

endmodule
