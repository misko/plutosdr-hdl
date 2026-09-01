#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"
mkdir -p build

python3 tb/verify_hdl_structure.py
python3 tb/verify_frozen_fixture.py

iverilog -g2012 -Wall \
  -s tb_starlink_sat_add48 \
  -o build/starlink_sat_add48.vvp \
  starlink_sat_add48.v \
  tb/tb_starlink_sat_add48.sv
vvp build/starlink_sat_add48.vvp

iverilog -g2012 -Wall \
  -s tb_starlink_pss_raw_correlator \
  -o build/starlink_pss_raw_correlator.vvp \
  starlink_sat_add48.v \
  starlink_pss_raw_correlator.v \
  tb/tb_starlink_pss_raw_correlator.sv
vvp build/starlink_pss_raw_correlator.vvp
