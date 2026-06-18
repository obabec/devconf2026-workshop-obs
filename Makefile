# devconf2026-demo — Observability escape room
#
# Platform is auto-detected from the active kubeconfig context.
# Override: make PLATFORM=podman install

CURRENT_CONTEXT := $(shell kubectl config current-context 2>/dev/null)

ifeq ($(CURRENT_CONTEXT),orbstack)
  PLATFORM ?= orbstack
else ifeq ($(CURRENT_CONTEXT),kind-observability)
  PLATFORM ?= podman
else
  PLATFORM ?= orbstack
endif

ifeq ($(PLATFORM),podman)
  MIMIR_VALUES         := kubernetes/mimir/distributed-podman.yaml
  MIMIR_CHALLENGE4     := kubernetes/mimir/distributed-challenge4-podman.yaml
  TEMPO_VALUES         := kubernetes/tempo/distributed-podman.yaml
  TEMPO_CHALLENGE5     := kubernetes/tempo/distributed-challenge5-podman.yaml
  GRAFANA_CR           := kubernetes/grafana/grafana-podman.yaml
  GRAFANA_CHALLENGE4   := kubernetes/grafana/grafana-challenge4-podman.yaml
  ALLOY_WORKING        := config-podman.alloy
  ALLOY_CHALLENGE1     := config-challenge1-podman.alloy
  ALLOY_CHALLENGE2     := config-challenge2-podman.alloy
  ALLOY_CHALLENGE3     := config-challenge3-podman.alloy
  COMPOSE              := podman-compose
  GRAFANA_URL          := http://localhost:3000
else
  MIMIR_VALUES         := kubernetes/mimir/distributed.yaml
  MIMIR_CHALLENGE4     := kubernetes/mimir/distributed-challenge4.yaml
  TEMPO_VALUES         := kubernetes/tempo/distributed.yaml
  TEMPO_CHALLENGE5     := kubernetes/tempo/distributed-challenge5.yaml
  GRAFANA_CR           := kubernetes/grafana/grafana.yaml
  GRAFANA_CHALLENGE4   := kubernetes/grafana/grafana-challenge4.yaml
  ALLOY_WORKING        := config-k8s.alloy
  ALLOY_CHALLENGE1     := config-challenge1.alloy
  ALLOY_CHALLENGE2     := config-challenge2.alloy
  ALLOY_CHALLENGE3     := config-challenge3.alloy
  COMPOSE              := docker compose
  GRAFANA_URL          := http://grafana.k8s.orb.local
endif

GRAFANA_OPERATOR_VERSION := 5.16.0
TEMPO_CHART_VERSION      := 1.61.3
COFFEE_DIR               := coffee_shop

define use_alloy_config
	@printf 'ALLOY_CONFIG=./alloy/$(1)\n' > $(COFFEE_DIR)/.env
endef

# Delete datasource CRs, wait for operator to remove them from Grafana, then apply new ones.
define apply_datasources
	kubectl delete grafanadatasource -n grafana mimir tempo --ignore-not-found
	kubectl wait --for=delete grafanadatasource/mimir grafanadatasource/tempo \
	  -n grafana --timeout=60s 2>/dev/null || true
	kubectl apply -n grafana -f $(1)
endef

# Delete dashboard CR, wait for operator to remove it from Grafana, then apply new one.
define apply_dashboard
	kubectl delete grafanadashboard -n grafana coffee-shop --ignore-not-found
	kubectl wait --for=delete grafanadashboard/coffee-shop \
	  -n grafana --timeout=60s 2>/dev/null || true
	kubectl apply -n grafana -f $(1)
endef

.PHONY: prepull load-images install install-deps install-mimir install-tempo \
        install-grafana-operator install-grafana start \
        ports alloy-reload apply-datasources port-forward stop-port-forward \
        challenge-1 challenge-2 challenge-3 challenge-4 challenge-5 challenge-6 \
        reset clean uninstall help

##@ General

help: ## Show this help
	@printf '\nUsage:\n  make \033[36m<target>\033[0m\n'
	@grep -E '^##@|^[a-zA-Z_0-9-]+:.*##' $(MAKEFILE_LIST) | while IFS= read -r line; do \
	  if printf '%s' "$$line" | grep -qE '^##@'; then \
	    printf '\n\033[1m%s\033[0m\n' "$$(printf '%s' "$$line" | sed 's/^##@ //')"; \
	  else \
	    target=$$(printf '%s' "$$line" | sed 's/:.*//');\
	    desc=$$(printf '%s' "$$line" | sed 's/.*## *//');\
	    printf '  \033[36m%-22s\033[0m %s\n' "$$target" "$$desc"; \
	  fi; done
	@printf '\n  Platform : %s  (context: %s)\n' '$(PLATFORM)' '$(CURRENT_CONTEXT)'
	@printf '  Override : make PLATFORM=podman <target>\n\n'

##@ Setup

