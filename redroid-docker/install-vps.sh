#!/usr/bin/env bash
# ==============================================================================
# install-vps.sh - Automated Redroid (Android 12 + Magisk + GApps + ARM64)
#                  + ws-scrcpy + Docker Compose Installer for Ubuntu/Debian VPS
#
# Works on standard KVM Linux VPS WITHOUT nested virtualization (/dev/kvm not needed).
# Tested on Ubuntu 24.04 LTS (Linux kernel 6.8 with binderfs + memfd).
# ==============================================================================
set -euo pipefail

INSTALL_DIR="${REDROID_INSTALL_DIR:-/opt/redroid}"
VARIANT="full"         # full (GApps+libndk+Magisk) | lite (libndk+Magisk) | vanilla
EXPOSE_NGINX=0
PUBLIC_PORT=8000
INTERNAL_WS_PORT=18000
REDROID_MEM="2560m"
REDROID_WIDTH=720
REDROID_HEIGHT=1280
REDROID_DPI=320
REDROID_FPS=24

usage() {
  cat <<EOF
Usage: ./install-vps.sh [OPTIONS]

Options:
  --dir <path>         Installation directory (default: ${INSTALL_DIR})
  --full               Android 12 (64only) + MindTheGapps + libndk + Magisk (default)
  --lite               Android 12 (64only) + libndk + Magisk (no GApps, lower RAM)
  --vanilla            Official redroid:12.0.0_64only-latest (fastest, no build step)
  --mem <limit>        Redroid RAM limit (default: ${REDROID_MEM})
  --fps <N>            Target FPS (default: ${REDROID_FPS})
  --expose-nginx       Also configure Nginx reverse proxy with HTTP Basic Auth on port 8000
  --port <N>           Public Nginx port when using --expose-nginx (default: ${PUBLIC_PORT})
  -h, --help           Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) INSTALL_DIR="$2"; shift 2 ;;
    --full) VARIANT="full"; shift ;;
    --lite) VARIANT="lite"; shift ;;
    --vanilla) VARIANT="vanilla"; shift ;;
    --mem) REDROID_MEM="$2"; shift 2 ;;
    --fps) REDROID_FPS="$2"; shift 2 ;;
    --expose-nginx) EXPOSE_NGINX=1; shift ;;
    --port) PUBLIC_PORT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[ERROR] Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "============================================================"
echo "  Redroid Android 12 + ws-scrcpy VPS Installer"
echo "  Install Dir : ${INSTALL_DIR}"
echo "  Variant     : ${VARIANT}"
echo "  RAM Limit   : ${REDROID_MEM}"
echo "============================================================"

step "1/6 Checking kernel & enabling binder_linux module"
if ! modinfo binder_linux >/dev/null 2>&1; then
  echo "Installing linux-modules-extra-$(uname -r) for binder_linux..."
  sudo apt-get update -qq
  sudo apt-get install -y "linux-modules-extra-$(uname -r)"
fi

sudo modprobe binder_linux devices="binder,hwbinder,vndbinder"
echo 'binder_linux' | sudo tee /etc/modules-load.d/redroid.conf >/dev/null
echo 'options binder_linux devices="binder,hwbinder,vndbinder"' | sudo tee /etc/modprobe.d/redroid.conf >/dev/null

if grep -qE '[[:space:]]binder$' /proc/filesystems || [[ -e /dev/binder ]]; then
  ok "binder_linux loaded and persisted across reboots"
else
  echo "[ERROR] binder filesystem did not register. Check kernel support for CONFIG_ANDROID_BINDERFS." >&2
  exit 1
fi

step "2/6 Installing host prerequisites (Docker, ADB, build tools)"
sudo apt-get update -qq
sudo apt-get install -y -qq curl git unzip lzip python3-requests python3-tqdm android-tools-adb

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker not found; installing Docker Engine via official get.docker.com script..."
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "${USER}" || true
fi
ok "Docker ready: $(docker --version)"

step "3/6 Preparing ${INSTALL_DIR} directory"
sudo mkdir -p "${INSTALL_DIR}/data"
sudo chown -R "${USER}:${USER}" "${INSTALL_DIR}"

step "4/6 Building/pulling Redroid Android 12 image (${VARIANT})"
case "${VARIANT}" in
  full)
    REDROID_IMAGE="redroid/redroid:12.0.0_64only_mindthegapps_ndk_magisk"
    BUILD_FLAGS=(-a 12.0.0_64only -mtg -n -m)
    ;;
  lite)
    REDROID_IMAGE="redroid/redroid:12.0.0_64only_ndk_magisk"
    BUILD_FLAGS=(-a 12.0.0_64only -n -m)
    ;;
  vanilla)
    REDROID_IMAGE="redroid/redroid:12.0.0_64only-latest"
    BUILD_FLAGS=()
    ;;
