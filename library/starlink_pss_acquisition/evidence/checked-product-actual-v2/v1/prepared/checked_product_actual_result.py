"""Checked-product actual result checks; no tool execution or timing/RF claim.

The semantic parser is tested with explicitly synthetic fixtures. The public
admission CLI checks the prepared runtime/source gate before verify_result;
the latter also requires real generated xFFT artifacts. Old paired results
and controller-actor logs are not accepted.
"""
import base64
import csv
import hashlib
import json
import re
import subprocess
from collections import Counter

OWNER_COUNTS = ["pre", "post", "jobs", "products", "seals", "publications", "acks", "starts",
    "raw_offers", "raw_takes", "raw_bad_offers", "core_takes", "releases", "resets",
    "current_faults", "statuses", "purge_checks", "capacity_receipts", "retained_checks"]
TRACE_HEADER = "cycle,epoch,profile,running,state,core_resetn,admit,config,inverse,core_input,core_output,status,guard_commit,forward_committed,product_commit,handoff_ack,result_busy,source_valid,source_ready,product_read_valid,product_read_ready,output_bank_ready,fault,block_start"
FINAL = "CHECKED_PRODUCT_ACTUAL_PASS"


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def fields(log, marker, numeric, fixed):
    rows = re.findall(r"^" + re.escape(marker) + r"[^\n]*$", log, re.MULTILINE)
    if len(rows) != 1:
        raise ValueError("missing/duplicate terminal " + marker)
    tokens = rows[0].split()[1:]
    result = {}
    for token in tokens:
        if token.count("=") != 1:
            raise ValueError("malformed terminal " + marker)
        key, value = token.split("=")
        if key in result:
            raise ValueError("duplicate terminal field")
        result[key] = value
    if set(result) != set(numeric) | set(fixed) or any(result[k] != str(v) for k, v in fixed.items()):
        raise ValueError("wrong terminal scope/fields " + marker)
    for key in numeric:
        if not re.fullmatch(r"[0-9]+", result[key]):
            raise ValueError("noninteger terminal count")
        result[key] = int(result[key])
    return result


