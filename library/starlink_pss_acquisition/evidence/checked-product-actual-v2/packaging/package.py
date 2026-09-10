"""One-shot lossless archive of original30484 FAIL and58385 functional PASS.

Reuses the already tested portable WDB part format/reconstruction helper.
No vendor tools and no changes to original run/source directories.
"""
import gzip
import hashlib
import json
import runpy
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RECOVERY = ROOT.parent
ACQ = Path('/tmp/starlink-rom-prefetch.j829ht/fw/hdl/library/starlink_pss_acquisition')
PORTABLE = ROOT / 'portable'
PORTABLE.mkdir()


def identity(path):
    with path.open('rb') as source:
        digest = hashlib.file_digest(source, 'sha256').hexdigest()
    return {'bytes': path.stat().st_size, 'sha256': digest}


def save(relative, value):
    path = PORTABLE / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('x') as out:
        json.dump(value, out, indent=2, sort_keys=True)
        out.write('\n')


raw = {}
def copy(source, relative, compress=False):
    if source.is_symlink():
        raise ValueError('aliased original artifact')
    before = identity(source)
    path = PORTABLE / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    with source.open('rb') as inp, path.open('xb') as out:
        if compress:
            with gzip.GzipFile(filename='', mode='wb', fileobj=out, mtime=0) as zipped:
                shutil.copyfileobj(inp, zipped, 1024 * 1024)
        else:
            shutil.copyfileobj(inp, out, 1024 * 1024)
    if identity(source) != before:
        raise ValueError('original changed during archive')
    raw[relative] = {'original_path': str(source), **before,
                     'compression': 'gzip' if compress else 'none'}


