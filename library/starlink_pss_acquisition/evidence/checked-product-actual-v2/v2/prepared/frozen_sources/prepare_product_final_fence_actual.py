"""Offline additive final-fence admission; never runs a vendor tool."""
import argparse
import hashlib
import json
import re
import runpy
import shutil
import subprocess
from pathlib import Path

ORIGIN_INVENTORY = "6f5eddb99510e869bbe65548acc6ed64cd76bd98908aacfcd6e1c0361ccbe4ae"
ORIGIN_HELPER_SHA = "bca85ff4affb7fd4650489103ee5750567fe031d225fda057303007defb840b3"
ORIGIN_RUNNER_SHA = "9f198abf60d9119eae2ef565ae3d65b64104f93ce5f1b5be4b2e89776dd3deed"
TOP = "tb_starlink_pss_fft_bank_owned_slice.sv"
RUNNER = "simulate_exact_control_prepared.tcl"
KNOB = "PRODUCER_LOCAL_FINAL_FENCE"
SELF = "prepare_product_final_fence_actual.py"
BINDING = "starlink_pss_product_final_actual_binding.svh"
OBSERVER = "starlink_pss_product_final_actual_observer.sv"
RECIPE = "product_final_fence_delta.json"
ADDED_SHA = {
    "starlink_pss_fft_bank_owned_product_fence.v": "8923b42b3574fc1418eee99c5f5819f173c73fbf7b8bb65726a7ab3a5d8a6f7c",
    "starlink_pss_product_fence_mailbox.v": "e4f4c56ddab8f05d0f9b9da9a75f975e11cb8ad441581c904bfb094f3013982f",
    RECIPE: "816cc8e19ebb16ad21f964a06173d2c829c3c8751df61fbdcc4f34465e7d72e0",
    BINDING: "4b04032bb8eda1d597cc03b972c02839880caf4b28bf70de2176dda43fca3211",
    OBSERVER: "632273d1d31829964a2197d1cb967dbceb9ee72ac77cda213c172fb7d9ba1087",
}
SETTINGS = {"REGISTERED_SCHEDULING": 1, "DISTRIBUTED_FAST_FAULT": 1,
    "PRIVATE_NEXT_START_SCRATCH": 1, "EXACT_EXTRA_EPOCHS": 1, "FAST_MHZ": 175,
    "QUICK_MUTATION": 0, "PER_CAUSE_FAULT_CDC": 1, "PRIVATE_ROM_READ_AHEAD": 1,
    "PRIVATE_BLOCK_METADATA_READ_AHEAD": 1}