esac

if [[ "${VARIANT}" == "vanilla" ]]; then
  sudo docker pull "${REDROID_IMAGE}"
else
  RS_DIR="${INSTALL_DIR}/redroid-script"
  if [[ ! -d "${RS_DIR}" ]]; then
    git clone --depth 1 https://github.com/ayasa520/redroid-script.git "${RS_DIR}"
  else
    git -C "${RS_DIR}" pull --ff-only || true
  fi
  (
    cd "${RS_DIR}"
    python3 redroid.py "${BUILD_FLAGS[@]}"
  )
  # Clean temporary extracted build layers to save disk space
  rm -rf "${RS_DIR}/mindthegapps" "${RS_DIR}/ndk" "${RS_DIR}/magisk" /tmp/libndkunpack /tmp/redroid-magisk-* "${HOME}/.cache/redroid"
fi
ok "Redroid image ready: ${REDROID_IMAGE}"

step "5/6 Writing docker-compose.yml & .env and starting services"
cp "${SCRIPT_DIR}/docker-compose.yml" "${INSTALL_DIR}/docker-compose.yml"
cp -r "${SCRIPT_DIR}/scripts" "${INSTALL_DIR}/"
cp -r "${SCRIPT_DIR}/nginx" "${INSTALL_DIR}/"
chmod +x "${INSTALL_DIR}/scripts/"*.sh

cat > "${INSTALL_DIR}/.env" <<EOF
REDROID_IMAGE=${REDROID_IMAGE}
REDROID_WIDTH=${REDROID_WIDTH}
REDROID_HEIGHT=${REDROID_HEIGHT}
REDROID_DPI=${REDROID_DPI}
REDROID_FPS=${REDROID_FPS}
REDROID_GPU_MODE=guest
REDROID_MEM_LIMIT=${REDROID_MEM}
REDROID_MEMSWAP_LIMIT=3584m
WS_SCRCPY_MEM_LIMIT=256m
REDROID_DATA_DIR=${INSTALL_DIR}/data
ADB_BIND=127.0.0.1:5555
WS_SCRCPY_BIND=127.0.0.1:${INTERNAL_WS_PORT}
WS_SCRCPY_IMAGE=smanx/ws-scrcpy:latest
EOF

(
  cd "${INSTALL_DIR}"
  sudo docker compose pull ws-scrcpy
  sudo docker compose up -d
)

step "6/6 Waiting for Android 12 to finish booting"
BOOTED=0
for i in $(seq 1 45); do
  adb connect 127.0.0.1:5555 >/dev/null 2>&1 || true
  BOOT="$(adb -s 127.0.0.1:5555 shell getprop sys.boot_completed </dev/null 2>/dev/null | tr -d '\r\n' || true)"
  if [[ "${BOOT}" == "1" ]]; then
    ok "Android 12 booted in ~$((i * 2))s!"
    BOOTED=1
    break
  fi
  sleep 2
done

if [[ "${BOOTED}" -eq 0 ]]; then
  warn "Boot check timed out; inspect logs with: cd ${INSTALL_DIR} && docker compose logs -f"
else
  echo "  Android Release : $(adb -s 127.0.0.1:5555 shell getprop ro.build.version.release </dev/null 2>/dev/null | tr -d '\r')"
  echo "  ABI List        : $(adb -s 127.0.0.1:5555 shell getprop ro.product.cpu.abilist </dev/null 2>/dev/null | tr -d '\r')"
  echo "  Magisk Version  : $(adb -s 127.0.0.1:5555 shell 'su -v 2>/dev/null || echo none' </dev/null 2>/dev/null | tr -d '\r')"
fi

if [[ "${EXPOSE_NGINX}" -eq 1 ]]; then
  bash "${INSTALL_DIR}/scripts/setup-nginx-auth.sh" --port "${PUBLIC_PORT}" --internal-port "${INTERNAL_WS_PORT}"
fi

echo ""
echo "============================================================"
echo "  Redroid + ws-scrcpy installation complete!"
echo "  Directory      : ${INSTALL_DIR}"
echo "  ADB (local)    : 127.0.0.1:5555 (use SSH tunnel from your PC)"
echo "  Web UI (local) : http://127.0.0.1:${INTERNAL_WS_PORT}"
echo ""
echo "  SSH Tunnel from your computer:"
echo "    ssh -L 8000:127.0.0.1:${INTERNAL_WS_PORT} -L 5555:127.0.0.1:5555 ${USER}@<YOUR_VPS_IP>"
echo "    Then open: http://localhost:8000"
echo ""
echo "  Expose Web UI publicly with Basic Auth:"
echo "    ${INSTALL_DIR}/scripts/setup-nginx-auth.sh --port 8000"
echo "============================================================"
