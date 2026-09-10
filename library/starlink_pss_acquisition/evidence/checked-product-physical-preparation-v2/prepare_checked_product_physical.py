"""Offline, source-specific checked-product extension of the reviewed P1 recipe.

No Vivado invocation. Admission requires the original root-owned actual outcome
and independently reruns the frozen changed-latency result gate. A pending or
failed actual run is not a physical source admission.
"""
import argparse
import hashlib
import json
import os
import runpy
import shutil
import subprocess
from pathlib import Path

P1_GENERATOR_SHA = "2b6174a783cb3f78cec9701dde6567d9302cf377074271db42891c392e323bc4"
P1_HELPER_SHA = "d22bda330f571774a3099d0da9615a6a445e58fb4aecf43d10e6657fc954e876"
ACTUAL_INVENTORY = "55288860074df8107d142c97bd69cb67bc71815f13bbb8bacc3b664b9547f5ea"
PYTHON = "/home/mouse9911/gits/pluto-plus-utils/.venv/bin/python"
NEW_RTL = (
    "fft_bank_owned_checked_product", "realtime_checked_product_input_guard",
    "realtime_result_guard_observe", "checked_product_read_observe",
    "product_sealed_observe", "epoch_sealed_publication_bank",
)
ADMISSION = '''def verify_actual(actual):
    owner = actual.parent / "checked-drain-actual-parent.wlpL6hYk"
    for anchor in (actual, owner):
        if any(p.is_symlink() for p in (anchor, *anchor.parents)):
            raise ValueError("aliased checked-product actual evidence")
    # Original owner completion is mandatory; never infer PASS from a live log.
    outcome = json.loads((owner / "outcome.json").read_text())
    required = {"vendor_exit": 0, "timed_out": False, "interruption": None,
        "source_pins_unchanged": True, "live_sources_unchanged": True,
        "generated_wrapper_matches_known": True, "result_exit": 0,
        "functional_accepted": True, "physical_qualified": False,
        "deployment_eligible": False}
    if any(type(outcome.get(k)) is not type(v) or outcome[k] != v for k, v in required.items()):
        raise ValueError("checked actual pending/failed/unqualified outcome")
    if sha(owner / "owner.py") != "d43778ae62b057bd5c08a7101d2f8556cac1a5199f61331498aa5c0c728b393d":
        raise ValueError("checked actual owner changed")
    if sha(actual / "SHA256SUMS") != ACTUAL_INVENTORY:
        raise ValueError("requires exact checked actual89 inventory")
    rows = {}
    for line in (actual / "SHA256SUMS").read_text().splitlines():
        expected, name = line.split("  ", 1)
        path = actual / name
        if name in rows or Path(name).is_absolute() or ".." in Path(name).parts or any(
                p.is_symlink() for p in (path, *path.parents)) or sha(path) != expected:
            raise ValueError("checked actual source changed: " + name)
        rows[name] = expected
    pins = json.loads((owner / "input-pins.json").read_text())
    after = json.loads((owner / "after-sources.json").read_text())
    if len(rows) != 89 or pins["manifest"] != ACTUAL_INVENTORY or pins["files"] != rows or after != {
            "manifest_unchanged": True, "source_errors": [], "live_errors": []}:
        raise ValueError("checked actual pre/post source closure differs")
    execution = json.loads((owner / "execution.json").read_text())
    if any(type(execution.get(k)) is not type(required[k]) or execution[k] != required[k]
            for k in ("vendor_exit", "timed_out", "interruption")):
        raise ValueError("original checked actual process failed")
    cli = actual / "prepare_checked_product_drain_actual.py"
    if sha(cli) != "bcd3c96b3f784b6ef7a12c5750e976d6d50c8eb19d13e4c6a3de3f08bcacfe6a" or sha(
            actual / "checked_product_actual_result.py") != "a04c648779af03ba0d156215fa274e5b2d4b92af7028fc38b95e66a35e452084":
        raise ValueError("changed checked actual admission/result policy")
    env = {k: v for k, v in __import__("os").environ.items()
        if k not in ("PYTHONHOME", "PYTHONPATH", "LD_LIBRARY_PATH", "PYTHONOPTIMIZE")}
    check = subprocess.run([PYTHON, "-B", str(cli), "--verify-result", str(actual)],
        cwd="/", env=env, capture_output=True, text=True, timeout=90, check=False)
    if check.returncode:
        raise ValueError("frozen checked actual result rejected: " + check.stderr)
    result = json.loads(check.stdout)
    drain = result.get("final_drain_witnesses")
    if not isinstance(drain, dict) or drain.get("scope") != "two_final_live_preedge_drains_after_unchanged_full_result_gate":
        raise ValueError("requires complete frozen drain-aware result")
    markers = drain.get("markers")
    if (not isinstance(markers, list) or len(markers) != 2 or any(
            not isinstance(row, list) or len(row) != 5 or any(type(value) is not int for value in row)
            for row in markers) or [row[:2] for row in markers] != [[0, 32], [1, 6]] or any(
            row[2] < 0 or row[3] - row[2] != row[4] or not 0 < row[4] <= 5215 for row in markers)):
        raise ValueError("requires exact two final drain receipts")
    old = json.loads((owner / "result-check.json").read_text())
    if type(old["exit"]) is not int or old["exit"] != 0 or json.loads(old["stdout"]) != result:
        raise ValueError("independent checked result differs from original owner")
    frozen = actual / "frozen_sources"
    binding = runpy.run_path(str(actual / "prepare_checked_product_actual.py"))
    metadata = json.loads((actual / "drain-preparation.json").read_text())
    if metadata["settings"] != SETTINGS or set(binding["RUNTIME_SHA"]) != set(RTL):
        raise ValueError("checked runtime/settings closure differs")
    for name, digest in binding["RUNTIME_SHA"].items():
        if sha(frozen / name) != digest:
            raise ValueError("checked runtime changed: " + name)
    ip = json.loads((owner / "generated-ip-after.json").read_text())
    files = ip["files"]
    if len(files) != 19:
        raise ValueError("incomplete after-only generated IP receipt")
    for name, item in files.items():
        path = actual / "project" / name
        if Path(name).is_absolute() or ".." in Path(name).parts or path.is_symlink() or (
                path.stat().st_size != item["bytes"] or sha(path) != item["sha256"]):
            raise ValueError("changed after-only generated IP")
    launch = (owner / "stdout.log").read_text()
    marker = "CHECKED_PRODUCT_ACTUAL_VENDOR_VERIFIED_CHANGED_LATENCY_NO_RAW217_NO_PHYSICAL_OR_RF_CLAIM"
    if re.findall(r"^" + marker + r"$", launch, re.MULTILINE) != [marker] or re.search(
            r"fatal_error|fatal:|error:|segmentation fault|kernel.*crash", launch, re.IGNORECASE):
        raise ValueError("missing/failed checked actual runner completion")
    return {"actual_directory": str(actual.resolve()), "inventory_sha256": ACTUAL_INVENTORY,
        "settings": SETTINGS, "source_sha256": {n: sha(frozen / n) for n in SOURCE_NAMES
            if n not in ("fft_bank_owned_resource_probe.xdc", "fft_bank_owned_synth_threads.tcl")},
        "qualified_observer": result, "generated_IP_after_only": ip,
        "owner_receipts_sha256": {n: sha(owner / n) for n in ("owner.py", "outcome.json",
            "input-pins.json", "after-sources.json", "execution.json", "result-check.json", "stdout.log")}}
'''


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def changes(source):
    old_admission = source[source.index("def verify_actual(actual):"):source.index("\ndef bindings(actual):")]
    addition = "".join(f'        "{name}",\n' for name in NEW_RTL)
    source_list = " ".join("starlink_pss_" + name for name in NEW_RTL)
    return [
        ('ACTUAL_INVENTORY = "7adf2efa0a242b89ccfbb387b00210e76841ba544cbae4cef97efc861acf59b2"',
         f'ACTUAL_INVENTORY = "{ACTUAL_INVENTORY}"'),
        ('    "PRODUCER_LOCAL_FINAL_FENCE": 1,\n', '    "PRODUCER_LOCAL_FINAL_FENCE": 1,\n    "CHECKED_PRODUCT_BANK": 1,\n'),
        ('        "fft_bank_owned_product_fence",\n', addition + '        "fft_bank_owned_product_fence",\n'),
        (' || $producer_final != 1}}', ' || $producer_final != 1 || $checked_product != 1}}'),
        (' PRODUCER_LOCAL_FINAL_FENCE $producer_final] {', ' PRODUCER_LOCAL_FINAL_FENCE $producer_final CHECKED_PRODUCT_BANK $checked_product] {'),
        ('PRIVATE_BLOCK_METADATA_READ_AHEAD PRODUCER_LOCAL_FINAL_FENCE} {',
         'PRIVATE_BLOCK_METADATA_READ_AHEAD PRODUCER_LOCAL_FINAL_FENCE CHECKED_PRODUCT_BANK} {'),
        (' PRODUCER_LOCAL_FINAL_FENCE=$producer_final] [get_filesets sources_1]',
         ' PRODUCER_LOCAL_FINAL_FENCE=$producer_final CHECKED_PRODUCT_BANK=$checked_product] [get_filesets sources_1]'),
        ('; producer_local_final_fence=$producer_final', '; producer_local_final_fence=$producer_final; checked_product_bank=$checked_product'),
        ('    return original\n\n\ndef verify_actual(actual):',
         '    original = once(original, "set_property top starlink_pss_fft_bank_owned_product_fence",\n'
         '        "set_property top starlink_pss_fft_bank_owned_checked_product")\n'
         '    original = once(original, "set rtl_names {", "set rtl_names {' + source_list + ' ")\n'
         '    return original\n\n\ndef verify_actual(actual):'),
        (old_admission, ADMISSION + '\n'),
        ('        f"set producer_final {options[\'PRODUCER_LOCAL_FINAL_FENCE\']}\\n"\n',
         '        f"set producer_final {options[\'PRODUCER_LOCAL_FINAL_FENCE\']}\\n"\n        f"set checked_product {options[\'CHECKED_PRODUCT_BANK\']}\\n"\n'),
        ('        "rtl_count": 8,\n', '        "rtl_count": 14,\n        "checked_product": 1,\n'),
        ('OFFLINE_ONLY_exact111C1K1M1P1_physical_preparation_NO_synthesis_route',
         'OFFLINE_ONLY_checked_product14_physical_preparation_NO_synthesis_route'),
    ]


