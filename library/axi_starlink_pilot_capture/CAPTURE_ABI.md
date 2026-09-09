# PIL1 fixed-frequency paired capture — experimental, DO NOT MERGE

This is the first integrated pilot capture profile, not the hopping ABI or a
qualified receiver. `STARLINK_PSS_PROFILE=paired-pilot` preserves coarse PSS and
the full-rate tracker, removes the legacy raw RX DMA/expansion peripherals,
and connects their canonical 15 MS/s acquisition tap to this pilot DDC and a
32-bit AXIS -> DDR DMA. The source rate remains 15/30/60 MS/s. **Upper edge only**;
the source conditioner/template banks are not yet runtime switchable.

PIL1 uses CPU clock 100 MHz throughout. Capture control is at `0x79050000`,
IRQ 55 (PS-11); pilot DMA replaces the *disabled* raw DMA at `0x7c400000`,
IRQ 57 (PS-13). Its source bus is AXIS, 32 bits; memory side is 64 bits. There
is no timestamp word interleaved into IQ and no TAG2 or legacy HOPS identity.
An opt-in matching device tree and new IIO driver are required before deploy.
The old detector device tree must never be used to claim pilot IIO support.

## Stream and lifecycle

Each AXIS beat is `{Q[15:0], I[15:0]}`, signed CI16, little-endian in memory.
Only fully supported pilot results enter the 32-sample output FIFO. It absorbs
short DMA stalls but cannot backpressure the ADC. Overflow/source gaps/invalid
control stop admission and raise a sticky fault IRQ. Already offered AXIS data
remains stable under stall and drains in order even after STOP or fault.
The accepted FIFO prefix is contiguous; a faulty session cannot restart and
silently append another segment. No TLAST or per-descriptor timestamp exists.

Prepare DMA before ARM. With PSS enabled, start the map engine **before** arming
pilot capture: a subsequent map-control flush interrupts shared conditioning
and invalidates an active pilot capture. Pilot enable keeps conditioning alive
at 30/60 MS/s even when map acquisition is disabled. Disabling pilot does not
disable map acquisition. Original non-pilot profiles retain their behavior.

The control word is decoded into a registered request before execution. AXI
write response follows execution, not initial decode. This adds one internal
clock of control latency without changing the register meanings. The source
counter, not host command-send time, remains the observation coordinate.

The complete DDC output observation (IQ, newest source index, visit and support)
crosses a one-clock register before capture admission. Signal coordinates and
filter group delay are unchanged. STOP, explicit source-gap/flush, registered
DDC-halt indications and capture faults suppress admission on their execution
edge; a staged but not yet admitted
word is discarded on termination. Already offered AXIS words remain stable and
drain normally. DDC-emitted telemetry may therefore lead capture accounting by
one staged output, or include a final output discarded on termination; it is not
a substitute for the admitted/delivered counters.
If a new internal DDC input fault coincides with admission of the final valid
staged prefix, auto-stop can precede capture's observation of registered DDC
halt. The DDC sticky fault survives flush even if capture fault bit0 stays zero.
Qualification must inspect **both** DDC and capture faults, including at finite
completion; an exact output count alone is insufficient.

Commands require a full 32-bit write, one command at a time:

- CLEAR (4): only inactive and FIFO empty. Clears session counters, faults,
  snapshots, and DDC telemetry. Preserves configured visit and sample limit.
- Configure nonzero visit ID and optional supported-output sample limit while
  clear/unused. Zero limit means continuous; positive limit stops admission
  automatically after exactly that many fully supported outputs.
- ARM (1): requires clear/unused, no fault, FIFO empty, nonzero visit ID.
  Absolute source index is never reset. Initial unsupported output is counted
  but not exported. A limit of 300000 exports exactly 120 ms on its output grid.
- STOP (2): idempotently stops admission and flushes pending DDC arithmetic.
  Keep DMA serviced until the output FIFO is empty. STOP is not a DMA completion
  or a guarantee that a partially filled IIO descriptor has reached the host.
- SNAPSHOT (8): atomically latches the complete pre-edge state. Repeated reads
  stay immutable until another snapshot or CLEAR. Single control owner required.

