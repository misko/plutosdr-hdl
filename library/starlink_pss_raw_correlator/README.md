# Stage-15 exact-PSS raw correlator — DO NOT MERGE TO HDL MAIN

This directory is an isolated Gate-2 development slice on
`codex/starlink-rx-only-do-not-merge`. It now contains the raw arithmetic
reference, the optimized engine, and a composed queued-capture tracking core.
It is not connected to the Pluto block design, AXI, DMA, the diagnostic delay
monitor, or a radio image. It must not be packaged or booted in this state.

## Frozen contract

`starlink_pss_raw_correlator.v` accepts one sequential 66-tap signed
CI16/Q1.15 coefficient bank and exactly 130 signed CI16 samples, each with its
stored raw 64-bit timestamp. A start is accepted only after both exact counts
are present. The engine emits 65 ready/valid tuples in deterministic lag order
`-32..+32`. Each tuple is:

```text
{lag, stored_first_tap_timestamp, C_re, C_im, Ex, Eh, saturation_events}
```

For result index `j`, the coefficient bank is correlated against capture
slots `j..j+65`, and the timestamp is read directly from slot `j`. The engine
computes `sum(x * conj(h))` in ascending tap order. `C_re`, `C_im`, `Ex`, and
`Eh` use signed 48-bit saturation after every complete tap, matching
`starlink-fixed-correlator-v1` exactly.

The datapath has only three multiplication operators. They infer one shared
set of three DSP48E1s and issue one tap per 100 MHz engine clock:

```text
m0 = xi * hi
m1 = xq * hq
m2 = (xi + xq) * (hi - hq)
C_re tap = m0 + m1
C_im tap = m2 - m0 + m1
```

The same multipliers compute the bounded `xi^2 + xq^2` and `hi^2 + hq^2`
prepasses; multiplier 2 receives zero operands during those passes. Operand,
product, and complete-tap registers preserve one-tap-per-clock issue while
separating RAM selection, DSP arithmetic, and after-tap saturation. There is
no NCO and no hidden square multiplier.

With exactly 66 legal CI16 taps, no result can reach a signed-48 rail: every
complete correlation or energy addend has magnitude at most `2^31`, so the
worst legal magnitude is `66 * 2^31 = 141733920768 < 2^47`. The portable
fixture checker executes this bound. The event count is nevertheless part of
the ABI because the oracle declares it. The shared saturating-add primitive has
direct positive-rail, negative-rail, exact-boundary, and repeated-event tests;
the structural checker proves both primitive events feed the three phase
counters and the published sum. All legal 66-tap engine vectors must report
zero events. Fault-injection checks of the later wrapper's unexpected-event
counter remain a wrapper qualification gate; production arithmetic is not
distorted merely to manufacture an unreachable top-level rail event.

After the final result handshake the sample count returns to zero while the
coefficient bank remains loaded, so another 130-sample job can reuse it. A
coefficient clear is idle-only and discards both the bank and any sample
image. These engine-clock controls are intentionally simple inputs for a later
AXI/CDC wrapper; they are not an AXI ABI.

## Independent fixtures

The Icarus testbench runs six complete jobs and checks 390 tuples, plus two
mid-job reset aborts:

- an adversarial protocol job with back-to-back loads, rejected 67th/131st
  beats, premature/busy starts, sample-only clear, ready-held-high and stalled
  outputs, and nonmonotonic/MSB-set/near-wrap raw timestamps;
- zero samples with a nonzero bank;
- a second zero-sample job that reuses the retained bank;
- full-scale signed endpoints;
- an all-lag tie using Q15 ties-to-even-derived values, which also proves
  ascending deterministic order; and
- 65 frozen tuples from a real capture.

The real fixture uses `stream-1` / RX1 from
`cap-20260831T071200-9184cf0ad6cc`, 15 MS/s, first chunk, predicted PSS
first-tap coordinate 1185. Capture slots 1153 through 1282 become the 130
sample image. Raw timestamps start at `480554573351 + 1153`; they are frozen
individually rather than reconstructed in RTL. The bank is the upper-edge
15 MS/s PSS conditioned at `-100000 Hz`, then quantized with the oracle's
ties-to-even Q1.15 rule. Its exact energy is `1073725951`, below the declared
31-bit commit bound.

