"""Offline-only exact P1 extension of the frozen K1/M1 physical recipe."""
import argparse
import hashlib
import json
import os
import runpy
import shutil
import subprocess
from pathlib import Path

ROM_GENERATOR_SHA = "2f00d50a175fa087596b6164831ca2c8a55a168f103469ceb2a7dd924f5b78d0"
ROM_HELPER_SHA = "73553095e0ea15305e542b8dc76a5a58164ea976363a8719207ccb27461bd664"
ACTUAL_INVENTORY = "7adf2efa0a242b89ccfbb387b00210e76841ba544cbae4cef97efc861acf59b2"
PYTHON = "/home/mouse9911/gits/pluto-plus-utils/.venv/bin/python"
MAILBOX_LIST_ADDITION = '''    original = once(original,
        "starlink_pss_realtime_result_guard starlink_pss_block_mailbox\\n",
        "starlink_pss_realtime_result_guard starlink_pss_block_mailbox starlink_pss_product_fence_mailbox\\n")
'''
RUNTIME_CHECK = '''    for name, digest in {
        "starlink_pss_fft_bank_owned_product_fence.v": "8923b42b3574fc1418eee99c5f5819f173c73fbf7b8bb65726a7ab3a5d8a6f7c",
        "starlink_pss_product_fence_mailbox.v": "e4f4c56ddab8f05d0f9b9da9a75f975e11cb8ad441581c904bfb094f3013982f",
    }.items():
        if sha(frozen / name) != digest:
            raise ValueError("requires exact tested producer-final runtime: " + name)
'''


def changes():
    return [
        ('ACTUAL_INVENTORY = "6f5eddb99510e869bbe65548acc6ed64cd76bd98908aacfcd6e1c0361ccbe4ae"',
         f'ACTUAL_INVENTORY = "{ACTUAL_INVENTORY}"', 1),
        ('    "PRIVATE_BLOCK_METADATA_READ_AHEAD": 1,\n',
         '    "PRIVATE_BLOCK_METADATA_READ_AHEAD": 1,\n    "PRODUCER_LOCAL_FINAL_FENCE": 1,\n', 1),
        ('        "fft_bank_owned_rom_read_ahead",\n', '        "fft_bank_owned_product_fence",\n', 1),
        ('        "block_mailbox",\n', '        "block_mailbox",\n        "product_fence_mailbox",\n', 1),
        (' || $rom_metadata != 1}}', ' || $rom_metadata != 1 || $producer_final != 1}}', 1),
        (' PRIVATE_BLOCK_METADATA_READ_AHEAD $rom_metadata] {',
         ' PRIVATE_BLOCK_METADATA_READ_AHEAD $rom_metadata PRODUCER_LOCAL_FINAL_FENCE $producer_final] {', 1),
        ('foreach name {PRIVATE_ROM_READ_AHEAD PRIVATE_BLOCK_METADATA_READ_AHEAD} {',
         'foreach name {PRIVATE_ROM_READ_AHEAD PRIVATE_BLOCK_METADATA_READ_AHEAD PRODUCER_LOCAL_FINAL_FENCE} {', 1),
        (' PRIVATE_BLOCK_METADATA_READ_AHEAD=$rom_metadata] [get_filesets sources_1]',
         ' PRIVATE_BLOCK_METADATA_READ_AHEAD=$rom_metadata PRODUCER_LOCAL_FINAL_FENCE=$producer_final] [get_filesets sources_1]', 1),
        ('; private_block_metadata_read_ahead=$rom_metadata',
         '; private_block_metadata_read_ahead=$rom_metadata; producer_local_final_fence=$producer_final', 1),
        ('("starlink_pss_fft_bank_owned_slice", "starlink_pss_fft_bank_owned_rom_read_ahead")',
         '("starlink_pss_fft_bank_owned_slice", "starlink_pss_fft_bank_owned_product_fence")', 1),
        ('    return original\n\n\ndef verify_actual(actual):',
         MAILBOX_LIST_ADDITION + '    return original\n\n\ndef verify_actual(actual):', 1),
        ('metadata = json.loads((actual / "preparation.json").read_text())',
         'metadata = json.loads((actual / "fence-preparation.json").read_text())', 1),
        ('rom-actual-owner-v1', 'product-final-actual-owner-v1', 7),
        ('4c5db6e2acade10b16ccf71ec1e458bad61b63a4ddf5f9055519d57edd420631',
         '62e4fa75b645f200b9c6bbccc0a43cf6e7cda0c2f58d04245128f5da9b24cb68', 1),
        ('9f198abf60d9119eae2ef565ae3d65b64104f93ce5f1b5be4b2e89776dd3deed',
         '2d3b5008f0d087614000ae518421cd9d800aadeb98a747f47fce01d8e76cc6e3', 1),
        ('prepare_rom_read_ahead_actual.py', 'prepare_product_final_fence_actual.py', 1),
        ('rom["verify_result"](logfile, 1, 1, frozen)', 'rom["verify_result"](logfile, 1, frozen)', 1),
        ('    if rom_qualified != qualified:\n', RUNTIME_CHECK + '    if rom_qualified != qualified:\n', 1),
        ('        "rom_terminal": re.findall(r"^ROM_READ_AHEAD_ACTUAL_PASS[^\\n]*$", log, re.MULTILINE)[0],\n',
         '        "rom_terminal": re.findall(r"^ROM_READ_AHEAD_ACTUAL_PASS[^\\n]*$", log, re.MULTILINE)[0],\n        "product_final_terminal": re.findall(r"^PRODUCT_FINAL_FENCE_ACTUAL_PASS[^\\n]*$", log, re.MULTILINE)[0],\n', 1),
        ('        f"set rom_metadata {options[\'PRIVATE_BLOCK_METADATA_READ_AHEAD\']}\\n"\n',
         '        f"set rom_metadata {options[\'PRIVATE_BLOCK_METADATA_READ_AHEAD\']}\\n"\n        f"set producer_final {options[\'PRODUCER_LOCAL_FINAL_FENCE\']}\\n"\n', 1),
        ('        "rtl_count": 7,\n', '        "rtl_count": 8,\n        "producer_final": 1,\n', 1),
        ('OFFLINE_ONLY_exact111C1K1M1_physical_preparation_NO_synthesis_route',
         'OFFLINE_ONLY_exact111C1K1M1P1_physical_preparation_NO_synthesis_route', 1),
    ]


