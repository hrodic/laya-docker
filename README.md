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
- **Autonomous Release Sync & CI/CD:** Scheduled GitHub Actions watchers monitor upstream releases (`NandhaKishorM/laya`) and automatically build, tag, and publish synchronized multi-tier SemVer releases to Docker Hub with zero manual intervention.

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

## Production Example: Automated SRE Incident Triage

Demonstrating a multi-task evaluation for automated deployment rollback decisions (`choice`, `noul`, and `score`) in a single forward pass:

### Request

```bash
curl -X POST http://localhost:8000/v1/systemone \
  -H "Content-Type: application/json" \
  -d '{
    "state": "Incident Alert [SEV-2]: Canary deployment v2.14.0 in us-east-1 is failing live customer checkout transactions with error rates at 14.8%, breaching the 5% rollback threshold. Diagnostic analysis reveals an unindexed foreign-key migration locked the primary orders table, causing PostgreSQL connection pool exhaustion and 4,800ms query latency. Ingress proxies are returning 504 timeouts because container threads are blocked waiting for database connections.",
    "questions": {
      "root_cause_domain": {
        "type": "choice",
        "instructions": "Identify the primary architectural layer causing the failure cascade",
        "criteria": {
          "database": "Database table locks, unindexed schema migrations, or connection pool exhaustion",
          "network": "DNS failures, edge routing, internet transit, or load balancer faults",
          "application_code": "Memory leaks, unhandled code exceptions, or container crash loops",
          "third_party": "External vendor APIs or upstream payment gateway outages"
        }
      },
      "abort_canary_pipeline": {
        "type": "noul",
        "instructions": "Should the orchestrator execute an immediate automated canary abort due to error budget breach?"
      },
      "severity_tier": {
        "type": "score",
        "instructions": "Classify the operational severity tier based on business impact and blast radius",
        "criteria": [
          "Tier 0: Non-customer facing metric drift with no error budget impact",
          "Tier 1: Degraded non-critical auxiliary features with payment paths unaffected",
          "Tier 2: Active customer checkout failures contained within a canary deployment cohort",
          "Tier 3: Total global infrastructure outage affecting all production regions simultaneously"
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
    "root_cause_domain": {
      "type": "choice",
      "choice": "database",
      "probabilities": {
        "database": 0.8536,
        "network": 0.0305,
        "application_code": 0.0797,
        "third_party": 0.0362
      },
      "confidence": 0.5937,
      "answer_confidence": 0.8536,
      "action": {
        "act_probability": 1.0
      }
    },
    "abort_canary_pipeline": {
      "type": "noul",
      "noul": 0.9954,
      "confidence": 0.9954,
      "answer_confidence": 0.9954,
      "action": {
        "act_probability": 1.0
      }
    },
    "severity_tier": {
      "type": "score",
      "score": 1.9693,
      "legend": {
        "0": "Tier 0: Non-customer facing metric drift with no error budget impact",
        "1": "Tier 1: Degraded non-critical auxiliary features with payment paths unaffected",
        "2": "Tier 2: Active customer checkout failures contained within a canary deployment cohort",
        "3": "Tier 3: Total global infrastructure outage affecting all production regions simultaneously"
      },
      "probabilities": {
        "0": 0.0072,
        "1": 0.04,
        "2": 0.9289,
        "3": 0.0238
      },
      "confidence": 0.7677,
      "answer_confidence": 0.9289,
      "action": {
        "act_probability": 1.0
      }
    }
  },
  "usage": {
    "input_tokens": 512,
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

## Automated CI/CD & Autonomous Release Sync

The repository uses a decoupled, dual-workflow architecture to automate container releases and track upstream updates:

### 1. Upstream Watcher (`.github/workflows/check-upstream.yml`)
Runs on a scheduled cron cadence (every 4–6 hours) or via manual dispatch:
1. **Upstream Detection:** Queries GitHub Releases (`NandhaKishorM/laya`) with an automated fallback to the PyPI JSON API.
2. **Registry Delta Check:** Inspects Docker Hub's public API to determine if the detected tag already exists for `hrodicus/laya-service`.
3. **Automated Dispatch:** If a new release is detected, it triggers `docker-publish.yml` via the GitHub CLI (`gh workflow run`) with the target version. If the tag already exists, the job exits cleanly in seconds.

### 2. Builder & Publisher (`.github/workflows/docker-publish.yml`)
Triggers automatically on code pushes to `master`, via the upstream watcher, or through manual `workflow_dispatch`:
1. **SemVer Resolution:** Resolves the exact SemVer tag from inputs or PyPI metadata.
2. **Multi-Tier Tagging:** Builds and tags `:MAJOR.MINOR.PATCH`, `:MAJOR.MINOR`, and `:latest` concurrently.
3. **Layer-Cached Publication:** Compiles the air-gapped image and pushes signed layers to Docker Hub utilizing GitHub Actions cache (`type=gha`).

---

### Required Repository Configuration

1. **Docker Hub Secrets:**  
   Configure under **Settings > Secrets and variables > Actions**:
   - `DOCKERHUB_USERNAME`: Your Docker Hub registry username.
   - `DOCKERHUB_TOKEN`: Personal Access Token with read/write permissions.

2. **Workflow Permissions:**  
   To allow the upstream watcher to trigger the builder workflow, configure under **Settings > Actions > General > Workflow permissions**:
   - Select **Read and write permissions**.
   - Check **Allow GitHub Actions to create and approve pull requests** (if prompted) and save.