| Authority | SHA-256 |
|---|---|
| recording manifest | `be6a196eaf0894667b835a73afe3aa83ff3200eadc0349b4a45cc5420f7b6f09` |
| compressed first chunk | `68732179d9e147e0f173677f810e032d5240fc3ba024cb9045fe17dff9f38946` |
| uncompressed first chunk | `fd922ab9913b72e545ff526d99ebe884170170d2c817a6a56384740316d661ae` |
| projected upper-edge complex64 template | `3c4e6e36250c970c2905ae64d177e0d9d40e941702483f15f11cc57e88edaced` |
| conditioned Q15 little-endian bank | `2f6f309f3c7d61304ccaf87169481bd3ff546ee89331d46fdc826c88bc30d31a` |
| `tests/starlink_oracle/fixed.py` | `85286478353c736e266e8ac7b9038c6ff95624e7980d96619ae0a746810f37f9` |

The authority manifest describes this overall recording as `degraded` and
`stream-1` as `partial`. The selected interval is nevertheless inside observed
chunk 0, continuity segment 0, before that stream's first gap. The fixture is
algorithm evidence from radio `10400056f695001322002d0010ad1719f2`; it is not
target-radio evidence.

`tb/real_071200_fixture_provenance.json` freezes every fixture-file digest,
the logical recording URI, geometry, counter origin, oracle schema, and tuple
field order. `tb/generate_real_fixture.py` is the reviewed regeneration and
external-qualification path. Generation now requires explicit manifest and
chunk arguments and machine-checks manifest/session/stream/radio identities,
requested and applied settings, first counter, chunk layout, observed
continuity segment, sizes, and compressed/uncompressed hashes before using any
byte or timestamp. Normal portable tests remain independent of bulk storage.

Two independent checks guard the goldens. The generator/verifier calls the
versioned NumPy oracle. `tb/verify_frozen_fixture.py` uses only Python's
standard library and separately implements direct integer products,
after-tap saturation, timestamp mapping, and tuple ordering.

## Tests and synthesis gate

Run the portable checks from this directory:

```sh
./run_tests.sh
```

To recheck only the frozen files against the NumPy oracle, use the exact
qualification dependency in `qualification-requirements.txt`:

```sh
uv run --isolated --no-project --managed-python --python 3.13.15 \
  --with-requirements qualification-requirements.txt \
  python tb/generate_real_fixture.py --verify-only
```

The provenance qualification is deliberately explicit and writes its JSON
receipt with absent-only semantics. It verifies the authoritative manifest and
chunk, proves that their selected 130 samples equal the frozen fixture, then
runs the NumPy 2.4.6 oracle:

```sh
./run_fixture_qualification.sh \
  /trusted/capture/manifest.json \
  /trusted/capture/radio-10400056f695001322002d0010ad1719f2/iq-000000.ci16.zst \
  /absent/output/real_071200_qualification_receipt.json
```

Regeneration uses the same explicit authorities without `--verify-only` and is
never part of a normal test run.

For the resource/timing gate, source Vivado 2022.2 and run:

```sh
./run_ooc.sh
```

`synthesize_ooc.tcl` fails unless the tool is exactly Vivado 2022.2, the part
is `xc7z010clg400-1`, every default `check_timing` category and every
methodology count is zero, all maximum-delay endpoints are constrained at
100 MHz, post-synthesis setup WNS is nonnegative, and exactly three DSP48E1
primitives remain. The generated utilization, timing, methodology,
check-timing, summary, and DCP evidence is placed under ignored `build/ooc/`.
`run_ooc.sh` retains the complete Vivado transcript and a canonical JSON
manifest under `evidence/`; that manifest hashes all RTL/XDC/Tcl/run/manifest-
writer sources and every report, DCP, summary, and transcript. Its source-status
field is deliberately scoped to exactly those attested source paths, so
separately generated evidence does not make a committed source set appear
dirty.

The current local Vivado 2022.2 OOC result is 838 Slice LUTs (including 220
LUT-memory cells), 650 registers, one RAMB36 tile, and exactly three DSP48E1s.
Post-synthesis setup WNS at 100 MHz is `+1.778 ns`, with zero methodology
violations, zero nonzero timing-coverage categories, zero unconstrained
internal endpoints, and complete input/output delay coverage. This run is
explicitly maximum-delay post-synthesis evidence: hold analysis is `NA` until
implementation. These are isolated synthesis figures, not full-shell route or
hold evidence.

