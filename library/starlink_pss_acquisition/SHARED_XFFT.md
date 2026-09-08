# Shared transform island experiment — DO NOT MERGE / NOT DEPLOYABLE

The candidate removes a second transform core, not either PSS detection stage.
`starlink_pss_iq_to_score_shared` keeps ingress, overlap scheduling, energy,
kernel multiplication and normalized scoring at 100 MHz. Only the generated
XFFT and its adapter run at 200 MHz. Pilot IQ and full-rate refinement are not
changed. **No receiver profile selects this candidate yet.** The default
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
- In this unselected experimental composition, the existing forward-fault
  output represents a shared-service error; it does not identify which
  direction failed. Production health/identity contracts have NOT been changed.
  Resolve and version that interpretation before deployment.

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
- Firmware pytest: `tests/starlink_oracle/test_block_mailbox_rtl.py`

Next: opt-in wrapper/IP/block-design integration using the actual 200 MHz
clock, scoped ownership/held-bus timing constraints, explicit reset and health
identity, and fresh complete paired-receiver placement/routing/timing. Preserve
both PSS stages and exact pilot samples. Do not count standalone savings as a
whole-design fit. Then qualify the matched DMA/IIO image on .18 before deploying
.17 through serial-locked PPU network flashing. Same-observation live blind host
GLRT AND qualified FPGA PSS timing lock remain mandatory, followed by the
120 ms/eight-target/300 s and 30/60 MS/s gates. No radio was touched here.
