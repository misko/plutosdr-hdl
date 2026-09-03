#!/usr/bin/env python3
"""Fail closed if the experimental phase-map AXI/CDC contract drifts."""

from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


def executable(path: Path) -> str:
    source = path.read_text()
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.DOTALL)
    return re.sub(r"//.*", "", source)


bridge = executable(ROOT / "axi_starlink_pss_phase_map.v")
adapter = executable(ROOT / "starlink_pss_axi_lite.v")
constraints = (ROOT / "axi_starlink_pss_phase_map_constr.xdc").read_text()
ooc_constraints = (ROOT / "axi_starlink_pss_phase_map_ooc.xdc").read_text()
ooc_gate = (ROOT / "synthesize_ooc.tcl").read_text()
ip_package = (ROOT / "axi_starlink_pss_phase_map_ip.tcl").read_text()


def require(source: str, fragment: str, message: str) -> None:
    if fragment not in source:
        raise SystemExit(f"AXI_PHASE_MAP_STRUCTURE_FAIL {message}")


for source, fragment, message in (
    (bridge, "localparam integer SNAPSHOT_BITS = 790", "snapshot is not compact"),
    (bridge, "read_request_settle_count <= 2'd1", "read request has no payload settling cycle"),
    (bridge, "release_request_settle_count <= 2'd1", "release request has no payload settling cycle"),
    (bridge, "read_settle_count <= 2'd1", "read response has no payload settling cycle"),
    (bridge, "snapshot_settle_count <= 2'd2", "snapshot response lacks two settling cycles"),
    (bridge, "snapshot_payload <= snapshot_payload_sync_2", "snapshot is not atomically published"),
    (bridge, "up_rack <= up_rreq || read_pending || register_read_pending", "map reset cannot abort a pending AXI read"),
    (bridge, ".resetn            (control_reset_sync[1])", "map reset incorrectly resets the AXI transport"),
    (bridge, "starlink_pss_axi_lite", "long-latency AXI front end is absent"),
    (adapter, "s_axi_awready && s_axi_awvalid", "AXI AW handshake is absent"),
    (adapter, "s_axi_wready && s_axi_wvalid", "AXI W handshake is absent"),
    (adapter, "aw_pending && w_pending", "independent AXI write channels are not joined"),
    (adapter, "read_waiting && up_rack", "long-latency read acknowledgement is absent"),
    (adapter, "s_axi_rvalid && s_axi_rready", "AXI R backpressure handshake is absent"),
    (constraints, "set_bus_skew", "bundled-data skew constraints are absent"),
    (ooc_constraints, "set_clock_groups -asynchronous", "map and AXI clocks are not declared asynchronous"),
    (ooc_gate, "route_design -directive Explore", "physical gate does not route"),
    (ooc_gate, "critical_cdc_count", "physical gate does not reject critical CDC rows"),
    (ooc_gate, "snapshot_source] != 790", "physical gate does not prove all source snapshot bits"),
    (ip_package, '"starlink_pss_axi_lite.v"', "AXI front end is absent from packaged IP"),
):
    require(source, fragment, message)

if adapter.count("up_rcount") or "deaddead" in adapter.lower():
    raise SystemExit(
        "AXI_PHASE_MAP_STRUCTURE_FAIL short read-timeout logic reappeared"
    )

if constraints.count("set_bus_skew") != 3:
    raise SystemExit(
        "AXI_PHASE_MAP_STRUCTURE_FAIL expected exactly three payload skew constraints"
    )

register_function = re.search(
    r"function automatic \[31:0\] register_value;(?P<body>.*?)endfunction",
    bridge,
    flags=re.DOTALL,
)
if register_function is None:
    raise SystemExit("AXI_PHASE_MAP_STRUCTURE_FAIL register function is absent")
for unsafe_live_value in (
    "map_generation_0",
    "map_generation_1",
    "map_start_index_0",
    "map_start_index_1",
    "accepted_score_count",
    "discarded_score_count",
    "discontinuity_abort_count",
    "map_publish_count",
    "map_overrun_count",
    "score_protocol_error_count",
    "map_arithmetic_overflow_count",
    "map_read_error_count",
    "map_release_error_count",
    "detector_health_flags",
    "ingress_dropped_sample_count",
    "ingress_fifo_level",
    "ingress_maximum_fifo_level",
    "scheduler_gap_count",
    "scheduler_index_error_count",
    "scheduler_overflow_count",
    "detector_fault_count",
    "score_phase_index_discontinuity_count",
    "score_denominator_zero_count",
    "candidate_fifo_stored_count",
    "candidate_fifo_maximum_stored_count",
):
    if unsafe_live_value in register_function.group("body"):
        raise SystemExit(
            "AXI_PHASE_MAP_STRUCTURE_FAIL live map telemetry is visible in AXI"
        )

print(
    "AXI_PHASE_MAP_STRUCTURE_PASS axi_lite=long_latency snapshot_bits=790 "
    "atomic_snapshot=1 reset_abort=1 async_clocks=1 skew_constraints=3 "
    "routed_gate=1"
)
