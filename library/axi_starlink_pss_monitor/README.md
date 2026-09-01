# Experimental Starlink PSS candidate monitor — do not merge to HDL main

`axi_starlink_pss_monitor` is a read-only diagnostic on the protected
RX-only experiment branch. It observes the post-decimator CI16 stream and the
same 64-bit sample counter used by capture timestamping. It has no transmitter,
interrupt, or control output and cannot alter the DMA/timestamp datapath.

An event means only that one sliding window crossed a repeated-delay metric.
It is **not an exact PSS match, frame alignment, or evidence of a Starlink
signal**. Exact template correlation and repeated-frame cadence qualification
remain mandatory.

## Fixed 15 MS/s build policy

The Pluto block design instantiates one compile-time geometry:

- `RATE_MSPS = 15`
- lag `D = 8`, symbol length `S = 66`, correlation length `W = 58`
- `THRESHOLD_Q15 = 24576` (`0.75`)
- `MIN_WINDOW_ENERGY = 1`

These values are immutable at runtime and readable through AXI. The reusable
RTL still rejects any compile-time rate other than 15, 30, or 60 MS/s, but this
integration deliberately builds 15 only. A rate change requires a new bitstream
and a new qualification campaign.

The 0.75 threshold is intentionally not tuned downward to manufacture hits. In
the exact lower-edge 15 MS/s projected-PSS CI16 fixture its lag-8 metric is
approximately 0.429, so the fixture correctly produces no event. Independent
real-capture characterization is weaker still. This is useful negative evidence:
the repeated-delay stage is diagnostic and a more sensitive gate or exact
correlator is required before this path can serve acquisition.

## Stream and timestamp contract

`adc_valid && adc_enable` accepts one post-decimator I/Q sample with
`adc_sample_index`. The index is the current value of `counter_timestamp/Q`, so
the reported symbol-start index names a sample in the same counter space as the
captured data.

- A valid gap while enable remains asserted pauses all detector and metric
  pipeline state. The timestamp counter also pauses because its clock-enable is
  post-decimator valid.
- Deasserting enable flushes all history and in-flight scores.
- A non-consecutive accepted sample index flushes history; the discontinuous
  sample becomes the first sample of a fresh history.
- Reset clears detector and event accounting state.

Only fan-out connections were added. Existing cpack, timestamp insertion, and
DMA connections are unchanged.

## Register map

The block is mapped at `0x79030000`; its occupied AXI aperture is 4 KiB and does
not overlap the adjacent AD9361 core at `0x79020000`. All registers are 32-bit,
read-only. Writes are acknowledged and ignored.

| Offset | Name | Value |
|---:|---|---|
| `0x00` | `IDENTIFICATION` | `0x50535343` (ASCII `PSSC`) |
| `0x04` | `VERSION` | `0x00010000` |
| `0x08` | `RATE_MSPS` | compile-time integer |
| `0x0c` | `THRESHOLD_Q15` | compile-time Q1.15 threshold |
| `0x10` | `MIN_ENERGY_LO` | minimum energy bits 31:0 |
| `0x14` | `MIN_ENERGY_HI` | minimum energy bits 40:32 |
| `0x18` | `GEOMETRY` | `{5'b0, W[8:0], S[8:0], D[8:0]}` |
| `0x1c` | `METRIC_WIDTHS` | `{16'b0, numerator_width=83, denominator_width=82}` |
| `0x20` | `GENERATION` | CPU-domain snapshot generation |
| `0x24` | `EVENT_COUNT_LO` | event count bits 31:0 |
| `0x28` | `EVENT_COUNT_HI` | event count bits 63:32 |
| `0x2c` | `SAMPLE_INDEX_LO` | latest candidate start bits 31:0 |
| `0x30` | `SAMPLE_INDEX_HI` | latest candidate start bits 63:32 |
| `0x34` | `METRIC_NUM_LO` | exact numerator bits 31:0 |
| `0x38` | `METRIC_NUM_MID` | exact numerator bits 63:32 |
| `0x3c` | `METRIC_NUM_HI` | zero-padded numerator bits 82:64 |
| `0x40` | `METRIC_DEN_LO` | exact denominator bits 31:0 |
| `0x44` | `METRIC_DEN_MID` | exact denominator bits 63:32 |
| `0x48` | `METRIC_DEN_HI` | zero-padded denominator bits 81:64 |

Unimplemented locations read as zero. `EVENT_COUNT` counts every source event.
When candidates arrive faster than the CDC round trip, intermediate payloads
may be coalesced, while the final snapshot carries the newest payload and the
full count.

The geometry words for the supported compile-time rates are `0x00e88408`
(15 MS/s), `0x01d10810` (30 MS/s), and `0x03a21020` (60 MS/s). Nine-bit fields
are required because the 60 MS/s symbol contains 264 samples.

## CDC and software seqlock

The ADC domain writes a bundled-data mailbox, toggles a request, and holds all
293 payload bits stable until a two-flop-synchronized acknowledgement returns.
The CPU domain synchronizes the request, captures every payload register on one
clock edge, increments `GENERATION`, and acknowledges. Constraints mark both
toggle synchronizers asynchronous and bound mailbox delay/bus skew to 10 ns,
one Pluto `sys_cpu_clk` period.

Software must read a self-consistent snapshot as follows:

1. Read `GENERATION` into `g0`.
2. Read event count, sample index, numerator, and denominator words.
3. Read `GENERATION` into `g1`.
4. Accept the payload only when `g0 == g1`; otherwise retry from step 1.

A zero generation means no snapshot has been published since CPU reset.

## Focused validation

Run from this directory:

```sh
bash run_tests.sh
```

The self-checking Icarus suite covers the exact register map and ignored writes,
asynchronous-clock CDC/coalesced event accounting, all 83/82 metric bits, zero,
deterministic noise, wrong period, enabled valid gaps, disable boundaries,
timestamp discontinuity, one positive structural candidate, and the exact
projected-PSS negative characterization fixture. The fixture is derived from
the frozen oracle whose complex64 identity is
`4edc636f6b176c651a3547cbd8254429fda41f35c677bc30801eeba71c325a21`.

After a routed Pluto build, validate that all 293 bundled-data paths and four
toggle synchronizer registers survived implementation and that the mailbox
max-delay constraint is met:

```sh
vivado -mode batch -source validate_routed.tcl -tclargs \
  ../../projects/pluto/pluto.runs/impl_1/system_top_routed.dcp \
  /tmp/starlink-pss-routed-reports
```

The canonical local Vivado 2022.2 build on 2026-09-01 passed that validator.
The complete RX-only shell used 6,417 LUTs, 9,187 registers, 1,012 LUT-memory
cells, 3 BRAM tiles, and 49 DSP48E1s. Setup WNS was +1.277 ns and hold WHS was
+0.016 ns; all 15,945 routed nets were complete. The monitor hierarchy itself
synthesized to 1,953 LUTs, 2,013 registers, 434 LUT-memory cells, no BRAM, and
21 DSP48E1s. Its mailbox max-delay slack was +8.019 ns and bus-skew slack was
+8.238 ns. The full design retained only the two pre-existing critical
timestamp CDC rows and the monitor added exactly 293 CDC-15 payload rows, two
CDC-3 toggle rows, and no critical row. The routed checkpoint SHA-256 was
`c81e64767b02ca1a535f487a6dc7c64df7f497d975623c064f94f479ac069f9e`.
