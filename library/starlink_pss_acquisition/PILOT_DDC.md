# Experimental paired-scanner pilot DDC — DO NOT MERGE

This is a building block, not a deployable receiver or a GLRT/PSS detection
claim. The planned path is canonical 15 MS/s -> pilot mixer -> 31-tap halfband
/2 -> 255-tap FIR /3 -> 2.5 MS/s single-RX IIO DMA. Only the last stage is
implemented in RTL here. The complete fixed-point reference lives in the
firmware superproject's `tests/starlink_oracle/pilot_ddc.py`.

## `starlink_pilot_fir3` contract

- One 100 MHz clock. CI16 input at 7.5 MS/s; CI16 output at 2.5 MS/s.
- Input beats must be at least 13 core clocks apart. This supports the nominal
  13/13/14-clock pattern and a small pacing margin. A future FIFO/pacer must
  enforce this at the bursty acquisition tap without backpressuring the ADC.
- `input_index` is the absolute, even canonical 15 MS/s index, advancing by
  two per accepted beat. `input_phase` is `(input_index / 2) mod 3`. The caller
  supplies the absolute initial phase; this core checks its subsequent 0/1/2
  progression. The integrated wrapper must attest initial phase against the
  source counter. Outputs select phase zero and retain the input index.
- That output index identifies the newest input contributing to the result,
  NOT its group-delay-corrected sample center. The core delay is 127 of its
  7.5 MS/s input samples, or 254 canonical samples. Including the earlier
  halfband, the proposed complete pilot tap has 269 canonical samples of
  group delay and 538 canonical samples of history.
- Output arithmetic includes zero-padded startup samples, marked invalid by
  `output_support_valid`. A result is fully supported only after 255 consecutive
  `input_support_valid` beats. An invalid input taints its entire filter window.
  Downstream recording must also apply the independent RF/hop guard.
- `flush` aborts outstanding work, zeros logical histories without clearing
  block RAM, and releases a fault halt. It does not reset the source clock or
  erase `sticky_fault`. Output data without `output_valid` is don't-care.
- Sticky bits: bit 0 index discontinuity/odd index, bit 1 invalid/discontinuous
  phase, bit 2 a new output job arriving before the previous job can finish.
  Any such fault halts the stream and discards pending work until an explicit
  flush; no sample is silently dropped and no ready/backpressure signal exists.
- `output_saturations` counts saturated I/Q lanes (0, 1, or 2) for that output.
  The wrapper must accumulate these events and tag them by the owning visit.
  There is no hidden saturation counter reset on a hop.

The source counter must not wrap during a recording. Visit IDs and the source
to canonical counter conversion belong to the integrated wrapper, not this
arithmetic core. A consumer FIFO must report its own overflow; this core does
not prove IIO continuity.

## Arithmetic and implementation

`pilot_fir3_q17.mem` contains the first 128 signed 18-bit coefficients of the
frozen symmetric 255-tap bank. The test reconstructs the complete bank and
checks it against the pinned numerical oracle; it must not regenerate a new
golden merely to satisfy a mismatch. Pair sums are signed 17-bit, products
35-bit, lane accumulators 42-bit, and the final sum 44-bit. Quantization uses
nearest/ties-even rounding followed by explicit signed-16 saturation.

Four complex lanes evaluate 128 symmetric pairs in 32 issue clocks; the center
tap is included once. Each lane uses two DSP multiply-accumulators. The sample
ring is 512 complex samples striped across four banks with two read ports per
bank. Each arriving sample temporarily owns one write port and pauses issue,
not reception. The ring is longer than the filter so live writes cannot replace
data still needed by the current window. Missing startup history is masked,
not read as uninitialized IQ.

With no overlapping writes the output latency is 37 core clocks; at the
minimum 13-clock input spacing it is 39 clocks. A new job can start on the
same clock that the previous output is emitted. Index and support metadata
are captured before that handoff, not reconstructed from the next job.

## Tests and qualification boundary

From the firmware superproject, with NumPy/pytest and Icarus installed:

```sh
python -m pytest -q tests/starlink_oracle/test_pilot_fir3_rtl.py
bash hdl/library/starlink_pss_acquisition/run_pilot_fir3_ooc.sh
```

The RTL suite fails explicitly if Icarus is missing. It checks coefficient
identity, exact IQ/saturation/index/support agreement with direct integer
convolution, all three initial phases, indexes above 2^63, repeated RAM ring
wraps, minimum-rate and jittered pacing, impulses, clipped steps, flushes in
the arithmetic pipeline (including the output boundary), source/phase faults,
overspeed, and validity contamination by an interior invalid sample.

The Vivado 2022.2 experiment targets `xc7z010clg400-1`. Its gate covers resource
budgets and **standalone register-to-register** routed setup/hold timing only.
OOC input/output ports lack physical placement constraints and report boundary
hold violations; those remain explicitly UNQUALIFIED in the summary. The full
timing/methodology reports are retained. No exceptions are inserted into timing
constraints, and any internal negative hold/setup slack still fails the gate.
Unexpected methodology categories, unrouted nets, or missing timing paths fail.
This experiment cannot be substituted for a full-shell route with real
upstream/downstream paths, PSS, the remaining DDC, and DMA.

Next gates: complete mixer/halfband/pacer RTL; compose 15/30/60 source-rate
references with full pilot/PSS frames; complete receiver route; then .18
single-frequency paired IIO capture. No radio has been deployed with this core.
