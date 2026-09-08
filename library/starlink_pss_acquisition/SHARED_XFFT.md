# Shared transform island experiment — DO NOT MERGE / NOT DEPLOYABLE

The candidate removes a second transform core, not either PSS detection stage.
`starlink_pss_iq_to_score_shared` keeps ingress, overlap scheduling, energy,
kernel multiplication and normalized scoring at 100 MHz. Only the generated
XFFT and its adapter run at 200 MHz. Pilot IQ and full-rate refinement are not
changed. An explicit `STARLINK_PSS_SHARED_XFFT=1` selector now integrates the
candidate ONLY in the `paired-pilot` 15 MS/s build. It is not deployable until
full fit/timing/CDC and matched software qualify. The default
`starlink_pss_iq_to_score` still owns the qualified pair of dedicated FFTs.

## Ownership and numerical contract

- `starlink_pss_block_mailbox` commits a complete, framing-checked 512-word
  block. One dual-clock RAM carries 36-bit IQ; a held metadata bus accompanies
  a two-flop synchronized request toggle. The sender cannot reuse storage until
  the final output handshake returns an acknowledged toggle. It is a
  backpressured transform interface, NOT a replacement for loss-aware ADC CDC.
- Metadata is captured at the first input word, checked throughout the block,
  and held through acknowledgment. A malformed word may write unpublished RAM,
  but cannot commit the block. This removes the wide comparator from RAM write
  enable without weakening the publication gate. RAM contents need no reset.
- Either reset purges both domains. Partial input, stalled complete output,
  and partially consumed blocks are all discarded as an explicit reset epoch.
  A caller must record such invalidity; a reset is not an uninterrupted stream.
- `starlink_pss_shared_xfft_service` carries input metadata
  `{inverse, block_start[63:0], forward_exponent[4:0]}` and adds the actual
  transform exponent to output bits `[4:0]`. It reserves return storage before
  starting a transform. The same strict adapter validates XFFT framing, status,
  exponents and index. Direction changes only under a complete core reset.
- The coarse composition permits one in-flight forward and one in-flight
  inverse block. It retains the original energy/exponent/scoring checks. An
  independent FFT reset during active acquisition latches global quarantine;
  deasserting reset alone cannot erase it. Disable/flush is required to recover.
- Inside the shared composition, the forward-fault wire represents a
  service-wide error; it does not identify direction. The integrated health
  mapper explicitly publishes that cause in bit 14, NOT forward bit 4 or
  inverse bit 7. The opt-in wrapper advertises PSMA ABI 1.5 and capability bit
  8 (`0x13f` total). All default rate-dependent ABIs remain unchanged. The
  matched experimental kernel and explicit PPU opt-in now understand 1.5;
  default host readers still reject it. This is not firmware qualification.

## Measured evidence, 2026-09-08

1. The existing radix-4 burst BFP18 core (`C_ARCH=1`) routes internally at
   200 MHz: 1283 LUTs, 3119 FFs, 17 DSPs, 11 RAMB18s; setup/hold slack
   +0.168/+0.053 ns. The IP generator emits a fixed 10 ns OOC clock despite
   the 200 MHz configuration. The probe explicitly implements at 5 ns and
   retains that override and its XDCC diagnostics. Unplaced boundary hold
   failures remain unqualified; this is NOT full-receiver timing.
2. An idealized historical one-core composition with ALL logic at 200 MHz
   matches 1341 frozen scores and sustains 64 blocks/28608 scores at true
   15 MS/s input. Each transform pair takes 3632 fast clocks (18.16 us).
   This idealized result is not evidence about a 100 MHz kernel/score path.
3. Real mailbox tests cover 4/8/512-word geometries, 100->200 and 200->100 MHz,
   unrelated and coincident clocks, stalls, four framing failures, ten
   independent resets including two mid-read purges. All 12 tests pass.
4. Final 512x36/70-bit-metadata mailbox probes use 71 LUTs, 185 FFs and one
   RAMB18 each. Internal setup/hold slack is +0.904/+0.104 ns (100->200) and
   +0.227/+0.084 ns (200->100). The actual return service uses 75 metadata bits;
   its integrated implementation still requires measurement. CDC reports retain
   the expected 70 clock-enable-controlled held-bus crossings; no blanket
   asynchronous clock-group exceptions are used. These probes do NOT qualify
   OOC boundary setup/hold, integrated CDC, or the complete service/receiver.
5. The actual 100/200/100 MHz service passes 66 jobs/33792 exact transform words,
   output stalls, a fault after partial return-buffer filling, input framing
   failure and recovery via each reset. Maximum saturated transform-pair
   interval in that benchmark is 2972 slow clocks (29.72 us). Its already
   prepared input vectors do not establish full acquisition throughput.
6. The COMPLETE coarse composition using both real mailbox crossings, the
   100 MHz kernel/score path and 200 MHz XFFT matches all forward/product/inverse
   intermediates and 1341 frozen scores. It passes output stalls and global
   fault recovery, plus independent FFT-reset quarantine/recovery. A separate
   canonical 15 MS/s run returns all 28608 ordered scores over 64 overlap blocks
   with candidate FIFO high water 356/512 and no loss/fault. This ~1.96 ms
   simulation is NOT a 120 ms/300 s soak or full-receiver hardware evidence.

