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

python3 tb/verify_upper_edge_pss_kernel.py
iverilog -g2012 -Wall \
  -s tb_starlink_pss_kernel_rom \
  -o build/starlink_pss_kernel_rom.vvp \
  starlink_pss_kernel_rom.v \
  tb/tb_starlink_pss_kernel_rom.sv
vvp build/starlink_pss_kernel_rom.vvp

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

iverilog -g2012 -Wall \
  -s tb_starlink_pss_ifft_qualifier \
  -o build/starlink_pss_ifft_qualifier.vvp \
  starlink_pss_ifft_qualifier.v \
  tb/tb_starlink_pss_ifft_qualifier.sv
vvp build/starlink_pss_ifft_qualifier.vvp

iverilog -g2012 -Wall \
  -s tb_starlink_pss_xfft_block_adapter \
  -o build/starlink_pss_xfft_block_adapter.vvp \
  starlink_pss_xfft_block_adapter.v \
  tb/tb_starlink_pss_xfft_block_adapter.sv
vvp build/starlink_pss_xfft_block_adapter.vvp

iverilog -g2012 -Wall \
  -s tb_starlink_pss_energy_join \
  -o build/starlink_pss_energy_join.vvp \
  starlink_pss_energy_join.v \
  tb/tb_starlink_pss_energy_join.sv
vvp build/starlink_pss_energy_join.vvp

iverilog -g2012 -Wall \
  -s tb_starlink_pss_score_lanes \
  -o build/starlink_pss_score_lanes.vvp \
  starlink_pss_score_divider.v \
  starlink_pss_score_lanes.v \
  tb/tb_starlink_pss_score_lanes.sv
vvp build/starlink_pss_score_lanes.vvp

python3 tb/generate_score_pipeline_vectors.py \
  build/starlink_pss_score_pipeline_vectors.txt
iverilog -g2012 -Wall \
  -s tb_starlink_pss_score_pipeline \
  -o build/starlink_pss_score_pipeline.vvp \
  starlink_pss_score_prepare.v \
  starlink_pss_score_divider.v \
  starlink_pss_score_lanes.v \
  tb/tb_starlink_pss_score_pipeline.sv
vvp build/starlink_pss_score_pipeline.vvp

python3 tb/generate_candidate_score_path_vectors.py \
  build/starlink_pss_candidate_score_path_vectors.txt
iverilog -g2012 -Wall \
  -s tb_starlink_pss_candidate_score_path \
  -o build/starlink_pss_candidate_score_path.vvp \
  starlink_pss_energy_cache.v \
  starlink_pss_ifft_qualifier.v \
  starlink_pss_raw_result_fifo.v \
  starlink_pss_energy_join.v \
  starlink_pss_score_prepare.v \
  starlink_pss_score_divider.v \
  starlink_pss_score_lanes.v \
  starlink_pss_candidate_score_path.v \
  tb/tb_starlink_pss_candidate_score_path.sv
vvp build/starlink_pss_candidate_score_path.vvp
