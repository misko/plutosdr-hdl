# Fresh coarse25 arithmetic foundation — do not merge

This library is a new small RX-only correlator, not the old shared-FFT design.
It is not yet an FPGA detector or a deployable receiver: score normalization,
fractional-frame folding, candidate qualification, IQ fanout/DMA, control and
clock-domain interfaces remain to be integrated.

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
