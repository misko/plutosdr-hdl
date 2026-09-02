#!/usr/bin/env python3
"""Machine-check the fixed TRACK_ONE composition and its handshake edges."""

from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
text = (ROOT / "starlink_pss_reduced_tracking_core.v").read_text()


def require(pattern: str, message: str) -> None:
    if re.search(pattern, text, re.MULTILINE | re.DOTALL) is None:
        raise SystemExit(f"REDUCED_TRACKING_STRUCTURE_FAIL {message}")


for module_name in (
    "starlink_pss_tracking_core",
    "starlink_pss_exact_reducer",
    "starlink_pss_result_store",
):
    require(rf"\b{module_name}\b", f"{module_name} is not instantiated")

require(
    r"assign\s+raw_result_ready\s*=\s*!raw_result_in_track_aperture\s*\|\|\s*reducer_tuple_ready",
    "raw correlator edge-drain/reducer backpressure split is absent",
)
require(
    r"\.o_tuple_ready\s*\(reducer_tuple_ready\)",
    "reducer tuple handshake is not connected to the raw core",
)
require(
    r"TRACK_FIRST_LAG\s*=\s*-7'sd30",
    "frozen first lag is not -30",
)
require(
    r"TRACK_LAST_LAG\s*=\s*7'sd30",
    "frozen last lag is not +30",
)
require(
    r"\.i_tuple_valid\s*\(raw_result_valid\s*&&\s*raw_result_in_track_aperture\)",
    "out-of-aperture raw tuples can enter the reducer",
)
require(
    r"\.i_include_eh\s*\(1'b0\)",
    "TRACK_ONE does not cancel job-constant Eh",
)
require(
    r"\.i_result_ready\s*\(reduced_result_ready\)",
    "reducer output is not backpressured by atomic publication",
)
require(
    r"\.o_result_ready\s*\(reduced_result_ready\)",
    "result-store completion handshake is not connected to the reducer",
)

print(
    "REDUCED_TRACKING_STRUCTURE_PASS mode=TRACK_ONE first_lag=-30 "
    "last_lag=30 raw_trace_lags=65 reduced_lags=61 "
    "exact_eh_cancellation=1 atomic_store=1"
)
