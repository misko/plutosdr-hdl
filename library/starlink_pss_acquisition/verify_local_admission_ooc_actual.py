"""Read-only admission of exact successful6473 sources and saved-WDB evidence."""
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path

MANIFEST = "1717107b5be08b9ff72e7a224cbf20a1354ddd215270a7cd1923b62e12b5d858"
RESULTS = "4938eb536dce3adfd62cd185e2868727a9843fd4ed896d0b02b1638f19bbe292"
WDB = "52f4ccf572df859e21cdb6e92a82c3b22459b551874acf241f0ea8acd7539a31"
HELPER = "eb1dc68389c12f6d0832a421b0312d32a3f528807ea21292b113b555b585654b"
SIM = Path("project/fft_bank_arithmetic_actual.sim/sim_1/behav/xsim")
ROOT = "/\\tb_starlink_pss_local_admission_actual(FAST_MHZ=175,B=1,O=1,L=1) "
OLD_ROOT = "/\\tb_starlink_pss_bank_arithmetic_actual(FAST_MHZ=175,B=1,O=1) "
PYTHON = "/home/mouse9911/gits/pluto-plus-utils/.venv/bin/python"
TIMES = (0, 1, 999, 1000, 1001, 2857142, 2857143, 2858142, 2858143, 2858144,
         100000000000, 1261765777375, 3000000000000, 3371803025732,
         3371803025733, 3371803026732, 3371803026733)
HISTORICAL_TIMES = (100000000000, 1261765777375, 3000000000000)
EVIDENCE = {
    "actual_before.json": "fd1a9414d02b1a41e6c6b0aa2457efcc89231c31c32653631b50a34a24176fc8",
    "actual_terminal.json": "6f014a66a996f8948edd121e07cecd73505724338dcd8d2622b81ca52b5df332",
    "actual_outer.log": "3831f99e5cb1a581f9c34cd33c8e3b34ec805ba1dfee6fed84e7cef7f888a344",
    "wdb_before.json": "4181b35873b70a1af44e7cf84aa68211a2c1c405aa6011ddce01a1d87d37858e",
    "wdb_terminal.json": "d788ca7f84347ef872a0bc37b136a5be78254a6a59c7c1ae7858206cbcc86b12",
    "wdb_outer.log": "2d824c513da39c9f0b44bfe217105dc8d5d19fe50f2cb85b65b27bed27a89f31",
    "read_original6473_wdb.tcl": "05d9b02626d2849b4b18bd8c0dfd533d2a102e0fb874a9ffaaeefa9d3a60b7fb",
    "own_readonly_wdb.py": "3d59d459dcf4e75f28339722c33f85a0e16beefbe7127645983bdbf0e1247a07",
    "arithmetic_wdb_reference.log": "e2150fca7a2861fc008d3962271f71c4e64b77b662aa8ebbc640d84eb8bcaf2d",
}
RTL_HASHES = {
    "starlink_pss_fft_bank_owned_local_admission_probe.v": "0cb54617eb6757e1d6c719d97b0fd5002ec7f6105c8c4b50c41eba67d4306235",
    "starlink_pss_realtime_input_guard_local_admission.v": "55438743eede0d346cec67351e079eb6ae21da437d4088a131a2a258b43ff233",
    "starlink_pss_realtime_result_guard.v": "09ab35339d55ddf88e813830322d21574d0794c489c9749f68113e9da7807be2",
    "starlink_pss_block_mailbox.v": "e85122eb6689ff49b31aa5a0c200e2666786629055b4f45856fe79fb829dbb55",
    "starlink_pss_forward_kernel_join.v": "87e40b3cc9025502c05d2afbd6b0d9658618cd7204d4fd8ddc3f0ba74e68843a",
    "starlink_pss_kernel_rom.v": "0b4ee87d93d61c6fa12ee9992aa517a3a8be568835075531d9af4453f4ec80e5",
    "starlink_pss_spectrum_product_operand_register.v": "dead8e465b4bd982cebcab0c4a4e7eb4f3b20c038938f74c7663a79e0779893d",
    "starlink_pss_spectrum_product_bank_arithmetic.v": "515d29534dab921601c37564ad8a9957eed9befb9dff2e1c8c5f1f79fc6b5f70",
}


def sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def safe(value):
    path = Path(value)
    if not path.is_absolute():
        path = Path.cwd() / path
    require(not any(p.is_symlink() for p in (path, *path.parents)), "symlink path/parent forbidden")
    return path.resolve()


def verify_histories(text, arithmetic_paths, observer_paths, reference):
    marker = "LOCAL_WDB_HISTORY_EXTRACTED arithmetic=115 observer=14 times=17 values=2193 no_advance=1 physical_time_only=1"
    require(text.splitlines().count(marker) == 1, "missing exact history terminal")
    require(not re.search(r"^(?:ERROR|FATAL):", text, re.MULTILINE), "history loader error")
    groups = {"arithmetic": arithmetic_paths, "observer": observer_paths}
    require(len(arithmetic_paths) == len(set(arithmetic_paths)) == 115 and
            len(observer_paths) == len(set(observer_paths)) == 14, "wrong diagnostic inventory")
    require(all(path.startswith(ROOT + "/") for paths in groups.values() for path in paths), "wrong diagnostic root")
    values = {}
    for line in text.splitlines():
        if not line.startswith("LOCAL_WDB_VALUE\t"):
            continue
        fields = line.split("\t")
        require(len(fields) == 6, "malformed history row")
        _, group, time, radix, path, value = fields
        require(group in groups and time.isdecimal() and int(time) in TIMES, "wrong history group/time")
        require(path in groups[group] and radix == ("bin" if group == "observer" else "hex"), "wrong history path/radix")
        require(bool(re.fullmatch("[01xXzZ]+" if radix == "bin" else "[0-9a-fA-FxXzZ]+", value)), "unrecorded or malformed history value")
        key = (group, int(time), path)
        require(key not in values, "duplicate history value")
        values[key] = value
    expected = {(group, time, path) for group, paths in groups.items() for time in TIMES for path in paths}
    require(set(values) == expected, "incomplete recorded history closure")
    snapshots = []
    for time in TIMES:
        row = {p.rsplit("/", 1)[-1]: values["observer", time, p] for p in observer_paths}
        require(all(len(row[name]) == 155 for name in ("actual_view", "original_view", "default_view")), "guard history width differs")
        require(row["actual_view"] == row["original_view"] == row["default_view"], "recorded155-bit guard mismatch")
        pre = time // 2857143 + 1
        post = 0 if time < 1000 else (time - 1000) // 2857143 + 1
        # The original unmodified bench terminates in this last +1ps time slot.
        # Require its exact observed outstanding count, never generalize a waiver.
        if time == TIMES[-1]:
            post -= 1
        require(int(row["pre_checks"], 2) == pre and int(row["post_checks"], 2) == post,
                "startup/physical-edge/final counter history differs")
        snapshots.append({"time_fs": time, "pre_checks": pre, "post_checks": post,
                          "reset_checks": int(row["reset_checks"], 2), "views_equal": True})
    old = {}
    for line in reference.splitlines():
        if line.startswith("ACTUAL_WDB_VALUE\t"):
            _, arm, time, path, value = line.split("\t")
            require(arm == "candidate" and path.startswith(OLD_ROOT + "/"), "wrong arithmetic history reference")
            key = ("arithmetic", int(time.removesuffix("fs")), ROOT + path.removeprefix(OLD_ROOT))
            require(key not in old, "duplicate arithmetic history reference")
            old[key] = value
    require(len(old) == 345 and {key[1] for key in old} == set(HISTORICAL_TIMES), "incomplete arithmetic history reference")
    require(all(values.get(key) == value for key, value in old.items()), "historical arithmetic recorded value changed")
    return {"paths": 129, "values": 2193, "times": 17, "guard_equal_snapshots": 17,
            "historical_arithmetic_values_equal": 345, "physical_time_only": True,
            "same_timestamp_region_ordering_proven": False, "guard_snapshots": snapshots}


