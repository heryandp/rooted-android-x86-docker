#!/usr/bin/env bash
# ==============================================================================
# setup-nginx-auth.sh - Expose ws-scrcpy safely via Nginx + HTTP Basic Auth
# Keeps ADB port 5555 private on 127.0.0.1!
# ==============================================================================
set -euo pipefail

PUBLIC_PORT=8000
INTERNAL_PORT=18000
SERVER_NAME="_"
AUTH_USER="redroid"
AUTH_PASS=""
DISABLE_ONLY=0

usage() {
  cat <<EOF
Usage: ./setup-nginx-auth.sh [OPTIONS]

Options:
  --port <N>           Public Nginx port (default: ${PUBLIC_PORT})
  --internal-port <N>  Internal localhost ws-scrcpy port (default: ${INTERNAL_PORT})
  --server-name <host> Nginx server_name (default: _)
  --user <username>    Basic Auth username (default: ${AUTH_USER})
  --pass <password>    Basic Auth password (default: auto-generated 16-char random)
  --disable            Disable and remove the Nginx site from sites-enabled
  -h, --help           Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) PUBLIC_PORT="$2"; shift 2 ;;
    --internal-port) INTERNAL_PORT="$2"; shift 2 ;;
    --server-name) SERVER_NAME="$2"; shift 2 ;;
    --user) AUTH_USER="$2"; shift 2 ;;
    --pass) AUTH_PASS="$2"; shift 2 ;;
    --disable) DISABLE_ONLY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "[ERROR] Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

SITE_AVAIL="/etc/nginx/sites-available/redroid-scrcpy"
SITE_ENABLED="/etc/nginx/sites-enabled/redroid-scrcpy"
HTPASSWD_FILE="/etc/nginx/.htpasswd-redroid"

if [[ "${DISABLE_ONLY}" -eq 1 ]]; then
  sudo rm -f "${SITE_ENABLED}"
  sudo nginx -t && sudo systemctl reload nginx
  echo "[OK] Public Nginx access for ws-scrcpy disabled."
  exit 0
fi

if ! command -v nginx >/dev/null 2>&1; then
  echo "Installing nginx and openssl..."
  sudo apt-get update -qq
  sudo apt-get install -y -qq nginx openssl
fi

if [[ -z "${AUTH_PASS}" ]]; then
  AUTH_PASS="$(python3 -c 'import secrets, string; a=string.ascii_letters+string.digits; print("".join(secrets.choice(a) for _ in range(16)))')"
fi

HASH="$(openssl passwd -6 "${AUTH_PASS}")"
printf '%s:%s\n' "${AUTH_USER}" "${HASH}" | sudo tee "${HTPASSWD_FILE}" >/dev/null
sudo chown root:www-data "${HTPASSWD_FILE}"
sudo chmod 640 "${HTPASSWD_FILE}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${SCRIPT_DIR}/../nginx/redroid-scrcpy.conf.template"

if [[ -f "${TEMPLATE}" ]]; then
  sed \
    -e "s/__PUBLIC_PORT__/${PUBLIC_PORT}/g" \
    -e "s/__INTERNAL_PORT__/${INTERNAL_PORT}/g" \
    -e "s/__SERVER_NAME__/${SERVER_NAME}/g" \
    "${TEMPLATE}" | sudo tee "${SITE_AVAIL}" >/dev/null
else
  sudo tee "${SITE_AVAIL}" >/dev/null <<EOF
map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen ${PUBLIC_PORT};
    listen [::]:${PUBLIC_PORT};
    server_name ${SERVER_NAME};

    auth_basic "Redroid Android 12 Access";
    auth_basic_user_file ${HTPASSWD_FILE};

    location / {
        proxy_pass http://127.0.0.1:${INTERNAL_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection \$connection_upgrade;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 86400s;
        proxy_send_timeout 86400s;
        proxy_buffering off;
    }
}
EOF
fi

sudo ln -sf "${SITE_AVAIL}" "${SITE_ENABLED}"
sudo nginx -t
sudo systemctl reload nginx

echo ""
echo "============================================================"
echo "  Nginx Basic Auth Proxy Enabled!"
echo "  URL      : http://<YOUR_VPS_IP>:${PUBLIC_PORT}"
echo "  Username : ${AUTH_USER}"
echo "  Password : ${AUTH_PASS}"
echo "  Note     : Save this password now; only its hash is stored"
echo "             at ${HTPASSWD_FILE}."
echo "============================================================"