def identity(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def adapt(source):
    if hashlib.sha256(source.encode()).hexdigest() != ROM_HELPER_SHA:
        raise ValueError("requires complete reviewed ROM physical helper")
    for old, new, count in changes():
        if source.count(old) != count:
            raise ValueError("nonunique product-final physical anchor: " + old)
        source = source.replace(old, new)
    return source


def restore(source):
    for old, new, count in reversed(changes()):
        if source.count(new) != count:
            raise ValueError("nonunique product-final physical inverse anchor")
        source = source.replace(new, old)
    if hashlib.sha256(source.encode()).hexdigest() != ROM_HELPER_SHA:
        raise ValueError("product-final inverse does not restore entire ROM helper")
    return source


def prepare(actual, output):
    tools = output.with_name(output.name + "-tools")
    for path in (output, tools):
        if path.exists() or any(p.is_symlink() for p in (path, *path.parents)):
            raise FileExistsError("refusing overwrite/alias product-final physical preparation")
    if any(p.is_symlink() for anchor in (actual, actual / "frozen_sources") for p in (anchor, *anchor.parents)):
        raise ValueError("aliased product-final actual source")
    acq = Path(__file__).resolve().parent
    rom_path = acq / "prepare_rom_read_ahead_physical.py"
    if identity(rom_path) != ROM_GENERATOR_SHA:
        raise ValueError("reviewed ROM generator changed")
    rom = runpy.run_path(str(rom_path))
    c1_path = acq / "prepare_fault_cdc_physical.py"
    if identity(c1_path) != rom["C1_GENERATOR_SHA"]:
        raise ValueError("reviewed C1 generator changed")
    c1 = runpy.run_path(str(c1_path))
    original = (acq / "prepare_exact_control_physical.py").read_text()
    rom_source = rom["adapt"](c1["adapt"](original))
    transformed = adapt(rom_source)
    assert c1["restore"](rom["restore"](restore(transformed))) == original
    if identity(acq / "run_exact_control_synthesis.py") != rom["OWNER_SHA"]:
        raise ValueError("reviewed synthesis owner changed")
    base = runpy.run_path(str(acq / "prepare_exact_control_physical.py"))
    for name, digest in base["FIXED"].items():
        if identity(acq / name) != digest:
            raise ValueError("reviewed physical script/constraint changed: " + name)
    tools.mkdir()
    for name in (*base["FIXED"], "run_exact_control_synthesis.py"):
        shutil.copyfile(acq / name, tools / name)
    helper = tools / "prepare_exact_control_physical.py"
    helper.write_text(transformed)
    environment = os.environ.copy()
    for key in ("PYTHONHOME", "PYTHONPATH", "LD_LIBRARY_PATH"):
        environment.pop(key, None)
    result = subprocess.run([PYTHON, "-B", str(helper), "--actual", str(actual), "--output", str(output)],
        env=environment, capture_output=True, text=True, check=False)
    (tools / "prepare-stdout.log").write_text(result.stdout)
    (tools / "prepare-stderr.log").write_text(result.stderr)
    if result.returncode:
        raise ValueError("offline product-final physical admission failed: " + result.stderr)
    return json.loads(result.stdout)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--actual", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(prepare(args.actual, args.output), sort_keys=True))