def verify_terminals(log, source):
    if re.search(r"(?im)fatal:|error:|fatal_error|segmentation fault|core dumped|abnormal program termination|internal exception|kernel[^\n]*crash|^FAIL\b|control_actor_not_fft|actor_only=1", log):
        raise ValueError("failure or actor scope is not actual qualification")
    if re.search(r"(?m)^(EXACT_CONTROL_ACTUAL_PASS|PRODUCT_FINAL_FENCE_ACTUAL_PASS|STATUS_QUALIFIED_ACTUAL_PASS)\b", log):
        raise ValueError("old paired/private-mailbox scope is not checked result")
    if log.count("Time resolution is 1 fs") != 1:
        raise ValueError("missing actual simulator log preamble")
    owner = fields(log, FINAL, OWNER_COUNTS, {"enabled": 1,
        "source": "actual_ports_and_independent_origin", "changed_latency": 1, "raw217_claim": 0})
    if any(owner[x] <= 0 for x in OWNER_COUNTS) or owner["pre"] != owner["post"] or owner["purge_checks"] != owner["post"]:
        raise ValueError("ownership coverage missing")
    if not (owner["jobs"] >= owner["publications"] >= owner["acks"] >= owner["starts"] >= owner["releases"]):
        raise ValueError("ownership lifetime counts inconsistent")
    if owner["seals"] < owner["publications"] or owner["raw_takes"] < owner["core_takes"] or owner["raw_bad_offers"] < 6:
        raise ValueError("sealed/raw token coverage missing")
    if owner["publications"] < 44 or owner["core_takes"] < 44*512 or owner["products"] < 44*512:
        raise ValueError("ownership counts cannot support unchanged healthy blocks")
    main = fields(log, "FFT_BANK_OWNED_SLICE_PASS", ["inverse_words", "closed_input_prefetch_witnesses",
        "provisional_prefix_words", "nominal_max_forward_interval_cycles"],
        {"fast_mhz": 175, "healthy_blocks": 44, "forward_words": 24064, "product_words": 24064,
         "purge_cases": 4, "fault_cases": 10, "overlap_loads": 37,
         "acceptance_equality_witnesses": 2, "held_final_ready_witnesses": 3})
    if not 128 <= main["provisional_prefix_words"] <= 132 or main["inverse_words"] != 44*512 + main["provisional_prefix_words"]:
        raise ValueError("numerical/provisional-prefix count changed")
    if main["closed_input_prefetch_witnesses"] <= 0 or not 0 < main["nominal_max_forward_interval_cycles"] <= 5215:
        raise ValueError("prefetch or absolute nominal service gate failed")
    definitions = [
        ("CHECKED_PORT_FED_GUARD_PASS", "return_checks full_shadow_checks", {}),
        ("CHECKED_CAPACITY_ACTUAL_ACK_PASS", "late_orphan_private_advances full_shadow_checks",
         {"handoff_fault_cases": 11, "raw_ready_differences": 0, "late_ack_witnesses": 4, "handoff_reset_recovery": 1}),
        ("REGISTERED_SCHEDULING_PASS", "completion_receipt_consumptions nominal_max_forward_interval_cycles",
         {"boundary_fault_cases": 8, "boundary_reset_cases": 4, "snapshot_to_admission_cycles": 2}),
        ("PREFLIGHT_REASON_SPLIT_PASS", "private_ready_differences private_admits masked_start_samples",
         {"matrix_cases": 84, "transform_phases": 2, "reason_bits": 6, "simultaneous_orphan_and_next_status": 1,
          "one_sided_fault_recoveries": 2, "exact_public_and_reason_shadow": 1}),
        ("CHECKED_INPUT_PHASE_PASS", "input_shadow_checks full_open_tuple_checks quarantine_open_checks",
         {"registered": 1, "active_fault_cases": 12, "vendor_open_quarantine_cases": 2,
          "reset_recoveries": 2, "exact_certified_and_bank_reads": 1}),
        ("CHECKED_SOURCE_IDENTITY_ACTUAL_PASS", "legacy_input_shadow_checks",
         {"enabled": 1, "exact_per_beat_fault_reasons": 1}),
        ("CHECKED_PREFLIGHT_ACTUAL_PASS", "global_current_cause_checks preparing_tuple_checks",
         {"registered": 1, "expected_cache_cases": 12, "raw_bank_boundary_rows": 84, "independent_old_reason_shadow": 1}),
        ("PAYLOAD_BUBBLES_ACTUAL_PASS", "checks join_occupied product_occupied invalid_join invalid_product",
         {"registered": 1, "frozen_old_chain": 1, "logical_retirement_unchanged": 1}),
        ("FORWARD_RETIREMENT_ACTUAL_PASS", "checks forward inverse_current sticky_forward",
         {"registered": 1, "all_old_outputs_literal": 1, "frozen_old_guard_chain": 1}),
        ("EXACT_CONTROL_EXTRA_EPOCHS_PASS", "", {"final_faults": 2, "held_final_stalls": 3,
         "one_sided_resets": 2, "healthy_recoveries": 4}),
    ]
    receipts = {}
    may_be_zero = {"late_orphan_private_advances", "private_admits", "inverse_current", "sticky_forward",
                   "invalid_join", "invalid_product"}
    for marker, counts, fixed in definitions:
        row = fields(log, marker, counts.split(), fixed)
        if any(row[k] <= 0 for k in counts.split() if k not in may_be_zero):
            raise ValueError("missing inherited local-shadow coverage " + marker)
        receipts[marker] = row
    # Execute only the two unchanged frozen receipt procedures, never the old
    # paired/raw217 verifier or the Vivado body of the original Tcl.
    old = (source.parent / "checked-original-runner.tcl").read_text()
    procedure = old[old.index("# BEGIN FAULT_CDC_RECEIPTS"):old.index("# BEGIN PRODUCT_FINAL_RECEIPT")]
    # Encode text as data, never interpolate a vendor log as Tcl commands.
    program = procedure + "\nset log [encoding convertfrom utf-8 [binary decode base64 {" + base64.b64encode(log.encode()).decode() + "}]]\nputs [fault_cdc_verify_receipt $log 1]\nputs [rom_verify_receipt $log 1 1]\n"
    result = subprocess.run(["tclsh"], input=program, text=True, capture_output=True, check=False, timeout=15)
    if result.returncode or result.stdout.splitlines() != ["FAULT_CDC_RECEIPT_VERIFIED", "ROM_INPUT_SHADOW_RECEIPT_VERIFIED"] or result.stderr:
        raise ValueError("unchanged CDC/ROM receipt rejected")
    return owner, receipts


