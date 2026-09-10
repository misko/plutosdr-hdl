"""Offline source-specific L1/R1B1O1 OOC preparation. Never launches Vivado."""
import argparse
import hashlib
import importlib.util
import json
import shutil
from pathlib import Path

BASE_HELPER_SHA = "6701325bbae5b6a82e75155e0b7eaadc222fd6cf9126f3b88b251a810669fbbd"
BASE_TCL_SHA = "359864493a948bab19bd0bc0079b7f7402b28fcb20caa9fb305496b4c7711183"
BASE_RUNNER_SHA = "137f77891cbb0f61e5f376a0ea0774dfac3dc4b4dfaf291008f10bd9aeb3d160"
RUNNER = "run_local_admission_synthesis.py"
SYNTHESIS = "synthesize_local_admission_prepared.tcl"
SETTINGS = "local_admission_physical_settings.tcl"
BASE_REFERENCE = "prepare_arithmetic_physical.reference.py"
ADMISSION = "verify_local_admission_ooc_actual.py"
POLICY = "test_local_admission_physical_preparation.py"
BASE_INVENTORY = "c249a13a4e34aa393513fa955199407eef0a569484025d1e5cdb5fc83cb185ce"


def module(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


def admit():
    return module(Path(__file__).resolve().with_name(ADMISSION), "local_physical_admission")


def base():
    directory = Path(__file__).resolve().parent
    path = directory / BASE_REFERENCE
    if not path.exists():
        path = directory / "prepare_arithmetic_physical.py"
    admit().require(admit().sha(path) == BASE_HELPER_SHA, "original arithmetic physical recipe changed")
    return module(path, "literal_arithmetic_physical_recipe")


def once(text, before, after):
    if text.count(before) != 1:
        raise ValueError("nonunique local synthesis adaptation anchor")
    return text.replace(before, after, 1)


LEXICAL_TCL = """# Reject aliases before normalization can hide source/output ancestry.
foreach requested_path [list [lindex $argv 0] [lindex $argv 1] [info script]] {
  set lexical_path $requested_path
  if {[file pathtype $lexical_path] eq "relative"} { set lexical_path [file join [pwd] $lexical_path] }
  while {1} {
    if {![catch {file type $lexical_path} lexical_type] && $lexical_type eq "link"} {
      error "symlink physical path forbidden: $lexical_path"
    }
    set parent_path [file dirname $lexical_path]
    if {$parent_path eq $lexical_path} { break }
    set lexical_path $parent_path
  }
}
"""


def synthesis_edits():
    return (
        ("set output_dir [file normalize [lindex $argv 0]]", LEXICAL_TCL + "set output_dir [file normalize [lindex $argv 0]]"),
        ("set audit_helper [file join $evidence_dir prepare_arithmetic_physical.py]",
         "set audit_helper [file join $evidence_dir prepare_local_admission_physical.py]"),
        ("source [file join $evidence_dir arithmetic_physical_settings.tcl]",
         "source [file join $evidence_dir local_admission_physical_settings.tcl]"),
        ('if {$registered != 1 || $round != 1 || $operands != 1} { error "wrong arithmetic physical options" }',
         'if {$registered != 1 || $round != 1 || $operands != 1 || $local != 1} { error "wrong arithmetic/local physical options" }'),
        ("set rtl_names {starlink_pss_fft_bank_owned_arithmetic_probe starlink_pss_realtime_input_guard\n",
         "set rtl_names {starlink_pss_fft_bank_owned_local_admission_probe starlink_pss_realtime_input_guard_local_admission\n"),
        ("set_property top starlink_pss_fft_bank_owned_arithmetic_probe [get_filesets sources_1]",
         "set_property top starlink_pss_fft_bank_owned_local_admission_probe [get_filesets sources_1]"),
        ("  REGISTER_OPERANDS=$operands] [get_filesets sources_1]",
         "  REGISTER_OPERANDS=$operands LOCAL_FIRST_ADMISSION=$local] [get_filesets sources_1]"),
        ("BOUNDARY_ROUND_SAT $round REGISTER_OPERANDS $operands] {",
         "BOUNDARY_ROUND_SAT $round REGISTER_OPERANDS $operands LOCAL_FIRST_ADMISSION $local] {"),
        ('puts $channel "boundary_round_sat=$round; register_operands=$operands"',
         'puts $channel "boundary_round_sat=$round; register_operands=$operands"\nputs $channel "local_first_admission=$local; default_off=true"'),
    )


def runner_edits():
    return (
        ('str(prepared / "prepare_arithmetic_physical.py")', 'str(prepared / "prepare_local_admission_physical.py")'),
        ('str(prepared / "synthesize_arithmetic_prepared.tcl")', 'str(prepared / "synthesize_local_admission_prepared.tcl")'),
        ("    prepared, run = prepared.resolve(), run.resolve()",
         ("    for requested in (prepared, run):\n"
         "        lexical = requested if requested.is_absolute() else Path.cwd() / requested\n"
         "        if any(p.is_symlink() for p in (lexical, *lexical.parents)):\n"
         "            raise ValueError(\"symlink physical owner path forbidden\")\n"
         "    prepared, run = prepared.resolve(), run.resolve()")),
    )


def adapt(text, edits, inverse=False):
    for old, new in reversed(edits) if inverse else edits:
        text = once(text, new, old) if inverse else once(text, old, new)
    return text


def source_names():
    return tuple(admit().RTL_HASHES) + (
        "create_shared_realtime_xfft_ip.tcl", "upper_edge_pss_kernel_q17.mem",
        "fft_bank_owned_resource_probe.xdc", "fft_bank_owned_synth_threads.tcl")


def evidence_inputs():
    tools = Path(__file__).resolve().parent
    frozen = tools / "admission_evidence"
    if frozen.is_dir():
        return {name: frozen / name for name in admit().EVIDENCE}
    build = tools / "build"
    owner = build / "local-admission-L1-175-actual-owned-v3"
    query = build / "local-admission-wdb-history-v1.7RQSIW"
    return {"actual_before.json": owner / "before.json", "actual_terminal.json": owner / "terminal.json",
            "actual_outer.log": owner / "outer.log", "wdb_before.json": query / "before.json",
            "wdb_terminal.json": query / "terminal.json", "wdb_outer.log": query / "outer.log",
            "read_original6473_wdb.tcl": query / "read_original6473_wdb.tcl",
            "own_readonly_wdb.py": query / "own_readonly_wdb.py",
            "arithmetic_wdb_reference.log": build / "bank-arithmetic-monitor-actual-assessment-v1.OsPugx/read_original_v3_wdb_candidate.outer.log"}


def settings(actual):
    path = str(Path(actual["actual_directory"]) / admit().SIM / "simulate.log")
    if any(c in path for c in "{}\\\r\n"):
        raise ValueError("unsupported Tcl source path")
    return "set registered 1\nset round 1\nset operands 1\nset local 1\n" + f"set simlog {{{path}}}\n"


def inventory(root):
    entries = list(root.rglob("*"))
    if any(p.is_symlink() for p in entries):
        raise ValueError("symlink prepared member forbidden")
    return {p.relative_to(root).as_posix(): admit().sha(p) for p in entries if p.is_file() and p != root / "SHA256SUMS"}


def verify(prepared, expected, copied=None):
    gate = admit()
    prepared = gate.safe(prepared)
    gate.require(gate.sha(gate.safe(prepared / "SHA256SUMS")) == expected, "unexpected local physical preparation")
    lines = (prepared / "SHA256SUMS").read_text().splitlines()
    pairs = [line.split("  ", 1) for line in lines]
    gate.require(all(len(row) == 2 for row in pairs), "malformed inventory")
    listed = {name: value for value, name in pairs}
    gate.require(len(listed) == len(pairs) and inventory(prepared) == listed, "complete prepared inventory differs")
    declared = {ADMISSION, "prepare_local_admission_physical.py", BASE_REFERENCE, POLICY,
                "route_completed_input_fence.tcl", "run_arithmetic_synthesis.original.py",
                "synthesize_fft_bank_owned_slice.original.tcl", "synthesize_arithmetic_prepared.reference.tcl",
                SYNTHESIS, RUNNER, SETTINGS, "physical_preparation.json"}
    declared |= {"frozen_sources/" + name for name in source_names()}
    declared |= {"admission_evidence/" + name for name in gate.EVIDENCE}
    gate.require(set(listed) == declared, "declared physical source/helper closure differs")
    metadata = json.loads((prepared / "physical_preparation.json").read_text())
    actual = gate.verify(metadata["actual"]["actual_directory"], prepared / "admission_evidence")
    gate.require(actual == metadata["actual"] and metadata["options"] == {"R": 1, "B": 1, "O": 1, "L": 1}, "actual admission or local options changed")
    gate.require(metadata["scope"] == "OFFLINE_ONLY_L1_R1B1O1_NO_SYNTHESIS_ROUTE" and
                 metadata["arithmetic_baseline_inventory"] == BASE_INVENTORY, "physical scope/baseline changed")
    gate.require(gate.sha(prepared / BASE_REFERENCE) == BASE_HELPER_SHA, "frozen baseline recipe identity changed")
    literal = base()
    gate.require(metadata["fixed_tools_sha256"] == literal.FIXED, "fixed recipe identity changed")
    original = prepared / "synthesize_fft_bank_owned_slice.original.tcl"
    reference = prepared / "synthesize_arithmetic_prepared.reference.tcl"
    gate.require(gate.sha(original) == literal.FIXED["synthesize_fft_bank_owned_slice.tcl"] and
                 gate.sha(reference) == BASE_TCL_SHA and reference.read_text() == literal.adapt_synthesis(original.read_text()), "original arithmetic synthesis inverse changed")
    gate.require((prepared / SYNTHESIS).read_text() == adapt(reference.read_text(), synthesis_edits()), "local synthesis-only inverse changed")
    gate.require(gate.sha(prepared / "run_arithmetic_synthesis.original.py") == BASE_RUNNER_SHA and
                 (prepared / RUNNER).read_text() == adapt((prepared / "run_arithmetic_synthesis.original.py").read_text(), runner_edits()), "one-shot owner inverse changed")
    gate.require(gate.sha(prepared / "route_completed_input_fence.tcl") == literal.FIXED["route_completed_input_fence.tcl"], "original route recipe changed")
    gate.require((prepared / SETTINGS).read_text() == settings(actual), "explicit local physical bindings changed")
    sources = prepared / "frozen_sources"
    expected_sources = {name: literal.FIXED[name] if name in {"fft_bank_owned_resource_probe.xdc", "fft_bank_owned_synth_threads.tcl"}
                        else actual["source_sha256"][name] for name in source_names()}
    gate.require(metadata["source_sha256"] == expected_sources and
                 {p.name: gate.sha(p) for p in sources.iterdir()} == expected_sources, "physical runtime source closure changed")
    if copied is not None:
        copied = gate.safe(copied)
        gate.require({p.name for p in copied.iterdir()} == set(expected_sources) | {SYNTHESIS} and
                     all(p.is_file() and not p.is_symlink() for p in copied.iterdir()), "copied physical input closure differs")
        gate.require(all(gate.sha(copied / name) == value for name, value in expected_sources.items()) and
                     gate.sha(copied / SYNTHESIS) == gate.sha(prepared / SYNTHESIS), "copied physical input bytes differ")
    return {"scope": "verified_preparation_NO_physical_execution", "R": 1, "B": 1, "O": 1, "L": 1,
            "rtl_count": 8, "source_count": 12, "functional_terminals": actual["functional_terminals"],
            "original_automation_status": "PASS", "histories": actual["histories"]}


def prepare(actual, output):
    gate, literal = admit(), base()
    actual, output = gate.safe(actual), gate.safe(output)
    if output.exists():
        raise FileExistsError("refusing physical preparation overwrite")
    tools = Path(__file__).resolve().parent
    evidence = evidence_inputs()
    for name, path in evidence.items():
        gate.require(gate.sha(gate.safe(path)) == gate.EVIDENCE[name], "reviewed evidence changed")
    # Validate admission before creating the final exclusive preparation.
    gate.verify_sources(actual)
    for name, value in literal.FIXED.items():
        gate.require(gate.sha(tools / name) == value, "fixed physical file changed: " + name)
    original = (tools / "synthesize_fft_bank_owned_slice.tcl").read_text()
    reference = literal.adapt_synthesis(original)
    gate.require(hashlib.sha256(reference.encode()).hexdigest() == BASE_TCL_SHA, "baseline adapter differs")
    gate.require(gate.sha(tools / "run_arithmetic_synthesis.py") == BASE_RUNNER_SHA, "original owner changed")
    output.mkdir(parents=True, exist_ok=False)
    source = output / "frozen_sources"
    source.mkdir()
    admission = output / "admission_evidence"
    admission.mkdir()
    for name, path in evidence.items():
        shutil.copyfile(path, admission / name)
    qualified = gate.verify(actual, admission)
    for name in source_names():
        origin = tools if name in {"fft_bank_owned_resource_probe.xdc", "fft_bank_owned_synth_threads.tcl"} else actual / "frozen_sources"
        shutil.copyfile(origin / name, source / name)
    for name in (ADMISSION, "prepare_local_admission_physical.py", "route_completed_input_fence.tcl"):
        shutil.copyfile(tools / name, output / name)
    shutil.copyfile(tools.parents[2] / "tests/starlink_oracle" / POLICY, output / POLICY)
    shutil.copyfile(tools / "prepare_arithmetic_physical.py", output / BASE_REFERENCE)
    shutil.copyfile(tools / "run_arithmetic_synthesis.py", output / "run_arithmetic_synthesis.original.py")
    (output / "synthesize_fft_bank_owned_slice.original.tcl").write_text(original)
    (output / "synthesize_arithmetic_prepared.reference.tcl").write_text(reference)
    (output / SYNTHESIS).write_text(adapt(reference, synthesis_edits()))
    (output / RUNNER).write_text(adapt((tools / "run_arithmetic_synthesis.py").read_text(), runner_edits()))
    (output / SETTINGS).write_text(settings(qualified))
    metadata = {"scope": "OFFLINE_ONLY_L1_R1B1O1_NO_SYNTHESIS_ROUTE", "actual": qualified,
                "options": {"R": 1, "B": 1, "O": 1, "L": 1}, "arithmetic_baseline_inventory": BASE_INVENTORY,
                "fixed_tools_sha256": literal.FIXED, "source_sha256": {p.name: gate.sha(p) for p in source.iterdir()}}
    (output / "physical_preparation.json").write_text(json.dumps(metadata, indent=2, sort_keys=True) + "\n")
    (output / "SHA256SUMS").write_text("".join(f"{value}  {name}\n" for name, value in sorted(inventory(output).items())))
    return verify(output, gate.sha(output / "SHA256SUMS"))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--actual", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--verify", type=Path)
    parser.add_argument("--expected")
    parser.add_argument("--copied", type=Path)
    args = parser.parse_args()
    if args.actual is not None and args.output is not None and args.verify is None and args.expected is None and args.copied is None:
        value = prepare(args.actual, args.output)
    elif args.verify is not None and args.expected is not None and args.actual is None and args.output is None:
        value = verify(args.verify, args.expected, args.copied)
    else:
        parser.error("choose --actual/--output or --verify/--expected [--copied]")
    print(json.dumps(value, sort_keys=True))


if __name__ == "__main__":
    main()
