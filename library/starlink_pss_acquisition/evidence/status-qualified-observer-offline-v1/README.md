# Offline status-qualified observer evidence

73 PASS in14.02s, original15112 exit0; no vendor FFT execution or physical run.
Tested FW3bb9fcc20b4ed8f8a9417e8002f69a092b995b4a /
HDL80e652c038121308b966797627ea120d0c91acdb. Runtime seven RTL unchanged ae50.

This is explicitly a DIFFERENT observer scope from the raw217 assertion:
only the complete status payload may differ when BOTH valids are exactly0.
Raw217 remains intact; all216 other fields stay unconditional; all8 status
bits remain checked for any other valid combination, including X/Z.
The original fatal diagnostic/CSV evidence remains immutable in the prior
exact-control-diagnostic-actual-v1 archive. It has not become a pass.

prepared/ is the complete baseline R0D0S0/extras1/FAST175/QUICK0 freeze.
Original runner and all numerical/full-CSV/extra-epoch gates are unchanged.
Any future authorized actual result additionally requires calling frozen
verify_observation_receipt(log, exact_checks): count/log/scope mismatches
are failures, not warnings. No actual result is included here.

fast/ contains final generated standalone source and logs (not vvp binaries).
sources/ retains tested helper/bench/test files and Python import dependencies.
prior-v3/ retains exact69-pass pre-expansion source; logs/ retains all four
incremental successful selections. The final guard bench proves77 phase
witnesses per mode, including3 coincident-output and2 ready-high ACK cases.
It is real guard RTL with synthetic core events, not actual FFT proof.

Full report: enclosing FW docs/starlink-status-qualified-observer-offline-20260910.md.
