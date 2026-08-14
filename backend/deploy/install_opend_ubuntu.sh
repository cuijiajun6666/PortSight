#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run this script as root."
  exit 1
fi

INSTALL_DIR="${INSTALL_DIR:-/opt/moomoo-opend}"
ENV_FILE="${ENV_FILE:-/etc/moomoo-opend.env}"
SERVICE_NAME="${SERVICE_NAME:-moomoo-opend}"
DOWNLOAD_URL="${DOWNLOAD_URL:-https://www.moomoo.com/download/fetch-lasted-link?name=opend-ubuntu}"

apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl tar findutils

mkdir -p "${INSTALL_DIR}"
cd "${INSTALL_DIR}"

echo "Downloading latest moomoo OpenD for Ubuntu..."
curl -L -o moomoo-opend.tar.gz "${DOWNLOAD_URL}"

echo "Extracting OpenD..."
tar -xzf moomoo-opend.tar.gz

OPEND_BIN="$(find "${INSTALL_DIR}" -maxdepth 4 -type f \( -name "moomoo_OpenD" -o -name "OpenD" -o -name "FutuOpenD" \) | head -n 1)"

if [[ -z "${OPEND_BIN}" ]]; then
  echo "Could not find OpenD executable after extraction."
  echo "Files under ${INSTALL_DIR}:"
  find "${INSTALL_DIR}" -maxdepth 3 -type f | sed 's#^#  #'
  exit 1
fi

chmod +x "${OPEND_BIN}"

echo
echo "OpenD executable:"
echo "  ${OPEND_BIN}"
echo

read -rp "Moomoo account/email/phone: " MOOMOO_ACCOUNT
read -rsp "Moomoo password: " MOOMOO_PASSWORD
echo

cat > "${ENV_FILE}" <<EOF
MOOMOO_ACCOUNT=${MOOMOO_ACCOUNT}
MOOMOO_PASSWORD=${MOOMOO_PASSWORD}
EOF
chmod 600 "${ENV_FILE}"

cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=moomoo OpenD gateway
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$(dirname "${OPEND_BIN}")
EnvironmentFile=${ENV_FILE}
ExecStart=${OPEND_BIN} -login_account=\${MOOMOO_ACCOUNT} -login_pwd=\${MOOMOO_PASSWORD} -lang=en
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable "${SERVICE_NAME}"

echo
echo "Starting OpenD in this terminal for first login."
echo "If moomoo asks for device verification or 2FA, confirm it in your moomoo app."
echo "After login succeeds, type 'exit' at the OpenD >>> prompt to let this script finish."
echo

set +e
"${OPEND_BIN}" -login_account="${MOOMOO_ACCOUNT}" -login_pwd="${MOOMOO_PASSWORD}" -lang=en
OPEND_EXIT_CODE=$?
set -e

echo
echo "Starting OpenD as a background service..."
systemctl restart "${SERVICE_NAME}"
systemctl status "${SERVICE_NAME}" --no-pager -l | sed -n '1,12p'

if systemctl list-unit-files moomoo-backend.service >/dev/null 2>&1; then
  echo
  echo "Restarting backend and running verification..."
  systemctl restart moomoo-backend
  if [[ -x /opt/moomoo-backend/app/backend/deploy/verify_server.sh ]]; then
    /opt/moomoo-backend/app/backend/deploy/verify_server.sh
  fi
fi

exit "${OPEND_EXIT_CODE}"