## Reproduction and next gate

Use Vivado 2022.2 and the frozen vector directory generated by
`tools/generate_starlink_pss15_pipeline_vectors.py`. Each simulation must contain
its positive bench PASS marker; a runner completion line alone is insufficient.

- `measure_shared_xfft_clock.tcl OUTPUT 200`
- `measure_block_mailbox_clock.tcl OUTPUT INPUT_MHZ`
- `simulate_shared_xfft_service.tcl OUTPUT numeric 200 VECTOR_DIRECTORY`
- `simulate_shared_xfft_service.tcl OUTPUT capacity 200`
- `simulate_shared_xfft_mailbox.tcl OUTPUT VECTOR_DIRECTORY 64`
- `simulate_iq_to_score_shared.tcl OUTPUT numeric VECTOR_DIRECTORY`
- `simulate_iq_to_score_shared.tcl OUTPUT capacity`
- `simulate_iq_to_score_shared.tcl OUTPUT capacity 4096` (122 ms source span;
  completed on the older f85f0888 baseline, not current mailbox/control RTL)
- Firmware pytest: `tests/starlink_oracle/test_block_mailbox_rtl.py`

The opt-in wrapper/IP/block-design integration uses the existing PS FCLK1
200 MHz clock and local reset-release synchronizers. Declarative packaged XDC
constrains the four ownership crossings, service fault, and both held metadata
buses; the initial Tcl-loop XDC was rejected by the synthesis parser and is
not valid timing evidence. `projects/pluto/shared_xfft_impl_gate.tcl` checks
the actual 10/5 ns endpoint clocks, all surviving metadata endpoints and their
timing requirements before placement. It retains CDC/exception reports without
blanket clock-group waivers. It is NOT a route/timing qualification. The held
metadata CDC-15 diagnostics and reset fan-out CDC-11 diagnostics must still be
reviewed against the integrated reset/publication protocol before deployment.

The shared phase-map replay also matches 1341 scores and 447 exact map entries
with a reduced three-by-447 test geometry. A service fault after partial tile
accumulation aborts the tile, publishes no partial map, and latches health bit
14 without directional bits. The default dedicated-core map replay also
passes. This small test does not qualify production 64x20000 geometry or dwell
sensitivity. Reproduce using `simulate_iq_to_phase_map_xfft.tcl OUTPUT VECTORS 1`
(use final argument 0 for the default regression).

Next: finish fresh complete paired-receiver placement/routing/timing. Preserve
both PSS stages and exact pilot samples. Do not count standalone savings as a
whole-design fit. Then qualify the matched DMA/IIO image on .18 before deploying
.17 through serial-locked PPU network flashing. Same-observation live blind host
GLRT AND qualified FPGA PSS timing lock remain mandatory, followed by the
120 ms/eight-target/300 s and 30/60 MS/s gates. No radio was touched here.

The first full integrated builds remained **placement failures**. The
correctly packaged/clock-audited threshold-4 build synthesizes to 13546 LUTs,
18856 FFs, 48.5 BRAM tiles and 48 DSPs; placement requires 2372 currently
unplaced slices where 2361 remain available (11 short). Threshold 8 reduces
control sets from 449 to 373 but needs 2385 versus 2363 available (22 short),
so it is not adopted. Threshold 4 remains default. The earlier Tcl-XDC attempt
was 17 short and cannot be used as properly constrained timing evidence.
No route, bitstream, IIO capture or live GLRT/FPGA lock is qualified by these
builds. See the firmware integration checkpoint report for source/evidence pins.

## Common reset release, pilot RAM, and control timing checkpoint

The service now supplies one common reset-release pair to both mailboxes and
the controller. Each release includes both raw reset epochs. The mailbox's
default independent reset synchronization remains available; the service alone
opts into `RESET_RELEASE_EXTERNAL=1`. The integrated gate requires exactly
eight common synchronizer flops and no duplicate mailbox release chains.
Ninety-six mailbox tests cover both choices, both 70/75-bit metadata widths,
and two-cycle release skew on either side. The six critical reset-fanout CDC
findings in the earlier full
build disappear; held-metadata findings remain visible for protocol review.

That change reduced the placement shortfall to two slices. Preserving the
pilot pacer's synchronous RAM read boundary then replaced its accidental
LUTRAM implementation with one RAMB18. A routed-checkpoint audit confirms
36-bit simple-dual-port storage and READ_FIRST mode. Standalone tests cover
read-first collisions, independent reads/writes, disabled-read holding, and
4/128/1024-word sizes. The unchanged 120 ms pilot IQ hash is retained in the
firmware replay report.

The complete `pilot-pacer-bram` receiver **placed and routed**, with 33333/33333
routable nets complete and no routing errors. Synthesis used 13396 LUTs,
18841 FFs, 49 BRAM tiles and 48 DSPs. It is nevertheless NOT deployable:
routed setup slack is -3.109 ns at 100 MHz and -2.323 ns at 200 MHz; minimum
hold slack is +0.014 ns. All four declared bus-skew constraints pass. The build
correctly terminates with its timing gate failed; routing alone is not success.

