"""Source-specific offline actual preparation for disabled and enabled review.

No vendor commands. Enabled observer/binding adaptations are a separate scope.
The copied original runner is intentionally NOT admitted by its original source
verifier after this transformation. Do not treat offline elaboration as a run.
"""
import argparse
import hashlib
import json
import re
import shutil
from pathlib import Path

ORIGIN_INVENTORY = "7adf2efa0a242b89ccfbb387b00210e76841ba544cbae4cef97efc861acf59b2"
TOP = "tb_starlink_pss_fft_bank_owned_slice.sv"
BINDING = "starlink_pss_product_final_actual_binding.svh"
ORIGINAL_SHA = {
    TOP: "68aab9352336490972dba7b05b59c9fcd6c3a813f741af8ee4590f25aec7870b",
    BINDING: "4b04032bb8eda1d597cc03b972c02839880caf4b28bf70de2176dda43fca3211",
}
RUNTIME_SHA = {
    "starlink_pss_fft_bank_owned_checked_product.v": "56f341f02623698d23e66a4b46146eaaca29a25de36aad1b3cdfa5f1d56ed062",
    "starlink_pss_fft_bank_owned_product_fence.v": "8923b42b3574fc1418eee99c5f5819f173c73fbf7b8bb65726a7ab3a5d8a6f7c",
    "starlink_pss_realtime_checked_product_input_guard.v": "7e0b6e674a8c70898c050571f66513fd06208c9738954385a3d3207d0cc65d37",
    "starlink_pss_realtime_input_guard.v": "eb1f968a30ae0371421cfb0766c7f8bf0c23411e730717cd0d4924be0604109e",
    "starlink_pss_realtime_result_guard_observe.v": "b052874e6f1e40d5ee1149256fe89a47abdf35cb06f7a9b46c5c4d4615dcc22e",
    "starlink_pss_realtime_result_guard.v": "09ab35339d55ddf88e813830322d21574d0794c489c9749f68113e9da7807be2",
    "starlink_pss_checked_product_read_observe.v": "222d09935af40ccd742f6df7344ae6c6682edb435b65fd7481877bdd33b2b344",
    "starlink_pss_product_sealed_observe.v": "386323152dff509f64688a1d3ea6827d6fb668430365180396df7baf94910f15",
    "starlink_pss_epoch_sealed_publication_bank.v": "76d6985aa2148776ee1e834307066575d269878dc2c32cffd2bdbb87f2c5a490",
    "starlink_pss_block_mailbox.v": "e85122eb6689ff49b31aa5a0c200e2666786629055b4f45856fe79fb829dbb55",
    "starlink_pss_product_fence_mailbox.v": "e4f4c56ddab8f05d0f9b9da9a75f975e11cb8ad441581c904bfb094f3013982f",
    "starlink_pss_forward_kernel_join_read_ahead.v": "191124c2ddadf1b6d7c56fa029ac2a8e952a75d9c174c2b6a7f6e8283b53365b",
    "starlink_pss_kernel_rom_read_ahead.v": "d35020ea933637d96f1d197322110d4c436566e9e03870732082a55dc7d2cee4",
    "starlink_pss_spectrum_product.v": "f4fd79f2744cbaf4d7caa6afdf2781ab588fff612266cdb377593bbb31076669",
}
ALIASES = {TOP: 144, BINDING: 19}
OLD_MODULE = "  starlink_pss_fft_bank_owned_product_fence #(" 
NEW_MODULE = "  starlink_pss_fft_bank_owned_checked_product #(" 
OLD_PARAMETER = "    .PRODUCER_LOCAL_FINAL_FENCE(PRODUCER_LOCAL_FINAL_FENCE)) dut (.*);"
NEW_PARAMETER = "    .PRODUCER_LOCAL_FINAL_FENCE(PRODUCER_LOCAL_FINAL_FENCE),\n    .CHECKED_PRODUCT_BANK(0)) dut (.*);"
ENABLED_OBSERVER = "starlink_pss_checked_product_actual_observer.svh"
OBSERVER_SHA = "e0fc22ae7975db53790b0fc46115dbfe9ab3bbcf18c8c37784011d7248dd5647"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def no_links(path):
    if any(item.is_symlink() for item in (path, *path.parents)):
        raise ValueError("aliased checked-product preparation path")


