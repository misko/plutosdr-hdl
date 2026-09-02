# Experimental Stage-15 exact PSS tracker — do not merge to HDL main

`axi_starlink_pss_tracker` is the software boundary for one RX-only, one-
candidate-at-a-time exact tracking pipeline. Software loads a 66-tap CI16
template, schedules a future center in the capture stream's 64-bit sample
counter, and receives one atomic 26-word packet containing the exact best lag
from -30 through +30. The underlying arithmetic engine still produces the
historical 65-tuple `-32..+32` trace; `TRACK_ONE` drains the four guard tuples
and reduces exactly the frozen 61-lag tracking aperture.

This is a **15 MS/s milestone**, not an autonomous Starlink acquisition claim.
The IP rejects every `RATE_MSPS` value other than 15 at elaboration. It does not
contain or trust the older repeated-delay diagnostic, search an unbounded
stream, identify SSS, qualify repeated-frame cadence, compensate carrier
offset, or prove that a winner is Starlink. Those are later acquisition and
qualification stages.

The complete experimental firmware remains on
`codex/starlink-rx-only-do-not-merge`. Reusable host/radio setup support belongs
in PPU main, but this FPGA implementation must not be merged into HDL or
firmware main.

## Stream and clock contract

The post-decimator stream accepts one CI16 sample when
`sample_enable && sample_strobe` is true. `sample_index` and
`sample_timestamp` name that same accepted beat. The Pluto Stage-15 block
design drives both from the existing 64-bit capture timestamp counter, so a
scheduled center timestamp equals its center index in that integration.

The AXI clock is also the tracking engine clock. Capture occurs in the AD9361
sample-clock domain and crosses into the engine through an abort-atomic,
double-buffered capture bridge. AXI reset asserts asynchronously into both
domains and releases through independent synchronizers. Sample reset holds the
sample side synchronously and crosses through a two-stage synchronizer to hold
the AXI/engine side. It therefore flushes AXI commands, FIFO ownership, partial
captures, and unpublished results even if the PS AXI reset remains released.

Software schedules from `CURRENT_INDEX_LO/HI`. Reading the low word snapshots
both halves after a Gray-coded CDC. The observed value can lag the live stream
by synchronizer latency, so software must schedule comfortably beyond the
reported index. Hardware rejects a command with less than 64 samples of lead.

## Register map

The Pluto design maps this block at `0x79030000` with a 4 KiB aperture. All
locations are 32-bit. Writes are acknowledged after the wrapper has copied the
payload into its one-entry command buffer; overrun counters expose writes made
while that buffer is occupied.

