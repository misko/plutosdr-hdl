#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir"
mkdir -p build

iverilog -g2012 -Wall \
  -s tb_axi_ad9361_tx_null \
  -o build/axi_ad9361_tx_null.vvp \
  axi_ad9361_tx_null.v \
  tb/tb_axi_ad9361_tx_null.sv
vvp build/axi_ad9361_tx_null.vvp

echo "AXI_AD9361_RX_ONLY_TESTS_PASS"
