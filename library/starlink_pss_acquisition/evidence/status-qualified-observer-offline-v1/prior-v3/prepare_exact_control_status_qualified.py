"""Offline ONLY: qualify the new observer's invalid status payload, not RTL."""

import argparse
import hashlib
import json
import re
import shutil
import subprocess
from pathlib import Path

BASE_INVENTORY = "68511c5c9b7d0fb980ebdab498066fcf8d2ac41925e7ff9adfa0627f8249403f"
TOP = "tb_starlink_pss_fft_bank_owned_slice"
OBSERVER = "starlink_pss_exact_control_actual_compare.sv"
STATUS = "dut.core_status_data"
VALID = "dut.core_status_valid"
ANCHOR = "  wire [31:0] exact_checks, exact_active_checks, exact_consumed, exact_private_differences;"
OLD_CONNECTION = ".actual_public(exact_public_equal), .reference_public(1'b1)"
NEW_CONNECTION = ".actual_public(exact_protocol_equal), .reference_public(1'b1)"
ACCOUNT_CALL = f"    {TOP}.exact_status_account();\n"
FINISH_CALL = "    exact_status_finish();\n"
FINISH_ANCHOR = '    $display("EXACT_CONTROL_ACTUAL_PASS registered='


def once(text, old, new):
    if text.count(old) != 1:
        raise ValueError(f"nonunique status qualification anchor: {old}")
    return text.replace(old, new, 1)


def qualification(fields, actual=None, reference=None):
    """The original raw217 expression remains outside this additive block."""
    if (
        len(fields) != 217
        or len(set(fields)) != 217
        or STATUS not in fields
        or VALID not in fields
    ):
        raise ValueError("frozen217 observation inventory changed")
    a = {f: f for f in fields} if actual is None else actual
    b = {f: "exact_reference." + f for f in fields} if reference is None else reference
    other = [f for f in fields if f != STATUS]
    at = ", ".join(a[f] for f in other)
    bt = ", ".join(b[f] for f in other)
    return f"""  // BEGIN STATUS_QUALIFIED_OBSERVER: different from the raw217 contract.
  // Only both-exactly-zero TVALIDs exempt the complete eight-bit payload.
  // No signal from this observation block drives either island.
  wire exact_other_public_equal = ({{{at}}} === {{{bt}}});
  wire exact_both_status_invalid = ({a[VALID]} === 1'b0) && ({b[VALID]} === 1'b0);
  wire exact_status_payload_equal = exact_both_status_invalid ||
    ({a[STATUS]} === {b[STATUS]});
  wire exact_protocol_equal = exact_other_public_equal && exact_status_payload_equal;
  // END STATUS_QUALIFIED_OBSERVER
"""


def accounting(
    actual_status=STATUS,
    reference_status="exact_reference." + STATUS,
    actual_valid=VALID,
    reference_valid="exact_reference." + VALID,
):
    return f"""  // BEGIN STATUS_QUALIFIED_ACCOUNTING: diagnostic bookkeeping only.
  integer exact_status_samples = 0, exact_status_raw_equal = 0;
  integer exact_invalid_status_only = 0;
  task automatic exact_status_account;
    if (exact_protocol_equal !== 1'b1)
      $fatal(1, "STATUS_ACCOUNT_ON_FAILED_PUBLIC_COMPARISON");
    exact_status_samples = exact_status_samples + 1;
    if (exact_public_equal === 1'b1) exact_status_raw_equal = exact_status_raw_equal + 1;
    else begin
      if ({actual_valid} !== 1'b0 || {reference_valid} !== 1'b0 ||
          exact_other_public_equal !== 1'b1 || {actual_status} === {reference_status})
        $fatal(1, "STATUS_INVALID_ONLY_CLASSIFICATION_FAILED");
      exact_invalid_status_only = exact_invalid_status_only + 1;
      $display("EXACT_STATUS_INVALID_ONLY time=%0t epoch=%0d candidate_valid=%b reference_valid=%b candidate_hex=%h reference_hex=%h candidate_fourstate=%b reference_fourstate=%b raw_equal=%b protocol_equal=%b",
        $realtime, epoch, {actual_valid}, {reference_valid}, {actual_status}, {reference_status},
        {actual_status}, {reference_status}, exact_public_equal, exact_protocol_equal);
    end
  endtask
  task automatic exact_status_finish;
    if (exact_status_samples <= 0 || exact_status_samples != exact_checks ||
        exact_status_samples != exact_status_raw_equal + exact_invalid_status_only)
      $fatal(1, "STATUS_QUALIFIED_ACCOUNTING_INCOMPLETE");
    $display("EXACT_STATUS_QUALIFIED_OBSERVER scope=only_both_valid_exactly_zero_payload samples=%0d raw_equal=%0d invalid_only=%0d original_raw_contract_pass=0",
      exact_status_samples, exact_status_raw_equal, exact_invalid_status_only);
  endtask
  // END STATUS_QUALIFIED_ACCOUNTING
"""


