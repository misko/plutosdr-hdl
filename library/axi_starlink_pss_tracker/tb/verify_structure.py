#!/usr/bin/env python3
"""Fail closed if the rate-scalable AXI/core boundary drifts."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
source = (ROOT / "axi_starlink_pss_tracker.v").read_text()
executable = re.sub(r"/\*.*?\*/", "", source, flags=re.DOTALL)
executable = re.sub(r"//.*", "", executable)


def require(fragment: str, message: str) -> None:
    if fragment not in executable:
        raise SystemExit(f"AXI_TRACKER_STRUCTURE_FAIL {message}")


for fragment, message in (
    ("(RATE_MSPS != 15) && (RATE_MSPS != 30) &&", "rate guard omits qualified values"),
    ("(RATE_MSPS != 60)", "60 MS/s is not qualified"),
    ("RATE_MULTIPLIER = RATE_MSPS / 15", "rate multiplier is not derived from the advertised rate"),
    ("COEFFICIENT_COUNT = 66 * RATE_MULTIPLIER", "coefficient geometry is not rate-scaled"),
    ("CAPTURE_COUNT = 130 * RATE_MULTIPLIER", "capture geometry is not rate-scaled"),
    ("QUALIFIED_LAG_COUNT = 60 * RATE_MULTIPLIER + 1", "qualified lag geometry is not rate-scaled"),
    ("32'h0001_0002 : 32'h0001_0003", "rate-specific ABI version is absent"),
    ("(RATE_MSPS != 15) && (ENABLE_INJECTION != 0)", "injection is not limited to its qualified rate"),
    ("parameter integer ENABLE_INJECTION = 1", "injection is not independently configurable"),
    ("if (ENABLE_INJECTION != 0 && ENABLE_INJECTION != 1)", "injection parameter is not fail-closed"),
    ("CAPABILITIES = ENABLE_INJECTION ?", "injection capability does not follow the implementation"),
    ("starlink_pss_reduced_tracking_core", "exact TRACK_ONE core is absent"),
    ("reset_epoch_async_n = s_axi_aresetn", "AXI reset is not the common asynchronous epoch"),
    ("sample_reset_control_sync <= {", "sample reset is not synchronized into AXI"),
    ("sample_reset_sync[1] && !sample_reset", "sample reset does not hold the sample core"),
    ("sample_index_gray <= binary_to_gray_64(selected_sample_index)", "selected sample index is not Gray encoded"),
    ("starlink_pss_injection_mux", "deterministic accepted-sample injection mux is absent"),
    ("if (ENABLE_INJECTION) begin : g_injection", "injection mux is not compile-time removable"),
    ("end else begin : g_direct_sample_path", "production direct sample path is absent"),
    ("assign selected_sample_i = sample_i", "production sample I is not direct"),
    ("assign selected_sample_q = sample_q", "production sample Q is not direct"),
    ("assign selected_sample_injected = 1'b0", "production path can claim injected data"),
    (".i_sample_i                        (selected_sample_i)", "tracker does not consume the selected sample path"),
    ("REG_INJECTION_LAST_GENERATION", "injection evidence register map is incomplete"),
    ("candidate_pending_sync <= {candidate_pending_sync[0], candidate_pending}", "sample status is not synchronized"),
    ("current_index_snapshot <= current_sample_index", "64-bit scheduling snapshot is absent"),
    ("candidate_command_pending && candidate_submit_ready && !telemetry_busy", "candidate buffer is not held during telemetry capture"),
    ("coefficient_push_pending && !coefficient_clear_pending", "coefficient buffer has no handshake"),
    ("coefficient_clear_pending && configuration_idle", "coefficient clear is not issued from an input-independent idle state"),
    ("if (register_read_pending)", "AXI register read tree is not pipelined"),
    ("if (result_word_valid)", "synchronous result RAM response is not acknowledged"),
    ("assign irq = result_available", "interrupt is not a level result indication"),
    ("telemetry_pipeline_idle =", "telemetry does not wait for quiescent sample counters"),
    ("candidate_queue_room == COMMAND_FIFO_CAPACITY", "telemetry does not drain queued commands"),
    ("telemetry_idle_count == 3'd3", "telemetry lacks a cross-domain quiescence guard"),
    (".wea   (telemetry_capture_active)", "telemetry counters are not stored in dual-clock RAM"),
    ("telemetry_write_index == TELEMETRY_COUNTERS - 1", "telemetry does not serialize all counters"),
    ("telemetry_ack_toggle <= telemetry_request_seen", "telemetry acknowledges before the RAM bank is complete"),
    ("if (telemetry_read_pending)", "synchronous telemetry RAM read is not pipelined"),
    ("telemetry_valid ? telemetry_memory_read_data : 32'd0", "invalid telemetry RAM contents are exposed"),
    ("REG_TELEMETRY_GENERATION", "telemetry generation register is absent"),
    (".i_candidate_center_timestamp      (candidate_pending_timestamp)", "candidate timestamp is not forwarded"),
    (".i_result_release                  (result_release)", "atomic result release is not forwarded"),
):
    require(fragment, message)

for unsafe_counter in (
    "read_bank_4_value = admitted_count",
    "read_bank_5_value = capture_published_count",
):
    if unsafe_counter in executable:
        raise SystemExit(
            "AXI_TRACKER_STRUCTURE_FAIL live sample-domain counter crosses into AXI"
        )

for retired_wide_mailbox in (
    "telemetry_sample_payload",
    "telemetry_payload_sync_1",
    "telemetry_payload_sync_2",
    "telemetry_snapshot",
):
    if retired_wide_mailbox in executable:
        raise SystemExit(
            "AXI_TRACKER_STRUCTURE_FAIL wide telemetry mailbox was reintroduced: "
            f"{retired_wide_mailbox}"
        )

if "starlink_pss_delay_candidate" in executable:
    raise SystemExit(
        "AXI_TRACKER_STRUCTURE_FAIL repeated-delay diagnostic was used as an exact gate"
    )

result_read_case = re.search(
    r"if\s*\(up_raddr\s*==\s*REG_RESULT_WORD_DATA\)\s*begin(?P<body>.*?)end",
    executable,
    flags=re.DOTALL,
)
if result_read_case is None or "up_rack <= 1'b1" in result_read_case.group("body"):
    raise SystemExit(
        "AXI_TRACKER_STRUCTURE_FAIL result read acknowledged before synchronous RAM data"
    )

telemetry_read_case = re.search(
    r"else\s+if\s*\(telemetry_word_addressed\)\s*begin(?P<body>.*?)end",
    executable,
    flags=re.DOTALL,
)
if telemetry_read_case is None or "up_rack <= 1'b1" in telemetry_read_case.group("body"):
    raise SystemExit(
        "AXI_TRACKER_STRUCTURE_FAIL telemetry read acknowledged before synchronous RAM data"
    )

print(
    "AXI_TRACKER_STRUCTURE_PASS rates=15,30,60 host_scheduled=1 exact_track_one=1 "
    "coordinated_reset=1 gray_index=1 atomic_result=1 "
    "atomic_telemetry=serial_bram deterministic_injection=1 irq=level"
)
