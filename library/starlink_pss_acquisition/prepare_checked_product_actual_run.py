"""Source-specific vendor-run admission derived from the reviewed offline gate.

Preparation only: this module never invokes Vivado. An independently reviewed
one-shot owner must authorize/execute the resulting Tcl separately.
"""
import argparse
import hashlib
import json
import shutil
from pathlib import Path

OFFLINE_INVENTORY = "fc59a9d828598570440205ed07d5367a2a3f117731a05fc13267b839e3bed860"
OFFLINE_HELPER = "9d06f33d810eb69e9a9112c06756cadf3906c91935b80f53c98477c0904601e3"
ORIGINAL_RUNNER = "2d3b5008f0d087614000ae518421cd9d800aadeb98a747f47fce01d8e76cc6e3"
SELF = "prepare_checked_product_actual_run.py"
RESULT = "checked_product_actual_result.py"
RESULT_SHA = "a04c648779af03ba0d156215fa274e5b2d4b92af7028fc38b95e66a35e452084"
RUNNER = "frozen_sources/simulate_exact_control_prepared.tcl"
SETTINGS = {"REGISTERED_SCHEDULING": 1, "DISTRIBUTED_FAST_FAULT": 1,
    "PRIVATE_NEXT_START_SCRATCH": 1, "EXACT_EXTRA_EPOCHS": 1, "FAST_MHZ": 175,
    "QUICK_MUTATION": 0, "PER_CAUSE_FAULT_CDC": 1, "PRIVATE_ROM_READ_AHEAD": 1,
    "PRIVATE_BLOCK_METADATA_READ_AHEAD": 1, "PRODUCER_LOCAL_FINAL_FENCE": 1,
    "CHECKED_PRODUCT_BANK": 1}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def no_links(path):
    if any(p.is_symlink() for p in (path, *path.parents)):
        raise ValueError("aliased checked actual run path")


def once(body, old, new):
    if body.count(old) != 1:
        raise ValueError("changed checked actual runner anchor")
    return body.replace(old, new, 1)


def runner(original):
    if sha(original.encode()) != ORIGINAL_RUNNER:
        raise ValueError("not frozen original P1 runner")
    changes = [
        ("[llength $exact_generics] != 10", "[llength $exact_generics] != 11"),
        ("PRODUCER_LOCAL_FINAL_FENCE} {", "PRODUCER_LOCAL_FINAL_FENCE CHECKED_PRODUCT_BANK} {"),
        ("[file join $source_dir prepare_product_final_fence_actual.py] --verify-prepared",
         "[file join $output_dir prepare_checked_product_actual_run.py] --verify-prepared"),
        ("set project_name exact_control_actual\n",
         'if {[lsearch -exact $exact_generics CHECKED_PRODUCT_BANK=1] < 0} {error "requires reviewed checked-product option"}\nset project_name exact_control_actual\n'),
    ]
    start = original.index("puts [exact_verify_receipts $log $registered")
    end = original.index("cd $output_dir\nexec sha256sum -c SHA256SUMS", start)
    changes.append((original[start:end],
        ("# Changed-latency candidate: no old paired raw217/CSV pass is asserted.\n"
        "puts [exec env -u PYTHONHOME -u PYTHONPATH -u LD_LIBRARY_PATH "
        "/home/mouse9911/gits/pluto-plus-utils/.venv/bin/python -B "
        "[file join $output_dir prepare_checked_product_actual_run.py] --verify-result $output_dir]\n")))
    changes.append(('puts "EXACT_CONTROL_ACTUAL_FROZEN_PAIR_VERIFIED_NO_PHYSICAL_OR_RF_CLAIM"',
                    'puts "CHECKED_PRODUCT_ACTUAL_VENDOR_VERIFIED_CHANGED_LATENCY_NO_RAW217_NO_PHYSICAL_OR_RF_CLAIM"'))
    body = original
    for old, new in changes:
        body = once(body, old, new)
    restored = body
    for old, new in reversed(changes):
        restored = once(restored, new, old)
    if restored != original:
        raise ValueError("whole original runner inverse changed")
    return body, changes


def settings_text():
    return "set exact_generics {" + " ".join(f"{k}={v}" for k, v in SETTINGS.items()) + "}\n"


def read_offline(path):
    no_links(path)
    manifest = path / "SHA256SUMS"
    no_links(manifest)
    if sha(manifest.read_bytes()) != OFFLINE_INVENTORY:
        raise ValueError("requires exact reviewed77-file offline freeze")
    result = {}
    for line in manifest.read_text().splitlines():
        expected, name = line.split("  ", 1)
        if name in result or Path(name).is_absolute() or ".." in Path(name).parts:
            raise ValueError("unsafe offline inventory")
        target = path / name
        no_links(target)
        body = target.read_bytes()
        if sha(body) != expected:
            raise ValueError("offline source changed: " + name)
        result[name] = body
    if len(result) != 77 or sha(result["prepare_checked_product_actual.py"]) != OFFLINE_HELPER:
        raise ValueError("incomplete frozen preparation dependency")
    return result


