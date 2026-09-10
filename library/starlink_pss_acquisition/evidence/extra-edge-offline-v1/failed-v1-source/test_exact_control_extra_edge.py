"""Offline added-stimulus scheduling only; original runtime/checkers stay exact."""

import importlib.util
import json
import subprocess
from pathlib import Path

import pytest

from tests.starlink_oracle.test_exact_control import STUB

ACQ = Path(__file__).resolve().parents[2] / "hdl/library/starlink_pss_acquisition"
SPEC = importlib.util.spec_from_file_location(
    "extra_edge", ACQ / "prepare_exact_control_extra_edge.py"
)
EDGE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(EDGE)
ORIGINAL = ACQ / "evidence/status-qualified-observer-offline-v1/prepared"
TOP = "tb_starlink_pss_fft_bank_owned_slice"


def test_only_added_negedge_boundary_check_inverse_and_full_pair_compile(tmp_path):
    prepared = tmp_path / "prepared"
    EDGE.prepare(ORIGINAL, prepared)
    source = prepared / "frozen_sources"
    subprocess.run(
        ["sha256sum", "-c", "SHA256SUMS", "--quiet"], cwd=prepared, check=True
    )
    for name in json.loads((ORIGINAL / "preparation.json").read_text())[
        "source_sha256"
    ]:
        text = (source / name).read_text()
        if name == EDGE.EXTRA:
            assert text.count(EDGE.CORRECTION) == 1
            text = text.replace(EDGE.CORRECTION, "", 1)
        assert text.encode() == (ORIGINAL / "frozen_sources" / name).read_bytes(), name
    assert (prepared / "settings.tcl").read_bytes() == (
        ORIGINAL / "settings.tcl"
    ).read_bytes()
    # The full paired candidate/reference bench compiles; it is never run
    # against this quiescent stub, which would not prove numerical behavior.
    stub = tmp_path / "never_run_stub.v"
    stub.write_text(STUB)
    result = subprocess.run(
        [
            "iverilog",
            "-g2012",
            "-Wall",
            "-I",
            str(source),
            "-s",
            TOP,
            f"-P{TOP}.FAST_MHZ=175",
            f"-P{TOP}.EXACT_EXTRA_EPOCHS=1",
            "-o",
            str(tmp_path / "full_pair_never_run.vvp"),
            *map(str, sorted(source.glob("*.v"))),
            *map(str, sorted(source.glob("*.sv"))),
            str(stub),
        ],
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )
    (tmp_path / "full_pair_compile.log").write_text(result.stdout + result.stderr)
    assert result.returncode == 0, result.stdout + result.stderr
    with pytest.raises(FileExistsError):
        EDGE.prepare(ORIGINAL, prepared)


def fault_body():
    text = EDGE.align((ORIGINAL / "frozen_sources" / EDGE.EXTRA).read_text())
    # Execute literal prepared wait/hold/fault/current-veto/sticky/ownership
    # body for kinds0/1 only. Reset kinds2/3 remain literal via full inverse.
    start = text.index("    wait(!dut.next_inverse")
    end = text.index("    reset_epoch(0); send_words(0, 512); await_results(1);")
    return text[start:end]


def run(tmp_path, kind, mode, mutation=None):
    body = fault_body()
    if mutation == "remove_negedge":
        assert body.count(EDGE.CORRECTION) == 1
        body = body.replace(
            EDGE.CORRECTION,
            EDGE.CORRECTION.replace("      @(negedge fft_clk);\n", ""),
            1,
        )
    elif mutation in {"two_held", "four_held"}:
        assert body.count("repeat (3) tick();") == 1
        body = body.replace(
            "repeat (3) tick();",
            f"repeat ({2 if mutation == 'two_held' else 4}) tick();",
        )
    elif mutation == "late_posedge":
        body = body.replace(
            EDGE.CORRECTION,
            EDGE.CORRECTION.replace("@(negedge fft_clk);", "@(posedge fft_clk);"),
            1,
        )
    elif mutation == "bad_owner":
        body = body.replace(
            EDGE.CORRECTION,
            EDGE.CORRECTION.replace(
                "@(negedge fft_clk);",
                "@(negedge fft_clk); force dut.product_bank_valid=1;",
            ),
            1,
        )
    bench = (ACQ / "tb/tb_starlink_pss_extra_edge.sv").read_text()
    assert bench.count("// INSERT_EXACT_EXTRA_FAULT_BODY") == 1
    bench = bench.replace("// INSERT_EXACT_EXTRA_FAULT_BODY", body, 1)
    source = tmp_path / "fixture.sv"
    source.write_text(bench)
    executable = tmp_path / "fixture.vvp"
    result = subprocess.run(
        [
            "iverilog",
            "-g2012",
            "-Wall",
            "-s",
            TOP,
            f"-P{TOP}.KIND={kind}",
            f"-P{TOP}.MODE={mode}",
            "-o",
            str(executable),
            str(source),
            str(ACQ / "starlink_pss_realtime_result_guard.v"),
            str(
                ORIGINAL
                / "frozen_sources/starlink_pss_realtime_result_guard_ce6a885e_golden.v"
            ),
        ],
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )
    (tmp_path / "compile.log").write_text(result.stdout + result.stderr)
    assert result.returncode == 0, result.stdout + result.stderr
    result = subprocess.run(
        ["vvp", str(executable)],
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )
    log = result.stdout + result.stderr
    (tmp_path / "simulate.log").write_text(log)
    return result.returncode, log


@pytest.mark.parametrize("kind,mode", [(0, 0), (0, 1), (1, 0), (1, 1)])
def test_literal_fault_body_real_guard_three_held_edges_and_precommit_lead(
    tmp_path, kind, mode
):
    rc, log = run(tmp_path, kind, mode)
    assert rc == 0, log
    assert (
        f"EXTRA_EDGE_GUARD_PASS kind={kind} mode={mode} held_posedges={3 if kind else 0} fault_edges=1 lead_ns=2.857143 exact_reasons=01"
        in log
    )
    assert "synthetic_core_minimal_banks_not_fft=1" in log


@pytest.mark.parametrize(
    "kind,mutation,marker",
    [
        (0, "remove_negedge", "EDGE_FAULT_DRIVE_NOT_NEGEDGE"),
        (1, "remove_negedge", "EDGE_FAULT_DRIVE_NOT_NEGEDGE"),
        (1, "two_held", "EDGE_HELD_COUNT_WRONG"),
        (1, "four_held", "EDGE_HELD_COUNT_WRONG"),
        (0, "late_posedge", "EDGE_FAULT_DRIVE_NOT_NEGEDGE"),
        (1, "bad_owner", "EXACT_EXTRA_ALIGNED_FINAL_BOUNDARY_MISSING"),
    ],
)
def test_edge_count_late_fault_and_ownership_mutants_rejected(
    tmp_path, kind, mutation, marker
):
    rc, log = run(tmp_path, kind, 1, mutation)
    assert rc != 0 and marker in log, log
    assert "EXTRA_EDGE_GUARD_PASS" not in log


def test_wrong_freeze_rejected_without_actual_launch(tmp_path):
    wrong = tmp_path / "wrong"
    wrong.mkdir()
    (wrong / "SHA256SUMS").write_text("wrong\n")
    with pytest.raises(ValueError, match="reviewed qualified"):
        EDGE.prepare(wrong, tmp_path / "absent")
    assert not (tmp_path / "absent").exists()
    helper = (ACQ / "prepare_exact_control_extra_edge.py").read_text()
    assert "launch_simulation" not in helper and '"vivado"' not in helper
