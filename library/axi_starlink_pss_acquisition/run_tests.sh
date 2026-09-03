#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
acq_dir="$script_dir/../starlink_pss_acquisition"
map_dir="$script_dir/../axi_starlink_pss_phase_map"
root_dir="$(cd "$script_dir/../../.." && pwd)"
cd "$script_dir"
mkdir -p build "$acq_dir/build"

python3 tb/verify_structure.py
python3 "$acq_dir/tb/verify_upper_edge_pss30_x2_ddc_kernel_q17.py"
python3 "$acq_dir/tb/verify_upper_edge_pss60_x4_ddc_kernel_q17.py"
PYTHONPATH="$root_dir" uv run --no-project --with numpy python \
  "$root_dir/tools/generate_starlink_pss30_ddc_vectors.py" \
  "$acq_dir/build"
PYTHONPATH="$root_dir" uv run --no-project --with numpy python \
  "$root_dir/tools/generate_starlink_pss60_ddc_vectors.py" \
  "$acq_dir/build"

common_control_sources=(
  "$map_dir/starlink_pss_axi_lite.v"
  axi_starlink_pss_phase_map_sync.v
  tb/tb_axi_starlink_pss_phase_map_sync_rate.sv
)
for rate in 15 30 60; do
  iverilog -g2012 -Wall \
    -s tb_axi_starlink_pss_phase_map_sync_rate \
    -Ptb_axi_starlink_pss_phase_map_sync_rate.INPUT_RATE_MSPS="$rate" \
    -o "build/phase_map_sync_rate${rate}.vvp" \
    "${common_control_sources[@]}"
  vvp "build/phase_map_sync_rate${rate}.vvp"
done

common_wrapper_sources=(
  "$acq_dir/starlink_pss_sample_cdc.v"
  "$acq_dir/starlink_pss_x2_ddc.v"
  "$map_dir/starlink_pss_axi_lite.v"
  axi_starlink_pss_phase_map_sync.v
  axi_starlink_pss_acquisition.v
  tb/starlink_pss_iq_to_phase_map_stub.v
  tb/tb_axi_starlink_pss_acquisition_rate.sv
)
for rate in 15 30 60; do
  iverilog -g2012 -Wall \
    -s tb_axi_starlink_pss_acquisition_rate \
    -Ptb_axi_starlink_pss_acquisition_rate.INPUT_RATE_MSPS="$rate" \
    -o "build/acquisition_rate${rate}.vvp" \
    "${common_wrapper_sources[@]}"
  vvp "build/acquisition_rate${rate}.vvp"
done

iverilog -g2012 -Wall \
  -s tb_axi_starlink_pss_acquisition_rate \
  -Ptb_axi_starlink_pss_acquisition_rate.INPUT_RATE_MSPS=25 \
  -o build/acquisition_rate_invalid.vvp \
  "${common_wrapper_sources[@]}"
if vvp build/acquisition_rate_invalid.vvp >build/acquisition_rate_invalid.log 2>&1; then
  echo "ACQUISITION_INVALID_RATE_FAIL rate 25 unexpectedly elaborated" >&2
  exit 1
fi
if ! grep -q "INPUT_RATE_MSPS must be 15, 30, or 60" \
    build/acquisition_rate_invalid.log; then
  echo "ACQUISITION_INVALID_RATE_FAIL expected guard did not fire" >&2
  exit 1
fi
echo "ACQUISITION_INVALID_RATE_PASS rejected=25"

echo "AXI_STARLINK_PSS_ACQUISITION_TESTS_PASS"
