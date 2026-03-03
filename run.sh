#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

IMAGE="${IMAGE:-deepseek-ocr2:latest}"
INPUT_DIR="${INPUT_DIR:-$ROOT/input}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT/output}"
CACHE_DIR="${CACHE_DIR:-$ROOT/.cache}"

# If user provided an argument, use it. Otherwise, use demo image if it exists
if [[ $# -ge 1 ]]; then
  IMG="$1"
else
  IMG="$INPUT_DIR/receipt.jpg"
  if [[ ! -f "$IMG" ]]; then
    echo "No input image provided and demo image not found at: $IMG" >&2
    echo "Usage: ./run.sh path/to/receipt.jpg" >&2
    echo "Tip: put a demo image at $INPUT_DIR/receipt.jpg to run without arguments." >&2
    exit 2
  fi
fi

mkdir -p "$OUTPUT_DIR" "$CACHE_DIR"

# Make IMG absolute for mounting
IMG_ABS="$(realpath "$IMG")"

exec docker run --rm --gpus all \
  -v "$IMG_ABS:/input/receipt.jpg:ro" \
  -v "$(realpath "$OUTPUT_DIR"):/output" \
  -v "$(realpath "$CACHE_DIR"):/cache" \
  "$IMAGE" \
  /input/receipt.jpg /output
