#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
output_dir="${1:-${script_dir}/build/ooc}"
evidence_dir="${script_dir}/evidence"
mkdir -p "$output_dir"
mkdir -p "$evidence_dir"
output_dir="$(cd "$output_dir" && pwd)"
transcript="${evidence_dir}/starlink_pss_raw_correlator_vivado_transcript.log"
manifest="${evidence_dir}/starlink_pss_raw_correlator_ooc_evidence.json"

if ! command -v vivado >/dev/null 2>&1; then
  printf '%s\n' 'Vivado is not on PATH; source the Vivado 2022.2 settings first.' >&2
  exit 1
fi

(
  cd "$output_dir"
  vivado -mode batch -nojournal -nolog \
    -source "$script_dir/synthesize_ooc.tcl" \
    -tclargs "$output_dir" 2>&1 | tee "$transcript"
)

PYTHONDONTWRITEBYTECODE=1 python3 "$script_dir/write_ooc_evidence_manifest.py" \
  --output-dir "$output_dir" \
  --transcript "$transcript" \
  --manifest "$manifest"