def verify_prepared(path):
    no_links(path)
    inventory = (path / "checked-offline-SHA256SUMS").read_bytes()
    if sha(inventory) != OFFLINE_INVENTORY:
        raise ValueError("changed reviewed source provenance")
    old_runner = (path / "checked-original-runner.tcl").read_text()
    new_runner, edits = runner(old_runner)
    if (path / RUNNER).read_text() != new_runner:
        raise ValueError("runner full inverse mismatch")
    if json.loads((path / "checked-runner-inverse.json").read_text()) != [list(x) for x in edits]:
        raise ValueError("runner inverse receipt mismatch")
    if (path / "settings.tcl").read_text() != settings_text():
        raise ValueError("missing/duplicate/zero/wrong explicit checked setting")
    rows = set()
    for line in inventory.decode().splitlines():
        expected, name = line.split("  ", 1)
        target = path / name
        no_links(target)
        if name == RUNNER:
            body = old_runner.encode()
        elif name == "settings.tcl":
            body = (path / "checked-original-settings.tcl").read_bytes()
        else:
            body = target.read_bytes()
        if sha(body) != expected:
            raise ValueError("inherited reviewed file changed: " + name)
        rows.add(name)
    if len(rows) != 77:
        raise ValueError("incomplete offline inheritance")
    for name in (SELF, RESULT):
        no_links(path / name)
        if (path / name).read_bytes() != Path(__file__).with_name(name).read_bytes():
            raise ValueError("unreviewed run/result helper")
    if sha((path / RESULT).read_bytes()) != RESULT_SHA:
        raise ValueError("changed source-specific result policy")
    metadata = json.loads((path / "checked-run-preparation.json").read_text())
    if metadata["settings"] != SETTINGS or any(type(x) is not int for x in metadata["settings"].values()) or metadata["scope"] != "source_specific_actual_vendor_candidate_changed_latency":
        raise ValueError("run scope changed")
    expected_files = rows | {SELF, RESULT, "checked-original-runner.tcl", "checked-original-settings.tcl",
        "checked-runner-inverse.json", "checked-run-preparation.json", "checked-offline-SHA256SUMS", "SHA256SUMS"}
    no_links(path / "project")
    files = {str(p.relative_to(path)) for p in path.rglob("*") if p.is_file() and p.relative_to(path).parts[0] != "project"}
    if files != expected_files:
        raise ValueError("unexpected/missing prepared run member")
    return dict(SETTINGS)


def prepare(offline, output):
    no_links(output)
    if output.exists():
        raise FileExistsError("refusing overwrite/retry of checked actual preparation")
    members = read_offline(offline)
    body, edits = runner(members[RUNNER].decode())
    for name in (SELF, RESULT):
        no_links(Path(__file__).with_name(name))
        if not Path(__file__).with_name(name).is_file():
            raise ValueError("missing source-specific result helper")
    output.mkdir(parents=True)
    for name, content in members.items():
        target = output / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(content)
    (output / RUNNER).write_text(body)
    (output / "checked-original-runner.tcl").write_bytes(members[RUNNER])
    (output / "checked-original-settings.tcl").write_bytes(members["settings.tcl"])
    (output / "settings.tcl").write_text(settings_text())
    (output / "checked-runner-inverse.json").write_text(json.dumps(edits, indent=2))
    shutil.copyfile(offline / "SHA256SUMS", output / "checked-offline-SHA256SUMS")
    for name in (SELF, RESULT):
        shutil.copyfile(Path(__file__).with_name(name), output / name)
    (output / "checked-run-preparation.json").write_text(json.dumps({
        "scope": "source_specific_actual_vendor_candidate_changed_latency", "settings": SETTINGS,
        "offline_origin": str(offline), "offline_inventory": OFFLINE_INVENTORY,
        "absolute_service_cap": 5215, "raw217_claim": False}, indent=2))
    (output / "SHA256SUMS").write_text("".join(f"{sha(p.read_bytes())}  {p.relative_to(output)}\n"
        for p in sorted(output.rglob("*")) if p.is_file()))
    return verify_prepared(output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--offline", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--verify-prepared", type=Path)
    parser.add_argument("--verify-result", type=Path)
    args = parser.parse_args()
    if args.verify_prepared:
        result = verify_prepared(args.verify_prepared)
    elif args.verify_result:
        import runpy
        verify_prepared(args.verify_result)
        result = runpy.run_path(str(Path(__file__).with_name(RESULT)))["verify_result"](args.verify_result)
    elif args.offline and args.output:
        result = prepare(args.offline, args.output)
    else:
        parser.error("requires offline/output or verify-prepared/result")
    print(json.dumps(result, sort_keys=True))