def once(text, old, new):
    if text.count(old) != 1:
        raise ValueError("changed checked-product literal anchor")
    return text.replace(old, new, 1)


def disabled_source(name, body, inverse=False):
    """Whole-file inverse, including every old observer/stimulus byte."""
    if name not in ORIGINAL_SHA:
        raise ValueError("unknown disabled source")
    if not inverse and digest(body.encode()) != ORIGINAL_SHA[name]:
        raise ValueError("original disabled source changed")
    if name == TOP:
        if inverse:
            body = once(body, NEW_PARAMETER, OLD_PARAMETER)
            body = once(body, NEW_MODULE, OLD_MODULE)
        else:
            body = once(body, OLD_MODULE, NEW_MODULE)
            body = once(body, OLD_PARAMETER, NEW_PARAMETER)
    before, after = "dut.product_bank.", "dut.original_product_bank.product_bank."
    if inverse:
        before, after = after, before
    # Negative prefix prevents changing exact_reference.dut and diagnostic
    # reference operands; only actual candidate mailbox names are relocated.
    body, count = re.subn(r"(?<![A-Za-z0-9_.])" + re.escape(before), after, body)
    if count != ALIASES[name]:
        raise ValueError("candidate-only mailbox alias inventory changed")
    if inverse and digest(body.encode()) != ORIGINAL_SHA[name]:
        raise ValueError("whole original observer/stimulus inverse changed")
    return body


