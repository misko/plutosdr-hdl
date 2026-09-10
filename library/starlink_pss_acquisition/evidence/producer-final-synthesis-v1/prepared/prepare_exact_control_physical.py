"""Offline physical preparation from the exact passing combined actual run."""

import argparse
import hashlib
import json
import re
import runpy
import shutil
import subprocess
from pathlib import Path

ACTUAL_INVENTORY = "7adf2efa0a242b89ccfbb387b00210e76841ba544cbae4cef97efc861acf59b2"
PYTHON = "/home/mouse9911/gits/pluto-plus-utils/.venv/bin/python"
PYTHON_CHILD = f"env -u PYTHONHOME -u PYTHONPATH -u LD_LIBRARY_PATH {PYTHON} -B"
SETTINGS = {
    "REGISTERED_SCHEDULING": 1,
    "DISTRIBUTED_FAST_FAULT": 1,
    "PRIVATE_NEXT_START_SCRATCH": 1,
    "EXACT_EXTRA_EPOCHS": 1,
    "FAST_MHZ": 175,
    "QUICK_MUTATION": 0,
    "PER_CAUSE_FAULT_CDC": 1,
    "PRIVATE_ROM_READ_AHEAD": 1,
    "PRIVATE_BLOCK_METADATA_READ_AHEAD": 1,
    "PRODUCER_LOCAL_FINAL_FENCE": 1,
}
RTL = tuple(
    f"starlink_pss_{name}.v"
    for name in (
        "fft_bank_owned_product_fence",
        "realtime_input_guard",
        "realtime_result_guard",
        "block_mailbox",
        "product_fence_mailbox",
        "forward_kernel_join_read_ahead",
        "kernel_rom_read_ahead",
        "spectrum_product",
    )
)
FIXED = {
    "synthesize_fft_bank_owned_slice.tcl": "f843af0394cc680bf8344739ebe7adf7aece5d3db13e06b59b452d63372b9fe7",
    "route_completed_input_fence.tcl": "0873675fcec384f676a80b75b746460fbff2ecc3ee162f6111705ead2fad6d4a",
    "fft_bank_owned_resource_probe.xdc": "bac30eff84cc71d1f273104b716b388b55e51d33be10f9beaf1901232193ba3f",
    "fft_bank_owned_synth_threads.tcl": "aec974f2800f01285e888d1b188cd089534941922531914926a8e1b568d4c227",
    "create_shared_realtime_xfft_ip.tcl": "0795ea7e6aa981d78080ac22fa4ba6355da59d6829ceb409dda07a54f7f9420d",
}
SOURCE_NAMES = RTL + (
    "create_shared_realtime_xfft_ip.tcl",
    "upper_edge_pss_kernel_q17.mem",
    "fft_bank_owned_resource_probe.xdc",
    "fft_bank_owned_synth_threads.tcl",
)
LEGACY_ADMISSION = """set simlog [file join $evidence_dir project fft_bank_owned_slice.sim sim_1 behav xsim simulate.log]
set channel [open $simlog r]; set simulation [read $channel]; close $channel
if {[string first "FFT_BANK_OWNED_SLICE_PASS" $simulation] < 0 ||
    [regexp -nocase {fatal:|error:} $simulation]} { error "requires passing actual-core evidence" }
set prior_sources [file join $evidence_dir frozen_sources]
set channel [open [file join $evidence_dir scope.txt] r]; set sim_scope [read $channel]; close $channel
set registered [expr {[string first "registered_scheduling=1" $sim_scope] >= 0}]
if {$registered && [string first "REGISTERED_SCHEDULING_PASS" $simulation] < 0} {
  error "registered scheduling boundary tests did not pass"
}
"""
ADMISSION = f"""# Prepared-inventory identity is supplied separately by the reviewed caller.
set expected_prepared [lindex $argv 2]
set prepared_inventory [file join $evidence_dir SHA256SUMS]
if {{![regexp {{^[0-9a-f]{{64}}$}} $expected_prepared] ||
    [lindex [exec sha256sum $prepared_inventory] 0] ne $expected_prepared}} {{
  error "unexpected exact-control physical preparation"
}}
set audit_helper [file join $evidence_dir prepare_exact_control_physical.py]
set old_directory [pwd]; cd $evidence_dir
exec sha256sum -c SHA256SUMS --quiet
cd $old_directory
puts [exec {PYTHON_CHILD} $audit_helper --verify $evidence_dir --expected $expected_prepared]
source [file join $evidence_dir exact_physical_settings.tcl]
if {{$registered != 1 || $distributed != 1 || $scratch != 1 || $per_cause != 1 || $rom_word != 1 || $rom_metadata != 1 || $producer_final != 1}} {{ error "wrong combined physical options" }}
set prior_sources [file join $evidence_dir frozen_sources]
"""
COPY_VERIFY = f"puts [exec {PYTHON_CHILD} $audit_helper --verify $evidence_dir --expected $expected_prepared --copied $source_dir]\n"
GENERIC_CHECK = """set physical_generics [get_property GENERIC [get_filesets sources_1]]
foreach {name value} [list REGISTERED_SCHEDULING $registered DISTRIBUTED_FAST_FAULT $distributed PRIVATE_NEXT_START_SCRATCH $scratch PER_CAUSE_FAULT_CDC $per_cause PRIVATE_ROM_READ_AHEAD $rom_word PRIVATE_BLOCK_METADATA_READ_AHEAD $rom_metadata PRODUCER_LOCAL_FINAL_FENCE $producer_final] {
  if {[lsearch -exact $physical_generics ${name}=$value] < 0} { error "missing physical parameter $name" }
}
if {[lsearch -all -inline -glob $physical_generics PER_CAUSE_FAULT_CDC=*] ne [list PER_CAUSE_FAULT_CDC=1]} {
  error "requires exactly one explicit C1 physical parameter"
}
foreach name {PRIVATE_ROM_READ_AHEAD PRIVATE_BLOCK_METADATA_READ_AHEAD PRODUCER_LOCAL_FINAL_FENCE} {
  if {[lsearch -all -inline -glob $physical_generics ${name}=*] ne [list ${name}=1]} {
    error "requires exactly one explicit ROM physical parameter $name"
  }
}
"""


