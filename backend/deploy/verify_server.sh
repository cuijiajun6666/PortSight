#!/usr/bin/env bash
set -euo pipefail

BACKEND_URL="${BACKEND_URL:-http://127.0.0.1:8000}"
BACKEND_SERVICE="${BACKEND_SERVICE:-moomoo-backend}"
OPEND_SERVICE="${OPEND_SERVICE:-moomoo-opend}"

echo "Checking OpenD service..."
systemctl is-active --quiet "${OPEND_SERVICE}"
systemctl status "${OPEND_SERVICE}" --no-pager -l | sed -n '1,12p'

echo
echo "Restarting backend..."
systemctl restart "${BACKEND_SERVICE}"
systemctl is-active --quiet "${BACKEND_SERVICE}"
systemctl status "${BACKEND_SERVICE}" --no-pager -l | sed -n '1,12p'

echo
echo "Checking backend root endpoint..."
curl -fsS "${BACKEND_URL}/"

echo
echo
echo "Checking account endpoint..."
curl -fsS "${BACKEND_URL}/account"

echo
echo
echo "Server verification finished."