def adapt(source):
    if hashlib.sha256(source.encode()).hexdigest() != P1_HELPER_SHA:
        raise ValueError("requires full reviewed P1 physical helper")
    edits = changes(source)
    for old, new in edits:
        if source.count(old) != 1:
            raise ValueError("nonunique checked physical anchor: " + old[:80])
        source = source.replace(old, new, 1)
    return source, edits


def restore(source, edits):
    for old, new in reversed(edits):
        if source.count(new) != 1:
            raise ValueError("nonunique checked physical inverse")
        source = source.replace(new, old, 1)
    if hashlib.sha256(source.encode()).hexdigest() != P1_HELPER_SHA:
        raise ValueError("whole P1 physical helper inverse differs")
    return source


def build(acq):
    p1_path = acq / "prepare_product_final_fence_physical.py"
    if sha(p1_path) != P1_GENERATOR_SHA:
        raise ValueError("reviewed P1 generator changed")
    p1 = runpy.run_path(str(p1_path))
    rom_path = acq / "prepare_rom_read_ahead_physical.py"
    if sha(rom_path) != p1["ROM_GENERATOR_SHA"]:
        raise ValueError("reviewed ROM generator changed")
    rom = runpy.run_path(str(rom_path))
    c1_path = acq / "prepare_fault_cdc_physical.py"
    if sha(c1_path) != rom["C1_GENERATOR_SHA"]:
        raise ValueError("reviewed C1 generator changed")
    c1 = runpy.run_path(str(c1_path))
    base = (acq / "prepare_exact_control_physical.py").read_text()
    original = p1["adapt"](rom["adapt"](c1["adapt"](base)))
    body, edits = adapt(original)
    if c1["restore"](rom["restore"](p1["restore"](restore(body, edits)))) != base:
        raise ValueError("complete physical helper inverse differs")
    return body, edits, rom["OWNER_SHA"]


