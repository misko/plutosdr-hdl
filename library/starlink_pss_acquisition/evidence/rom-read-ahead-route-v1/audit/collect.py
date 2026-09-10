"""Independent terminal integrity audit and lossless bounded route collection."""
import hashlib
import json
from pathlib import Path
import re
import shutil

ROOT = Path('/home/mouse9911/gits/starlink-build-recovery-20260910.vHzUVnBz')
HERE = Path(__file__).parent
RUN = ROOT / 'rom-k1m1-route-v1'
PREP = ROOT / 'rom-k1m1-physical-prepared-v1'
OUT = HERE / 'archive'
OUT.mkdir()

def identity(path):
    return {'bytes': path.stat().st_size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}

def write(name, value):
    with (OUT / name).open('x') as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write('\n')

terminal = json.loads((RUN / 'terminal.json').read_text())
assert terminal['tool_returncode'] == 0 and terminal['errors'] == []
assert terminal['marker_count'] == 1 and terminal['deployment_eligible'] is False
assert terminal['source_hashes_before'] == terminal['source_hashes_after']
for name, sha in terminal['source_hashes_before'].items():
    assert identity(Path(name))['sha256'] == sha
names = {
    'probe.tcl', 'clocks_before.rpt', 'inherited_constraints.xdc', 'route_status.rpt',
    'utilization.rpt', 'hierarchy.rpt', 'timing_unqualified.rpt',
    'check_timing_unqualified.rpt', 'cdc_unqualified.rpt', 'receipt.txt',
    'source_100_max.rpt', 'source_100_min.rpt', 'island_175_max.rpt', 'island_175_min.rpt',
    'completed_input_diagnostic_routed.dcp',
}
assert {p.name for p in (RUN / 'route').iterdir()} == names
assert set(terminal['products']) == {'route/' + name for name in names}
for name, expected in terminal['products'].items():
    assert expected['bytes'] > 0 and identity(RUN / name) == expected
raw = (RUN / 'outer.log').read_text()
assert sum(s.strip() == 'COMPLETED_INPUT_DIAGNOSTIC_RECORDED_NOT_A_PHYSICAL_RELEASE_PASS' for s in raw.splitlines()) == 1
assert not re.search(r'^\s*(?:ERROR|FATAL)(?:\s|:)', raw, re.M)
assert identity(PREP / 'SHA256SUMS')['sha256'] == 'd4d364427c31531358ce747b5931d4fa441e8e46002bf986626c69e923be2a39'
prepared = {}
for line in (PREP / 'SHA256SUMS').read_text().splitlines():
    expected, name = line.split('  ', 1)
    assert identity(PREP / name)['sha256'] == expected
    prepared[name] = expected
assert len(prepared) == 18
scope = (ROOT / 'rom-k1m1-synth-v1/synthesis/scope.txt').read_text()
rows = re.findall(r'(?:source_hashes_before_synthesis=)?([0-9a-f]{64})  (/[^\n]+)', scope)
assert len(rows) == 14
for expected, name in rows:
    assert identity(Path(name))['sha256'] == expected

def paths(name):
    text = (RUN / 'route' / name).read_text()
    result = []
    for block in re.split(r'(?=^Slack(?: \(|:))', text, flags=re.M)[1:]:
        fields = {}
        for key in ('Source', 'Destination', 'Path Group', 'Path Type', 'Data Path Delay', 'Logic Levels'):
            match = re.search(r'^  ' + key + r':\s*([^\n]*)', block, re.M)
            fields[key] = match[1] if match else None
        fields['Slack'] = block.splitlines()[0]
        fields['clocked_by'] = re.findall(r'cell \S+ clocked by (\S+)', block)
        result.append(fields)
    return result

summaries = {name: paths(name) for name in names if name.endswith(('_max.rpt', '_min.rpt'))}
assert all(len(value) == 20 for value in summaries.values())
cross = {}
for entry in paths('timing_unqualified.rpt'):
    clocks = entry['clocked_by']
    if len(clocks) == 2 and clocks[0] != clocks[1] and entry['Path Type'].startswith(('Setup', 'Hold')):
        key = f'{clocks[0]}->{clocks[1]} {entry["Path Type"].split()[0]}'
        cross.setdefault(key, entry)
assert len(cross) == 4
write('path-summary.json', {'internal_top20': summaries, 'worst_cross_setup_hold': cross})
write('independent-post-audit.json', {
    'original_handle': 87839, 'owner_terminal_exit': 0,
    'original_terminal': terminal, 'required_nonempty_products': 15,
    'all_products_rehashed': True, 'prepared_18_hashes': prepared,
    'synthesis_source_ip_and_actual_log_rows_rehashed': 14,
    'timing_pass': False, 'deployment_eligible': False,
    'scope': 'read-only terminal integrity, not functional or physical qualification',
})
originals = {}

def copy(source, rel):
    assert source.is_file() and not source.is_symlink()
    dest = OUT / rel
    assert not dest.exists()
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, dest)
    expected = identity(source)
    assert identity(dest) == expected
    originals[str(rel)] = {'original': str(source), **expected}

for path in sorted(RUN.iterdir()):
    if path.is_file():
        copy(path, Path('owner') / path.name)
for path in sorted((RUN / 'route').iterdir()):
    copy(path, Path('route') / path.name)
copy(HERE / 'collect.py', Path('audit/collect.py'))
copy(ROOT / 'rom-k1m1-synth-v1/synthesis/fft_bank_owned_synth.dcp', Path('input/fft_bank_owned_synth.dcp'))
copy(PREP / 'route_completed_input_fence.tcl', Path('input/route_completed_input_fence.tcl'))
copy(ROOT / 'rom-k1m1-synth-v1/synthesis/scope.txt', Path('input/synthesis_scope.txt'))
copy(ROOT / 'rom-k1m1-synth-v1/terminal.json', Path('input/synthesis_terminal.json'))
copy(PREP / 'SHA256SUMS', Path('input/prepared-SHA256SUMS'))
baseline = Path('/tmp/starlink-completed-input.5EaJuD/fault-cdc-route-v1')
for name in ('timing_unqualified.rpt', 'utilization.rpt', 'receipt.txt', 'island_175_max.rpt', 'cdc_unqualified.rpt'):
    copy(baseline / name, Path('baseline-C1-route') / name)
write('raw-artifact-identities.json', originals)
print(json.dumps({'required_products': 15, 'independent_audit_pass': True, 'timing_pass': False, 'copied_originals': len(originals), 'archive': str(OUT)}, sort_keys=True))
