# Experimental paired-scanner pilot DDC — DO NOT MERGE

This is a building block, not a deployable receiver or a GLRT/PSS detection
claim. The implemented path is canonical 15 MS/s -> paced pilot mixer ->
31-tap halfband /2 -> 255-tap FIR /3 -> 2.5 MS/s. Receiver/IIO DMA integration
is still pending. The complete fixed-point reference lives in the firmware
superproject's `tests/starlink_oracle/pilot_ddc.py`.

## Complete `starlink_pilot_ddc` contract

The wrapper accepts consecutive canonical 15 MS/s CI16 samples in the existing
100 MHz acquisition domain. A bounded 128-entry FIFO absorbs bursts; its reader
paces samples with alternating minimum 6/7-clock intervals. Idle time does not
rebase the source index, mixer phase, or decimation phase. The same canonical
interface is used after the existing 30->15 and 60->30->15 conditioners.

`edge_upper` selects the Q16 oscillator step: +12/64 or -13/64 cycles per
canonical sample. The oscillator uses the absolute source index, not the time
at which a FIFO entry is drained. The halfband stores even/odd phases in small
RAM rings and shares one pair-adder per IQ lane before its two MACs. The even
window remains intact throughout a job; the odd center is captured at job start
because the next odd input can overwrite its ring slot before the last row.
The complete pilot path uses fourteen DSP MAC/multiplier blocks in the measured
standalone build, including the four mixer multipliers.

The first accepted sample after reset/flush captures edge and `visit_id`.
Changing either without a flush fails closed, even while the input is idle.
Flush discards queued/in-flight work and logical histories; the external global
source counter keeps running. Every emitted result carries that captured visit,
its newest canonical index, and its support-valid flag. Results select absolute
indexes divisible by six. Subtract 269 canonical samples for the signal center;
do not subtract the earlier 30/60 conditioner delays a second time, because
those conditioners already emit center-coordinate indexes.

The initial modulo-three phase is computed with small byte reductions, avoiding
a generic wide divider. The integrated tests cover arbitrary initial phases
and high 64-bit indexes. Counter wrap is not supported during a recording.

There is no ADC backpressure or output `ready`. Downstream DMA/FIFO logic must
report its own losses and apply RF guard validity. A consumer samples output
transfers on the rising edge; `output_valid` includes a combinational fail-closed
qualifier for the current fault/flush condition. Tests sample actual transfers,
not signals midway through the next stimulus cycle.

Sticky fault bits (all halt this pilot branch until explicit flush):

- 0: ingress source-index discontinuity or exhausted uint64 counter.
- 1: ingress FIFO overflow.
- 2: edge/visit changed without a flush.
- 3: explicit upstream sample gap.
- 4: halfband job overrun.
- 5/6/7: final FIR index/phase/job-overrun fault respectively.

Accepted/emitted sample counters (uint64), saturation-event count (uint32),
FIFO high-water mark, and sticky faults survive a flush and clear on reset.
Counters saturate rather than wrap; a saturated counter is a lower bound, not
an exact total. Saturation events count I/Q clipping at all three arithmetic
stages. Intentional flush discards must be attributed by the hop controller;
the arithmetic core alone is not a continuity receipt.

## `starlink_pilot_fir3` contract

- One 100 MHz clock. CI16 input at 7.5 MS/s; CI16 output at 2.5 MS/s.
- Input beats must be at least 13 core clocks apart. This supports the nominal
  13/13/14-clock pattern and a small pacing margin. The complete wrapper's
  FIFO/pacer enforces this without backpressuring the ADC.
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
python -m pytest -q tests/starlink_oracle/test_pilot_ddc_rtl.py
bash hdl/library/starlink_pss_acquisition/run_pilot_fir3_ooc.sh
bash hdl/library/starlink_pss_acquisition/run_pilot_ddc_ooc.sh
bash hdl/library/starlink_pss_acquisition/run_pilot_ddc_dwell.sh
```

The RTL suite fails explicitly if Icarus is missing. It checks coefficient
identity, exact IQ/saturation/index/support agreement with direct integer
convolution, all three initial phases, indexes above 2^63, repeated RAM ring
wraps, minimum-rate and jittered pacing, impulses, clipped steps, flushes in
the arithmetic pipeline (including the output boundary), source/phase faults,
overspeed, and validity contamination by an interior invalid sample.

The complete-DDC suite adds 52 tests: both edges, all six initial phases,
burst/idle pacing, FIFO overflow, visit changes, queued/pipeline flushes, support
contamination, and exact whole-chain replay with the existing 30/60 conditioners.
Analytic tones at -100/0/+100 kHz residual CFO verify frequency and delay mapping
independently of the integer replay comparison. The separate full-dwell run
accepts 1,800,540 canonical samples and emits 300,090 results, including exactly
300,000 supported samples (120 ms) after 90 startup-invalid results. It verifies
CW gain/phase, all indexes, visit tags, counts and zero overflow/clipping; it is
not a 120 ms RF or IIO test.

The Vivado 2022.2 experiment targets `xc7z010clg400-1`. Its gate covers resource
budgets and **standalone register-to-register** routed setup/hold timing only.
OOC input/output ports lack physical placement constraints and report boundary
hold violations; those remain explicitly UNQUALIFIED in the summary. The full
timing/methodology reports are retained. No exceptions are inserted into timing
constraints, and any internal negative hold/setup slack still fails the gate.
Unexpected methodology categories, unrouted nets, or missing timing paths fail.
This experiment cannot be substituted for a full-shell route with real
upstream/downstream paths, PSS, the remaining DDC, and DMA.

Next gates: complete receiver/DMA/IIO integration and full-shell route; then .18
single-frequency paired capture. Runtime lower/upper selection in the existing
PSS conditioner/template banks and shared hop fencing also remain to be added.
No radio has been deployed with this core.