def prepare(actual, output):
    acq = Path(__file__).resolve().parent
    tools = output.with_name(output.name + "-tools")
    for anchor in (actual, output, tools):
        if any(p.is_symlink() for p in (anchor, *anchor.parents)):
            raise ValueError("aliased checked physical path")
    if output.exists() or tools.exists():
        raise FileExistsError("refusing checked physical overwrite")
    body, edits, owner_sha = build(acq)
    base = runpy.run_path(str(acq / "prepare_exact_control_physical.py"))
    for name, digest in {**base["FIXED"], "run_exact_control_synthesis.py": owner_sha}.items():
        if sha(acq / name) != digest:
            raise ValueError("unchanged physical dependency differs: " + name)
    tools.mkdir()
    for name in (*base["FIXED"], "run_exact_control_synthesis.py"):
        shutil.copyfile(acq / name, tools / name)
    helper = tools / "prepare_exact_control_physical.py"
    helper.write_text(body)
    (tools / "checked-physical-inverse.json").write_text(json.dumps(edits, indent=2))
    env = {k: v for k, v in os.environ.items()
        if k not in ("PYTHONHOME", "PYTHONPATH", "LD_LIBRARY_PATH", "PYTHONOPTIMIZE")}
    result = subprocess.run([PYTHON, "-B", str(helper), "--actual", str(actual), "--output", str(output)],
        env=env, capture_output=True, text=True, check=False)
    (tools / "prepare-stdout.log").write_text(result.stdout)
    (tools / "prepare-stderr.log").write_text(result.stderr)
    if result.returncode:
        raise ValueError("checked actual not admitted; original outcome retained: " + result.stderr)
    return json.loads(result.stdout)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--actual", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(prepare(args.actual, args.output), sort_keys=True))
