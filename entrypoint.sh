#!/usr/bin/env bash
set -euo pipefail

IMG="${1:-/input/receipt.jpg}"
OUT="${2:-/output}"

DTYPE="${DTYPE:-bf16}"
ATTN="${ATTN:-eager}"

ARGS=("$IMG" "$OUT" --dtype "$DTYPE" --attn "$ATTN")

# Only override the python default if the user explicitly set PROMPT
if [[ -n "${PROMPT:-}" ]]; then
  ARGS+=(--prompt "$PROMPT")
fi

python /app/run_ocr.py "${ARGS[@]}"
