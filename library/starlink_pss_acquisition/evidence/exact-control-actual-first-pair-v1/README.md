# Failed original actual pair, preserved without retry

FW613b14e673 / HDL027a903f7d; helpersd5cc9f28; runtimeae50 unchanged.
Baseline60442 and combined8914 both exit1 on exact whole-field mismatch
in epoch11. No original/extra terminal receipt, no full-CSV qualification.

`r0-d0-s0/` and `r1-d1-s1/` preserve source/settings, tool/simulation logs,
wall timing, after-run source checks and gzip-n compressed original partial
CSV/WDB files. `frozen-SHA256SUMS` is the original per-run before inventory.
The original runner's before check succeeded; after checks were separately
executed because its failure exit precedes the normal after-run gate.

`diagnosis/` is read-only saved-WDB inspection, handle2352 terminal0.
All217 fields were queried at the failure:23 candidate,0 reference values
available, zero paired fields. No simulation replay occurred; unsuccessful
command/escaping probes are retained too. Values/counters are partial only.

See FW report `docs/starlink-exact-control-actual-first-pair-20260910.md` for
exact failure/trace hashes, warning counts, limits and next observation.