def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def once(text, old, new):
    if text.count(old) != 1:
        raise ValueError("nonunique synthesis adapter anchor")
    return text.replace(old, new, 1)


def adapt_synthesis(original):
    changes = (
        (
            'if {$argc != 2} { error "expected NEW_OUTPUT PASSED_SIMULATION_DIRECTORY" }',
            'if {$argc != 3} { error "expected NEW_OUTPUT PREPARED EXPECTED_PREPARED_SHA256" }',
        ),
        (
            "set script_dir [file dirname [file normalize [info script]]]",
            "set script_dir [file join [file dirname [file normalize [info script]]] frozen_sources]",
        ),
        (LEGACY_ADMISSION, ADMISSION),
        (
            'puts $channel "source_simulation=$evidence_dir"\n',
            (
                'puts $channel "source_preparation=$evidence_dir"\n'
                'puts $channel "expected_preparation_sha256=$expected_prepared"\n'
                'puts $channel "source_simulation_log=$simlog"\n'
            ),
        ),
        (
            "  REGISTERED_SCHEDULING=$registered] [get_filesets sources_1]\n",
            "  REGISTERED_SCHEDULING=$registered DISTRIBUTED_FAST_FAULT=$distributed \\\n  PRIVATE_NEXT_START_SCRATCH=$scratch PER_CAUSE_FAULT_CDC=$per_cause PRIVATE_ROM_READ_AHEAD=$rom_word PRIVATE_BLOCK_METADATA_READ_AHEAD=$rom_metadata PRODUCER_LOCAL_FINAL_FENCE=$producer_final] [get_filesets sources_1]\n"
            + GENERIC_CHECK,
        ),
        (
            'puts $channel "registered_scheduling=$registered"\n',
            (
                'puts $channel "registered_scheduling=$registered"\n'
                'puts $channel "distributed_fast_fault=$distributed; private_next_start_scratch=$scratch; per_cause_fault_cdc=$per_cause; private_rom_read_ahead=$rom_word; private_block_metadata_read_ahead=$rom_metadata; producer_local_final_fence=$producer_final"\n'
                'puts $channel "effective_top_generics=$physical_generics"\n'
            ),
        ),
        (
            "launch_runs $ip_run -jobs 2\n",
            COPY_VERIFY + "launch_runs $ip_run -jobs 2\n",
        ),
        ("close_project\n", COPY_VERIFY + "close_project\n"),
    )
    for old, new in changes:
        original = once(original, old, new)
    for old, new in (
        ("starlink_pss_fft_bank_owned_slice", "starlink_pss_fft_bank_owned_product_fence"),
        ("starlink_pss_forward_kernel_join", "starlink_pss_forward_kernel_join_read_ahead"),
        ("starlink_pss_kernel_rom", "starlink_pss_kernel_rom_read_ahead"),
    ):
        original = original.replace(old, new)
    original = once(original,
        "starlink_pss_realtime_result_guard starlink_pss_block_mailbox\n",
        "starlink_pss_realtime_result_guard starlink_pss_block_mailbox starlink_pss_product_fence_mailbox\n")
    return original


