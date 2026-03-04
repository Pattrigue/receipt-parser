#!/usr/bin/env bash
set -euo pipefail
docker buildx build --load -t receipt-llm:latest .