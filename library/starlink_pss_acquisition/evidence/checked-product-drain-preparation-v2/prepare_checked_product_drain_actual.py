"""Offline v2 actual preparation: only the reviewed live-drain bench overlay.

No vendor invocation. The original84 files restore byte-for-byte; unchanged
result policy executes first, followed by separate drain-marker/CSV validation.
"""
import argparse
import csv
import hashlib
import json
import re
import runpy
import shutil
from pathlib import Path

ORIGINAL_INVENTORY = "9b21ff51490f0deb87ae0b69a78e65e37895bb8006f67b2615a567e70e8e63c7"
ORIGINAL_RUNNER = "934766358dc477bc288fa5e97519b01394708f1b8832c61e76f19d927003acda"
RESULT_SHA = "a04c648779af03ba0d156215fa274e5b2d4b92af7028fc38b95e66a35e452084"
TRANSFORM_SHA = "f64d6e96f1d2fa3f8d0af856c495ae9e6f88182893e949ec0d14a99006797d79"
SCHEDULER_TEST_SHA = "40c7ef6df39a06f5ee32fe5734d5b1d01ef6fda7d78507edfbd36a0213dcaee0"
SELF = "prepare_checked_product_drain_actual.py"
TRANSFORM = "prepare_checked_product_drain_witness.py"
TEST = "test_checked_product_drain_witness.py"
TOP = "frozen_sources/tb_starlink_pss_fft_bank_owned_slice.sv"
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
        raise ValueError("aliased drain actual path")


def rows(inventory):
    result = {}
    if sha(inventory) != ORIGINAL_INVENTORY:
        raise ValueError("requires original84 inventory")
    for line in inventory.decode().splitlines():
        digest, name = line.split("  ", 1)
        if name in result or Path(name).is_absolute() or ".." in Path(name).parts:
            raise ValueError("unsafe original inventory")
        result[name] = digest
    if len(result) != 84:
        raise ValueError("incomplete original84 inventory")
    return result


def runner(body, inverse=False):
    old = "[file join $output_dir prepare_checked_product_actual_run.py]"
    new = "[file join $output_dir prepare_checked_product_drain_actual.py]"
    if not inverse and sha(body.encode()) != ORIGINAL_RUNNER:
        raise ValueError("requires unchanged original v1 runner")
    before, after = (new, old) if inverse else (old, new)
    if body.count(before) != 2:
        raise ValueError("changed runner CLI binding")
    body = body.replace(before, after)
    if inverse and sha(body.encode()) != ORIGINAL_RUNNER:
        raise ValueError("whole original runner inverse differs")
    return body


def verify_prepared(path):
    no_links(path)
    members = rows((path / "drain-original-SHA256SUMS").read_bytes())
    for name, expected in ((TRANSFORM, TRANSFORM_SHA), (TEST, SCHEDULER_TEST_SHA)):
        no_links(path / name)
        if sha((path / name).read_bytes()) != expected:
            raise ValueError("reviewed drain policy changed: " + name)
    transform = runpy.run_path(str(path / TRANSFORM))["transform"]
    for name, digest in members.items():
        target = path / name
        no_links(target)
        body = target.read_bytes()
        if name == TOP:
            body = transform(body.decode(), True).encode()
        elif name == RUNNER:
            body = runner(body.decode(), True).encode()
        if sha(body) != digest:
            raise ValueError("original84 whole-source inverse changed: " + name)
    if sha((path / "checked_product_actual_result.py").read_bytes()) != RESULT_SHA:
        raise ValueError("original32/6/5215 result policy changed")
    if (path / "settings.tcl").read_text() != "set exact_generics {" + " ".join(
            f"{k}={v}" for k, v in SETTINGS.items()) + "}\n":
        raise ValueError("drain actual settings differ")
    metadata = json.loads((path / "drain-preparation.json").read_text())
    if metadata != {"scope": "checked_product_v2_live_drain_bench_only_NO_vendor_or_physical_claim",
            "original_inventory": ORIGINAL_INVENTORY, "result_sha256": RESULT_SHA,
            "transform_sha256": TRANSFORM_SHA, "scheduler_test_sha256": SCHEDULER_TEST_SHA,
            "settings": SETTINGS, "absolute_service_cap": 5215}:
        raise ValueError("drain preparation scope changed")
    expected = set(members) | {SELF, TRANSFORM, TEST, "drain-original-SHA256SUMS", "drain-preparation.json", "SHA256SUMS"}
    no_links(path / SELF)
    if (path / SELF).read_bytes() != Path(__file__).read_bytes():
        raise ValueError("unreviewed drain admission helper")
    no_links(path / "project")
    actual = {str(p.relative_to(path)) for p in path.rglob("*")
        if p.is_file() and p.relative_to(path).parts[0] != "project"}
    if actual != expected:
        raise ValueError("missing/extra drain preparation member")
    return dict(SETTINGS)


