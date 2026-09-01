#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 3 ]]; then
  printf '%s\n' \
    'usage: run_fixture_qualification.sh MANIFEST CHUNK ABSENT_RECEIPT_PATH' >&2
  exit 2
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
manifest="$1"
chunk="$2"
receipt="$3"

if ! command -v uv >/dev/null 2>&1; then
  printf '%s\n' 'uv is required for the pinned qualification environment.' >&2
  exit 1
fi

STARLINK_QUALIFICATION_UV_VERSION="$(uv --version)" \
STARLINK_QUALIFICATION_LAUNCH_POLICY="uv-run-isolated-no-project-no-config-managed-python" \
PYTHONDONTWRITEBYTECODE=1 \
uv run \
  --isolated \
  --no-project \
  --no-config \
  --managed-python \
  --python 3.13.15 \
  --with-requirements "$script_dir/qualification-requirements.txt" \
  --no-progress \
  python "$script_dir/tb/generate_real_fixture.py" \
    --verify-only \
    --manifest "$manifest" \
    --chunk "$chunk" \
    --receipt "$receipt"
