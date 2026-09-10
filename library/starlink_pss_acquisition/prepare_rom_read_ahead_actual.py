"""Offline additive ROM admission from the exact accepted C1 actual freeze."""

import argparse
import hashlib
import json
import re
import runpy
import shutil
import subprocess
from pathlib import Path

PYTHON = "/home/mouse9911/gits/pluto-plus-utils/.venv/bin/python"
C1_INVENTORY = "9c81c43d9ed0bbc6cfba1d40074d11ec8cd94530fc9d7920de809bd6d68ce39c"
C1_TOP_SHA = "bdcfd7e9137db6bc94ce3d9a8be03d4e8a347591df367f85ad7f73bc10d3657d"
C1_RUNNER_SHA = "1f3b5e34965062b901157a1118fa16d141c78ed43e426945a669ff272c4c4231"
ROM_SHA = "d35020ea933637d96f1d197322110d4c436566e9e03870732082a55dc7d2cee4"
TOP = "tb_starlink_pss_fft_bank_owned_slice.sv"
RUNNER = "simulate_exact_control_prepared.tcl"
OBSERVER = "starlink_pss_rom_actual_observer.svh"
OBSERVER_SHA = "de1dc6d2590014ed80351038077c2af52ba71ce7d200c704169f8243ab2ae45a"
WORD = "PRIVATE_ROM_READ_AHEAD"
META = "PRIVATE_BLOCK_METADATA_READ_AHEAD"
SETTINGS = {"REGISTERED_SCHEDULING": 1, "DISTRIBUTED_FAST_FAULT": 1,
            "PRIVATE_NEXT_START_SCRATCH": 1, "EXACT_EXTRA_EPOCHS": 1,
            "FAST_MHZ": 175, "QUICK_MUTATION": 0, "PER_CAUSE_FAULT_CDC": 1}
