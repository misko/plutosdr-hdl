`timescale 1ns/1ps

// Reach the completed input state through 512 real checked handshakes, then
// test its phase-restricted predicate through the public input/output pins.
// This does not change or qualify result publication, an FFT core, or timing.
module tb_starlink_pss_input_retirement #(
  parameter integer CHECK_IDENTITY = 0,
  parameter integer OMIT_DUPLICATE_MUTATION = 0
);
  reg clk = 0, resetn = 0;
  always #2.5 clk = !clk;
  reg job_start = 0, input_enable = 0, input_valid = 0, input_last = 0;
  reg core_input_tready = 0;
  reg [69:0] job_descriptor = 70'h123456789abcdef012;
  reg [69:0] input_metadata = 70'h123456789abcdef012;
  reg [35:0] input_data = 0;
  reg [8:0] input_position = 0;
  wire input_ready, input_transport_ready, core_input_tvalid, core_input_tlast;
  wire [47:0] core_input_tdata;
  wire certified_input_beat, certified_input_complete, input_complete;
  wire fault_now, protocol_fault;
  wire [2:0] fault_reasons;
  integer delivered = 0, completion_pulses = 0, post_rows = 0, duplicate_rows = 0;
  integer premature_witnesses = 0;
  reg expected_sticky = 0;
  wire retired_fault = OMIT_DUPLICATE_MUTATION ? 1'b0 : (resetn && job_start);
  wire duplicate_start_fault_now;
  starlink_pss_realtime_input_guard #(.CHECK_INPUT_BLOCK_IDENTITY(CHECK_IDENTITY)) dut (.*);

  always @(posedge clk) if (resetn) begin
    if (certified_input_beat) delivered = delivered + 1;
    if (certified_input_complete) completion_pulses = completion_pulses + 1;
  end
  task automatic boot;
    @(negedge clk); resetn = 0; job_start = 0; input_enable = 0;
    input_valid = 0; input_last = 0; core_input_tready = 0;
    input_position = 0; input_metadata = job_descriptor;
    repeat (3) @(negedge clk);
    delivered = 0; completion_pulses = 0;
    resetn = 1;
    #0.1;
    if (input_complete || fault_now || protocol_fault || certified_input_beat)
      $fatal(1, "INPUT_RETIREMENT_RESET_FAILURE");
    @(negedge clk); job_start = 1;
    @(negedge clk); job_start = 0; input_enable = 1; core_input_tready = 1;
  endtask
  task automatic word(input integer position);
    input_valid = 1; input_position = position; input_last = position == 511;
    input_metadata = job_descriptor; input_data = 36'(position * 773 + 11);
  endtask
  task automatic complete_job;
    boot();
    for (integer position = 0; position < 512; position = position + 1) begin
      word(position);
      #0.1;
      if (input_complete || fault_now || !certified_input_beat ||
          certified_input_complete !== (position == 511))
        $fatal(1, "INPUT_RETIREMENT_DELIVERY_FAILURE position=%0d", position);
      @(negedge clk);
    end
    input_valid = 0;
    #0.1;
    if (!input_complete || delivered != 512 || completion_pulses != 1 || protocol_fault)
      $fatal(1, "INPUT_RETIREMENT_INCOMPLETE_JOB");
  endtask

  initial begin
    // The simplification MUST NOT apply before registered input completion.
    // Each early witness is a real malformed/demanded beat, not a state deposit.
    for (integer cause = 0; cause < (CHECK_IDENTITY ? 5 : 4); cause = cause + 1) begin
      boot(); word(0); @(negedge clk); word(1);
      case (cause)
        0: input_position = 9'd3;
        1: input_last = 1;
        2: input_valid = 0;
        3: input_enable = 0;
        4: input_metadata = ~job_descriptor;
      endcase
      #0.1;
      if (input_complete || !fault_now || retired_fault || certified_input_beat)
        $fatal(1, "INPUT_RETIREMENT_PREMISE_WITNESS_MISSING cause=%0d", cause);
      premature_witnesses = premature_witnesses + 1;
      @(negedge clk);
      if (!protocol_fault || input_complete || delivered != 1)
        $fatal(1, "INPUT_RETIREMENT_EARLY_FAULT_NOT_RETAINED");
    end

    complete_job();
    // 32 pin combinations x 512 possible ordinals x two identities, all after
    // actual completion. Legal completed idle is followed by sticky duplicate
    // start faults. All ordinary presented metadata is immaterial in this phase.
    for (integer flags = 0; flags < 32; flags = flags + 1) begin
      for (integer position = 0; position < 512; position = position + 1) begin
        for (integer identity = 0; identity < 2; identity = identity + 1) begin
          {job_start, input_last, core_input_tready, input_valid, input_enable} = flags[4:0];
          input_position = position;
          input_metadata = identity ? ~job_descriptor : job_descriptor;
          input_data = 36'(post_rows * 17);
          #0.1;
          if (!input_complete || fault_now !== retired_fault || certified_input_beat ||
              certified_input_complete || input_ready || input_transport_ready || core_input_tvalid)
            $fatal(1, "INPUT_RETIREMENT_PREDICATE_MISMATCH flags=%0d ordinal=%0d identity=%0d", flags, position, identity);
          expected_sticky = expected_sticky || job_start;
          post_rows = post_rows + 1;
          if (job_start) duplicate_rows = duplicate_rows + 1;
          @(negedge clk);
          if (fault_reasons !== {expected_sticky, 2'b00} ||
              delivered != 512 || completion_pulses != 1)
            $fatal(1, "INPUT_RETIREMENT_STICKY_OR_COUNT_MISMATCH");
        end
      end
    end
    // A common reset purges completion and sticky fault; a fresh input job
    // again performs every check and generates exactly one completion pulse.
    complete_job();
    if (post_rows != 32768 || duplicate_rows != 16384 ||
        premature_witnesses != (CHECK_IDENTITY ? 5 : 4))
      $fatal(1, "INPUT_RETIREMENT_COVERAGE_MISSING");
    $display("INPUT_RETIREMENT_PASS identity=%0d rows=32768 duplicate_rows=16384 premature_witnesses=%0d reset_recovery=1 no_internal_deposits=1 no_publication_or_timing_claim=1",
             CHECK_IDENTITY, premature_witnesses);
    $finish;
  end
  initial begin #1000000; $fatal(1, "INPUT_RETIREMENT_WATCHDOG"); end
endmodule
