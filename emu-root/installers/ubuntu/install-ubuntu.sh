#!/usr/bin/env bash
# ==============================================================================
# emu-root Ubuntu / Debian Installer (.sh)
# Sets up KVM check, Android SDK, API 31 Play Store AVD, Magisk root via rootAVD,
# and installs the `emu-root` CLI launcher.
# ==============================================================================
set -euo pipefail

AVD_NAME="${EMU_ROOT_AVD:-Pixel_7_API_31_Rooted}"
API_LEVEL="${EMU_ROOT_API:-31}"
RAM_MB="${EMU_ROOT_RAM:-4096}"
CORES="${EMU_ROOT_CORES:-4}"
DATA_SIZE="${EMU_ROOT_DATA_SIZE:-8G}"
SKIP_ROOT=0
SKIP_APT=0
FORCE_RECREATE=0

usage() {
  cat <<EOF
Usage: ./install-ubuntu.sh [OPTIONS]

Options:
  --avd <name>       AVD name (default: ${AVD_NAME})
  --ram <MB>         RAM in MB (default: ${RAM_MB})
  --cores <N>        CPU cores (default: ${CORES})
  --skip-root        Skip automatic rootAVD Magisk patching
  --skip-apt         Skip apt-get dependency installation
  --force-recreate   Recreate AVD if it already exists
  -h, --help         Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --avd) AVD_NAME="$2"; shift 2 ;;
    --ram) RAM_MB="$2"; shift 2 ;;
    --cores) CORES="$2"; shift 2 ;;
    --skip-root) SKIP_ROOT=1; shift ;;
    --skip-apt) SKIP_APT=1; shift ;;
    --force-recreate) FORCE_RECREATE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[ERROR] Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "[ERROR] This installer is intended for Ubuntu / Debian Linux." >&2
  exit 1
fi

HOST_ARCH="$(uname -m)"
case "${HOST_ARCH}" in
  x86_64)  ANDROID_ABI="x86_64" ;;
  aarch64) ANDROID_ABI="arm64-v8a" ;;
  *)
    echo "[ERROR] Unsupported Linux architecture: ${HOST_ARCH}" >&2
    exit 1
    ;;
esac

echo "============================================================"
echo "  emu-root Ubuntu/Debian Installer (${HOST_ARCH} -> ${ANDROID_ABI})"
echo "  Target: Android 12 (API ${API_LEVEL}) Play Store + Magisk"
echo "============================================================"

step "Checking KVM hardware acceleration"
if [[ -e /dev/kvm ]]; then
  if [[ -r /dev/kvm && -w /dev/kvm ]]; then
    ok "/dev/kvm is accessible"
  else
    warn "/dev/kvm exists, adding ${USER} to 'kvm' group (re-login may be required)"
    sudo usermod -aG kvm "${USER}" || true
  fi
else
  warn "/dev/kvm NOT found!"
  warn "Android Emulator (x86_64) requires KVM on Linux."
  warn "If you are on a standard VPS without nested virtualization, use 'redroid-docker/' instead."
fi

if [[ "${SKIP_APT}" -eq 0 ]]; then
  step "Installing Ubuntu/Debian dependencies via apt"
  sudo apt-get update -qq
  sudo apt-get install -y \
    curl unzip git ca-certificates \
    openjdk-17-jdk-headless \
    qemu-kvm libpulse0 libgl1 libx11-6 libnss3 libasound2t64 2>/dev/null || \
  sudo apt-get install -y \
    curl unzip git ca-certificates \
    openjdk-17-jdk-headless \
    qemu-kvm libpulse0 libgl1 libx11-6 libnss3 libasound2
  ok "Dependencies installed"
fi

SDK_ROOT="${ANDROID_HOME:-${HOME}/Android/Sdk}"
export ANDROID_HOME="${SDK_ROOT}"
export ANDROID_SDK_ROOT="${SDK_ROOT}"
export ANDROID_AVD_HOME="${ANDROID_AVD_HOME:-${HOME}/.android/avd}"
mkdir -p "${SDK_ROOT}" "${ANDROID_AVD_HOME}"

SDKMANAGER="${SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager"
AVDMANAGER="${SDK_ROOT}/cmdline-tools/latest/bin/avdmanager"
ADB="${SDK_ROOT}/platform-tools/adb"
EMULATOR="${SDK_ROOT}/emulator/emulator"

