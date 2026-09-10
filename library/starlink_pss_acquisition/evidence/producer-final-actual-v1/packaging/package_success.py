"""One-shot lossless packaging of terminal 50316; never run vendor tools."""
import gzip
import hashlib
import json
import runpy
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PREPARED = Path('/home/mouse9911/gits/starlink-build-recovery-20260910.vHzUVnBz/product-final-actual-prepared-v1')
OWNER = PREPARED.parent / 'product-final-actual-owner-v1'
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
    if source.name == 'tmp':
        assert source.is_dir() and not source.is_symlink()
        continue  # Original scratch directory retained locally, not runtime evidence.
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
save_json('generated-ip-after-terminal.json', {
    'scope': 'fresh_read_only_after_terminal_not_precompile_equality', 'files': ip})

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

api = runpy.run_path(str(PREPARED / 'frozen_sources/prepare_product_final_fence_actual.py'))
settings = api['verify_prepared'](PREPARED)
result = api['verify_result'](SIM / 'simulate.log', 1, PREPARED / 'frozen_sources')
fresh = subprocess.check_output(['sha256sum', 'SHA256SUMS',
    'frozen_sources/simulate_exact_control_prepared.tcl'], cwd=PREPARED)
assert fresh == (OWNER / 'before.sha256').read_bytes()
assert identity(PREPARED / 'SHA256SUMS')['sha256'] == '7adf2efa0a242b89ccfbb387b00210e76841ba544cbae4cef97efc861acf59b2'
assert fresh == (OWNER / 'after.sha256').read_bytes()
for name in ('process-exit.txt', 'after-integrity-exit.txt', 'after-ip-exit.txt', 'receipt-exit.txt'):
    assert (OWNER / name).read_bytes() == b'0\n'
save_json('fresh-read-only-audit.json', {
    'scope': 'actual_qualified_status_ROM_and_sampled_product_final_NOT_raw217_or_physical',
    'original_handle': 50316, 'tool_observed_exit': 0, 'settings': settings,
    'tested_fw': 'b187e467e948362500e531935f9fd92756aa1b22',
    'tested_hdl': '420606aa1cd7e7691332387782a894fc88cda7d7',
    'all_65_source_members_verified': True,
    'exact_manifest': identity(PREPARED / 'SHA256SUMS'),
    'stored_before_after_equal': True, 'original_after_hash_file_bytes': len(fresh),
    'fresh_hashes_equal_original_before': True, 'frozen_result': result,
    'extra_CSVs_present': [(SIM / name).exists() for name in
        ('exact_control_extra_trace.csv', 'exact_control_reference_extra_trace.csv')],
    'simulation_scope_pass': True})
csv = {}
for name, expected in (
    ('fft_bank_owned_trace.csv', '25ab9d06ca0e03f280540cda625a7826b3c4cbaa6322ce3266c59e1fbad94122'),
    ('exact_control_reference_trace.csv', '25ab9d06ca0e03f280540cda625a7826b3c4cbaa6322ce3266c59e1fbad94122'),
    ('exact_control_extra_trace.csv', 'b965d12603a64111fa9c6ea36cb0f12189945ad4d9be7cf4fbd883980c4ec4a0'),
    ('exact_control_reference_extra_trace.csv', 'b965d12603a64111fa9c6ea36cb0f12189945ad4d9be7cf4fbd883980c4ec4a0')):
    data = (SIM / name).read_bytes()
    assert hashlib.sha256(data).hexdigest() == expected and data.endswith(b'\n')
    csv[name] = {'bytes': len(data), 'lines': data.count(b'\n'), 'sha256': expected, 'newline_closed': True}
save_json('fresh-full-csv-audit.json', csv)
copy_file(Path('/tmp/starlink-rom-prefetch.j829ht/fw/docs/starlink-producer-final-actual-result-20260910.md'), 'report.md')
save_json('raw-artifact-identities.json', raw)
copy_file(Path(__file__), 'packaging/package_success.py')
print(json.dumps({'portable': str(PORTABLE), 'parts': len(parts),
    'wdb': wdb_identity, 'gzip': compressed_identity, 'source_members': 65,
    'frozen_result': result}, indent=2))