def verify_cycles(simulation, owner):
    previous = -1
    services, pending, inverse_seen = {1: [], 2: []}, {}, set()
    last_admit, intervals = {}, {1: [], 2: []}
    streams = []
    for name, header in (("fft_bank_owned_trace.csv", True), ("exact_control_extra_trace.csv", False)):
        path = simulation / name
        with path.open("rb") as stream:
            stream.seek(-1, 2)
            if stream.read(1) != b"\n":
                raise ValueError("truncated complete cycle trace")
        count = 0
        with path.open() as stream:
            if header and stream.readline().rstrip("\n") != TRACE_HEADER:
                raise ValueError("changed full cycle trace schema")
            for row in csv.reader(stream):
                if len(row) != 24 or any(not re.fullmatch(r"[0-9]+|[xz]", value) for value in row):
                    raise ValueError("malformed four-state full trace")
                cycle = int(row[0])
                if cycle != previous + 1:
                    raise ValueError("cycle trace missing/reordered/duplicated row")
                previous = cycle
                count += 1
                epoch = int(row[1])
                if epoch not in (1, 2):
                    continue
                if row[22] == "1":
                    raise ValueError("fault in service profile")
                if row[6] == "1" and row[8] == "0":
                    if epoch in pending:
                        raise ValueError("new forward admission before real prior ACK drain")
                    if epoch in last_admit:
                        interval = cycle - last_admit[epoch]
                        if not 0 < interval <= 5215:
                            raise ValueError("absolute5215 forward admission interval failure")
                        intervals[epoch].append(interval)
                    last_admit[epoch] = cycle
                    pending[epoch] = cycle
                if row[6] == "1" and row[8] == "1":
                    inverse_seen.add(epoch)
                if epoch in pending and epoch in inverse_seen and row[4] == "2" and row[8] == "0" and row[16] == "0" and row[21] == "1":
                    service = cycle - pending.pop(epoch)
                    if not 0 < service <= 5215:
                        raise ValueError("absolute5215 service/real-ACK drain failure")
                    services[epoch].append(service)
                    inverse_seen.remove(epoch)
        if count <= 0:
            raise ValueError("empty trace")
        streams.append({"name": name, "rows": count, "bytes": path.stat().st_size, "sha256": sha(path)})
    if pending or len(services[1]) != 32 or len(services[2]) != 6 or previous + 1 != owner["pre"]:
        raise ValueError("incomplete full trace/service profile or observer accounting")
    streams[0]["forward_interval_cycles"] = intervals
    return streams, services


