#!/usr/bin/env python3
"""Fail closed if the raw engine grows an undeclared multiplier."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CORE = ROOT / "starlink_pss_raw_correlator.v"
SATURATOR = ROOT / "starlink_sat_add48.v"


def executable_verilog(path: Path) -> str:
    source = path.read_text()
    source = re.sub(r"/\*.*?\*/", "", source, flags=re.DOTALL)
    source = re.sub(r"//.*", "", source)
    source = re.sub(r"\(\*.*?\*\)", "", source, flags=re.DOTALL)
    source = source.replace("@*", "@")
    return source


def main() -> None:
    core_source = CORE.read_text()
    core = executable_verilog(CORE)
    saturator = executable_verilog(SATURATOR)
    products = re.findall(
        r"multiplier_([0-2])_a_registered\s*\*\s*"
        r"multiplier_\1_b_registered",
        core,
    )
    if products != ["0", "1", "2"]:
        raise RuntimeError(f"expected multiplier set 0,1,2 exactly once, got {products}")
    remaining = re.sub(
        r"multiplier_([0-2])_a_registered\s*\*\s*"
        r"multiplier_\1_b_registered",
        "",
        core,
    )
    if "*" in remaining or "*" in saturator:
        raise RuntimeError("an undeclared multiplication operator exists in the RTL")
    for declaration in (
        "COEFFICIENT_COUNT = 66",
        "CAPTURE_COUNT = 130",
        "RESULT_COUNT = 65",
    ):
        if declaration not in core:
            raise RuntimeError(f"missing fixed geometry declaration: {declaration}")
    if core_source.count('use_dsp = "yes"') != 3:
        raise RuntimeError("exactly three multiplier result registers must request DSP use")
    if "sample_timestamp_memory[lag_index]" not in core:
        raise RuntimeError("result timestamp is no longer read from the first-tap slot")
    event_patterns = (
        r"coefficient_saturation_count\s*<=\s*"
        r"coefficient_saturation_count\s*\+\s*saturator_0_event",
        r"sample_saturation_count\s*<=\s*"
        r"sample_saturation_count\s*\+\s*saturator_0_event",
        r"correlation_saturation_count\s*<=\s*"
        r"correlation_saturation_count\s*\+\s*"
        r"saturator_0_event\s*\+\s*saturator_1_event",
        r"o_result_saturation_events\s*<=\s*"
        r"coefficient_saturation_count\s*\+\s*"
        r"sample_saturation_count\s*\+\s*correlation_saturation_count",
    )
    for pattern in event_patterns:
        if re.search(pattern, core) is None:
            raise RuntimeError("the engine saturation-event aggregation path changed")
    print(
        "HDL_STRUCTURE_PASS multipliers=3 coefficients=66 samples=130 "
        "results=65 saturation_event_paths=4"
    )


if __name__ == "__main__":
    main()
