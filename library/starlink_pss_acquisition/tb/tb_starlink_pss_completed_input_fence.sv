// Paired live input checker + default/opt-in result guards. Synthetic control
// events exercise boundaries that the actual FFT does not naturally overlap.
`timescale 1ns/1ps
module tb_starlink_pss_completed_input_fence;
  parameter integer MUTATE_DUPLICATE = 0;
  reg clk = 0, resetn = 0;
  always #2.5 clk = !clk;
  reg job_valid = 0, job_start = 0, input_enable = 0;
  reg input_valid = 0, input_last = 0, core_ready = 1;
  reg [8:0] input_position = 0;
  reg [69:0] input_metadata = 70'h123456789abcdef012;
  wire [69:0] descriptor = 70'h123456789abcdef012;
  wire beat, complete_pulse, input_complete, input_fault_now, input_fault, duplicate_fault;
  reg output_reserved = 1, mailbox_ready = 1, mailbox_fault = 0, other_fault = 0;
  reg frame = 0, raw_valid = 0, raw_last = 0, status_valid = 0;
  reg [23:0] raw_user = 0;
  reg [47:0] raw_data = 0;
  reg [7:0] status_data = 8'd3;
  wire full_external = input_fault_now || input_fault || other_fault;
  wire narrow_external = (MUTATE_DUPLICATE ? 1'b0 : duplicate_fault) || input_fault || other_fault;
  wire old_fence = input_complete && !input_fault && !input_fault_now;
  wire new_fence = input_complete && !input_fault && !duplicate_fault;
  wire old_ready, new_ready, old_valid, new_valid, old_private, new_private;
  wire old_commit_valid, new_commit_valid, old_busy, new_busy, old_commit, new_commit;
  wire old_fault, new_fault;
  wire [7:0] old_reasons, new_reasons;
  integer comparisons = 0, return_checks = 0, healthy = 0, rejected = 0, phase, kind, p;
  integer simultaneous_edges = 0, commits = 0;
  starlink_pss_realtime_input_guard input_guard (
    .clk(clk), .resetn(resetn), .job_start(job_start), .job_descriptor(descriptor),
    .input_enable(input_enable), .input_valid(input_valid), .input_ready(), .input_transport_ready(),
    .input_data(36'd0), .input_position(input_position), .input_last(input_last),
    .input_metadata(input_metadata), .core_input_tdata(), .core_input_tvalid(),
    .core_input_tready(core_ready), .core_input_tlast(), .certified_input_beat(beat),
    .certified_input_complete(complete_pulse), .input_complete(input_complete),
    .fault_now(input_fault_now), .duplicate_start_fault_now(duplicate_fault),
    .protocol_fault(input_fault), .fault_reasons()
  );
`define INPUTS \
    .clk(clk), .resetn(resetn), .job_valid(job_valid), .job_descriptor(descriptor), \
    .input_bank_reserved(1'b1), .output_bank_reserved(output_reserved), \
    .certified_input_beat(beat), .certified_input_complete(complete_pulse), \
    .external_fault_now(full_external), .phase_input_fault_now(1'bz), \
    .completed_input_certified(input_complete), .completed_input_fault_now(narrow_external), \
    .core_event_frame_started(frame), .core_output_tdata(raw_data), .core_output_tuser(raw_user), \
    .core_output_tvalid(raw_valid), .core_output_tlast(raw_last), \
    .core_status_tdata(status_data), .core_status_tvalid(status_valid), \
    .mailbox_input_ready(mailbox_ready), .mailbox_input_fault(mailbox_fault), \
    .mailbox_input_data(), .mailbox_input_position(), .mailbox_input_last(), .mailbox_input_metadata()
  starlink_pss_realtime_result_guard original (
    `INPUTS, .final_fence_certified(old_fence), .job_ready(old_ready),
    .mailbox_input_valid(old_valid), .mailbox_private_valid(old_private),
    .mailbox_commit_valid(old_commit_valid), .busy(old_busy), .commit_pulse(old_commit),
    .protocol_fault(old_fault), .fault_reasons(old_reasons)
  );
  starlink_pss_realtime_result_guard #(.USE_COMPLETED_INPUT_FAULT(1)) candidate (
    `INPUTS, .final_fence_certified(new_fence), .job_ready(new_ready),
    .mailbox_input_valid(new_valid), .mailbox_private_valid(new_private),
    .mailbox_commit_valid(new_commit_valid), .busy(new_busy), .commit_pulse(new_commit),
    .protocol_fault(new_fault), .fault_reasons(new_reasons)
  );
