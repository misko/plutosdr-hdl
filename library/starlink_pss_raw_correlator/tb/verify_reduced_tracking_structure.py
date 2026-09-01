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
    r"\.i_result_ready\s*\(raw_result_ready\)",
    "raw correlator output is not backpressured by the reducer",
)
require(
    r"\.o_tuple_ready\s*\(raw_result_ready\)",
    "reducer tuple handshake is not connected to the raw core",
)
require(
    r"\.i_tuple_first\s*\(raw_result_lag\s*==\s*-7'sd32\)",
    "first tuple is not derived from lag -32",
)
require(
    r"\.i_tuple_last\s*\(raw_result_lag\s*==\s*7'sd32\)",
    "last tuple is not derived from lag +32",
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
    "REDUCED_TRACKING_STRUCTURE_PASS mode=TRACK_ONE first_lag=-32 "
    "last_lag=32 exact_eh_cancellation=1 atomic_store=1"
)
