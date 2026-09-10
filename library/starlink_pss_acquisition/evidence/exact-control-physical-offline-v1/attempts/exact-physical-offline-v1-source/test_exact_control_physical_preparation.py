"""Offline admission/source/parameter proof; Tcl mocks NEVER invoke Vivado."""

import importlib.util
import json
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ACQ = Path(__file__).resolve().parents[2] / "hdl/library/starlink_pss_acquisition"
ACTUAL = Path("/tmp/starlink-completed-input.5EaJuD/extra-edge-combined-prepared-v1")
SPEC = importlib.util.spec_from_file_location(
    "physical_prepare", ACQ / "prepare_exact_control_physical.py"
)
PREPARE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PREPARE)


@pytest.fixture(scope="module")
def prepared(tmp_path_factory):
    output = tmp_path_factory.mktemp("physical-fixture") / "prepared"
    receipt = PREPARE.prepare(ACTUAL, output)
    assert receipt["rtl_count"] == 7
    assert receipt["qualified_observer"] == {
        "samples": 1246258,
        "raw_equal": 953795,
        "invalid_only": 292463,
    }
    return output


def test_minimal_physical_adapter_whole_inverse_and_fixed_directives(prepared):
    original = (ACQ / "synthesize_fft_bank_owned_slice.tcl").read_text()
    assert (
        PREPARE.sha(ACQ / "synthesize_fft_bank_owned_slice.tcl")
        == PREPARE.FIXED["synthesize_fft_bank_owned_slice.tcl"]
    )
    text = (prepared / "synthesize_exact_control_prepared.tcl").read_text()
    text = PREPARE.once(
        text,
        'if {$argc != 3} { error "expected NEW_OUTPUT PREPARED EXPECTED_PREPARED_SHA256" }',
        'if {$argc != 2} { error "expected NEW_OUTPUT PASSED_SIMULATION_DIRECTORY" }',
    )
    text = PREPARE.once(
        text,
        "set script_dir [file join [file dirname [file normalize [info script]]] frozen_sources]",
        "set script_dir [file dirname [file normalize [info script]]]",
    )
    text = PREPARE.once(text, PREPARE.ADMISSION, PREPARE.LEGACY_ADMISSION)
    text = PREPARE.once(text, PREPARE.GENERIC_CHECK, "")
    text = PREPARE.once(
        text,
        "  REGISTERED_SCHEDULING=$registered DISTRIBUTED_FAST_FAULT=$distributed \\\n  PRIVATE_NEXT_START_SCRATCH=$scratch] [get_filesets sources_1]\n",
        "  REGISTERED_SCHEDULING=$registered] [get_filesets sources_1]\n",
    )
    text = PREPARE.once(
        text,
        'puts $channel "distributed_fast_fault=$distributed; private_next_start_scratch=$scratch"\n',
        "",
    )
    text = PREPARE.once(
        text, 'puts $channel "effective_top_generics=$physical_generics"\n', ""
    )
    assert text.count(PREPARE.COPY_VERIFY) == 2
    text = text.replace(PREPARE.COPY_VERIFY, "")
    assert text == original
    for name in ("route_completed_input_fence.tcl",):
        assert (prepared / name).read_bytes() == (ACQ / name).read_bytes()
    source = prepared / "frozen_sources"
    assert {p.name for p in source.iterdir()} == set(PREPARE.SOURCE_NAMES)
    for name in PREPARE.RTL + (
        "create_shared_realtime_xfft_ip.tcl",
        "upper_edge_pss_kernel_q17.mem",
    ):
        assert (source / name).read_bytes() == (
            ACTUAL / "frozen_sources" / name
        ).read_bytes()
    for name in (
        "fft_bank_owned_resource_probe.xdc",
        "fft_bank_owned_synth_threads.tcl",
    ):
        assert (source / name).read_bytes() == (ACQ / name).read_bytes()
    with pytest.raises(FileExistsError):
        PREPARE.prepare(ACTUAL, prepared)