| Offset | Name | Access | Meaning |
|---:|---|:---:|---|
| `0x00` | `IDENTIFICATION` | R | `0x50535354` (`PSST`) |
| `0x04` | `VERSION` | R | `0x00010001` (ABI 1.1) |
| `0x08` | `RATE_MSPS` | R | `15` |
| `0x0c` | `GEOMETRY` | R | `{0, lags=61, capture=130, taps=66}` |
| `0x10` | `CAPABILITIES` | R | bit 0 exact score, bit 2 host scheduled, bit 3 atomic packet, bit 4 atomic telemetry |
| `0x14` | `STATUS` | R | live state described below |
| `0x18` | `CURRENT_INDEX_LO` | R | current index low; snapshots both halves |
| `0x1c` | `CURRENT_INDEX_HI` | R | high half of the last low-word snapshot |
| `0x20` | `CANDIDATE_REQUEST` | R/W | software request ID |
| `0x24` | `CANDIDATE_CENTER_LO` | R/W | center index low |
| `0x28` | `CANDIDATE_CENTER_HI` | R/W | center index high |
| `0x2c` | `CANDIDATE_TIMESTAMP_LO` | R/W | center timestamp low |
| `0x30` | `CANDIDATE_TIMESTAMP_HI` | R/W | center timestamp high |
| `0x34` | `CANDIDATE_CONTROL` | W | bit 0 copies staged command into buffer |
| `0x38` | `CANDIDATE_COMMAND_OVERRUN` | R | saturated rejected-write count |
| `0x3c` | `COEFFICIENT_WRITE_OVERRUN` | R | saturated rejected-write count |
| `0x40` | `COEFFICIENT_DATA` | W | `{Q[15:0], I[15:0]}`; enqueues one tap |
| `0x44` | `COEFFICIENT_CONTROL` | W | bit 0 clear shadow bank; otherwise bit 1 commit |
| `0x48` | `COEFFICIENT_GENERATION` | R/W | generation attached to the next commit |
| `0x4c` | `ACTIVE_COEFFICIENT_GENERATION` | R | committed generation |
| `0x50` | `RESULT_WORD_INDEX` | R/W | packet word 0..25; larger values clamp to 25 |
| `0x54` | `RESULT_WORD_DATA` | R | selected synchronous result-RAM word |
| `0x58` | `RESULT_CONTROL` | W | bit 0 releases the published result bank |
| `0x5c` | `RESULT_STATUS` | R | bits 28:24 words=26, bit 1 bank, bit 0 available |
| `0x60` | `ACTIVE_ENERGY_LO` | R | signed 48-bit template energy low |
| `0x64` | `ACTIVE_ENERGY_HI` | R | sign-extended template energy high |
| `0x68` | `TELEMETRY_CONTROL` | W | bit 0 requests one atomic counter snapshot |
| `0x6c` | `TELEMETRY_STATUS` | R | bit 0 valid, bit 1 busy |
| `0x70` | `TELEMETRY_GENERATION` | R | saturated snapshot generation |

`STATUS` uses bit 0 reset released, bit 1 candidate ready, bit 2 command
buffered, bit 3 coefficients valid, bit 4 coefficient write ready, bit 5
coefficient commit ready, bit 6 result available, bit 7 IRQ, bits 14:8 shadow
tap count, bits 16:15 free result-bank mask, bits 19:17 candidate queue room,
bit 20 synchronized capture active, and bit 21 synchronized candidate pending.

Debug counters occupy `0x80` through `0xe0`:

| Offset | Counter | Offset | Counter |
|---:|---|---:|---|
| `0x80` | queue overrun | `0xbc` | engine consumed |
| `0x84` | admitted | `0x88` | completed capture |
| `0x8c` | rejected | `0x90` | late |
| `0x94` | duplicate | `0x98` | overlap |
| `0x9c` | aborted | `0xa0` | valid-gap abort |
| `0xa4` | index-jump abort | `0xa8` | timestamp abort |
| `0xac` | capture published | `0xb0` | capture abort discard |
| `0xb4` | capture buffer overrun | `0xb8` | capture protocol error |
| `0xc0` | correlator bound error | `0xc4` | reducer jobs processed |
| `0xc8` | reducer results emitted | `0xcc` | reducer invalid tuple |
| `0xd0` | reducer bound error | `0xd4` | reducer protocol error |
| `0xd8` | result published | `0xdc` | result overrun |
| `0xe0` | result consumed |  |  |

Offsets `0x84` through `0xb8` expose only the last immutable sample-clock
telemetry snapshot. A toggle request captures all fourteen counters on one
sample-clock edge; the 448-bit payload crosses through two destination stages
and is published only after the acknowledgement plus two settling cycles.
Software must serialize requests: read the generation, write control bit 0,
then wait for `valid && !busy` and a changed generation before reading the
snapshot. Counters outside that range are native to the AXI/engine clock.

## Focused validation

Run the self-checking AXI/core simulation from this directory:

```sh
./run_tests.sh
```

After a routed Pluto build, validate timing, hold, the tracker Gray-bus skew,
the complete synchronizer/payload structure, exact 3-DSP and 5.5-BRAM tracker
footprint, absence of TX DMA, routing completeness, and tracker-specific CDC:

```sh
vivado -mode batch -source validate_routed.tcl -tclargs \
  ../../projects/pluto/pluto.runs/impl_1/system_top_routed.dcp \
  /tmp/starlink-pss-tracker-routed
```