install: install-deps install-mimir install-tempo install-grafana-operator install-grafana port-forward start ## Full install: Kubernetes stack + start coffee shop
	@printf '\n\033[32m✓ Done.\033[0m\n'
	@printf '\n  Grafana        → $(GRAFANA_URL)  (admin / admin)\n'
	@printf '  App            → http://localhost:8000/docs\n'
	@printf '  Alloy UI       → http://localhost:12345\n'
	@printf '  Mimir          → http://localhost:9009   (port-forward → mimir-gateway:80)\n'
	@printf '  Tempo gateway  → http://localhost:3200   (port-forward → tempo-gateway:80)\n'
	@printf '\n  Alloy logs     : podman logs coffee-shop-alloy --follow\n\n'

prepull: ## Pull all workshop images to the local daemon (needs internet)
	bash scripts/prepull.sh

load-images: ## Load pre-pulled images into the Kind cluster (run after prepull)
	bash scripts/load-images.sh

install-deps: ## Add Helm repos (Grafana)
	helm repo add grafana https://grafana.github.io/helm-charts
	helm repo update

install-mimir: ## Install Mimir distributed
	kubectl create namespace mimir --dry-run=client -o yaml | kubectl apply -f -
	helm upgrade --install mimir grafana/mimir-distributed \
	  -n mimir -f $(MIMIR_VALUES)
	kubectl -n mimir rollout status deployment/mimir-gateway --timeout=5m

install-tempo: ## Install Tempo distributed with metrics generator
	kubectl create namespace tempo --dry-run=client -o yaml | kubectl apply -f -
	helm upgrade --install tempo grafana/tempo-distributed \
	  -n tempo --version $(TEMPO_CHART_VERSION) -f $(TEMPO_VALUES)
	kubectl -n tempo rollout status deployment/tempo-gateway --timeout=5m

install-grafana-operator: ## Install Grafana Operator (CRD controller)
	kubectl create namespace grafana --dry-run=client -o yaml | kubectl apply -f -
	helm upgrade --install grafana-operator grafana/grafana-operator \
	  -n grafana --version $(GRAFANA_OPERATOR_VERSION)
	kubectl -n grafana rollout status \
	  deployment/grafana-operator  --timeout=3m

install-grafana: ## Apply Grafana CR, datasources and dashboards
	kubectl apply -n grafana -f $(GRAFANA_CR)
	kubectl -n grafana rollout status deployment/grafana-deployment --timeout=3m
	$(call apply_datasources,kubernetes/grafana/datasources.yaml)
	$(call apply_dashboard,kubernetes/grafana/coffee-shop-dashboard.yaml)

ports: ## Show all exposed service URLs and ports
	@printf '\n  Grafana        → $(GRAFANA_URL)  (admin / admin)\n'
	@printf '  App            → http://localhost:8000/docs\n'
	@printf '  Alloy UI       → http://localhost:12345\n'
	@printf '  Mimir          → http://localhost:9009   (port-forward → mimir-gateway:80)\n'
	@printf '  Tempo gateway  → http://localhost:3200   (port-forward → tempo-gateway:80)\n'
	@printf '\n  Alloy logs     : podman logs coffee-shop-alloy --follow\n\n'

alloy-reload: ## Hot-reload Alloy config without restarting the container
	curl -X POST http://localhost:12345/-/reload

apply-datasources: ## Delete and reapply working Grafana datasources
	$(call apply_datasources,kubernetes/grafana/datasources.yaml)

start: ## Start coffee shop with the working Alloy config
	$(call use_alloy_config,$(ALLOY_WORKING))
	cd $(COFFEE_DIR) && $(COMPOSE) up --build -d

port-forward: ## (Podman) Forward Mimir, Tempo and Grafana to localhost
ifeq ($(PLATFORM),podman)
	@pkill -f 'kubectl port-forward.*mimir-gateway' 2>/dev/null || true
	@pkill -f 'kubectl port-forward.*tempo-gateway' 2>/dev/null || true
	@pkill -f 'kubectl port-forward.*grafana-service' 2>/dev/null || true
	kubectl port-forward svc/mimir-gateway   -n mimir   9009:80   &>/tmp/pf-mimir.log &
	kubectl port-forward svc/tempo-gateway   -n tempo   3200:80   &>/tmp/pf-tempo.log &
	kubectl port-forward svc/grafana-service -n grafana 3000:3000 &>/tmp/pf-grafana.log &
	@printf '\033[32m✓ Port-forwards started\033[0m  (logs: /tmp/pf-*.log)\n'
	@printf '  Mimir   → localhost:9009\n'
	@printf '  Tempo   → localhost:3200\n'
	@printf '  Grafana → localhost:3000\n'
else
	@printf 'Port-forward not needed for OrbStack (uses ingress).\n'
endif

stop-port-forward: ## (Podman) Stop port-forwards
	@pkill -f 'kubectl port-forward.*mimir-gateway'   2>/dev/null || true
	@pkill -f 'kubectl port-forward.*tempo-gateway'   2>/dev/null || true
	@pkill -f 'kubectl port-forward.*grafana-service' 2>/dev/null || true
	@printf 'Port-forwards stopped.\n'

##@ Challenges

