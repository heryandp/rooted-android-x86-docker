#!/usr/bin/env bash
# ==============================================================================
# build-deb.sh - Build emu-root Debian/Ubuntu .deb package
# Output: dist/emu-root_<version>_all.deb
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EMU_ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
REPO_ROOT="$(cd "${EMU_ROOT_DIR}/.." && pwd)"

PKG_NAME="emu-root"
VERSION="${1:-1.0.0}"
OUT_DIR="${REPO_ROOT}/dist"
STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "${STAGE_DIR}"' EXIT

PKG_ROOT="${STAGE_DIR}/${PKG_NAME}_${VERSION}_all"
mkdir -p "${PKG_ROOT}/DEBIAN" \
         "${PKG_ROOT}/usr/bin" \
         "${PKG_ROOT}/usr/share/emu-root" \
         "${PKG_ROOT}/usr/share/doc/${PKG_NAME}"

# Copy DEBIAN metadata and set version
sed "s/^Version: .*/Version: ${VERSION}/" \
  "${EMU_ROOT_DIR}/packaging/deb/DEBIAN/control" > "${PKG_ROOT}/DEBIAN/control"
cp "${EMU_ROOT_DIR}/packaging/deb/DEBIAN/postinst" "${PKG_ROOT}/DEBIAN/postinst"
chmod 0755 "${PKG_ROOT}/DEBIAN/postinst"

# Install CLI binary and user setup helper
install -m 0755 "${EMU_ROOT_DIR}/bin/emu-root" "${PKG_ROOT}/usr/bin/emu-root"
install -m 0755 "${EMU_ROOT_DIR}/installers/ubuntu/install-ubuntu.sh" "${PKG_ROOT}/usr/share/emu-root/install-ubuntu.sh"
install -m 0644 "${REPO_ROOT}/LICENSE" "${PKG_ROOT}/usr/share/doc/${PKG_NAME}/copyright"
install -m 0644 "${EMU_ROOT_DIR}/README.md" "${PKG_ROOT}/usr/share/doc/${PKG_NAME}/README.md"

mkdir -p "${OUT_DIR}"
DEB_PATH="${OUT_DIR}/${PKG_NAME}_${VERSION}_all.deb"
dpkg-deb --build --root-owner-group "${PKG_ROOT}" "${DEB_PATH}"

echo "[OK] Built Debian package: ${DEB_PATH}"
echo "     Install with: sudo apt install ./$(basename "${DEB_PATH}")"
echo "     Then run:     emu-root --setup"
