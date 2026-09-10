#!/usr/bin/env bash
# One authorized actual run. Existing paths and repeat execution are rejected.
set -u -o pipefail
set -C
rom_prepared=/home/mouse9911/gits/starlink-build-recovery-20260910.vHzUVnBz/rom-relocated-actual-v2.CWJkzwEi/rom-actual-prepared-v1
rom_owner=/home/mouse9911/gits/starlink-build-recovery-20260910.vHzUVnBz/rom-relocated-actual-v2.CWJkzwEi/rom-actual-owner-v1
rom_python=/home/mouse9911/gits/pluto-plus-utils/.venv/bin/python
for rom_path in "$rom_owner/launch.log" "$rom_owner/vivado.log" "$rom_owner/vivado.jou" "$rom_owner/start-utc.txt" "$rom_prepared/project"; do
  if test -e "$rom_path"; then printf 'refusing existing run path: %s\n' "$rom_path"; exit 2; fi
done
cd "$rom_prepared" || exit 2
sha256sum SHA256SUMS frozen_sources/simulate_exact_control_prepared.tcl > "$rom_owner/before.sha256"
if ! test "$(sha256sum SHA256SUMS | cut -d ' ' -f 1)" = 6f5eddb99510e869bbe65548acc6ed64cd76bd98908aacfcd6e1c0361ccbe4ae; then exit 2; fi
if ! test "$(sha256sum frozen_sources/simulate_exact_control_prepared.tcl | cut -d ' ' -f 1)" = 9f198abf60d9119eae2ef565ae3d65b64104f93ce5f1b5be4b2e89776dd3deed; then exit 2; fi
sha256sum --check SHA256SUMS > "$rom_owner/before-integrity.log" 2>&1
rom_before=$?
if test "$rom_before" -ne 0; then exit "$rom_before"; fi
env -u PYTHONHOME -u PYTHONPATH -u LD_LIBRARY_PATH "$rom_python" -B frozen_sources/prepare_rom_read_ahead_actual.py --verify-prepared "$rom_prepared" > "$rom_owner/before-admission.json" 2> "$rom_owner/before-admission.err"
rom_admission=$?
if test "$rom_admission" -ne 0; then exit "$rom_admission"; fi
printf '{"project_present":false,"generated_IP_present":false,"factory_in_pinned_source_inventory":true}\n' > "$rom_owner/before-ip.json"
date -u +%Y-%m-%dT%H:%M:%S.%NZ > "$rom_owner/start-utc.txt"
LD_LIBRARY_PATH=/opt/Xilinx/Vivado/2022.2/lib/lnx64.o/SuSE \
/usr/bin/time -v -o "$rom_owner/time.txt" \
/opt/Xilinx/Vivado/2022.2/bin/vivado -mode batch -notrace \
  -source "$rom_prepared/frozen_sources/simulate_exact_control_prepared.tcl" \
  -log "$rom_owner/vivado.log" -journal "$rom_owner/vivado.jou" \
  -tclargs "$rom_prepared" > "$rom_owner/launch.log" 2>&1
