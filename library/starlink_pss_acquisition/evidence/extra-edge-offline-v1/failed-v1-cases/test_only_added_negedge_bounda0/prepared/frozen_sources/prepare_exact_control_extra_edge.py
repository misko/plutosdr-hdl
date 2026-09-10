"""Offline-only edge alignment of added extra-epoch fault stimulus."""

import argparse
import hashlib
import json
import shutil
import subprocess
from pathlib import Path

BASE_INVENTORY = "36e44321ea694ee324f12613a54d0758219a62c7f9edd73b0106a45f6e70dd09"
EXTRA = "starlink_pss_exact_control_extra_epochs.svh"
ANCHOR = "    if (exact_extra_kind < 2) begin\n"
CORRECTION = """      // Added stimulus only: do not drive at tick's posedge+1ps,
      // which is also the unchanged original join-input checker's sample.
      // Kind1 retains all three held posedges; kind0 is still pre-commit.
      @(negedge fft_clk);
      if (!dut.result_guard.active || !dut.result_guard.final_qualified ||
          !dut.return_commit_valid || !dut.result_guard.return_last ||
          dut.joiner.kernel_rom.expected_bin_index != 511 || dut.next_inverse ||
          dut.forward_committed || dut.product_bank_valid || inverse_jobs ||
          dut.forward_handoff_ack ||
          (exact_extra_kind == 0 && !dut.product_bank_ready) ||
          (exact_extra_kind == 1 && dut.product_bank_ready))
        $fatal(1, "EXACT_EXTRA_ALIGNED_FINAL_BOUNDARY_MISSING");
"""


def align(text):
    if text.count(ANCHOR) != 1:
        raise ValueError("nonunique frozen extra fault branch")
    return text.replace(ANCHOR, ANCHOR + CORRECTION, 1)


def prepare(original, output):
    if output.exists():
        raise FileExistsError("refusing to overwrite extra-edge evidence")
    inventory = (original / "SHA256SUMS").read_bytes()
    if hashlib.sha256(inventory).hexdigest() != BASE_INVENTORY:
        raise ValueError("not the reviewed qualified-baseline freeze")
    subprocess.run(
        ["sha256sum", "-c", "SHA256SUMS", "--quiet"],
        cwd=original,
        check=True,
        timeout=10,
    )
    metadata = json.loads((original / "preparation.json").read_text())
    source = output / "frozen_sources"
    source.mkdir(parents=True)
    # Copy the exact inventoried source set, not generated Python cache files.
    for name in metadata["source_sha256"]:
        shutil.copyfile(original / "frozen_sources" / name, source / name)
    extra = source / EXTRA
    extra.write_text(align(extra.read_text()))
    shutil.copyfile(__file__, source / Path(__file__).name)
    for name in ("settings.tcl", "original-SHA256SUMS", "strict-diagnostic-SHA256SUMS"):
        shutil.copyfile(original / name, output / name)
    (output / "qualified-baseline-SHA256SUMS").write_bytes(inventory)
    metadata["scope"] = (
        "OFFLINE_ONLY_added_extra_fault_negedge_alignment_status_qualified_NOT_raw217_pass"
    )
    metadata["qualified_baseline_inventory_sha256"] = BASE_INVENTORY
    metadata["qualified_baseline_path"] = str(original.resolve())
    metadata["source_sha256"] = {
        p.name: hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted(source.iterdir())
    }
    (output / "preparation.json").write_text(json.dumps(metadata, indent=2) + "\n")
    files = sorted(source.iterdir()) + [
        output / name
        for name in (
            "settings.tcl",
            "preparation.json",
            "original-SHA256SUMS",
            "strict-diagnostic-SHA256SUMS",
            "qualified-baseline-SHA256SUMS",
        )
    ]
    (output / "SHA256SUMS").write_text(
        "".join(
            f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(output)}\n"
            for p in files
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