RTL_SHA = {
    "starlink_pss_fft_bank_owned_slice.v": "e8285f5ef2b548272ec357fca5213b1e400b5242396be2597498eff09f665579",
    "starlink_pss_forward_kernel_join.v": "d5a2d9d4f81b3bc0a7eb2a2f553eaa5a478d53c1d1ccc0653af6d7b4b6de6558",
    "starlink_pss_kernel_rom.v": "2d90b6b13c79074debcd3650836803752a2269f4ae9f3491abe575452240de71",
    "starlink_pss_realtime_input_guard.v": "eb1f968a30ae0371421cfb0766c7f8bf0c23411e730717cd0d4924be0604109e",
    "starlink_pss_realtime_result_guard.v": "09ab35339d55ddf88e813830322d21574d0794c489c9749f68113e9da7807be2",
    "starlink_pss_block_mailbox.v": "e85122eb6689ff49b31aa5a0c200e2666786629055b4f45856fe79fb829dbb55",
    "starlink_pss_spectrum_product.v": "f4fd79f2744cbaf4d7caa6afdf2781ab588fff612266cdb377593bbb31076669",
}
VARIANTS = {
    "starlink_pss_fft_bank_owned_slice": "starlink_pss_fft_bank_owned_rom_read_ahead",
    "starlink_pss_forward_kernel_join": "starlink_pss_forward_kernel_join_read_ahead",
}
CHECKS = """    if (PRIVATE_ROM_READ_AHEAD !== 0 && PRIVATE_ROM_READ_AHEAD !== 1)
      $fatal(1, "PRIVATE_ROM_READ_AHEAD must be zero or one");
    if (PRIVATE_BLOCK_METADATA_READ_AHEAD !== 0 && PRIVATE_BLOCK_METADATA_READ_AHEAD !== 1)
      $fatal(1, "PRIVATE_BLOCK_METADATA_READ_AHEAD must be zero or one");
"""
PARAMS = "  parameter integer PRIVATE_ROM_READ_AHEAD = 0,\n  parameter integer PRIVATE_BLOCK_METADATA_READ_AHEAD = 0\n"
FORWARD = "    .PRIVATE_ROM_READ_AHEAD(PRIVATE_ROM_READ_AHEAD),\n    .PRIVATE_BLOCK_METADATA_READ_AHEAD(PRIVATE_BLOCK_METADATA_READ_AHEAD)"
TCL_RECEIPT = r"""# BEGIN ROM_INPUT_SHADOW_RECEIPT
proc rom_verify_receipt {log word metadata} {
  set lines [regexp -all -inline -line {^ROM_READ_AHEAD_ACTUAL_PASS[^\n]*$} $log]
  if {[llength $lines] != 1} {error "expected exactly one ROM terminal"}
  set pattern {^ROM_READ_AHEAD_ACTUAL_PASS word=([01]) metadata=([01]) pre=([0-9]+) post=([0-9]+) accepts=([0-9]+) first=([0-9]+) last=([0-9]+) stalls=([0-9]+) resets=([0-9]+) current_fault_edges=([0-9]+) final_fault_edges=([0-9]+) private_reset_edges=([0-9]+) old_source=C1 input_ports_only=1 unconditional_old_state=1$}
  if {![regexp $pattern [lindex $lines 0] unused k m pre post accepts first last stalls resets current final private]} {
    error "malformed ROM receipt"
  }
  if {$k != $word || $m != $metadata || $pre <= 0 || $post != $pre ||
      $accepts < 512 || $first <= 0 || $last <= 0 || $stalls <= 0 ||
      $resets <= 0 || $current <= 0 || $final < 2 || $private <= 0} {error "ROM settings/coverage mismatch"}
  return "ROM_INPUT_SHADOW_RECEIPT_VERIFIED"
}
# END ROM_INPUT_SHADOW_RECEIPT
"""
TCL_ADMISSION = """if {!$per_cause} {error "requires accepted C1 option"}
set rom_word [expr {[lsearch -exact $exact_generics PRIVATE_ROM_READ_AHEAD=1] >= 0}]
set rom_metadata [expr {[lsearch -exact $exact_generics PRIVATE_BLOCK_METADATA_READ_AHEAD=1] >= 0}]
puts [exec env -u PYTHONHOME -u PYTHONPATH -u LD_LIBRARY_PATH """ + PYTHON + """ -B [file join $source_dir prepare_rom_read_ahead_actual.py] --verify-prepared $output_dir]
"""


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def once(text, before, after):
    if text.count(before) != 1:
        raise ValueError("nonunique literal ROM adapter anchor")
    return text.replace(before, after, 1)


def apply_edits(text, edits, inverse=False):
    for before, after in reversed(edits) if inverse else edits:
        text = once(text, after, before) if inverse else once(text, before, after)
    return text


def variant_edits(name):
    edits = [("module " + name + " #(", "module " + VARIANTS[name] + " #("),
             ("  parameter integer PRIVATE_NEXT_START_SCRATCH = 0\n",
              "  parameter integer PRIVATE_NEXT_START_SCRATCH = 0,\n" + PARAMS),
             ("  initial begin\n", "  initial begin\n" + CHECKS)]
    if name.endswith("slice"):
        edits += [("  starlink_pss_forward_kernel_join #(",
                   "  starlink_pss_forward_kernel_join_read_ahead #("),
                  ("    .PRIVATE_NEXT_START_SCRATCH(PRIVATE_NEXT_START_SCRATCH)) joiner (",
                   "    .PRIVATE_NEXT_START_SCRATCH(PRIVATE_NEXT_START_SCRATCH),\n" + FORWARD + ") joiner (")]
    else:
        edits += [("  starlink_pss_kernel_rom #(", "  starlink_pss_kernel_rom_read_ahead #("),
                  ("    .PRIVATE_NEXT_START_SCRATCH(PRIVATE_NEXT_START_SCRATCH)\n",
                   "    .PRIVATE_NEXT_START_SCRATCH(PRIVATE_NEXT_START_SCRATCH),\n" + FORWARD + "\n")]
    return edits


