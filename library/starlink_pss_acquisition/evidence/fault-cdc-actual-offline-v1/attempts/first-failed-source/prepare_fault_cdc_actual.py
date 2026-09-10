"""Offline-only CDC actual admission from the immutable passing111 run."""

import argparse
import hashlib
import json
import re
import runpy
import shutil
import subprocess
from pathlib import Path

RUNTIME_PIN = "02de07cc7a6c241dd6cc8cf5b733037d89eac6bd"
WRAPPER_SHA = "e8285f5ef2b548272ec357fca5213b1e400b5242396be2597498eff09f665579"
TOP = "tb_starlink_pss_fft_bank_owned_slice.sv"
RUNNER = "simulate_exact_control_prepared.tcl"
OBSERVER = "starlink_pss_fault_cdc_actual_observer.svh"
OBS_INCLUDE = '  `include "starlink_pss_fault_cdc_actual_observer.svh"\n'
PARAMETER = "  parameter integer PER_CAUSE_FAULT_CDC = 0;\n"
BINDING = "    .PER_CAUSE_FAULT_CDC(PER_CAUSE_FAULT_CDC),\n"
TERMINAL_CALL = "    fault_cdc_verify_terminal();\n"
TCL_RECEIPTS = r"""# BEGIN FAULT_CDC_RECEIPTS
proc fault_cdc_verify_receipt {log enabled} {
  set lines [regexp -all -inline -line {^FAULT_CDC_ACTUAL_PASS[^\n]*$} $log]
  if {[llength $lines] != 1} {error "expected exactly one CDC terminal"}
  set pattern {^FAULT_CDC_ACTUAL_PASS enabled=([01]) checks=([0-9]+) stage0_high=([0-9]+) stage1_high=([0-9]+) reset_samples=([0-9]+) current_fault_edges=([0-9]+) final_fault_edges=([0-9]+) private_core_reset_samples=([0-9]+) scalar_source=actual_fast_fault reference_reset=slow_running$}
  if {![regexp $pattern [lindex $lines 0] unused c checks first second resets current final private]} {
    error "malformed CDC settings/count receipt"
  }
  if {$c != $enabled || $checks <= 0 || $first <= 0 || $second <= 0 ||
      $resets <= 0 || $current <= 0 || $final < 2} {error "CDC setting/coverage mismatch"}
  return "FAULT_CDC_RECEIPT_VERIFIED"
}
# END FAULT_CDC_RECEIPTS
"""
TCL_BINDING = """set per_cause [expr {[lsearch -exact $exact_generics PER_CAUSE_FAULT_CDC=1] >= 0}]
if {!$registered || !$distributed || !$scratch || !$extras} {error "requires passing111 extra baseline"}
"""
TCL_READBACK = """if {[lsort [get_property GENERIC [get_filesets sim_1]]] ne [lsort $exact_generics]} {
  error "CDC actual generic readback mismatch"
}
"""
EXTRA_GATE = """# The unchanged full extra epochs must match the passing111 history too.
foreach name {exact_control_extra_trace.csv exact_control_reference_extra_trace.csv} {
  if {[lindex [exec sha256sum [file join $simulation_dir $name]] 0] ne "b965d12603a64111fa9c6ea36cb0f12189945ad4d9be7cf4fbd883980c4ec4a0"} {
    error "passing111 full extra CSV changed"
  }
}
"""


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def once(text, old, new):
    if text.count(old) != 1:
        raise ValueError("nonunique CDC actual adapter anchor")
    return text.replace(old, new, 1)


