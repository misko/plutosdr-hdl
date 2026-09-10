"""Offline-only, literal C1 extension of the frozen strict physical preparer."""

import argparse
import hashlib
import json
import os
import runpy
import shutil
import subprocess
from pathlib import Path

BASE_SHA = "0fee7f69b011d242cd4fe76f8e5374bc199ad525b49a962292e127cd5d0a6399"
OWNER_SHA = "d0f36ce2817ab20baaff8668b6743e367d296f7a60e714099fe69aa5b6912111"
ACTUAL_SHA = "9c81c43d9ed0bbc6cfba1d40074d11ec8cd94530fc9d7920de809bd6d68ce39c"
WRAPPER_SHA = "e8285f5ef2b548272ec357fca5213b1e400b5242396be2597498eff09f665579"
PYTHON = "/home/mouse9911/gits/pluto-plus-utils/.venv/bin/python"
CDC_ADMISSION = """    if (actual / "actual-process-exit.txt").read_text() != "0\\n":
        raise ValueError("original C1 process did not exit zero")
    cdc = runpy.run_path(str(frozen / "prepare_fault_cdc_actual.py"))
    if cdc["verify_result"](logfile, 1, frozen) != qualified:
        raise ValueError("C1 actual receipt/qualified status disagrees")
    if sha(frozen / "starlink_pss_fft_bank_owned_slice.v") != "e8285f5ef2b548272ec357fca5213b1e400b5242396be2597498eff09f665579":
        raise ValueError("requires exact tested C1 runtime")
"""
EXTRA_ADMISSION = """    if hashes["exact_control_extra_trace.csv"] != "b965d12603a64111fa9c6ea36cb0f12189945ad4d9be7cf4fbd883980c4ec4a0":
        raise ValueError("historical passing111 extra CSV differs")
"""
CDC_GENERIC_UNIQUE = """if {[lsearch -all -inline -glob $physical_generics PER_CAUSE_FAULT_CDC=*] ne [list PER_CAUSE_FAULT_CDC=1]} {
  error "requires exactly one explicit C1 physical parameter"
}
"""


def changes():
    """Each exact replacement is inverted in full before freezing the output."""
    return (
        (
            'ACTUAL_INVENTORY = "8e9251fe06e41917e9e0b5ebceef36db444bc39770efe7acb940dbfcc4ed7906"',
            f'ACTUAL_INVENTORY = "{ACTUAL_SHA}"',
        ),
        (
            '    "QUICK_MUTATION": 0,\n',
            '    "QUICK_MUTATION": 0,\n    "PER_CAUSE_FAULT_CDC": 1,\n',
        ),
        (
            'if {{$registered != 1 || $distributed != 1 || $scratch != 1}} {{ error "wrong combined physical options" }}',
            'if {{$registered != 1 || $distributed != 1 || $scratch != 1 || $per_cause != 1}} {{ error "wrong combined physical options" }}',
        ),
        (
            "PRIVATE_NEXT_START_SCRATCH $scratch] {",
            "PRIVATE_NEXT_START_SCRATCH $scratch PER_CAUSE_FAULT_CDC $per_cause] {",
        ),
        (
            '}\n"""\n\n\ndef sha(path):',
            "}\n" + CDC_GENERIC_UNIQUE + '"""\n\n\ndef sha(path):',
        ),
        (
            r'  PRIVATE_NEXT_START_SCRATCH=$scratch] [get_filesets sources_1]\n"',
            r'  PRIVATE_NEXT_START_SCRATCH=$scratch PER_CAUSE_FAULT_CDC=$per_cause] [get_filesets sources_1]\n"',
        ),
        (
            "distributed_fast_fault=$distributed; private_next_start_scratch=$scratch",
            "distributed_fast_fault=$distributed; private_next_start_scratch=$scratch; per_cause_fault_cdc=$per_cause",
        ),
        (
            '    )["verify_observation_receipt"](log, count)\n',
            '    )["verify_observation_receipt"](log, count)\n' + CDC_ADMISSION,
        ),
        (
            '        raise ValueError("independent extra CSVs differ or are empty")\n',
            '        raise ValueError("independent extra CSVs differ or are empty")\n'
            + EXTRA_ADMISSION,
        ),
        (
            '        "exact_control_terminal": terminal[0],\n',
            (
                '        "exact_control_terminal": terminal[0],\n'
                '        "cdc_terminal": re.findall(r"^FAULT_CDC_ACTUAL_PASS[^\\n]*$", log, re.MULTILINE)[0],\n'
            ),
        ),
        (
            "        f\"set distributed {options['DISTRIBUTED_FAST_FAULT']}\\n\"\n",
            (
                "        f\"set distributed {options['DISTRIBUTED_FAST_FAULT']}\\n\"\n"
                "        f\"set per_cause {options['PER_CAUSE_FAULT_CDC']}\\n\"\n"
            ),
        ),
        ('        "scratch": 1,\n', '        "scratch": 1,\n        "per_cause": 1,\n'),
        (
            "OFFLINE_ONLY_exact111_physical_preparation_NO_synthesis_route",
            "OFFLINE_ONLY_exact111C1_physical_preparation_NO_synthesis_route",
        ),
    )