Evidence currently generated before the reviewed source commit is provisional,
not release evidence. Qualification uses a two-commit sequence: commit the
reviewed implementation/test/qualification sources first; rerun the OOC and
manifest/chunk/NumPy qualification commands from that clean source revision;
machine-check their hashes and clean OOC attested-source status; then commit the
retained `evidence/` artifacts separately. Never carry a pre-commit evidence
JSON or its digest forward as the final qualification record.

## Queued-center scheduler milestone

`starlink_pss_candidate_scheduler.v` is an isolated Gate-2 source slice. It is
not connected to AXI, DMA, or a radio image. A project-local, coordinated-reset
asynchronous FIFO crosses one explicit 160-bit command from the future
MMIO/control domain into the accepted-sample domain:

```text
{request_id[31:0], center_index[63:0], center_timestamp[63:0]}
```

With `COMMAND_FIFO_ADDRESS_WIDTH=3`, the FIFO deliberately leaves one slot
empty and therefore provides seven usable queued commands. Its payload memory
is block RAM, its Gray pointers cross through two marked synchronizer stages,
and its destination word is registered and held stable until the scheduler
requests another prefetch. Each MMIO submission is a one-control-clock pulse. A
pulse while the FIFO is full is not retained and increments the saturating
`queue_overrun` counter once.

All index ordering is modulo `2^64` with the usual unambiguous half-range rule:
a forward distance has bit 63 clear and no valid campaign may span `2^63`
accepted samples. A command is admitted only on a consecutive valid input beat,
and its `p-32` capture start must be at least 64 accepted samples beyond the next
expected index. The frozen rejection priority is duplicate center, overlapping
or out-of-order window, then insufficient lead/late. Once admitted, a request
emits exactly 130 unbackpressured tagged beats for indexes `p-32..p+97`; the
stored candidate timestamp must equal the observed raw timestamp at `p`.

A deasserted valid, accepted-index jump, timestamp mismatch, or lane disable
fails the affected admitted request closed. The later buffer writer must give
`capture_abort` priority over every partial `capture_valid` beat and discard the
entire buffer. Aggregate admitted/completed/rejected/aborted counters and
separate overrun, late, duplicate, overlap, valid-gap, index-jump, and timestamp
counters saturate at `2^32-1`. The eventual AXI block will publish those fields
without reconstructing events from software timing.

The scheduler's control and sample resets are one coordinated module reset:
the integration wrapper must assert both together before either is released.
Independent reset epochs are intentionally not accepted because they could
reinterpret an asynchronous FIFO pointer; that top-level reset acknowledgement
is a required integration test before a radio image exists.

The asynchronous-clock test fills all seven FIFO entries with the destination
clock stopped, proves a single eighth overrun, drains disabled commands, and
then covers chronological queuing, exact 130-beat data/timestamp mapping,
back-to-back clock phases, every rejection class, pending and active valid-gap
aborts, active index-jump and timestamp aborts, disable flushing, and a capture
that crosses the full-width index wrap. These tests establish the trigger seam;
they do not establish arithmetic equivalence, buffering, CDC constraints,
route closure, or radio qualification.

## Cached-Eh and sliding-Ex milestone

`starlink_pss_sliding_correlator.v` is a second implementation kept alongside
the immutable raw arithmetic reference. It retains exactly three registered
17x17 multipliers, but validates coefficient energy once at commit, copies a
passing shadow bank into the active bank, and publishes the active generation
with every result. Zero-energy, above-31-bit-energy, or saturated commits are
rejected without changing the prior active bank.

For each 130-sample job it computes each unsigned CI16 sample energy once,
stores all 130 energies, and accumulates the first 66-sample `Ex` window during
that same pass. Each later lag uses the exact integer update
`Ex[k+1] = Ex[k] - e[k] + e[k+66]`. A 50-bit intermediate checks the already
proved legal 38-bit Stage-15 bound; any impossible excursion increments a
saturating bound-error counter. Correlation and externally visible tuple fields
retain the raw engine's signed-48 after-tap saturation contract.

The differential test treats the original raw core as an independent RTL
reference. It compares 260 complete tuples across full-scale legal samples,
zero samples, the frozen real capture, cached-bank reuse, independent output
backpressure, two accepted generations, and rejected full-scale/zero-energy
shadow commits. It also proves that rejected commits preserve the active bank,
that every legal saturation and bound-error count remains zero, and that the
no-stall optimized job completes in fewer cycles than the raw job.

## Abort-atomic capture and composed tracking milestone

