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

Run the deterministic simulation with:

```sh
./run_tests.sh
```

Run the default-geometry Zynq-7010 out-of-context gate with:

```sh
./run_phase_map_ooc.sh /absolute/output/directory
```

The OOC gate requires the canonical Vivado 2022.2 installation and fails if
the map does not infer exactly 20 RAMB36E1 blocks, uses a DSP, exceeds its logic
budget, has a methodology/check-timing violation, or misses 100 MHz post-opt
unplaced setup/hold timing.  Its synchronous input boundary assumes a
0.5--1.0 ns source-clock-to-input arrival window; the complete-shell gate must
replace that OOC assumption with timing from the actual upstream registers.
Complete-shell routing remains a later gate.
