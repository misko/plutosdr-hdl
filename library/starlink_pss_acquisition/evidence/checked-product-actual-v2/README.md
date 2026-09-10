# Actual v2 functional PASS; original v1 remains FAIL

Root-owned58385 exited0 in272.655s. Root-owned30484 remains failed by its original
full-trace final-drain predicate. Separate v1/v2 trees preserve each original
source, outcome, logs, complete CSVs, generated IP and WDB evidence; no v1 bytes
or acceptance criteria were repaired. See report.md for exact scope and hashes.

Original v2 source89 inventory55288860074df8107d142c97bd69cb67bc71815f13bbb8bacc3b664b9547f5ea.
The unchanged a04 full32/6/5215 result plus new two-drain receipts passed fresh
read-only archival verification and matched original owner JSON. Runtime14,
FFT factory and vectors unchanged. No raw217/paired CSV, physical, receiver,
continuous-ADC/reset-capacity or radio/deployment qualification is asserted.

Both WDBs use the unchanged tested reconstruct_wdb_parts.py
(SHAeec4a26845a2323c65a29d3100cbc5627fe47d3d24963227e4b9700724c6dcc1),
with three <=40MiB parts each. Executed reconstruction receipts are included.
After checking SHA256SUMS, reconstruct each into a NEW empty-path directory:

```sh
python -B reconstruct_wdb_parts.py --manifest v1/simulation/wdb-parts.json --output-dir NEW_V1
python -B reconstruct_wdb_parts.py --manifest v2/simulation/wdb-parts.json --output-dir NEW_V2
```

Original raw WDB identities:

- v1:110854722 bytes,63edc5b10085a91a24554c00bf9d08c12ba04f9fd4a5363d0ccba3b6e14e0f09.
- v2:110855305 bytes,b58baa1ccd6419df6be3168b3d75d2aa0e8212acc6289abfff166dc056bf1523.

`raw-artifact-identities.json` identifies uncompressed originals for copied or
gzip-named files, including originally empty logs. Source/owner/runtime bytes
are unchanged. Owner TMPDIRs and generated vendor work products not listed here
remain in the original projects; this archive preserves required source/IP/log/
CSV/wave evidence rather than claiming a relocatable vendor build directory.

Original first packaging attempt, rejected only for the unexpected owner .Xil
directory, is preserved in packaging/initial-attempt.tar.gz. Corrected staging
copies those .Xil files and preserves all original source/run outputs. The
staging archive/reconstruction paths are recorded in packaging/package.py.
