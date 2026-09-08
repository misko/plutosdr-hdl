#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sample_count="${1:-1800540}"
if [[ ! "$sample_count" =~ ^[0-9]+$ ]]; then
  echo "sample count must be a positive decimal integer" >&2
  exit 1
fi
output_dir="${2:-$(mktemp -d /tmp/starlink-pilot-dwell.XXXXXX)}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
iverilog -g2012 -Wall -s tb_starlink_pilot_ddc_dwell \
  -P "tb_starlink_pilot_ddc_dwell.INPUT_COUNT=$sample_count" \
  -o "$output_dir/dwell.vvp" \
  "$script_dir/starlink_pilot_ddc.v" "$script_dir/starlink_pilot_halfband2.v" \
  "$script_dir/starlink_pilot_fir3.v" "$script_dir/tb/tb_starlink_pilot_ddc_dwell.sv"
cd "$script_dir"
vvp "$output_dir/dwell.vvp"