BENCH_EDITS = [
    ("  parameter integer PRIVATE_BLOCK_METADATA_READ_AHEAD = 0;\n",
     "  parameter integer PRIVATE_BLOCK_METADATA_READ_AHEAD = 0;\n  parameter integer PRODUCER_LOCAL_FINAL_FENCE = 0;\n"),
    ("  starlink_pss_fft_bank_owned_rom_read_ahead #(", "  starlink_pss_fft_bank_owned_product_fence #("),
    ("    .PRIVATE_BLOCK_METADATA_READ_AHEAD(PRIVATE_BLOCK_METADATA_READ_AHEAD)) dut (.*);",
     "    .PRIVATE_BLOCK_METADATA_READ_AHEAD(PRIVATE_BLOCK_METADATA_READ_AHEAD),\n    .PRODUCER_LOCAL_FINAL_FENCE(PRODUCER_LOCAL_FINAL_FENCE)) dut (.*);"),
    ('  `include "starlink_pss_rom_actual_observer.svh"\n',
     '  `include "starlink_pss_rom_actual_observer.svh"\n  `include "starlink_pss_product_final_actual_binding.svh"\n'),
    ("    rom_verify_terminal();\n", "    rom_verify_terminal();\n    product_final_verify_terminal();\n"),
]
TCL_RECEIPT = r"""# BEGIN PRODUCT_FINAL_RECEIPT
proc product_final_verify_receipt {log enabled} {
  set lines [regexp -all -inline -line {^PRODUCT_FINAL_FENCE_ACTUAL_PASS[^\n]*$} $log]
  if {[llength $lines] != 1} {error "expected one product final receipt"}
  set pattern {^PRODUCT_FINAL_FENCE_ACTUAL_PASS enabled=([01]) pre=([0-9]+) post=([0-9]+) sampled=([0-9]+) authorized=([0-9]+) vetoed=([0-9]+) unknown=([0-9]+) malformed=([0-9]+) nonsampled_private=([0-9]+) closed=([0-9]+) resets=([0-9]+) inverse_owned=([0-9]+) owned_stalls=([0-9]+) current_faults=([0-9]+) private_reset=([0-9]+) public_overlap=([0-9]+) source=real_controller old_public_shadow=unchanged_dec20 qualified_status_only=1$}
  if {![regexp $pattern [lindex $lines 0] unused e pre post sampled authorized vetoed unknown malformed private closed resets inverse stalls faults core overlap]} {
    error "malformed product final receipt"
  }
  if {$e != $enabled || $pre <= 0 || $post != $pre || $sampled <= 0 ||
      $authorized <= 0 || $sampled != $authorized+$vetoed+$unknown ||
      $closed <= 0 || $closed > $sampled || $resets <= 0 || $inverse <= 0 ||
      $stalls <= 0 || $faults < 2 || $core <= 0} {error "product final coverage mismatch"}
  return "PRODUCT_FINAL_RECEIPT_VERIFIED"
}
# END PRODUCT_FINAL_RECEIPT
"""
RUNNER_EDITS = [
    ("# END ROM_INPUT_SHADOW_RECEIPT\n", "# END ROM_INPUT_SHADOW_RECEIPT\n" + TCL_RECEIPT),
    ("[llength $exact_generics] != 9", "[llength $exact_generics] != 10"),
    ("PRIVATE_BLOCK_METADATA_READ_AHEAD} {", "PRIVATE_BLOCK_METADATA_READ_AHEAD PRODUCER_LOCAL_FINAL_FENCE} {"),
    ("prepare_rom_read_ahead_actual.py] --verify-prepared", SELF + "] --verify-prepared"),
    ("set project_name exact_control_actual\n",
     "set producer_final [expr {[lsearch -exact $exact_generics PRODUCER_LOCAL_FINAL_FENCE=1] >= 0}]\nset project_name exact_control_actual\n"),
    ("puts [rom_verify_receipt $log $rom_word $rom_metadata]\n",
     "puts [rom_verify_receipt $log $rom_word $rom_metadata]\nputs [product_final_verify_receipt $log $producer_final]\n"),
]


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def no_links(path):
    if any(p.is_symlink() for p in (path, *path.parents)):
        raise ValueError("aliased product-final evidence path")


def edits(text, pairs, inverse=False):
    for old, new in reversed(pairs) if inverse else pairs:
        before, after = (new, old) if inverse else (old, new)
        if text.count(before) != 1:
            raise ValueError("nonunique full product-final inverse anchor")
        text = text.replace(before, after, 1)
    return text


def inventory(path, expected=None):
    no_links(path)
    if expected is not None and sha(path / "SHA256SUMS") != expected:
        raise ValueError("wrong original inventory")
    seen = set()
    for line in (path / "SHA256SUMS").read_text().splitlines():
        digest, name = line.split("  ", 1)
        part = Path(name)
        if name in seen or part.is_absolute() or ".." in part.parts:
            raise ValueError("unsafe duplicate inventory member")
        seen.add(name)
        no_links(path / part)
        if sha(path / part) != digest:
            raise ValueError("source inventory mismatch: " + name)
    return seen


