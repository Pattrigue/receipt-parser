#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Building OCR image..."
( cd "$ROOT/ocr" && ./build.sh )
echo "==> OCR build done"

echo "==> Building LLM image..."
( cd "$ROOT/llm" && ./build.sh )
echo "==> LLM build done"
