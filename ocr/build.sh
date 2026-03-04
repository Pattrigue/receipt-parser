#!/usr/bin/env bash
set -euo pipefail

OCR2_GIT_SHA="2f3699ebbb96fa8af32212e8c170f2cc28730fad"

docker buildx build --load -t deepseek-ocr2:latest \
  --build-arg OCR2_GIT_SHA="$OCR2_GIT_SHA" \
  .