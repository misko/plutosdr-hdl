# Development and terminal failures — retained, not accepted as passes

1. The first paired-control test invocation reported2failures before its
   mutation witness: `legal simultaneous terminal input/output rejected` at
   time2585010. It checked `new_valid` immediately after the capture while the
   old raw_valid/index0 stimulus was still present; the next-cycle checker
   correctly saw that still-present raw word as a duplicate. The test now
   deasserts raw_valid and waits0.2ns before checking. RTL and gates did not
   change. The transient pytest executable was cleaned by pytest before an
   archival replay attempt; this is a summarized original failure, not a claim
   that its raw transcript/binary is archived. The final executable/logs use
   an explicit task-specific basetemp and remain in the run directory.
2. The first broad regression invocation reported13failed/50passed/6skipped.
   Twelve elaborations of the existing wildcard-connected final-veto bench
   lacked identifiers for new opt-in input ports. The fix adds explicit Z
   signals, verifying that default mode ignores them. One structural proof
   expected the input cursor to be the only source delta; it now checks the
   exact newly exported duplicate-start alias before performing its original
   entire-body comparison against the unchanged golden. No original checker
   or reason is omitted. This is a summarized original failure, not a complete
   archived pytest transcript. Final retained run:74passed/6explicit skips.
3. The deliberate narrow duplicate-start veto mutation failed on the intended
   immediate nonfinal control-equivalence witness. Its raw failure is
   `unit/duplicate-mutation.log`. The original actual-FFT join-ready mutation
   failed on its exact held-final acceptance witness; raw output and mutated
   source are in `join-mutation/`. Both are expected negative-control outcomes.
4. The only implemented175MHz route failed setup with−3.855ns slack, worse than
   baseline−2.557ns. All raw synthesis/route logs, timing/utilization/CDC/constraint
   reports and checkpoint hashes are retained. There was no second RTL or
   physical iteration. No route failure was renamed a pass or waived.
