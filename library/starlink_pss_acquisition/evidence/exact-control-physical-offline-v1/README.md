# Offline physical preparation, not physical execution

Tested FW b0b43802603c18472c65c159a36424785441af1a /
HDL 26cc65a7f473ba3f528c90524df35ff0b25b7466. Final 43 tests pass,
original 96286 exit 0 / 82.78s. Earlier v1–v4 successful offline attempts are
retained with their exact sources; only v5 includes all final review gates.
The source files were unchanged during the parent's independent replay.

`prepared/` is the exact 18-file freeze, manifest SHA
99862b8d88414de6b2b4171df2a1a61bf5849ef2effed3c875de9904c366f158.
Live path: /tmp/starlink-completed-input.5EaJuD/exact-control-physical-prepared-v1.
It depends on the already passing actual directory recorded in its metadata,
not on an invented scope.txt or a fresh simulation. No project has been made.

All Tcl project calls in `final-offline-logs/` are mocked; all owner invocations
are stubbed. Any tiny synthetic resource/DCP products in original pytest dirs
are explicitly mock-only and are not synthesized evidence. Complete original
pytest directories remain /tmp/starlink-completed-input.5EaJuD/exact-physical-offline-v1
through v5; mutated large CSV copies are not repeated in this compact archive.

Final test command:

```sh
/home/mouse9911/gits/pluto-plus-utils/.venv/bin/python -B -m pytest -q tests/starlink_oracle/test_exact_control_physical_preparation.py --basetemp=NEW_OFFLINE_TEST_DIRECTORY
```

Relevant unchanged suites for independent review are
test_exact_control_actual_preparation.py, test_exact_control_combined_preparation.py,
test_exact_control_extra_edge.py and test_status_qualified_observer.py.
They are already tracked; this archive adds no new numerical expectations.

Proposed future synthesis command — **not executed, requires authorization**:

```sh
env -u PYTHONHOME -u PYTHONPATH -u LD_LIBRARY_PATH /home/mouse9911/gits/pluto-plus-utils/.venv/bin/python -B /tmp/starlink-completed-input.5EaJuD/exact-control-physical-prepared-v1/run_exact_control_synthesis.py --execute-synthesis --prepared /tmp/starlink-completed-input.5EaJuD/exact-control-physical-prepared-v1 --expected 99862b8d88414de6b2b4171df2a1a61bf5849ef2effed3c875de9904c366f158 --new-run /tmp/starlink-completed-input.5EaJuD/exact-control-combined-synth-v1
```

The owner uses exactly /opt/Xilinx/Vivado/2022.2/bin/vivado and gives that child
LD_LIBRARY_PATH=/opt/Xilinx/Vivado/2022.2/lib/lnx64.o/SuSE. Logs/journal precede
tclargs, output is a fresh child synthesis directory, and no timeout/retry is
implemented. Two-thread settings live in the unchanged Tcl. The owner separately
records raw process return and completion/integrity failures; terminal marker,
eight nonempty products, zero black boxes and copied source closure are required.
No route is invoked; route authorization and actual checkpoint/clock review are
separate. No timing, area saving, receiver or RF success is implied.
