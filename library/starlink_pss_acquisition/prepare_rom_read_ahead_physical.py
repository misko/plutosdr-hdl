"""Offline-only, literal K1/M1 extension of the reviewed C1 physical recipe."""

import argparse
import hashlib
import json
import os
import runpy
import shutil
import subprocess
from pathlib import Path

C1_GENERATOR_SHA = "4ecdc1264f062765f41b691450988f523f8fef93808f5516fa9d1f38310b68a5"
C1_HELPER_SHA = "c3e4d4ebc46928bb15b9134e3c4e056803cbec34f3389c8e7c22001669cde45a"
ACTUAL_SHA = "6f5eddb99510e869bbe65548acc6ed64cd76bd98908aacfcd6e1c0361ccbe4ae"
OWNER_SHA = "d0f36ce2817ab20baaff8668b6743e367d296f7a60e714099fe69aa5b6912111"
PYTHON = "/home/mouse9911/gits/pluto-plus-utils/.venv/bin/python"
NAMES = {
    "starlink_pss_fft_bank_owned_slice": "starlink_pss_fft_bank_owned_rom_read_ahead",
    "starlink_pss_forward_kernel_join": "starlink_pss_forward_kernel_join_read_ahead",
    "starlink_pss_kernel_rom": "starlink_pss_kernel_rom_read_ahead",
}
ROM_GENERIC_UNIQUE = """foreach name {PRIVATE_ROM_READ_AHEAD PRIVATE_BLOCK_METADATA_READ_AHEAD} {
  if {[lsearch -all -inline -glob $physical_generics ${name}=*] ne [list ${name}=1]} {
    error "requires exactly one explicit ROM physical parameter $name"
  }
}
"""
ROM_ADMISSION = '''    owner = actual.parent / "rom-actual-owner-v1"
    for anchor in (actual, frozen, owner):
        if any(p.is_symlink() for p in (anchor, *anchor.parents)):
            raise ValueError("aliased ROM actual evidence")
    for name in ("process-exit.txt", "after-integrity-exit.txt", "after-ip-exit.txt", "receipt-exit.txt"):
        if (owner / name).read_text() != "0\\n":
            raise ValueError("ROM actual persisted status is not zero: " + name)
    if sha(owner / "owner.sh") != "4c5db6e2acade10b16ccf71ec1e458bad61b63a4ddf5f9055519d57edd420631":
        raise ValueError("ROM actual owner differs from reviewed path-only source")
    expected_hashes = (ACTUAL_INVENTORY + "  SHA256SUMS\\n" +
        "9f198abf60d9119eae2ef565ae3d65b64104f93ce5f1b5be4b2e89776dd3deed  frozen_sources/simulate_exact_control_prepared.tcl\\n")
    if any((owner / name).read_text() != expected_hashes for name in ("before.sha256", "after.sha256")):
        raise ValueError("ROM actual stored pre/post inventory or runner differs")
    rom = runpy.run_path(str(frozen / "prepare_rom_read_ahead_actual.py"))
    if rom["verify_prepared"](actual) != SETTINGS:
        raise ValueError("ROM actual full inherited source/binding differs")
    rom_qualified = rom["verify_result"](logfile, 1, 1, frozen)
    ip = json.loads((owner / "after-ip.json").read_text())
    if (ip.get("scope") != "generated_IP_after_run_only_not_precompile_equivalence" or
            ip.get("project_present") is not True or len(ip.get("files", {})) != 19):
        raise ValueError("ROM actual after-only IP receipt incomplete")
    for name, item in ip["files"].items():
        relative = Path(name)
        if relative.is_absolute() or ".." in relative.parts or relative.suffix not in (".vhd", ".xci"):
            raise ValueError("unsafe ROM actual IP path")
        path = actual / "project" / relative
        if path.is_symlink() or path.stat().st_size != item["bytes"] or sha(path) != item["sha256"]:
            raise ValueError("ROM actual after-only generated IP differs")
'''