def old_helper(source):
    helper = source / "prepare_rom_read_ahead_actual.py"
    if sha(helper) != ORIGIN_HELPER_SHA:
        raise ValueError("old ROM helper changed")
    return runpy.run_path(str(helper))


def verify_origin(original):
    inventory(original, ORIGIN_INVENTORY)
    source = original / "frozen_sources"
    old = old_helper(source)
    if old["verify_prepared"](original) != SETTINGS:
        raise ValueError("not accepted C1/K1/M1 source/settings")
    owner = original.parent / "rom-actual-owner-v1"
    no_links(owner)
    for name in ("process-exit.txt", "after-integrity-exit.txt", "after-ip-exit.txt", "receipt-exit.txt"):
        if (owner / name).read_text() != "0\n":
            raise ValueError("original ROM actual failed: " + name)
    expected = ORIGIN_INVENTORY + "  SHA256SUMS\n" + ORIGIN_RUNNER_SHA + "  frozen_sources/" + RUNNER + "\n"
    if any((owner / name).read_text() != expected for name in ("before.sha256", "after.sha256")):
        raise ValueError("original actual stored integrity changed")
    simulation = original / "project/exact_control_actual.sim/sim_1/behav/xsim"
    status = old["verify_result"](simulation / "simulate.log", 1, 1, source)
    for names, digest in ((["fft_bank_owned_trace.csv", "exact_control_reference_trace.csv"],
            "25ab9d06ca0e03f280540cda625a7826b3c4cbaa6322ce3266c59e1fbad94122"),
            (["exact_control_extra_trace.csv", "exact_control_reference_extra_trace.csv"],
            "b965d12603a64111fa9c6ea36cb0f12189945ad4d9be7cf4fbd883980c4ec4a0")):
        if any(sha(simulation / name) != digest for name in names):
            raise ValueError("old complete CSV changed")
    return status


def verify_prepared(output):
    inventory(output)
    source = output / "frozen_sources"
    origin = output / "fence-passing-ROM-SHA256SUMS"
    if sha(origin) != ORIGIN_INVENTORY:
        raise ValueError("inherited full ROM inventory changed")
    inherited = set()
    for line in origin.read_text().splitlines():
        digest, name = line.split("  ", 1)
        inherited.add(name)
        if name == "settings.tcl":
            data = (output / "fence-origin-settings.tcl").read_bytes()
        elif name in ("frozen_sources/" + TOP, "frozen_sources/" + RUNNER):
            data = edits((output / name).read_text(), BENCH_EDITS if name.endswith(TOP) else RUNNER_EDITS, True).encode()
        else:
            data = (output / name).read_bytes()
        if hashlib.sha256(data).hexdigest() != digest:
            raise ValueError("inherited ROM artifact changed: " + name)
    metadata = json.loads((output / "fence-preparation.json").read_text())
    settings = metadata["settings"]
    if set(settings) != set(SETTINGS) | {KNOB} or any(type(settings[k]) is not int or settings[k] != v for k, v in SETTINGS.items()):
        raise ValueError("requires exact accepted ROM settings")
    if type(settings[KNOB]) is not int or settings[KNOB] not in (0, 1):
        raise ValueError("requires explicit final-fence 0/1 option")
    tokens = re.fullmatch(r"set exact_generics \{([^{}]+)\}\n", (output / "settings.tcl").read_text())
    if not tokens or sorted(tokens[1].split()) != sorted(f"{k}={v}" for k, v in settings.items()):
        raise ValueError("missing/duplicate/mismatched final-fence binding")
    expected = {Path(x).name for x in inherited if Path(x).parent == Path("frozen_sources")} | set(ADDED_SHA) | {SELF}
    if set(metadata["source_sha256"]) != expected or {p.name for p in source.iterdir()} != expected:
        raise ValueError("incomplete/extra inherited source closure")
    for name, digest in metadata["source_sha256"].items():
        if sha(source / name) != digest:
            raise ValueError("source closure hash mismatch")
    for name, digest in ADDED_SHA.items():
        if sha(source / name) != digest:
            raise ValueError("reviewed product-final source changed: " + name)
    if sha(source / SELF) != sha(Path(__file__)):
        raise ValueError("copied preparation helper differs")
    recipe = json.loads((source / RECIPE).read_text())
    for name, record in recipe["modules"].items():
        if edits((source / (name + ".v")).read_text(), record["edits"], True) != (source / (record["original"] + ".v")).read_text():
            raise ValueError("whole runtime inverse differs")
    return settings


