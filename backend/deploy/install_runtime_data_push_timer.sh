#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run this script as root."
  exit 1
fi

APP_DIR="${APP_DIR:-/opt/moomoo-backend/app}"
BACKEND_DIR="${BACKEND_DIR:-${APP_DIR}/backend}"
SERVICE_NAME="${SERVICE_NAME:-portsight-runtime-data-push}"

cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<EOF
[Unit]
Description=Push PortSight runtime JSON data to GitHub
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
WorkingDirectory=${APP_DIR}
ExecStart=${BACKEND_DIR}/deploy/push_runtime_data.sh
EOF

cat > "/etc/systemd/system/${SERVICE_NAME}.timer" <<EOF
[Unit]
Description=Daily PortSight runtime JSON data push

[Timer]
OnCalendar=*-*-* 22:30:00 UTC
Persistent=true

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable --now "${SERVICE_NAME}.timer"

echo "Installed ${SERVICE_NAME}.timer"
echo "Next run:"
systemctl list-timers "${SERVICE_NAME}.timer" --no-pager
