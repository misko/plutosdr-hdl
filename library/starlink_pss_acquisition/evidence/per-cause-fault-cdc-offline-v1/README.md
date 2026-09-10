# Offline default-off per-cause CDC candidate

Tested FW640cf54b8a28e979e62f90a8c57e911bb789ac7c /
HDL02de07cc7a6c241dd6cc8cf5b733037d89eac6bd. WrapperSHA
e8285f5ef2b548272ec357fca5213b1e400b5242396be2597498eff09f665579.
No actual FFT, synthesis, route or analog CDC closure on this source.

Final original42701 exit0:122PASS22.78s (new37+prior49+17+19).
Original36038 exit0:30PASS5.68s. Original46213 exit1:48PASS/1strict inverse anchor
FAIL14.80s, retained with exact precompatibility sources. Approved four-line
composition plus literal full CDC_BODY validation fixes compatibility without
changing any old expected bytes. Six malformed-body inverse mutations reject.

Per enabled new bench:4096source subsets,48X/Z rows,3 common reset variants,
1privatecore reset,16836slow/29464fast checks. Both R modes and three slow phases
(0,713,2857ps). Twelve omitted causes, missing stage, wrong resets and added
latency fail. Five invalid knob cases fail closed. All source-Q drives and
quiescent FFT stub scope are explicit; no active FFT or metastability claim.

Reproduce from FW root:

```sh
/home/mouse9911/gits/pluto-plus-utils/.venv/bin/python -B -m pytest -q tests/starlink_oracle/test_fault_cdc.py tests/starlink_oracle/test_exact_control.py tests/starlink_oracle/test_forward_retirement.py tests/starlink_oracle/test_payload_bubbles.py --basetemp=NEW_OFFLINE_DIRECTORY
```

`source/` captures changed sources and test dependencies; `runtime/` all seven
tested modules/kernel; `old-runtime/` independently frozen old modules; `attempts/`
retains old logs/source; `logs/` final unmodified compiler/simulator receipts.
`new-cases/` retains candidate wrappers/bench snapshots for new executable cases.
All full original pytest directories remain /tmp/starlink-completed-input.5EaJuD/
per-cause-cdc-offline-v1, per-cause-cdc-prior-v1, per-cause-cdc-integrated-v2.
The earlier measured route remains separately frozen in exact-control-combined-route-v1.
