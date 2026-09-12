# C251 bypass capture / coarse detector — experimental, DO NOT MERGE

`COARSE25_BYPASS=1` selects a **distinct** identity, `0x43323531` (C251),
version `0x00010000`. The default PIL1 implementation is unchanged. The existing
PIL1-only Linux driver intentionally rejects C251 until explicit support is
implemented and tested. This interface is simulated/routed at subsystem level,
not deployed or qualified on a complete board.

## Input and IQ

Only already centered **2.5 MS/s** CI16 is supported. There is no internal
mixing, decimation or digital filtering. Source/output rates both read 2500000;
ratio reads 1, edge reads 0 (centered), delay and history read 0. The historical
`canonical_*` pin names carry actual source coordinates in this mode, not a
fictional 15 MS/s grid. First/last admitted indexes differ by one per output.

The PIL1 command, FIFO, snapshot-generation, visit, finite-limit, fault and
drain contracts remain in force. The front input observation is registered
before admission. Source observations not yet promised to AXIS may be discarded
on STOP; already admitted IQ must drain unchanged. Host bytes are CI16, I then
Q, exactly 4 bytes/sample. No timestamps or detector words are interleaved.

The detector receives a registered copy of **each FIFO admission**, indexed
by the zero-based admitted count. It never observes AXIS drain timing and never
backpressures IQ. Reset/CLEAR/ARM reset detector arithmetic; capture faults hold
it reset. Normal STOP/finite completion do not cancel a completed map's pending
scan. Detector faults are counted separately and do not stop IQ export.

## Coherent latest-result mailbox

The same SNAPSHOT command and generation latch IQ counters and these additional
pre-edge words. They stay immutable until another snapshot/CLEAR. A result on
the snapshot edge appears in the **next** snapshot. Single control owner is
required. This is a latest-result mailbox, **not a lossless event queue**.

| Byte offset | Snapshot field |
| --- | --- |
| a0 | Candidate sequence since CLEAR, saturating u32; includes rejected maps |
| a4 | Flags: bit0 mailbox valid, bit1 detected, bit2 initializing, bit3 arithmetic held reset, bit4 counter saturation |
| a8 / ac | Candidate map-first inspection index, u64 low then high |
| b0 | Phase, 0..9999, in thirds of an inspection sample relative to map-first |
| b4 | Circular three-cell peak |
| b8 | Background sum, 28 meaningful bits |
| bc / c0 | Background squared sum, u64 with 43 meaningful bits |
| c4 | Background count, normally 9699 |
| c8 | Detector fault-pulse count since CLEAR, saturating u32 |
| cc | Scores per map; release default 290000 (116 ms) |
| d0 | Template profile/taps: 0x00010010, centered profile 1 / 16 taps |
| d4..fc | Reserved zero |

Sequence changes reveal missed mailbox results; software must report a jump,
not imply that every map was recorded. At saturation, stop/restart with a new
visit; do not compute a wrapped delta. Capture faults, detector faults, reset
and saturation qualify the entire receipt: `valid` alone is not usable evidence.
`detected=0` is an ordinary rejected map, not a PSS detection.

For exported sample j, raw source index is `capture_first_index + j`.
The candidate identifies the correlation-window-start phase:
`capture_first_index + candidate_map_first_index + phase/3`, modulo the nominal
frame period. **This is not yet a calibrated PSS epoch.** Template convention,
actual AD9361 response, RF centering and clock calibration still need verification.
Do not reuse the older 15->2.5 filter's 269-sample delay or +17 epoch correction.

## Implemented test boundary

Eight C251 integration tests exercise exact raw IQ, high 64-bit indexes, a real
second detector map against the independent integer reference, coherent held
snapshots, overflow, index gaps, explicit gaps/flush, and stop/drain/clear/rearm
with a finite limit. The testbench asserts that the detector's registered
IQ/index tokens equal actual FIFO admission. The map lifecycle test overrides
GROUPS to 1 for speed; the build IP exposes no such override and defaults to 29.
The existing 72 PIL1 capture tests still pass. Full 120 ms positive/negative
replays of the detector core are preserved separately; they are not a radio
capture or full C251 receiver test.

The 100 MHz registered-boundary C251 capture/detector probe routes with setup
+0.874 ns and hold +0.021 ns. All 12 timing-check categories are zero.
The capture block uses 2889 LUTs, 4174 FFs, 13 RAMB36 and 36 DSPs. This does not
include AD9361, CDC, DMA, PS7 clocks/interconnects or board IO timing. The first
unregistered external-input probe failed hold (-0.225 ns); its evidence is
retained. The registered harness measures internal fabric paths without claiming
that it qualifies physical external input timing.
