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

# Install minimal build tools required for C-extensions/bindings
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Create a clean virtual environment
RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Install dependencies conditionally based on build arguments
RUN if [ -z "$LAYA_VERSION" ]; then \
        pip install --no-cache-dir laya onnxruntime uvicorn fastapi; \
    else \
        pip install --no-cache-dir "laya==${LAYA_VERSION}" onnxruntime uvicorn fastapi; \
    fi

# Guarantee the models directory exists before attempting to download
RUN mkdir -p /opt/models/huggingface
ENV HF_HOME=/opt/models/huggingface

# Pre-download and cache model weights into the isolated folder
# Forces Laya to resolve the script detectors, download all 3 sub-checkpoints, and store them into /opt/models/huggingface making it 100% standalone.
RUN python -c "from laya import Router; r = Router(); r.predict(state='warmup', questions={'q': {'type': 'noul', 'instructions': 'warmup'}})"

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

# Create dedicated non-root service user and group (UID/GID 10001)
RUN groupadd -g 10001 appgroup && \
    useradd -u 10001 -g appgroup -s /sbin/nologin -M appuser

WORKDIR /app

# Copy virtualenv and model weights using raw UIDs (CNCF Best Practice)
COPY --from=builder --chown=10001:10001 /opt/venv /opt/venv
COPY --from=builder --chown=10001:10001 /opt/models /opt/models

# Run under least privilege
USER 10001:10001

EXPOSE 8000

# Zero-dependency Python healthcheck bound to the verified /health route
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health')" || exit 1

# Start Laya server with signal propagation
ENTRYPOINT ["laya-serve"]
CMD ["--host", "0.0.0.0", "--port", "8000", "--device", "cpu"]
