# Bounded future shared-realtime FFT candidate

Status: design/test contract only. This architecture is **not implemented or
qualified**. It does not change the frozen nonrealtime receiver, production IP,
clock constraints, or deployment eligibility. The experimental firmware remains
do-not-merge. Realtime is a candidate if the current nonrealtime design still
fails; it is not an assumed solution to whole-chip timing or packing.

## Evidence and its limits

The standalone observer sources were committed in HDL `718c32e0`. Its retained
run is `build/realtime-xfft-protocol-numeric-v1/`, with console output in
`build/realtime-xfft-protocol-numeric-v1-console.log`. The run's `scope.txt`
correctly records base HEAD `6b58ea92`: the new diagnostic files were uncommitted
when that snapshot was created. Source hashes, copied vectors, generated
generics, and every-cycle CSV are retained with the run.

Measured at a 5 ns simulation clock using the actual generated realtime XFFT:

- Seven healthy jobs produced 3,584 exact complex words, comparing both full
  18-bit components, per-word exponent/index/TLAST/padding, and independent
  status exponent. Three direction changes without reset passed.
- Status arrived **two clocks after the first data** in all eight observed jobs.
  That 10 ns observation is not a universal upper bound on status latency.
- With 64 active-demand gaps after 128 delivered words, all 512 output values
  were wrong. The frame still had correct metadata/exponents, one frame event,
  one status, and no TLAST errors. Input-halt first appeared two clocks after
  the first gap, and was asserted for 64 clocks.
- No halt was observed during the healthy reset/config/idle/input/compute/
  output/drain phases exercised. This does not prove a universal event-latency
  bound or justify treating every input-halt indication as fatal in every phase.
- Explicit reset followed by a healthy replay recovered. The diagnostic did
  not exercise a production adapter, mailbox service, sustained acquisition,
  receiver implementation, or hardware.

The generated configuration retains 512 points, radix-4 burst, BFP18, 16-bit
coefficients, convergent rounding, natural ordering, and the frozen scaling
contract. All 34 generated generics match the preceding isolated realtime
physical probe. Agreement on these fixtures is not an all-input equivalence
proof. The current nonrealtime whole-chip report still contains independent
vendor BFP-range and CE-prediction failures (-0.905 ns and -0.678 ns in
`counter-retirement-v1/spread-high-v2`); removing nonrealtime CE prediction does
not eliminate the BFP-range timing problem by definition.

## Smallest storage architecture to qualify

Reuse the existing input/output block mailboxes and the existing final-word
return register. Do not add another 512-word payload buffer as the first step.
Use a shared-realtime-specific private-result interface; do not silently weaken
the existing adapter's public `output_valid` contract or dedicated-core default.

1. **Reserve before starting.** Require a fully committed 512-word input bank,
   its prefetched first word, a free output bank, an empty return register, and
   a healthy common reset epoch. The service exclusively owns the output bank
   for the entire job. Keep the descriptor/direction/start index stable until
   final commit or explicit abort/reset. No competing writer may claim that bank.
2. **Reset/configure one job.** Initially retain per-job reset and direction
   configuration. The no-reset direction experiment is a later optimization,
   not a prerequisite. Preserve the generated core's reset requirements and
   both-clock reset-release/flush behavior.
3. **Deliver every active input demand.** The committed input bank must provide
   each of the 512 ordered words, with original framing/identity checks, whenever
   the core requires it. The synchronous read/prefetch path must sustain one
   word per FFT clock. There is no host, upstream FIFO, or output-ready dependency
   after the first input word starts the job. Release the input bank only after
   all required input words have actually been delivered, or purge it on reset.
4. **Write provisional output privately.** Account for every emitted core beat;
   realtime has no output/status backpressure ports. Validate raw ordinal,
   XK_INDEX, TLAST, TUSER padding, frame identity/lifecycle, and constant TUSER
   exponent. Latch the first output exponent as provisional. Stream positions
   0 through 510 into the reserved output mailbox through the existing return
   register at one word per clock. These writes are not public results.
5. **Hold the final word.** Keep structurally checked position 511 in the existing
   return register. Do not offer that word to the mailbox until all independent
   status, count, event, and fault checks have completed. Keep the core/checker
   and descriptor alive during this drain phase.
