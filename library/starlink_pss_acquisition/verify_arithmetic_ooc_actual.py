"""Read-only, source-specific admission of reviewed v3 post-hoc evidence.

This does not accept arbitrary failed simulations or rewrite original results.
Only the immutable candidate's diagnostic-marker log-source failure is allowed.
"""

import hashlib
import importlib.util
import json
import re
from pathlib import Path

MANIFEST = "6376f1fb2508f357933d4cb9cd9949d8da452d155a47084701aa29fb99df1954"
RECEIPT = "be23853ba29f36a137b7ceba084bca0395338fbc6448dbd3a59640419cdb9c9c"
ASSESSMENT = "a1e7eebc49fba088327109643d9beb120276eb2f6f230a885d5a9438e048da0f"
QUERY = "e2150fca7a2861fc008d3962271f71c4e64b77b662aa8ebbc640d84eb8bcaf2d"
SIM = Path("project/fft_bank_arithmetic_actual.sim/sim_1/behav/xsim")
OUTER = "bank-arithmetic-actual-candidate175-monitor-v3.outer.log"
EVIDENCE_NAMES = (
    "originals.json",
    "posthoc_assessment.json",
    "read_original_v3_wdb_candidate.outer.log",
)


def sha(path):
    with Path(path).open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def require(condition, message):
    if not condition:
        raise ValueError(message)


def verify_histories(text, diagnostics, assessment):
    """Reconstruct the six qualified 119-bit comparisons from recorded fields."""
    marker = (
        "ACTUAL_WDB_HISTORY_VERIFIED arm=candidate objects=115 times=3 no_advance=1"
    )
    require(text.splitlines().count(marker) == 1, "missing exact WDB history terminal")
    values = {}
    for line in text.splitlines():
        if not line.startswith("ACTUAL_WDB_VALUE\t"):
            continue
        parts = line.split("\t")
        require(len(parts) == 5, "malformed WDB value")
        _, arm, time, path, value = parts
        require(arm == "candidate" and value not in ("", "<Blank>"), "absent WDB value")
        require((time, path) not in values, "duplicate WDB value")
        values[time, path] = value
    times = sorted({time for time, _ in values})
    require(
        times == ["100000000000fs", "1261765777375fs", "3000000000000fs"],
        "WDB history times differ",
    )
    require(len(values) == 345, "incomplete recorded WDB history")
    comparisons = []
    for time in times:
        paths = {path: value for (t, path), value in values.items() if t == time}
        require(
            set(paths) == set(diagnostics["recorded_internal_signals"]),
            "WDB recorded path closure differs",
        )
        for path, value in paths.items():
            if not path.endswith("reference /product_outputs"):
                continue
            prefix = path.rsplit("/", 1)[0]

            def number(name, paths=paths, prefix=prefix):
                return int(paths[prefix + "/" + name], 16)

            require(
                number("resetn") == 1 and number("flush") == 0,
                "required WDB comparison not qualified",
            )
            expected = number("available")
            for name, width in (
                ("p_valid", 1),
                ("p_i", 18),
                ("p_q", 18),
                ("p_position", 9),
                ("p_exponent", 5),
                ("p_last", 1),
                ("p_start", 64),
                ("p_overflow", 1),
                ("p_overflow_pulse", 1),
            ):
                require(0 <= number(name) < 1 << width, "WDB field width differs")
                expected = (expected << width) | number(name)
            require(int(value, 16) == expected, "WDB qualified arithmetic mismatch")
            comparisons.append(
                {
                    "time": time,
                    "path": path,
                    "actual": value,
                    "reference": f"{expected:030x}",
                }
            )
    require(
        len(comparisons) == 6
        and comparisons == assessment["qualified_119bit_comparisons"],
        "post-hoc qualified comparisons differ",
    )
    for suffix, expected in (
        ("/dut/product/output_overflow", "1"),
        ("/dut/product/arithmetic/output_overflow", "0"),
        ("/dut/product_overflow", "1"),
        ("/dut/external_fault_now", "1"),
        ("/dut/product_commit_authorized", "0"),
        ("/dut/forward_handoff_ack", "0"),
    ):
        observed = [
            v
            for (t, p), v in values.items()
            if t == "1261765777375fs" and p.endswith(suffix)
        ]
        require(
            observed == [expected],
            "recorded current-fault transport differs: " + suffix,
        )
    return {
        "recorded_paths": 115,
        "recorded_values": 345,
        "qualified_119bit_comparisons": 6,
    }


