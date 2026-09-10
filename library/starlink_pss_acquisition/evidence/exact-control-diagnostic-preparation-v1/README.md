# Offline same-fatal diagnostic preparation

Tested FWd22a91af / HDL1f0068e6. Original82851 exit0:50PASS2.31s.
No actual FFT diagnostic was launched. All seven runtime RTL remainae50.

`prepared/` is the full source/settings/inventory copy of the new unique
`/tmp/starlink-completed-input.5EaJuD/exact-control-diagnostic-actual-v1`.
Only the candidate bench diagnostic task and observer same-fatal task call
change existing files; runner, settings, reference and stimulus are literal.
The original failed baseline inventory is cryptographically pinned.

`source/` has exact tests and full generated observer/bench diffs.
`logs/` retains compile-only full-pair output and no-FFT observer fixtures,
including217 bit69/X/Z mismatches and zero named mismatches with old0/fresh1
still producing the unchanged fatal. These are diagnostics tests, not FFT proof.

See FW report `docs/starlink-exact-control-diagnostic-preparation-20260910.md`.
One baseline actual diagnostic remains subject to separate approval.
