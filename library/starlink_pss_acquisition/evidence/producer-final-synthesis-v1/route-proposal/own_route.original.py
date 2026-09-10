"""Own one authorized diagnostic route; never retry or alter its inputs."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import time
from datetime import datetime, timezone


OWNER = Path(__file__).absolute().parent
BUILD = Path("/home/mouse9911/gits/starlink-build-recovery-20260910.vHzUVnBz")
DCP = BUILD / "rom-k1m1-synth-v1/synthesis/fft_bank_owned_synth.dcp"
TCL = BUILD / "rom-k1m1-physical-prepared-v1/route_completed_input_fence.tcl"
EXPECTED = {
    str(DCP): "264b7dbb89ccef59b1b41dbaee2e01d4138b8d9a368f64ebc6532efd04f5405e",
    str(TCL): "0873675fcec384f676a80b75b746460fbff2ecc3ee162f6111705ead2fad6d4a",
}
ROUTE = OWNER / "route"
TEMP = OWNER / "tmp"
COMMAND = [
    "/opt/Xilinx/Vivado/2022.2/bin/vivado", "-mode", "batch", "-source", str(TCL),
    "-log", str(OWNER / "vivado.log"), "-journal", str(OWNER / "vivado.jou"),
    "-tclargs", str(DCP), EXPECTED[str(DCP)], str(ROUTE),
]
MARKER = "COMPLETED_INPUT_DIAGNOSTIC_RECORDED_NOT_A_PHYSICAL_RELEASE_PASS"


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def write(name, value):
    with (OWNER / name).open("x") as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write("\n")


def utc():
    return datetime.now(timezone.utc).isoformat()


def main():
    for name in ("route", "tmp", "before.json", "terminal.json", "outer.log", "vivado.log", "vivado.jou"):
        if (OWNER / name).exists() or (OWNER / name).is_symlink():
            raise SystemExit(f"refusing existing evidence: {name}")
    before = {name: sha(name) for name in EXPECTED}
    if before != EXPECTED:
        raise SystemExit("authorized source hash mismatch")
    TEMP.mkdir()
    env = dict(os.environ)
    for name in ("PYTHONHOME", "PYTHONPATH"):
        env.pop(name, None)
    env["LD_LIBRARY_PATH"] = "/opt/Xilinx/Vivado/2022.2/lib/lnx64.o/SuSE"
    env["TMPDIR"] = str(TEMP)
    started = utc()
    tick = time.monotonic()
    write("before.json", {
        "started_utc": started, "command": COMMAND, "cwd": str(OWNER),
        "source_hashes": before, "owner_sha256": sha(__file__),
        "environment": {name: env.get(name) for name in ("LD_LIBRARY_PATH", "TMPDIR", "PYTHONHOME", "PYTHONPATH")},
        "scope": "one isolated diagnostic route; no physical release qualification",
    })
    code = None
    pid = None
    errors = []
    try:
        with (OWNER / "outer.log").open("x") as stream:
            child = subprocess.Popen(COMMAND, cwd=OWNER, env=env, stdout=stream, stderr=subprocess.STDOUT)
            pid = child.pid
            print(json.dumps({"pid": pid, "started_utc": started, "owner": str(OWNER), "command": COMMAND}), flush=True)
            code = child.wait()
    except Exception as error:
        errors.append(f"launch/wait: {type(error).__name__}: {error}")
    after = {}
    for name, expected in EXPECTED.items():
        try:
            after[name] = sha(name)
            if after[name] != expected:
                errors.append(f"changed source: {name}")
        except Exception as error:
            errors.append(f"after integrity: {name}: {error}")
    raw = (OWNER / "outer.log").read_text(errors="replace") if (OWNER / "outer.log").exists() else ""
    marker_count = sum(line.strip() == MARKER for line in raw.splitlines())
    if code != 0:
        errors.append(f"original tool exit: {code}")
    if marker_count != 1:
        errors.append(f"completion marker count: {marker_count}")
    products = {
        str(path.relative_to(OWNER)): {"bytes": path.stat().st_size, "sha256": sha(path)}
        for path in sorted(ROUTE.rglob("*")) if path.is_file()
    } if ROUTE.exists() else {}
    result = {
        "started_utc": started, "ended_utc": utc(), "elapsed_seconds": time.monotonic() - tick,
        "original_pid": pid, "tool_returncode": code, "marker_count": marker_count,
        "source_hashes_before": before, "source_hashes_after": after,
        "products": products, "errors": errors, "deployment_eligible": False,
    }
    write("terminal.json", result)
    print(json.dumps(result, sort_keys=True), flush=True)
    return 0 if not errors else 1


if __name__ == "__main__":
    raise SystemExit(main())