The next source revision addresses two measured control cones without changing
sample arithmetic. PIL1 write decoding is registered before capture/DDC
admission and acknowledged only after execution. The FFT output-state gate is
factored using its existing output-phase predicates; the original global fault
checks remain intact. Actual-adapter equivalence tests check 524288 combinations
for each input-identity mode, including simultaneous invalid inputs and output
faults. These finite tests and the documented algebra support the refactor;
they are not a formal whole-design proof or timing qualification.

The `registered-control-v1` complete build uses 13396 LUTs, 18848 FFs,
49 BRAM tiles and 48 DSPs at synthesis. It places/routes but still fails timing:
100 MHz setup -1.851 ns, 200 MHz -1.727 ns, hold +0.019 ns. Its finished routed
DCP SHA256 is `7551538b4c79440c8f78f2201145b164a21f586986d38b2530b0fb4f9a02419c`.

The next `active-admission-v1` build explicitly separates active STOP/SNAPSHOT
eligibility from inactive ARM checks. 262144 settled actual-RTL comparisons
and continuous runtime assertions match the original admission/flush predicates.
Its full 120 ms capture retains every IQ word and the same hash. The full build
uses 13397 LUTs, 18848 FFs, 49 BRAM tiles and 48 DSPs. All 33325 routable nets
complete, but timing still FAILS: 100 MHz -1.208 ns, 200 MHz -1.478 ns, hold
+0.011 ns. DCP SHA256 is
`fb17fac2c7164d3336f13d8f80682c9830f8f0906f4f74d88c8f565ddb61710f`.
Four bus-skew constraints pass; no internal endpoint is unconstrained. The
13 RX input-delay and two enable/txnrx output-delay findings remain explicit
board-I/O qualification work, not waived timing success.

That route identifies the first-word mailbox metadata enable as the worst
200 MHz path. The `metadata-load-v1` candidate factors its exact first-word
predicate (accepted position zero, no TLAST); subsequent-word equality checks,
fault quarantine and complete-block publication are unchanged. Both 70/75-bit
mailboxes pass the 96-case clock/reset/stall/framing suite, including corruption
of the highest metadata bit. Actual two-clock numerical replay still matches
1341 scores and all forward/product/inverse intermediates, and the service
passes 33792 words/66 jobs with reset/fault recovery and unchanged 2972-cycle
maximum slow-clock service-pair interval. The 64-block coarse capacity run also
returns all 28608 scores and 32768 words at each transform boundary, FIFO high
water 356. The reduced-geometry phase-map replay matches all 447 reads and
aborts a partial tile on a shared-service fault without partial publication.
The fresh full `metadata-load-v1` default implementation fails placement
(Place 46-13 / 30-99: more than 5% of movable instances require spiral search).
Synthesis uses 13429 LUTs, 18848 FFs, 49 BRAM tiles and 48 DSPs. It has no route
or timing claim. A separately logged spread-placement trial on this opt DCP is
running; do not reuse the older candidate's route as evidence for this source.
The offline firmware suite passes 411 tests, including the new kernel contract
logic harness; none is a real IIO or live-lock claim.

Matched Linux now explicitly admits 1.5/0x13f only at canonical 15 MS/s and
rejects service-fault health bit 14. Its ARM module compiles; extracted real
contract/health functions pass 1408 register mutations and 2240 health-bit cases.
PPU main `5e3d6b91c18383c74d356fa490c8a245a96328b6` adds explicit opt-in,
serial-attested connection and stream/context ABI binding. Its local suite
passes 1578 tests (one unavailable-transmitter skip, ten browser/hardware
deselections), full lint and type checking. This does not replace the remaining
real pilot reader, matched image packaging, hardware timing/CDC/IIO qualification
or same-observation live GLRT and qualified FPGA PSS lock.

`projects/pluto/audit_shared_receiver_checkpoint.tcl CHECKPOINT NEW_DIRECTORY`
opens the checkpoint's own stored constraints and reports timing, route status,
CDC, exceptions, bus skew, methodology and actual pilot RAM properties. It does
not reapply constraints or authorize deployment. Preserve each audit directory.

`explore_shared_receiver_checkpoint.tcl CHECKPOINT NEW_DIRECTORY spread-high`
is a bounded physical experiment using a saved pre-placement DCP and its own
constraints. `post-route` instead starts from a routed DCP. Neither mode writes
a bitstream or changes clocks/exceptions. The completed spread trial on the
older `registered-control-v1` DCP has all 33348 nets routed, setup slack -1.127
ns at 100 MHz / -1.289 ns at 200 MHz and hold +0.014 ns. It still FAILS timing.
This is not a result for the current metadata-load source.

The older f85f0888 4096-block capacity simulation now PASSes: 1830977 source
samples, 1830912 ordered scores, 2097152 words at each transform boundary,
FIFO high water 356. It is a full coarse-pipeline 122 ms simulation only, not
current-source proof, paired capture, real IIO, RF or a live lock. Its completed
log can now be source-pinned; it must not be silently attributed to later edits.
