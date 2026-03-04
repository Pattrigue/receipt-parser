#!/usr/bin/env bash
set -euo pipefail

LLM_IMAGE="${LLM_IMAGE:-receipt-llm:latest}"
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen2.5:14b-instruct}"
OLLAMA_VOL="${OLLAMA_VOL:-receipt-ollama}"

if [[ $# -lt 2 ]]; then
  echo "Usage: llm/run.sh path/to/ocr.txt path/to/output.json" >&2
  exit 2
fi

OCR_TXT_HOST="$(realpath "$1")"
OUT_HOST="$(realpath -m "$2")"

if [[ ! -f "$OCR_TXT_HOST" ]]; then
  echo "OCR text file not found: $OCR_TXT_HOST" >&2
  exit 2
fi

mkdir -p "$(dirname "$OUT_HOST")"

CONTAINER_NAME="receipt-ollama-$$"

cleanup() {
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Persistent model cache volume (so model download happens once)
docker volume inspect "$OLLAMA_VOL" >/dev/null 2>&1 || docker volume create "$OLLAMA_VOL" >/dev/null

# Start Ollama server for this run
docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
docker run -d --rm --name "$CONTAINER_NAME" --gpus all \
  -v "${OLLAMA_VOL}:/root/.ollama" \
  -v "${OCR_TXT_HOST}:/work/ocr.txt:ro" \
  "${LLM_IMAGE}" >/dev/null

echo "==> Starting Ollama (cold start may take ~1-2 minutes)..."
for _ in $(seq 1 600); do
  if docker exec "$CONTAINER_NAME" ollama list >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done
docker exec "$CONTAINER_NAME" ollama list >/dev/null 2>&1 || { echo "Ollama not ready" >&2; exit 1; }
echo "==> Ollama ready"

# Pull model if missing (cached in volume)
if ! docker exec "$CONTAINER_NAME" ollama show "$OLLAMA_MODEL" >/dev/null 2>&1; then
  echo "==> Pulling LLM model (first run only): $OLLAMA_MODEL"
  docker exec -it "$CONTAINER_NAME" ollama pull "$OLLAMA_MODEL"
  echo "==> Model pulled"
fi

echo "==> Generating JSON with LLM..."
JSON_OUT="$(docker exec "$CONTAINER_NAME" python3 /app/llm.py /work/ocr.txt --model "$OLLAMA_MODEL")"
echo "==> Done"

if [[ -z "$JSON_OUT" ]]; then
  echo "LLM produced empty output" >&2
  exit 1
fi

printf "%s\n" "$JSON_OUT" > "$OUT_HOST"
echo "==> Wrote JSON to: $OUT_HOST"
