#!/usr/bin/env bash
# Pull all workshop images to the local container daemon.
# Run this before the workshop (ideally the day before) while you still have
# a good internet connection.
#
#   bash scripts/prepull.sh
#
# Requires: docker or podman

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

# ---------------------------------------------------------------------------
# Detect container runtime
# ---------------------------------------------------------------------------
if command -v docker &>/dev/null; then
  RUNTIME=docker
elif command -v podman &>/dev/null; then
  RUNTIME=podman
else
  die "Neither docker nor podman found in PATH"
fi
info "Container runtime: $RUNTIME"

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

# ---------------------------------------------------------------------------
# Image list
# ---------------------------------------------------------------------------
IMAGES=(
  # Kind node
  "$NODE_IMAGE"

  # Mimir distributed
  "grafana/mimir:3.0.4"
  "grafana/rollout-operator:v0.32.0"
  "quay.io/minio/minio:RELEASE.2024-12-18T13-15-44Z"
  "quay.io/minio/mc:RELEASE.2024-11-21T17-21-54Z"
  "docker.io/nginxinc/nginx-unprivileged:1.29-alpine"

  # Tempo distributed
  "grafana/tempo:2.9.0"
  "memcached:1.6.39-alpine"

  # Grafana Operator + Grafana instance
  "ghcr.io/grafana/grafana-operator:v5.16.0"
  "grafana/grafana:11.3.0"

  # Coffee shop (Compose — run on host, not in Kind)
  "grafana/alloy:v1.4.0"
  "python:3.12-slim"
)

# ---------------------------------------------------------------------------
# Pull
# ---------------------------------------------------------------------------
TOTAL=${#IMAGES[@]}
FAILED=()

printf "\n${CYAN}Pulling %d images with %s${RESET}\n\n" "$TOTAL" "$RUNTIME"

for img in "${IMAGES[@]}"; do
  info "[$((${#FAILED[@]} + 1))/$TOTAL] $img"
  if $RUNTIME pull "$img"; then
    success "$img"
  else
    warn "Failed to pull $img — continuing"
    FAILED+=("$img")
  fi
  echo
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf "${CYAN}════════════════════════════════════════${RESET}\n"
if [[ ${#FAILED[@]} -eq 0 ]]; then
  printf "${GREEN}  All %d images pulled successfully.${RESET}\n" "$TOTAL"
  printf "${GREEN}  Run scripts/load-images.sh next to load them into Kind.${RESET}\n"
else
  printf "${RED}  %d image(s) failed to pull:${RESET}\n" "${#FAILED[@]}"
  for img in "${FAILED[@]}"; do
    printf "    - %s\n" "$img"
  done
  exit 1
fi
printf "${CYAN}════════════════════════════════════════${RESET}\n\n"
