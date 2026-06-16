# Coffee Shop — Observability Escape Room

## Architecture

```
┌─────────────────────────────────────────────────┐
│ Docker Compose                                  │
│                                                 │
│  ┌─────────────┐    OTLP     ┌───────────────┐  │
│  │  coffee-shop │──────────▶ │     Alloy     │  │
│  │     app      │            │  (collector)  │  │
│  └─────────────┘            └───────┬───────┘  │
│                                     │           │
│  ┌──────────────┐                   │           │
│  │ load-generator│                  │           │
│  └──────────────┘                   │           │
└─────────────────────────────────────┼───────────┘
                                      │ traces → Tempo
                                      │ metrics → Mimir
                               ┌──────▼──────┐
                               │  Kubernetes │
                               │  (OrbStack) │
                               └─────────────┘
```

Alloy runs in Docker and needs to reach Kubernetes ingress endpoints.
Because `.k8s.orb.local` DNS only resolves on the Mac host (not inside Docker),
the hostnames must be hardcoded via `extra_hosts` in `docker-compose.yml`.

---

## Setting up extra_hosts

### 1. Find the ingress IP

The Traefik ingress controller in OrbStack exposes a single IP for all ingresses.
Run this to find it:

```bash
kubectl get ingress -A
```

Example output:
```
NAMESPACE   NAME           CLASS     HOSTS                         ADDRESS         PORTS
mimir       mimir          traefik   mimir.k8s.orb.local           192.168.139.2   80
tempo       tempo-gateway  traefik   tempo-gateway.k8s.orb.local   192.168.139.2   80
```

The `ADDRESS` column is the IP you need — all ingresses share the same Traefik IP.

### 2. Update docker-compose.yml

Edit the `extra_hosts` block in `docker-compose.yml` under the `alloy` service:

```yaml
extra_hosts:
  - "mimir.k8s.orb.local:<ADDRESS>"
  - "tempo-gateway.k8s.orb.local:<ADDRESS>"
```

Replace `<ADDRESS>` with the IP from the previous step. Example:

```yaml
extra_hosts:
  - "mimir.k8s.orb.local:192.168.139.2"
  - "tempo-gateway.k8s.orb.local:192.168.139.2"
```

This injects the entries directly into the Alloy container's `/etc/hosts`,
bypassing Docker's DNS which can't resolve OrbStack's `.k8s.orb.local` domain.

### Why this is needed

OrbStack registers `.k8s.orb.local` as a DNS domain at the macOS system level.
Docker containers run inside a Linux VM and use Docker's embedded DNS (`127.0.0.11`),
which has no knowledge of OrbStack's resolver. `network_mode: host` doesn't help
on macOS because it attaches to the VM's network stack, not the Mac's.
`extra_hosts` is the simplest reliable workaround.

---

## Running

### Full stack in Docker

```bash
cd coffee_shop
docker compose up --build
```

| Service        | URL                        |
|----------------|----------------------------|
| Coffee Shop API | http://localhost:8000/docs |
| Alloy UI        | http://localhost:12345     |

### App from IDE, infrastructure in Docker

```bash
# Start only Alloy and the load-generator
APP_URL=http://host.docker.internal:8000 docker compose up --build

# Run the app from your IDE with these environment variables:
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318
OTEL_SERVICE_NAME=coffee-shop
```

### Switching Alloy config

Two configs are provided:

| File | Purpose |
|------|---------|
| `alloy/config.alloy` | Buggy version — used for the escape room workshop |
| `alloy/config-k8s.alloy` | Working version — correct endpoints |

`config-k8s.alloy` is the default. To use the buggy one:

```bash
ALLOY_CONFIG=./alloy/config.alloy docker compose up
```

---

## Workshop stages

### Stage 1 — Traces missing
Symptom: app is running, Tempo shows nothing.

Look at `alloy/config.alloy` → `otelcol.exporter.otlp "tempo"`.
The endpoint port is wrong. Fix it to point to Tempo's OTLP HTTP endpoint.

### Stage 2 — Metrics missing
Symptom: traces work, Grafana shows no metrics.

Look at `alloy/config.alloy` → `otelcol.exporter.otlphttp "mimir"`.
The endpoint is wrong. Fix the host and port, and add the required
`X-Scope-OrgID` header.

### Stage 3 — Build a dashboard
Create a Grafana dashboard with:
- Order rate by status (`orders_created_total`)
- Failure reasons (`orders_failed_total`)
- P99/P50 order latency (`order_latency_ms`)
- P99/P50 payment latency (`payment_latency_ms`)
- Service graph (Tempo)

### Stage 4 — Find the production incident
Users report that checkout is intermittently slow.
Use the dashboard to spot the latency spike, drill into a slow trace in Tempo,
and identify which span is the bottleneck.
