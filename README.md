# devconf2026-demo

Observability escape room workshop — Grafana, Mimir, Tempo, Alloy on Kubernetes.

## Platform support

| Platform | Guide |
|----------|-------|
| OrbStack (macOS) | This file |
| Podman + Kind (Linux / macOS) | [docs/podman-traefik.md](docs/podman-traefik.md) |

---

## OrbStack setup

OrbStack ships with a built-in Kubernetes cluster and Traefik ingress.
All ingresses use the `.k8s.orb.local` DNS suffix, which resolves automatically on the Mac host.

### Prerequisites

```bash
# Homebrew tools
brew install helm kubectl

# OrbStack — https://orbstack.dev
# Enable Kubernetes in OrbStack settings
```

### Add Helm repo

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update
```

### Mimir

```bash
kubectl create namespace mimir
helm install mimir grafana/mimir-distributed \
  -n mimir \
  -f kubernetes/mimir/distributed.yaml
```

```bash
kubectl -n mimir rollout status deployment/mimir-gateway
curl -s http://mimir.k8s.orb.local/ready
```

### Tempo

```bash
kubectl create namespace tempo
helm install tempo grafana/tempo-distributed \
  -n tempo \
  --version 1.61.3 \
  -f kubernetes/tempo/distributed.yaml
```

```bash
kubectl -n tempo rollout status deployment/tempo-gateway
curl -s http://tempo-gateway.k8s.orb.local/ready
```

### Grafana Operator

```bash
kubectl create namespace grafana
helm install grafana-operator grafana/grafana-operator \
  -n grafana \
  --version 5.16.0
```

```bash
kubectl -n grafana rollout status deployment/grafana-operator-controller-manager
```

### Grafana

```bash
kubectl apply -n grafana -f kubernetes/grafana/grafana.yaml
kubectl apply -n grafana -f kubernetes/grafana/datasources.yaml
kubectl apply -n grafana -f kubernetes/grafana/coffee-shop-dashboard.yaml
```

```bash
kubectl -n grafana rollout status deployment/grafana
```

Open [http://grafana.k8s.orb.local](http://grafana.k8s.orb.local) — login `admin` / `admin`.

---

## Coffee Shop

See [coffee_shop/README.md](coffee_shop/README.md) for:

- How to find the Traefik ingress IP and configure `extra_hosts`
- Running the full stack in Docker
- Running the app from IDE while Alloy runs in Docker
- Workshop stages (escape room)

---

## Sanity tests

Quick scripts to verify Mimir and Tempo are receiving data:

```bash
cd observability-sanity-test
pip install -r requirements.txt

# Run both tests in a loop (Ctrl+C to stop)
python run.py
```

---

## Kubernetes file reference

```
kubernetes/
├── kind-config.yaml              # Kind cluster config (Podman setup)
├── mimir/
│   ├── distributed.yaml          # OrbStack (.k8s.orb.local)
│   └── distributed-podman.yaml   # Podman/Kind (.localhost)
├── tempo/
│   ├── distributed.yaml          # OrbStack
│   └── distributed-podman.yaml   # Podman/Kind
└── grafana/
    ├── grafana.yaml              # OrbStack
    ├── grafana-podman.yaml       # Podman/Kind
    ├── datasources.yaml          # Same for both (uses in-cluster FQDNs)
    ├── coffee-shop-dashboard.yaml
    └── test-dashboard.yaml
```
