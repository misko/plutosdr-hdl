#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"
mkdir -p build

python3 tb/verify_structure.py
python3 tb/generate_real_wrapper_replay.py verify

iverilog -g2012 -Wall \
  -s tb_starlink_pss_injection_mux \
  -o build/starlink_pss_injection_mux.vvp \
  starlink_pss_injection_mux.v \
  tb/tb_starlink_pss_injection_mux.sv
vvp build/starlink_pss_injection_mux.vvp

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
  starlink_pss_injection_mux.v \
  axi_starlink_pss_tracker.v \
  tb/tb_axi_starlink_pss_tracker.sv
vvp build/axi_starlink_pss_tracker.vvp

iverilog -g2012 -Wall \
  -s tb_axi_starlink_pss_tracker \
  -Ptb_axi_starlink_pss_tracker.RATE_MSPS=30 \
  -o build/axi_starlink_pss_tracker_30msps.vvp \
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
  starlink_pss_injection_mux.v \
  axi_starlink_pss_tracker.v \
  tb/tb_axi_starlink_pss_tracker.sv
vvp build/axi_starlink_pss_tracker_30msps.vvp

iverilog -g2012 -Wall \
  -s tb_axi_starlink_pss_tracker \
  -Ptb_axi_starlink_pss_tracker.RATE_MSPS=60 \
  -o build/axi_starlink_pss_tracker_60msps.vvp \
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
  starlink_pss_injection_mux.v \
  axi_starlink_pss_tracker.v \
  tb/tb_axi_starlink_pss_tracker.sv
vvp build/axi_starlink_pss_tracker_60msps.vvp

iverilog -g2012 -Wall \
  -s tb_axi_starlink_pss_tracker_no_injection \
  -o build/axi_starlink_pss_tracker_no_injection.vvp \
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
  starlink_pss_injection_mux.v \
  axi_starlink_pss_tracker.v \
  tb/tb_axi_starlink_pss_tracker_no_injection.sv
vvp build/axi_starlink_pss_tracker_no_injection.vvp

iverilog -g2012 -Wall \
  -s tb_axi_starlink_pss_tracker_real_replay \
  -o build/axi_starlink_pss_tracker_real_replay.vvp \
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
  starlink_pss_injection_mux.v \
  axi_starlink_pss_tracker.v \
  tb/tb_axi_starlink_pss_tracker_real_replay.sv
vvp build/axi_starlink_pss_tracker_real_replay.vvp
