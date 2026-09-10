# Added extra-epoch phase alignment: offline only

Tested FW48b88f6786334f5a62efaf1972ca430140e2b06c /
HDL12ce2854b35ee797f52cc32b6d3668ed65726d79. Runtime all seven modules
remain ae50b1889fd10cd762fb60266aecbb7c163e1d1a. No actual FFT rerun,
synthesis, route, radio, promotion or push occurred in this study.

`prepared/` copies the new live freeze
`/tmp/starlink-completed-input.5EaJuD/extra-edge-prepared-v1`.
Its SHA256SUMS hash is
`8efa2657fd43d4c7d2804d90abf9aa169fb8d916136ee681d38d4b533885ad92`.
Only one insertion in the added extra-epoch include differs from the
reviewed qualified baseline, apart from the additive preparation helper
and provenance. Remove the exact `CORRECTION` string to restore the entire
include byte-for-byte; all other inventoried sources/settings are exact.
Both independently driven actual benches include this same task source.

## Results and retained failures

Final original process49596 exited0: **53 PASS in13.52s** (24 new edge,
23 status-qualified, six diagnostic preparation tests). The 12 positive
edge cases exercise kind0/1, default/experimental real guard, and three
declared synthetic provider schedules. All report one qualification edge:
clock0 for negedge/low-half-offset, clock1 for posedge-registered. Kind1
holds exactly three positive edges. Fault lead is2857143fs except kind0
low-half-offset at1428572fs; all meet the prior positive/half-period bound.
No final commit or modeled ownership escape precedes the fault; current
veto and exact sticky reason01 are checked. The original join-input
comparison still samples at posedge+1ps. Ten mutants reject missing high
phase wait, low-phase unconditional next-negedge wait, two/four held
edges, X/Z clock and premature ownership. The unknown-X negative run also
prints an early-publication fatal caused by forcing X onto the fixture
clock; its required explicit unknown-phase fatal remains present.

These use the real current result guard and an independent frozen
ce6a885e guard, synthetic core events, and minimal ordinal/ownership
models. They are NOT vendor FFT, full bank RAM/joiner, arithmetic,
actual reset/recovery, or arbitrary-asynchronous-producer qualification.
Reset kinds2/3 and all old assertions remain literal by whole-file inverse.
The full paired actual bench compiles against a stub but is not executed
against it. The status-qualified tests independently retain their real
guard/four-state/mutation checks and original observation scope.

`failed-v1-source/`, `failed-v1-cases/`, and `logs/extra-edge-offline-v1.log`
retain **7 PASS /5 FAIL**. Unconditionally waiting for another negedge
crossed a commit edge for kind0 under the original negedge provider.
That low-phase no-wait mutant actually passed: no-wait is correct in that
phase, so it is now a positive contract case, not a weakened rejection.
Kind1's missing wait reproduced the original posedge+1ps checker fatal;
the current negative explicitly retains the new low-phase check and
rejects at that fence. The old late-posedge mutant failed the precommit
check instead of the expected drive marker; the new late-wait witnesses
require the exact early-publication marker. Two/four holds and ownership
mutants retain their exact safety claims. No failed result is relabeled.

V2:24 PASS/0.60s, before additive provider-phase receipt fields.
V3:exit4/no tests collected because a diagnostic test filename was wrong;
its log is retained. V4 is the corrected 53-test run. Parent independently
reported47 PASS/13.66s before the additive provider receipt fields.
All generated fixtures and compile/simulation logs are retained; rebuildable
`.vvp` files, Python cache, pytest convenience symlinks are omitted.

## Vendor provenance, separately bounded

`provenance/actual-core-portmap.txt` shows the actual core clock wired
directly to fft_clk and raw output/status valid wired directly to the
guard inputs. The copied generated VHDL wrapper maps those signals to
xfft_v9_1_8; its protected implementation identifies Xilinx2022.2.
Only its hash/header are copied, not the protected payload. Its internal
delta-cycle/output-transition implementation is not established by this
read-only source audit. The generated interface's100MHz metadata is not
the bench clock: frozen settings and actual bench use175MHz.

The preserved actual8757 WDB/CSV diagnosis in the adjacent
`status-qualified-actual-v1` archive establishes kind1/high-clock at the
fatal, but lacks the internal raw signals needed to reconstruct the
qualification transition or simulator process ordering. The CSV is
positive-edge sampled, not a subcycle transition trace. None of the three
synthetic schedules is claimed to be recovered vendor implementation.
The correction admits both known phases and does not depend on that claim.

## Future baseline invocation, NOT EXECUTED

Separate source-specific authorization is required. From the live prepared
directory, retain one original handle and never restart on timeout:

```sh
sha256sum -c SHA256SUMS --quiet
test ! -e project
/usr/bin/time -v -o actual-time.txt env LD_LIBRARY_PATH=/opt/Xilinx/Vivado/2022.2/lib/lnx64.o/SuSE /opt/Xilinx/Vivado/2022.2/bin/vivado -mode batch -source frozen_sources/simulate_exact_control_prepared.tcl -log actual-vivado.log -journal actual-vivado.jou -tclargs /tmp/starlink-completed-input.5EaJuD/extra-edge-prepared-v1 > actual-launch.log 2>&1
```

The frozen runner496a3ed4a2b55d494a22fd78f64b4a68580d923b398f5282e31145dc6a7951b0
requires Vivado2022.2/two threads, R0/D0/S0/extras1/175/QUICK0, original
full CSV hashb0d60e80... and both complete extra-epoch receipts. After a
successful runner, independently call frozen
`prepare_exact_control_status_qualified.py:verify_observation_receipt`
with the complete simulation log and the exact checks count from its
single `EXACT_CONTROL_ACTUAL_PASS` terminal. Reject any scope/count/row
mismatch; never synthesize receipts from partial counters. This remains
the qualified-status observer scope, not an original raw217 pass.
Recheck all frozen hashes before/after and retain all raw invalid-only
rows, both valid bits, complete/extra CSVs, failure logs and warnings.
