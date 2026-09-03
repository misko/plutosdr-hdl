# Experimental Starlink PSS phase-map AXI bridge

> **DO NOT MERGE THIS EXPERIMENTAL DETECTOR IP TO HDL MAIN.**
>
> It belongs only to the `codex/starlink-rx-only-do-not-merge` firmware line.

This IP connects the continuous PSS phase-map accumulator to one AXI4-Lite
control port without placing backpressure on RX samples or normalized scores.
The map clock and AXI clock are independent. Two immutable map banks remain
owned by the acquisition domain until software explicitly releases one.

## Data movement

- Software receives a level interrupt whenever at least one synchronized map
  ready bit is set.
- A map read command crosses to `map_clk` through a one-outstanding toggle
  mailbox. Bank and index are held immutable until its response returns.
- Reading `MAP_DATA` waits for that response, returns one zero-extended map
  word, and auto-increments the selected phase index without wrapping.
- A release command is acknowledged only after the map domain has accepted or
  rejected it.
- Twenty-six telemetry words are captured atomically. The ABI 1.0 prefix is
  unchanged and ABI 1.1 appends ten health words. The CDC payload is compact:
  24 full words, two 10-bit candidate FIFO levels, and two ready bits, or 790
  bits rather than the 832-bit zero-extended AXI register view.
- Enable is a synchronized level. Flush is a toggle-transferred one-shot pulse.
- A map-local reset clears the acquisition/control epoch. It aborts any AXI
  register request already in flight with a zero read result so the bus cannot
  be stranded. Only `s_axi_aresetn` resets the AXI transport itself.

The included AXI front end supports independent AW and W arrival, holds B/R
responses under backpressure, and honors write strobes. It intentionally has no
short peripheral timeout: a legal `MAP_DATA` access includes a map-clock CDC
round trip. The attached phase-map core must still obey its bounded
one-request/one-response interface.

## Register contract

All offsets are bytes from the IP base. Reserved bits read as zero.

| Offset | Name | Access | Meaning |
|---:|---|:---:|---|
| `0x00` | `IDENTIFICATION` | RO | `0x50534d41` (`PSMA`) |
| `0x04` | `VERSION` | RO | `0x00010001` |
| `0x08` | `PHASE_BINS` | RO | Number of map bins; normally 20,000 |
| `0x0c` | `TILE_GEOMETRY` | RO | `[31:16]` frames, `[15:8]` map width, `[7:0]` banks |
| `0x10` | `CAPABILITIES` | RO | Bits 0–5: two banks, blocking data read, auto-increment, atomic snapshot, level IRQ, health snapshot |
| `0x14` | `CONTROL` | RW/WO | Bit 0 enable; writing bit 1 emits one flush pulse |
| `0x18` | `STATUS` | RO | Bit 0 control epoch live, 1 enable, 3:2 ready, 4 IRQ, 5 read pending, 6 release pending, 7 snapshot pending, 8 snapshot valid |
| `0x1c` | `MAP_SELECT` | RW | Bit 0 selects bank |
| `0x20` | `MAP_INDEX` | RW | Selected bin; out-of-range writes clamp to the last bin |
| `0x24` | `MAP_DATA` | RO | Blocking map word; increments `MAP_INDEX` on success and saturates at the last bin |
| `0x28` | `MAP_RELEASE` | WO | Write bit 0 to release `MAP_SELECT` |
| `0x2c` | `COMMAND_STATUS` | RO | Bit 0 read pending, 1 release pending, 2 last read error, 3 last release error |
| `0x30` | `SNAPSHOT_CONTROL` | WO | Write bit 0 to request an atomic snapshot |
| `0x34` | `SNAPSHOT_STATUS` | RO | Bit 0 valid, bit 1 pending |
| `0x38` | `SNAPSHOT_GENERATION` | RO | Saturating count of completed snapshots |
| `0x3c` | `SNAPSHOT_READY` | RO | Captured map-ready mask in bits 1:0 |
| `0x40` | `SNAPSHOT_MAP_GENERATION_0` | RO | Captured bank-zero generation |
| `0x44` | `SNAPSHOT_MAP_GENERATION_1` | RO | Captured bank-one generation |
| `0x48` | `SNAPSHOT_START_INDEX_0_LO` | RO | Captured bank-zero start index `[31:0]` |
| `0x4c` | `SNAPSHOT_START_INDEX_0_HI` | RO | Captured bank-zero start index `[63:32]` |
| `0x50` | `SNAPSHOT_START_INDEX_1_LO` | RO | Captured bank-one start index `[31:0]` |
| `0x54` | `SNAPSHOT_START_INDEX_1_HI` | RO | Captured bank-one start index `[63:32]` |
| `0x58` | `SNAPSHOT_ACCEPTED` | RO | Captured accepted-score count |
| `0x5c` | `SNAPSHOT_DISCARDED` | RO | Captured discarded-score count |
| `0x60` | `SNAPSHOT_DISCONTINUITY` | RO | Captured discontinuity-abort count |
| `0x64` | `SNAPSHOT_PUBLISHED` | RO | Captured map-publication count |
| `0x68` | `SNAPSHOT_OVERRUN` | RO | Captured acquisition map-overrun count |
| `0x6c` | `SNAPSHOT_PROTOCOL_ERROR` | RO | Captured score-protocol error count |
| `0x70` | `SNAPSHOT_ARITHMETIC_OVERFLOW` | RO | Captured accumulation-overflow count |
| `0x74` | `SNAPSHOT_READ_ERROR` | RO | Captured map-core read-error count |
| `0x78` | `SNAPSHOT_RELEASE_ERROR` | RO | Captured map-core release-error count |
| `0x7c` | `BRIDGE_READ_ERROR` | RO | Live saturating bridge read-error count |
| `0x80` | `BRIDGE_RELEASE_ERROR` | RO | Live saturating bridge release-error count |
| `0x84` | `SNAPSHOT_REQUEST_OVERRUN` | RO | Live saturating count of snapshot requests made while pending |
| `0x88` | `SNAPSHOT_HEALTH_FLAGS` | RO | Captured sticky detector flags in bits 11:0 and ingress-overflow sticky in bit 12 |
| `0x8c` | `SNAPSHOT_INGRESS_DROPPED` | RO | Captured saturating RX-to-acquisition FIFO drop count |
| `0x90` | `SNAPSHOT_INGRESS_FIFO` | RO | Captured maximum FIFO level `[31:16]` and current level `[15:0]` |
| `0x94` | `SNAPSHOT_SCHEDULER_GAP` | RO | Captured scheduler gap count |
| `0x98` | `SNAPSHOT_SCHEDULER_INDEX_ERROR` | RO | Captured scheduler absolute-index error count |
| `0x9c` | `SNAPSHOT_SCHEDULER_OVERFLOW` | RO | Captured overlap scheduler retention/queue overflow count |
| `0xa0` | `SNAPSHOT_DETECTOR_FAULT` | RO | Captured aggregate detector-fault episode count |
| `0xa4` | `SNAPSHOT_PHASE_DISCONTINUITY` | RO | Captured score phase/index discontinuity count |
| `0xa8` | `SNAPSHOT_DENOMINATOR_ZERO` | RO | Captured normalized-score zero-denominator count |
| `0xac` | `SNAPSHOT_CANDIDATE_FIFO` | RO | Captured maximum candidate FIFO occupancy `[25:16]` and current occupancy `[9:0]`; padding is zero |

