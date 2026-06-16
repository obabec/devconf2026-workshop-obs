# Before the conference checklist

Complete these steps **before you arrive** — ideally the day before.
Everything below requires a working internet connection.

---

## 1. Pre-pull all Docker images

### Option A — script (recommended)

```bash
bash scripts/prepull.sh
```

### Option B — manually

```bash
# Kind node (match your installed kind version — run `kind version` to check)
docker pull kindest/node:v1.33.0

# Mimir distributed
docker pull grafana/mimir:3.0.4
docker pull grafana/rollout-operator:v0.32.0
docker pull quay.io/minio/minio:RELEASE.2024-12-18T13-15-44Z
docker pull quay.io/minio/mc:RELEASE.2024-11-21T17-21-54Z
docker pull docker.io/nginxinc/nginx-unprivileged:1.29-alpine

# Tempo distributed
docker pull grafana/tempo:2.9.0
docker pull memcached:1.6.39-alpine

# Grafana Operator + Grafana instance
docker pull ghcr.io/grafana/grafana-operator:v5.16.0
docker pull grafana/grafana:11.3.0

# Coffee shop (run on host via Compose, not in Kind)
docker pull grafana/alloy:v1.4.0
docker pull python:3.12-slim
```

---

## 2. Create the Kind cluster

```bash
# Docker
kind create cluster --name observability --config kubernetes/kind-config.yaml

# Podman
KIND_EXPERIMENTAL_PROVIDER=podman kind create cluster --name observability --config kubernetes/kind-config.yaml
```

Verify:

```bash
kubectl cluster-info --context kind-observability
kubectl get nodes
# Expected: one node, STATUS = Ready
```

---

## 3. Load images into the Kind cluster

Pulling images to the local daemon is not enough — Kind runs Kubernetes inside
a container and has its own image cache. You need to load each image into it.

### Option A — script (recommended)

```bash
bash scripts/load-images.sh
```

### Option B — manually

```bash
kind load docker-image grafana/mimir:3.0.4                                    --name observability
kind load docker-image grafana/rollout-operator:v0.32.0                       --name observability
kind load docker-image quay.io/minio/minio:RELEASE.2024-12-18T13-15-44Z      --name observability
kind load docker-image quay.io/minio/mc:RELEASE.2024-11-21T17-21-54Z         --name observability
kind load docker-image docker.io/nginxinc/nginx-unprivileged:1.29-alpine      --name observability
kind load docker-image grafana/tempo:2.9.0                                    --name observability
kind load docker-image memcached:1.6.39-alpine                                --name observability
kind load docker-image ghcr.io/grafana/grafana-operator:v5.16.0               --name observability
kind load docker-image grafana/grafana:11.3.0                                 --name observability
```

> The Compose images (`alloy`, `python:3.12-slim`) run directly on the host —
> no `kind load` needed for those.

---

## 4. Add Helm repos

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

---

## 5. Verify everything is ready

```bash
# Cluster is up
kubectl get nodes

# Images are cached in Kind
docker exec observability-control-plane crictl images | grep -E "mimir|tempo|grafana|minio|memcached|nginx"

# Helm repos are present
helm repo list | grep grafana
```

---

## Day-of checklist

- [ ] `kubectl get nodes` → node is Ready
- [ ] `helm repo list` → grafana repo present
- [ ] `make install` completes without pulling new images
- [ ] `http://grafana.k8s.orb.local` (OrbStack) or `http://localhost:3000` (Podman) loads
- [ ] Coffee shop API responds at `http://localhost:8000/docs`
- [ ] Alloy UI loads at `http://localhost:12345`
