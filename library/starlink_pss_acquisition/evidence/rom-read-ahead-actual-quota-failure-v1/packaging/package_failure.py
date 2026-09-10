"""One-shot lossless packaging of terminal 23845; never run vendor tools."""
import gzip
import hashlib
import json
import runpy
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PREPARED = Path('/tmp/starlink-rom-prefetch.j829ht/rom-actual-prepared-v1')
OWNER = PREPARED.parent / 'rom-actual-owner-v1'
SIM = PREPARED / 'project/exact_control_actual.sim/sim_1/behav/xsim'
PORTABLE = ROOT / 'portable'
PORTABLE.mkdir()

def identity(path):
    with path.open('rb') as stream:
        digest = hashlib.file_digest(stream, 'sha256').hexdigest()
    return {'bytes': path.stat().st_size, 'sha256': digest}

def save_json(name, value):
    path = PORTABLE / name
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('x') as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write('\n')

raw = {}
def copy_file(source, relative, compress=False):
    target = PORTABLE / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    original = identity(source)
    if compress:
        with source.open('rb') as inp, target.open('xb') as out:
            with gzip.GzipFile(filename='', mode='wb', fileobj=out, mtime=0) as zipped:
                shutil.copyfileobj(inp, zipped, 1024 * 1024)
    else:
        with source.open('rb') as inp, target.open('xb') as out:
            shutil.copyfileobj(inp, out, 1024 * 1024)
    assert identity(source) == original
    raw[relative] = {'original_path': str(source), **original,
                     'compression': 'gzip' if compress else 'none'}

for line in (PREPARED / 'SHA256SUMS').read_text().splitlines():
    digest, name = line.split('  ', 1)
    assert identity(PREPARED / name)['sha256'] == digest
    copy_file(PREPARED / name, 'prepared/' + name)
copy_file(PREPARED / 'SHA256SUMS', 'prepared/SHA256SUMS')
for source in sorted(OWNER.iterdir()):
    assert source.is_file() and not source.is_symlink()
    zipped = source.name in ('launch.log', 'vivado.log')
    copy_file(source, 'owner/' + source.name + ('.gz' if zipped else ''), zipped)
for source in sorted(SIM.iterdir()):
    if source.is_file() and source.suffix in ('.log', '.csv', '.jou', '.tcl', '.prj', '.sh'):
        copy_file(source, 'simulation/' + source.name + '.gz', True)

ip = {}
for source in sorted((PREPARED / 'project').rglob('*')):
    if source.is_file() and source.suffix in ('.xci', '.vhd'):
        name = source.relative_to(PREPARED / 'project').as_posix()
        ip[name] = identity(source)
        copy_file(source, 'generated-ip/' + name)
save_json('generated-ip-after-failure.json', {
    'scope': 'fresh_read_only_after_failure_not_precompile_equality', 'files': ip})

wdb = SIM / 'tb_starlink_pss_fft_bank_owned_slice_behav.wdb'
wdb_identity = identity(wdb)
compressed = ROOT / (wdb.name + '.gz')
with wdb.open('rb') as inp, compressed.open('xb') as out:
    with gzip.GzipFile(filename='', mode='wb', fileobj=out, mtime=0) as zipped:
        shutil.copyfileobj(inp, zipped, 1024 * 1024)
assert identity(wdb) == wdb_identity
compressed_identity = identity(compressed)
parts = []
part_limit = 40 * 1024 * 1024
with compressed.open('rb') as inp:
    while block := inp.read(part_limit):
        number = len(parts)
        name = compressed.name + f'.part{number:03d}'
        target = PORTABLE / 'simulation' / name
        with target.open('xb') as out:
            out.write(block)
        parts.append({'index': number, 'name': name, **identity(target)})
save_json('simulation/wdb-parts.json', {
    'format': 'starlink-portable-gzip-parts-v1', 'max_part_bytes': part_limit,
    'gzip': {'name': compressed.name, **compressed_identity},
    'uncompressed': {'name': wdb.name, **wdb_identity}, 'parts': parts})
copy_file(Path('/tmp/starlink-rom-prefetch.j829ht/fw/hdl/library/starlink_pss_acquisition/evidence/exact-control-combined-actual-v1/reconstruct_wdb_parts.py'),
          'reconstruct_wdb_parts.py')

api = runpy.run_path(str(PREPARED / 'frozen_sources/prepare_rom_read_ahead_actual.py'))
settings = api['verify_prepared'](PREPARED)
try:
    api['verify_result'](SIM / 'simulate.log', 1, 1, PREPARED / 'frozen_sources')
except ValueError as failure:
    rejection = str(failure)
else:
    raise AssertionError('incomplete actual result unexpectedly accepted')
fresh = subprocess.check_output(['sha256sum', 'SHA256SUMS',
    'frozen_sources/simulate_exact_control_prepared.tcl'], cwd=PREPARED)
assert fresh == (OWNER / 'before.sha256').read_bytes()
assert identity(PREPARED / 'SHA256SUMS')['sha256'] == '6f5eddb99510e869bbe65548acc6ed64cd76bd98908aacfcd6e1c0361ccbe4ae'
assert not (OWNER / 'after.sha256').read_bytes()
save_json('fresh-read-only-audit.json', {
    'scope': 'new_read_only_observation_not_repaired_original_receipt',
    'original_handle': 23845, 'tool_observed_exit': 1, 'settings': settings,
    'all_56_source_members_verified': True,
    'exact_manifest': identity(PREPARED / 'SHA256SUMS'),
    'stored_before_after_equal': False, 'original_after_hash_file_bytes': 0,
    'fresh_hashes_equal_original_before': True, 'result_rejection': rejection,
    'extra_CSVs_present': [(SIM / name).exists() for name in
        ('exact_control_extra_trace.csv', 'exact_control_reference_extra_trace.csv')],
    'qualification': False})
save_json('raw-artifact-identities.json', raw)
copy_file(Path(__file__), 'packaging/package_failure.py')
print(json.dumps({'portable': str(PORTABLE), 'parts': len(parts),
    'wdb': wdb_identity, 'gzip': compressed_identity, 'source_members': 56,
    'result_rejection': rejection}, indent=2))
