# Experimental continuous PSS acquisition — do not merge to HDL main

This directory contains staged RTL for the RX-only Starlink PSS acquisition
experiment.  It is developed only on `codex/starlink-rx-only-do-not-merge`.
It is not release firmware and is never persistently flashed.

`starlink_pss_phase_map.v` is the first independently testable hardware slice.

`starlink_pss_sample_cdc.v` is the non-backpressured one-RX ingress boundary.
It transfers CI16 samples and their 64-bit accepted-sample index from the
AD936x receive clock into the 100 MHz acquisition domain through a 128-entry
dual-clock FIFO.  Each reset is independently synchronized into both clock
domains and purges both pointer domains.  The first sample
after reset, or after any FIFO-full drop, is explicitly gap tagged; a
saturating drop counter, sticky overflow indication, live FIFO level, and
maximum observed level are exported in the acquisition domain.  Consequently
the detector never silently correlates across lost or stale samples.

The functional suite runs the CDC contract at both four-entry stress depth and
the default 128-entry implementation depth.  The independent Zynq-7010 timing,
CDC, methodology, and resource gate is:

```sh
./run_sample_cdc_ooc.sh /absolute/output/directory
```

`starlink_pss_acquisition_health.v` retains the diagnostic evidence that must
cross the PSMA 1.1 snapshot: scheduler gap/index/overflow counts, detector
fault episodes, phase/index discontinuities, zero denominators, and sticky
cause flags for every quarantining pipeline stage.  Its counters saturate
rather than wrap; a reduced-width test proves saturation as well as episode
versus level counting and reset-epoch clearing.
It consumes one already-normalized eight-bit score for each candidate start at
the canonical 15 MS/s acquisition rate.  It keeps all 20,000 one-sample phase
hypotheses, sums exactly 64 complete frames into a 16-bit map, and uses two
banks so the ARM can read one immutable map while the next is filled.

This slice deliberately does not claim an implemented FFT or a PSS detector.
The future score front end must provide consecutive absolute start indexes and
phases, pass fixed-point replay, and remain a read-only tap beside the unchanged
RX DMA path.  A discontinuity or phase/index mismatch invalidates and clears
the partial map; incomplete maps are never published.

`starlink_pss_overlap_scheduler.v` is the next IP-independent slice.  It turns
the continuous, gap-tagged CI16 stream into 512-sample FFT input blocks with 65
samples of overlap (447 new samples per block).  A 2,048-sample ring and a
four-entry descriptor FIFO decouple the non-backpressured ADC side from a
ready/valid FFT input.  Explicit gaps, absolute-index discontinuities, queue
overflow, ring-retention overflow, and disable all fail closed: no partial
block survives, and the current valid sample becomes the first sample of a new
segment where applicable.  The scheduler remains independent of Xilinx FFT IP
so its cadence, data, backpressure, and restart behavior are fully covered by
ordinary RTL simulation.

`starlink_pss_spectrum_product.v` is the exact arithmetic bridge between the
forward and inverse FFTs.  It accepts signed Q1.23 transform and kernel bins,
computes their complex product, applies the frozen one-bit safety shift, rounds
to nearest with ties to even, and saturates back to Q1.23 with an explicit
overflow event.  Its three-stage elastic pipeline sustains one bin per clock
and carries the FFT block exponent and absolute block identity unchanged.  It
is independent of generated Xilinx FFT source and kernel-ROM packaging.

`starlink_pss_kernel_rom.v` is the hash-locked coefficient boundary between
the forward XFFT adapter and that spectrum product.  Its 512 upper-edge PSS
frequency-domain coefficients are signed Q1.23, packed as `{Q,I}`, and served
from a synchronous block ROM at one bin per clock.  It independently checks
all bin indexes, TLAST, per-block exponent stability, absolute block identity,
and the 447-sample overlap-save stride.  Any malformed beat is consumed but
never emitted, and the boundary remains quarantined until common flush.  The
checked-in memory artifact is also verified byte-for-byte against its frozen
canonical signed-I/Q SHA-256 before RTL simulation.

