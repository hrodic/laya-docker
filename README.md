# Laya Decision Service (Docker)

[![Docker Hub](https://img.shields.io/docker/pulls/hrodicus/laya-service?style=flat-square)](https://hub.docker.com/r/hrodicus/laya-service)
[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg?style=flat-square)](LICENSE)
[![Security](https://img.shields.io/badge/Security-Rootless_UID_10001-green.svg?style=flat-square)](#security--hardening)

A production-grade, CNCF-compliant Docker distribution for **Laya** (`convaiinnovations/laya`)—the open-weights, non-autoregressive "System One" decision model competing with TypeSafe AI's Jev.

Unlike generative LLMs that predict tokens autoregressively, Laya evaluates unstructured text against typed criteria (`choice`, `score`, `noul`) in a **single forward pass** with calibrated probabilities and zero output token generation latency.

This image packages complete model weights and runs in **100% air-gapped environments** on standard CPUs without external token authentication or runtime downloads.

---

## Highlights

- **100% Air-Gapped & Offline:** Complete model snapshots, tokenizers, and dynamic language/script subfolder checkpoints are pre-baked during build time. Operates with zero runtime network requests (`HF_HUB_OFFLINE=1`).
- **No API Tokens Required:** Weights are entirely public. No Hugging Face accounts or API tokens are needed to run inference.
- **Sub-150ms CPU Execution:** Powered by `onnxruntime` for fast matrix math on edge hardware and standard developer laptops without requiring a GPU.
- **Zero Token Generation Overhead:** Evaluates direct logit classification heads (`output_tokens: 0`), preventing prompt-injection loops and non-deterministic text generation.
- **CNCF-Compliant Hardening:** Built as a multi-stage distroless-style container running under an unprivileged user (`UID: 10001`). Stripped of build tools (`pip`, `setuptools`, `wheel`) to eliminate scanner vulnerabilities.
- **Automated SemVer CI/CD:** Integrated GitHub Actions workflow that detects PyPI releases and publishes synchronized SemVer tags to Docker Hub.

---

## API Endpoints

Once running, the microservice exposes three core endpoints:

| Method | Endpoint | Description |
| :--- | :--- | :--- |
| `GET` | `/health` | Zero-dependency healthcheck probe reporting service readiness |
| `GET` | `/docs` | Interactive OpenAPI / Swagger UI |
| `POST` | `/v1/systemone` | Decision evaluation endpoint supporting multi-task typed evaluations |

---

## Quickstart

Run the pre-built image directly from Docker Hub:

```bash
docker run -d \
  -p 8000:8000 \
  --name laya \
  --restart unless-stopped \
  hrodicus/laya-service:latest
```

Ensure you are running the newest layers:

```bash
docker run -d --pull=always -p 8000:8000 --name laya hrodicus/laya-service:latest
```

### Resource-Constrained Run (Recommended for Laptops)

Constrain memory and CPU footprints to ensure cool and predictable operation:

```bash
docker run -d \
  -p 8000:8000 \
  --cpus="2" \
  --memory="2g" \
  --name laya \
  hrodicus/laya-service:latest
```

---

## Querying the API

Laya supports three question types in a single request:
1. **`choice`**: Categorical classification across defined options (requires a `criteria` object mapping keys to descriptions).
2. **`noul`**: Binary null/non-null (true/false) activation probability.
3. **`score`**: Continuous scalar assessment (requires a `criteria` list of strings ordered from index 0 upward).

### Full 3-in-1 Request

```bash
curl -X POST http://localhost:8000/v1/systemone \
  -H "Content-Type: application/json" \
  -d '{
    "state": "The user reported an unexpected $45 charge on their invoice, demanding an immediate refund and threatening to cancel their enterprise subscription.",
    "questions": {
      "department": {
        "type": "choice",
        "instructions": "Route this ticket to the appropriate department",
        "criteria": {
          "billing": "Invoices, transactions, charge disputes, and refunds",
          "tech_support": "Software errors, crashes, and performance issues",
          "sales": "Upgrades, onboarding, and contract inquiries"
        }
      },
      "churn_risk": {
        "type": "noul",
        "instructions": "Is the customer threatening to leave or cancel their contract?"
      },
      "urgency": {
        "type": "score",
        "instructions": "Rate the urgency and frustration level of this inquiry",
        "criteria": [
          "Calm, routine inquiry with no business impact",
          "Mild frustration, standard escalation request",
          "Severe anger, demands immediate resolution under threat of cancellation"
        ]
      }
    }
  }'
```

### Response

```json
{
  "model": "laya-rl-agent",
  "answers": {
    "department": {
      "type": "choice",
      "choice": "billing",
      "probabilities": {
        "billing": 0.9441,
        "tech_support": 0.0304,
        "sales": 0.0255
      },
      "confidence": 0.7688,
      "answer_confidence": 0.9441,
      "action": {
        "act_probability": 1.0
      }
    },
    "churn_risk": {
      "type": "noul",
      "noul": 0.8112,
      "confidence": 0.8112,
      "answer_confidence": 0.8112,
      "action": {
        "act_probability": 1.0
      }
    },
    "urgency": {
      "type": "score",
      "score": 1.8006,
      "legend": {
        "0": "Calm, routine inquiry with no business impact",
        "1": "Mild frustration, standard escalation request",
        "2": "Severe anger, demands immediate resolution under threat of cancellation"
      },
      "probabilities": {
        "0": 0.0135,
        "1": 0.1724,
        "2": 0.8141
      },
      "confidence": 0.5188,
      "answer_confidence": 0.8141,
      "action": {
        "act_probability": 1.0
      }
    }
  },
  "usage": {
    "input_tokens": 217,
    "output_tokens": 0
  },
  "routing": {
    "model": "english",
    "repo": "convaiinnovations/laya",
    "reason": "English Latin text",
    "detection": {
      "script": "latin",
      "script_profile": {
        "latin": 1.0
      },
      "language": "en",
      "is_english": true,
      "language_undecided": false,
      "diacritic_rate": 0.0,
      "non_latin_fraction": 0.0
    },
    "workflow": null
  }
}
```

---

## Security & Hardening

This image follows CNCF and CIS Docker container security best practices:

- **Rootless Execution:** Runs under `UID 10001:10001` with an explicit non-login shell (`/sbin/nologin`).
- **Scrubbed Packaging Attack Surface:** Python packaging tools (`pip`, `setuptools`, `wheel`, `jaraco.context`) and their `.dist-info` metadata are completely purged from both `/opt/venv` and `/usr/local` to remediate common scanner CVE flags.
- **Embedded Health Probe:** Healthchecking runs via native Python standard library (`urllib.request`), eliminating binary injection risks associated with shipping `curl` or `wget`.
- **Signal Propagation:** The native `laya-serve` binary runs as the container entrypoint, ensuring immediate OS signal (`SIGTERM`/`SIGINT`) propagation and clean shutdown in Kubernetes pods.

---

## Local Development & Custom Builds

### 1. Standard Build (Latest PyPI release)

```bash
docker build -t laya-service:latest .
```

### 2. Pinned SemVer Build

```bash
docker build --build-arg LAYA_VERSION=0.3.20 -t laya-service:0.3.20 .
```

### 3. Check Logs & Native Health Check

```bash
# Verify log stream (startup takes <2s with no remote downloads)
docker logs -f laya

# Verify healthcheck status
docker inspect --format='{{json .State.Health.Status}}' laya
```

---

## Automated CI/CD Pipeline

The `.github/workflows/docker-publish.yml` workflow automates the container release lifecycle:

1. **Version Resolution:** Queries the PyPI JSON API on push to `main` to identify the latest released version of `laya`.
2. **Semantic Tagging:** Builds multi-tier tags (`:MAJOR.MINOR.PATCH`, `:MAJOR.MINOR`, and `:latest`).
3. **Registry Publication:** Pushes signed, verified builds to Docker Hub with GitHub Actions layer caching.

### Required Repository Secrets

Configure these under **Settings > Secrets and variables > Actions**:
- `DOCKERHUB_USERNAME`: Your Docker Hub registry username.
- `DOCKERHUB_TOKEN`: Personal Access Token with read/write access.