`starlink_pss_capture_bridge.v` accepts the scheduler's unbackpressured capture
stream into two 130-sample banks. A bank is published to the engine only after
all slots arrive in exact order and `capture_done` is observed. Abort has
priority over every write. A malformed slot sequence or descriptor/buffer
failure discards the whole image and increments a separate saturating counter;
partial data is never exposed to the correlator.

The sample-to-engine descriptor and engine-to-sample bank releases use marked
two-stage synchronizers under the same coordinated reset epoch as the command
FIFO. The capture payload uses true dual-clock block RAM. The engine drains a
published bank in slot order with normal ready/valid backpressure and returns
ownership only after all 130 samples have been accepted.

`starlink_pss_tracking_core.v` composes the scheduler, bridge, and optimized
correlator across explicit control, sample, and engine clocks. Its asynchronous
test deliberately fills both capture banks, drops a third job exactly once,
returns and reuses a bank, applies result backpressure, and bit-checks 130 raw
tuples from two ordered jobs. Request ID, center index/timestamp, stored first-
tap timestamp, lag order, coefficient generation, complex correlation,
sliding energy, saturation, and every clean/error counter are checked.

The composed core is still pre-ABI RTL. In particular, it does not yet connect
the exact normalized winner reducer, multi-bank modes, double-buffered result
publication, AXI register file, or rate-parameterized 30/60 MS/s geometry.

## Exact normalized winner reducer

`starlink_pss_exact_reducer.v` consumes one strictly ordered 65-lag tuple job
and selects the earliest maximum of the exact score `|C|^2/(Ex*Eh)`. In the
single-bank tracking mode, `Eh` is constant across the job and is cancelled
exactly; validation mode retains it. The implementation never divides and
uses strict rational cross-products, so it neither rounds a score nor changes
the first-wins tie rule.

The Stage-15 bounds are checked before a tuple can win: each complex
correlation component fits signed 39 bits, `Ex` fits 38 unsigned bits, and
`Eh` fits 31 unsigned bits. These proofs reduce the exact datapath to a 77-bit
numerator, a 69-bit denominator, and a 146-bit cross-product. Impossible
values, nonpositive energies, or any saturation fail closed and increment
separate invalid/bound counters. A malformed job creates one protocol-error
episode and is drained through its last marker. The complete winner packet is
held stable under output backpressure.

The self-checking reducer test covers single-bank cancellation, validation
with unequal `Eh`, exact ties, all-invalid jobs, legal near-bound values,
explicit bound failures, output backpressure, and malformed-job recovery. Run
the portable suite with `./run_tests.sh`. Run its Vivado 2022.2 OOC gate with:

```sh
./run_reducer_ooc.sh
```

The gate requires 100 MHz post-opt setup closure, clean methodology and timing
coverage, zero DSP/BRAM inference, at most 1,600 Slice LUTs, and at most 1,700
registers. The current local post-opt, unplaced result passes at 1,513 Slice
LUTs, 1,649 registers, zero block RAM, zero DSP48E1s, and +1.470 ns setup
slack. A naïve full-width implementation measured 2,118 LUTs and 2,757
registers and was rejected rather than becoming the milestone baseline.

The reducer result is not yet part of the composed-core OOC count below.
Simply adding both independently synthesized totals would exceed the original
2,500-LUT/2,000-register provisional milestone, so integration must be
measured and the complete RX-only shell must establish the real device
headroom before a hardware image is considered.

## Composed-core OOC gate

Run the Stage-15 composed gate with Vivado 2022.2:

```sh
./run_tracking_ooc.sh
```

The gate constrains the sample input at 16.667 ns (the 60 MS/s clock ceiling)
and the control/engine clocks at 10 ns, declares the three clock groups
asynchronous, checks every timing-coverage category, requires zero methodology
violations, and requires exactly three DSP48E1s. The conservative milestone
budget is at most 2,500 Slice LUTs, 2,000 registers, and five RAMB36-equivalent
tiles. Vivado's documented area-oriented synthesis and post-synthesis
resynthesis directives are part of this reproducible gate.

The current local post-opt, unplaced result passes at 2,483 Slice LUTs, 1,855
registers, five RAMB36-equivalent tiles, exactly three DSP48E1s, and +0.192 ns
maximum-delay setup slack. Methodology violations and unexpected nonzero
`check_timing` categories are both zero. The one expected `no_input_delay`
entry is the explicitly false-pathed shared reset. Hold analysis, placed/routed
timing, full-shell headroom, AXI correctness, and radio behavior remain
unproven.