def verify_result(log_path, enabled, source):
    status = old_helper(source)["verify_result"](log_path, 1, 1, source)
    program = TCL_RECEIPT + "\nset f [open [lindex $argv 0]]; set log [read $f]; close $f\n" + f"puts [product_final_verify_receipt $log {enabled}]\n"
    result = subprocess.run(["tclsh", "/dev/stdin", str(log_path)], input=program, text=True,
        capture_output=True, check=False, timeout=15)
    if result.returncode or result.stdout.strip() != "PRODUCT_FINAL_RECEIPT_VERIFIED":
        raise ValueError("product final terminal rejected: " + result.stdout + result.stderr)
    return status


def prepare(original, output, enabled=1):
    no_links(output)
    if output.exists():
        raise FileExistsError("refusing to overwrite product-final actual preparation")
    if type(enabled) is not int or enabled not in (0, 1):
        raise ValueError("final-fence option must be explicit 0/1")
    passed = verify_origin(original)
    acq = Path(__file__).resolve().parent
    sources = {name: acq / name for name in ADDED_SHA}
    sources[RECIPE] = acq.parents[2] / "tests/starlink_oracle" / RECIPE
    for name in (BINDING, OBSERVER):
        sources[name] = acq / "tb" / name
    if any(sha(path) != ADDED_SHA[name] for name, path in sources.items()):
        raise ValueError("local reviewed source changed")
    output.mkdir(parents=True)
    for name in inventory(original, ORIGIN_INVENTORY):
        target = output / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(original / name, target)
    source = output / "frozen_sources"
    for name, path in sources.items():
        shutil.copyfile(path, source / name)
    shutil.copyfile(__file__, source / SELF)
    for name, pairs in ((TOP, BENCH_EDITS), (RUNNER, RUNNER_EDITS)):
        (source / name).write_text(edits((source / name).read_text(), pairs))
    shutil.copyfile(original / "settings.tcl", output / "fence-origin-settings.tcl")
    shutil.copyfile(original / "SHA256SUMS", output / "fence-passing-ROM-SHA256SUMS")
    settings = dict(SETTINGS, **{KNOB: enabled})
    (output / "settings.tcl").write_text("set exact_generics {" + " ".join(f"{k}={v}" for k, v in settings.items()) + "}\n")
    metadata = {"settings": settings, "scope": "OFFLINE_real_controller_final_observer_NOT_vendor_execution",
        "origin": str(original), "origin_inventory": ORIGIN_INVENTORY, "origin_status": passed,
        "source_sha256": {p.name: sha(p) for p in sorted(source.iterdir())}}
    (output / "fence-preparation.json").write_text(json.dumps(metadata, indent=2) + "\n")
    (output / "SHA256SUMS").write_text("".join(f"{sha(p)}  {p.relative_to(output)}\n" for p in sorted(output.rglob("*")) if p.is_file()))
    return verify_prepared(output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--original", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--enabled", type=int, choices=(0, 1), default=1)
    parser.add_argument("--verify-prepared", type=Path)
    args = parser.parse_args()
    if args.verify_prepared:
        result = verify_prepared(args.verify_prepared)
    elif args.original and args.output:
        result = prepare(args.original, args.output, args.enabled)
    else:
        parser.error("requires original/output or verify-prepared")
    print(json.dumps(result, sort_keys=True))
