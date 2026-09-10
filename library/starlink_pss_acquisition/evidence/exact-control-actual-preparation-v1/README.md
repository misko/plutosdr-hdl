# Offline preparation only — no actual FFT execution

Tested helper pins: FW7cc98f66b834c0c3f015c8dccf41e8b051232d7c /
HDLd5cc9f28ecd389e277a2278131661b6f21beac41. All seven RTL remain ae50b188.
Final original20822 exit0:93PASS16.40s (44new +49existing fast).

`matrix/` contains eight complete prepared R/D/S combinations,175MHz,
extras1, QUICK_MUTATION0. Each inventory is independently checkable;
none has a Vivado project or actual result. The raw final matrix is
`/tmp/starlink-completed-input.5EaJuD/exact-control-actual-matrix-v3/`.

`logs/` preserves aggregate v1–v6 and final new standalone/elaboration
receipts. Compilation checks the complete217-field equality is2168bits;
actual benches were never executed against the compile-only stub.
Monitor, parameter-entry and Tcl receipt tests run independently without FFT.
`source/` preserves exact Python tests and source delta inventory.

`invalid-width/` preserves the original observer whose hierarchical $bits
localparam compiled to0 despite the initial green compile-only tests.
`invalid-xz-override/` and v5.log preserve the four failed negative stimuli
caused by Icarus rejecting command-line X/Z overrides and retaining0.
Literal SV instance overrides fixed the test application, not its criterion.

Read the FW report `docs/starlink-exact-control-actual-preparation-20260910.md`
for invariants, scope limits, original CSV hashes, proposed staged actual
matrix and estimated runtime. Actual, numerical, physical and radio gates
remain unexecuted for this preparation.