def verify_observation_receipt(log, expected_checks):
    """Additional offline audit; never replaces the literal runner's gates."""
    lines = re.findall(r"^EXACT_STATUS_QUALIFIED_OBSERVER[^\n]*$", log, re.MULTILINE)
    pattern = (
        r"EXACT_STATUS_QUALIFIED_OBSERVER scope=only_both_valid_exactly_zero_payload "
        r"samples=(\d+) raw_equal=(\d+) invalid_only=(\d+) original_raw_contract_pass=0"
    )
    if len(lines) != 1 or not (match := re.fullmatch(pattern, lines[0])):
        raise ValueError("missing or malformed qualified-scope receipt")
    samples, raw, invalid = map(int, match.groups())
    if samples <= 0 or samples != expected_checks or samples != raw + invalid:
        raise ValueError("qualified observation accounting differs")
    rows = re.findall(r"^EXACT_STATUS_INVALID_ONLY[^\n]*$", log, re.MULTILINE)
    if len(rows) != invalid:
        raise ValueError("invalid-only row count differs")
    row_pattern = (
        r"EXACT_STATUS_INVALID_ONLY time=\d+ epoch=\d+ candidate_valid=0 reference_valid=0 "
        r"candidate_hex=[0-9a-fA-FxXzZ]+ reference_hex=[0-9a-fA-FxXzZ]+ "
        r"candidate_fourstate=([01xz]{8}) reference_fourstate=([01xz]{8}) "
        r"raw_equal=0 protocol_equal=1"
    )
    for row in rows:
        match = re.fullmatch(row_pattern, row)
        if not match or match[1] == match[2]:
            raise ValueError(
                "invalid-only row does not establish both-zero raw difference"
            )
    return {"samples": samples, "raw_equal": raw, "invalid_only": invalid}


def prepare(original, output):
    if output.exists():
        raise FileExistsError("refusing to overwrite observation evidence")
    inventory = (original / "SHA256SUMS").read_bytes()
    if hashlib.sha256(inventory).hexdigest() != BASE_INVENTORY:
        raise ValueError("not the authorized strict diagnostic freeze")
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
        raise ValueError("strict diagnostic settings changed")
    fields = metadata["compared_fields"]
    block = qualification(fields)
    source = output / "frozen_sources"
    shutil.copytree(original / "frozen_sources", source)
    bench = source / f"{TOP}.sv"
    text = once(bench.read_text(), ANCHOR, block + ANCHOR)
    text = once(text, OLD_CONNECTION, NEW_CONNECTION)
    text = once(text, "endmodule", accounting() + "endmodule")
    text = once(text, FINISH_ANCHOR, FINISH_CALL + FINISH_ANCHOR)
    bench.write_text(text)
    observer = source / OBSERVER
    observer.write_text(
        once(
            observer.read_text(),
            "    checks = checks + 1;",
            ACCOUNT_CALL + "    checks = checks + 1;",
        )
    )
    shutil.copyfile(original / "settings.tcl", output / "settings.tcl")
    shutil.copyfile(__file__, source / Path(__file__).name)
    (output / "strict-diagnostic-SHA256SUMS").write_bytes(inventory)
    # Retain the original baseline provenance dependency too.
    shutil.copyfile(original / "original-SHA256SUMS", output / "original-SHA256SUMS")
    metadata["scope"] = (
        "OFFLINE_ONLY_status_qualified_observer_NOT_original_raw217_pass"
    )
    metadata["strict_diagnostic_inventory_sha256"] = BASE_INVENTORY
    metadata["strict_diagnostic_path"] = str(original.resolve())
    metadata["unconditional_fields"] = [f for f in fields if f != STATUS]
    metadata["qualified_field"] = STATUS
    metadata["qualification"] = (
        "both status_valid exactly zero; otherwise all eight bits exact"
    )
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
