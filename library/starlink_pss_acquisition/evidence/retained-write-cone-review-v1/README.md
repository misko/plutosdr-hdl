# Retained write-metadata cone review and rejected pulse-only experiment

This is analysis/counterexample evidence, not a new RTL candidate or timing qualification. The initial pulse-only recommendation was rejected after root demonstrated an early forward guard ACK at cycle2736. Baseline passes; the one-trigger mutant fails with committed0,commit_pulse1,bank_valid0,awaiting_ack1,mailbox_ready1.

Contents:

- `report.md`: corrected analysis. Any revised completion/ACK-phase design is proposal-only and must audit every forward_committed consumer, including independent head faults and actual publication.
- `initial-proposal.md`: exact initial report, SHA b97e2804b5c22bdda2c7d213b98ef64c8a16e07a347268f8127262cdca478cdb, retained without silently rewriting the failed recommendation.
- `original-counterexample/`: byte-identical full root terminal evidence from `/home/mouse9911/gits/starlink-build-recovery-20260910.vHzUVnBz/commit-pulse-ack-parent.xkh8BtdU`. Includes original script, result, baseline/mutant compiled netlists, benches, logs and exit receipts. Empty compile logs are preserved. The original script contains a pinned original tree path and must not be run in place as an archival inspection.
- `frozen-source-snapshot/`: exact 97-file retained synthesis input source snapshot, plus the three source-pinned intermediate private-offer candidate modules required by its strict inverse helper. This preserves original RTL, vectors, reference/bench and Python helper dependencies without copying them into production.
- `portable-source-verification.json`: read-only verification receipt. No simulation or vendor run was launched while packaging.
- `SHA256SUMS`: complete file inventory, excluding only itself.

The frozen helpers reconstruct both original benches exactly; all 18 actual compile-source hashes equal the original root result source map. The pulse-only top is exactly one trigger substitution in the registered-scheduling branch, including its retained !next_inverse qualifier. Root's baseline and deliberate-mutant outcomes are not labeled as a test of the revised design. Its secondary final-inventory fatal follows the first deliberate early-ACK stop and does not replace that witness.

Source/runtime files in this archive are evidence only. The existing canonical/closed/offered-summary candidates were not edited. No extra clock, timing exception, fault waiver, vendor execution or radio action is authorized by publication. The independent Git-object archive gate must pass at the complete committed pin, not merely on local files.
