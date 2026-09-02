#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"
mkdir -p build

iverilog -g2012 -Wall \
  -s tb_starlink_pss_phase_map \
  -o build/starlink_pss_phase_map.vvp \
  starlink_pss_phase_map_bank.v \
  starlink_pss_phase_map.v \
  tb/tb_starlink_pss_phase_map.sv
vvp build/starlink_pss_phase_map.vvp
