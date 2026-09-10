"""Offline observation-only diagnostic derived from the failed baseline freeze."""

import argparse
import hashlib
import json
import shutil
import subprocess
from pathlib import Path

BASE_INVENTORY = "13f525d4fa04a0f84cf4c0a26fecdd2173091556686af2feaee60379e96ab757"
TOP = "tb_starlink_pss_fft_bank_owned_slice"
OBSERVER = "starlink_pss_exact_control_actual_compare.sv"
FATAL = '      $fatal(1, "EXACT_ACTUAL_PUBLIC_REASON_OWNERSHIP_MISMATCH actual=%h old=%h", actual_public, reference_public);'
OLD_BRANCH = "    if (actual_public !== reference_public)\n" + FATAL
NEW_BRANCH = (
    "    if (actual_public !== reference_public) begin\n"
    f"      {TOP}.exact_diagnose_mismatch();\n" + FATAL + "\n    end"
)
CONTEXT = (
    "injected_status",
    "test_kind",
    "clk",
    "fft_clk",
    "fast_cycle",
    "slow_cycle",
    "epoch",
    "resetn",
    "fft_resetn",
)


def once(text, old, new):
    if text.count(old) != 1:
        raise ValueError(f"nonunique frozen diagnostic anchor: {old}")
    return text.replace(old, new, 1)


def diagnostic_task(fields, actual=None, reference=None):
    """Names are literal; optional expression maps support a no-FFT self-test."""
    lines = [
        "  // BEGIN EXACT_CONTROL_NAMED_DIAGNOSTIC",
        "  task automatic exact_diagnose_mismatch;",
        "    integer diagnostic_count;",
        "    diagnostic_count = 0;",
        '    $display("EXACT_DIAGNOSTIC_CONTEXT time=%0t fields=217", $realtime);',
    ]
    for name in CONTEXT:
        lines += [
            f'    $display("EXACT_DIAGNOSTIC_CONTEXT {name} candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",',
            f"      {name}, exact_reference.{name}, {name}, exact_reference.{name});",
        ]
    for field in fields:
        a = field if actual is None else actual[field]
        b = "exact_reference." + field if reference is None else reference[field]
        lines += [
            f"    if ({a} !== {b}) begin",
            "      diagnostic_count = diagnostic_count + 1;",
            f'      $display("EXACT_DIAGNOSTIC_FIELD name={field} candidate_width=%0d reference_width=%0d candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b",',
            f"        $bits({a}), $bits({b}), {a}, {b}, {a}, {b});",
            "    end",
        ]
    actual_tuple = ", ".join(fields if actual is None else [actual[f] for f in fields])
    reference_tuple = ", ".join(
        ["exact_reference." + f for f in fields]
        if reference is None
        else [reference[f] for f in fields]
    )
    lines += [
        '    $display("EXACT_DIAGNOSTIC_TERMINAL mismatches=%0d original_equal=%b fresh_equal=%b",',
        f"      diagnostic_count, exact_public_equal, ({{{actual_tuple}}} === {{{reference_tuple}}}));",
    ]
    lines += ["  endtask", "  // END EXACT_CONTROL_NAMED_DIAGNOSTIC", ""]
    return "\n".join(lines)


def prepare(original, output):
    if output.exists():
        raise FileExistsError("refusing to overwrite diagnostic evidence")
    original_inventory = (original / "SHA256SUMS").read_bytes()
    if hashlib.sha256(original_inventory).hexdigest() != BASE_INVENTORY:
        raise ValueError("not the authorized original failed baseline inventory")
    subprocess.run(
        ["sha256sum", "-c", "SHA256SUMS", "--quiet"],
        cwd=original,
        check=True,
        timeout=10,
    )
    metadata = json.loads((original / "preparation.json").read_text())
    if metadata["settings"] != {
        "REGISTERED_SCHEDULING": 0,
        "DISTRIBUTED_FAST_FAULT": 0,
        "PRIVATE_NEXT_START_SCRATCH": 0,
        "EXACT_EXTRA_EPOCHS": 1,
        "FAST_MHZ": 175,
        "QUICK_MUTATION": 0,
    }:
        raise ValueError("diagnostic baseline settings changed")
    fields = metadata["compared_fields"]
    if len(fields) != 217 or len(set(fields)) != 217:
        raise ValueError("original observation inventory changed")
    source = output / "frozen_sources"
    shutil.copytree(original / "frozen_sources", source)
    observer = source / OBSERVER
    observer.write_text(once(observer.read_text(), OLD_BRANCH, NEW_BRANCH))
    bench = source / f"{TOP}.sv"
    bench.write_text(
        once(bench.read_text(), "endmodule", diagnostic_task(fields) + "endmodule")
    )
    shutil.copyfile(original / "settings.tcl", output / "settings.tcl")
    shutil.copyfile(__file__, source / Path(__file__).name)
    (output / "original-SHA256SUMS").write_bytes(original_inventory)
    metadata["scope"] = "offline_diagnostic_preparation_only_no_actual_execution"
    metadata["original_failed_baseline_inventory_sha256"] = BASE_INVENTORY
    metadata["original_failed_baseline_path"] = str(original.resolve())
    metadata["source_sha256"] = {
        p.name: hashlib.sha256(p.read_bytes()).hexdigest()
        for p in sorted(source.iterdir())
    }
    (output / "preparation.json").write_text(json.dumps(metadata, indent=2) + "\n")
    files = sorted(source.iterdir()) + [
        output / "settings.tcl",
        output / "preparation.json",
        output / "original-SHA256SUMS",
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
