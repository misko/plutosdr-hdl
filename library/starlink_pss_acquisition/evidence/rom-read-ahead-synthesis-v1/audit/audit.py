"""Read-only independent post-synthesis audit; no Vivado execution."""
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

ROOT = Path('/home/mouse9911/gits/starlink-build-recovery-20260910.vHzUVnBz')
HERE = Path(__file__).parent
RUN = ROOT / 'rom-k1m1-synth-v1'
PREP = ROOT / 'rom-k1m1-physical-prepared-v1'
EXPECTED = 'd4d364427c31531358ce747b5931d4fa441e8e46002bf986626c69e923be2a39'

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def emit(name, value):
    with (HERE / name).open('x') as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write('\n')

terminal = json.loads((RUN / 'terminal.json').read_text())
assert all(terminal[k] == 0 for k in ('before_audit', 'tool_returncode', 'after_audit', 'returncode'))
assert terminal['completion']['verified'] is True and terminal['completion']['errors'] == []
products = terminal['completion']['products']
assert len(products) == 8
for name, identity in products.items():
    path = RUN / 'synthesis' / name
    assert identity == {'bytes': path.stat().st_size, 'sha256': sha(path)}
    assert identity['bytes'] > 0
assert sha(PREP / 'SHA256SUMS') == EXPECTED
scope = (RUN / 'synthesis/scope.txt').read_text()
source_rows = re.findall(r'(?:source_hashes_before_synthesis=)?([0-9a-f]{64})  (/[^\n]+)', scope)
assert len(source_rows) == 14  # 13 inputs plus the separately identified simulation log.
for expected, name in source_rows:
    assert sha(Path(name)) == expected, name
sources = dict((name, expected) for expected, name in source_rows)
assert len(sources) == 14
clock = (RUN / 'synthesis/synthesis_clocks.rpt').read_text()
assert re.search(r'island_175\s+5\.71400022506713867\s+.*\{fft_clk\}', clock)
assert re.search(r'source_100\s+10\.00000000000000000\s+.*\{clk\}', clock)
receipt = (RUN / 'synthesis/resource_receipt.txt').read_text()
assert 'black_boxes=0' in receipt
for name in ('REGISTERED_SCHEDULING', 'DISTRIBUTED_FAST_FAULT', 'PRIVATE_NEXT_START_SCRATCH', 'PER_CAUSE_FAULT_CDC', 'PRIVATE_ROM_READ_AHEAD', 'PRIVATE_BLOCK_METADATA_READ_AHEAD'):
    assert scope.count(name + '=1') == 1, name
env = dict(os.environ)
for name in ('PYTHONHOME', 'PYTHONPATH', 'LD_LIBRARY_PATH'):
    env.pop(name, None)
command = ['/home/mouse9911/gits/pluto-plus-utils/.venv/bin/python', '-B', str(PREP / 'prepare_exact_control_physical.py'), '--verify', str(PREP), '--expected', EXPECTED, '--copied', str(RUN / 'synthesis/frozen_sources')]
result = subprocess.run(command, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
with (HERE / 'frozen-helper-post-audit.log').open('x') as stream:
    stream.write(result.stdout)
assert result.returncode == 0, result.stdout
owner = ROOT / 'rom-k1m1-route-v1/own_route.py'
old_owner = ROOT / 'local-admission-route-v1.EzXzzuNB/own_route.py'
restored = owner.read_text()
for new, old in (
    ('/home/mouse9911/gits/starlink-build-recovery-20260910.vHzUVnBz', '/tmp/starlink-coarse-alternatives.Y3JzOI/bank-arithmetic/hdl/library/starlink_pss_acquisition/build'),
    ('rom-k1m1-synth-v1/synthesis/fft_bank_owned_synth.dcp', 'local-admission-ooc-L1R1B1O1-175-owned-v1/synthesis/fft_bank_owned_synth.dcp'),
    ('rom-k1m1-physical-prepared-v1/route_completed_input_fence.tcl', 'local-admission-ooc-L1R1B1O1-175-prepared-v1/route_completed_input_fence.tcl'),
    ('264b7dbb89ccef59b1b41dbaee2e01d4138b8d9a368f64ebc6532efd04f5405e', 'a6a8e404b90924bb538a0da2ae7be7fc9ebc9e0c323b8f1a17661b4550648242'),
):
    assert restored.count(new) == 1
    restored = restored.replace(new, old)
assert restored == old_owner.read_text()
compile(owner.read_text(), str(owner), 'exec')
for name in ('route', 'tmp', 'before.json', 'terminal.json', 'outer.log', 'vivado.log', 'vivado.jou'):
    assert not (owner.parent / name).exists() and not (owner.parent / name).is_symlink()
emit('independent-post-audit.json', {
    'original_handle': 11476, 'original_terminal': terminal,
    'prepared_manifest_sha256': EXPECTED, 'scope_source_and_log_hashes': sources,
    'frozen_helper_command': command, 'frozen_helper_exit': result.returncode,
    'frozen_helper_result': json.loads(result.stdout),
    'route_proposal_owner_sha256': sha(owner), 'route_proposal_original_owner_sha256': sha(old_owner),
    'route_proposal_whole_source_four_replacement_inverse': True,
    'route_launched': False, 'independent_audit_pass': True,
})
print('INDEPENDENT_ROM_SYNTHESIS_AUDIT_PASS; route owner inverse PASS; route NOT launched')
