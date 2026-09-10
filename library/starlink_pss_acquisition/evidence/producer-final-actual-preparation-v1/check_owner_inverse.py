"""Read-only one-shot literal owner inverse; never executes the owner."""
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path('/home/mouse9911/gits/starlink-build-recovery-20260910.vHzUVnBz')
old = ROOT / 'rom-relocated-actual-v2.CWJkzwEi/rom-actual-owner-v1/owner.sh'
new = Path(__file__).parent / 'owner.sh'
assert hashlib.sha256(old.read_bytes()).hexdigest() == '4c5db6e2acade10b16ccf71ec1e458bad61b63a4ddf5f9055519d57edd420631'
assert hashlib.sha256(new.read_bytes()).hexdigest() == '62e4fa75b645f200b9c6bbccc0a43cf6e7cda0c2f58d04245128f5da9b24cb68'
added = """expected_snapshot = ('7adf2efa0a242b89ccfbb387b00210e76841ba544cbae4cef97efc861acf59b2  SHA256SUMS\\n'
    '2d3b5008f0d087614000ae518421cd9d800aadeb98a747f47fce01d8e76cc6e3  frozen_sources/simulate_exact_control_prepared.tcl\\n')
assert all((owner / name).read_text() == expected_snapshot for name in ('before.sha256', 'after.sha256'))
"""
text = new.read_text()
assert text.count(added) == 1
text = text.replace(added, '', 1)
changes = [
    (str(ROOT / 'rom-relocated-actual-v2.CWJkzwEi/rom-actual-prepared-v1'), str(ROOT / 'product-final-actual-prepared-v1'), 3),
    (str(ROOT / 'rom-relocated-actual-v2.CWJkzwEi/rom-actual-owner-v1'), str(ROOT / 'product-final-actual-owner-v1'), 2),
    ('6f5eddb99510e869bbe65548acc6ed64cd76bd98908aacfcd6e1c0361ccbe4ae', '7adf2efa0a242b89ccfbb387b00210e76841ba544cbae4cef97efc861acf59b2', 1),
    ('9f198abf60d9119eae2ef565ae3d65b64104f93ce5f1b5be4b2e89776dd3deed', '2d3b5008f0d087614000ae518421cd9d800aadeb98a747f47fce01d8e76cc6e3', 1),
    ('prepare_rom_read_ahead_actual.py', 'prepare_product_final_fence_actual.py', 2),
    ('bca85ff4affb7fd4650489103ee5750567fe031d225fda057303007defb840b3', '39141329e600b15c2ff9357d952d3cd148d6db3126fff2c394108073db49b853', 1),
    ("api['verify_result'](log, 1, 1, source)", "api['verify_result'](log, 1, source)", 1),
    ('actual_C1_plus_ROM_qualified_status_NOT_raw217_or_physical', 'actual_C1_ROM_final_fence_qualified_status_NOT_raw217_or_physical', 1),
]
for before, after, count in changes:
    assert text.count(after) == count
    text = text.replace(after, before)
assert text.encode() == old.read_bytes()
subprocess.run(['bash', '-n', str(new)], check=True)
print(json.dumps({'whole_inverse': True, 'literal_replacements': len(changes),
    'added_exact_snapshot_assertion_lines': 3, 'bash_syntax': 'PASS',
    'scope': 'OFFLINE_owner_not_executed',
    'owner_sha256': hashlib.sha256(new.read_bytes()).hexdigest()}, sort_keys=True))
