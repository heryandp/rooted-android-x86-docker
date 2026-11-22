#!/usr/bin/env bash
# ==============================================================================
# emu-root macOS Installer (Intel x86_64 + Apple Silicon arm64)
# Sets up Android SDK, API 31 Play Store AVD (auto-matching Mac CPU arch),
# Magisk root via rootAVD, and installs the `emu-root` CLI launcher.
# ==============================================================================
set -euo pipefail

AVD_NAME="${EMU_ROOT_AVD:-Pixel_7_API_31_Rooted}"
API_LEVEL="${EMU_ROOT_API:-31}"
RAM_MB="${EMU_ROOT_RAM:-4096}"
CORES="${EMU_ROOT_CORES:-4}"
DATA_SIZE="${EMU_ROOT_DATA_SIZE:-8G}"
SKIP_ROOT=0
FORCE_RECREATE=0

usage() {
  cat <<EOF
Usage: ./install-macos.sh [OPTIONS]

Options:
  --avd <name>       AVD name (default: ${AVD_NAME})
  --ram <MB>         RAM in MB (default: ${RAM_MB})
  --cores <N>        CPU cores (default: ${CORES})
  --skip-root        Skip automatic rootAVD Magisk patching
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
    --force-recreate) FORCE_RECREATE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[ERROR] Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "[ERROR] This installer is intended for macOS." >&2
  exit 1
fi

HOST_ARCH="$(uname -m)"
case "${HOST_ARCH}" in
  arm64)
    ANDROID_ABI="arm64-v8a"
    HOMEBREW_PREFIX="/opt/homebrew"
    ARCH_LABEL="Apple Silicon (arm64)"
    ;;
  x86_64)
    ANDROID_ABI="x86_64"
    HOMEBREW_PREFIX="/usr/local"
    ARCH_LABEL="Intel Mac (x86_64)"
    ;;
  *)
    echo "[ERROR] Unsupported macOS architecture: ${HOST_ARCH}" >&2
    exit 1
    ;;
esac

echo "============================================================"
echo "  emu-root macOS Installer - ${ARCH_LABEL}"
echo "  Target: Android 12 (API ${API_LEVEL}) Play Store (${ANDROID_ABI}) + Magisk"
echo "============================================================"

# Ensure Homebrew PATH if installed
if [[ -x "${HOMEBREW_PREFIX}/bin/brew" ]]; then
  eval "$("${HOMEBREW_PREFIX}/bin/brew" shellenv)"
fi

step "Checking prerequisites (Java 17+, curl, unzip, git)"
if ! /usr/libexec/java_home -v 17+ >/dev/null 2>&1; then
  if command -v brew >/dev/null 2>&1; then
    echo "Installing OpenJDK 17 via Homebrew..."
    brew install openjdk@17
    export JAVA_HOME="${HOMEBREW_PREFIX}/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home"
    export PATH="${HOMEBREW_PREFIX}/opt/openjdk@17/bin:${PATH}"
  else
    echo "[ERROR] JDK 17+ not found and Homebrew is not installed." >&2
    echo "        Install Homebrew (https://brew.sh) or OpenJDK 17, then re-run." >&2
    exit 1
  fi
else
  export JAVA_HOME="$(/usr/libexec/java_home -v 17+)"
  ok "Java found: ${JAVA_HOME}"
fi

for tool in curl unzip git; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "[ERROR] Required tool '${tool}' not found. Run: xcode-select --install" >&2
    exit 1
  fi
done

SDK_ROOT="${ANDROID_HOME:-${HOME}/Library/Android/sdk}"
export ANDROID_HOME="${SDK_ROOT}"
export ANDROID_SDK_ROOT="${SDK_ROOT}"
export ANDROID_AVD_HOME="${ANDROID_AVD_HOME:-${HOME}/.android/avd}"
mkdir -p "${SDK_ROOT}" "${ANDROID_AVD_HOME}"

