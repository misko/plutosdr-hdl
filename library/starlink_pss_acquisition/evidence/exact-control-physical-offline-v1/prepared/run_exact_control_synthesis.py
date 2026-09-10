"""One-shot external synthesis owner; execution requires separate authorization.

This wrapper is prepared/tested offline. It never retries and does not route.
Both audit attempts and copied-source hashes survive a nonzero tool exit.
"""

import argparse
import hashlib
import json
import os
import re
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

PYTHON = "/home/mouse9911/gits/pluto-plus-utils/.venv/bin/python"
VIVADO = "/opt/Xilinx/Vivado/2022.2/bin/vivado"
VIVADO_LIBRARY = "/opt/Xilinx/Vivado/2022.2/lib/lnx64.o/SuSE"
MARKER = "FFT_BANK_OWNED_THREE_BANK_SYNTHESIS_RESOURCES_RECORDED"
PRODUCTS = (
    "fft_bank_owned_synth.dcp",
    "resource_receipt.txt",
    "scope.txt",
    "utilization.rpt",
    "hierarchy.rpt",
    "synthesis_clocks.rpt",
    "check_timing_unqualified.rpt",
    "cdc_unqualified.rpt",
)


def digest(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def audit(prepared, expected, run, phase):
    copied = run / "synthesis/frozen_sources"
    inventory = {
        "prepared_inventory_sha256": digest(prepared / "SHA256SUMS"),
        "copied_present": copied.exists(),
        "copied_sha256": {
            p.name: digest(p) for p in sorted(copied.glob("*")) if p.is_file()
        },
    }
    (run / f"{phase}-inventory.json").write_text(json.dumps(inventory, indent=2) + "\n")
    with (run / f"{phase}-integrity.log").open("x") as log:
        if inventory["prepared_inventory_sha256"] != expected:
            log.write("prepared inventory differs from reviewed SHA\n")
            return 1
        checked = subprocess.run(
            ["sha256sum", "-c", "SHA256SUMS"],
            cwd=prepared,
            stdout=log,
            stderr=subprocess.STDOUT,
            check=False,
        )
        if checked.returncode:
            return checked.returncode
        command = [
            PYTHON,
            "-B",
            str(prepared / "prepare_exact_control_physical.py"),
            "--verify",
            str(prepared),
            "--expected",
            expected,
        ]
        if copied.exists():
            command += ["--copied", str(copied)]
        clean = os.environ.copy()
        for name in ("PYTHONHOME", "PYTHONPATH", "LD_LIBRARY_PATH"):
            clean.pop(name, None)
        return subprocess.run(
            command,
            env=clean,
            stdout=log,
            stderr=subprocess.STDOUT,
            check=False,
        ).returncode


def launch_vivado(command, run):
    environment = os.environ.copy()
    environment["LD_LIBRARY_PATH"] = VIVADO_LIBRARY
    with (run / "launch.log").open("x") as log:
        return subprocess.run(
            command,
            cwd=run,
            env=environment,
            stdout=log,
            stderr=subprocess.STDOUT,
            check=False,
        ).returncode


def completion(run):
    errors, products = [], {}
    log = (run / "launch.log").read_text() if (run / "launch.log").is_file() else ""
    if log.splitlines().count(MARKER) != 1:
        errors.append("requires exactly one original terminal synthesis marker")
    if re.search(r"^(?:ERROR|FATAL):", log, re.MULTILINE):
        errors.append("tool reported ERROR/FATAL")
    source = run / "synthesis"
    if not (source / "frozen_sources").is_dir():
        errors.append("missing copied-source closure")
    for name in PRODUCTS:
        path = source / name
        if not path.is_file() or not path.stat().st_size:
            errors.append("missing or empty synthesis product: " + name)
        else:
            products[name] = {"bytes": path.stat().st_size, "sha256": digest(path)}
    receipt = source / "resource_receipt.txt"
    if receipt.is_file() and re.findall(
        r"^black_boxes=(.*)$", receipt.read_text(), re.MULTILINE
    ) != ["0"]:
        errors.append("requires exact zero-black-box receipt")
    return {"verified": not errors, "errors": errors, "products": products}


def execute(prepared, expected, run):
    prepared, run = prepared.resolve(), run.resolve()
    run.mkdir()  # Exclusive owner directory; never overwrite or restart.
    command = [
        VIVADO,
        "-mode",
        "batch",
        "-source",
        str(prepared / "synthesize_exact_control_prepared.tcl"),
        "-log",
        str(run / "vivado.log"),
        "-journal",
        str(run / "vivado.jou"),
        "-tclargs",
        str(run / "synthesis"),
        str(prepared),
        expected,
    ]
    receipt = {
        "command": command,
        "prepared": str(prepared),
        "expected_sha256": expected,
        "started_utc": datetime.now(timezone.utc).isoformat(),
        "before_audit": None,
        "tool_returncode": None,
        "completion": {"verified": False, "errors": ["tool not launched"]},
        "after_audit": None,
        "scope": "one_OOC_synthesis_only_NO_route_or_promotion",
    }
    (run / "invocation.json").write_text(json.dumps(receipt, indent=2) + "\n")
    start = time.monotonic()
    result = 1
    try:
        receipt["before_audit"] = audit(prepared, expected, run, "before")
        if receipt["before_audit"] == 0:
            receipt["tool_returncode"] = launch_vivado(command, run)
            result = receipt["tool_returncode"]
            receipt["completion"] = completion(run)
            if result == 0 and not receipt["completion"]["verified"]:
                result = 1
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        receipt["execution_exception"] = repr(error)
        result = 127
    finally:
        try:
            receipt["after_audit"] = audit(prepared, expected, run, "after")
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            receipt["after_audit_exception"] = repr(error)
            receipt["after_audit"] = 127
        if receipt["tool_returncode"] != 0 or receipt["after_audit"] != 0:
            receipt["completion"]["verified"] = False
            receipt["completion"]["errors"].append(
                "process or after-integrity audit failed"
            )
        if result == 0 and receipt["after_audit"] != 0:
            result = 1
        receipt["returncode"] = result
        receipt["wall_seconds"] = time.monotonic() - start
        receipt["ended_utc"] = datetime.now(timezone.utc).isoformat()
        (run / "terminal.json").write_text(json.dumps(receipt, indent=2) + "\n")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--execute-synthesis", action="store_true", required=True)
    parser.add_argument("--prepared", type=Path, required=True)
    parser.add_argument("--expected", required=True)
    parser.add_argument("--new-run", type=Path, required=True)
    args = parser.parse_args()
    raise SystemExit(execute(args.prepared, args.expected, args.new_run))


if __name__ == "__main__":
    main()
