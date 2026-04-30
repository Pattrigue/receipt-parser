#!/usr/bin/env bash

docker_last_error() {
  local tmp
  tmp="$(mktemp)"
  if docker info >/dev/null 2>"$tmp"; then
    rm -f "$tmp"
    return 0
  fi
  cat "$tmp"
  rm -f "$tmp"
  return 1
}

try_start_docker() {
  if [[ -n "${DOCKER_START_CMD:-}" ]]; then
    bash -lc "$DOCKER_START_CMD" >/dev/null 2>&1 || true
    return
  fi

  if command -v systemctl >/dev/null 2>&1; then
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
      systemctl start docker.service >/dev/null 2>&1 || true
    elif command -v sudo >/dev/null 2>&1; then
      sudo -n systemctl start docker.service >/dev/null 2>&1 || true
    fi
  elif command -v service >/dev/null 2>&1 && command -v sudo >/dev/null 2>&1; then
    sudo -n service docker start >/dev/null 2>&1 || true
  elif [[ "$(uname -s)" == "Darwin" ]] && command -v open >/dev/null 2>&1; then
    open -ga Docker >/dev/null 2>&1 || true
  fi
}

ensure_docker() {
  if ! command -v docker >/dev/null 2>&1; then
    echo "Docker CLI not found. Install Docker and re-run this command." >&2
    return 1
  fi

  local err
  if err="$(docker_last_error)"; then
    return 0
  fi

  if grep -qiE "permission denied|Got permission denied" <<<"$err"; then
    echo "Docker is installed, but this user cannot access the Docker daemon." >&2
    echo "$err" >&2
    echo "Add the user to the docker group or run this command with appropriate Docker permissions." >&2
    return 1
  fi

  echo "==> Docker daemon is not reachable; trying to start Docker..."
  try_start_docker

  for _ in $(seq 1 60); do
    if docker info >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.5
  done

  echo "Docker daemon is still not reachable." >&2
  echo "$err" >&2
  echo "Start Docker manually, or set DOCKER_START_CMD to the command that starts Docker on this machine." >&2
  return 1
}

docker_gpu_args() {
  read -r -a DOCKER_GPU_ARGS_ARR <<< "${DOCKER_GPU_ARGS:---gpus all}"

  if [[ "${DOCKER_ADD_NVIDIA_DEVICES:-auto}" == "0" || "${DOCKER_ADD_NVIDIA_DEVICES:-auto}" == "false" ]]; then
    return
  fi

  local dev
  local devices=(
    /dev/nvidiactl
    /dev/nvidia-uvm
    /dev/nvidia-uvm-tools
  )

  shopt -s nullglob
  for dev in /dev/nvidia[0-9]*; do
    devices+=("$dev")
  done
  shopt -u nullglob

  for dev in "${devices[@]}"; do
    if [[ -e "$dev" ]]; then
      DOCKER_GPU_ARGS_ARR+=(--device "$dev")
    fi
  done
}

check_image_gpu() {
  local image="$1"

  docker_gpu_args
  if ! docker run --rm "${DOCKER_GPU_ARGS_ARR[@]}" --entrypoint nvidia-smi "$image" >/dev/null; then
    echo "Docker is running, but GPUs are not available inside containers." >&2
    echo "Install/configure the NVIDIA Container Toolkit and verify: docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi" >&2
    return 1
  fi
}

check_image_torch_cuda() {
  local image="$1"
  local err
  local tmp

  docker_gpu_args
  tmp="$(mktemp)"
  if docker run --rm "${DOCKER_GPU_ARGS_ARR[@]}" --entrypoint python3 "$image" -c 'import torch; raise SystemExit(0 if torch.cuda.is_available() else 1)' 2>"$tmp"; then
    rm -f "$tmp"
    return 0
  fi

  err="$(cat "$tmp")"
  rm -f "$tmp"
  echo "Docker can expose the GPU, but PyTorch inside $image cannot initialize CUDA." >&2
  if [[ -n "$err" ]]; then
    echo "$err" >&2
  fi
  echo "Rebuild the OCR image with ./ocr/build.sh, then retry." >&2
  return 1
}
