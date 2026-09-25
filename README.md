# laya-docker
Laya System One decision model (docker)

A CNCF-compliant Docker distribution for **Laya** (`convaiinnovations/laya`)—the open-weights, non-autoregressive "System One" decision model competing with TypeSafe AI's Jev.

Unlike generative LLMs that predict tokens autoregressively, Laya evaluates unstructured text against typed criteria (`choice`, `score`, `noul`) in a **single forward pass** with calibrated probabilities and zero output token latency.

This repository provides a multi-stage, non-root, CPU-optimized container ready to serve predictions locally or in container orchestration platforms.

---

## Features

- **CPU-First Optimization:** Built using `onnxruntime` for fast inference (sub-150ms) on standard laptop processors without GPU overhead.
- **Zero Token Generation:** Direct classification heads yielding deterministic, calibrated decisions with 0 output tokens.
- **CNCF-Compliant Security:** Multi-stage build running under an unprivileged user (`UID: 10001`) with zero build tools in the final image.
- **Pre-cached Weights:** Base models are pre-cached during build time, ensuring the container boots instantly offline.
- **Automated SemVer Publishing:** GitHub Actions pipeline to detect, pin, and publish SemVer-tagged images directly to Docker Hub.

---

## API Endpoints

Once running, the microservice exposes two primary endpoints:

| Method | Endpoint | Description |
| :--- | :--- | :--- |
| `GET` | `/health` | Healthcheck endpoint reporting service readiness |
| `GET` | `/docs` | Interactive Swagger API documentation |
| `POST` | `/v1/systemone` | Decision evaluation endpoint (Jev-compatible format) |

---

## Local Development & Build

### 1. Build Automatically (Latest Version from PyPI)
Builds the container using whatever is the newest release of `laya`:

```bash
docker build -t laya-service:latest .
```

### 2. Build with an Explicit Version (Reproducible SemVer)
Pass the `LAYA_VERSION` build argument to freeze a specific library release:

```bash
docker build --build-arg LAYA_VERSION=0.3.20 -t laya-service:0.3.20 .
```

*(Optional)* Bypass Hugging Face anonymous download rate limits by passing a token during build:

```bash
docker build --build-arg HF_TOKEN=hf_your_token_here -t laya-service:latest .
```

---

## Running the Container

### Basic Run (Localhost on Port 8000)
```bash
docker run -d -p 8000:8000 --name laya laya-service:latest
```

### CPU-Constrained Run (Recommended for Laptops)
To keep your laptop cool and prevent full CPU utilization:

```bash
docker run -d \
  -p 8000:8000 \
  --cpus="2" \
  --memory="2g" \
  --name laya \
  laya-service:latest
```

### Check Logs & Health Status
```bash
# View startup logs
docker logs -f laya

# Inspect Docker's native healthcheck status
docker inspect --format='{{json .State.Health.Status}}' laya
```

---

## Quickstart Query Example

Send a typed decision request using `curl`:

```bash
curl -X POST http://localhost:8000/v1/systemone \
  -H "Content-Type: application/json" \
  -d '{
    "state": "The app crashes when clicking settings.",
    "questions": {
      "department": {
        "type": "choice",
        "instructions": "Which department handles this?",
        "criteria": {
          "billing": "Invoices and subscriptions",
          "tech_support": "Crashes and software bugs"
        }
      },
      "is_bug": {
        "type": "noul",
        "instructions": "Is this a bug report?"
      }
    }
  }'
```

### Example Response

```json
{
  "model": "laya-rl-agent",
  "answers": {
    "department": {
      "type": "choice",
      "choice": "tech_support",
      "probabilities": {
        "billing": 0.0975,
        "tech_support": 0.9025
      },
      "confidence": 0.5389,
      "answer_confidence": 0.9025,
      "action": {
        "act_probability": 1.0
      }
    },
    "is_bug": {
      "type": "noul",
      "noul": 0.8482,
      "confidence": 0.8482,
      "answer_confidence": 0.8482,
      "action": {
        "act_probability": 1.0
      }
    }
  },
  "usage": {
    "input_tokens": 77,
    "output_tokens": 0
  },
  "routing": {
    "model": "english",
    "repo": "convaiinnovations/laya",
    "reason": "English Latin text"
  }
}
```

---

## CI/CD Pipeline (GitHub Actions)

This repository includes an automated workflow at `.github/workflows/docker-publish.yml`:

1. **Automatic Inspection:** On every push to `main` (or `master`), the pipeline queries PyPI for the newest published release of `laya`.
2. **SemVer Multi-Tagging:** Automatically tags and pushes `:MAJOR.MINOR.PATCH`, `:MAJOR.MINOR`, and `:latest` to Docker Hub.
3. **Manual Trigger:** Supports running manual builds with custom version overrides via the GitHub Actions **"Run workflow"** UI.

### Required GitHub Secrets
To use automated publishing, configure these in **Settings > Secrets and variables > Actions**:
- `DOCKERHUB_USERNAME`: Your Docker Hub username.
- `DOCKERHUB_TOKEN`: A Personal Access Token (Read & Write) from Docker Hub.
