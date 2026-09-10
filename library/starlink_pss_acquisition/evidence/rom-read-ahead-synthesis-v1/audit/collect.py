"""Copy bounded original synthesis evidence, retaining its source identities."""
import hashlib
import json
from pathlib import Path
import shutil

ROOT = Path('/home/mouse9911/gits/starlink-build-recovery-20260910.vHzUVnBz')
HERE = Path(__file__).parent
OUT = HERE / 'archive'
OUT.mkdir()
RUN = ROOT / 'rom-k1m1-synth-v1'
PREP = ROOT / 'rom-k1m1-physical-prepared-v1'
identities = {}

def identity(path):
    return {'bytes': path.stat().st_size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}

def copy(source, relative):
    assert source.is_file() and not source.is_symlink()
    dest = OUT / relative
    assert not dest.exists()
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, dest)
    expected = identity(source)
    assert identity(dest) == expected
    identities[str(relative)] = {'original': str(source), **expected}

for path in sorted(RUN.iterdir()):
    if path.is_file():
        copy(path, Path('run') / path.name)
for path in sorted((RUN / 'synthesis').iterdir()):
    if path.is_file():
        copy(path, Path('synthesis') / path.name)
for path in sorted((RUN / 'synthesis/frozen_sources').iterdir()):
    copy(path, Path('synthesis/frozen_sources') / path.name)
for path in sorted(PREP.rglob('*')):
    if path.is_file():
        copy(path, Path('prepared') / path.relative_to(PREP))
project = RUN / 'synthesis/project'
for path in sorted(project.rglob('*')):
    if not path.is_file() or path.is_symlink():
        continue
    rel = path.relative_to(project)
    if path.suffix in {'.xci', '.xdc', '.tcl', '.log', '.jou', '.rpt'} or '/synth/' in str(rel):
        copy(path, Path('project') / rel)
for name in ('audit.py', 'collect.py', 'independent-post-audit.json', 'frozen-helper-post-audit.log'):
    copy(HERE / name, Path('audit') / name)
copy(ROOT / 'rom-k1m1-synthesis-authorized-command-v1.txt', Path('run/authorized-command.txt'))
copy(ROOT / 'rom-k1m1-route-v1/own_route.py', Path('route-proposal/own_route.py'))
copy(ROOT / 'local-admission-route-v1.EzXzzuNB/own_route.py', Path('route-proposal/own_route.original.py'))
baseline = Path('/tmp/starlink-completed-input.5EaJuD/fault-cdc-synth-v1/synthesis')
for name in ('utilization.rpt', 'hierarchy.rpt', 'resource_receipt.txt', 'cdc_unqualified.rpt', 'synthesis_clocks.rpt', 'scope.txt'):
    copy(baseline / name, Path('baseline-C1-synthesis') / name)
with (OUT / 'raw-artifact-identities.json').open('x') as stream:
    json.dump(identities, stream, indent=2, sort_keys=True)
    stream.write('\n')
with (OUT / 'original-synthesis-file-inventory.json').open('x') as stream:
    json.dump({str(p.relative_to(RUN)): identity(p) for p in sorted(RUN.rglob('*')) if p.is_file() and not p.is_symlink()}, stream, indent=2, sort_keys=True)
    stream.write('\n')
print(json.dumps({'copied_original_files': len(identities), 'bytes': sum(x['bytes'] for x in identities.values()), 'archive': str(OUT)}, sort_keys=True))