def changes():
    source_changes = "".join(
        f'        ("{old}", "{new}"),\n' for old, new in NAMES.items()
    )
    # These three renames operate only on the synthesis Tcl text, never RTL.
    return (
        ('ACTUAL_INVENTORY = "9c81c43d9ed0bbc6cfba1d40074d11ec8cd94530fc9d7920de809bd6d68ce39c"',
         f'ACTUAL_INVENTORY = "{ACTUAL_SHA}"'),
        ('    "PER_CAUSE_FAULT_CDC": 1,\n', '    "PER_CAUSE_FAULT_CDC": 1,\n    "PRIVATE_ROM_READ_AHEAD": 1,\n    "PRIVATE_BLOCK_METADATA_READ_AHEAD": 1,\n'),
        ('        "fft_bank_owned_slice",\n', '        "fft_bank_owned_rom_read_ahead",\n'),
        ('        "forward_kernel_join",\n', '        "forward_kernel_join_read_ahead",\n'),
        ('        "kernel_rom",\n', '        "kernel_rom_read_ahead",\n'),
        (' || $per_cause != 1}}', ' || $per_cause != 1 || $rom_word != 1 || $rom_metadata != 1}}'),
        (' PER_CAUSE_FAULT_CDC $per_cause] {', ' PER_CAUSE_FAULT_CDC $per_cause PRIVATE_ROM_READ_AHEAD $rom_word PRIVATE_BLOCK_METADATA_READ_AHEAD $rom_metadata] {'),
        ('}\n"""\n\n\ndef sha(path):', '}\n' + ROM_GENERIC_UNIQUE + '"""\n\n\ndef sha(path):'),
        (r'PER_CAUSE_FAULT_CDC=$per_cause] [get_filesets sources_1]\n"',
         r'PER_CAUSE_FAULT_CDC=$per_cause PRIVATE_ROM_READ_AHEAD=$rom_word PRIVATE_BLOCK_METADATA_READ_AHEAD=$rom_metadata] [get_filesets sources_1]\n"'),
        ('; per_cause_fault_cdc=$per_cause', '; per_cause_fault_cdc=$per_cause; private_rom_read_ahead=$rom_word; private_block_metadata_read_ahead=$rom_metadata'),
        ('    for old, new in changes:\n        original = once(original, old, new)\n    return original\n',
         '    for old, new in changes:\n        original = once(original, old, new)\n    for old, new in (\n' + source_changes + '    ):\n        original = original.replace(old, new)\n    return original\n'),
        ('        "actual-before-source-verification.log",\n        "actual-after-source-verification.log",',
         '        "before-integrity.log",\n        "after-integrity.log",'),
        ('        if (actual / name).read_text() != expected_snapshot:',
         '        if (actual.parent / "rom-actual-owner-v1" / name).read_text() != expected_snapshot:'),
        ('actual / "actual-time.txt"', 'actual.parent / "rom-actual-owner-v1/time.txt"'),
        ('actual / "actual-launch.log"', 'actual.parent / "rom-actual-owner-v1/launch.log"'),
        ('actual / "actual-process-exit.txt"', 'actual.parent / "rom-actual-owner-v1/process-exit.txt"'),
        ('    frozen = actual / "frozen_sources"\n', '    frozen = actual / "frozen_sources"\n' + ROM_ADMISSION),
        ('        raise ValueError("requires exact tested C1 runtime")\n',
         '        raise ValueError("requires exact tested C1 runtime")\n    if rom_qualified != qualified:\n        raise ValueError("ROM and original qualified-status receipts disagree")\n'),
        ('        "cdc_terminal": re.findall(r"^FAULT_CDC_ACTUAL_PASS[^\\n]*$", log, re.MULTILINE)[0],\n',
         '        "cdc_terminal": re.findall(r"^FAULT_CDC_ACTUAL_PASS[^\\n]*$", log, re.MULTILINE)[0],\n        "rom_terminal": re.findall(r"^ROM_READ_AHEAD_ACTUAL_PASS[^\\n]*$", log, re.MULTILINE)[0],\n        "rom_owner_sha256": {p.name: sha(p) for p in sorted(owner.iterdir()) if p.is_file()},\n        "rom_generated_IP_after_only": ip,\n'),
        ('        f"set per_cause {options[\'PER_CAUSE_FAULT_CDC\']}\\n"\n',
         '        f"set per_cause {options[\'PER_CAUSE_FAULT_CDC\']}\\n"\n        f"set rom_word {options[\'PRIVATE_ROM_READ_AHEAD\']}\\n"\n        f"set rom_metadata {options[\'PRIVATE_BLOCK_METADATA_READ_AHEAD\']}\\n"\n'),
        ('        "per_cause": 1,\n', '        "per_cause": 1,\n        "rom_word": 1,\n        "rom_metadata": 1,\n'),
        ('OFFLINE_ONLY_exact111C1_physical_preparation_NO_synthesis_route',
         'OFFLINE_ONLY_exact111C1K1M1_physical_preparation_NO_synthesis_route'),
    )


def identity(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def adapt(source):
    if hashlib.sha256(source.encode()).hexdigest() != C1_HELPER_SHA:
        raise ValueError("requires complete reviewed C1 physical helper")
    for old, new in changes():
        expected = 2 if old in ('actual / "actual-time.txt"', 'actual / "actual-launch.log"') else 1
        if source.count(old) != expected:
            raise ValueError("nonunique ROM physical anchor: " + old)
        source = source.replace(old, new)
    return source


def restore(source):
    for old, new in reversed(changes()):
        expected = 2 if old in ('actual / "actual-time.txt"', 'actual / "actual-launch.log"') else 1
        if source.count(new) != expected:
            raise ValueError("nonunique ROM physical inverse anchor")
        source = source.replace(new, old)
    if hashlib.sha256(source.encode()).hexdigest() != C1_HELPER_SHA:
        raise ValueError("ROM inverse does not restore complete C1 helper")
    return source


def prepare(actual, output):
    tools = output.with_name(output.name + "-tools")
    for path in (output, tools):
        if path.exists() or any(p.is_symlink() for p in (path, *path.parents)):
            raise FileExistsError("refusing to overwrite/alias ROM physical preparation")
    if any(p.is_symlink() for anchor in (actual, actual / "frozen_sources") for p in (anchor, *anchor.parents)):
        raise ValueError("aliased ROM actual source")
    acq = Path(__file__).resolve().parent
    c1_path = acq / "prepare_fault_cdc_physical.py"
    if identity(c1_path) != C1_GENERATOR_SHA:
        raise ValueError("reviewed C1 generator changed")
    c1 = runpy.run_path(str(c1_path))
    original = (acq / "prepare_exact_control_physical.py").read_text()
    c1_source = c1["adapt"](original)
    transformed = adapt(c1_source)
    assert c1["restore"](restore(transformed)) == original
    if identity(acq / "run_exact_control_synthesis.py") != OWNER_SHA:
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
        raise ValueError("offline ROM physical admission failed: " + result.stderr)
    return json.loads(result.stdout)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--actual", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(prepare(args.actual, args.output), sort_keys=True))


if __name__ == "__main__":
    main()
