FROM nvidia/cuda:11.8.0-cudnn8-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    HF_HOME=/cache/huggingface \
    TORCH_HOME=/cache/torch \
    HF_HUB_DISABLE_TELEMETRY=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    git ca-certificates \
    python3 python3-venv python3-dev python3-pip \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

ARG OCR2_GIT_SHA=main
RUN git clone https://github.com/deepseek-ai/DeepSeek-OCR-2.git . \
 && git checkout "$OCR2_GIT_SHA"

RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

RUN pip install -U pip setuptools wheel \
 && pip install torch==2.6.0 torchvision==0.21.0 torchaudio==2.6.0 --index-url https://download.pytorch.org/whl/cu118

RUN pip install -r requirements.txt && pip install "accelerate>=0.26.0"

COPY ocr.py /app/ocr.py
COPY entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

ENTRYPOINT ["/app/entrypoint.sh"]
CMD []
