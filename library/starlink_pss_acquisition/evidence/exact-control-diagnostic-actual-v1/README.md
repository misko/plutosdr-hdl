# One failed baseline diagnostic, immutable evidence

Actual handle 69434 exited 1 at the same original epoch-11 failure time,
1198594347644 fs. The sole named mismatch is eight-bit core_status_data:
candidate xx100101 versus reference 00000101. Both original and fresh
whole-field equality are 0. This is not a qualification pass.

Measured FW c13a04e539f4a36cda27f3e1c79a8d5c88bd38c6 /
HDL f43cdcf9ef817670ccb9bfbc53c890027ba5543b; runtime ae50b188 unchanged.
R0 D0 S0 extras1 FAST175 QUICK0; original runner, two threads, one actual run.
Raw directory: /tmp/starlink-completed-input.5EaJuD/exact-control-diagnostic-actual-v1.

Both partial CSVs are equal to the original baseline partial trace. No
full-CSV, original suite, exact-control or extra-epoch terminal PASS exists.
Read-only WDB handle 90275 exited 0; it did not replay simulation. The raw
status-valid aliases are unlogged. Recorded independent old-public-valid=1
plus literal status vetoes implies both status-valid=0 at the fatal, but
the vendor/force-release driver origin remains unproven. All eight bits,
including asserted bit 5, are retained. No comparison or RTL was changed.

frozen-SHA256SUMS is the original authorized inventory. After checks pass
for that inventory, all seven current RTL and the tested ae50b188 source.
A first current-file search accidentally selected an older immutable
evidence copy of the result guard and reported a byte mismatch; the exact
live library paths then compared successfully. No source was changed.
diagnosis/wdb.log and .jou retain command-discovery/read-only limitations.
Compressed CSV/WDB files decompress to the hashes in after-raw-hashes.txt.
The full technical result is in the enclosing FW report
docs/starlink-exact-control-diagnostic-actual-20260910.md.
