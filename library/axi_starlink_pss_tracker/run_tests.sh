#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"
mkdir -p build

python3 tb/verify_structure.py

iverilog -g2012 -Wall \
  -s tb_axi_starlink_pss_tracker \
  -o build/axi_starlink_pss_tracker.vvp \
  ../common/up_axi.v \
  ../common/ad_mem.v \
  ../starlink_pss_raw_correlator/starlink_pss_async_fifo.v \
  ../starlink_pss_raw_correlator/starlink_sat_add48.v \
  ../starlink_pss_raw_correlator/starlink_pss_candidate_scheduler.v \
  ../starlink_pss_raw_correlator/starlink_pss_capture_bridge.v \
  ../starlink_pss_raw_correlator/starlink_pss_sliding_correlator.v \
  ../starlink_pss_raw_correlator/starlink_pss_tracking_core.v \
  ../starlink_pss_raw_correlator/starlink_pss_exact_reducer.v \
  ../starlink_pss_raw_correlator/starlink_pss_result_store.v \
  ../starlink_pss_raw_correlator/starlink_pss_reduced_tracking_core.v \
  axi_starlink_pss_tracker.v \
  tb/tb_axi_starlink_pss_tracker.sv
vvp build/axi_starlink_pss_tracker.vvp
