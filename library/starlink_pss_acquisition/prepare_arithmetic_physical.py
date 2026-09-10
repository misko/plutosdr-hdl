"""Offline OOC preparation from exact R1/B1/O1 reviewed post-hoc actual evidence."""

import argparse
import hashlib
import importlib.util
import json
import shutil
import subprocess
from pathlib import Path

PYTHON = "/home/mouse9911/gits/pluto-plus-utils/.venv/bin/python"
PYTHON_CHILD = f"env -u PYTHONHOME -u PYTHONPATH -u LD_LIBRARY_PATH {PYTHON} -B"
RTL = tuple(
    f"starlink_pss_{name}.v"
    for name in (
        "fft_bank_owned_arithmetic_probe",
        "realtime_input_guard",
        "realtime_result_guard",
        "block_mailbox",
        "forward_kernel_join",
        "kernel_rom",
        "spectrum_product_operand_register",
        "spectrum_product_bank_arithmetic",
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
  error "unexpected arithmetic physical preparation"
}}
set audit_helper [file join $evidence_dir prepare_arithmetic_physical.py]
set old_directory [pwd]; cd $evidence_dir
exec sha256sum -c SHA256SUMS --quiet
cd $old_directory
puts [exec {PYTHON_CHILD} $audit_helper --verify $evidence_dir --expected $expected_prepared]
source [file join $evidence_dir arithmetic_physical_settings.tcl]
if {{$registered != 1 || $round != 1 || $operands != 1}} {{ error "wrong arithmetic physical options" }}
set prior_sources [file join $evidence_dir frozen_sources]
"""
COPY_VERIFY = f"puts [exec {PYTHON_CHILD} $audit_helper --verify $evidence_dir --expected $expected_prepared --copied $source_dir]\n"
GENERIC_CHECK = """set physical_generics [get_property GENERIC [get_filesets sources_1]]
foreach {name value} [list REGISTERED_SCHEDULING $registered BOUNDARY_ROUND_SAT $round REGISTER_OPERANDS $operands] {
  if {[lsearch -exact $physical_generics ${name}=$value] < 0} { error "missing physical parameter $name" }
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


def synthesis_edits():
    return (
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
            "set rtl_names {starlink_pss_fft_bank_owned_slice ",
            "set rtl_names {starlink_pss_fft_bank_owned_arithmetic_probe ",
        ),
        (
            "starlink_pss_kernel_rom starlink_pss_spectrum_product}",
            (
                "starlink_pss_kernel_rom starlink_pss_spectrum_product_operand_register\n"
                "  starlink_pss_spectrum_product_bank_arithmetic}"
            ),
        ),
        (
            "set_property top starlink_pss_fft_bank_owned_slice [get_filesets sources_1]",
            "set_property top starlink_pss_fft_bank_owned_arithmetic_probe [get_filesets sources_1]",
        ),
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
            "  REGISTERED_SCHEDULING=$registered BOUNDARY_ROUND_SAT=$round \\\n  REGISTER_OPERANDS=$operands] [get_filesets sources_1]\n"
            + GENERIC_CHECK,
        ),
        (
            'puts $channel "registered_scheduling=$registered"\n',
            (
                'puts $channel "registered_scheduling=$registered"\n'
                'puts $channel "boundary_round_sat=$round; register_operands=$operands"\n'
                'puts $channel "effective_top_generics=$physical_generics"\n'
            ),
        ),
        (
            "launch_runs $ip_run -jobs 2\n",
            COPY_VERIFY + "launch_runs $ip_run -jobs 2\n",
        ),
        ("close_project\n", COPY_VERIFY + "close_project\n"),
    )


def adapt_synthesis(original):
    for old, new in synthesis_edits():
        original = once(original, old, new)
    return original


def admission_inputs():
    tools = Path(__file__).resolve().parent
    frozen = tools / "admission_evidence"
    if frozen.is_dir():
        return {
            name: frozen / name
            for name in (
                "originals.json",
                "posthoc_assessment.json",
                "read_original_v3_wdb_candidate.outer.log",
            )
        }
    assessment = tools / "build/bank-arithmetic-monitor-actual-assessment-v1.OsPugx"
    return {
        "originals.json": tools.parents[2]
        / "reports/experiments/20260910-bank-arithmetic-monitor-actual175-originals-v3.json",
        "posthoc_assessment.json": assessment / "posthoc_assessment.json",
        "read_original_v3_wdb_candidate.outer.log": assessment
        / "read_original_v3_wdb_candidate.outer.log",
    }


