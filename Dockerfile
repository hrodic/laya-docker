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

# Create virtual environment and upgrade core tools for clean compilation
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install --upgrade pip setuptools wheel

# Install dependencies conditionally
RUN if [ -z "$LAYA_VERSION" ]; then \
        pip install --no-cache-dir laya onnxruntime uvicorn fastapi; \
    else \
        pip install --no-cache-dir "laya==${LAYA_VERSION}" onnxruntime uvicorn fastapi; \
    fi

# FIX 1: Pre-download 100% of the repository (all subfolders & checkpoints)
# Eliminates all runtime Hugging Face downloads without executing model code
RUN mkdir -p /opt/models/huggingface
ENV HF_HOME=/opt/models/huggingface
RUN python -c "from huggingface_hub import snapshot_download; snapshot_download(repo_id='convaiinnovations/laya')"

# FIX 2: Strip packaging tooling and build artifacts from virtualenv
RUN pip uninstall -y pip setuptools wheel 2>/dev/null || true
RUN rm -rf /opt/venv/lib/python3.11/site-packages/pip* \
           /opt/venv/lib/python3.11/site-packages/setuptools* \
           /opt/venv/lib/python3.11/site-packages/wheel* \
           /opt/venv/lib/python3.11/site-packages/jaraco* \
           /opt/venv/bin/pip*

# ==========================================
# Stage 2: Hardened Minimal Distro Runtime
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

# FIX 3: Patch Debian libraries and purge global python base image packaging tools
RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get autoremove -y && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* \
           /usr/local/lib/python3.11/site-packages/pip* \
           /usr/local/lib/python3.11/site-packages/setuptools* \
           /usr/local/lib/python3.11/site-packages/wheel* \
           /usr/local/lib/python3.11/site-packages/jaraco* \
           /usr/local/bin/pip* \
           /usr/local/bin/wheel*

# Dedicated unprivileged user/group (UID/GID 10001)
RUN groupadd -g 10001 appgroup && \
    useradd -u 10001 -g appgroup -s /sbin/nologin -M appuser

WORKDIR /app

# Copy virtual environment and model cache using explicit numeric IDs
COPY --from=builder --chown=10001:10001 /opt/venv /opt/venv
COPY --from=builder --chown=10001:10001 /opt/models /opt/models

USER 10001:10001

EXPOSE 8000

# Zero-dependency Python healthcheck bound to the verified /health route
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health')" || exit 1

ENTRYPOINT ["laya-serve"]
CMD ["--host", "0.0.0.0", "--port", "8000", "--device", "cpu"]