6. **Commit once, then retire.** A fully qualified final-word acceptance toggles
   the mailbox's publication request. The slow side may then read the complete
   block, and acknowledges only after consuming its last word. Do not start a
   new job until its required bank reservations can be obtained again.

The storage property comes from `starlink_pss_block_mailbox.v`: the request
toggle changes only on a framing-valid final write; the reader cannot begin a
new block until that toggle crosses domains. The existing service already holds
a final return word through a completion fence.

**Important boundary:** writing all 512 words into the *unchanged* mailbox would
already publish the block. Holding only the downstream acknowledgment is too
late. The minimal proposal is **511 private RAM writes plus one held final word**.
Writing all 512 privately would require a separate mailbox commit API and its
own ownership/CDC proof, which is a larger alternative.

## Independent status and full-block qualification

Capture status independently of output flow. Require exactly one status for the
job; missing, orphan, duplicate, padded, or mismatched status must not commit.
Compare whichever exponent arrives second against the retained first exponent:

- If status precedes data, compare the first and every subsequent TUSER exponent
  against that status.
- If data precedes status, retain the first TUSER exponent and require every
  later word to match it. Compare independent status against that retained value
  when it arrives.

This preserves the full-block condition by transitivity:

```text
every word's exponent == first word's exponent
exactly one independent status exponent == first word's exponent
therefore every word's exponent == independent status exponent
```

No per-word exponent RAM is needed. Status may arrive more than two clocks late,
even after the final output word, without overflowing early-data storage: the
partial bank and final register remain private. A finite, explicitly qualified
watchdog must fault missing/overdue status or an incomplete job. Its deadline is
not inferred from the observed two-clock delay, and safety must not depend on
silently waiting forever. Status flags/exponents and job identity remain retained
until commit/reset, not cleared merely because output word 511 appeared.

At commit, require all of the following:

- Exactly 512 qualified input deliveries and 512 accounted output words;
  no missing, repeated, extra, misordered, or malformed beat.
- Every per-word structural check passed; constant output exponent matched
  exactly one independently captured status.
- Required frame-event and input-starvation checks completed in the same job
  epoch; no latched fault, watchdog expiry, reservation loss, or reset/flush.
- The final staged word, descriptor, and bank ownership remain intact.
- **No same-cycle fatal condition.** A fault, duplicate/bad status, or extra raw
  output on the commit edge must directly veto final-word acceptance. A sticky
  flag which changes only on the following clock is insufficient.

## Input starvation, event latency, and recovery

Output framing/exponent checks cannot detect the demonstrated realtime input
starvation corruption. The candidate needs two separate protections:

1. A local immediate delivery-contract check, armed only after the first input
   handshake and before all 512 required inputs are delivered: an active core
   demand without the required valid, correctly framed word aborts the job.
   It must not classify ordinary pre-first-word or post-complete idle as missing
   data. Malformed input still faults through the original input checker.
2. A separately qualified vendor-event policy. An input-halt event may trail the
   offending input cycle, so testing only the *current* input-loading state is
   insufficient. A conservative candidate retains its started-job guard through
   compute/output/status-wait/final drain, with reset establishing the event epoch.
   Idle/config/between-job events require vendor-backed lifecycle classification;
   the current trace alone does not authorize a blanket fatal OR or a universal
   two-cycle tail mask.

Before qualification, establish a vendor-backed and experimentally checked
observation bound, or an earlier local detector, for every corruption mechanism
that could otherwise report after commit. A finite fence cannot revoke an
already published block upon an arbitrarily late event. Preserve current-cycle
commit vetoes and explicitly test delayed events across phase boundaries.

Any abort makes the partial RAM contents and held final word unreachable, blocks
reuse, and enters sticky quarantine. Common reset must purge request/acknowledge
state, prefetched input, pending status/exponent, counts, the final register, and
all job-event guards across both clock domains. Clearing a local flag without
resetting retained transactions is not recovery. Do not silently retry or reuse
a poisoned bank. No result from a reset/aborted epoch may appear after re-enable.

## Capacity and conceptual cost

Keep the arithmetic, coefficients, 512-point transform, 65-sample overlap,
**447-sample stride**, absolute timestamps, forward/inverse pairing, scores,
phase-map ordering, and downstream coarse/fine contracts unchanged.

