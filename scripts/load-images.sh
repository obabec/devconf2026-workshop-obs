#!/usr/bin/env bash
# Load pre-pulled images into the Kind cluster.
# Run this after scripts/prepull.sh and after the Kind cluster exists.
#
#   bash scripts/load-images.sh
#
# The cluster is created automatically if it does not exist yet.
# Requires: docker or podman, kind

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RESET='\033[0m'

info()    { printf "${CYAN}▸ %s${RESET}\n" "$*"; }
success() { printf "${GREEN}✓ %s${RESET}\n" "$*"; }
warn()    { printf "${YELLOW}⚠ %s${RESET}\n" "$*"; }
die()     { printf "${RED}✗ %s${RESET}\n" "$*" >&2; exit 1; }

CLUSTER_NAME=observability

# ---------------------------------------------------------------------------
# Detect runtime and Kind provider
# ---------------------------------------------------------------------------
if command -v docker &>/dev/null; then
  RUNTIME=docker
  KIND_PROVIDER=docker
elif command -v podman &>/dev/null; then
  RUNTIME=podman
  KIND_PROVIDER=podman
else
  die "Neither docker nor podman found in PATH"
fi
info "Container runtime : $RUNTIME"
info "Kind provider     : $KIND_PROVIDER"

# ---------------------------------------------------------------------------
# Detect Kind node image from installed kind version
# ---------------------------------------------------------------------------
KIND_VERSION=$(kind version 2>/dev/null | awk '{print $2}' | tr -d 'v')
case "$KIND_VERSION" in
  0.23.*) NODE_IMAGE="kindest/node:v1.30.0" ;;
  0.24.*) NODE_IMAGE="kindest/node:v1.31.0" ;;
  0.25.*) NODE_IMAGE="kindest/node:v1.32.0" ;;
  0.26.*) NODE_IMAGE="kindest/node:v1.32.0" ;;
  0.27.*) NODE_IMAGE="kindest/node:v1.32.0" ;;
  0.28.*) NODE_IMAGE="kindest/node:v1.33.0" ;;
  0.29.*) NODE_IMAGE="kindest/node:v1.33.0" ;;
  0.3[0-9].*) NODE_IMAGE="kindest/node:v1.33.0" ;;
  *) warn "Unknown kind version '$KIND_VERSION' — defaulting to kindest/node:v1.33.0"
     NODE_IMAGE="kindest/node:v1.33.0" ;;
esac
info "Kind node image   : $NODE_IMAGE"

# ---------------------------------------------------------------------------
# Images to load into Kind
# (Compose images — alloy, python — run on the host, skip them here)
# ---------------------------------------------------------------------------
IMAGES=(
  "grafana/mimir:3.0.4"
  "grafana/rollout-operator:v0.32.0"
  "quay.io/minio/minio:RELEASE.2024-12-18T13-15-44Z"
  "quay.io/minio/mc:RELEASE.2024-11-21T17-21-54Z"
  "docker.io/nginxinc/nginx-unprivileged:1.29-alpine"
  "grafana/tempo:2.9.0"
  "memcached:1.6.39-alpine"
  "ghcr.io/grafana/grafana-operator:v5.16.0"
  "grafana/grafana:11.3.0"
)

# ---------------------------------------------------------------------------
# Ensure cluster exists
# ---------------------------------------------------------------------------
if ! kind get clusters 2>/dev/null | grep -q "^${CLUSTER_NAME}$"; then
  warn "Cluster '${CLUSTER_NAME}' not found — creating it now"
  KIND_EXPERIMENTAL_PROVIDER=$KIND_PROVIDER kind create cluster \
    --name "$CLUSTER_NAME" \
    --image "$NODE_IMAGE" \
    --config kubernetes/kind-config.yaml
  success "Cluster '${CLUSTER_NAME}' created"
else
  info "Cluster '${CLUSTER_NAME}' already exists"
fi

# ---------------------------------------------------------------------------
# Load images
# ---------------------------------------------------------------------------
TOTAL=${#IMAGES[@]}
FAILED=()

printf "\n${CYAN}Loading %d images into Kind cluster '%s'${RESET}\n\n" "$TOTAL" "$CLUSTER_NAME"

for img in "${IMAGES[@]}"; do
  info "[$((${#FAILED[@]} + 1))/$TOTAL] $img"
  if kind load docker-image "$img" --name "$CLUSTER_NAME"; then
    success "$img"
  else
    warn "Failed to load $img"
    FAILED+=("$img")
  fi
  echo
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf "${CYAN}════════════════════════════════════════${RESET}\n"
if [[ ${#FAILED[@]} -eq 0 ]]; then
  printf "${GREEN}  All %d images loaded into '%s'.${RESET}\n" "$TOTAL" "$CLUSTER_NAME"
  printf "${GREEN}  You are ready to run offline.${RESET}\n"
  printf "${GREEN}  Next step: make install${RESET}\n"
else
  printf "${RED}  %d image(s) failed to load:${RESET}\n" "${#FAILED[@]}"
  for img in "${FAILED[@]}"; do
    printf "    - %s\n" "$img"
  done
  printf "\n  Make sure you ran scripts/prepull.sh first.\n"
  exit 1
fi
printf "${CYAN}════════════════════════════════════════${RESET}\n\n"