`starlink_pss_forward_kernel_join.v` supplies the explicit data alignment that
the coefficient-only ROM intentionally omits.  It captures each accepted
forward-XFFT I/Q bin in the same handshake as the synchronous lookup and emits
the complex bin, matching coefficient, and checked metadata as one elastic
transaction.  Downstream stalls hold the entire combined payload; a ROM
protocol fault publishes neither the malformed coefficient nor its I/Q.

`starlink_pss_energy_cache.v` computes the exact 66-sample CI16 denominator
stream beside the FFT path.  It retains 2,048 consecutive 38-bit energies in
an absolute-indexed circular BRAM, so delayed IFFT results request the matching
window without assuming a fixed transform latency.  Full absolute range
metadata prevents stale circular aliases.  A same-cycle newest-value bypass
is defined; an imminent oldest-value overwrite fails the lookup closed.  Gap,
index discontinuity, flush, and disable invalidate both partial energy windows
and retained results without clearing the BRAM contents themselves.

`starlink_pss_score_divider.v` is one exact rational quantization lane.  It
accepts an already-scaled 69-bit correlation-power numerator and 69-bit
energy/coefficient denominator, performs eight restoring iterations, and
returns `round_ties_even(255*numerator/denominator)`.  Zero and saturation
cases intentionally take the same eight cycles as ordinary ratios, making a
later two-lane dispatcher deterministic.  This slice does not calculate the
wide numerator/denominator or join them to the energy cache.

`starlink_pss_score_prepare.v` is the exact wide-arithmetic stage immediately
before those divider lanes.  It squares signed Q1.23 IFFT components, restores
correlation power by `2^(2*(1 + Ef + Ei))`, and multiplies the indexed 38-bit
sample energy by the frozen 31-bit coefficient energy.  A mathematical
numerator beyond 69 bits saturates to the ratio maximum, which is exactly
equivalent to a unity-or-greater score because every denominator fits 69 bits.
Its three elastic stages sustain one result per clock and preserve candidate
identity through stalls and flush.  The raw IFFT-result FIFO, energy-cache
lookup join, and two-lane dispatcher remain separate composition work.

`starlink_pss_raw_result_fifo.v` absorbs the 447 qualified outputs from each
512-point overlap-save IFFT block.  Its 512-entry, 123-bit storage preserves
signed correlation, both block exponents, the absolute candidate-start index,
and the block-last marker.  A registered synchronous read keeps the wide FIFO
in block RAM.  The declared capacity includes the prefetched output register;
overflow is reported without mutating queued state, and flush invalidates
pointers/count/output without clearing memory contents.

`starlink_pss_ifft_qualifier.v` validates every index, TLAST, exponent, and
block-start field in the complete 512-result IFFT stream.  It discards indexes
0 through 64, maps indexes 65 through 511 to absolute candidate starts, and
latches a protocol fault until flush if framing, metadata stability, or the
447-sample next-block stride is wrong.

`starlink_pss_xfft_block_adapter.v` is the vendor-IP-independent control and
metadata boundary for one generated 512-point XFFT core.  It stretches reset,
sends exactly one fixed transform-direction configuration before opening the
data input, permits only one block in flight, preserves its absolute start
identity, and validates both application and XFFT framing.  It captures the
per-frame block exponent from the always-ready status channel and requires the
same value on every indexed TUSER result before publication.  Missing status
holds output; malformed index, TLAST, padding, exponent, status identity, or a
hard XFFT event latches a fail-closed quarantine until explicit common flush.
Data-input/output halt events remain visible telemetry because ordinary AXI
backpressure can cause them; they do not silently invalidate good data.

`starlink_pss_energy_join.v` keeps raw correlation metadata aligned with the
one-outstanding absolute-indexed energy-cache transaction.  It can retire one
response while issuing the next lookup, sustaining one join per clock.  A
miss, returned-index mismatch, or orphan response is consumed but never
emitted; the interfaces remain quarantined until flush.

