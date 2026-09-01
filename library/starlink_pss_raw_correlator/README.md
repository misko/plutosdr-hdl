# Stage-15 exact-PSS raw correlator — DO NOT MERGE TO HDL MAIN

This directory is an isolated arithmetic milestone on
`codex/starlink-rx-only-do-not-merge`. It is not connected to the Pluto block
design, AXI, DMA, the diagnostic delay monitor, or a radio image. It must not
be packaged or booted in this state.

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
