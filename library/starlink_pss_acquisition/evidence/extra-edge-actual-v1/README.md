# Actual baseline: qualified observer plus phase-aligned extra stimulus

One authorized actual-core run, original handle22816, terminal exit0.
Measured FWc9e191f898a146ff08ab5b6c9c848d747fc552d7 /
HDLbed131df5740315da90d1742a0ff956d61990b06; tested helper/source
FW48b88f6786334f5a62efaf1972ca430140e2b06c /
HDL12ce2854b35ee797f52cc32b6d3668ed65726d79. Runtime remains ae50.
R0/D0/S0/extras1/FAST175/QUICK0, Vivado2022.2/two threads.
No second actual mode, physical trial, radio or promotion.

Original directory `/tmp/starlink-completed-input.5EaJuD/extra-edge-prepared-v1`.
Freeze8efa2657fd43d4c7d2804d90abf9aa169fb8d916136ee681d38d4b533885ad92
verified before and after. Frozen runner496a3ed4... is unchanged. Start
08:16:56UTC, Vivado exit08:22:56UTC, wall359.77s, user368.86/system2.07s,
peak RSS836928KB. All27 warnings match the prior8757 run after replacing
only the prepared-directory path. No warning is waived.

Both complete original CSVs:325750lines,
b0d60e80101b34ff163b85ef7547814e0403561b315f975eb38a98817b7eb84d,
exact historical baseline and candidate/reference byte equality.
Both extra CSVs:33131lines,
d3a4aaff96db5c9a9d15cc9f4af8400f42b52fd4f97c08712dfce4d3d585562b,
candidate/reference byte equality; no historical extra golden was invented.

The literal runner's exact receipt and full CSV gates passed. BOTH
independently driven extra tasks report2finalfaults/3heldstalls/
2one-sidedresets/4healthyrecoveries. Candidate whole-module shadow:
checks717760, active504864, consumed36, private_differences0,
final_fault_edges2, owned_stalls78830, reset_owned_edges40.
Simulator $finish at2050740106537fs, no fatal.

Independent invocation of the frozen qualified-observer verifier also
passed:717760samples=717731raw-equal+29invalid-only. Every raw differing
row is retained, both valid bits0, candidate1xx00101/reference00000101,
epoch11,1198594347644..1198674347648fs. Driver origin remains unknown.
This scope is NOT an original raw217 pass; earlier xx100101 and e5 strict/
qualified failures remain immutable in their original archives.

Original main receipts remain intact, including44healthyblocks,
12active-inputfaultcases, two vendor-open quarantine cases and two reset
recoveries. In this R0 run registered preflight/boundary rows remain0,
as do actual inverse_current and sticky_forward fault counters. No D/S
candidate or registered-mode coverage is inferred from this baseline.

The added-stimulus change alone resolves the reproduced final-fault
scheduling failure in this actual run. It does not identify the old
simulator process ordering, qualify arbitrary asynchronous stimulus,
alter any runtime fault rule, or establish physical timing/RF behavior.

All inventoried sources, logs, exact receipts, independent observer audit,
warnings, timing, complete CSVs and saved WDB are retained. CSV/WDB gzip
files decompress to original hashes; the original project remains intact.
See FW docs/starlink-extra-edge-actual-20260910.md and the adjacent
extra-edge-offline-v1 archive for the strict inverse and retained v1 errors.
