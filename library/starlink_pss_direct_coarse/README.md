# Isolated direct coarse arithmetic experiment — DO NOT MERGE

This directory does not replace production coarse RTL. See firmware
`docs/starlink-direct-coarse-evaluation-20260910.md` for coefficient provenance,
the failed numerical comparison, measured resource limits and omitted work.

The current slice has six exact three-product complex MAC lanes, eleven issue
beats per 66-tap job, a registered partial-sum reduction and ready/valid output
with stored timestamp/epoch. It has no ADC sample-history or job owner and no
normalizer. Its 200 MHz ideal 18.18M job/s rate is not source-input qualification.

Portable arithmetic/protocol test (from this directory):

```sh
mkdir -p build
iverilog -g2012 -Wall -s tb_direct_mac6 -o build/direct_mac6.vvp starlink_pss_direct_mac6.v tb_direct_mac6.sv
vvp build/direct_mac6.vvp
```

Measured current isolated route: 2087 LUT, 2442 FF, 690 slices, 18 DSP, no BRAM,
eight control sets. Setup +0.453 ns, hold **−0.713 ns** at 200 MHz, so physical
qualification fails. Explicit fabric post-adds prevent the first revision's
24-DSP multiplication duplication. Both failed physical runs are retained.

The direct numerical contract changes six of the existing 1341 golden scores
by one LSB. In the extended synthetic matrix, 2/102 controls exceed the
predeclared one-LSB/exact-peak comparison gate: up to nine LSBs and changed
global noise maxima under extreme block dynamic range. Existing production
goldens and all comparison tolerances are unchanged.

The `build/` directory contains ignored generated C-model libraries, DCPs and
replay artifacts. `evidence/` retains only experimental reports and receipts;
none proves receiver fit, map cadence, live PSS lock or GLRT agreement.

## Streaming feeder/history continuation

`starlink_pss_direct_feeder.v` now provides an isolated synchronous source
interface with no ready signal, six 128x32 sample replicas, one 128x64 raw
timestamp store, six immutable coefficient banks and atomic bank/generation
identity. It counts gaps and expiry across local fences, including an explicit
gap coincident with config/flush, and fails closed on identity exhaustion.
Canonical ordinals advance by 1; raw source timestamps advance by 1/2/4 for
source15/30/60. No energy or score normalization is included.

The feeder replay passes 72543 inputs/71047 exact results, source and ordinal
wrap, supported stalls, deliberate expiry, timestamp/gap faults, bank changes
and reset/identity-rail checks. The combined corrected isolated route uses
2354 LUT, 2814 FF, 744 slices, 18 DSP and 4 BRAM tiles; setup −3.161 ns and
hold −0.742 ns at 200 MHz fail. See firmware
`docs/starlink-direct-coarse-feeder-20260910.md` and `evidence/feeder/` for full
scope, endpoints, logic/routing delays and reproduction commands. The original
numerical incompatibility and all production requirements remain unchanged.
