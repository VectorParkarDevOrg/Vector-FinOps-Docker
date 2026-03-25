#!/usr/bin/env bash
# Pull all Vector FinOps (OptScale) images from Docker Hub and tag them as :local.
# ngui and herald are built from source to apply Vector white-label branding.
#
# Usage:
#   ./pull-images.sh                        # use default public tag
#   ./pull-images.sh 2026012001-public      # specify tag explicitly

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

REGISTRY="hystax"
TAG="${1:-2026012001-public}"

# Detect container CLI (docker or nerdctl)
if command -v docker &>/dev/null; then
  CTR=docker
elif command -v nerdctl &>/dev/null; then
  CTR=nerdctl
else
  echo "ERROR: neither docker nor nerdctl found" >&2
  exit 1
fi

# All service images pulled from Docker Hub (excludes ngui and herald — built from source)
IMAGES=(
  auth
  bi_exporter
  bi_scheduler
  booking_observer
  bumischeduler
  bumiworker
  calendar_observer
  cleaninfluxdb
  cleanmongodb
  configurator
  demo_org_cleanup
  diproxy
  diworker
  etcd
  gemini_scheduler
  gemini_worker
  grafana
  herald_executor
  influxdb
  insider_api
  insider_scheduler
  insider_worker
  jira_bus
  jira_ui
  katara_service
  katara_worker
  keeper
  keeper_executor
  layout_cleaner
  live_demo_generator
  mariadb
  metroculus_api
  metroculus_scheduler
  metroculus_worker
  mongo
  organization_violations
  power_schedule
  redis
  resource_discovery
  resource_observer
  resource_violations
  rest_api
  risp_scheduler
  risp_worker
  slacker
  slacker_executor
  subspector
  trapper_scheduler
  trapper_worker
  webhook_executor
)

echo "========================================================"
echo "  Vector FinOps — Image Setup"
echo "========================================================"
echo

# Step 1: Pull service images
echo "Step 1/2: Pulling ${#IMAGES[@]} service images from ${REGISTRY} (tag: ${TAG})..."
echo

for img in "${IMAGES[@]}"; do
  full="${REGISTRY}/${img}:${TAG}"
  echo "  pulling ${full} ..."
  $CTR pull "${full}"
  $CTR tag  "${full}" "${img}:local"
done

echo
echo "All service images pulled and tagged as :local"
echo

# Step 2: Build branded images from source
echo "Step 2/2: Building Vector-branded images from source..."
echo

cd "$REPO_ROOT"

echo "  building herald:local (Vector email logos)..."
$CTR build -t herald:local -f herald/Dockerfile . 2>&1 | grep -E "^(Step|Successfully|ERROR|error)" || true
echo "  herald:local built"

echo "  building ngui:local (Vector logo, title, translations)..."
$CTR build -t ngui:local -f ngui/Dockerfile . 2>&1 | grep -E "^(Step|Successfully|ERROR|error)" || true
echo "  ngui:local built"

echo
echo "========================================================"
echo "  Done! All images ready."
echo "  Run: cd optscale-deploy && docker compose up -d"
echo "========================================================"
