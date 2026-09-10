"""Lossless offline evidence packaging only; no test or vendor execution."""
import gzip
import hashlib
import io
import json
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ATTEMPT = Path('/home/mouse9911/gits/starlink-build-recovery-20260910.vHzUVnBz/product-final-physical-offline-v1.0wLqPlbi')
PREPARED = Path('/home/mouse9911/gits/starlink-build-recovery-20260910.vHzUVnBz/product-final-physical-prepared-v1')
TOOLS = PREPARED.with_name(PREPARED.name + '-tools')
FW = Path('/tmp/starlink-rom-prefetch.j829ht/fw')
STAGE = ROOT / 'stage'
STAGE.mkdir()
raw, excluded = {}, []

def copy(source, name):
    if source.is_symlink():
        excluded.append({'path': str(source), 'archive_label': name, 'target': str(source.readlink())})
        return
    if not source.is_file():
        return
    data = source.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    compressed = len(data) > 512 * 1024
    if compressed:
        name += '.gz'
    target = STAGE / name
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open('xb') as output:
        output.write(gzip.compress(data, mtime=0) if compressed else data)
    assert hashlib.sha256(source.read_bytes()).hexdigest() == digest
    check = target.read_bytes()
    if compressed:
        check = gzip.decompress(check)
    assert check == data
    raw[name] = {'original_path': str(source), 'bytes': len(data),
                 'sha256': digest, 'compression': 'gzip' if compressed else 'none'}

for source in sorted(ATTEMPT.rglob('*')):
    copy(source, 'attempt/' + source.relative_to(ATTEMPT).as_posix())
for source in sorted(PREPARED.rglob('*')):
    copy(source, 'final-prepared/' + source.relative_to(PREPARED).as_posix())
for source in sorted(TOOLS.rglob('*')):
    copy(source, 'final-tools/' + source.relative_to(TOOLS).as_posix())
for name in (
    'hdl/library/starlink_pss_acquisition/prepare_exact_control_physical.py',
    'hdl/library/starlink_pss_acquisition/prepare_fault_cdc_physical.py',
    'hdl/library/starlink_pss_acquisition/prepare_rom_read_ahead_physical.py',
    'hdl/library/starlink_pss_acquisition/prepare_product_final_fence_physical.py',
    'tests/starlink_oracle/test_rom_physical_preparation.py',
    'tests/starlink_oracle/test_product_final_physical_preparation.py',
):
    copy(FW / name, 'source/' + name)
copy(Path(__file__), 'packaging/archive_preparation.py')
with (STAGE / 'raw-identities-and-symlink-exclusions.json').open('x') as output:
    json.dump({'raw': raw, 'excluded_symlinks': excluded,
               'scope': 'excluded_link_metadata_retained_no_original_link_changed'}, output, indent=2, sort_keys=True)
    output.write('\n')
files = sorted(p for p in STAGE.rglob('*') if p.is_file())
assert files and len(files) < 10000 and sum(p.stat().st_size for p in files) < 128 * 1024**2
assert max(p.stat().st_size for p in files) <= 40 * 1024**2
hashes = {p.relative_to(STAGE).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in files}
receipt = {'scope': 'retained_offline_P1_physical_preparation_NO_vendor_run_in_this_package',
           'members': len(files), 'file_sha256': hashes}
archive_path = ROOT / '20260910-product-final-physical-preparation-v1.tgz'
with tarfile.open(archive_path, 'x:gz') as archive:
    for path in files:
        name = path.relative_to(STAGE).as_posix()
        data = path.read_bytes()
        assert hashlib.sha256(data).hexdigest() == hashes[name]
        item = tarfile.TarInfo(name)
        item.size = len(data)
        archive.addfile(item, io.BytesIO(data))
    data = (json.dumps(receipt, sort_keys=True, indent=2) + '\n').encode()
    item = tarfile.TarInfo('receipt.json')
    item.size = len(data)
    archive.addfile(item, io.BytesIO(data))
receipt['archive_sha256'] = hashlib.sha256(archive_path.read_bytes()).hexdigest()
receipt['archive_bytes'] = archive_path.stat().st_size
with archive_path.with_suffix('.json').open('x') as output:
    json.dump(receipt, output, indent=2, sort_keys=True)
    output.write('\n')
print(json.dumps({key: value for key, value in receipt.items() if key != 'file_sha256'}, indent=2))