At the canonical 15 MS/s detector input, a new block arrives every
`447 / 15e6 = 29.80 us`. Sustained forward-plus-inverse service, including CDC,
bank return, required status handling, and bounded downstream stalls, must meet
that cadence without a growing queue or retention-age drift. The current
nonrealtime saturated replay measured **29.74 us** per pair: only 60 ns margin.
Standalone realtime latency is not evidence of integrated capacity improvement.

Whole-bank reservation prevents output backpressure within a started job. Any
unexpected non-final return-stage stall or extra core beat is an overrun fault,
not permission to hide a stall from the realtime core. A late status may safely
hold a private completed job, but acceptable *healthy* lateness and timeout
behavior must also satisfy the sustained service budget.

Storage accounting, not a synthesis estimate:

- Reuse the existing 512 x 36-bit output RAM and existing approximately 52-bit
  return slot (36 data + 9 position + 5 exponent + last + valid), plus the held
  descriptor and existing exponent/status state. No additional 512-word RAM
  or DSP is inherently required by this proposal.
- New control may need a few job-completion/event flags and a W-bit watchdog.
  A rough design allowance is 4–10 control FFs plus W timer FFs, and small
  comparisons/gating; actual reuse, LUT count, control sets, packing, and timing
  are unmeasured. Do not book those figures as a resource saving.
- An additional two raw-word slots would cost about 104 payload/control FFs
  before mux/occupancy logic. A two/three-word early-data buffer cannot be called
  sufficient merely because the observed status delay was two clocks. Without
  a proven delay bound it must fail closed on overflow or use reserved whole-
  block storage. It is a fallback, not the minimal candidate described here.

## Differentiating tests and promotion gates

1. **Synthetic-core transaction proof.** Drive status before first data, with
   first data, at +2, +3, substantially later, with the last word, after the last
   word, and never. Test matching/mismatching/padded/duplicate/orphan status.
   Delay beyond a small FIFO's capacity to distinguish whole-bank safety from
   an accidental two-cycle assumption. Verify zero publication before commit.
2. **Reservation and ownership.** Hold the previous output bank busy; withhold
   input commit; stall the slow reader; vary clock phase. No job may start without
   both complete reservations. Once started, every demanded input and emitted
   output is accounted for without host dependence. Verify ACK and descriptor
   stability through final hold, abort, and reuse.
3. **Adversarial beat/final fence.** Corrupt first/middle/last index, TLAST, padding,
   exponent or input identity. Omit/duplicate a beat and inject a 513th output.
   Inject every relevant fault on final capture, status acceptance, completion
   registration, and the exact commit edge. No request toggle, completed result,
   or partial map may escape a failed job.
4. **Starvation/event qualification.** Force active-demand gaps of different
   lengths at early, middle and final input positions, with both isolated and
   bursty gaps. Sweep event delay across input/compute/output/drain boundaries;
   compare local delivery detection, vendor event timing, and actual numerical
   corruption. Also observe long legal idle/config/reset gaps. Do not turn a
   finite trace into an undocumented universal phase/latency guarantee.
5. **Reset cleanup.** Independently reset each clock side during input, private
   output, pending status, final hold, commit boundary and slow drain. Check
   that prefetched words, pending status, and stale toggles cannot enter the
   next epoch; require explicit successful recovery.
6. **Actual generated-core numerics.** Replay frozen forward/product/inverse
   words and exponents, then exact scores/maps and partial-map fault handling.
   Retain full 36-bit comparisons, per-word metadata checks, independent status,
   and exact input sample tags. Start with per-job reset; no-reset operation is
   a separate later qualification.
7. **Sustained capacity and physical gates.** Run saturated service and bounded
   64-block bursty/stalled tests, followed by at least a 120 ms current-source
   acquisition run with explicit queue/retention-age bounds. A 64-block pass is
   not 120 ms evidence. Then require whole-chip packing, all 100/200 MHz setup/
   hold constraints, vendor-internal timing, and CDC/methodology checks. Do not
   relax clocks or replace integrated evidence with standalone-core timing.

Only after these gates pass should an explicitly selected experimental shared-
realtime implementation become a deployment candidate. No radio flash, runtime
switch, or production-default change is authorized by this document.
