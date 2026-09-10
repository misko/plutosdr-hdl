# Single authorized exact111 OOC synthesis

Original handle 41784 terminal 0. Raw Vivado exit 0, verified completion true,
both before/after audit 0. 108.902732 seconds, 2026-09-10T09:43:14.159463Z to
09:45:03.062275Z. Exact command is retained in invocation.json and terminal.json.
No route, retry, source modification or RF operation.

Tested FW b0b43802603c18472c65c159a36424785441af1a /
HDL 26cc65a7f473ba3f528c90524df35ff0b25b7466. Prepared inventory
99862b8d88414de6b2b4171df2a1a61bf5849ef2effed3c875de9904c366f158,
the separately archived exact-control-physical-offline-v1 input bundle.
All three R/D/S knobs are explicitly 1 in scope.txt and synthesis elaboration.

Final DCP SHA256 00cd669cee367f2ff9b3852d7fd05827ba64027ccd526f1f269cde5ddff630d9,
2,123,338 bytes. Area: 1970 LUT / 4478 FF / 21 DSP / 15 RAMB18 / 0 black boxes.
source_100 clk 10 ns; island_175 fft_clk 5.71400022506713867 ns. No timing pass.
One CDC-10 Critical distributed-fault reduction before the slow synchronizer,
139 CDC-15 warnings, 5 CDC-3 informational crossings. Interface constraints remain
missing for 114 inputs and 124 outputs. No waiver or CDC/IO closure claim.

The 13 scope-declared input hashes (12 copied inputs plus generated VHDL wrapper)
all verify after synthesis. Scope/after inventories, source closure, full reports,
generated-IP inventory/XCI/wrapper, child logs/Tcl and final DCP are preserved.
The original project remains at
/tmp/starlink-completed-input.5EaJuD/exact-control-combined-synth-v1/synthesis/project.
Vendor support files are inventoried locally rather than duplicating the project.
No later route or any altered-source measurement is represented by this archive.