Invalid writes, including configuration while active/used, fail closed in the
fault register (AXI helper still returns OKAY). CLEAR cannot discard a stalled
AXIS promise. Cancellation must stop the source and drain with DMA still
serviced before aborting/reinitializing DMA; failure to drain is an explicit
recovery failure, not permission to relabel buffered data as a new capture.
The DMA/IIO integration must separately attest completed bytes and handle a
partial final descriptor. Counts at AXIS acceptance do **not** prove DDR write
completion, host receipt, disk persistence, or RF validity.

## Register map (byte offsets)

All counters/indexes are unsigned; 64-bit pairs are low word then high word.

| Offset | Access | Meaning |
|---|---|---|
| 00 | RO | Magic `0x50494c31` (PIL1) |
| 04 | RO | ABI `0x00010000` |
| 08 | WO | Command: ARM=1, STOP=2, CLEAR=4, SNAPSHOT=8 |
| 0c | RO | Live status: bit0 active, bit1 queued, bit2 fault, bit3 prefix exists, bit4 used |
| 10 | RO | Live sticky faults |
| 14 / 18 | RO | Source/output rates in Hz |
| 1c | RO | Source samples per output (6/12/24) |
| 20 | RW | Visit ID, nonzero at ARM |
| 24 | RO | Edge: 1=upper; lower not supported by this integrated profile |
| 28 / 2c | RO | Pilot group delay=269 / history span=538, canonical samples |
| 30 / 38 | snapshot, u64 | First/last admitted newest canonical index |
| 40 / 48 | snapshot, u64 | Admitted / AXIS-delivered sample counts |
| 50 | snapshot, u64 | Initial unsupported result count |
| 58 | snapshot, u64 | First fault diagnostic index (staged DDC output if valid, else canonical input) |
| 60 / 68 | snapshot, u64 | DDC accepted / emitted counts (includes unsupported) |
| 70 | snapshot | DDC saturation count |
| 74 | snapshot | DDC fault bits [7:0], ingress FIFO high water [15:8] |
| 78 / 7c | snapshot | Capture faults / status |
| 80 / 84 / 88 | snapshot | Visit ID / export FIFO high water / queued count |
| 8c..94 | snapshot | Reserved zero |
| 98 | RO | Snapshot generation, 0=invalid; wraps ffffffff -> 1 |
| 9c | RW | Supported output limit; 0=continuous; preserved by CLEAR |

Snapshot is pre-edge state, including a contemporaneous transfer only on the
next snapshot. Firmware must serialize snapshot/read sequences; reading the
generation before/after protects against another snapshot but not unauthorized
concurrent control. Reset/CLEAR invalidates snapshots.

Fault bits: 0 DDC halt; 1 explicit canonical gap/CDC overflow; 2 output FIFO
overflow; 3 nonconsecutive output index or wrong visit; 4 shared conditioner
flush while active; 5 invalid write; 6 exhausted capture counter. At output
overflow, diagnostic index is the first fully supported result not admitted.
For other faults it is only an observation coordinate, **not** a precise first
missing RF sample. DDC and capture fault fields remain distinct.

If first admitted index is `k`, delivered sample `j` has canonical signal-center
coordinate `k + 6*j - 269`. Multiply by `source_rate/15MHz` for the original
source coordinate. The 30/60 conditioner indexes already correct their own
delay: do not subtract it twice. All outputs use the absolute modulo-six phase.
Only arithmetic history is qualified here; RF settling guards must be applied
by the future hop controller. Full source counter mapping is not host wall time.

## Verification boundary

`tests/starlink_oracle/test_pilot_capture_rtl.py` simulates the **real** DDC,
AXI helper and capture FIFO, checks exact IQ against the independent integer
oracle, snapshots and high indexes, stalls/overflow with stable AXIS promises,
stop/drain/clear/rearm, invalid commands and source faults. Its rate parameter
checks rate reporting; the canonical stimulus is always 15 MS/s. Upstream
30/60 numerical composition is covered separately by the DDC tests.
The AXI bench checks exactly one execution and response per write, payload
stability through the registered request, and no premature acknowledgement.
All reserved command bits and partial write strobes are exercised fail-closed.

Full receiver route, real DMA behavior, IIO/PPU, digital hardware replay, RF
settling, lower/upper hops, and live GLRT/qualified PSS lock remain separate
gates. No firmware is eligible for deployment on the strength of these tests.