def verify_actual(actual):
    if sha(actual / "SHA256SUMS") != ACTUAL_INVENTORY:
        raise ValueError("requires exact passing combined actual inventory")
    subprocess.run(
        ["sha256sum", "-c", "SHA256SUMS", "--quiet"], cwd=actual, check=True, timeout=10
    )
    metadata = json.loads((actual / "fence-preparation.json").read_text())
    if metadata["settings"] != SETTINGS:
        raise ValueError("requires R1/D1/S1/extras1/175/QUICK0")
    expected_settings = (
        "set exact_generics {"
        + " ".join(f"{k}={v}" for k, v in SETTINGS.items())
        + "}\n"
    )
    if (actual / "settings.tcl").read_text() != expected_settings:
        raise ValueError("actual explicit settings differ")
    expected_snapshot = "".join(
        line.split("  ", 1)[1] + ": OK\n"
        for line in (actual / "SHA256SUMS").read_text().splitlines()
    )
    for name in (
        "before-integrity.log",
        "after-integrity.log",
    ):
        if (actual.parent / "product-final-actual-owner-v1" / name).read_text() != expected_snapshot:
            raise ValueError("incomplete actual before/after source verification")
    time = (actual.parent / "product-final-actual-owner-v1/time.txt").read_text()
    if re.findall(r"^\s*Exit status: (\d+)$", time, re.MULTILINE) != ["0"]:
        raise ValueError("actual original process did not exit zero")
    launch = (actual.parent / "product-final-actual-owner-v1/launch.log").read_text()
    if re.findall(
        r"^EXACT_CONTROL_ACTUAL_FROZEN_PAIR_VERIFIED_NO_PHYSICAL_OR_RF_CLAIM$",
        launch,
        re.MULTILINE,
    ) != ["EXACT_CONTROL_ACTUAL_FROZEN_PAIR_VERIFIED_NO_PHYSICAL_OR_RF_CLAIM"]:
        raise ValueError("actual runner did not complete frozen gates")
    simulation = actual / "project/exact_control_actual.sim/sim_1/behav/xsim"
    logfile = simulation / "simulate.log"
    log = logfile.read_text()
    if re.search(r"fatal:|error:", log, re.IGNORECASE) or "$finish called" not in log:
        raise ValueError("failed or incomplete actual simulation")
    for marker in (
        "FFT_BANK_OWNED_SLICE_PASS",
        "HELD_PHASE_INPUT_PASS",
        "HELD_PREFLIGHT_ACTUAL_PASS",
        "BALANCED_IDENTITY_ACTUAL_PASS",
        "PAYLOAD_BUBBLES_ACTUAL_PASS",
        "FORWARD_RETIREMENT_ACTUAL_PASS",
        "EXACT_CONTROL_ACTUAL_PASS",
        "REGISTERED_SCHEDULING_PASS",
        "PREFLIGHT_REASON_SPLIT_PASS",
    ):
        if marker not in log:
            raise ValueError("missing original actual marker: " + marker)
    frozen = actual / "frozen_sources"
    owner = actual.parent / "product-final-actual-owner-v1"
    for anchor in (actual, frozen, owner):
        if any(p.is_symlink() for p in (anchor, *anchor.parents)):
            raise ValueError("aliased ROM actual evidence")
    for name in ("process-exit.txt", "after-integrity-exit.txt", "after-ip-exit.txt", "receipt-exit.txt"):
        if (owner / name).read_text() != "0\n":
            raise ValueError("ROM actual persisted status is not zero: " + name)
    if sha(owner / "owner.sh") != "62e4fa75b645f200b9c6bbccc0a43cf6e7cda0c2f58d04245128f5da9b24cb68":
        raise ValueError("ROM actual owner differs from reviewed path-only source")
    expected_hashes = (ACTUAL_INVENTORY + "  SHA256SUMS\n" +
        "2d3b5008f0d087614000ae518421cd9d800aadeb98a747f47fce01d8e76cc6e3  frozen_sources/simulate_exact_control_prepared.tcl\n")
    if any((owner / name).read_text() != expected_hashes for name in ("before.sha256", "after.sha256")):
        raise ValueError("ROM actual stored pre/post inventory or runner differs")
    rom = runpy.run_path(str(frozen / "prepare_product_final_fence_actual.py"))
    if rom["verify_prepared"](actual) != SETTINGS:
        raise ValueError("ROM actual full inherited source/binding differs")
    rom_qualified = rom["verify_result"](logfile, 1, frozen)
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
    runner = (frozen / "simulate_exact_control_prepared.tcl").read_text()
    procedures = runner.split("# BEGIN EXACT_CONTROL_RECEIPTS\n")[1].split(
        "# END EXACT_CONTROL_RECEIPTS"
    )[0]
    program = (
        procedures
        + "\nset f [open [lindex $argv 0] r]; set log [read $f]; close $f\nputs [exact_verify_receipts $log 1 1 1 1]\n"
    )
    checked = subprocess.run(
        ["tclsh", "/dev/stdin", str(logfile)],
        input=program,
        capture_output=True,
        text=True,
        timeout=15,
        check=False,
    )
    if (
        checked.returncode
        or checked.stdout.strip() != "EXACT_CONTROL_RECEIPTS_VERIFIED"
    ):
        raise ValueError(
            "literal frozen actual receipt rejected: " + checked.stdout + checked.stderr
        )
    terminal = re.findall(r"^EXACT_CONTROL_ACTUAL_PASS[^\n]*$", log, re.MULTILINE)
    count = int(re.search(r" checks=(\d+) ", terminal[0])[1])
    qualified = runpy.run_path(
        str(frozen / "prepare_exact_control_status_qualified.py")
    )["verify_observation_receipt"](log, count)
    if (actual.parent / "product-final-actual-owner-v1/process-exit.txt").read_text() != "0\n":
        raise ValueError("original C1 process did not exit zero")
    cdc = runpy.run_path(str(frozen / "prepare_fault_cdc_actual.py"))
    if cdc["verify_result"](logfile, 1, frozen) != qualified:
        raise ValueError("C1 actual receipt/qualified status disagrees")
    if sha(frozen / "starlink_pss_fft_bank_owned_slice.v") != "e8285f5ef2b548272ec357fca5213b1e400b5242396be2597498eff09f665579":
        raise ValueError("requires exact tested C1 runtime")
    for name, digest in {
        "starlink_pss_fft_bank_owned_product_fence.v": "8923b42b3574fc1418eee99c5f5819f173c73fbf7b8bb65726a7ab3a5d8a6f7c",
        "starlink_pss_product_fence_mailbox.v": "e4f4c56ddab8f05d0f9b9da9a75f975e11cb8ad441581c904bfb094f3013982f",
    }.items():
        if sha(frozen / name) != digest:
            raise ValueError("requires exact tested producer-final runtime: " + name)
    if rom_qualified != qualified:
        raise ValueError("ROM and original qualified-status receipts disagree")
    hashes = {
        name: sha(simulation / name)
        for name in (
            "fft_bank_owned_trace.csv",
            "exact_control_reference_trace.csv",
            "exact_control_extra_trace.csv",
            "exact_control_reference_extra_trace.csv",
        )
    }
    expected = "25ab9d06ca0e03f280540cda625a7826b3c4cbaa6322ce3266c59e1fbad94122"
    if (
        hashes["fft_bank_owned_trace.csv"] != expected
        or hashes["exact_control_reference_trace.csv"] != expected
    ):
        raise ValueError("historical R1 full CSV differs")
    if (
        hashes["exact_control_extra_trace.csv"]
        != hashes["exact_control_reference_extra_trace.csv"]
        or not (simulation / "exact_control_extra_trace.csv").stat().st_size
    ):
        raise ValueError("independent extra CSVs differ or are empty")
    if hashes["exact_control_extra_trace.csv"] != "b965d12603a64111fa9c6ea36cb0f12189945ad4d9be7cf4fbd883980c4ec4a0":
        raise ValueError("historical passing111 extra CSV differs")
    return {
        "actual_directory": str(actual.resolve()),
        "inventory_sha256": ACTUAL_INVENTORY,
        "settings": metadata["settings"],
        "source_sha256": metadata["source_sha256"],
        "simulation_sha256": sha(logfile),
        "launch_sha256": sha(actual.parent / "product-final-actual-owner-v1/launch.log"),
        "time_sha256": sha(actual.parent / "product-final-actual-owner-v1/time.txt"),
        "csv_sha256": hashes,
        "qualified_observer": qualified,
        "exact_control_terminal": terminal[0],
        "cdc_terminal": re.findall(r"^FAULT_CDC_ACTUAL_PASS[^\n]*$", log, re.MULTILINE)[0],
        "rom_terminal": re.findall(r"^ROM_READ_AHEAD_ACTUAL_PASS[^\n]*$", log, re.MULTILINE)[0],
        "product_final_terminal": re.findall(r"^PRODUCT_FINAL_FENCE_ACTUAL_PASS[^\n]*$", log, re.MULTILINE)[0],
        "rom_owner_sha256": {p.name: sha(p) for p in sorted(owner.iterdir()) if p.is_file()},
        "rom_generated_IP_after_only": ip,
    }


