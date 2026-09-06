#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"
mkdir -p build

python3 tb/verify_periodic_fixture.py
python3 tb/verify_m2_vectors.py

iverilog -g2012 -Wall \
  -s tb_starlink_pss_periodic_injection_mux \
  -o build/starlink_pss_periodic_injection_mux.vvp \
  starlink_pss_periodic_injection_mux.v \
  tb/tb_starlink_pss_periodic_injection_mux.sv
vvp build/starlink_pss_periodic_injection_mux.vvp

iverilog -g2012 -Wall \
  -s tb_axi_starlink_pss_periodic_injector \
  -o build/axi_starlink_pss_periodic_injector.vvp \
  ../common/up_axi.v \
  starlink_pss_periodic_injection_mux.v \
  axi_starlink_pss_periodic_injector.v \
  tb/tb_axi_starlink_pss_periodic_injector.sv
vvp build/axi_starlink_pss_periodic_injector.vvp

echo "PERIODIC_INJECTOR_TESTS_PASS"
