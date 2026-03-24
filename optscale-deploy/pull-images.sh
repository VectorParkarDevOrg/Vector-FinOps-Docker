#!/usr/bin/env bash
# Pull all Vector FinOps (OptScale) images from Docker Hub and tag them as :local.
# Run this on any fresh machine before starting docker compose.
#
# Usage:
#   ./pull-images.sh                        # use default public tag
#   ./pull-images.sh 2026012001-public      # specify tag explicitly

set -euo pipefail

REGISTRY="hystax"
TAG="${1:-2026012001-public}"

# All service images that the docker-compose.yml uses as :local
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
  herald
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
  ngui
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

echo "Pulling ${#IMAGES[@]} images from ${REGISTRY} (tag: ${TAG})..."
echo

for img in "${IMAGES[@]}"; do
  full="${REGISTRY}/${img}:${TAG}"
  echo "  pulling ${full} ..."
  docker pull "${full}"
  docker tag  "${full}" "${img}:local"
done

echo
echo "Done. All images tagged as :local"
echo
echo "NOTE: The ngui:local image above uses upstream OptScale branding."
echo "      For Vector branding (logo + title), rebuild ngui from source:"
echo "        cd /path/to/optscale && docker build -t ngui:local ngui/"