if [[ ! -x "${SDKMANAGER}" ]]; then
  step "Downloading Android SDK Command-Line Tools (Linux)"
  LATEST_ZIP="$(curl -fsSL --max-time 20 https://dl.google.com/android/repository/repository2-3.xml 2>/dev/null \
    | grep -oE 'commandlinetools-linux-[0-9]+_latest\.zip' | tail -n 1 || true)"
  LATEST_ZIP="${LATEST_ZIP:-commandlinetools-linux-11076708_latest.zip}"
  DL_URL="https://dl.google.com/android/repository/${LATEST_ZIP}"
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "${TMP_DIR}"' EXIT

  echo "Downloading ${DL_URL} ..."
  curl -fL "${DL_URL}" -o "${TMP_DIR}/cmdline-tools.zip"
  unzip -q "${TMP_DIR}/cmdline-tools.zip" -d "${TMP_DIR}/extract"
  mkdir -p "${SDK_ROOT}/cmdline-tools"
  rm -rf "${SDK_ROOT}/cmdline-tools/latest"
  mv "${TMP_DIR}/extract/cmdline-tools" "${SDK_ROOT}/cmdline-tools/latest"
  ok "Installed Android cmdline-tools at ${SDK_ROOT}/cmdline-tools/latest"
else
  ok "Android cmdline-tools already installed"
fi

SYS_IMAGE_PKG="system-images;android-${API_LEVEL};google_apis_playstore;${ANDROID_ABI}"

step "Installing platform-tools, emulator, and ${SYS_IMAGE_PKG}"
yes | "${SDKMANAGER}" --sdk_root="${SDK_ROOT}" --licenses >/dev/null 2>&1 || true
"${SDKMANAGER}" --sdk_root="${SDK_ROOT}" \
  "platform-tools" \
  "emulator" \
  "platforms;android-${API_LEVEL}" \
  "${SYS_IMAGE_PKG}"

step "Creating AVD '${AVD_NAME}'"
AVD_DIR="${ANDROID_AVD_HOME}/${AVD_NAME}.avd"
if [[ -d "${AVD_DIR}" && "${FORCE_RECREATE}" -eq 0 ]]; then
  ok "AVD '${AVD_NAME}' already exists (pass --force-recreate to overwrite)"
else
  CREATE_ARGS=(create avd -n "${AVD_NAME}" -k "${SYS_IMAGE_PKG}" -d pixel_7)
  [[ "${FORCE_RECREATE}" -eq 1 ]] && CREATE_ARGS+=(--force)
  echo "no" | "${AVDMANAGER}" "${CREATE_ARGS[@]}"
  ok "Created AVD '${AVD_NAME}'"
fi

set_ini_key() {
  local file="$1" key="$2" val="$3"
  if grep -qE "^[[:space:]]*${key}[[:space:]]*=" "${file}" 2>/dev/null; then
    sed -i -E "s|^[[:space:]]*${key}[[:space:]]*=.*|${key} = ${val}|" "${file}"
  else
    printf '%s = %s\n' "${key}" "${val}" >> "${file}"
  fi
}

CONFIG_INI="${AVD_DIR}/config.ini"
if [[ -f "${CONFIG_INI}" ]]; then
  set_ini_key "${CONFIG_INI}" "PlayStore.enabled" "true"
  set_ini_key "${CONFIG_INI}" "hw.cpu.ncore" "${CORES}"
  set_ini_key "${CONFIG_INI}" "hw.ramSize" "${RAM_MB}"
  set_ini_key "${CONFIG_INI}" "vm.heapSize" "512"
  set_ini_key "${CONFIG_INI}" "disk.dataPartition.size" "${DATA_SIZE}"
  set_ini_key "${CONFIG_INI}" "hw.gpu.enabled" "yes"
  set_ini_key "${CONFIG_INI}" "hw.gpu.mode" "auto"
  set_ini_key "${CONFIG_INI}" "hw.keyboard" "yes"
  set_ini_key "${CONFIG_INI}" "fastboot.forceColdBoot" "yes"
  set_ini_key "${CONFIG_INI}" "fastboot.forceFastBoot" "no"
  set_ini_key "${CONFIG_INI}" "avd.ini.displayname" "Pixel 7 API ${API_LEVEL} (Android 12 PlayStore Rooted)"
  ok "Configured ${CONFIG_INI}"
fi