def verify(actual, evidence, outer=None):
    actual = Path(actual).resolve()
    paths = (
        evidence
        if isinstance(evidence, dict)
        else {name: Path(evidence).resolve() / name for name in EVIDENCE_NAMES}
    )
    outer = Path(outer).resolve() if outer is not None else actual.parent / OUTER
    for name, expected in zip(
        EVIDENCE_NAMES, (RECEIPT, ASSESSMENT, QUERY), strict=True
    ):
        require(
            sha(paths[name]) == expected,
            "reviewed post-hoc evidence identity differs: " + name,
        )
    original = json.loads(paths["originals.json"].read_text())
    full_assessment = json.loads(paths["posthoc_assessment.json"].read_text())
    run = next(row for row in original["runs"] if row["arm"] == "candidate")
    assessment = next(
        row for row in full_assessment["runs"] if row["arm"] == "candidate"
    )
    require(
        sha(actual / "manifest.json") == MANIFEST == run["manifest_sha256"],
        "requires exact R1/B1/O1 candidate175 manifest",
    )
    require(
        not (actual / "results.json").exists(),
        "original automation must remain FAIL with no results.json",
    )
    # Byte identity of every archived candidate artifact includes the exact
    # original traceback (not just an error substring), phase/IP receipts and WDB.
    identities = original["archive_file_sha256"]
    for relative, expected in identities.items():
        if relative.startswith("candidate/"):
            local = relative.removeprefix("candidate/")
            target = (
                outer.parent / local.removeprefix("outer/")
                if local.startswith("outer/")
                else actual / local
            )
            require(
                sha(target) == expected,
                "original candidate artifact changed: " + relative,
            )
    require(
        sha(outer)
        == run["outer_log_sha256"]
        == assessment["diagnostic_outer_log_sha256"],
        "original diagnostic log provenance differs",
    )
    frozen = actual / "frozen_sources"
    spec = importlib.util.spec_from_file_location(
        "immutable_arithmetic_v3", frozen / "bank_arithmetic_actual.py"
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    manifest = module.verify_freeze(actual)
    require(
        manifest["source_sha256"] == run["frozen_source_sha256"],
        "original source closure differs",
    )
    require(
        (manifest["R"], manifest["B"], manifest["O"], manifest["frequency"])
        == (1, 1, 1, 175),
        "wrong actual parameters",
    )
    for name in ("preflight.json", "postflight.json"):
        require(
            json.loads((actual / name).read_text()) == manifest,
            "actual phase source identity differs",
        )
    outcome = (actual / "run_outcome.txt").read_text()
    require(
        outcome.startswith("run_status=1\n")
        and "\nafter_status=0\n" in outcome
        and "ValueError: missing/duplicate/malformed diagnostic waveform inventory\n"
        in outcome,
        "not the reviewed diagnostic-marker log-source failure",
    )
    require(
        (actual / "launch_started.txt").read_text()
        == "actual_fft=true R=1 B=1 O=1 frequency=175 no_restart=true\n",
        "wrong actual launch binding",
    )
    before = (actual / "generated_ip_before.txt").read_text()
    match = re.fullmatch(r"([0-9a-f]{64})  ([^\n]+)\n", before)
    require(
        match is not None and before == (actual / "generated_ip_after.txt").read_text(),
        "generated FFT before/after mismatch",
    )
    # The original receipt carries its original absolute path. Relocated test
    # mirrors still verify the same relative generated source, never a substitute.
    ip_relative = Path(match[2]).relative_to(Path(run["directory"]))
    require(
        sha(actual / ip_relative) == match[1] == run["generated_ip_pre_post_sha256"],
        "live generated FFT differs",
    )
    sim = actual / SIM
    raw = (sim / "simulate.log").read_text()
    require("$finish called" in raw, "actual HDL did not finish")
    terminals = module.require_terminal(raw, manifest)
    require(
        terminals == assessment["functional_receipts"] and len(terminals) == 11,
        "post-hoc eleven-terminal contract differs",
    )
    events = module.verify_events(sim / "bank_arithmetic_events.csv", frozen)
    require(events == assessment["events"], "post-hoc event contract differs")
    jobs = [
        {k: int(v) for k, v in re.findall(r"(\w+)=(\d+)", line)}
        for line in re.findall(r"^BANK_JOB (.*)$", raw, re.MULTILINE)
    ]
    jobs = [row for row in jobs if row["epoch"] in (1, 2)]
    require(
        len(jobs) == 76
        and all(
            all(row.get(k) == v for k, v in module.CORE_TIMING.items()) for row in jobs
        ),
        "immutable core timing differs",
    )
    inventory = (sim / "arithmetic_diagnostic_signals.txt").read_text()
    # Prove the precise old failure, then use ONLY the identified original outer
    # log. No generic failed-run exception and no original result publication.
    try:
        module.require_wave_diagnostics(raw, inventory)
    except ValueError as error:
        require(
            str(error) == "missing/duplicate/malformed diagnostic waveform inventory",
            "unexpected diagnostic rejection",
        )
    else:
        raise ValueError("original known log-source failure no longer reproduced")
    diagnostics = module.require_wave_diagnostics(outer.read_text(), inventory)
    require(
        outer.read_text().splitlines()[447] == run["diagnostic_marker"],
        "marker location differs",
    )
    histories = verify_histories(
        paths[EVIDENCE_NAMES[2]].read_text(), diagnostics, assessment
    )
    require(
        sha(sim / "tb_starlink_pss_bank_arithmetic_actual_behav.wdb")
        == assessment["waveform_sha256"],
        "actual WDB no longer matches read-only history",
    )
    return {
        "actual_directory": str(actual),
        "outer_log": str(outer),
        "manifest_sha256": MANIFEST,
        "posthoc_sha256": ASSESSMENT,
        "original_receipt_sha256": RECEIPT,
        "source_sha256": manifest["source_sha256"],
        "original_automation_status": "FAIL",
        "accepted_failure": "exact_original_diagnostic_marker_log_source_only",
        "functional_terminals": len(terminals),
        "events": events,
        "core_jobs": len(jobs),
        "histories": histories,
        "generated_ip_sha256": match[1],
        "scorer_RTL_physical_receiver_RF_qualified": False,
    }