def enabled_source(original):
    """Build the reviewed changed-latency branch with a literal full inverse.

    Every removed observer body is retained in the edit receipt. This is a
    source construction function, not a vendor result or launch admission.
    """
    if digest(original.encode()) != ORIGINAL_SHA[TOP]:
        raise ValueError("enabled baseline bench changed")
    body = original
    changes = []

    def change(old, new):
        nonlocal body
        body = once(body, old, new)
        changes.append((old, new))

    def section(first, last, replacement):
        start = body.index(first)
        end = body.index(last, start) + len(last)
        change(body[start:end], replacement)

    change(OLD_MODULE, NEW_MODULE)
    change("  parameter integer PRODUCER_LOCAL_FINAL_FENCE = 0;\n",
           "  parameter integer PRODUCER_LOCAL_FINAL_FENCE = 0;\n  parameter integer CHECKED_PRODUCT_BANK = 1;\n")
    change(OLD_PARAMETER, NEW_PARAMETER.replace("CHECKED_PRODUCT_BANK(0)", "CHECKED_PRODUCT_BANK(CHECKED_PRODUCT_BANK)"))
    change('  `include "starlink_pss_product_final_actual_binding.svh"\n',
           '  // Old sampled-mailbox observer is preserved in disabled/history scope.\n')
    section("  // BEGIN EXACT_CONTROL_SHADOW\n", "  // END EXACT_CONTROL_SHADOW\n",
            f'  `include "{ENABLED_OBSERVER}"\n  `include "starlink_pss_exact_control_extra_epochs.svh"\n')
    section("  // BEGIN EXACT_CONTROL_NAMED_DIAGNOSTIC\n", "  // END EXACT_CONTROL_NAMED_DIAGNOSTIC\n",
            "  // Raw217 diagnostics retained in immutable original and disabled control.\n")
    section("  // BEGIN STATUS_QUALIFIED_ACCOUNTING: diagnostic bookkeeping only.\n",
            "  // END STATUS_QUALIFIED_ACCOUNTING\n",
            "  // Enabled status is checked by frozen actual-input guard/ROM shadows; no retimed raw217 comparison.\n")
    change("  wire old_input_valid = old_input_phase ? dut.product_bank_valid : dut.source_valid;",
           "  wire old_discovery_valid = old_input_phase ? dut.product_bank_valid : dut.source_valid;\n"
           "  wire old_input_valid = old_input_phase ? dut.product_core_valid : dut.source_valid;")
    change("  wire old_preflight_lease = old_input_phase ? dut.product_consume_generation : dut.source_consume_generation;",
           "  wire [1:0] old_preflight_lease = old_input_phase ? dut.product_head_lease : {1'b0,dut.source_consume_generation};")
    change("  wire old_preparation_valid = old_input_valid && old_input_position == 0 && !old_input_last &&\n"
           "    old_preflight_lease == dut.held_lease && old_input_metadata == dut.engine_metadata &&\n"
           "    old_descriptor_header_valid && dut.destination_reserved;",
           "  wire old_preparation_valid = old_discovery_valid && old_input_position == 0 && !old_input_last &&\n"
           "    old_preflight_lease == dut.held_lease && old_input_metadata == dut.engine_metadata &&\n"
           "    old_descriptor_header_valid && dut.destination_reserved && (!old_input_phase || checked_start_binding);")
    change("     (old_input_metadata != dut.engine_metadata || !old_descriptor_header_valid),\n"
           "     (old_preflight_lease != dut.held_lease), (old_input_position != 0 || old_input_last),\n"
           "     !old_input_valid} : 6'b0;",
           "     (old_input_metadata != dut.engine_metadata || !old_descriptor_header_valid ||\n"
           "      (old_input_phase && !checked_start_binding)),\n"
           "     (old_preflight_lease != dut.held_lease), (old_input_position != 0 || old_input_last),\n"
           "     !old_discovery_valid} : 6'b0;")
    change("  reg injected_preflight_lease;", "  reg [1:0] injected_preflight_lease;")
    change("          {old_input_phase, old_input_valid, old_input_data, old_input_position,\n"
           "           old_input_last, old_input_metadata, old_preflight_lease, old_preparation_valid})",
           "          {old_input_phase, old_discovery_valid, old_input_data, old_input_position,\n"
           "           old_input_last, old_input_metadata, old_preflight_lease, old_preparation_valid})")
    change("  wire original_destination_ready = dut.next_inverse ? dut.output_bank_ready :\n"
           "    (dut.forward_committed ? dut.forward_handoff_ack : (dut.kernel_ready && dut.product_bank_ready));",
           "  // Shadow receives the actual guard READY/capacity input, never an old reconstructed ACK.\n"
           "  wire original_destination_ready = dut.result_guard.mailbox_input_ready;")
    # Exact approved destination-loss rebinding; actual READY force sites are
    # otherwise untouched (including held final, RUN, unknown and late faults).
    change("          2: begin wait(dut.state == dut.ARM_JOB && !dut.admission_receipt); force dut.product_bank_ready = 0; end",
           "          2: begin wait(dut.state == dut.ARM_JOB && !dut.admission_receipt); force dut.product_reservation = 0; end")
    change("        release dut.source_metadata; release dut.held_lease; release dut.product_bank_ready;",
           "        release dut.source_metadata; release dut.held_lease; release dut.product_reservation;")
    change("          if (preflight_kind == 4 || preflight_kind == 6) force dut.product_bank_ready = 0;",
           "          if (preflight_kind == 4 || preflight_kind == 6) force dut.product_reservation = 0;")
    change("        release dut.held_lease; release dut.product_bank_ready; release dut.output_bank_ready;",
           "        release dut.held_lease; release dut.product_reservation; release dut.output_bank_ready;")
    change("        expected_preflight_mask = preflight_kind == 6 ? 6'h3f : 6'b1 << preflight_kind;",
           "        expected_preflight_mask = preflight_kind == 6 ? 6'h3f :\n"
           "          (preflight_inverse && preflight_kind == 1 ? 6'h0a : 6'b1 << preflight_kind);")
    # Two original lease assignments are changed independently, preserving the
    # original source line as a complete inverse witness for each context.
    change("          1: begin wait(dut.state == dut.VERIFY_LEASE); injected_preflight_lease = !dut.held_lease;",
           "          1: begin wait(dut.state == dut.VERIFY_LEASE); injected_preflight_lease = dut.held_lease ^ 2'b01;")
    change("          injected_preflight_lease = !dut.held_lease; force dut.held_lease = injected_preflight_lease;",
           "          injected_preflight_lease = dut.held_lease ^ 2'b01; force dut.held_lease = injected_preflight_lease;")
    change("      if (dut.state == dut.ACK_DRAIN && !dut.result_busy && !dut.any_fast_fault &&\n"
           "          dut.result_destination_ready !== (dut.next_inverse ? dut.output_bank_ready : dut.forward_handoff_ack))\n"
           "        $fatal(1, \"raw readiness changed healthy controller drain edge\");",
           "      // Enabled actual ACK capacity is not the retained scheduler receipt.\n"
           "      // The independent checked observer asserts each lifetime separately.\n"
           "      if (dut.product_guard_ack_event !== checked_old_guard_ack)\n"
           "        $fatal(1, \"checked actual guard ACK differs from frozen port-fed guard\");")
    change("        preflight_generations = {dut.product_consume_generation, dut.source_consume_generation};\n"
           "        expected_preflight_mask =",
           "        preflight_generations = {dut.product_consume_generation, dut.source_consume_generation};\n"
           "        if(preflight_inverse)checked_begin_retained_watch();\n"
           "        expected_preflight_mask =")
    change("        preflight_generations = {dut.product_consume_generation, dut.source_consume_generation};\n"
           "        injected_expected_product =",
           "        preflight_generations = {dut.product_consume_generation, dut.source_consume_generation};\n"
           "        if(preflight_inverse)checked_begin_retained_watch();\n"
           "        injected_expected_product =")
    change("        if ({dut.product_consume_generation, dut.source_consume_generation} !== preflight_generations ||\n"
           "            !dut.selected_valid || dut.selected_position != 0)\n"
           "          $fatal(1, \"preflight fault released/consumed the still-owned source bank\");",
           "        if ({dut.product_consume_generation, dut.source_consume_generation} !== preflight_generations)\n"
           "          $fatal(1, \"preflight fault changed consumption generations\");\n"
           "        if(preflight_inverse)begin\n"
           "          checked_retained_owner();\n"
           "          if(!dut.fast_fault || dut.state!=dut.QUARANTINE)\n"
           "            $fatal(1,\"checked retained bank missing quarantine\");\n"
           "        end else if(!dut.selected_valid || dut.selected_position!=0)\n"
           "          $fatal(1, \"preflight fault released/consumed the still-owned source bank\");")
    change("          if ({dut.product_consume_generation, dut.source_consume_generation} !== preflight_generations ||\n"
           "              !dut.product_bank_valid || dut.product_bank_position != 0)\n"
           "            $fatal(1, \"expected-cache mismatch released inverse bank ownership\");",
           "          if ({dut.product_consume_generation, dut.source_consume_generation} !== preflight_generations)\n"
           "            $fatal(1, \"expected-cache mismatch changed consumption generations\");\n"
           "          checked_retained_owner();\n"
           "          if(!dut.fast_fault || dut.state!=dut.QUARANTINE)\n"
           "            $fatal(1, \"expected-cache mismatch lost retained quarantine\");")
    # The original enabled handoff drive now names ACTUAL ACK, not its later
    # receipt. All raw vendor force values and pre/post-ACK case distinctions
    # remain intact. Keep each original source occurrence in the inverse.
    change("      else wait(dut.forward_handoff_ack);", "      else wait(dut.checked_product_bank.actual_handoff);")
    change("      wait(dut.forward_handoff_ack);\n      if (test_kind >= 7)",
           "      wait(dut.checked_product_bank.actual_handoff);\n      if (test_kind >= 7)")
    change("    reset_epoch(0); expected_results = 0; send_words(0, 512); wait(dut.forward_handoff_ack);",
           "    reset_epoch(0); expected_results = 0; send_words(0, 512); wait(dut.checked_product_bank.actual_handoff);")
    change("        0: force dut.product_bank_metadata = 70'h123456789;",
           "        0: force dut.product_head_metadata = 75'h123456789;")
    change("      release dut.product_bank_metadata; release dut.product_bank_position; release dut.product_bank_last;\n"
           "      release dut.event_frame;",
           "      release dut.product_head_metadata; release dut.product_bank_position; release dut.product_bank_last;\n"
           "      release dut.event_frame;")
    change("      if (dut.forward_handoff_ack && test_kind != 3 && test_kind != 4 && test_kind != 5 && test_kind < 8)\n"
           "        $fatal(1, \"certified handoff ACK missed current external/identity fault\");",
           "      if (test_kind < 7 && (dut.checked_product_bank.actual_handoff || dut.product_guard_ack_event))\n"
           "        $fatal(1, \"checked actual ACK missed current external/identity/orphan fault\");\n"
           "      if (dut.forward_handoff_ack && test_kind != 3 && test_kind != 4 && test_kind != 5 && test_kind < 8)\n"
           "        $fatal(1, \"certified handoff receipt missed current external/identity fault\");")
    change("    if (raw_ready_handoff_fault_cases != 11 || !raw_ready_differences || late_ack_witnesses != 4)",
           "    if (raw_ready_handoff_fault_cases != 11 || !checked_capacity_receipts || late_ack_witnesses != 4)")
    # Source-half of the original active RUN loop remains literal. Inverse
    # corruption is now an offered token BEFORE GOOD, not a post-GOOD wire
    # upset claimed to preserve the old immediate input framing mask.
    start = body.index("    // Live RUN input faults must still be rejected on the presenting edge,")
    end = body.index("    // Vendor-only quarantine", start)
    old_active = body[start:end]
    source_active = old_active[old_active.index("      wait(dut.state == dut.RUN_JOB"):old_active.index("      await_fault(); active_fault_cases")]
    new_active = """    // Same12 phase/kind/readiness cases; inverse targets the real raw offered
    // tuple before staged GOOD. Source checks below are the literal old body.
    for (active_inverse = 0; active_inverse < 2; active_inverse = active_inverse + 1)
    for (active_kind = 0; active_kind < 3; active_kind = active_kind + 1)
    for (active_ready = 0; active_ready < 2; active_ready = active_ready + 1) begin
      reset_epoch(0); expected_fault = 1; expected_results = 0; send_words(0, 512);
      if(active_inverse)begin
        wait(dut.checked_product_bank.adapter.reader.raw_valid &&
             dut.checked_product_bank.adapter.reader.raw_position==37);
        @(negedge fft_clk);
        if(active_ready==0)force dut.core_input_ready=0;
        else force dut.core_input_ready=1;
        if(active_kind==0)force dut.checked_product_bank.adapter.reader.raw_metadata=75'h123;
        if(active_kind==1)force dut.checked_product_bank.adapter.reader.raw_position=9'd7;
        if(active_kind==2)force dut.checked_product_bank.adapter.reader.raw_last=1;
        // Offered-word evidence includes a stalled/not-taken word. The
        // independent observer forbids delivery of this nominal word37.
        repeat(4)tick();
        if(dut.checked_product_bank.reader_reasons[3:0] !==
           (active_kind==0 ? 4'h4 : active_kind==1 ? 4'h1 : 4'h2) ||
           dut.checked_product_bank.core_take || dut.return_commit_valid ||
           checked_core_index>37)
          $fatal(1,"checked inverse offered corruption lost verdict or escaped");
        @(negedge fft_clk);release dut.core_input_ready;
        release dut.checked_product_bank.adapter.reader.raw_metadata;
        release dut.checked_product_bank.adapter.reader.raw_position;
        release dut.checked_product_bank.adapter.reader.raw_last;
      end else begin
""" + source_active + """      end
      await_fault(); active_fault_cases = active_fault_cases + 1;
    end
"""
    change(old_active, new_active)
    # No fake old paired-terminal or raw-status accounting is emitted.
    section("  // BEGIN EXACT_CONTROL_RECEIPT\n", "  // END EXACT_CONTROL_RECEIPT\n", """    $fclose(trace);
    if(EXACT_EXTRA_EPOCHS)begin
      trace=$fopen("exact_control_extra_trace.csv","w");
      exact_control_extra_epochs();
    end else $fatal(1,"checked actual requires original extra epochs");
    #0.003;
    fault_cdc_verify_terminal();
    rom_verify_terminal();
    checked_actual_verify_terminal();
""")
    change('"COMPLETED_INPUT_ACTUAL_CORE_EQ_PASS return_checks=', '"CHECKED_PORT_FED_GUARD_PASS return_checks=')
    change('"RAW_READY_CERTIFIED_ACK_PASS handoff_fault_cases=', '"CHECKED_CAPACITY_ACTUAL_ACK_PASS handoff_fault_cases=')
    change('"HELD_PHASE_INPUT_PASS registered=', '"CHECKED_INPUT_PHASE_PASS registered=')
    change('"BALANCED_IDENTITY_ACTUAL_PASS enabled=', '"CHECKED_SOURCE_IDENTITY_ACTUAL_PASS enabled=')
    change('"HELD_PREFLIGHT_ACTUAL_PASS registered=', '"CHECKED_PREFLIGHT_ACTUAL_PASS registered=')
    restored = restore_enabled_source(body, changes)
    if restored != original:
        raise ValueError("enabled full source inverse failed")
    return body, changes