challenge-1: ## [EASY] Traces missing — Alloy exporter type wrong for Tempo gateway
	$(call use_alloy_config,$(ALLOY_CHALLENGE1))
	cd $(COFFEE_DIR) && $(COMPOSE) up -d --no-deps alloy
	@printf '\n\033[33m→ Challenge 1 active\033[0m\n'
	@printf '  Symptom : traces no longer appear in Tempo.\n'
	@printf '  Start   : podman logs coffee-shop-alloy --follow\n\n'

challenge-2: ## [EASY] Metrics missing — wrong Mimir endpoint, no auth header
	$(call use_alloy_config,$(ALLOY_CHALLENGE2))
	cd $(COFFEE_DIR) && $(COMPOSE) up -d --no-deps alloy
	@printf '\n\033[33m→ Challenge 2 active\033[0m\n'
	@printf '  Symptom : all Grafana metric panels are empty; traces still work.\n'
	@printf '  Start   : podman logs coffee-shop-alloy --follow\n\n'

challenge-3: ## [MEDIUM] Everything looks broken — bad datasource URL + aggressive sampling
	$(call use_alloy_config,$(ALLOY_CHALLENGE3))
	cd $(COFFEE_DIR) && $(COMPOSE) up -d --no-deps alloy
	$(call apply_datasources,kubernetes/grafana/datasources-challenge3.yaml)
	@printf '\n\033[33m→ Challenge 3 active\033[0m\n'
	@printf '  Symptom : Grafana dashboards dead, almost no traces visible.\n'
	@printf '  Clue    : Alloy UI shows no errors. Mimir and Tempo are healthy.\n\n'

challenge-4: ## [MEDIUM] Correlation broken — exemplar links dead, metric timestamps shifted
	kubectl apply -n grafana -f $(GRAFANA_CHALLENGE4)
	kubectl -n grafana rollout status deployment/grafana-deployment --timeout=3m
	$(MAKE) port-forward
	$(call apply_datasources,kubernetes/grafana/datasources-challenge4.yaml)
	$(call apply_dashboard,kubernetes/grafana/coffee-shop-dashboard.yaml)
	@printf '\n\033[33m→ Challenge 4 active\033[0m\n'
	@printf '  Symptom : exemplar dots appear but clicking them does nothing; metric/trace timestamps misaligned.\n'
	@printf '  Clue    : both Mimir and Tempo are healthy; all data is there.\n\n'

challenge-5: ## [HARD] Service graph empty — Tempo metrics generator can't reach Mimir
	helm upgrade tempo grafana/tempo-distributed \
	  -n tempo --version $(TEMPO_CHART_VERSION) \
	  -f $(TEMPO_CHALLENGE5)
	kubectl -n tempo rollout status \
	  deployment/tempo-metrics-generator --timeout=3m
	$(MAKE) port-forward
	@printf '\n\033[33m→ Challenge 5 active\033[0m\n'
	@printf '  Symptom : service graph panel goes empty in ~2 minutes.\n'
	@printf '  Clue    : traces and all other metrics are fine; Alloy shows no errors.\n\n'

challenge-6: ## [HARD] Inventory depletes — reserved stock never restored on payment failure
	cp $(COFFEE_DIR)/app/services/order_buggy.py \
	   $(COFFEE_DIR)/app/services/order.py
	cd $(COFFEE_DIR) && $(COMPOSE) up --build -d --no-deps app
	@printf '\n\033[33m→ Challenge 6 active\033[0m\n'
	@printf '  Symptom : inventory_unavailable failures grow steadily over time.\n'
	@printf '  Clue    : watch the dashboard for 10+ minutes, then dig into traces.\n\n'

##@ Reset

reset: ## Restore fully working state (all config, Helm releases, datasources, app code)
	$(call use_alloy_config,$(ALLOY_WORKING))
	git checkout -- $(COFFEE_DIR)/app/services/order.py
	kubectl apply -n grafana -f $(GRAFANA_CR)
	kubectl -n grafana rollout status deployment/grafana-deployment --timeout=3m
	$(call apply_datasources,kubernetes/grafana/datasources.yaml)
	$(call apply_dashboard,kubernetes/grafana/coffee-shop-dashboard.yaml)
	helm upgrade tempo grafana/tempo-distributed \
	  -n tempo --version $(TEMPO_CHART_VERSION) -f $(TEMPO_VALUES)
	cd $(COFFEE_DIR) && $(COMPOSE) up --build -d --force-recreate
	kubectl -n tempo rollout status \
	  deployment/tempo-metrics-generator --timeout=3m
	$(MAKE) port-forward
	@printf '\n\033[32m✓ Reset complete — working state restored.\033[0m\n\n'

##@ Teardown

clean: stop-port-forward ## Stop coffee shop containers and port-forwards
	cd $(COFFEE_DIR) && $(COMPOSE) down

uninstall: clean ## Remove all Kubernetes resources
	helm uninstall grafana          -n grafana      2>/dev/null || true
	helm uninstall grafana-operator -n grafana      2>/dev/null || true
	helm uninstall tempo            -n tempo        2>/dev/null || true
	helm uninstall mimir            -n mimir        2>/dev/null || true
	kubectl delete namespace grafana mimir tempo    2>/dev/null || true