def identity(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def adapt(source):
    if hashlib.sha256(source.encode()).hexdigest() != BASE_SHA:
        raise ValueError("requires literal reviewed strict physical helper")
    for old, new in changes():
        if source.count(old) != 1:
            raise ValueError("nonunique C1 physical adapter anchor: " + old)
        source = source.replace(old, new, 1)
    return source


def restore(source):
    for old, new in reversed(changes()):
        if source.count(new) != 1:
            raise ValueError("nonunique C1 physical inverse anchor")
        source = source.replace(new, old, 1)
    if hashlib.sha256(source.encode()).hexdigest() != BASE_SHA:
        raise ValueError("C1 inverse does not restore the entire reviewed helper")
    return source


def prepare(actual, output):
    tool_copy = output.with_name(output.name + "-tools")
    for path in (output, tool_copy):
        if path.exists() or any(p.is_symlink() for p in (path, *path.parents)):
            raise FileExistsError("refusing to overwrite/alias C1 physical preparation")
    if actual.is_symlink() or (actual / "frozen_sources").is_symlink():
        raise ValueError("symlinked C1 actual source is not admitted")
    acq = Path(__file__).resolve().parent
    original = (acq / "prepare_exact_control_physical.py").read_text()
    transformed = adapt(original)
    assert restore(transformed) == original
    if identity(acq / "run_exact_control_synthesis.py") != OWNER_SHA:
        raise ValueError("reviewed external owner changed")
    # Staging only: no tool launches. The copied helper retains its filename
    # and all old functions; only the reviewed C1 additions above differ.
    tool_copy.mkdir()
    base = runpy.run_path(str(acq / "prepare_exact_control_physical.py"))
    for name, digest in base["FIXED"].items():
        if identity(acq / name) != digest:
            raise ValueError("reviewed physical script/constraint changed: " + name)
        shutil.copyfile(acq / name, tool_copy / name)
    shutil.copyfile(
        acq / "run_exact_control_synthesis.py",
        tool_copy / "run_exact_control_synthesis.py",
    )
    helper = tool_copy / "prepare_exact_control_physical.py"
    helper.write_text(transformed)
    environment = os.environ.copy()
    for key in ("PYTHONHOME", "PYTHONPATH", "LD_LIBRARY_PATH"):
        environment.pop(key, None)
    result = subprocess.run(
        [PYTHON, "-B", str(helper), "--actual", str(actual), "--output", str(output)],
        env=environment,
        capture_output=True,
        text=True,
        check=False,
    )
    (tool_copy / "prepare-stdout.log").write_text(result.stdout)
    (tool_copy / "prepare-stderr.log").write_text(result.stderr)
    if result.returncode:
        raise ValueError("offline C1 physical admission failed: " + result.stderr)
    return json.loads(result.stdout)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--actual", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(prepare(args.actual, args.output), sort_keys=True))


if __name__ == "__main__":
    main()
