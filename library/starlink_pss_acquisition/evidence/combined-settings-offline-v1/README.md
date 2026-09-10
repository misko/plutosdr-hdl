# Combined R1/D1/S1: settings-only offline freeze

No actual combined run, physical experiment or RTL change. Tested
FW9135a11738afb5f6553d979b20d606e6af0a1d00 /
HDLca0117ccef655f189612769d21e109a20e64d364. New external copy helper
9f2c5f2b41cabbfec6dce7169399cc6ef6f38ecd3c51e6b938884a538bf5001b
is provenance only; it is not added to frozen_sources. Every preexisting
frozen helper, checker, stimulus, vector and RTL byte remains identical
to the passing phase-aligned R0 baseline. Runtime remains ae50.

Prepared live directory:
`/tmp/starlink-completed-input.5EaJuD/extra-edge-combined-prepared-v1`.
Inventory8e9251fe06e41917e9e0b5ebceef36db444bc39770efe7acb940dbfcc4ed7906.
Only settings.tcl selects R/D/S=1; metadata scope/settings/provenance and
the new lineage inventory record this change. Whole source and metadata
inverse pass. Project is absent. Original baseline inventory8efa2657...
and all earlier failure evidence remain unmodified.

Original offline handle62400 terminal0:94 PASS/14.51s (three new settings/
binding tests,44 existing actual-preparation tests including all eight
option elaborations and observer/receipt mutations,24 edge tests,23
qualified-status tests). Ruff passes. The new full hierarchy compiles
against a NEVER-EXECUTED stub. Its compiled scopes/parameter values prove:

- candidate actual bench R1/D1/S1/extras1/175/QUICK0;
- candidate DUT R1/D1/S1, scratch1 propagated into joiner and ROM;
- independent reference bench R1/extras1/175/QUICK0;
- independent dec20 DUT R1, with neither D/S parameter/implementation.

This is binding/elaboration proof, not actual FFT arithmetic, active
combined-state equivalence or simulation coverage. Existing old contracts,
all expected bytes/assertions, raw217 expression and qualified observer
remain literal. No test expectation or acceptance predicate was changed.

The unchanged frozen runner496a3ed4... still requires historical R1 main
CSV25ab9d06ca0e03f280540cda625a7826b3c4cbaa6322ce3266c59e1fbad94122,
independent candidate/reference equality, exact options and complete
extra receipts from both benches. The unchanged qualified observer
70096312... retains all216 other fields unconditionally and all8 status
bits unless both valid bits are exactly0. Independently audit its terminal
against exact_checks, including samples=raw_equal+invalid_only and every
logged row. Baseline's29 rows are NOT a new expected count for combined.
No missing/fewer/different row may be hidden, nor may raw217 PASS be claimed.

## Proposed next actual run (not authorized or executed)

One run only after parent source-specific review, same2022.2/two threads,
explicit SuSE library path and frozen runner. Estimated10–12minutes from
the longer registered fixture, not a timeout/restart threshold. From the
live prepared directory:

```sh
sha256sum -c SHA256SUMS --quiet
test ! -e project
/usr/bin/time -v -o actual-time.txt env LD_LIBRARY_PATH=/opt/Xilinx/Vivado/2022.2/lib/lnx64.o/SuSE /opt/Xilinx/Vivado/2022.2/bin/vivado -mode batch -source frozen_sources/simulate_exact_control_prepared.tcl -log actual-vivado.log -journal actual-vivado.jou -tclargs /tmp/starlink-completed-input.5EaJuD/extra-edge-combined-prepared-v1 > actual-launch.log 2>&1
```

Own original handle; no timeout restart. Require original full numerical/
CSV and both extra receipts, independent qualified-observer verifier,
before/after hashes, full original/extra CSV comparison and all raw rows.
Stop and retain any failure without retuning acceptance. No attribution
mode, arithmetic graft, physical run or promotion follows automatically.

Archive contains the official full freeze, all regression logs, generated
case fixtures and source tests. Redundant per-test prepared copies,
rebuildable vvp files/cache/convenience symlinks are omitted; original
complete raw cases remain at `/tmp/starlink-completed-input.5EaJuD/combined-settings-offline-v1`.
