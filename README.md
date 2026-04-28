# AI DevOps Incident Response Agent

Production SRE Copilot is a multi-agent incident-response service for telemetry ingestion, anomaly detection, root-cause analysis, safe Kubernetes remediation, feedback capture, and incident memory.

## Architecture

```text
Prometheus / ELK / API / Simulator
              |
              v
      Monitoring Agent
      - normalizes logs and metrics
      - builds service feature windows
              |
              v
  Anomaly Detection Agent
  - guardrail thresholds
  - EWMA + z-score drift
  - Isolation Forest when baseline is warm
              |
              v
 Root Cause Analysis Agent <---- Chroma / JSON Vector Memory
 - Google Gemini structured JSON RCA
 - correlates logs, metrics, and similar incidents
              |
              v
        Action Agent
        - Gemini action planning
        - independent safety validation
        - Kubernetes scale/restart/rollback
        - dry-run by default
              |
              v
       Feedback Agent
       - MTTR and outcome scoring
              |
              v
       Memory Update
       - stores logs, RCA, action, and outcome
```

Mandatory flow is implemented in `src/sre_copilot/orchestrator.py`:

```text
logs/metrics -> anomaly detection -> RCA -> action -> feedback -> memory update
```

The orchestration layer uses LangGraph when installed and falls back to the same linear graph for local smoke tests if LangGraph is unavailable.

## What Is Implemented

- FastAPI endpoints: `POST /ingest`, `GET /incident`, `POST /incident`, `GET /status`, `GET /metrics`
- Monitoring agent for API, Prometheus-style, ELK-style, and simulator telemetry payloads
- Real anomaly detection with absolute SRE guardrails, EWMA/z-score drift detection, and Isolation Forest after baseline warmup
- Google Gemini API wrapper using structured JSON outputs for RCA and action planning
- Chroma vector memory with deterministic embeddings, plus JSON fallback for constrained local environments
- Kubernetes actions: scale deployment, rollout restart, rollout undo
- Safety gates: dry-run default, namespace allowlist, confidence threshold, replica bounds, non-destructive action whitelist
- Rollback metadata and scale rollback support
- Prometheus metrics for detection latency, MTTR, incident count, and automated fixes
- Local simulator for high CPU and crash-loop incidents
- Dockerfile and Kubernetes deployment/service/RBAC manifests

Gemini structured output follows the official Google AI documentation: [Structured outputs | Gemini API](https://ai.google.dev/gemini-api/docs/structured-output).

## Setup

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
pip install -r requirements.txt
Copy-Item .env.example .env
```

Edit `.env`:

```text
GEMINI_API_KEY=your-real-key
GEMINI_OFFLINE_MODE=false
DRY_RUN=true
K8S_NAMESPACE=default
K8S_DEFAULT_DEPLOYMENT=checkout-api
```

For local testing without a Gemini key, set:

```text
GEMINI_OFFLINE_MODE=true
```

Production should use Gemini mode with `GEMINI_API_KEY` set.

## Run Locally

```powershell
$env:PYTHONPATH="src"
uvicorn sre_copilot.api:app --host 0.0.0.0 --port 8000 --reload
```

Check health:

```powershell
Invoke-RestMethod http://localhost:8000/status
```

Trigger the mandatory high-CPU demo:

```powershell
Invoke-RestMethod `
  -Method Post `
  -Uri http://localhost:8000/incident `
  -ContentType "application/json" `
  -Body '{"scenario":"high_cpu","service":"checkout-api","environment":"local"}'
```

Trigger the crash-loop demo:

```powershell
Invoke-RestMethod `
  -Method Post `
  -Uri http://localhost:8000/incident `
  -ContentType "application/json" `
  -Body '{"scenario":"service_crash","service":"checkout-api","environment":"local"}'
```

Run the CLI demo:

```powershell
$env:PYTHONPATH="src"
python scripts/run_demo.py --scenario high_cpu --offline-llm
```

The demo warms the baseline with normal traffic, sends a high-CPU event, detects the anomaly, creates RCA, plans a scale-out action, validates safety, records dry-run outcome, and stores the incident in memory.

## API Payload

`POST /ingest` accepts normalized telemetry:

```json
{
  "source": "api",
  "environment": "prod",
  "logs": [
    {
      "service": "checkout-api",
      "level": "ERROR",
      "message": "request timeout after 3000ms route=/checkout"
    }
  ],
  "metrics": [
    {
      "service": "checkout-api",
      "name": "cpu_pct",
      "value": 96.4,
      "unit": "%"
    },
    {
      "service": "checkout-api",
      "name": "latency_ms",
      "value": 2180,
      "unit": "ms"
    }
  ]
}
```

## Kubernetes Deployment

Build and deploy:

```powershell
docker build -t sre-copilot:0.1.0 .
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/secret.example.yaml
kubectl apply -f k8s/rbac.yaml
kubectl apply -f k8s/deployment.yaml
kubectl apply -f k8s/service.yaml
```

Keep `DRY_RUN=true` until the namespace allowlist, default deployment, RBAC, and rollback procedures are verified. To enable mutations, set `DRY_RUN=false` in `k8s/deployment.yaml`.

## Safety Model

The LLM can recommend actions, but it cannot directly execute them. `ActionAgent` revalidates every plan:

- action type must be in the allowlist
- anomaly and action confidence must exceed thresholds
- namespace must be explicitly allowed
- replica targets must be inside policy limits
- Kubernetes resource names must be valid
- destructive operations are not implemented

## Tests

```powershell
$env:PYTHONPATH="src"
pytest
```

## Production Notes

- Use a persistent volume for `/app/data` so baseline and Chroma memory survive pod restarts.
- Wire real Prometheus/ELK collectors to `POST /ingest`, or add a poller process that converts upstream telemetry into `IngestPayload`.
- Keep `AUTO_ACTION_ENABLED=false` during initial shadow mode if your SRE team wants RCA-only behavior.
- Export `/metrics` to Prometheus and alert on failed actions, rising MTTR, or low-confidence RCA rates.
