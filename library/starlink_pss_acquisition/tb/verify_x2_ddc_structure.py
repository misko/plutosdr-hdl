#!/usr/bin/env python3
"""Machine-check the fixed acquisition-only x2 DDC implementation shape."""

from __future__ import annotations

import re
from pathlib import Path


SOURCE_PATH = Path(__file__).resolve().parents[1] / "starlink_pss_x2_ddc.v"
raw = SOURCE_PATH.read_text()
source = re.sub(r"/\*.*?\*/", "", raw, flags=re.DOTALL)
source = re.sub(r"//.*", "", source)
source = re.sub(r"\(\*.*?\*\)", "", source, flags=re.DOTALL)

for fragment in (
    "FILTER_TAPS = 15",
    "GROUP_DELAY_SAMPLES = 7",
    "COEFFICIENT_0 = -16'sd572",
    "COEFFICIENT_2 =  16'sd1260",
    "COEFFICIENT_4 = -16'sd2923",
    "COEFFICIENT_6 =  16'sd10235",
    "case (input_index[1:0])",
    "history_count == FILTER_TAPS-1",
    "input_index[0]",
    "(input_index - GROUP_DELAY_SAMPLES) >> 1",
    "magnitude[14:0] == 15'h4000",
    "integer_magnitude[0]",
    "gap_pending",
    "input_index == expected_input_index",
):
    if fragment not in source:
        raise SystemExit(f"X2_DDC_STRUCTURE_FAIL missing {fragment}")

products = re.findall(
    r"product_([0246])_([iq])\s*<=\s*pair_\1_\2\s*\*\s*COEFFICIENT_\1",
    source,
)
if sorted(products) != sorted(
    [(tap, component) for tap in ("0", "2", "4", "6") for component in ("i", "q")]
):
    raise SystemExit(f"X2_DDC_STRUCTURE_FAIL multiplier set is {products}")
remaining = re.sub(
    r"product_([0246])_([iq])\s*<=\s*pair_\1_\2\s*\*\s*COEFFICIENT_\1",
    "",
    source,
).replace("@*", "@")
if "*" in remaining or re.search(r"\s/\s", remaining):
    raise SystemExit("X2_DDC_STRUCTURE_FAIL undeclared multiply/divide operator")
if raw.count('use_dsp = "yes"') != 8:
    raise SystemExit("X2_DDC_STRUCTURE_FAIL expected exactly eight DSP requests")
if re.search(r"output\s+(?:wire|reg)\s+input_ready", source):
    raise SystemExit("X2_DDC_STRUCTURE_FAIL acquisition path gained backpressure")

print(
    "X2_DDC_STRUCTURE_PASS mixer=quadrant_absolute_index taps=15 "
    "nonzero_symmetric_pairs=4 dsps=8 decimation=2 group_delay=7 "
    "rounding=ties_even saturation=ci16"
)
