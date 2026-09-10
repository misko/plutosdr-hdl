# Product READY/publication-only seams: offline evidence

Additive primitives only; canonical d9c, reviewed1444 and P1 unchanged. No vendor
FFT, synthesis, routing, hardware or top integration is represented here.

Source checkpoint: FW eba403dc38b7a0d5a5634a4f76cb0bf78a3d7ae9 and
HDL1703e90347b607219d9c714c2cce698deea6ab9d. The report is
docs/starlink-product-ready-publication-seams-offline-20260910.md in FW.

Each attempt tarball retains its complete original compiled-source snapshots,
per-case command/exit/log receipts, netlists and pytest XML. Final-v1/v2/v3 also
retain raw full pytest stdout. Initial attempts' aggregate summaries come from
the original tool terminal and XML, not a newly rerun/reconstructed raw log.
All failed counterparts remain failures. Extract tarballs only into a fresh
empty directory; pytest's original relative current-directory symlinks remain.

Final original65756:2752PASS78.64s,1308new+immutable1444. The manifest covers
these portable artifacts; it does not claim that a hash
proves functional or physical correctness. final-receipt.json contains exact
source/netlist/log/XML hashes, measured traces and direct-driver cone results.