def restore_enabled_source(body, changes):
    for old, new in reversed(changes):
        body = once(body, new, old)
    if digest(body.encode()) != ORIGINAL_SHA[TOP]:
        raise ValueError("whole enabled observer/stimulus inverse changed")
    return body


def origin_files(origin):
    no_links(origin)
    manifest = origin / "SHA256SUMS"
    no_links(manifest)
    if digest(manifest.read_bytes()) != ORIGIN_INVENTORY:
        raise ValueError("not the passing full P1 inventory")
    result = {}
    for line in manifest.read_text().splitlines():
        expected, name = line.split("  ", 1)
        path = Path(name)
        if path.is_absolute() or ".." in path.parts or name in result:
            raise ValueError("invalid inherited inventory path")
        target = origin / path
        no_links(target)
        body = target.read_bytes()
        if digest(body) != expected:
            raise ValueError("inherited source changed: " + name)
        result[name] = body
    if len(result) != 65:
        raise ValueError("incomplete inherited source closure")
    return result


def verify_disabled(output):
    """Offline source integrity, not old actual result or vendor admission."""
    no_links(output)
    metadata = json.loads((output / "checked-preparation.json").read_text())
    if metadata["scope"] != "disabled_compile_only_NOT_vendor_admission" or metadata["enabled"] != 0:
        raise ValueError("disabled preparation scope changed")
    origin_manifest = (output / "checked-passing-P1-SHA256SUMS").read_bytes()
    if digest(origin_manifest) != ORIGIN_INVENTORY:
        raise ValueError("changed inherited manifest")
    source = output / "frozen_sources"
    rows = {}
    for line in origin_manifest.decode().splitlines():
        expected, name = line.split("  ", 1)
        target = output / name
        no_links(target)
        body = target.read_bytes()
        if name in ("frozen_sources/" + TOP, "frozen_sources/" + BINDING):
            body = disabled_source(Path(name).name, body.decode(), inverse=True).encode()
        if digest(body) != expected:
            raise ValueError("full inherited body changed: " + name)
        rows[name] = expected
    if len(rows) != 65:
        raise ValueError("incomplete inherited closure")
    for name, expected in RUNTIME_SHA.items():
        no_links(source / name)
        if digest((source / name).read_bytes()) != expected:
            raise ValueError("frozen runtime changed: " + name)
    expected_files = set(rows) | {"frozen_sources/" + name for name in RUNTIME_SHA}
    expected_files |= {"checked-passing-P1-SHA256SUMS", "checked-preparation.json", "SHA256SUMS"}
    actual_files = {str(p.relative_to(output)) for p in output.rglob("*") if p.is_file()}
    if actual_files != expected_files:
        raise ValueError("unexpected/missing offline source")
    return {"scope": metadata["scope"], "enabled": 0, "runtime_modules": len(RUNTIME_SHA),
            "inherited_members": len(rows), "whole_original_bodies_restored": [TOP, BINDING]}