step "Installing emu-root CLI launcher"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAUNCHER_SRC="${SCRIPT_DIR}/../../bin/emu-root"
if [[ ! -x "/usr/bin/emu-root" ]]; then
  if [[ -f "${LAUNCHER_SRC}" ]]; then
    sudo install -m 0755 "${LAUNCHER_SRC}" /usr/local/bin/emu-root
  else
    TMP_BIN="$(mktemp)"
    curl -fsSL "https://raw.githubusercontent.com/heryandp/rooted-android-x86-docker/main/emu-root/bin/emu-root" -o "${TMP_BIN}"
    sudo install -m 0755 "${TMP_BIN}" /usr/local/bin/emu-root
    rm -f "${TMP_BIN}"
  fi
  ok "Installed launcher at /usr/local/bin/emu-root"
else
  ok "emu-root already installed via .deb package at /usr/bin/emu-root"
fi

SHELL_RC="${HOME}/.bashrc"
[[ "${SHELL:-}" == *zsh ]] && SHELL_RC="${HOME}/.zshrc"
if ! grep -q "# emu-root Android SDK" "${SHELL_RC}" 2>/dev/null; then
  cat >> "${SHELL_RC}" <<EOF

# emu-root Android SDK
export ANDROID_HOME="${SDK_ROOT}"
export ANDROID_SDK_ROOT="${SDK_ROOT}"
export PATH="\$ANDROID_HOME/platform-tools:\$ANDROID_HOME/emulator:\$ANDROID_HOME/cmdline-tools/latest/bin:\$PATH"
EOF
  ok "Added ANDROID_HOME & PATH exports to ${SHELL_RC}"
fi

if [[ "${SKIP_ROOT}" -eq 0 ]]; then
  if [[ ! -r /dev/kvm || ! -w /dev/kvm ]]; then
    warn "Skipping automatic rootAVD patching because /dev/kvm is not accessible in this session."
    warn "After enabling KVM / re-logging in, run emu-root and patch ramdisk.img with rootAVD."
  else
    step "Rooting ramdisk.img with Magisk via rootAVD"
    RAMDISK_REL="system-images/android-${API_LEVEL}/google_apis_playstore/${ANDROID_ABI}/ramdisk.img"
    if [[ -f "${SDK_ROOT}/${RAMDISK_REL}.backup" ]]; then
      ok "Backup exists (${RAMDISK_REL}.backup) — ramdisk.img appears already patched. Skipping."
    else
      ROOTAVD_DIR="${HOME}/AndroidTools/rootAVD"
      if [[ ! -d "${ROOTAVD_DIR}" ]]; then
        mkdir -p "$(dirname "${ROOTAVD_DIR}")"
        git clone --depth 1 https://gitlab.com/newbit/rootAVD.git "${ROOTAVD_DIR}"
      fi
      chmod +x "${ROOTAVD_DIR}/rootAVD.sh"

      echo "Booting '${AVD_NAME}' temporarily (headless) for rootAVD patching..."
      nohup "${EMULATOR}" -avd "${AVD_NAME}" -no-snapshot -no-metrics -no-window -no-audio >/tmp/emu-root-install.log 2>&1 &
      EMU_PID=$!

      WAITED=0
      while [[ "${WAITED}" -lt 180 ]]; do
        BOOT="$("${ADB}" -e shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n' || true)"
        [[ "${BOOT}" == "1" ]] && break
        if ! kill -0 "${EMU_PID}" 2>/dev/null; then
          warn "Emulator exited early. Check /tmp/emu-root-install.log"
          break
        fi
        sleep 3
        WAITED=$((WAITED + 3))
      done

      if [[ "${WAITED}" -lt 180 ]]; then
        (
          cd "${ROOTAVD_DIR}"
          export PATH="${SDK_ROOT}/platform-tools:${SDK_ROOT}/emulator:${PATH}"
          ./rootAVD.sh "${RAMDISK_REL}"
        )
        ok "rootAVD Magisk patching complete!"
        sleep 4
        "${ADB}" -e emu kill >/dev/null 2>&1 || true
      else
        warn "Timed out waiting for boot. Run rootAVD.sh manually after starting emu-root."
      fi
    fi
  fi
fi

echo ""
echo "============================================================"
echo "  Ubuntu/Debian installation complete!"
echo "  Reload shell:   source ${SHELL_RC}"
echo "  Start emulator: emu-root"
echo "  Root shell:     emu-root --root"
echo "  Stop emulator:  emu-root --stop"
echo "============================================================"
