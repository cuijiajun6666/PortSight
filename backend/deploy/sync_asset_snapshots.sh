#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/moomoo-backend/app}"
BACKEND_DIR="${BACKEND_DIR:-${APP_DIR}/backend}"
DATA_DIR="${DATA_DIR:-/opt/moomoo-backend/data}"
SERVICE_USER="${SERVICE_USER:-moomoo}"

SOURCE_FILE="${BACKEND_DIR}/data/asset_snapshots.json"
TARGET_FILE="${DATA_DIR}/asset_snapshots.json"

if [[ ! -f "${SOURCE_FILE}" ]]; then
  echo "Missing source asset snapshots: ${SOURCE_FILE}"
  exit 1
fi

mkdir -p "${DATA_DIR}"

if [[ -f "${TARGET_FILE}" ]]; then
  BACKUP_FILE="${TARGET_FILE}.backup.$(date -u +%Y%m%d%H%M%S)"
  cp "${TARGET_FILE}" "${BACKUP_FILE}"
  echo "Backed up current runtime snapshots to ${BACKUP_FILE}"
fi

cp "${SOURCE_FILE}" "${TARGET_FILE}"
chown "${SERVICE_USER}:${SERVICE_USER}" "${TARGET_FILE}" 2>/dev/null || true

echo "Synced ${SOURCE_FILE} -> ${TARGET_FILE}"
