"""Offline settings-only combined freeze; never execute the actual-core runner."""

import argparse
import hashlib
import json
import shutil
import subprocess
from pathlib import Path

BASE_INVENTORY = "8efa2657fd43d4c7d2804d90abf9aa169fb8d916136ee681d38d4b533885ad92"
SETTINGS = {
    "REGISTERED_SCHEDULING": 1,
    "DISTRIBUTED_FAST_FAULT": 1,
    "PRIVATE_NEXT_START_SCRATCH": 1,
    "EXACT_EXTRA_EPOCHS": 1,
    "FAST_MHZ": 175,
    "QUICK_MUTATION": 0,
}


def prepare(original, output):
    if output.exists():
        raise FileExistsError("refusing to overwrite combined evidence")
    inventory = (original / "SHA256SUMS").read_bytes()
    if hashlib.sha256(inventory).hexdigest() != BASE_INVENTORY:
        raise ValueError("not the passing phase-aligned baseline freeze")
    subprocess.run(
        ["sha256sum", "-c", "SHA256SUMS", "--quiet"],
        cwd=original,
        check=True,
        timeout=10,
    )
    metadata = json.loads((original / "preparation.json").read_text())
    source = output / "frozen_sources"
    source.mkdir(parents=True)
    # Existing helpers, observers, stimuli, vectors and all RTL remain exact.
    # This settings-copy helper is provenance, not a new simulation source.
    for name in metadata["source_sha256"]:
        shutil.copyfile(original / "frozen_sources" / name, source / name)
    lineage = (
        "original-SHA256SUMS",
        "strict-diagnostic-SHA256SUMS",
        "qualified-baseline-SHA256SUMS",
    )
    for name in lineage:
        shutil.copyfile(original / name, output / name)
    (output / "combined-origin-SHA256SUMS").write_bytes(inventory)
    (output / "settings.tcl").write_text(
        "set exact_generics {"
        + " ".join(f"{key}={value}" for key, value in SETTINGS.items())
        + "}\n"
    )
    metadata["settings"] = dict(SETTINGS)
    metadata["scope"] = (
        "OFFLINE_ONLY_combined_settings_copy_qualified_status_NOT_raw217_pass"
    )
    metadata["combined_origin_inventory_sha256"] = BASE_INVENTORY
    metadata["combined_origin_path"] = str(original.resolve())
    metadata["combined_preparer_sha256"] = hashlib.sha256(
        Path(__file__).read_bytes()
    ).hexdigest()
    (output / "preparation.json").write_text(json.dumps(metadata, indent=2) + "\n")
    files = sorted(source.iterdir()) + [
        output / name
        for name in (
            *lineage,
            "combined-origin-SHA256SUMS",
            "settings.tcl",
            "preparation.json",
        )
    ]
    (output / "SHA256SUMS").write_text(
        "".join(
            f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.relative_to(output)}\n"
            for path in files
        )
    )
    return metadata["settings"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--original", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(prepare(args.original, args.output)))


if __name__ == "__main__":
    main()