`starlink_pss_score_lanes.v` alternates ratios across two fixed-latency exact
divider instances and independently alternates the selected output only on
handshake.  This preserves FIFO order through arbitrary downstream stalls and
provides 22.22 million score starts/s at a 100 MHz clock.

`starlink_pss_candidate_score_path.v` composes the qualifier, raw FIFO, energy
join, ratio preparation, and two ordered divider lanes.  It exposes the energy
cache transaction port and normalized score stream.  Any component fault is
latched and immediately gates input and output; the external acquisition
controller must then apply the same explicit flush to this path and its energy
cache.  XFFT cores, coefficient ROM, scheduler wiring, phase-map wiring, and
the real RX shell remain outside this source-only top.

`starlink_pss_iq_to_score.v` closes the source-only 15 MS/s datapath from a
continuous CI16 accepted-sample stream through the overlap scheduler, exact
energy cache, two regenerated XFFT v9.1 instances, hash-locked kernel join,
complex product, inverse-result qualification, and normalized score tail.  It
publishes 447 exact timing scores per complete 512-sample overlap-save block
and quarantines the detector on any constituent protocol or arithmetic fault.
Registered lifecycle control keeps external reset/flush/fault inputs out of
the internal ready chain while same-cycle output gates still fail closed. The
inverse XFFT output is consumed without downstream backpressure; if the
burst-sized candidate path ever cannot accept, the beat is suppressed and the
whole detector quarantines instead of stalling the real-time transform.

`starlink_pss_score_phase_tagger.v` establishes phase zero on the first valid
score after reset, disable, flush, or a stream discontinuity, then advances
modulo the configured frame length only on score events. It checks consecutive
absolute candidate indexes, suppresses a mismatched score, and cleanly rebases
the next consecutive score at phase zero; wall-clock gaps with no score-valid
event do not change phase.

`starlink_pss_iq_to_phase_map.v` composes the complete score path, phase tagger,
and qualified ping-pong phase map. A one-cycle, one-score-per-clock boundary
separates the tagger's absolute-index comparison from the map's independent
continuity checks and segmented BRAM enables. At the default geometry it
accumulates 20,000 phases across 64 frames and exposes only complete immutable
40,000-byte maps for the eventual processor interface. Register/CDC control,
RX-shell routing, complete placement and routing, and hardware qualification
remain separate later gates.

Run the deterministic simulation with:

```sh
./run_tests.sh
```

From the firmware repository root, regenerate the deterministic three-block
oracle vectors and replay the full IQ-to-score top against the actual Vivado
2022.2 XFFT behavioral model with:

```sh
./run_starlink_pss15_iq_to_score_xfft.sh
```

Replay the same exact IQ, transform, product, inverse, and score vectors
through a reduced-geometry three-frame map, then exhaustively read every
published bin, with:

```sh
./run_starlink_pss15_iq_to_phase_map_xfft.sh
```

