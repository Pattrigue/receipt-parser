#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

OCR_IMAGE="${OCR_IMAGE:-deepseek-ocr2:latest}"
LLM_SCRIPT="${LLM_SCRIPT:-$SCRIPT_DIR/llm/run.sh}"

if [[ $# -lt 1 ]]; then
  echo "Usage: ./run.sh path/to/receipt.jpg" >&2
  exit 2
fi

IMG_HOST="$(realpath "$1")"
if [[ ! -f "$IMG_HOST" ]]; then
  echo "Input image not found: $IMG_HOST" >&2
  exit 2
fi

if [[ ! -x "$LLM_SCRIPT" ]]; then
  echo "LLM runner not executable: $LLM_SCRIPT" >&2
  echo "Run: chmod +x \"$LLM_SCRIPT\"" >&2
  exit 2
fi

WORKDIR="$(mktemp -d)"
cleanup() { rm -rf "$WORKDIR" >/dev/null 2>&1 || true; }
trap cleanup EXIT

mkdir -p "$SCRIPT_DIR/.cache" "$SCRIPT_DIR/output"

OUT_JSON="$SCRIPT_DIR/output/result.json"

echo "==> Running OCR (may download model on first run)..."
docker run --rm --gpus all \
  -v "$IMG_HOST:/input/receipt.jpg:ro" \
  -v "$WORKDIR:/work" \
  -v "$SCRIPT_DIR/.cache:/cache" \
  "$OCR_IMAGE" \
  /input/receipt.jpg /work --quiet >/dev/null
echo "==> OCR done"

OCR_TXT="$WORKDIR/ocr.txt"
if [[ ! -s "$OCR_TXT" ]]; then
  echo "OCR failed: $OCR_TXT is missing/empty" >&2
  exit 1
fi

echo "==> Running LLM..."
"$LLM_SCRIPT" "$OCR_TXT" "$OUT_JSON" >/dev/null
echo "==> LLM done: $OUT_JSON"

cat "$OUT_JSON"
echo