BENCH_EDITS = [
    ("  parameter integer PER_CAUSE_FAULT_CDC = 0;\n",
     ("  parameter integer PER_CAUSE_FAULT_CDC = 0;\n"
     "  parameter integer PRIVATE_ROM_READ_AHEAD = 0;\n"
     "  parameter integer PRIVATE_BLOCK_METADATA_READ_AHEAD = 0;\n")),
    ("  starlink_pss_fft_bank_owned_slice #(", "  starlink_pss_fft_bank_owned_rom_read_ahead #("),
    ("    .PRIVATE_NEXT_START_SCRATCH(PRIVATE_NEXT_START_SCRATCH)) dut (.*);\n",
     "    .PRIVATE_NEXT_START_SCRATCH(PRIVATE_NEXT_START_SCRATCH),\n" + FORWARD + ") dut (.*);\n"),
    ('  `include "starlink_pss_fault_cdc_actual_observer.svh"\n',
     ('  `include "starlink_pss_fault_cdc_actual_observer.svh"\n'
      '  `include "starlink_pss_rom_actual_observer.svh"\n')),
    ("    fault_cdc_verify_terminal();\n", "    fault_cdc_verify_terminal();\n    rom_verify_terminal();\n"),
]
RUNNER_EDITS = [
    ("# END FAULT_CDC_RECEIPTS\n", "# END FAULT_CDC_RECEIPTS\n" + TCL_RECEIPT),
    ("[llength $exact_generics] != 7", "[llength $exact_generics] != 9"),
    ("EXACT_EXTRA_EPOCHS PER_CAUSE_FAULT_CDC}", "EXACT_EXTRA_EPOCHS PER_CAUSE_FAULT_CDC " + WORD + " " + META + "}"),
    ("set project_name exact_control_actual\n", TCL_ADMISSION + "set project_name exact_control_actual\n"),
    ("puts [fault_cdc_verify_receipt $log $per_cause]\n",
     "puts [fault_cdc_verify_receipt $log $per_cause]\nputs [rom_verify_receipt $log $rom_word $rom_metadata]\n"),
]


def no_links(path):
    if any(p.is_symlink() for p in (path, *path.parents)):
        raise ValueError("symlinked preparation/source path")


def verify_inventory(directory, expected=None):
    no_links(directory)
    if expected is not None and sha(directory / "SHA256SUMS") != expected:
        raise ValueError("unexpected original C1 inventory")
    seen = set()
    for line in (directory / "SHA256SUMS").read_text().splitlines():
        digest, relative = line.split("  ", 1)
        path = Path(relative)
        if path.is_absolute() or ".." in path.parts or relative in seen:
            raise ValueError("unsafe/duplicate source inventory")
        seen.add(relative)
        no_links(directory / path)
        if sha(directory / path) != digest:
            raise ValueError("frozen source mismatch: " + relative)


def verify_sources(source):
    for name, digest in RTL_SHA.items():
        if sha(source / name) != digest:
            raise ValueError("canonical C1 source changed: " + name)
    for old, new in VARIANTS.items():
        if apply_edits((source / (new + ".v")).read_text(), variant_edits(old), True) != (source / (old + ".v")).read_text():
            raise ValueError("additive runtime inverse differs: " + new)
    if sha(source / "starlink_pss_kernel_rom_read_ahead.v") != ROM_SHA:
        raise ValueError("ROM differs from separately tested source")