The earlier 65-lag ABI 1.0 Vivado 2022.2 build on 2026-09-02 passed with setup WNS
`+0.519 ns`, hold WHS `+0.014 ns`, one met Gray-bus-skew constraint
(`1.590 ns` actual against `10.000 ns`), zero tracker Critical CDC rows, and
zero routing errors. The complete RX-only shell uses 8,906 LUTs (50.60%),
11,531 registers (32.76%), 8.5 BRAM tiles (14.17%), and 31 DSPs (38.75%). The
tracker hierarchy accounts for exactly 3 DSP48E1s, 3 RAMB18E1s, and 4
RAMB36E1s (5.5 BRAM tiles). That build and every firmware package derived from
it are now **superseded and ineligible for radio use**: retained-window replay
showed three outer-aperture winner mismatches. These hashes remain only as an
audit trail; ABI 1.1 must be freshly routed and packaged:

| Artifact | SHA-256 |
|---|---|
| `system_top_routed.dcp` | `64785b8b5a4e9e5af1ead62d659f4078076aab98c42fc639fb95b2fe4548160a` |
| `system_top.bit` | `0e783199a0a56c7742d6079daeb4ebc6ac4750e58f543d4020529275a39b3e49` |
| `system_top.xsa` | `44dd4c0525fa67630dbb0f225999d0498a62baf27991fca497d6cfba96ff565d` |

## Host sequence

1. Verify ID, exact ABI 1.1, rate, geometry, and capabilities.
2. Write coefficient clear, then exactly 66 packed CI16 taps.
3. Write a nonzero generation, request commit, and poll active generation.
4. Read current index low then high. Choose a center with ample lead; in the
   Pluto integration use the same value for center timestamp.
5. Stage request, center, and timestamp, then write candidate-control bit 0.
6. Atomically snapshot the counters, then wait for the level
   IRQ/result-available indication.
7. Select and read all 26 result words in any order. The bank is immutable.
8. Atomically snapshot the counters again and require the declared success
   deltas plus zero error deltas.
9. Write result-control bit 0 only after the complete packet is validated.

The result packet is:

| Word | Field |
|---:|---|
| 0 | magic `0x31535350` (`PSS1` in little-endian bytes) |
| 1 | bits 28:24 length 26, 23:16 ABI 1, bit 1 includes `Eh`, bit 0 score valid |
| 2 | request ID |
| 3..4 | scheduled center index |
| 5..6 | scheduled center timestamp |
| 7 | sign-extended winner lag |
| 8..9 | winner sample timestamp |
| 10 | coefficient generation |
| 11..12 | sign-extended 48-bit complex correlation real part |
| 13..14 | sign-extended 48-bit complex correlation imaginary part |
| 15..16 | sign-extended 48-bit sample energy `Ex` |
| 17..18 | sign-extended 48-bit template energy `Eh` |
| 19 | saturation-event count |
| 20..22 | exact 77-bit score numerator `|C|^2` |
| 23..25 | exact 69-bit score denominator |

TRACK_ONE cancels the positive, job-constant `Eh`, so packet bit 1 is zero,
words 17..18 retain the diagnostic value, and the exact winner comparison is
`|C|^2/Ex`. No division or approximate score is used.

The fail-closed structure check rejects rate broadening, an early AXI result
acknowledgement, loss of the coordinated reset/Gray index/level IRQ contracts,
or insertion of the repeated-delay diagnostic. The self-checking asynchronous-
clock simulations perform real AXI transactions, load coefficients, capture
130 indexed samples, evaluate 65 raw tuples and the 61-lag qualified aperture,
check atomic telemetry and every packet word, release the bank/IRQ, and prove
that a sample-domain reset flushes the entire epoch. A second wrapper-level test
replays all 210 provenance-bound retained windows and matches the frozen
float-oracle lag in 210/210 cases.

Portable Icarus simulation is intentionally slow because variable-index memory
reads expand the explicit 66-tap engine sensitivity set. This is simulator
cost, not a 15 MS/s hardware throughput estimate. IP packaging, out-of-context
synthesis, full routed timing, CDC review, and hardware qualification are
separate required gates.