SDKMANAGER="${SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager"
AVDMANAGER="${SDK_ROOT}/cmdline-tools/latest/bin/avdmanager"
ADB="${SDK_ROOT}/platform-tools/adb"
EMULATOR="${SDK_ROOT}/emulator/emulator"

if [[ ! -x "${SDKMANAGER}" ]]; then
  step "Downloading Android SDK Command-Line Tools (macOS)"
  LATEST_ZIP="$(curl -fsSL --max-time 20 https://dl.google.com/android/repository/repository2-3.xml 2>/dev/null \
    | grep -oE 'commandlinetools-mac-[0-9]+_latest\.zip' | tail -n 1 || true)"
  LATEST_ZIP="${LATEST_ZIP:-commandlinetools-mac-11076708_latest.zip}"
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

step "Creating AVD '${AVD_NAME}' (${ANDROID_ABI})"
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
    sed -i '' -E "s|^[[:space:]]*${key}[[:space:]]*=.*|${key} = ${val}|" "${file}"
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
  set_ini_key "${CONFIG_INI}" "hw.gpu.mode" "host"
  set_ini_key "${CONFIG_INI}" "hw.keyboard" "yes"
  set_ini_key "${CONFIG_INI}" "fastboot.forceColdBoot" "yes"
  set_ini_key "${CONFIG_INI}" "fastboot.forceFastBoot" "no"
  set_ini_key "${CONFIG_INI}" "avd.ini.displayname" "Pixel 7 API ${API_LEVEL} (${ANDROID_ABI} PlayStore Rooted)"
  ok "Configured ${CONFIG_INI}"
fi

step "Installing emu-root CLI launcher"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAUNCHER_SRC="${SCRIPT_DIR}/../../bin/emu-root"
INSTALL_BIN="${HOME}/.local/bin"
if [[ -w "/usr/local/bin" ]]; then
  INSTALL_BIN="/usr/local/bin"
fi
mkdir -p "${INSTALL_BIN}"

if [[ -f "${LAUNCHER_SRC}" ]]; then
  cp "${LAUNCHER_SRC}" "${INSTALL_BIN}/emu-root"
else
  curl -fsSL "https://raw.githubusercontent.com/heryandp/rooted-android-x86-docker/main/emu-root/bin/emu-root" \
    -o "${INSTALL_BIN}/emu-root"
fi
chmod +x "${INSTALL_BIN}/emu-root"
ok "Installed launcher at ${INSTALL_BIN}/emu-root"

# Persist environment variables in shell profile
SHELL_RC="${HOME}/.zshrc"
[[ "${SHELL:-}" == *bash ]] && SHELL_RC="${HOME}/.bash_profile"
if ! grep -q "# emu-root Android SDK" "${SHELL_RC}" 2>/dev/null; then
  cat >> "${SHELL_RC}" <<EOF

# emu-root Android SDK
export ANDROID_HOME="${SDK_ROOT}"
export ANDROID_SDK_ROOT="${SDK_ROOT}"
export PATH="${INSTALL_BIN}:\$ANDROID_HOME/platform-tools:\$ANDROID_HOME/emulator:\$ANDROID_HOME/cmdline-tools/latest/bin:\$PATH"
EOF
  ok "Added ANDROID_HOME & PATH exports to ${SHELL_RC}"
fi

if [[ "${SKIP_ROOT}" -eq 0 ]]; then
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

    echo "Booting '${AVD_NAME}' temporarily for rootAVD patching..."
    nohup "${EMULATOR}" -avd "${AVD_NAME}" -no-snapshot -no-metrics >/tmp/emu-root-install.log 2>&1 &
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

echo ""
echo "============================================================"
echo "  macOS (${ARCH_LABEL}) installation complete!"
echo "  Reload shell:   source ${SHELL_RC}"
echo "  Start emulator: emu-root"
echo "  Root shell:     emu-root --root"
echo "  Stop emulator:  emu-root --stop"
echo "============================================================"
