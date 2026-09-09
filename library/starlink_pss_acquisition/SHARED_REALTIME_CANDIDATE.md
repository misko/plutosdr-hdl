# Bounded future shared-realtime FFT candidate

Status: the synthesizable shared-realtime service and its input/result guards
are implemented and actual-core tested. Full receiver integration, sustained
capacity and physical timing/CDC are **not qualified**. The original
nonrealtime implementation remains the default; realtime must be explicitly
selected and cannot authorize deployment before the remaining gates pass.
The experimental firmware remains do-not-merge. Realtime is a candidate for
the current packing/timing failure, not an assumed whole-chip solution.

## First measured control-cone cut — 2026-09-09

The explicitly integrated `ff4229bb` receiver fits and routes, but final timing
fails at 200 MHz: WNS -3.531 ns, 577 setup endpoints. The 100 MHz domain passes
by only +0.002 ns. The longest path crosses input-position certification,
result-guard validation, and service admission; the private watchdog enable
shares it. A read-only routed audit also finds independent vendor-internal
(-1.932 ns), return-slot (-2.949 ns), publication (-2.590 ns), and output-RAM
control (-3.255 ns) failures. No generated bitstream is qualified for deployment.

The first targeted RTL trial changes only result-guard control factoring:

- Admission already requires `!active`. There, the reservation/slot/watchdog
  errors are false and every input/frame/status/output event is an error.
  Use that exactly equivalent idle predicate for `job_ready`; do not delay
  faults or weaken any idle rejection.
- Update private `age` independently of current-cycle fault aggregation:
  zero while inactive, increment while active. Admission starts at zero and
  every healthy active age/deadline remains identical. Only faulted/inactive
  private state may differ. The immediate watchdog veto stays unchanged.

All output-publication checks, fault reasons, metadata, arithmetic, coefficients,
mailbox/reset ownership, certificate latency, and constraints remain unchanged.
Actual-core service, exact score, reduced-map and bursty 64-block replays pass
for this trial. The immutable `ff4229bb` golden comparison preserves public
controls, fault reasons and valid payloads across 23 healthy / 37 rejected jobs,
12 resets, 12288 idle combinations and six exact watchdog configurations.
This finite differential regression is not universal formal equivalence.
Sustained >=120 ms capacity and fresh physical evidence remain separate gates.
Removing two fanout consumers is not a claim that the remaining failing cones
will meet timing. Preserve the failed baseline and measure the new route.

## Synthesizable persistent service — 2026-09-09

`starlink_pss_shared_realtime_xfft_service.v` now owns admission, configuration
and the final fence in RTL. Both real mailboxes and the result guard retain a
common reset epoch; only the FFT/input checker reset between jobs, after actual
slow output ACK. A prefetched next input survives that per-job reset. Admission
captures the committed descriptor and sends a registered checker token one fast
edge later. A separate two-flop sticky source-fault crossing avoids an
asynchronous slow-domain signal in the fast commit-veto cone.

`build/shared-realtime-service-v3/` passes 26 healthy forward/inverse jobs with
13312 exact full 36-bit raw and published words, descriptor/exponent/framing
checks, six missing-demand faults, three same-final-edge vendor vetoes, malformed
bank metadata at words 10 and 511, and six independent raw-reset cases. Both raw
reset inputs interrupt configuration before handshake and partial input after
128 certified deliveries, with successful fresh-epoch recovery. Reset of a
committed output with a prefetched next bank and a late ACK-drain fault are also
tested. The source-matched v2 pass remains retained; v1 failed a testbench's
premature cross-domain fault assertion, corrected without changing service RTL.

The final fence uses checked completion to exclude the documented input
starvation/framing causes locally, together with independent result checks. It
does not guess a vendor event delay or prove arbitrary future errors impossible.
Vendor/local faults remain direct final-edge vetoes and sticky through ACK drain.
Independent review found no actionable RTL bug in this candidate contract.

The six queued-job latency lane measured a maximum paired-admission interval of
28.46 us, including slow ACK and per-job reset/configuration, versus the required
29.80 us canonical block cadence. Six jobs are not sustained-capacity evidence.
Full score/map replay, current-source >=120 ms capacity and complete receiver
resources/timing/CDC remain separate gates. No radio was accessed or deployed.

