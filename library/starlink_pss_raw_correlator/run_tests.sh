#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"
mkdir -p build

python3 tb/verify_hdl_structure.py
python3 tb/verify_scheduler_sliding_structure.py
python3 tb/verify_frozen_fixture.py

iverilog -g2012 -Wall \
  -s tb_starlink_pss_candidate_scheduler \
  -o build/starlink_pss_candidate_scheduler.vvp \
  starlink_pss_async_fifo.v \
  starlink_pss_candidate_scheduler.v \
  tb/tb_starlink_pss_candidate_scheduler.sv
vvp build/starlink_pss_candidate_scheduler.vvp

iverilog -g2012 -Wall \
  -s tb_starlink_pss_capture_bridge \
  -o build/starlink_pss_capture_bridge.vvp \
  ../common/ad_mem.v \
  starlink_pss_async_fifo.v \
  starlink_pss_capture_bridge.v \
  tb/tb_starlink_pss_capture_bridge.sv
vvp build/starlink_pss_capture_bridge.vvp

iverilog -g2012 -Wall \
  -s tb_starlink_pss_tracking_core \
  -o build/starlink_pss_tracking_core.vvp \
  ../common/ad_mem.v \
  starlink_pss_async_fifo.v \
  starlink_sat_add48.v \
  starlink_pss_candidate_scheduler.v \
  starlink_pss_capture_bridge.v \
  starlink_pss_sliding_correlator.v \
  starlink_pss_tracking_core.v \
  tb/tb_starlink_pss_tracking_core.sv
vvp build/starlink_pss_tracking_core.vvp

iverilog -g2012 -Wall \
  -s tb_starlink_pss_sliding_correlator \
  -o build/starlink_pss_sliding_correlator.vvp \
  starlink_sat_add48.v \
  starlink_pss_raw_correlator.v \
  starlink_pss_sliding_correlator.v \
  tb/tb_starlink_pss_sliding_correlator.sv
vvp build/starlink_pss_sliding_correlator.vvp

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
