# Fresh coarse25 arithmetic foundation — do not merge

This library is a new small RX-only correlator, not the old shared-FFT design.
The complete `starlink_coarse25_detector` now includes score normalization,
fractional-frame folding and candidate qualification. It is not a deployable
receiver: IQ fanout/DMA, control, rate conditioning and clock-domain interfaces
remain to be integrated and qualified on the full board.

`starlink_coarse25_mac` computes an exact 16-tap complex dot product against
chronological signed CI16/Q15 coefficients and the exact input-window energy.
Coefficient format is sixteen hexadecimal words `{signed Q, signed I}`; the
MAC conjugates the coefficient. No saturation or truncation occurs in its
37-bit signed correlation and 36-bit unsigned energy outputs.

The pipeline separates history/coefficient selection, six real multiplies,
pair sums and accumulation. Result latency is 19 calculation clocks after an
input completing a supported window. Minimum input spacing is 20 clocks;
2.5 MS/s at 100 MHz supplies 40. No ready/backpressure output exists.

Reset discards history and pending work. Nonconsecutive input indices or an
arrival while computation is busy discard the pending result and restart
history with that new input. One-cycle gap/overrun flags report the event.
An integration must count/export these flags; this module alone does not
persist an error receipt. Missing valid pulses are idle clocks, not missing
accepted samples. Counter discontinuity is what identifies a missing sample.

`result_first_index` is the **first sample of the dot-product window**, in the
accepted 2.5 MS/s index domain. It is not already PSS frame time. Apply the
tracked template origin and front-end group delay/source mapping separately.
Never silently equate it with the original 15/60 MS/s source counter.

`coarse25_q15.mem` is the zero-residual-CFO upper pilot-band template from the
firmware's frozen `tools/starlink_coarse25.py`, rounded after multiplying the
unit-energy float template by 32767. A regression checks its exact bytes.
Useful narrow-band PSS in the recorded development episode required centering
before filtering using the earlier +512585.3848550797 Hz pilot alternative.
This ROM does not perform that centering or resolve pilot CFO aliases.

From the firmware root:

```sh
python -B -m pytest -q tests/test_starlink_coarse25_mac_rtl.py
```

The tests compare full-width RTL results against independent chronological
integer dot products, random/full-scale data, minimum and nominal spacing,
gaps, overloads, and reset during arithmetic. They do not establish real-time
RF detection or host transport.

`route_mac.tcl` preserves the initial standalone probes, including their
boundary-constraint limitations. `route_probe.tcl` uses real registered
stimulus and sink logic through `starlink_coarse25_mac_probe` so MAC input and
output paths are routable. The harness's 100 MHz clock origin is a declared
OOC assumption, not the clock placement of a full receiver design.
Both scripts refuse to overwrite artifact directories. Full-board routing
and actual radio tests remain mandatory regardless of a probe's result.

## Normalized score and complete detector

`starlink_coarse25_score` uses a 75-bit numerator/denominator interface to the
existing restoring divider, with exact ties-to-even uint8 quantization:
`round_even(255 * (re*re + im*im) / (input_energy * coefficient_energy))`.
Zero denominator returns zero, and values above unity saturate to 255.
The default ROM energy is 1073660387, checked by regression. Its output latency
is 11 clocks; the MAC/scorer combination produces a score 31 clocks after an
input completes a supported window. Arithmetic overload expires pending scores.

`starlink_coarse25_fold` advances phase by three modulo 10000 per consecutive
score. A default map has 290000 scores: 29 complete 4 ms groups, 87 nominal
750 Hz repeats, 116 ms. Every phase cell receives 29 contributions. Two banks
allow continuous fill while the previous bank is scanned and cleared. A reset
or fault sequentially clears 20000 RAM locations (200 us at 100 MHz); arriving
scores are not admitted during that initialization. IQ transport is unaffected.

The FPGA finds the peak of a circular three-cell sum, then accumulates
background sum, sum of squares and count excluding +/-150 cells around the
peak. It evaluates z >=8 exactly without division:
`(N*peak - sum)^2 >= 64*(N*sumsq - sum*sum)`, requiring a positive numerator and
the expected background count 9699. A candidate pulse is emitted for each
complete map; **only `detected=1` passes the confidence gate**. Below-threshold
peak coordinates are diagnostics, not a detected PSS.

The candidate phase is in one-third-inspection-sample units, relative to
`candidate_map_first_index`, modulo one nominal frame. It still names the
correlation-window start. The verified 15 -> 2.5 model converts it with:
`(first_canonical_center + 6*map_first_index + 2*phase + 17) mod 20000`.
Do not blindly apply that model-specific origin to a different analog/filter
profile; establish its actual source mapping first.

`route_detector.tcl` includes the complete arithmetic, maps and confidence gate
with registered source/sink boundaries. The final current probe at 100 MHz
has setup +0.837 ns and hold +0.067 ns, no missing clock/I/O constraints or
unconstrained internal endpoints. Detector resources are 1722 LUTs, 2301 FFs,
13 RAMB36 blocks and 36 DSPs. This still excludes receiver/IIO/filter integration.

Full 120 ms recorded-derivative replays are run by
`tools/starlink_coarse25_detector_replay.py` in the firmware repository. With IQ
present immediately after reset, the first admitted complete map starts at
score index 485; this initialization behavior is checked, not hidden. Two
positive and two negative windows match every integer map field exactly.