The simulation suite checks the phase map plus both default-geometry and small-
geometry scheduler tests, plus thousands of deterministic spectrum-product
vectors generated by an independent Python oracle.  It covers exact overlap
contents, 15 MS/s-equivalent input cadence at a 100 MHz clock, output
backpressure stability, disable abort, explicit gap and index restart,
descriptor overflow, ring-retention overflow, signed half-way rounding,
saturation, metadata ordering, and arithmetic-pipeline flush.
The energy-cache test additionally checks all 2,435 exact windows from a
15 MS/s-equivalent segment, full-cache rollover and boundary lookups, lookup
backpressure, a stalled-response gap flush, index restart, and disable.
The divider test replays thousands of independently generated 69-bit rational
cases, including even/odd half-way ties, zero denominator, saturation, output
stalls, and flushes during calculation and completed-output hold.
The score-preparation test independently forms thousands of signed
correlation-power, exponent, and full-width energy cases.  It covers actual and
extreme block exponents, numerator-width boundaries, exact denominator
multiplication, pipeline backpressure, metadata, and flushes.
The raw-result FIFO test holds its consumer stalled for an entire 447-result
IFFT burst, checks exact payload/order while draining with stalls, exercises
1,200 results of simultaneous input/output traffic, fills all 512 declared
entries, verifies fail-closed overflow, and flushes all retained state.
The qualifier test checks two full blocks through deterministic stalls and
injects index, TLAST, metadata, and next-block-stride faults.  The energy join
sustains 1,000 consecutive lookups and proves miss, mismatch, and orphan
quarantine.  The two-lane and composed score tests compare ordered results to
independent exact-integer vectors.  Finally, the candidate-path integration
test uses the real energy cache: one dense 512-result IFFT block produces all
447 exact scores without input backpressure, while a missing-energy replay
publishes no score and latches the path fault.
The XFFT-adapter test drives a mock AXI core through a complete 512-sample
input/output frame with independent stalls, proves data cannot precede either
configuration or block status, checks exact lane/index/exponent/block metadata,
and injects application framing, orphan status, hard core-event, status-halt,
and output-index faults across explicit flush recovery.
The kernel-ROM test verifies all 512 coefficients across consecutive blocks,
continuous one-bin-per-clock input, deterministic downstream stalls, exact
metadata propagation, output stability, and fail-closed recovery from index,
TLAST, exponent, block-identity, and overlap-stride faults.  A separate Python
gate binds both the textual memory image and canonical little-endian signed-I/Q
stream to fixed SHA-256 digests.

Run the default-geometry Zynq-7010 out-of-context gate with:

```sh
./run_phase_map_ooc.sh /absolute/output/directory
```

Run the scheduler's independent default-geometry OOC gate with:

```sh
./run_overlap_scheduler_ooc.sh /absolute/output/directory
```

Run the spectrum product's independent OOC gate with:

```sh
./run_spectrum_product_ooc.sh /absolute/output/directory
```

Run the sliding-energy cache's independent OOC gate with:

```sh
./run_energy_cache_ooc.sh /absolute/output/directory
```

Run one exact score-divider lane's independent OOC gate with:

```sh
./run_score_divider_ooc.sh /absolute/output/directory
```

Run the exponent-aware ratio-preparation OOC gate with:

```sh
./run_score_prepare_ooc.sh /absolute/output/directory
```

Run the raw IFFT-result FIFO's independent OOC gate with:

```sh
./run_raw_result_fifo_ooc.sh /absolute/output/directory
```

Run the composed IFFT-to-score path OOC gate with:

```sh
./run_candidate_score_path_ooc.sh /absolute/output/directory
```

Run the strict generated-XFFT boundary-adapter OOC gate with:

```sh
./run_xfft_block_adapter_ooc.sh /absolute/output/directory
```

Run the hash-locked kernel-ROM OOC gate with:

```sh
./run_kernel_rom_ooc.sh /absolute/output/directory
```

Run the full IQ-to-score generated-XFFT OOC gate from the firmware repository
root with:

```sh
./run_starlink_pss15_iq_to_score_xfft_ooc.sh /absolute/output/directory
```

Run the default 20,000-bin, 64-frame IQ-to-phase-map composition gate with:

```sh
./run_starlink_pss15_iq_to_phase_map_xfft_ooc.sh /absolute/output/directory
```

The OOC gate requires the canonical Vivado 2022.2 installation and fails if
the map does not infer exactly 20 RAMB36E1 blocks, uses a DSP, exceeds its logic
budget, has a methodology/check-timing violation, or misses 100 MHz post-opt
unplaced setup/hold timing.  Its synchronous input boundary assumes a
0.5--1.0 ns source-clock-to-input arrival window; the complete-shell gate must
replace that OOC assumption with timing from the actual upstream registers.
Complete-shell routing remains a later gate.

The scheduler OOC gate uses the same clock and boundary assumptions.  It
requires the CI16 ring to infer exactly two RAMB36E1 blocks, no DSPs, bounded
logic, clean methodology/check-timing reports, and nonnegative 100 MHz post-opt
unplaced setup and hold slack.  This proves only the scheduler slice; composed
timing with FFT IP and the real RX tap remains a later gate.