`SNAPSHOT_HEALTH_FLAGS` uses bit 0 for aggregate detector fault, bits 1–3
for scheduler gap/index/overflow, bits 4–9 for forward FFT, kernel join,
product overflow, inverse FFT, forward-exponent, and candidate-path faults,
bit 10 for score phase/index discontinuity, bit 11 for a zero denominator,
and bit 12 for an ingress FIFO drop. Detector flags are sticky for the reset
epoch; counters are saturating.

Writing `CONTROL=2` disables acquisition while flushing it. Software that wants
to remain enabled must write `CONTROL=3`.

## Intended software sequence

1. Verify `IDENTIFICATION`, `VERSION`, geometry, and capabilities.
2. Write `CONTROL=1` and wait for IRQ or nonzero `STATUS[3:2]`.
3. Request a snapshot and wait for `SNAPSHOT_STATUS.valid`.
4. Choose a ready bank from the coherent snapshot, write `MAP_SELECT`, and set
   `MAP_INDEX=0`.
5. Read exactly `PHASE_BINS` `MAP_DATA` words into an ARM buffer.
6. Run bounded candidate extraction on that buffer.
7. Write `MAP_RELEASE=1` only after the copy is complete.

At the nominal 15 MS/s geometry, one 20,000-by-16-bit map is 40,000 bytes and a
64-frame tile arrives about every 85.3 ms. This bridge therefore exposes about
468.75 kB/s of map data rather than the approximately 60 MB/s raw complex-IQ
stream. It does not yet implement candidate extraction or frame-lock policy.

## Verification

Run functional simulations:

```sh
./run_tests.sh
```

They exercise integrated map publication/read/release at four map-clock ratios
(62.5, about 71.4, 100, and 125 MHz against 100 MHz AXI), all 26 atomic
snapshot words, a 10 MHz snapshot CDC stress case, split AW/W ordering, byte
strobes, AXI response backpressure, invalid commands, flush, and reset abort.

Run the physical evidence gate with Vivado 2022.2:

```sh
./run_ooc.sh /tmp/starlink-pss-phase-map-axi-ooc
```

The gate synthesizes, places, and routes for `xc7z010clg400-1` at 100 MHz on
both clocks. It requires zero methodology violations, no unexpected timing
categories, zero critical CDC rows, exactly the known CDC report classes,
three met bundled-data skew constraints, complete 790/1580/790-bit snapshot
storage, nonnegative routed setup/hold slack, no BRAM/DSP, and explicit LUT/FF
caps. These figures cover the bridge only; the phase-map BRAMs are accounted
for by the acquisition-core evidence and later full-system implementation.
