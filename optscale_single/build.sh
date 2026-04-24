#!/usr/bin/env bash
# Build and run Vector FinOps single container
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
IMAGE_NAME="vectorfinops:single"

cd "$REPO_ROOT"

echo "========================================================"
echo "  Vector FinOps — Single Container Build"
echo "========================================================"
echo
echo "Build context: $REPO_ROOT"
echo "Image:         $IMAGE_NAME"
echo

case "${1:-build}" in
  build)
    echo "Building image (this takes 15-30 minutes first time)..."
    docker build -f optscale_single/Dockerfile -t "$IMAGE_NAME" .
    echo
    echo "Build complete! Image: $IMAGE_NAME"
    echo
    echo "To start: cd optscale_single && docker compose up -d"
    ;;

  start)
    cd "$SCRIPT_DIR"
    echo "Starting Vector FinOps..."
    docker compose up -d
    echo
    echo "Container starting. First boot takes 3-5 minutes for DB initialization."
    echo "Monitor progress: docker compose logs -f vectorfinops"
    echo "Access UI:        http://localhost"
    ;;

  stop)
    cd "$SCRIPT_DIR"
    docker compose down
    ;;

  restart)
    cd "$SCRIPT_DIR"
    docker compose restart
    ;;

  logs)
    cd "$SCRIPT_DIR"
    docker compose logs -f vectorfinops
    ;;

  status)
    cd "$SCRIPT_DIR"
    docker compose ps
    docker exec "$(docker compose ps -q vectorfinops)" \
      /usr/bin/supervisorctl status 2>/dev/null || echo "Container not running"
    ;;

  shell)
    cd "$SCRIPT_DIR"
    docker exec -it "$(docker compose ps -q vectorfinops)" /bin/bash
    ;;

  *)
    echo "Usage: $0 {build|start|stop|restart|logs|status|shell}"
    exit 1
    ;;
esac