def verify_drain_receipts(simulation, result):
    text = (simulation / "simulate.log").read_text()
    prefix = "CHECKED_PROFILE_DRAIN_WITNESS"
    lines = [line for line in text.splitlines() if line.startswith(prefix)]
    pattern = prefix + r" profile=([01]) count=(32|6) forward=([0-9]+) drain=([0-9]+) service=([0-9]+)"
    parsed = [re.fullmatch(pattern, line) for line in lines]
    if len(parsed) != 2 or any(m is None for m in parsed):
        raise ValueError("missing/duplicate/malformed final drain receipts")
    markers = [tuple(map(int, m.groups())) for m in parsed]
    if [(x[0], x[1]) for x in markers] != [(0, 32), (1, 6)]:
        raise ValueError("wrong final drain profile/count/order")
    wanted = {marker[3] for marker in markers}
    matching, final_admit = {}, {}
    with (simulation / "fft_bank_owned_trace.csv").open() as stream:
        next(stream)
        for row in csv.reader(stream):
            cycle, epoch = int(row[0]), int(row[1])
            if epoch in (1, 2) and row[6] == "1" and row[8] == "0":
                final_admit[epoch] = cycle
            if cycle in wanted:
                matching[cycle] = row
    for profile, count, forward, drain, service in markers:
        row = matching.get(drain)
        services = result["service_cycles"].get(profile + 1)
        if services is None:
            services = result["service_cycles"].get(str(profile + 1))
        if (row is None or row[1:3] != [str(profile + 1), str(profile)] or
                any(row[index] != value for index, value in
                    ((3, "1"), (4, "2"), (8, "0"), (16, "0"), (21, "1"), (22, "0"))) or
                final_admit.get(profile + 1) != forward or service != drain-forward or
                not 0 < service <= 5215 or len(services or []) != count or services[-1] != service):
            raise ValueError("final drain receipt disagrees with live CSV/service")
    return {"scope": "two_final_live_preedge_drains_after_unchanged_full_result_gate", "markers": markers}


def verify_result(path):
    verify_prepared(path)
    result = runpy.run_path(str(path / "checked_product_actual_result.py"))["verify_result"](path)
    simulation = path / "project/exact_control_actual.sim/sim_1/behav/xsim"
    result["final_drain_witnesses"] = verify_drain_receipts(simulation, result)
    return result


def prepare(original, output):
    no_links(original)
    no_links(output)
    if output.exists():
        raise FileExistsError("refusing drain actual overwrite/retry")
    inventory = (original / "SHA256SUMS").read_bytes()
    members = rows(inventory)
    contents = {}
    for name, expected in members.items():
        no_links(original / name)
        contents[name] = (original / name).read_bytes()
        if sha(contents[name]) != expected:
            raise ValueError("original failure freeze changed: " + name)
    acq = Path(__file__).resolve().parent
    test = acq.parents[2] / "tests/starlink_oracle" / TEST
    for path, expected in ((acq / TRANSFORM, TRANSFORM_SHA), (test, SCHEDULER_TEST_SHA)):
        no_links(path)
        if sha(path.read_bytes()) != expected:
            raise ValueError("reviewed drain dependency changed")
    transform = runpy.run_path(str(acq / TRANSFORM))["transform"]
    contents[TOP] = transform(contents[TOP].decode()).encode()
    contents[RUNNER] = runner(contents[RUNNER].decode()).encode()
    output.mkdir(parents=True)
    for name, body in contents.items():
        target = output / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(body)
    for path in (Path(__file__), acq / TRANSFORM, test):
        shutil.copyfile(path, output / path.name)
    (output / "drain-original-SHA256SUMS").write_bytes(inventory)
    (output / "drain-preparation.json").write_text(json.dumps({
        "scope": "checked_product_v2_live_drain_bench_only_NO_vendor_or_physical_claim",
        "original_inventory": ORIGINAL_INVENTORY, "result_sha256": RESULT_SHA,
        "transform_sha256": TRANSFORM_SHA, "scheduler_test_sha256": SCHEDULER_TEST_SHA,
        "settings": SETTINGS, "absolute_service_cap": 5215}, indent=2))
    (output / "SHA256SUMS").write_text("".join(f"{sha(p.read_bytes())}  {p.relative_to(output)}\n"
        for p in sorted(output.rglob("*")) if p.is_file()))
    return verify_prepared(output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--original", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--verify-prepared", type=Path)
    parser.add_argument("--verify-result", type=Path)
    args = parser.parse_args()
    if args.verify_prepared:
        answer = verify_prepared(args.verify_prepared)
    elif args.verify_result:
        answer = verify_result(args.verify_result)
    elif args.original and args.output:
        answer = prepare(args.original, args.output)
    else:
        parser.error("choose original/output or verify-prepared/result")
    print(json.dumps(answer, sort_keys=True))