rom_process=$?
printf '%s\n' "$rom_process" > "$rom_owner/process-exit.txt"
date -u +%Y-%m-%dT%H:%M:%S.%NZ > "$rom_owner/end-utc.txt"
# These audits run on tool failure as well as success. No retry is permitted.
sha256sum --check SHA256SUMS > "$rom_owner/after-integrity.log" 2>&1
rom_after=$?
sha256sum SHA256SUMS frozen_sources/simulate_exact_control_prepared.tcl > "$rom_owner/after.sha256"
printf '%s\n' "$rom_after" > "$rom_owner/after-integrity-exit.txt"
env -u PYTHONHOME -u PYTHONPATH -u LD_LIBRARY_PATH "$rom_python" -B - <<'PY' > "$rom_owner/after-ip.json" 2> "$rom_owner/after-ip.err"
import hashlib
import json
from pathlib import Path
project = Path('/home/mouse9911/gits/starlink-build-recovery-20260910.vHzUVnBz/rom-relocated-actual-v2.CWJkzwEi/rom-actual-prepared-v1/project')
files = sorted(p for p in project.rglob('*') if p.is_file() and p.suffix in ('.xci', '.vhd'))
rows = {p.relative_to(project).as_posix(): {'bytes': p.stat().st_size, 'sha256': hashlib.sha256(p.read_bytes()).hexdigest()} for p in files}
print(json.dumps({'scope':'generated_IP_after_run_only_not_precompile_equivalence', 'project_present':project.exists(), 'files':rows}, indent=2))
PY
rom_ip=$?
printf '%s\n' "$rom_ip" > "$rom_owner/after-ip-exit.txt"
rom_receipt=1
if test "$rom_after" -eq 0; then
  env -u PYTHONHOME -u PYTHONPATH -u LD_LIBRARY_PATH "$rom_python" -B - <<'PY' > "$rom_owner/independent-receipts.json" 2> "$rom_owner/independent-receipts.err"
import hashlib
import json
import runpy
from pathlib import Path
prepared = Path('/home/mouse9911/gits/starlink-build-recovery-20260910.vHzUVnBz/rom-relocated-actual-v2.CWJkzwEi/rom-actual-prepared-v1')
source = prepared / 'frozen_sources'
helper = source / 'prepare_rom_read_ahead_actual.py'
assert hashlib.sha256(helper.read_bytes()).hexdigest() == 'bca85ff4affb7fd4650489103ee5750567fe031d225fda057303007defb840b3'
api = runpy.run_path(str(helper))
settings = api['verify_prepared'](prepared)
log = prepared / 'project/exact_control_actual.sim/sim_1/behav/xsim/simulate.log'
status = api['verify_result'](log, 1, 1, source)
owner = Path('/home/mouse9911/gits/starlink-build-recovery-20260910.vHzUVnBz/rom-relocated-actual-v2.CWJkzwEi/rom-actual-owner-v1')
launch = (owner / 'launch.log').read_text()
marker = 'EXACT_CONTROL_ACTUAL_FROZEN_PAIR_VERIFIED_NO_PHYSICAL_OR_RF_CLAIM'
assert launch.splitlines().count(marker) == 1
expected = {'fft_bank_owned_trace.csv':'25ab9d06ca0e03f280540cda625a7826b3c4cbaa6322ce3266c59e1fbad94122',
 'exact_control_reference_trace.csv':'25ab9d06ca0e03f280540cda625a7826b3c4cbaa6322ce3266c59e1fbad94122',
 'exact_control_extra_trace.csv':'b965d12603a64111fa9c6ea36cb0f12189945ad4d9be7cf4fbd883980c4ec4a0',
 'exact_control_reference_extra_trace.csv':'b965d12603a64111fa9c6ea36cb0f12189945ad4d9be7cf4fbd883980c4ec4a0'}
csv = {}
for name, digest in expected.items():
    data = (log.parent / name).read_bytes()
    assert hashlib.sha256(data).hexdigest() == digest, name
    csv[name] = {'sha256':digest, 'lines':data.count(b'\n'), 'bytes':len(data)}
print(json.dumps({'scope':'actual_C1_plus_ROM_qualified_status_NOT_raw217_or_physical', 'settings':settings, 'status':status, 'csv':csv, 'verified':True}, indent=2))
PY
  rom_receipt=$?
fi
printf '%s\n' "$rom_receipt" > "$rom_owner/receipt-exit.txt"
printf 'process=%s after_integrity=%s IP_audit=%s independent_receipts=%s\n' "$rom_process" "$rom_after" "$rom_ip" "$rom_receipt"
if test "$rom_process" -ne 0 || test "$rom_after" -ne 0 || test "$rom_ip" -ne 0 || test "$rom_receipt" -ne 0; then exit 1; fi
