"""Bench-only, bounded live drain witness; no actual preparation or execution.

The original v1 await_results task/calls and result parser remain byte-identical.
This transformer is an offline review artifact, not an admitted vendor bundle.
"""
import hashlib

ORIGINAL_TOP_SHA = "d9080893669c55c93108bc4175eefe23b6c3d90399b1d43cb21cf48bc85699e7"
TASK = '''  // Observe the same live pre-edge drain required by the complete CSV gate.
  // await_results may first see WAIT_BANK after NBA; do not reset before a
  // following live trace sample. The original 5215-clock service bound applies.
  task automatic checked_profile_drain(input integer count);
    reg observed;
    integer drain_cycle, service_cycles;
    observed = 0;
    while (!observed) begin
      @(posedge fft_clk);
      if (dut.fast_running !== 1'b1 || dut.fast_fault !== 1'b0 || fault !== 1'b0)
        $fatal(1, "CHECKED_PROFILE_DRAIN_RESET_OR_FAULT");
      drain_cycle = fast_cycle;
      service_cycles = drain_cycle - previous_admit;
      if (previous_admit < 0 || service_cycles <= 0 || service_cycles > 5215)
        $fatal(1, "CHECKED_PROFILE_DRAIN_SERVICE_BOUND");
      observed = published === count && dut.state === dut.WAIT_BANK &&
        dut.next_inverse === 1'b0 && dut.result_busy === 1'b0 &&
        dut.output_bank_ready === 1'b1;
      #0.001;
      if (dut.fast_running !== 1'b1 || dut.fast_fault !== 1'b0 || fault !== 1'b0)
        $fatal(1, "CHECKED_PROFILE_DRAIN_RESET_OR_FAULT");
    end
    $display("CHECKED_PROFILE_DRAIN_WITNESS profile=%0d count=%0d forward=%0d drain=%0d service=%0d",
      profile, count, previous_admit, drain_cycle, service_cycles);
  endtask
'''
CHANGES = (
    ("  task automatic await_fault;\n", TASK + "  task automatic await_fault;\n"),
    ("    await_results(QUICK_MUTATION ? 0 : 32);\n",
     "    await_results(QUICK_MUTATION ? 0 : 32);\n    if (!QUICK_MUTATION) checked_profile_drain(32);\n"),
    ("    await_results(QUICK_MUTATION ? 0 : 6); profile = 0;\n",
     "    await_results(QUICK_MUTATION ? 0 : 6);\n    if (!QUICK_MUTATION) checked_profile_drain(6);\n    profile = 0;\n"),
)


def transform(body, inverse=False):
    if not inverse and hashlib.sha256(body.encode()).hexdigest() != ORIGINAL_TOP_SHA:
        raise ValueError("requires complete original checked-product v1 bench")
    for old, new in reversed(CHANGES) if inverse else CHANGES:
        source, target = (new, old) if inverse else (old, new)
        if body.count(source) != 1:
            raise ValueError("nonunique drain-witness literal anchor")
        body = body.replace(source, target, 1)
    if inverse and hashlib.sha256(body.encode()).hexdigest() != ORIGINAL_TOP_SHA:
        raise ValueError("drain inverse does not restore whole original v1 bench")
    return body