def prepare_disabled(origin, output, acq=None):
    no_links(output)
    if output.exists():
        raise FileExistsError("refusing existing checked-product preparation")
    original = origin_files(origin)
    acq = Path(__file__).resolve().parent if acq is None else acq
    runtime = {}
    for name, expected in RUNTIME_SHA.items():
        no_links(acq / name)
        body = (acq / name).read_bytes()
        if digest(body) != expected:
            raise ValueError("unqualified runtime source: " + name)
        runtime[name] = body
    output.mkdir(parents=True)
    for name, body in original.items():
        target = output / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(body)
    source = output / "frozen_sources"
    for name in ORIGINAL_SHA:
        old = (source / name).read_text()
        new = disabled_source(name, old)
        if disabled_source(name, new, inverse=True) != old:
            raise ValueError("disabled whole-source inverse failed")
        (source / name).write_text(new)
    for name, body in runtime.items():
        if (source / name).exists() and name not in ORIGINAL_SHA and (source / name).read_bytes() != body:
            raise ValueError("inherited runtime collision")
        (source / name).write_bytes(body)
    shutil.copyfile(origin / "SHA256SUMS", output / "checked-passing-P1-SHA256SUMS")
    (output / "checked-preparation.json").write_text(json.dumps({
        "scope": "disabled_compile_only_NOT_vendor_admission", "enabled": 0,
        "origin": str(origin), "runtime_sha256": RUNTIME_SHA,
        "source_helper_sha256": digest(Path(__file__).read_bytes()),
        "candidate_mailbox_aliases": ALIASES}, indent=2))
    (output / "SHA256SUMS").write_text("".join(
        f"{digest(p.read_bytes())}  {p.relative_to(output)}\n"
        for p in sorted(output.rglob("*")) if p.is_file() and p != output / "SHA256SUMS"))
    return verify_disabled(output)