The spectrum-product OOC gate requires exactly eight DSP48E1 cells and no
BRAM, bounded elastic-control and rounding logic, clean reports, and
nonnegative 100 MHz post-opt unplaced setup and hold slack.  This gate does not
include either generated FFT core, the coefficient ROM, or composed routing.

The energy-cache OOC gate requires the 2,048-entry 38-bit result memory to
infer exactly two RAMB36E1 blocks plus one RAMB18E1 (2.5 BRAM tiles), the two
CI16 squares to infer exactly two DSP48E1s, bounded logic, clean reports, and
nonnegative 100 MHz post-opt unplaced setup and hold slack.  It proves neither
the later energy/correlation join nor the normalizer.

The score-divider OOC gate requires no BRAM or DSPs, bounded restoring-divider
logic, clean reports, and nonnegative 100 MHz post-opt unplaced setup and hold
slack.  It proves one fixed-latency lane; the later two-lane dispatcher, result
FIFO, and ordered merge remain composition gates.

The ratio-preparation OOC gate requires no BRAM, bounded squaring and sparse
constant-product resources, clean reports, and nonnegative 100 MHz post-opt
unplaced setup and hold slack.  It proves only the wide arithmetic pipeline;
the raw-result FIFO, indexed-energy join, and divider composition remain later
gates.

The raw-result FIFO OOC gate requires its 512-by-123-bit storage to infer
exactly two RAMB36E1 blocks, no RAMB18E1 or DSPs, bounded control logic, clean
reports, and nonnegative 100 MHz post-opt unplaced setup and hold slack.  It
proves only burst storage; IFFT qualification, indexed-energy lookup, and
fail-closed block lifecycle remain composition gates.

The candidate-score-path OOC gate covers the complete composed tail named
above.  It requires exactly two RAMB36E1 blocks, four DSP48E1 cells, bounded
logic, clean methodology/check-timing reports, and nonnegative 100 MHz
post-opt unplaced setup/hold slack.  It does not include the energy cache,
either XFFT core, coefficient ROM, scheduler, phase map, AXI/CDC shell, or
complete placement and routing.

The XFFT-boundary-adapter OOC gate requires no BRAM or DSPs, bounded control
logic, clean methodology/check-timing reports, and nonnegative 100 MHz
post-opt unplaced setup/hold slack.  It proves the reusable protocol boundary
only; it does not include a generated XFFT instance, coefficient ROM, transform
arithmetic, or the full forward/product/inverse composition.

The kernel-ROM OOC gate first verifies both frozen SHA-256 identities, then
requires exactly two initialized RAMB18E1s (one BRAM tile) and no RAMB36E1 or
DSPs, bounded control logic, clean methodology/check-timing reports, and
nonnegative 100 MHz post-opt unplaced setup/hold slack.  It proves the
coefficient lookup and its streaming protocol guard, not the forward XFFT
values or complex-product composition.

The full IQ-to-score OOC gate regenerates the exact two-core 24-bit,
block-floating, radix-4-burst XFFT definition used by replay and synthesizes it
with the complete source-only score path for `xc7z010clg400-1`.  It rejects a
resource overflow, methodology/check-timing error, or negative 100 MHz
post-opt unplaced setup/hold slack.  It is still not a placed-and-routed RX
shell result and includes neither the phase map nor AXI/CDC/control plumbing.

The full IQ-to-phase-map OOC gate adds the default two-bank map and requires
the whole composition to fit the Zynq-7010 and close 100 MHz after optimization
with clean methodology and `check_timing` reports. Its timing-driven lifecycle,
FIFO-admission, and score-to-map register boundaries do not reduce the
one-score-per-clock internal throughput. This remains an unplaced OOC gate;
the actual RX tap, AXI/CDC/control boundary, and complete shell route are the
next source milestones.
