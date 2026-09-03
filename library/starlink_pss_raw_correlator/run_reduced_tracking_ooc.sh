#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
vivado_bin="/opt/Xilinx/Vivado/2022.2/bin/vivado"
compat_lib="/opt/Xilinx/Vivado/2022.2/lib/lnx64.o/SuSE"
rate_multiplier="${1:-1}"
output_dir="$script_dir/build/reduced-tracking-ooc-m${rate_multiplier}"

case "$rate_multiplier" in
  1|2|4) ;;
  *)
    echo "rate multiplier must be 1, 2, or 4" >&2
    exit 1
    ;;
esac

if [[ ! -x "$vivado_bin" ]]; then
  echo "Vivado 2022.2 not found at $vivado_bin" >&2
  exit 1
fi

mkdir -p "$output_dir"
export LD_LIBRARY_PATH="$compat_lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
exec "$vivado_bin" -mode batch -nojournal -nolog \
  -source "$script_dir/synthesize_reduced_tracking_ooc.tcl" \
  -tclargs "$output_dir" "$rate_multiplier"
