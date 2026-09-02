#!/usr/bin/env python3
"""Fail closed if the Stage-15 AXI/core boundary drifts."""

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
    ("if (RATE_MSPS != 15)", "rate is not fail-closed at 15 MS/s"),
    ("starlink_pss_reduced_tracking_core", "exact TRACK_ONE core is absent"),
    ("reset_epoch_async_n = s_axi_aresetn", "AXI reset is not the common asynchronous epoch"),
    ("sample_reset_control_sync <= {", "sample reset is not synchronized into AXI"),
    ("sample_reset_sync[1] && !sample_reset", "sample reset does not hold the sample core"),
    ("sample_index_gray <= binary_to_gray_64(sample_index)", "sample index is not Gray encoded"),
    ("candidate_pending_sync <= {candidate_pending_sync[0], candidate_pending}", "sample status is not synchronized"),
    ("current_index_snapshot <= current_sample_index", "64-bit scheduling snapshot is absent"),
    ("candidate_command_pending && candidate_submit_ready", "candidate buffer has no handshake"),
    ("coefficient_push_pending && !coefficient_clear_pending", "coefficient buffer has no handshake"),
    ("coefficient_clear_pending && configuration_idle", "coefficient clear is not issued from an input-independent idle state"),
    ("if (register_read_pending)", "AXI register read tree is not pipelined"),
    ("if (result_word_valid)", "synchronous result RAM response is not acknowledged"),
    ("assign irq = result_available", "interrupt is not a level result indication"),
    ("telemetry_sample_payload <= {", "sample counters are not captured atomically"),
    ("telemetry_payload_sync_2 <= telemetry_payload_sync_1", "telemetry payload lacks two destination stages"),
    ("telemetry_snapshot <= telemetry_payload_sync_2", "settled telemetry payload is not published atomically"),
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

print(
    "AXI_TRACKER_STRUCTURE_PASS rate=15 host_scheduled=1 exact_track_one=1 "
    "coordinated_reset=1 gray_index=1 atomic_result=1 "
    "atomic_telemetry=1 irq=level"
)