def verify_prepared(output):
    verify_inventory(output)
    source = output / "frozen_sources"
    metadata = json.loads((output / "preparation.json").read_text())
    inherited = output / "rom-passing-C1-SHA256SUMS"
    if sha(inherited) != C1_INVENTORY:
        raise ValueError("inherited C1 inventory changed")
    # Bind every inherited artifact to the pinned original inventory, not the
    # new preparation's rehashable metadata. Only TOP/RUNNER are restored;
    # original settings/metadata have byte-exact separately named backups.
    inherited_sources = set()
    for line in inherited.read_text().splitlines():
        digest, relative = line.split("  ", 1)
        path = Path(relative)
        if path.parent == Path("frozen_sources"):
            inherited_sources.add(path.name)
        if relative == "preparation.json":
            data = (output / "rom-origin-preparation.json").read_bytes()
        elif relative == "settings.tcl":
            data = (output / "rom-origin-settings.tcl").read_bytes()
        elif relative in ("frozen_sources/" + TOP, "frozen_sources/" + RUNNER):
            edits = BENCH_EDITS if path.name == TOP else RUNNER_EDITS
            data = apply_edits((output / path).read_text(), edits, True).encode()
        else:
            data = (output / path).read_bytes()
        if hashlib.sha256(data).hexdigest() != digest:
            raise ValueError("inherited C1 artifact changed: " + relative)
    added_sources = {name + ".v" for name in VARIANTS.values()} | {
        "starlink_pss_kernel_rom_read_ahead.v", OBSERVER, "prepare_rom_read_ahead_actual.py"}
    if set(metadata["source_sha256"]) != inherited_sources | added_sources:
        raise ValueError("inherited C1 source membership changed")
    original_metadata = json.loads((output / "rom-origin-preparation.json").read_text())
    restored_metadata = dict(metadata)
    for key in ("rom_origin_status", "rom_origin_inventory", "rom_tested_source"):
        del restored_metadata[key]
    for key in ("settings", "scope", "source_sha256"):
        restored_metadata[key] = original_metadata[key]
    if restored_metadata != original_metadata:
        raise ValueError("inherited C1 preparation schema changed")
    settings = metadata["settings"]
    if set(settings) != set(SETTINGS) | {WORD, META} or any(type(settings[k]) is not int or settings[k] != v for k, v in SETTINGS.items()):
        raise ValueError("requires exact C1 settings and ROM options")
    if any(type(settings[k]) is not int or settings[k] not in (0, 1) for k in (WORD, META)):
        raise ValueError("invalid explicit ROM settings")
    tokens = re.fullmatch(r"set exact_generics \{([^{}]+)\}\n", (output / "settings.tcl").read_text())
    if not tokens or sorted(tokens[1].split()) != sorted(f"{k}={v}" for k, v in settings.items()):
        raise ValueError("missing/duplicate/mismatched ROM setting binding")
    if set(metadata["source_sha256"]) != {p.name for p in source.iterdir()}:
        raise ValueError("incomplete or extra source closure")
    for name, digest in metadata["source_sha256"].items():
        if sha(source / name) != digest:
            raise ValueError("source closure hash mismatch: " + name)
    verify_sources(source)
    if sha(source / OBSERVER) != OBSERVER_SHA:
        raise ValueError("input-only ROM observer differs from reviewed body")
    for name, edits, digest in ((TOP, BENCH_EDITS, C1_TOP_SHA), (RUNNER, RUNNER_EDITS, C1_RUNNER_SHA)):
        restored = apply_edits((source / name).read_text(), edits, True)
        if hashlib.sha256(restored.encode()).hexdigest() != digest:
            raise ValueError("whole original C1 bench/runner inverse differs")
    return settings


def verify_result(log_path, word, metadata, source):
    original = runpy.run_path(str(source / "prepare_fault_cdc_actual.py"))
    status = original["verify_result"](log_path, 1, source)
    program = TCL_RECEIPT + "\nset f [open [lindex $argv 0] r]; set log [read $f]; close $f\n" + f"puts [rom_verify_receipt $log {word} {metadata}]\n"
    result = subprocess.run(["tclsh", "/dev/stdin", str(log_path)], input=program,
                            capture_output=True, text=True, check=False, timeout=15)
    if result.returncode or result.stdout.strip() != "ROM_INPUT_SHADOW_RECEIPT_VERIFIED":
        raise ValueError("ROM terminal rejected: " + result.stdout + result.stderr)
    return status