@pytest.mark.parametrize("mutation", [None, "distributed", "scratch", "registered"])
def test_tcl_exact_generic_binding_and_omission_witnesses(prepared, tmp_path, mutation):
    text = (prepared / "synthesize_exact_control_prepared.tcl").read_text()
    fragment = text[
        text.index("set_property generic ") : text.index(
            "set_property STEPS.SYNTH_DESIGN"
        )
    ]
    if mutation == "distributed":
        fragment = fragment.replace("DISTRIBUTED_FAST_FAULT=$distributed ", "")
    elif mutation == "scratch":
        fragment = fragment.replace("PRIVATE_NEXT_START_SCRATCH=$scratch", "")
    elif mutation == "registered":
        fragment = fragment.replace(
            "REGISTERED_SCHEDULING=$registered", "REGISTERED_SCHEDULING=0"
        )
    mock = """
set registered 1; set distributed 1; set scratch 1; set source_dir /offline
proc get_filesets {args} {return sources_1}
proc set_property {name value object} {
  if {$name ne "generic" || $object ne "sources_1"} {error "unexpected property"}
  set ::bound $value
}
proc get_property {name object} {
  if {$name ne "GENERIC" || $object ne "sources_1"} {error "unexpected property"}
  return $::bound
}
"""
    result = subprocess.run(
        ["tclsh"],
        input=mock + fragment + '\nputs "OFFLINE_BOUND=$bound"\n',
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )
    log = result.stdout + result.stderr
    (tmp_path / "generic-fragment.log").write_text(log)
    if mutation:
        assert (
            "missing physical parameter "
            + {
                "distributed": "DISTRIBUTED_FAST_FAULT",
                "scratch": "PRIVATE_NEXT_START_SCRATCH",
                "registered": "REGISTERED_SCHEDULING",
            }[mutation]
            in log
        )
    else:
        assert (
            "OFFLINE_BOUND=KERNEL_ROM_FILE=/offline/upper_edge_pss_kernel_q17.mem REGISTERED_SCHEDULING=1 DISTRIBUTED_FAST_FAULT=1 PRIVATE_NEXT_START_SCRATCH=1"
            in log
        )


@pytest.mark.parametrize("mode", ["trap", "wrong_inventory", "overwrite"])
def test_tcl_preflight_stops_before_any_project_or_synthesis(prepared, tmp_path, mode):
    output = tmp_path / "NEVER_A_VIVADO_PROJECT"
    if mode == "overwrite":
        output.mkdir()
        (output / "sentinel").write_text("unchanged")
    expected = (
        "0" * 64 if mode == "wrong_inventory" else PREPARE.sha(prepared / "SHA256SUMS")
    )
    program = f"""
proc version {{args}} {{return 2022.2}}
proc set_param {{args}} {{}}
proc create_project {{args}} {{error "OFFLINE_STOP_BEFORE_CREATE_PROJECT"}}
set argc 3
set argv [list {{{output}}} {{{prepared}}} {expected}]
if {{[catch {{source {{{prepared / "synthesize_exact_control_prepared.tcl"}}}}} reason]}} {{
  puts $reason; exit 1
}}
error "preflight unexpectedly escaped"
"""
    result = subprocess.run(
        ["tclsh"],
        input=program,
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )
    log = result.stdout + result.stderr
    (tmp_path / "preflight.log").write_text(log)
    assert result.returncode == 1
    marker = {
        "trap": "OFFLINE_STOP_BEFORE_CREATE_PROJECT",
        "wrong_inventory": "unexpected exact-control physical preparation",
        "overwrite": "refusing to overwrite synthesis evidence",
    }[mode]
    assert marker in log, log
    if mode == "trap":
        assert not (output / "project").exists()
        assert {p.name for p in (output / "frozen_sources").glob("*.v")} == set(
            PREPARE.RTL
        )
    elif mode == "wrong_inventory":
        assert not output.exists()
    else:
        assert (output / "sentinel").read_text() == "unchanged"


@pytest.mark.parametrize(
    "mutation", ["missing_rtl", "extra_rtl", "rtl_changed", "constraint_changed"]
)
def test_copied_source_closure_rejects_missing_extra_and_changed_inputs(
    prepared, tmp_path, mutation
):
    copied = tmp_path / "copied"
    shutil.copytree(prepared / "frozen_sources", copied)
    if mutation == "missing_rtl":
        (copied / PREPARE.RTL[0]).unlink()
    elif mutation == "extra_rtl":
        (copied / "not_authorized.v").write_text("module not_authorized; endmodule\n")
    elif mutation == "rtl_changed":
        (copied / PREPARE.RTL[0]).write_text("// changed copy only\n")
    else:
        (copied / "fft_bank_owned_resource_probe.xdc").write_text(
            "# changed copy only\n"
        )
    with pytest.raises(
        ValueError, match="closure differs|copied synthesis source differs"
    ):
        PREPARE.verify_prepared(prepared, copied)