def bindings(actual):
    path = str(
        Path(actual["actual_directory"])
        / "project/exact_control_actual.sim/sim_1/behav/xsim/simulate.log"
    )
    if any(char in path for char in "{}\\\r\n"):
        raise ValueError("unsupported Tcl path characters")
    options = actual["settings"]
    return (
        f"set registered {options['REGISTERED_SCHEDULING']}\n"
        f"set distributed {options['DISTRIBUTED_FAST_FAULT']}\n"
        f"set per_cause {options['PER_CAUSE_FAULT_CDC']}\n"
        f"set rom_word {options['PRIVATE_ROM_READ_AHEAD']}\n"
        f"set rom_metadata {options['PRIVATE_BLOCK_METADATA_READ_AHEAD']}\n"
        f"set producer_final {options['PRODUCER_LOCAL_FINAL_FENCE']}\n"
        f"set scratch {options['PRIVATE_NEXT_START_SCRATCH']}\nset simlog {{{path}}}\n"
    )


def verify_prepared(prepared, copied=None, expected_inventory=None):
    if (
        expected_inventory is not None
        and sha(prepared / "SHA256SUMS") != expected_inventory
    ):
        raise ValueError("prepared inventory changed from reviewed identity")
    subprocess.run(
        ["sha256sum", "-c", "SHA256SUMS", "--quiet"],
        cwd=prepared,
        check=True,
        timeout=10,
    )
    metadata = json.loads((prepared / "physical_preparation.json").read_text())
    actual = verify_actual(Path(metadata["actual"]["actual_directory"]))
    if actual != metadata["actual"] or (
        prepared / "exact_physical_settings.tcl"
    ).read_text() != bindings(actual):
        raise ValueError("actual evidence or explicit bindings changed")
    source = prepared / "frozen_sources"
    expected_sources = {
        name: (
            FIXED[name]
            if name
            in {"fft_bank_owned_resource_probe.xdc", "fft_bank_owned_synth_threads.tcl"}
            else actual["source_sha256"][name]
        )
        for name in SOURCE_NAMES
    }
    if (
        metadata["source_sha256"] != expected_sources
        or metadata["fixed_tools_sha256"] != FIXED
    ):
        raise ValueError(
            "source identities no longer close passed actual and fixed tools"
        )
    original = prepared / "synthesize_fft_bank_owned_slice.original.tcl"
    if (
        sha(original) != FIXED["synthesize_fft_bank_owned_slice.tcl"]
        or sha(prepared / "route_completed_input_fence.tcl")
        != FIXED["route_completed_input_fence.tcl"]
        or (prepared / "synthesize_exact_control_prepared.tcl").read_text()
        != adapt_synthesis(original.read_text())
    ):
        raise ValueError("fixed physical scripts or exact adapter changed")
    if {p.name for p in source.iterdir()} != set(SOURCE_NAMES):
        raise ValueError("physical source closure has extra or missing files")
    if {p.name: sha(p) for p in source.iterdir()} != metadata["source_sha256"]:
        raise ValueError("physical source closure changed")
    if copied is not None:
        if {p.name for p in copied.iterdir()} != set(SOURCE_NAMES) | {
            "synthesize_exact_control_prepared.tcl"
        }:
            raise ValueError("copied complete input closure differs")
        for name in SOURCE_NAMES:
            if sha(copied / name) != metadata["source_sha256"][name]:
                raise ValueError("copied synthesis source differs: " + name)
        if sha(copied / "synthesize_exact_control_prepared.tcl") != sha(
            prepared / "synthesize_exact_control_prepared.tcl"
        ):
            raise ValueError("copied synthesis source differs: adapter")
    return {
        "scope": "verified_preparation_NOT_physical_execution",
        "registered": 1,
        "distributed": 1,
        "scratch": 1,
        "per_cause": 1,
        "rom_word": 1,
        "rom_metadata": 1,
        "rtl_count": 8,
        "producer_final": 1,
        "qualified_observer": actual["qualified_observer"],
    }