def verify_ledger(simulation, source, owner):
    path = simulation / "checked_product_ownership_trace.csv"
    if not path.read_bytes().endswith(b"\n"):
        raise ValueError("truncated ownership ledger")
    products = [int(x, 16) for x in (source / "product_q17.mem").read_text().splitlines()]
    exponents = [int(x, 16) for x in (source / "forward_exponents.mem").read_text().splitlines()]
    if len(products) != 1536 or len(exponents) != 3:
        raise ValueError("wrong numerical fixture")
    counts, private, published, accepted = Counter(), [], None, 0
    epoch_before, previous_cycle = -1, -1
    with path.open() as stream:
        if stream.readline().rstrip("\n") != "cycle,epoch,event,position,data,metadata,lease":
            raise ValueError("ownership ledger schema changed")
        for row in csv.reader(stream):
            if len(row) != 7:
                raise ValueError("malformed ownership row")
            cycle, epoch, event, pos = map(int, row[:4])
            data, metadata, lease = (int(x, 16) for x in row[4:])
            if cycle < previous_cycle or event not in (1, 2, 3, 4) or not 0 <= lease <= 3:
                raise ValueError("ownership ordering/lease changed")
            previous_cycle = cycle
            if epoch != epoch_before:
                private, published, accepted = [], None, 0
                epoch_before = epoch
            counts[event] += 1
            if event == 1:
                if pos == 0:
                    private = []
                private.append((pos, data, metadata, lease))
            elif event == 2:
                start = (metadata >> 5) & ((1 << 64)-1)
                offset = start - ((1 << 33) + epoch*65536)
                if offset < 0 or offset % 447:
                    raise ValueError("published descriptor not an admitted fixture")
                fixture = (offset//447) % 3
                expected_meta = (1 << 69) | (start << 5) | exponents[fixture]
                if metadata != expected_meta or len(private) != 512 or private != [
                    (n, products[fixture*512+n], expected_meta, lease) for n in range(512)]:
                    raise ValueError("published product differs from full numerical/private lifetime")
                published, accepted = (expected_meta, lease, fixture, False), 0
            elif event == 3:
                if published is None or published[3] or (metadata, lease) != published[:2]:
                    raise ValueError("ACK before publication or with wrong origin")
                published = (*published[:3], True)
            elif event == 4:
                if published is None or not published[3] or pos != accepted or accepted >= 512 or (metadata, lease) != published[:2] or data != products[published[2]*512+accepted]:
                    raise ValueError("bad/reordered/unchecked core tuple")
                accepted += 1
    if any(counts[event] != owner[key] for event, key in ((1, "products"), (2, "publications"), (3, "acks"), (4, "core_takes"))):
        raise ValueError("ownership terminal/ledger count disagreement")
    return {"name": path.name, "rows": sum(counts.values()), "sha256": sha(path), "bytes": path.stat().st_size}


def verify_result(prepared):
    source = prepared / "frozen_sources"
    project = prepared / "project"
    simulation = project / "exact_control_actual.sim/sim_1/behav/xsim"
    ip = "starlink_pss_fft512_bfp18_rt_candidate"
    xci = project / f"exact_control_actual.srcs/sources_1/ip/{ip}/{ip}.xci"
    instance = json.loads(xci.read_text())["ip_inst"]
    if instance["component_reference"] != "xilinx.com:ip:xfft:9.1":
        raise ValueError("not the generated vendor FFT")
    params = instance["parameters"]["component_parameters"]
    for key, value in {"transform_length": "512", "input_width": "18", "data_format": "fixed_point",
        "scaling_options": "block_floating_point", "throttle_scheme": "realtime"}.items():
        if params[key][0]["value"] != value:
            raise ValueError("generated FFT configuration changed")
    vendor_files = [xci, *(project / f"exact_control_actual.gen/sources_1/ip/{ip}/{kind}/{ip}.vhd" for kind in ("sim", "synth")),
                    simulation / "compile.log", simulation / "elaborate.log"]
    if any(not p.is_file() or p.is_symlink() or p.stat().st_size == 0 for p in vendor_files):
        raise ValueError("missing actual vendor/IP evidence")
    log_path = simulation / "simulate.log"
    log = log_path.read_text()
    owner, receipts = verify_terminals(log, source)
    streams, service = verify_cycles(simulation, owner)
    ledger = verify_ledger(simulation, source, owner)
    return {"scope": "checked_product_actual_vendor_functional_changed_latency_NOT_raw217_or_physical",
        "ownership": owner, "local_receipts": receipts, "full_traces": streams, "ownership_ledger": ledger,
        "service_cycles": service, "absolute_cap": 5215, "log_sha256": sha(log_path),
        "vendor_artifacts": {str(p.relative_to(prepared)): sha(p) for p in vendor_files}}
