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

iverilog -g2012 -Wall \
  -s tb_starlink_pss_overlap_scheduler \
  -o build/starlink_pss_overlap_scheduler.vvp \
  starlink_pss_overlap_scheduler.v \
  tb/tb_starlink_pss_overlap_scheduler.sv
vvp build/starlink_pss_overlap_scheduler.vvp

iverilog -g2012 -Wall \
  -s tb_starlink_pss_overlap_scheduler_lifecycle \
  -o build/starlink_pss_overlap_scheduler_lifecycle.vvp \
  starlink_pss_overlap_scheduler.v \
  tb/tb_starlink_pss_overlap_scheduler_lifecycle.sv
vvp build/starlink_pss_overlap_scheduler_lifecycle.vvp

python3 tb/generate_spectrum_product_vectors.py \
  build/starlink_pss_spectrum_product_vectors.txt
iverilog -g2012 -Wall \
  -s tb_starlink_pss_spectrum_product \
  -o build/starlink_pss_spectrum_product.vvp \
  starlink_pss_spectrum_product.v \
  tb/tb_starlink_pss_spectrum_product.sv
vvp build/starlink_pss_spectrum_product.vvp

iverilog -g2012 -Wall \
  -s tb_starlink_pss_energy_cache \
  -o build/starlink_pss_energy_cache.vvp \
  starlink_pss_energy_cache.v \
  tb/tb_starlink_pss_energy_cache.sv
vvp build/starlink_pss_energy_cache.vvp

python3 tb/generate_score_divider_vectors.py \
  build/starlink_pss_score_divider_vectors.txt
iverilog -g2012 -Wall \
  -s tb_starlink_pss_score_divider \
  -o build/starlink_pss_score_divider.vvp \
  starlink_pss_score_divider.v \
  tb/tb_starlink_pss_score_divider.sv
vvp build/starlink_pss_score_divider.vvp

python3 tb/generate_score_prepare_vectors.py \
  build/starlink_pss_score_prepare_vectors.txt
iverilog -g2012 -Wall \
  -s tb_starlink_pss_score_prepare \
  -o build/starlink_pss_score_prepare.vvp \
  starlink_pss_score_prepare.v \
  tb/tb_starlink_pss_score_prepare.sv
vvp build/starlink_pss_score_prepare.vvp

iverilog -g2012 -Wall \
  -s tb_starlink_pss_raw_result_fifo \
  -o build/starlink_pss_raw_result_fifo.vvp \
  starlink_pss_raw_result_fifo.v \
  tb/tb_starlink_pss_raw_result_fifo.sv
vvp build/starlink_pss_raw_result_fifo.vvp
