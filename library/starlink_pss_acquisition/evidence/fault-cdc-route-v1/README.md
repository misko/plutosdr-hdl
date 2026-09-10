# C1 single diagnostic route — timing FAIL

Original owned handle49744, terminal0. Vivado process exit0; post-DCP/Tcl
integrity0; timingFAIL is independent of process completion. Both original
raw directories remain intact. No retry or constraint/source change.

The route used Vivado2022.2/SuSE, maxThreads2, part xc7z010clg400-1, unchanged
100/175 resource clocks/directives and zero-blackbox admission. Invocation
(already executed once; this is provenance, not authorization to rerun):

```sh
LD_LIBRARY_PATH=/opt/Xilinx/Vivado/2022.2/lib/lnx64.o/SuSE \
/opt/Xilinx/Vivado/2022.2/bin/vivado -mode batch -notrace \
  -source /tmp/starlink-completed-input.5EaJuD/fault-cdc-physical-prepared-v1/route_completed_input_fence.tcl \
  -log /tmp/starlink-completed-input.5EaJuD/fault-cdc-route-owner-v1/vivado.log \
  -journal /tmp/starlink-completed-input.5EaJuD/fault-cdc-route-owner-v1/vivado.jou \
  -tclargs /tmp/starlink-completed-input.5EaJuD/fault-cdc-synth-v1/synthesis/fft_bank_owned_synth.dcp \
  8c87cbd93869a376ca727c601b47dc36ff6bc480e359abca5f12f3988ba426bd \
  /tmp/starlink-completed-input.5EaJuD/fault-cdc-route-v1
```

The external shell used /usr/bin/time, no-overwrite owner/output directories,
and before/after SHA checks even on process failure. Original output:
`route_process_status=0 post_integrity_status=0`; elapsed59.27s. All original
logs/time/exit/hash files are in owner/. Full timing, area, CDC, reset and
coverage reports plus routed checkpoint are in route/.

Input provenance: FW51b7bceed8a4ca9c42a1d43752fca3e5b00b4431 /
HDL096ab760b91198e8101614ed8b712f44f74707e2. Exact seven runtime sources and
generated-IP closure are preserved in sibling `fault-cdc-synthesis-v1`,
56-member manifest c1b5e9210497458e6524b7abd8d8efb29485e22392613e83dff97d36a428d12f.
Current archive includes that input DCP, source scope/post-check and exact
18-file prepared inventory66001eba6a4bd5773f73ea1eaac9b730cd11e620900bbce072b1b0c5d0accb65.
Runtime is R/D/S/C1111, unchanged from its passing qualified-status actual
freeze; no original raw217 pass or physical release is claimed.

Global WNS−1.830/TNS−673.636/653fails; hold+0.058/0fails. Routed2015LUT,
4581FF,1087slices,58controlsets,21DSP,7.5BRAMtiles. All6736routable nets
routed. CDC0critical/17information/139warnings, still unqualified; I/O114/124
missing delays. See FW docs/starlink-fault-cdc-route-20260910.md for exact
groups, paths, logic/route splits and limitations. Verify SHA256SUMS from
this directory; publication also requires Git-object manifest verification.
