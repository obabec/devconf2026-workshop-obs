# Podman + Kind Setup

Complete guide for running the observability stack on Podman with a local Kind cluster.
This is the alternative to the OrbStack setup described in the main README.

---

## Overview

| Component | Tool |
|-----------|------|
| Container runtime | Podman (rootless) |
| Kubernetes | Kind cluster with Podman driver |
| Ingress / routing | `kubectl port-forward` (no ingress controller needed) |
| Compose | `podman-compose` |

Services are exposed on fixed localhost ports — no DNS or ingress configuration needed:

| Service | URL |
|---------|-----|
| Grafana | http://localhost:3000 |
| Mimir | http://localhost:9009 |
| Tempo gateway | http://localhost:3200 |
| Coffee Shop API | http://localhost:8000/docs |
| Alloy UI | http://localhost:12345 |

---

## Prerequisites

### Fedora / RHEL

```bash
# Podman (usually pre-installed on Fedora)
sudo dnf install -y podman podman-compose

# Kind
curl -Lo kind https://kind.sigs.k8s.io/dl/v0.23.0/kind-linux-amd64
chmod +x kind && sudo mv kind /usr/local/bin/

# kubectl
curl -Lo kubectl "https://dl.k8s.io/release/$(curl -sL https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl && sudo mv kubectl /usr/local/bin/

# Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

### macOS (Podman Desktop)

```bash
brew install podman podman-compose kind kubectl helm
podman machine init
podman machine start
```

---

## 1. Create the Kind cluster

```bash
KIND_EXPERIMENTAL_PROVIDER=podman kind create cluster \
  --name observability \
  --config kubernetes/kind-config.yaml
```

Verify:

```bash
kubectl cluster-info --context kind-observability
kubectl get nodes
```

---

## 2. Install the observability stack

```bash
make install
```

This runs all the steps below automatically:
- Installs Mimir, Tempo, Grafana Operator, Grafana via Helm
- Starts port-forwards for each service
- Starts the Coffee Shop with the working Alloy config

### Manual steps (if you prefer to run them individually):

```bash
make install-deps
make install-mimir
make install-tempo
make install-grafana-operator
make install-grafana
make port-forward
make start
```

---

## 3. Port-forwards

`make install` starts port-forwards automatically. To restart them after a reboot:

```bash
make port-forward
```

To stop:

```bash
make stop-port-forward
```

Logs are written to `/tmp/pf-mimir.log`, `/tmp/pf-tempo.log`, `/tmp/pf-grafana.log`.

---

## 4. Run the Coffee Shop

```bash
make start
```

Open [http://localhost:3000](http://localhost:3000) — login `admin` / `admin`.

### Workshop (buggy config):

```bash
make challenge-1   # Traces missing
make challenge-2   # Metrics missing
make challenge-3   # Service graph empty
make challenge-4   # Inventory depletes
make reset         # Back to working state
```

---

## Alloy config reference

| File | Purpose |
|------|---------|
| `alloy/config-podman.alloy` | Working — Podman/Kind (port-forward on localhost) |
| `alloy/config-k8s.alloy` | Working — OrbStack (`.k8s.orb.local` ingress) |
| `alloy/config-challenge1.alloy` | Bug: wrong Tempo exporter type |
| `alloy/config-challenge2.alloy` | Bug: wrong Mimir endpoint, no auth header |

---

## Troubleshooting

### Port-forwards disconnect

Port-forwards can die if the pod restarts. Restart them:

```bash
make port-forward
```

### Alloy can't reach Mimir or Tempo

The Alloy container reaches the host via `observability-host` (mapped to `host-gateway` in
`docker-compose.yml`). If connections fail, verify the port-forwards are running:

```bash
curl -s http://localhost:9009/ready   # Mimir
curl -s http://localhost:3200/ready   # Tempo
```

### SELinux volume mount errors (Fedora)

Add the `:z` relabeling option to the Alloy volume in `docker-compose.yml`:

```yaml
volumes:
  - ${ALLOY_CONFIG:-./alloy/config-podman.alloy}:/etc/alloy/config.alloy:ro,z
```

### Kind cluster can't pull images

Check the Podman socket is running:

```bash
systemctl --user start podman.socket
systemctl --user enable podman.socket
```

---

## Cleanup

```bash
make uninstall
KIND_EXPERIMENTAL_PROVIDER=podman kind delete cluster --name observability
```
