#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run this script as root."
  exit 1
fi

REPO_URL="${REPO_URL:-}"
BACKEND_PUBLIC_URL="${BACKEND_PUBLIC_URL:-}"
APP_DIR="${APP_DIR:-/opt/moomoo-backend/app}"
BACKEND_DIR="${BACKEND_DIR:-${APP_DIR}/backend}"
DATA_DIR="${DATA_DIR:-/opt/moomoo-backend/data}"
SERVICE_USER="${SERVICE_USER:-moomoo}"
SERVICE_NAME="${SERVICE_NAME:-moomoo-backend}"
OPEND_HOST="${MOOMOO_OPEND_HOST:-127.0.0.1}"
OPEND_PORT="${MOOMOO_OPEND_PORT:-11111}"
INSTALL_OPEND="${INSTALL_OPEND:-0}"
INSTALL_RUNTIME_DATA_PUSH_TIMER="${INSTALL_RUNTIME_DATA_PUSH_TIMER:-1}"
GITHUB_TOKEN="${GITHUB_TOKEN:-}"

if [[ -z "${REPO_URL}" ]]; then
  echo "Missing REPO_URL. Example:"
  echo "REPO_URL=https://github.com/yourname/yourrepo.git BACKEND_PUBLIC_URL=http://45.63.31.248:8000 bash bootstrap_ubuntu.sh"
  exit 1
fi

if [[ -z "${BACKEND_PUBLIC_URL}" ]]; then
  PUBLIC_IP="$(curl -fsS https://api.ipify.org || true)"
  BACKEND_PUBLIC_URL="http://${PUBLIC_IP:-YOUR_SERVER_IP}:8000"
fi

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  ca-certificates \
  curl \
  git \
  python3 \
  python3-pip \
  python3-venv \
  ufw

if ! id "${SERVICE_USER}" >/dev/null 2>&1; then
  useradd --system --create-home --shell /usr/sbin/nologin "${SERVICE_USER}"
fi

mkdir -p "$(dirname "${APP_DIR}")" "${DATA_DIR}"
git config --global --add safe.directory "${APP_DIR}" 2>/dev/null || true

if [[ -d "${APP_DIR}/.git" ]]; then
  git -C "${APP_DIR}" pull --ff-only
else
  rm -rf "${APP_DIR}"
  git clone "${REPO_URL}" "${APP_DIR}"
fi

if [[ -n "${GITHUB_TOKEN}" ]]; then
  TOKEN_REMOTE_URL="${REPO_URL/https:\/\//https://${GITHUB_TOKEN}@}"
  git -C "${APP_DIR}" remote set-url origin "${TOKEN_REMOTE_URL}"
fi

if [[ ! -f "${DATA_DIR}/asset_snapshots.json" && -f "${BACKEND_DIR}/data/asset_snapshots.json" ]]; then
  cp "${BACKEND_DIR}/data/asset_snapshots.json" "${DATA_DIR}/asset_snapshots.json"
fi

python3 -m venv "${BACKEND_DIR}/.venv"
"${BACKEND_DIR}/.venv/bin/python" -m pip install --upgrade pip
"${BACKEND_DIR}/.venv/bin/python" -m pip install -r "${BACKEND_DIR}/requirements.txt"

chown -R "${SERVICE_USER}:${SERVICE_USER}" "$(dirname "${APP_DIR}")"

cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=Moomoo FastAPI backend
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_USER}
WorkingDirectory=${BACKEND_DIR}
Environment=BACKEND_PUBLIC_URL=${BACKEND_PUBLIC_URL}
Environment=MOOMOO_DATA_DIR=${DATA_DIR}
Environment=MOOMOO_OPEND_HOST=${OPEND_HOST}
Environment=MOOMOO_OPEND_PORT=${OPEND_PORT}
ExecStart=${BACKEND_DIR}/.venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

ufw allow OpenSSH
ufw allow 8000/tcp
ufw --force enable

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"
systemctl restart "${SERVICE_NAME}"

if [[ "${INSTALL_RUNTIME_DATA_PUSH_TIMER}" == "1" || "${INSTALL_RUNTIME_DATA_PUSH_TIMER}" == "true" ]]; then
  bash "${BACKEND_DIR}/deploy/install_runtime_data_push_timer.sh"
fi

echo
echo "Backend deploy finished."
echo "Service: ${SERVICE_NAME}"
echo "App dir: ${APP_DIR}"
echo "Backend dir: ${BACKEND_DIR}"
echo "Data dir: ${DATA_DIR}"
echo "Public URL: ${BACKEND_PUBLIC_URL}"
echo
echo "Check status:"
echo "  systemctl status ${SERVICE_NAME} --no-pager"
echo
echo "View logs:"
echo "  journalctl -u ${SERVICE_NAME} -f"
echo
echo "Runtime data GitHub push timer:"
echo "  systemctl list-timers portsight-runtime-data-push.timer --no-pager"
echo
if [[ "${INSTALL_OPEND}" == "1" || "${INSTALL_OPEND}" == "true" ]]; then
  echo "INSTALL_OPEND=${INSTALL_OPEND}; starting OpenD install and first login."
  bash "${BACKEND_DIR}/deploy/install_opend_ubuntu.sh"
else
  echo "OpenD still needs to be installed and logged in on this server."
  echo "To install it now:"
  echo "  bash ${BACKEND_DIR}/deploy/install_opend_ubuntu.sh"
fi