@pytest.mark.parametrize(
    "mutation",
    [
        "baseline",
        "settings",
        "exit",
        "snapshot",
        "fatal",
        "terminal",
        "extra",
        "original_marker",
        "status_accounting",
    ],
)
def test_actual_admission_rejects_wrong_failed_and_incomplete_evidence(
    tmp_path, mutation
):
    if mutation == "baseline":
        with pytest.raises(ValueError, match="exact passing combined"):
            PREPARE.prepare(
                Path("/tmp/starlink-completed-input.5EaJuD/extra-edge-prepared-v1"),
                tmp_path / "absent",
            )
        assert not (tmp_path / "absent").exists()
        return
    actual = tmp_path / "actual"
    actual.mkdir()
    # Read-only links avoid duplicating immutable source/golden data. ONLY the
    # selected mutation file is copied before writing; never write a symlink.
    relative = {
        "settings": "settings.tcl",
        "exit": "actual-time.txt",
        "snapshot": "actual-after-source-verification.log",
        "fatal": "project/exact_control_actual.sim/sim_1/behav/xsim/simulate.log",
        "terminal": "project/exact_control_actual.sim/sim_1/behav/xsim/simulate.log",
        "extra": "project/exact_control_actual.sim/sim_1/behav/xsim/simulate.log",
        "original_marker": "project/exact_control_actual.sim/sim_1/behav/xsim/simulate.log",
        "status_accounting": "project/exact_control_actual.sim/sim_1/behav/xsim/simulate.log",
    }[mutation]
    required = [
        "SHA256SUMS",
        "preparation.json",
        "settings.tcl",
        "frozen_sources",
        "original-SHA256SUMS",
        "strict-diagnostic-SHA256SUMS",
        "qualified-baseline-SHA256SUMS",
        "combined-origin-SHA256SUMS",
        "actual-before-source-verification.log",
        "actual-after-source-verification.log",
        "actual-time.txt",
        "actual-launch.log",
    ]
    sim = "project/exact_control_actual.sim/sim_1/behav/xsim/"
    required += [
        sim + name
        for name in (
            "simulate.log",
            "fft_bank_owned_trace.csv",
            "exact_control_reference_trace.csv",
            "exact_control_extra_trace.csv",
            "exact_control_reference_extra_trace.csv",
        )
    ]
    for name in required:
        target = actual / name
        target.parent.mkdir(parents=True, exist_ok=True)
        if name == relative:
            shutil.copyfile(ACTUAL / name, target)
        else:
            target.symlink_to(
                ACTUAL / name, target_is_directory=name == "frozen_sources"
            )
    target = actual / relative
    assert not target.is_symlink()
    text = target.read_text()
    if mutation == "settings":
        text = text.replace("DISTRIBUTED_FAST_FAULT=1", "DISTRIBUTED_FAST_FAULT=0")
    elif mutation == "exit":
        text = text.replace("Exit status: 0", "Exit status: 1")
    elif mutation == "snapshot":
        text = ""
    elif mutation == "fatal":
        text += "\nFatal: retained synthetic failure witness\n"
    elif mutation == "terminal":
        text = re.sub(r"^EXACT_CONTROL_ACTUAL_PASS.*\n", "", text, flags=re.MULTILINE)
    elif mutation == "extra":
        text = text.replace(
            "EXACT_CONTROL_EXTRA_EPOCHS_PASS final_faults=2",
            "EXACT_CONTROL_EXTRA_EPOCHS_PASS final_faults=1",
        )
    elif mutation == "original_marker":
        text = text.replace("REGISTERED_SCHEDULING_PASS", "REMOVED_REGISTERED_MARKER")
    else:
        text = text.replace(
            "raw_equal=953795 invalid_only=292463",
            "raw_equal=953794 invalid_only=292463",
        )
    target.write_text(text)
    with pytest.raises((ValueError, subprocess.CalledProcessError)):
        PREPARE.prepare(actual, tmp_path / "must_remain_absent")
    assert not (tmp_path / "must_remain_absent").exists()
    # Current source file remains the exact passing actual artifact.
    assert PREPARE.sha(ACTUAL / "SHA256SUMS") == PREPARE.ACTUAL_INVENTORY