copy(ACQ / 'evidence/producer-final-actual-v1/reconstruct_wdb_parts.py', 'reconstruct_wdb_parts.py')
reconstruct = runpy.run_path(str(PORTABLE / 'reconstruct_wdb_parts.py'))['reconstruct']
outcomes = {}
for label, handle, owner_name, manifest, expected, cli_name in (
    ('v1', 30484, 'checked-actual-parent.xtGiofa6',
     '9b21ff51490f0deb87ae0b69a78e65e37895bb8006f67b2615a567e70e8e63c7', False,
     'prepare_checked_product_actual_run.py'),
    ('v2', 58385, 'checked-drain-actual-parent.wlpL6hYk',
     '55288860074df8107d142c97bd69cb67bc71815f13bbb8bacc3b664b9547f5ea', True,
     'prepare_checked_product_drain_actual.py'),
):
    prepared = RECOVERY / ('checked-product-actual-prepared-' + label)
    owner = RECOVERY / owner_name
    sim = prepared / 'project/exact_control_actual.sim/sim_1/behav/xsim'
    outcome = json.loads((owner / 'outcome.json').read_text())
    if outcome['functional_accepted'] is not expected or outcome['physical_qualified'] is not False:
        raise ValueError('original result scope differs')
    if identity(prepared / 'SHA256SUMS')['sha256'] != manifest:
        raise ValueError('original source inventory differs')
    members = 0
    for line in (prepared / 'SHA256SUMS').read_text().splitlines():
        digest, name = line.split('  ', 1)
        if identity(prepared / name)['sha256'] != digest:
            raise ValueError('original source changed: ' + name)
        copy(prepared / name, label + '/prepared/' + name)
        members += 1
    copy(prepared / 'SHA256SUMS', label + '/prepared/SHA256SUMS')
    for path in sorted(owner.iterdir()):
        if path.name == 'tmp':
            continue  # Original owner scratch retained locally.
        if path.name == '.Xil' and path.is_dir() and not path.is_symlink():
            for child in sorted(path.rglob('*')):
                if child.is_file():
                    copy(child, label + '/owner/' + str(child.relative_to(owner)))
            continue
        if not path.is_file():
            raise ValueError('unexpected owner entry')
        copy(path, label + '/owner/' + path.name)
    for path in sorted(sim.rglob('*')):
        if path.is_file() and path.suffix in ('.log', '.csv', '.jou', '.tcl', '.prj', '.sh'):
            copy(path, label + '/simulation/' + str(path.relative_to(sim)) + '.gz', True)
    ip = {}
    for path in sorted((prepared / 'project').rglob('*')):
        if path.is_file() and path.suffix in ('.xci', '.vhd'):
            name = str(path.relative_to(prepared / 'project'))
            ip[name] = identity(path)
            copy(path, label + '/generated-ip/' + name)
    if len(ip) != 19:
        raise ValueError('incomplete generated IP archive')
    save(label + '/generated-ip-after-terminal.json', {
        'scope': 'fresh_after_terminal_hashes_not_pre_generation_equivalence', 'files': ip})

    wdb = sim / 'tb_starlink_pss_fft_bank_owned_slice_behav.wdb'
    wdb_before = identity(wdb)
    compressed = ROOT / (label + '-' + wdb.name + '.gz')
    with wdb.open('rb') as inp, compressed.open('xb') as out:
        with gzip.GzipFile(filename='', mode='wb', fileobj=out, mtime=0) as zipped:
            shutil.copyfileobj(inp, zipped, 1024 * 1024)
    if identity(wdb) != wdb_before:
        raise ValueError('original WDB changed')
    parts, limit = [], 40 * 1024 * 1024
    portable_name = wdb.name + '.gz'
    with compressed.open('rb') as inp:
        while block := inp.read(limit):
            number = len(parts)
            name = portable_name + f'.part{number:03d}'
            target = PORTABLE / label / 'simulation' / name
            with target.open('xb') as out:
                out.write(block)
            parts.append({'index': number, 'name': name, **identity(target)})
    save(label + '/simulation/wdb-parts.json', {
        'format': 'starlink-portable-gzip-parts-v1', 'max_part_bytes': limit,
        'gzip': {'name': portable_name, **identity(compressed)},
        'uncompressed': {'name': wdb.name, **wdb_before}, 'parts': parts})
    reconstructed = reconstruct(PORTABLE / label / 'simulation/wdb-parts.json', ROOT / (label + '-reconstruction'))
    save(label + '/reconstruction-receipt.json', reconstructed)

    api = runpy.run_path(str(prepared / cli_name))
    settings = api['verify_prepared'](prepared)
    if expected:
        result = api['verify_result'](prepared)
        saved = json.loads((owner / 'result-check.json').read_text())
        if saved['exit'] != 0 or json.loads(saved['stdout']) != json.loads(json.dumps(result)):
            raise ValueError('fresh result differs from original owner')
        validation = {'accepted': True, 'result': result}
    else:
        gate = runpy.run_path(str(prepared / 'checked_product_actual_result.py'))
        try:
            gate['verify_result'](prepared)
        except ValueError as error:
            if str(error) != 'incomplete full trace/service profile or observer accounting':
                raise
            validation = {'accepted': False, 'original_failure_preserved': str(error)}
        else:
            raise ValueError('original failed run unexpectedly admitted')
    csvs = {}
    for name in ('fft_bank_owned_trace.csv', 'exact_control_extra_trace.csv', 'checked_product_ownership_trace.csv'):
        body = (sim / name).read_bytes()
        csvs[name] = {**identity(sim / name), 'lines': body.count(b'\n'), 'newline_closed': body.endswith(b'\n')}
    save(label + '/fresh-source-result-csv-audit.json', {
        'scope': 'functional_and_source_evidence_only_NOT_raw217_or_physical',
        'original_root_handle': handle, 'original_outcome': outcome, 'source_members': members,
        'inventory_sha256': manifest, 'settings': settings, 'fresh_validation': validation,
        'full_csvs': csvs})
    outcomes[label] = {'handle': handle, 'accepted': expected, 'source_members': members,
                       'wdb_parts': len(parts), 'wdb': wdb_before}
save('raw-artifact-identities.json', raw)
save('packaging-result.json', outcomes)
copy(Path(__file__), 'packaging/package.py')
print(json.dumps(outcomes, sort_keys=True))
