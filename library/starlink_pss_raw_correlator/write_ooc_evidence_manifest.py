#!/usr/bin/env python3
"""Bind one successful OOC run to its exact sources and generated evidence."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent
SOURCE_FILES = (
    "starlink_sat_add48.v",
    "starlink_pss_raw_correlator.v",
    "starlink_pss_raw_correlator_ooc.xdc",
    "synthesize_ooc.tcl",
    "run_ooc.sh",
    "write_ooc_evidence_manifest.py",
)
OUTPUT_FILES = (
    "starlink_pss_raw_correlator_check_timing.rpt",
    "starlink_pss_raw_correlator_methodology_synth.rpt",
    "starlink_pss_raw_correlator_ooc_summary.txt",
    "starlink_pss_raw_correlator_synth.dcp",
    "starlink_pss_raw_correlator_timing_synth.rpt",
    "starlink_pss_raw_correlator_utilization_synth.rpt",
)
REQUIRED_SUMMARY = {
    "vivado_version": "2022.2",
    "part": "xc7z010clg400-1",
    "clock_period_ns": "10.000",
    "timing_scope": "post_synthesis_max_delay_only",
    "hold_analysis": "not_available_post_synthesis",
    "methodology_violations": "0",
    "check_timing_nonzero_categories": "0",
    "dsp48e1": "3",
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def file_attestation(path: Path) -> dict[str, int | str]:
    if not path.is_file():
        raise RuntimeError(f"missing evidence input: {path}")
    return {"sha256": sha256(path), "size_bytes": path.stat().st_size}


def git_output(repository: Path, *arguments: str) -> str:
    completed = subprocess.run(
        ("git", "-C", str(repository), *arguments),
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    )
    return completed.stdout.strip()


def load_summary(path: Path) -> dict[str, str]:
    summary: dict[str, str] = {}
    for line in path.read_text().splitlines():
        if not line or "=" not in line:
            raise RuntimeError(f"malformed OOC summary line: {line!r}")
        key, value = line.split("=", 1)
        if key in summary:
            raise RuntimeError(f"duplicate OOC summary key: {key}")
        summary[key] = value
    for key, expected in REQUIRED_SUMMARY.items():
        actual = summary.get(key)
        if actual != expected:
            raise RuntimeError(
                f"OOC summary {key} must be {expected!r}, got {actual!r}"
            )
    if float(summary["setup_wns_ns"]) < 0.0:
        raise RuntimeError("negative setup WNS cannot be attested")
    return summary


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--transcript", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    args = parser.parse_args()

    output_dir = args.output_dir.resolve()
    transcript = args.transcript.resolve()
    manifest = args.manifest.resolve()
    summary_path = output_dir / "starlink_pss_raw_correlator_ooc_summary.txt"
    summary = load_summary(summary_path)

    transcript_text = transcript.read_text(errors="replace")
    if "STARLINK_RAW_OOC_PASS" not in transcript_text:
        raise RuntimeError("retained Vivado transcript lacks the OOC pass marker")

    hdl_repository = Path(git_output(ROOT, "rev-parse", "--show-toplevel"))
    parent_text = git_output(hdl_repository, "rev-parse", "--show-superproject-working-tree")
    parent_repository = Path(parent_text) if parent_text else None
    source_root = ROOT.relative_to(hdl_repository)
    source_status_paths = tuple(
        (source_root / name).as_posix() for name in SOURCE_FILES
    )
    attested_source_status = git_output(
        hdl_repository,
        "status",
        "--porcelain=v1",
        "--untracked-files=all",
        "--",
        *source_status_paths,
    )

    payload = {
        "schema": "starlink-pss-raw-correlator-ooc-evidence-v1",
        "generated_utc": dt.datetime.now(dt.UTC).isoformat(),
        "claim": "post-synthesis maximum-delay OOC evidence only; hold is unavailable",
        "source_control": {
            "hdl_commit": git_output(hdl_repository, "rev-parse", "HEAD"),
            # Deliberately scope cleanliness to exactly the files hashed below.
            # Generated evidence is committed separately and must not make an
            # otherwise clean source qualification look dirty.
            "attested_source_paths": list(source_status_paths),
            "attested_source_status": attested_source_status,
            "attested_sources_clean": not bool(attested_source_status),
            "parent_commit": (
                git_output(parent_repository, "rev-parse", "HEAD")
                if parent_repository is not None
                else None
            ),
        },
        "source_files": {
            name: file_attestation(ROOT / name) for name in SOURCE_FILES
        },
        "summary": summary,
        "evidence_files": {
            name: file_attestation(output_dir / name) for name in OUTPUT_FILES
        }
        | {transcript.name: file_attestation(transcript)},
    }

    manifest.parent.mkdir(parents=True, exist_ok=True)
    manifest.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n")
    print(
        "OOC_EVIDENCE_MANIFEST_PASS "
        f"path={manifest} sha256={sha256(manifest)} "
        f"sources={len(payload['source_files'])} "
        f"evidence={len(payload['evidence_files'])}"
    )


if __name__ == "__main__":
    main()
