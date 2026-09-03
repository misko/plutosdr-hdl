#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
output_dir="${1:-${script_dir}/build/x2-ddc-ooc}"
vivado_bin="${VIVADO_BIN:-/opt/Xilinx/Vivado/2022.2/bin/vivado}"
compat_lib="/opt/Xilinx/Vivado/2022.2/lib/lnx64.o/SuSE"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"

if [[ ! -x "$vivado_bin" || ! -r "$compat_lib/libtinfo.so.5" ]]; then
  echo "Vivado 2022.2 or its compatibility library is unavailable" >&2
  exit 1
fi

LD_LIBRARY_PATH="$compat_lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" \
  "$vivado_bin" -mode batch -nojournal -nolog \
  -source "$script_dir/synthesize_x2_ddc_ooc.tcl" \
  -tclargs "$output_dir"