def adapt_bench(text):
    for old, new in (
        (
            "  parameter integer DISTRIBUTED_FAST_FAULT = 0;\n",
            "  parameter integer DISTRIBUTED_FAST_FAULT = 0;\n" + PARAMETER,
        ),
        (
            "    .DISTRIBUTED_FAST_FAULT(DISTRIBUTED_FAST_FAULT),\n",
            "    .DISTRIBUTED_FAST_FAULT(DISTRIBUTED_FAST_FAULT),\n" + BINDING,
        ),
        (
            "  // BEGIN EXACT_CONTROL_SHADOW\n",
            OBS_INCLUDE + "  // BEGIN EXACT_CONTROL_SHADOW\n",
        ),
        (
            '    $display("EXACT_CONTROL_ACTUAL_PASS registered=',
            TERMINAL_CALL + '    $display("EXACT_CONTROL_ACTUAL_PASS registered=',
        ),
    ):
        text = once(text, old, new)
    return text


def adapt_runner(text):
    for old, new in (
        (
            "# END EXACT_CONTROL_RECEIPTS\n",
            "# END EXACT_CONTROL_RECEIPTS\n" + TCL_RECEIPTS,
        ),
        ("[llength $exact_generics] != 6", "[llength $exact_generics] != 7"),
        (
            "PRIVATE_NEXT_START_SCRATCH EXACT_EXTRA_EPOCHS}",
            "PRIVATE_NEXT_START_SCRATCH EXACT_EXTRA_EPOCHS PER_CAUSE_FAULT_CDC}",
        ),
        (
            "set project_name exact_control_actual\n",
            TCL_BINDING + "set project_name exact_control_actual\n",
        ),
        (
            "set_property generic $exact_generics [get_filesets sim_1]\n",
            "set_property generic $exact_generics [get_filesets sim_1]\n"
            + TCL_READBACK,
        ),
        (
            "puts [exact_verify_receipts $log $registered $distributed $scratch $extras]\n",
            (
                "puts [exact_verify_receipts $log $registered $distributed $scratch $extras]\n"
                "puts [fault_cdc_verify_receipt $log $per_cause]\n"
            ),
        ),
        (
            'if {[lindex [exec sha256sum $candidate_csv] 0] ne $expected_csv} { error "original full CSV changed" }\n',
            'if {[lindex [exec sha256sum $candidate_csv] 0] ne $expected_csv} { error "original full CSV changed" }\n'
            + EXTRA_GATE,
        ),
    ):
        text = once(text, old, new)
    return text


def verify_result(log_path, enabled, source):
    log = log_path.read_text()
    if re.search(r"fatal:|error:", log, re.IGNORECASE) or "$finish called" not in log:
        raise ValueError("failed or incomplete actual run")
    lines = re.findall(r"^EXACT_CONTROL_ACTUAL_PASS[^\n]*$", log, re.MULTILINE)
    if len(lines) != 1:
        raise ValueError("missing exact terminal")
    count = int(re.search(r" checks=(\d+) ", lines[0])[1])
    original = runpy.run_path(str(source / "prepare_exact_control_status_qualified.py"))
    status = original["verify_observation_receipt"](log, count)
    proc = (
        (source / RUNNER)
        .read_text()
        .split("# BEGIN EXACT_CONTROL_RECEIPTS\n")[1]
        .split("# END EXACT_CONTROL_RECEIPTS")[0]
    )
    program = (
        proc
        + TCL_RECEIPTS
        + "\nset f [open [lindex $argv 0] r]; set log [read $f]; close $f\nputs [exact_verify_receipts $log 1 1 1 1]\n"
        + f"puts [fault_cdc_verify_receipt $log {enabled}]\n"
    )
    result = subprocess.run(
        ["tclsh", "/dev/stdin", str(log_path)],
        input=program,
        capture_output=True,
        text=True,
        check=False,
        timeout=15,
    )
    if result.returncode or result.stdout.splitlines() != [
        "EXACT_CONTROL_RECEIPTS_VERIFIED",
        "FAULT_CDC_RECEIPT_VERIFIED",
    ]:
        raise ValueError(
            "original or CDC receipt rejected: " + result.stdout + result.stderr
        )
    return status


