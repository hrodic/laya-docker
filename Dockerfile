# Author: hrodic
# ==========================================
# Stage 1: Build & Dependency Wheel Cache
# ==========================================
FROM python:3.11-slim AS builder

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

ARG LAYA_VERSION=""

WORKDIR /build

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Create virtual environment and upgrade core packaging tools immediately
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install --upgrade pip setuptools wheel

# Install dependencies conditionally
RUN if [ -z "$LAYA_VERSION" ]; then \
        pip install --no-cache-dir laya onnxruntime uvicorn fastapi; \
    else \
        pip install --no-cache-dir "laya==${LAYA_VERSION}" onnxruntime uvicorn fastapi; \
    fi

# Pre-download and cache all sub-checkpoints for 100% standalone execution
RUN mkdir -p /opt/models/huggingface
ENV HF_HOME=/opt/models/huggingface
RUN python -c "from laya import Router; r = Router(); r.predict(state='warmup', questions={'q': {'type': 'noul', 'instructions': 'warmup'}})"

# REMEDIATION: Strip build-only tooling from the venv so scanners don't flag them
RUN pip uninstall -y pip setuptools wheel jaraco.context 2>/dev/null || true

# ==========================================
# Stage 2: Minimal Distro Runtime
# ==========================================
FROM python:3.11-slim AS runner

LABEL org.opencontainers.image.title="laya-decision-service" \
      org.opencontainers.image.description="Non-autoregressive decision model microservice" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.documentation="https://github.com/NandhaKishorM/laya"

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH" \
    HF_HOME=/opt/models/huggingface

# REMEDIATION: Patch Debian base packages (resolves zlib and perl CVEs)
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Dedicated unprivileged user/group
RUN groupadd -g 10001 appgroup && \
    useradd -u 10001 -g appgroup -s /sbin/nologin -M appuser

WORKDIR /app

# Copy virtual environment and model cache
COPY --from=builder --chown=10001:10001 /opt/venv /opt/venv
COPY --from=builder --chown=10001:10001 /opt/models /opt/models

USER 10001:10001

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health')" || exit 1

ENTRYPOINT ["laya-serve"]
CMD ["--host", "0.0.0.0", "--port", "8000", "--device", "cpu"]
