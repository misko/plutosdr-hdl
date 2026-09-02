# Experimental continuous PSS acquisition — do not merge to HDL main

This directory contains staged RTL for the RX-only Starlink PSS acquisition
experiment.  It is developed only on `codex/starlink-rx-only-do-not-merge`.
It is not release firmware and is never persistently flashed.

`starlink_pss_phase_map.v` is the first independently testable hardware slice.
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

Run the deterministic simulation with:

```sh
./run_tests.sh
```

The simulation suite checks the phase map plus both default-geometry and small-
geometry scheduler tests.  It covers exact overlap contents, 15 MS/s-equivalent
input cadence at a 100 MHz clock, output backpressure stability, disable abort,
explicit gap and index restart, descriptor overflow, and ring-retention
overflow.

Run the default-geometry Zynq-7010 out-of-context gate with:

```sh
./run_phase_map_ooc.sh /absolute/output/directory
```

Run the scheduler's independent default-geometry OOC gate with:

```sh
./run_overlap_scheduler_ooc.sh /absolute/output/directory
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
