#!/usr/bin/env bash
set -euo pipefail

IMG="${1:-/input/receipt.jpg}"
OUT="${2:-/work}"

# Consume IMG and OUT if provided
if (( $# >= 1 )); then shift; fi
if (( $# >= 1 )); then shift; fi

DTYPE="${DTYPE:-bf16}"
ATTN="${ATTN:-eager}"

ARGS=("$IMG" "$OUT" --dtype "$DTYPE" --attn "$ATTN")

# Only override the python default if the user explicitly set PROMPT
if [[ -n "${PROMPT:-}" ]]; then
  ARGS+=(--prompt "$PROMPT")
fi

# Forward remaining args (e.g. --quiet, --image-size 512)
ARGS+=("$@")

mkdir -p "$OUT"
exec python /app/ocr.py "${ARGS[@]}"