def verify_sources(actual):
    actual = safe(actual)
    require(sha(safe(actual / "manifest.json")) == MANIFEST, "requires exact tested6473 manifest")
    manifest = json.loads((actual / "manifest.json").read_text())
    source = safe(actual / "frozen_sources")
    entries = list(source.iterdir())
    require(len(entries) == 49 and all(p.is_file() and not p.is_symlink() for p in entries), "unsafe or incomplete actual source closure")
    hashes = {p.name: sha(p) for p in entries}
    require(hashes == manifest["source_sha256"], "actual frozen source changed")
    require({name: hashes.get(name) for name in RTL_HASHES} == RTL_HASHES and
            manifest["runtime_rtl"] == list(RTL_HASHES), "tested62da6a39 runtime binding differs")
    require(hashes["local_admission_actual.py"] == HELPER, "wrong frozen actual verifier")
    return manifest


def verify(actual, evidence):
    actual, evidence = safe(actual), safe(evidence)
    manifest = verify_sources(actual)
    entries = list(evidence.iterdir())
    require({p.name for p in entries} == set(EVIDENCE) and all(p.is_file() and not p.is_symlink() for p in entries), "admission evidence closure differs")
    for name, expected in EVIDENCE.items():
        require(sha(evidence / name) == expected, "reviewed evidence identity differs: " + name)
    before = json.loads((evidence / "actual_before.json").read_text())
    terminal = json.loads((evidence / "actual_terminal.json").read_text())
    expected_sources = {"manifest.json": MANIFEST} | {"frozen_sources/" + k: v for k, v in manifest["source_sha256"].items()}
    require(before["source_sha256"] == terminal["after_source_sha256"] == expected_sources, "actual before/after sources differ")
    require(terminal["original_process_exit"] == 0 and terminal["source_unchanged"] is True and
            terminal["launch_error"] is None and terminal["after_integrity_error"] is None, "actual automation did not pass")
    require(sha(safe(actual / "results.json")) == RESULTS, "original successful results changed or missing")
    outcome = (actual / "run_outcome.txt").read_text()
    require(re.findall(r"^run_status=(.*)$", outcome, re.MULTILINE) == ["0"] and
            re.findall(r"^after_status=(.*)$", outcome, re.MULTILINE) == ["0"], "actual run/integrity failure")
    clean = {k: v for k, v in os.environ.items() if k not in {"PYTHONHOME", "PYTHONPATH", "LD_LIBRARY_PATH"}}
    checked = subprocess.run([PYTHON, "-B", str(actual / "frozen_sources/local_admission_actual.py"),
                              "results", str(actual), "--expected", MANIFEST], cwd="/", env=clean,
                             capture_output=True, text=True, check=False, timeout=30)
    require(checked.returncode == 0, "frozen full numeric/fault/metadata/latency verifier rejected actual")
    require(checked.stdout == (actual / "results.json").read_text(), "original/fresh frozen actual results differ")
    result = json.loads(checked.stdout)
    sim = safe(actual / SIM)
    require(sha(safe(sim / "tb_starlink_pss_local_admission_actual_behav.wdb")) == WDB, "original6473 WDB changed")
    wave_before = json.loads((evidence / "wdb_before.json").read_text())
    wave_terminal = json.loads((evidence / "wdb_terminal.json").read_text())
    require(wave_before["input_sha256"] == wave_terminal["after_sha256"] and
            wave_terminal["original_process_exit"] == 0 and wave_terminal["input_unchanged"] is True and
            wave_terminal["launch_error"] is None and wave_terminal["after_error"] is None, "read-only WDB loader failed or changed source")
    history = verify_histories((evidence / "wdb_outer.log").read_text(),
                               (sim / "arithmetic_diagnostic_signals.txt").read_text().splitlines(),
                               (sim / "local_guard_diagnostic_signals.txt").read_text().splitlines(),
                               (evidence / "arithmetic_wdb_reference.log").read_text())
    return {"actual_directory": str(actual), "manifest_sha256": MANIFEST, "runtime_git": "62da6a39edb8e40e08d41cbb13ba04af7584842d",
            "R": 1, "B": 1, "O": 1, "L": 1, "frequency": 175,
            "source_sha256": manifest["source_sha256"], "original_automation_status": "PASS",
            "functional_terminals": len(result["receipts"]), "guard": result["guard"],
            "events": result["events"], "trace_sha256": result["trace_sha256"], "histories": history}