def verify_enabled(output):
    """Full inherited inverse and frozen source closure, not vendor admission."""
    no_links(output)
    metadata = json.loads((output / "checked-preparation.json").read_text())
    if metadata["scope"] != "enabled_compile_only_NOT_vendor_admission" or metadata["enabled"] != 1:
        raise ValueError("enabled preparation scope changed")
    manifest = (output / "checked-passing-P1-SHA256SUMS").read_bytes()
    if digest(manifest) != ORIGIN_INVENTORY:
        raise ValueError("changed inherited manifest")
    original = (output / "checked-passing-P1-top.sv").read_text()
    expected_top, expected_changes = enabled_source(original)
    stored_changes = json.loads((output / "checked-whole-source-inverse.json").read_text())
    if stored_changes != [list(pair) for pair in expected_changes]:
        raise ValueError("enabled inverse receipt changed")
    source = output / "frozen_sources"
    candidate = (source / TOP).read_text()
    if candidate != expected_top or restore_enabled_source(candidate, expected_changes) != original:
        raise ValueError("enabled whole source changed")
    rows = {}
    for line in manifest.decode().splitlines():
        expected, name = line.split("  ", 1)
        target = output / name
        no_links(target)
        body = original.encode() if name == "frozen_sources/" + TOP else target.read_bytes()
        if digest(body) != expected:
            raise ValueError("full inherited body changed: " + name)
        rows[name] = expected
    if len(rows) != 65:
        raise ValueError("incomplete inherited closure")
    for name, expected in {**RUNTIME_SHA, ENABLED_OBSERVER: OBSERVER_SHA}.items():
        no_links(source / name)
        if digest((source / name).read_bytes()) != expected:
            raise ValueError("frozen enabled source changed: " + name)
    no_links(output / "prepare_checked_product_actual.py")
    if (output / "prepare_checked_product_actual.py").read_bytes() != Path(__file__).read_bytes():
        raise ValueError("preparation helper changed")
    expected_files = set(rows) | {"frozen_sources/" + name for name in RUNTIME_SHA}
    expected_files |= {"frozen_sources/" + ENABLED_OBSERVER, "checked-passing-P1-SHA256SUMS",
        "checked-preparation.json", "checked-passing-P1-top.sv", "checked-whole-source-inverse.json",
        "prepare_checked_product_actual.py", "SHA256SUMS"}
    actual_files = {str(p.relative_to(output)) for p in output.rglob("*") if p.is_file()}
    if actual_files != expected_files:
        raise ValueError("unexpected/missing enabled offline source")
    return {"scope": metadata["scope"], "enabled": 1, "runtime_modules": 14,
        "inherited_members": 65, "whole_original_bodies_restored": [TOP],
        "literal_edits": len(expected_changes), "absolute_service_cap": 5215,
        "raw217_claim": False, "vendor_launch_admitted": False}


