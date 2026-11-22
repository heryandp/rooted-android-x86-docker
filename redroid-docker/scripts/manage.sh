#!/usr/bin/env bash
# ==============================================================================
# manage.sh - Operational helper for Redroid + ws-scrcpy Docker stack
# ==============================================================================
set -euo pipefail

STACK_DIR="${REDROID_INSTALL_DIR:-/opt/redroid}"
if [[ ! -f "${STACK_DIR}/docker-compose.yml" ]]; then
  STACK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

cmd="${1:-help}"
shift || true

case "${cmd}" in
  start)
    cd "${STACK_DIR}" && sudo docker compose start
    ;;
  stop)
    cd "${STACK_DIR}" && sudo docker compose stop
    ;;
  restart)
    cd "${STACK_DIR}" && sudo docker compose restart
    ;;
  up)
    cd "${STACK_DIR}" && sudo docker compose up -d
    ;;
  down)
    cd "${STACK_DIR}" && sudo docker compose down
    ;;
  status)
    cd "${STACK_DIR}" && sudo docker compose ps -a
    echo ""
    sudo docker exec ws-scrcpy adb devices 2>/dev/null || echo "[INFO] ws-scrcpy is stopped"
    ;;
  stats)
    sudo docker stats --no-stream redroid ws-scrcpy
    free -h
    ;;
  logs)
    cd "${STACK_DIR}" && sudo docker compose logs -f --tail=100 "$@"
    ;;
  gsf-id)
    echo "Querying Google Services Framework (GSF) android_id..."
    adb connect 127.0.0.1:5555 >/dev/null 2>&1 || true
    adb -s 127.0.0.1:5555 root >/dev/null 2>&1 || true
    sleep 1
    adb -s 127.0.0.1:5555 shell 'sqlite3 /data/data/com.google.android.gsf/databases/gservices.db "select value from main where name=\"android_id\";"' </dev/null
    echo "Register at: https://www.google.com/android/uncertified/"
    ;;
  help|-h|--help|*)
    cat <<EOF
Usage: ./manage.sh <command>

Commands:
  start      Start stopped containers
  stop       Stop containers (frees ~1.8 GB RAM while keeping /data intact)
  restart    Restart containers
  up         Create & start containers from docker-compose.yml
  down       Stop & remove containers (keeps /data volume)
  status     Show container status and ws-scrcpy ADB connection
  stats      Show CPU/RAM usage of redroid & ws-scrcpy + host memory
  logs       Tail container logs
  gsf-id     Print GSF Android ID (for Play Protect uncertified registration)
EOF
    ;;
esac