def verify_actual(actual, evidence=None):
    path = Path(__file__).resolve().parent / "verify_arithmetic_ooc_actual.py"
    spec = importlib.util.spec_from_file_location("arithmetic_ooc_admission", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module.verify(actual, admission_inputs() if evidence is None else evidence)


def bindings(actual):
    path = str(
        Path(actual["actual_directory"])
        / "project/fft_bank_arithmetic_actual.sim/sim_1/behav/xsim/simulate.log"
    )
    if any(char in path for char in "{}\\\r\n"):
        raise ValueError("unsupported Tcl path characters")
    return (
        "set registered 1\nset round 1\nset operands 1\n" + f"set simlog {{{path}}}\n"
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
    inventoried = [
        line.split("  ", 1)[1]
        for line in (prepared / "SHA256SUMS").read_text().splitlines()
    ]
    extant = [
        str(p.relative_to(prepared))
        for p in prepared.rglob("*")
        if p.is_file() and p.name != "SHA256SUMS"
    ]
    if len(inventoried) != len(set(inventoried)) or set(extant) != set(inventoried):
        raise ValueError("prepared full inventory closure differs")
    metadata = json.loads((prepared / "physical_preparation.json").read_text())
    actual = verify_actual(
        Path(metadata["actual"]["actual_directory"]), prepared / "admission_evidence"
    )
    if actual != metadata["actual"] or (
        prepared / "arithmetic_physical_settings.tcl"
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
        or (prepared / "synthesize_arithmetic_prepared.tcl").read_text()
        != adapt_synthesis(original.read_text())
    ):
        raise ValueError("fixed physical scripts or exact adapter changed")
    if {p.name for p in source.iterdir()} != set(SOURCE_NAMES):
        raise ValueError("physical source closure has extra or missing files")
    if {p.name: sha(p) for p in source.iterdir()} != metadata["source_sha256"]:
        raise ValueError("physical source closure changed")
    if copied is not None:
        if {p.name for p in copied.iterdir()} != set(SOURCE_NAMES) | {
            "synthesize_arithmetic_prepared.tcl"
        }:
            raise ValueError("copied complete input closure differs")
        for name in SOURCE_NAMES:
            if sha(copied / name) != metadata["source_sha256"][name]:
                raise ValueError("copied synthesis source differs: " + name)
        if sha(copied / "synthesize_arithmetic_prepared.tcl") != sha(
            prepared / "synthesize_arithmetic_prepared.tcl"
        ):
            raise ValueError("copied synthesis source differs: adapter")
    return {
        "scope": "verified_preparation_NOT_physical_execution",
        "registered": 1,
        "round": 1,
        "operands": 1,
        "rtl_count": 8,
        "original_automation_status": actual["original_automation_status"],
        "functional_terminals": actual["functional_terminals"],
        "histories": actual["histories"],
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
    evidence = output / "admission_evidence"
    evidence.mkdir()
    for name, path in admission_inputs().items():
        shutil.copyfile(path, evidence / name)
    shutil.copyfile(
        tools / "verify_arithmetic_ooc_actual.py",
        output / "verify_arithmetic_ooc_actual.py",
    )
    shutil.copyfile(__file__, output / Path(__file__).name)
    shutil.copyfile(
        tools / "run_arithmetic_synthesis.py",
        output / "run_arithmetic_synthesis.py",
    )
    shutil.copyfile(
        tools / "route_completed_input_fence.tcl",
        output / "route_completed_input_fence.tcl",
    )
    original = (tools / "synthesize_fft_bank_owned_slice.tcl").read_text()
    (output / "synthesize_fft_bank_owned_slice.original.tcl").write_text(original)
    (output / "synthesize_arithmetic_prepared.tcl").write_text(
        adapt_synthesis(original)
    )
    (output / "arithmetic_physical_settings.tcl").write_text(bindings(actual))
    metadata = {
        "scope": "OFFLINE_ONLY_arithmetic_R1_B1_O1_NO_synthesis_route",
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
