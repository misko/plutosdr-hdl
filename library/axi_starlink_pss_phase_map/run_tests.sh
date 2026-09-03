#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"
mkdir -p build

python3 tb/verify_structure.py

run_case() {
  local name="$1"
  shift
  iverilog -g2012 -Wall \
    -s tb_axi_starlink_pss_phase_map \
    -o "build/axi_starlink_pss_phase_map_${name}.vvp" \
    "$@" \
    starlink_pss_axi_lite.v \
    ../starlink_pss_acquisition/starlink_pss_phase_map_bank.v \
    ../starlink_pss_acquisition/starlink_pss_phase_map.v \
    axi_starlink_pss_phase_map.v \
    tb/tb_axi_starlink_pss_phase_map.sv
  vvp "build/axi_starlink_pss_phase_map_${name}.vvp"
}

run_case async_71mhz
run_case phase_62mhz \
  -Ptb_axi_starlink_pss_phase_map.MAP_HALF_PERIOD_NS=8 \
  -Ptb_axi_starlink_pss_phase_map.MAP_INITIAL_DELAY_NS=3
run_case phase_100mhz \
  -Ptb_axi_starlink_pss_phase_map.MAP_HALF_PERIOD_NS=5 \
  -Ptb_axi_starlink_pss_phase_map.MAP_INITIAL_DELAY_NS=2
run_case phase_125mhz \
  -Ptb_axi_starlink_pss_phase_map.MAP_HALF_PERIOD_NS=4 \
  -Ptb_axi_starlink_pss_phase_map.MAP_INITIAL_DELAY_NS=1

iverilog -g2012 -Wall \
  -s tb_axi_starlink_pss_phase_map_snapshot \
  -o build/axi_starlink_pss_phase_map_snapshot.vvp \
  starlink_pss_axi_lite.v \
  axi_starlink_pss_phase_map.v \
  tb/tb_axi_starlink_pss_phase_map_snapshot.sv
vvp build/axi_starlink_pss_phase_map_snapshot.vvp
