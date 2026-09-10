// Full old-guard reference, every identity bit, live/stalled and terminal slots.
`timescale 1ns/1ps
module tb_starlink_pss_balanced_identity;
  parameter integer BALANCED_MODE = 1;
  reg clk = 0, resetn = 0, job_start = 0, input_enable = 0;
  reg input_valid = 0, input_last = 0, core_ready = 1;
  reg [69:0] job_descriptor = 70'h123456789abcdef012, input_metadata = 0;
  reg [35:0] input_data = 0;
  reg [8:0] input_position = 0;
  wire [63:0] current, golden;
  integer bit_index, slot, ready_case, p, rows = 0, comparisons = 0;
  reg [2:0] expected_reasons;
  always #2.5 clk = !clk;
`define INPUTS \
    .clk(clk), .resetn(resetn), .job_start(job_start), .job_descriptor(job_descriptor), \
    .input_enable(input_enable), .input_valid(input_valid), .input_data(input_data), \
    .input_position(input_position), .input_last(input_last), .input_metadata(input_metadata), \
    .core_input_tready(core_ready)
`define OUTPUTS(bus) \
    .input_ready(bus[0]), .input_transport_ready(bus[1]), .core_input_tvalid(bus[2]), \
    .core_input_tlast(bus[3]), .certified_input_beat(bus[4]), .certified_input_complete(bus[5]), \
    .input_complete(bus[6]), .fault_now(bus[7]), .protocol_fault(bus[8]), \
    .duplicate_start_fault_now(bus[9]), .fault_events_now(bus[12:10]), \
    .fault_reasons(bus[15:13]), .core_input_tdata(bus[63:16])
  starlink_pss_realtime_input_guard #(.BALANCED_IDENTITY_EQ(BALANCED_MODE)) dut (
    `INPUTS, `OUTPUTS(current)
  );
  starlink_pss_input_guard_d99c251e_golden reference_guard (
    `INPUTS, `OUTPUTS(golden)
  );
`undef INPUTS
`undef OUTPUTS
  task automatic compare;
    comparisons = comparisons + 1;
    if (current !== golden)
      $fatal(1, "BALANCED_IDENTITY_MISMATCH bit=%0d slot=%0d ready=%0d candidate=%h golden=%h",
        bit_index, slot, ready_case, current, golden);
  endtask
  always @(posedge clk or negedge clk) begin #0.1; compare(); end
  task automatic begin_job;
    @(negedge clk); resetn = 0; job_start = 0; input_enable = 0; input_valid = 0;
    input_position = 0; input_last = 0; input_metadata = job_descriptor; core_ready = 1;
    repeat (2) @(negedge clk);
    resetn = 1; job_start = 1; @(negedge clk); job_start = 0; input_enable = 1;
  endtask
  task automatic set_word(input integer ordinal);
    input_valid = 1; input_position = ordinal; input_last = ordinal == 511;
    input_metadata = job_descriptor; input_data = ordinal * 31 + 7;
  endtask
  initial begin
    for (bit_index = 0; bit_index < 70; bit_index = bit_index + 1)
    for (slot = 0; slot < 3; slot = slot + 1)
    for (ready_case = 0; ready_case < 2; ready_case = ready_case + 1) begin
      begin_job();
      for (p = 0; p < (slot == 0 ? 0 : slot == 1 ? 37 : 511); p = p + 1) begin
        set_word(p); @(negedge clk);
      end
      set_word(p); core_ready = ready_case;
      input_metadata = job_descriptor ^ (70'b1 << bit_index);
      expected_reasons = p != 0 && ready_case ? 3'b011 : 3'b010;
      #0.2; compare();
      if (!current[7] || current[5:4] != 0 || current[2] || current[12:10] !== expected_reasons)
        $fatal(1, "identity bit escaped immediate certificate/reason veto");
      @(negedge clk); #0.2; compare();
      if (!current[8] || current[15:13] !== expected_reasons || current[6])
        $fatal(1, "identity bit lost sticky reason or completed malformed input");
      input_metadata = job_descriptor; core_ready = 1;
      repeat (3) begin
        @(negedge clk); #0.2; compare();
        if (current[6:4] != 0 || current[2:0] != 0) $fatal(1, "identity quarantine resumed");
      end
      rows = rows + 1;
    end
    begin_job();
    for (p = 0; p < 512; p = p + 1) begin set_word(p); @(negedge clk); end
    input_valid = 0; #0.2; compare();
    if (!current[6] || current[8]) $fatal(1, "identity matrix reset recovery failed");
    if (rows != 420) $fatal(1, "identity bit matrix incomplete");
    $display("BALANCED_IDENTITY_PASS mode=%0d bits=70 rows=420 slots=3 readiness=2 comparisons=%0d exact_current_sticky_certificates=1 reset_recovery=1", BALANCED_MODE, comparisons);
    $finish;
  end
  initial begin #2000000; $fatal(1, "balanced identity watchdog"); end
endmodule
