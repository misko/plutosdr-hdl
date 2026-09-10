`timescale 1ns/1ps
module tb_starlink_pss_realtime_input_guard #(
  parameter integer CHECK_IDENTITY = 1
);
  reg clk = 0, resetn = 0;
  always #2.5 clk = !clk;
  reg job_start = 0, input_enable = 0, input_valid = 0, input_last = 0;
  reg core_ready = 1;
  reg [69:0] job_descriptor = 70'h123456789abcdef012;
  reg [69:0] admitted_descriptor = 0;
  reg [69:0] input_metadata = 0;
  reg [35:0] input_data = 0;
  reg [8:0] input_position = 0;
  wire ready, transport_ready, core_valid, core_last, beat, complete_pulse;
  wire complete, fault_now, fault;
  wire [47:0] core_data;
  wire [2:0] reasons;
  integer beats = 0, completes = 0, healthy = 0, rejected = 0, p, kind, at;
  starlink_pss_realtime_input_guard #(.CHECK_INPUT_BLOCK_IDENTITY(CHECK_IDENTITY), .BALANCED_IDENTITY_EQ(1)) dut (
    .clk(clk), .resetn(resetn), .job_start(job_start), .job_descriptor(job_descriptor),
    .input_enable(input_enable), .input_valid(input_valid), .input_ready(ready),
    .input_transport_ready(transport_ready), .input_data(input_data),
    .input_position(input_position), .input_last(input_last), .input_metadata(input_metadata),
    .core_input_tdata(core_data), .core_input_tvalid(core_valid),
    .core_input_tready(core_ready), .core_input_tlast(core_last),
    .certified_input_beat(beat), .certified_input_complete(complete_pulse),
    .input_complete(complete), .fault_now(fault_now), .protocol_fault(fault), .fault_reasons(reasons)
  );
  always @(posedge clk) if (resetn) begin
    if (beat) begin
      if (!core_valid || !core_ready || fault_now || fault ||
          core_data !== {6'b0, input_data[35:18], 6'b0, input_data[17:0]} ||
          core_last !== input_last)
        $fatal(1, "invalid certified handshake/payload");
      beats = beats + 1;
    end
    if (complete_pulse) completes = completes + 1;
  end
  task automatic reset_job;
    begin
      @(negedge clk); resetn = 0; input_valid = 0; input_enable = 0; job_start = 0;
      admitted_descriptor = 70'h123456789abcdef012 + healthy + rejected;
      job_descriptor = admitted_descriptor;
      core_ready = 1; input_last = 0; input_position = 0; input_metadata = admitted_descriptor;
      repeat (3) @(negedge clk);
      beats = 0; completes = 0; resetn = 1;
      // Prefetched data before admission and configured-enable are not deliveries.
      input_valid = 1;
      repeat (3) begin
        #0.1; if (ready || transport_ready || core_valid || beat || fault_now || fault)
          $fatal(1, "pre-admission input escaped");
        @(negedge clk);
      end
      job_start = 1; @(negedge clk); job_start = 0; input_valid = 0;
      job_descriptor = ~admitted_descriptor;
      repeat (5) @(negedge clk);
      input_enable = 1;
      repeat (17) begin
        #0.1; if (fault_now || fault || beat) $fatal(1, "legal first-word idle fault");
        @(negedge clk);
      end
    end
  endtask
  task automatic set_word(input integer index);
    begin
      input_position = index; input_last = index == 511; input_valid = 1;
      input_data = {18'(index * 31 + 7), 18'(index * 17 + 3)};
      input_metadata = admitted_descriptor;
    end
  endtask
  task automatic healthy_job(input integer stall_every, input bit change_identity);
    integer j;
    begin
      reset_job();
      for (j = 0; j < 512; j = j + 1) begin
        set_word(j);
        if (change_identity) input_metadata = admitted_descriptor ^ 70'(j + 1);
        if (stall_every && j % stall_every == 0) begin
          core_ready = 0;
          repeat (3) begin
            #0.1; if (fault_now || fault || ready || transport_ready || beat || !core_valid)
              $fatal(1, "legal core waitstate rejected");
            @(negedge clk);
          end
          if (j > 0) begin
            // No active demand: missing source-valid/enable are legal while
            // the core waits, provided both are restored before READY rises.
            input_valid = 0;
            #0.1; if (fault_now || fault || beat || core_valid)
              $fatal(1, "undemanded valid gap was called starvation");
            @(negedge clk); input_valid = 1; input_enable = 0;
            #0.1; if (fault_now || fault || beat || core_valid)
              $fatal(1, "undemanded enable gap was called starvation");
            @(negedge clk); input_enable = 1;
          end
          core_ready = 1;
        end
        #0.1; if (!ready || !transport_ready || !beat || fault_now || fault)
          $fatal(1, "healthy input not certified position=%0d", j);
        @(negedge clk);
      end
      input_valid = 0; input_enable = 0;
      repeat (31) @(negedge clk);
      if (beats != 512 || completes != 1 || !complete || fault || fault_now || core_valid || transport_ready)
        $fatal(1, "healthy counts/post-complete idle mismatch");
      healthy = healthy + 1;
    end
  endtask
  task automatic bad_job(input integer position, input integer mode);
    integer j, prior_beats;
    begin
      reset_job();
      for (j = 0; j < position; j = j + 1) begin
        set_word(j); @(negedge clk);
      end
      set_word(position); prior_beats = beats;
      case (mode)
        0: input_valid = 0;
        1: input_enable = 0;
        2: input_position = position ^ 1;
        3: input_last = !input_last;
        4: input_metadata = admitted_descriptor ^ 70'h1;
        5: begin input_position = position ^ 1; core_ready = 0; end
        6: job_start = 1;
      endcase
      #0.1;
      if (!fault_now || beat || complete_pulse)
        $fatal(1, "bad input not vetoed on same edge pos=%0d mode=%0d", position, mode);
      if (mode == 5 && (!ready || transport_ready))
        $fatal(1, "malformed stalled checker/transport split changed");
      @(negedge clk);
      if (!fault || beats != prior_beats || complete || completes)
        $fatal(1, "bad input not sticky/uncertified");
      input_valid = 1; input_enable = 1; core_ready = 1; job_start = 0;
      repeat (7) begin
        #0.1; if (beat || core_valid || ready || transport_ready) $fatal(1, "fault quarantine leaked");
        @(negedge clk);
      end
      rejected = rejected + 1;
    end
  endtask
  initial begin
    healthy_job(0, 0);
    healthy_job(37, 0);
    if (!CHECK_IDENTITY) healthy_job(17, 1);
    // Midstream source-enable removal cannot disable the delivery checker.
    for (kind = 0; kind < 7; kind = kind + 1)
      if (kind != 4 || CHECK_IDENTITY)
        for (at = 0; at < 3; at = at + 1)
          bad_job(at == 0 ? 1 : (at == 1 ? 255 : 511), kind);
    // First-word malformed framing must not require a previous good word.
    bad_job(0, 2); bad_job(0, 3); bad_job(0, 5);
    if (CHECK_IDENTITY) bad_job(0, 4);
    healthy_job(13, 0);
    // One-reset/one-job discipline also rejects a new start after all inputs.
    job_start = 1;
    #0.1; if (!fault_now) $fatal(1, "duplicate completed-job start accepted");
    @(negedge clk);
    if (!fault || beats != 512 || completes != 1) $fatal(1, "duplicate job quarantine mismatch");
    rejected = rejected + 1;
    healthy_job(11, 0);
    $display("REALTIME_INPUT_GUARD_PASS identity=%0d healthy=%0d rejected=%0d source_demand_checked=1 production_connected=0", CHECK_IDENTITY, healthy, rejected);
    $finish;
  end
  initial begin #1000000; $fatal(1, "input guard test watchdog"); end
endmodule