def prepare(original, output, word=1, metadata_option=1):
    no_links(output)
    if output.exists():
        raise FileExistsError("refusing to overwrite ROM actual preparation")
    if any(type(v) is not int or v not in (0, 1) for v in (word, metadata_option)):
        raise ValueError("ROM options must be explicit zero or one")
    verify_inventory(original, C1_INVENTORY)
    if (original / "actual-process-exit.txt").read_text() != "0\n":
        raise ValueError("original C1 process failed")
    old = original / "frozen_sources"
    metadata = json.loads((original / "preparation.json").read_text())
    if metadata["settings"] != SETTINGS:
        raise ValueError("not the accepted C1 settings")
    simulation = original / "project/exact_control_actual.sim/sim_1/behav/xsim"
    passed = runpy.run_path(str(old / "prepare_fault_cdc_actual.py"))["verify_result"](simulation / "simulate.log", 1, old)
    for names, digest in ((["fft_bank_owned_trace.csv", "exact_control_reference_trace.csv"], "25ab9d06ca0e03f280540cda625a7826b3c4cbaa6322ce3266c59e1fbad94122"),
                          (["exact_control_extra_trace.csv", "exact_control_reference_extra_trace.csv"], "b965d12603a64111fa9c6ea36cb0f12189945ad4d9be7cf4fbd883980c4ec4a0")):
        if any(sha(simulation / name) != digest for name in names):
            raise ValueError("original full C1 CSV changed")
    acq = Path(__file__).resolve().parent
    verify_sources(acq)
    if sha(acq / "tb" / OBSERVER) != OBSERVER_SHA:
        raise ValueError("input-only ROM observer differs from reviewed body")
    source = output / "frozen_sources"
    source.mkdir(parents=True)
    for name in metadata["source_sha256"]:
        shutil.copyfile(old / name, source / name)
    for new in VARIANTS.values():
        shutil.copyfile(acq / (new + ".v"), source / (new + ".v"))
    shutil.copyfile(acq / "starlink_pss_kernel_rom_read_ahead.v", source / "starlink_pss_kernel_rom_read_ahead.v")
    shutil.copyfile(acq / "tb" / OBSERVER, source / OBSERVER)
    shutil.copyfile(__file__, source / Path(__file__).name)
    for name, edits in ((TOP, BENCH_EDITS), (RUNNER, RUNNER_EDITS)):
        (source / name).write_text(apply_edits((old / name).read_text(), edits))
    settings = dict(SETTINGS, **{WORD: word, META: metadata_option})
    metadata["settings"] = settings
    metadata["scope"] = "OFFLINE_additive_ROM_on_accepted_C1_dec20_reference_qualified_status_NOT_raw217_or_physical"
    metadata["rom_origin_status"] = passed
    metadata["rom_origin_inventory"] = C1_INVENTORY
    metadata["rom_tested_source"] = "32b20cb750caeede27561193728f088bc249195e"
    metadata["source_sha256"] = {p.name: sha(p) for p in sorted(source.iterdir())}
    (output / "preparation.json").write_text(json.dumps(metadata, indent=2) + "\n")
    (output / "settings.tcl").write_text("set exact_generics {" + " ".join(f"{k}={v}" for k, v in settings.items()) + "}\n")
    for name in ("original-SHA256SUMS", "strict-diagnostic-SHA256SUMS", "qualified-baseline-SHA256SUMS", "combined-origin-SHA256SUMS", "cdc-passing111-SHA256SUMS"):
        shutil.copyfile(original / name, output / name)
    shutil.copyfile(original / "SHA256SUMS", output / "rom-passing-C1-SHA256SUMS")
    shutil.copyfile(original / "preparation.json", output / "rom-origin-preparation.json")
    shutil.copyfile(original / "settings.tcl", output / "rom-origin-settings.tcl")
    files = sorted(p for p in output.rglob("*") if p.is_file())
    (output / "SHA256SUMS").write_text("".join(f"{sha(p)}  {p.relative_to(output)}\n" for p in files))
    return verify_prepared(output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--original", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--word", type=int, choices=(0, 1), default=1)
    parser.add_argument("--metadata", type=int, choices=(0, 1), default=1)
    parser.add_argument("--verify-prepared", type=Path)
    args = parser.parse_args()
    if args.verify_prepared is not None:
        result = verify_prepared(args.verify_prepared)
    elif args.original is not None and args.output is not None:
        result = prepare(args.original, args.output, args.word, args.metadata)
    else:
        parser.error("requires original/output or verify-prepared")
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