`undef INPUTS
  task automatic compare;
    if (resetn) begin
      comparisons = comparisons + 1;
      if ({new_ready, new_valid, new_private, new_commit_valid, new_busy, new_commit, new_fault, new_reasons} !==
          {old_ready, old_valid, old_private, old_commit_valid, old_busy, old_commit, old_fault, old_reasons})
        $fatal(1, "COMPLETED_INPUT_EQ_MISMATCH phase=%0d kind=%0d time=%0t", phase, kind, $time);
      if (old_fence !== new_fence) $fatal(1, "old/new final fence mismatch");
      if (candidate.return_valid) begin
        return_checks = return_checks + 1;
        if (!input_complete || input_guard.slot_open || beat || complete_pulse ||
            candidate.input_count != 512 || !candidate.input_complete_seen ||
            !candidate.frame_seen || !candidate.exponent_seen ||
            candidate.completed_return_fault_now !== candidate.fault_now ||
            candidate.completed_final_fault_now !== candidate.final_fault_now)
          $fatal(1, "COMPLETED_INPUT_PHASE_MISMATCH phase=%0d kind=%0d", phase, kind);
      end
    end
  endtask
  always @(posedge clk) begin
    compare();
    if (resetn && complete_pulse && raw_valid) simultaneous_edges = simultaneous_edges + 1;
    if (resetn && new_commit_valid && mailbox_ready) commits = commits + 1;
    #0.001; compare();
  end
  always @(negedge clk) begin #0.1; compare(); end
  task automatic advance;
    @(posedge clk); #0.01; @(negedge clk); #0.01;
  endtask
  task automatic begin_job;
    @(negedge clk); resetn = 0; job_valid = 0; job_start = 0; input_enable = 0;
    input_valid = 0; input_last = 0; input_position = 0; input_metadata = descriptor;
    core_ready = 1; output_reserved = 1; mailbox_ready = 1; mailbox_fault = 0; other_fault = 0;
    frame = 0; raw_valid = 0; raw_last = 0; raw_user = 0; status_valid = 0; status_data = 3;
    advance(); advance(); resetn = 1; #0.1;
    if (!new_ready || !old_ready) $fatal(1, "admission unavailable after reset");
    job_valid = 1; advance(); job_valid = 0; job_start = 1;
    advance(); job_start = 0; input_enable = 1;
  endtask
  task automatic set_input(input integer index);
    input_valid = 1; input_position = index; input_last = index == 511;
    input_metadata = descriptor; frame = index == 0;
  endtask
  task automatic inputs(input integer count);
    integer index;
    for (index = 0; index < count; index = index + 1) begin set_input(index); advance(); end
    input_valid = 0; frame = 0;
  endtask
  task automatic set_output(input integer index);
    raw_valid = 1; raw_last = index == 511;
    raw_user = {3'b0, 5'd3, 7'd0, 9'(index)}; raw_data = index;
  endtask
  task automatic outputs(input bit include_status);
    integer index;
    for (index = 0; index < 512; index = index + 1) begin
      set_output(index); status_valid = include_status && index == 0; advance();
    end
    raw_valid = 0; status_valid = 0;
  endtask
  task automatic expect_fault;
    #0.2; compare();
    if (new_valid || new_commit_valid) $fatal(1, "fault missed immediate return veto");
    advance();
    if (!new_fault || !old_fault || new_reasons !== old_reasons)
      $fatal(1, "fault/reasons not retained on fault edge");
    job_start = 0; other_fault = 0; mailbox_fault = 0; raw_valid = 0; frame = 0; status_valid = 0;
    repeat (3) advance();
    if (new_valid || new_ready || new_commit_valid) $fatal(1, "quarantine resumed silently");
    rejected = rejected + 1;
  endtask
  initial begin
    // Legal final input/first output overlap: certificate registers together
    // with the first visible return; no extra bubble or delayed veto is allowed.
    phase = 0; kind = 0; begin_job(); inputs(511); set_input(511); set_output(0);
    advance(); input_valid = 0; frame = 0; raw_valid = 0; #0.2;
    if (!input_complete || !new_valid) $fatal(1, "legal simultaneous terminal input/output rejected");
    for (p = 1; p < 512; p = p + 1) begin
      set_output(p); status_valid = p == 7; advance();
    end
    raw_valid = 0; status_valid = 0; advance(); advance(); healthy = healthy + 1;
    // Prefetched next-block metadata after completion is not an input beat.
    phase = 1; begin_job(); inputs(512); set_output(0); advance(); raw_valid = 0;
    input_valid = 1; input_metadata = ~descriptor; input_position = 73; input_last = 1;
    advance();
    if (new_fault || input_fault_now || beat) $fatal(1, "closed input inspected prefetched next bank");
    input_valid = 0; healthy = healthy + 1;
    // Nonfinal live checks, including first matching status (legal) separately.
    phase = 2;
    for (kind = 0; kind < 12; kind = kind + 1) begin
      begin_job(); inputs(512); set_output(0); advance(); raw_valid = 0;
      case (kind)
        0: job_start = 1;
        1: other_fault = 1;
        2: mailbox_fault = 1;
        3: output_reserved = 0;
        4: mailbox_ready = 0;
        5: frame = 1;
        6: begin status_valid = 1; status_data = 8'h83; end
        7: begin status_valid = 1; status_data = 4; end
        8: begin set_output(9); end
        9: begin set_output(1); raw_last = 1; end
        10: begin set_output(1); raw_user[20:16] = 4; end
        11: begin set_output(1); raw_user[15] = 1; end
      endcase
      expect_fault();
    end
    phase = 3; kind = 0; begin_job(); inputs(512); set_output(0); advance(); raw_valid = 0;
    status_valid = 1; status_data = 3; #0.2;
    if (!new_valid || candidate.completed_return_fault_now) $fatal(1, "first good nonfinal status rejected");
    advance(); status_valid = 0; healthy = healthy + 1;
    // Active metadata/ordinal/TLAST checks, including malformed presented input
    // while the core stalls, and corruption on final-input/first-output edge.
    phase = 4;
    for (kind = 0; kind < 6; kind = kind + 1) begin
      begin_job(); inputs(kind < 3 ? 64 : 511); set_input(kind < 3 ? 64 : 511);
      if (kind % 3 == 0) input_metadata = ~descriptor;
      if (kind % 3 == 1) input_position = 12;
      if (kind % 3 == 2) input_last = !input_last;
      if (kind == 0) core_ready = 0;
      if (kind >= 3) set_output(0);
      #0.2;
      if (!input_fault_now || beat || complete_pulse) $fatal(1, "active corrupt input certified");
      expect_fault();
      if (input_complete || new_private) $fatal(1, "malformed final edge created held return/certificate");
    end
    // Duplicate starts in unqualified final, qualified final, and ACK. Full
    // original reason accounting and the publication-edge veto remain exact.
    phase = 5;
    for (kind = 0; kind < 3; kind = kind + 1) begin
      begin_job(); inputs(512); outputs(kind != 0); mailbox_ready = 0;
      if (kind == 0 && candidate.final_qualified) $fatal(1, "unqualified final setup failed");
      if (kind != 0 && !candidate.final_qualified) $fatal(1, "qualified final setup failed");
      if (kind == 2) begin mailbox_ready = 1; advance(); mailbox_ready = 0;
        if (!candidate.awaiting_ack) $fatal(1, "ACK setup failed"); end
      job_start = 1; expect_fault();
    end
    // Qualified final rejects every currently new raw/status/frame/fault event,
    // while an unqualified final may legally acquire its first delayed status.
    phase = 6;
    for (kind = 0; kind < 5; kind = kind + 1) begin
      begin_job(); inputs(512); outputs(1); mailbox_ready = 0;
      case (kind)
        0: status_valid = 1;
        1: frame = 1;
        2: set_output(511);
        3: mailbox_fault = 1;
        4: other_fault = 1;
      endcase
      expect_fault();
    end
    phase = 7; kind = 0; begin_job(); inputs(512); outputs(0); mailbox_ready = 0;
    repeat (3) advance();
    status_valid = 1; advance(); status_valid = 0; #0.2;
    if (!new_commit_valid || new_fault) $fatal(1, "delayed good final status did not qualify");
    mailbox_ready = 1; advance(); advance(); healthy = healthy + 1;
    if (!simultaneous_edges || !return_checks || commits != 3)
      $fatal(1, "missing completed-input edge/commit witnesses commits=%0d", commits);
    $display("COMPLETED_INPUT_FENCE_PASS healthy=%0d rejected=%0d simultaneous_edges=%0d comparisons=%0d return_checks=%0d commits=%0d",
      healthy, rejected, simultaneous_edges, comparisons, return_checks, commits);
    $finish;
  end
  initial begin #1000000; $fatal(1, "completed-input test watchdog"); end
endmodule