def prepare_enabled(origin, output, acq=None):
    no_links(output)
    if output.exists():
        raise FileExistsError("refusing existing enabled preparation")
    original = origin_files(origin)
    acq = Path(__file__).resolve().parent if acq is None else acq
    additions = {}
    for name, expected in {**RUNTIME_SHA, ENABLED_OBSERVER: OBSERVER_SHA}.items():
        path = acq / ("tb" if name == ENABLED_OBSERVER else "") / name
        no_links(path)
        body = path.read_bytes()
        if digest(body) != expected:
            raise ValueError("unqualified enabled source: " + name)
        additions[name] = body
    old_top = original["frozen_sources/" + TOP].decode()
    new_top, changes = enabled_source(old_top)
    output.mkdir(parents=True)
    for name, body in original.items():
        target = output / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(body)
    source = output / "frozen_sources"
    for name, body in additions.items():
        if (source / name).exists() and (source / name).read_bytes() != body:
            raise ValueError("inherited enabled source collision")
        (source / name).write_bytes(body)
    (source / TOP).write_text(new_top)
    (output / "checked-passing-P1-top.sv").write_text(old_top)
    (output / "checked-whole-source-inverse.json").write_text(json.dumps(changes, indent=2))
    shutil.copyfile(origin / "SHA256SUMS", output / "checked-passing-P1-SHA256SUMS")
    shutil.copyfile(Path(__file__), output / "prepare_checked_product_actual.py")
    (output / "checked-preparation.json").write_text(json.dumps({
        "scope": "enabled_compile_only_NOT_vendor_admission", "enabled": 1,
        "origin": str(origin), "runtime_sha256": RUNTIME_SHA, "observer_sha256": OBSERVER_SHA,
        "source_helper_sha256": digest(Path(__file__).read_bytes()),
        "absolute_service_cap": 5215, "changed_latency": True, "raw217_claim": False}, indent=2))
    (output / "SHA256SUMS").write_text("".join(
        f"{digest(p.read_bytes())}  {p.relative_to(output)}\n"
        for p in sorted(output.rglob("*")) if p.is_file() and p != output / "SHA256SUMS"))
    return verify_enabled(output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--origin", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--verify-disabled", type=Path)
    parser.add_argument("--enabled", action="store_true")
    parser.add_argument("--verify-enabled", type=Path)
    args = parser.parse_args()
    if args.verify_enabled is not None:
        result = verify_enabled(args.verify_enabled)
    elif args.verify_disabled is not None:
        result = verify_disabled(args.verify_disabled)
    elif args.origin is not None and args.output is not None:
        result = (prepare_enabled if args.enabled else prepare_disabled)(args.origin, args.output)
    else:
        parser.error("requires --origin/--output or --verify-disabled")
    print(json.dumps(result, sort_keys=True))
