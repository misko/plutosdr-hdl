#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"
mkdir -p build

iverilog -g2012 -Wall \
  -s tb_starlink_pss_event_cdc \
  -o build/starlink_pss_event_cdc.vvp \
  starlink_pss_event_cdc.v \
  tb/tb_starlink_pss_event_cdc.sv
vvp build/starlink_pss_event_cdc.vvp

iverilog -g2012 -Wall -Wno-portbind \
  -s tb_axi_starlink_pss_monitor_geometry \
  -o build/axi_starlink_pss_monitor_geometry.vvp \
  ../common/up_axi.v \
  starlink_pss_delay_candidate.v \
  starlink_pss_event_cdc.v \
  axi_starlink_pss_monitor.v \
  tb/tb_axi_starlink_pss_monitor_geometry.sv
vvp build/axi_starlink_pss_monitor_geometry.vvp

iverilog -g2012 -Wall \
  -s tb_axi_starlink_pss_monitor \
  -o build/axi_starlink_pss_monitor.vvp \
  ../common/up_axi.v \
  starlink_pss_delay_candidate.v \
  starlink_pss_event_cdc.v \
  axi_starlink_pss_monitor.v \
  tb/tb_axi_starlink_pss_monitor.sv
vvp build/axi_starlink_pss_monitor.vvp
