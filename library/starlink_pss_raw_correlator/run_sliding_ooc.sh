#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
output_dir="${1:-${script_dir}/build/sliding-ooc}"
vivado_bin="${VIVADO_BIN:-/opt/Xilinx/Vivado/2022.2/bin/vivado}"
vivado_compat_lib="/opt/Xilinx/Vivado/2022.2/lib/lnx64.o/SuSE"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"

if [[ ! -x "$vivado_bin" || ! -r "$vivado_compat_lib/libtinfo.so.5" ]]; then
  printf '%s\n' 'The canonical Vivado 2022.2 binary or compatibility library is unavailable.' >&2
  exit 1
fi

(
  cd "$output_dir"
  LD_LIBRARY_PATH="$vivado_compat_lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" \
  "$vivado_bin" -mode batch -nojournal -nolog \
    -source "$script_dir/synthesize_sliding_ooc.tcl" \
    -tclargs "$output_dir" 2>&1 | tee sliding_ooc_transcript.log
)