def prepare(actual_dir, output):
    if output.exists():
        raise FileExistsError("refusing to overwrite physical preparation")
    actual = verify_actual(actual_dir)
    tools = Path(__file__).resolve().parent
    for name, expected in FIXED.items():
        if sha(tools / name) != expected:
            raise ValueError("fixed physical tool changed: " + name)
    frozen = actual_dir / "frozen_sources"
    if (
        sha(frozen / "create_shared_realtime_xfft_ip.tcl")
        != FIXED["create_shared_realtime_xfft_ip.tcl"]
    ):
        raise ValueError("actual IP factory differs")
    source = output / "frozen_sources"
    source.mkdir(parents=True)
    for name in SOURCE_NAMES:
        origin = (
            tools
            if name
            in {"fft_bank_owned_resource_probe.xdc", "fft_bank_owned_synth_threads.tcl"}
            else frozen
        )
        shutil.copyfile(origin / name, source / name)
    shutil.copyfile(__file__, output / Path(__file__).name)
    shutil.copyfile(
        tools / "run_exact_control_synthesis.py",
        output / "run_exact_control_synthesis.py",
    )
    shutil.copyfile(
        tools / "route_completed_input_fence.tcl",
        output / "route_completed_input_fence.tcl",
    )
    original = (tools / "synthesize_fft_bank_owned_slice.tcl").read_text()
    (output / "synthesize_fft_bank_owned_slice.original.tcl").write_text(original)
    (output / "synthesize_exact_control_prepared.tcl").write_text(
        adapt_synthesis(original)
    )
    (output / "exact_physical_settings.tcl").write_text(bindings(actual))
    metadata = {
        "scope": "OFFLINE_ONLY_exact111C1K1M1P1_physical_preparation_NO_synthesis_route",
        "actual": actual,
        "fixed_tools_sha256": FIXED,
        "source_sha256": {p.name: sha(p) for p in sorted(source.iterdir())},
    }
    (output / "physical_preparation.json").write_text(
        json.dumps(metadata, indent=2) + "\n"
    )
    files = sorted(p for p in output.rglob("*") if p.is_file())
    (output / "SHA256SUMS").write_text(
        "".join(f"{sha(p)}  {p.relative_to(output)}\n" for p in files)
    )
    return verify_prepared(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--actual", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--verify", type=Path)
    parser.add_argument("--expected")
    parser.add_argument("--copied", type=Path)
    args = parser.parse_args()
    if (
        args.verify is not None
        and args.actual is None
        and args.output is None
        and args.expected is not None
    ):
        result = verify_prepared(args.verify, args.copied, args.expected)
    elif (
        args.actual is not None
        and args.output is not None
        and args.verify is None
        and args.copied is None
        and args.expected is None
    ):
        result = prepare(args.actual, args.output)
    else:
        parser.error(
            "choose --actual/--output or --verify/--expected with optional --copied"
        )
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