def prepare(original, output, enabled=1):
    if enabled not in (0, 1):
        raise ValueError("explicit CDC option must be zero or one")
    if output.exists() or any(p.is_symlink() for p in (output, *output.parents)):
        raise FileExistsError("refusing to overwrite CDC actual preparation")
    if original.is_symlink() or (original / "frozen_sources").is_symlink():
        raise ValueError("symlinked actual source directory is not admitted")
    acq = Path(__file__).resolve().parent
    admission = runpy.run_path(str(acq / "prepare_exact_control_physical.py"))
    passed = admission["verify_actual"](original)
    inverse_path = acq.parents[2] / "tests/starlink_oracle/fault_cdc_contract.py"
    inverse = runpy.run_path(str(inverse_path))["restore_fault_cdc"]
    old_source = original / "frozen_sources"
    wrapper = "starlink_pss_fft_bank_owned_slice.v"
    if (
        sha(acq / wrapper) != WRAPPER_SHA
        or inverse((acq / wrapper).read_text()) != (old_source / wrapper).read_text()
    ):
        raise ValueError("CDC candidate differs from tested runtime/inverse")
    for name in admission["RTL"]:
        if (
            name != wrapper
            and (acq / name).read_bytes() != (old_source / name).read_bytes()
        ):
            raise ValueError("unrelated runtime changed: " + name)
    metadata = json.loads((original / "preparation.json").read_text())
    source = output / "frozen_sources"
    source.mkdir(parents=True)
    for name in metadata["source_sha256"]:
        shutil.copyfile(old_source / name, source / name)
    shutil.copyfile(acq / wrapper, source / wrapper)
    (source / TOP).write_text(adapt_bench((old_source / TOP).read_text()))
    (source / RUNNER).write_text(adapt_runner((old_source / RUNNER).read_text()))
    shutil.copyfile(acq / "tb" / OBSERVER, source / OBSERVER)
    shutil.copyfile(__file__, source / Path(__file__).name)
    shutil.copyfile(
        acq / "prepare_exact_control_physical.py",
        source / "prepare_exact_control_physical.py",
    )
    shutil.copyfile(inverse_path, source / inverse_path.name)
    settings = dict(metadata["settings"], PER_CAUSE_FAULT_CDC=enabled)
    metadata["settings"] = settings
    metadata["scope"] = (
        "OFFLINE_ONLY_CDC_actual_preparation_dec20_reference_unchanged_qualified_status_NOT_raw217"
    )
    metadata["cdc_origin_actual"] = passed
    metadata["cdc_tested_runtime_pin"] = RUNTIME_PIN
    metadata["source_sha256"] = {p.name: sha(p) for p in sorted(source.iterdir())}
    (output / "preparation.json").write_text(json.dumps(metadata, indent=2) + "\n")
    (output / "settings.tcl").write_text(
        "set exact_generics {"
        + " ".join(f"{k}={v}" for k, v in settings.items())
        + "}\n"
    )
    for name in (
        "original-SHA256SUMS",
        "strict-diagnostic-SHA256SUMS",
        "qualified-baseline-SHA256SUMS",
        "combined-origin-SHA256SUMS",
    ):
        shutil.copyfile(original / name, output / name)
    shutil.copyfile(original / "SHA256SUMS", output / "cdc-passing111-SHA256SUMS")
    files = sorted(p for p in output.rglob("*") if p.is_file())
    (output / "SHA256SUMS").write_text(
        "".join(f"{sha(p)}  {p.relative_to(output)}\n" for p in files)
    )
    subprocess.run(["sha256sum", "-c", "SHA256SUMS", "--quiet"], cwd=output, check=True)
    return settings


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--original", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--enabled", type=int, choices=(0, 1), default=1)
    args = parser.parse_args()
    print(json.dumps(prepare(args.original, args.output, args.enabled), sort_keys=True))


if __name__ == "__main__":
    main()