## Isolated dependencies — 2026-09-09

`starlink_pss_realtime_input_guard.v` immediately rejects missing demanded
input, malformed ordinal/TLAST and optional descriptor mismatch. It retains the
explicit metadata-independent mailbox retirement cone. One common reset epoch
admits one job; pre-first-word idle and undemanded source pauses during core
waitstates are legal. Withdrawal of source enable cannot disable an already
started job's delivery checker. Its two synthetic tests cover both identity
modes, nine healthy blocks, 48 rejected jobs and exact same-edge certificates.
They are not actual-core or reservation proofs.

`starlink_pss_realtime_result_guard.v` reuses the real output mailbox and one
52-bit return slot. It checks raw output framing and counts, independent status
and provisional exponent, then holds word 511 until all certified premises pass.
Three synthetic clock/phase cases each transport 23 exact 512-word blocks,
reject 37 jobs, exercise 12 independent reset cases and two ACK-gated reuses.
Status delayed 777 clocks after the final word remains private; missing status
and the exact watchdog/commit edge fail closed. This proves the isolated guard
contract, not actual FFT arithmetic, input delivery, capacity or physical CDC.

Compose the two with a registered admission token. A combinational path from
result `job_ready` through input `job_start`/duplicate-start fault back into
result readiness would form a feedback loop. The result guard permits ACK-only
reuse; the input guard deliberately requires a new reset epoch. Initial combined
testing must retain per-job resets and align certificates with actual deliveries.

The expanded actual-generated-core observer in `build/realtime-delivery-sweep-v1/`
is separate from both guards. Its 27 healthy jobs match all 13,824 full 36-bit
complex words. All 21 starved jobs produce 512 wrong words each. Ten gap
geometries, including a missing final input, are exercised in both directions;
20 explicit-reset recoveries pass. Twelve halt cycles occur after the testbench
has left its input phase, so an input-phase-only event mask is insufficient.
Observed status and halt delays remain two clocks on these fixtures, **not a
universal bound**. Extended legal idle produces no halt in the tested jobs.

The input rule and warning about delayed TLAST events are documented in
[AMD PG109, May 4, 2022, pp. 12–13 and 51–53](https://www.amd.com/content/dam/xilinx/support/documents/ip_documentation/xfft/v9_1/pg109-xfft.pdf).
Immediate local checking is intended to detect those input corruption mechanisms
before their possibly delayed vendor indication; the eventual integrated event
policy, reservation ownership and final fence still require qualification.

No integrated actual-core service, sustained paired acquisition, whole-chip
resource saving, timing closure or radio deployment is established by these
dependency tests. The current nonrealtime receiver remains the runtime source.

The subsequent **testbench-coordinated** joint replay in
`build/realtime-guarded-mailbox-v4/` connects the actual core, both guards and both
real mailboxes. Twelve healthy forward/inverse jobs preserve 6144 exact raw and
published complex words, exponents, framing and block descriptors. Six missing-
demand tests at input ordinals 1, 255 and 511 (both directions) immediately
quarantine the result before any private write or publication; each is followed
by a successful reset recovery. Once quarantine starts, remaining input is
withheld too. The core's 3072 resulting wrong words are observed, not accepted.
Final-word holds and delayed/bursty slow reads pass. The final fence remains a
testbench-supplied premise, and all banks/guards reset between these jobs.

The production candidate must instead retain mailbox/result ownership across
per-job input-checker/core resets, preserve a prefetched next input, synchronize
sticky cross-domain faults, and internally establish its final fence from
coverage of the documented input-corruption causes. That cause-based argument
requires correct fixed-size reset/configuration plus actual checked deliveries;
it is not a universal theorem about delayed or spontaneous error indications.
Raw vendor events must remain direct/sticky fault inputs through the job and
ACK drain. Only fast-domain signals can supply a same-cycle fast commit veto.

Both diagnostic runners now validate the explicit terminal bench marker, full
job inventory and absence of fatal/error diagnostics after the simulator closes.
Vivado previously returned zero for an assertion-stopped run. The original
joint v1 failure and the first incompatible verifier attempts remain retained;
guarded v4 and delivery-sweep v3 both pass the corrected Vivado-compatible gate.

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
