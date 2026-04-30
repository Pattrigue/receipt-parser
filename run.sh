#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

OCR_IMAGE="${OCR_IMAGE:-deepseek-ocr2:latest}"
LLM_SCRIPT="${LLM_SCRIPT:-$SCRIPT_DIR/llm/run.sh}"

# shellcheck source=lib/docker.sh
source "$SCRIPT_DIR/lib/docker.sh"

usage() {
  echo "Usage: ./run.sh [--force] path/to/receipt.jpg|directory" >&2
}

FORCE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force)
      FORCE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage
      exit 2
      ;;
    *)
      break
      ;;
  esac
done

if [[ $# -ne 1 ]]; then
  usage
  exit 2
fi

INPUT_HOST="$(realpath "$1")"
if [[ ! -f "$INPUT_HOST" && ! -d "$INPUT_HOST" ]]; then
  echo "Input not found: $INPUT_HOST" >&2
  exit 2
fi

if [[ ! -x "$LLM_SCRIPT" ]]; then
  echo "LLM runner not executable: $LLM_SCRIPT" >&2
  echo "Run: chmod +x \"$LLM_SCRIPT\"" >&2
  exit 2
fi

mkdir -p "$SCRIPT_DIR/.cache"

ensure_docker
check_image_gpu "$OCR_IMAGE"
check_image_torch_cuda "$OCR_IMAGE"
docker_gpu_args

is_supported_image() {
  case "${1,,}" in
    *.jpg|*.jpeg|*.png|*.webp|*.tif|*.tiff) return 0 ;;
    *) return 1 ;;
  esac
}

json_for_image() {
  local image="$1"
  local dir
  local file
  dir="$(dirname "$image")"
  file="$(basename "$image")"
  printf "%s/%s.json\n" "$dir" "${file%.*}"
}

parse_image() {
  local img_host="$1"
  local out_json="$2"
  local workdir
  local ocr_txt

  workdir="$(mktemp -d)"
  trap 'rm -rf "$workdir" >/dev/null 2>&1 || true' RETURN

  echo "==> Processing: $img_host"
  echo "==> Running OCR (may download model on first run)..."
  if ! docker run --rm "${DOCKER_GPU_ARGS_ARR[@]}" \
    -v "$img_host:/input/receipt.jpg:ro" \
    -v "$workdir:/work" \
    -v "$SCRIPT_DIR/.cache:/cache" \
    "$OCR_IMAGE" \
    /input/receipt.jpg /work --quiet >/dev/null; then
    echo "OCR container failed: $img_host" >&2
    return 1
  fi
  echo "==> OCR done"

  ocr_txt="$workdir/ocr.txt"
  if [[ ! -s "$ocr_txt" ]]; then
    echo "OCR failed: $ocr_txt is missing/empty" >&2
    return 1
  fi

  echo "==> Running LLM..."
  if ! "$LLM_SCRIPT" "$ocr_txt" "$out_json" >/dev/null; then
    echo "LLM failed: $img_host" >&2
    return 1
  fi
  echo "==> Wrote JSON: $out_json"
  echo
}

if [[ -f "$INPUT_HOST" ]]; then
  if ! is_supported_image "$INPUT_HOST"; then
    echo "Unsupported image type: $INPUT_HOST" >&2
    exit 2
  fi

  parse_image "$INPUT_HOST" "$(json_for_image "$INPUT_HOST")"
  exit $?
fi

processed=0
skipped=0
failed=0
found=0

while IFS= read -r -d '' img_host; do
  found=$((found + 1))
  out_json="$(json_for_image "$img_host")"

  if [[ -e "$out_json" && "$FORCE" -eq 0 ]]; then
    echo "==> Skipping existing: $out_json"
    skipped=$((skipped + 1))
    continue
  fi

  if parse_image "$img_host" "$out_json"; then
    processed=$((processed + 1))
  else
    echo "Failed: $img_host" >&2
    failed=$((failed + 1))
  fi
done < <(
  find "$INPUT_HOST" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.tif' -o -iname '*.tiff' \) \
    -print0 | sort -z
)

if [[ "$found" -eq 0 ]]; then
  echo "No supported images found in: $INPUT_HOST" >&2
  exit 1
fi

echo "==> Summary: processed=$processed skipped=$skipped failed=$failed"
if [[ "$failed" -gt 0 ]]; then
  exit 1
fi
