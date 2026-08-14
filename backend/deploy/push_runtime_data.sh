#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/moomoo-backend/app}"
BACKEND_DIR="${BACKEND_DIR:-${APP_DIR}/backend}"
DATA_DIR="${DATA_DIR:-/opt/moomoo-backend/data}"

cd "${APP_DIR}"
git config --global --add safe.directory "${APP_DIR}" 2>/dev/null || true

mkdir -p "${BACKEND_DIR}/data"

files_to_add=()

for name in asset_snapshots.json trade_deals.json advisor_state.json advisor_symbol_meta.json advisor_training_samples.json advisor_model.json advisor_watchlist.json advisor_alert_acks.json advisor_trigger_alerts.json advisor_owner_plates.json advisor_valuations.json advisor_financials.json advisor_earnings_moves.json advisor_company_profiles.json advisor_operational_efficiency.json advisor_capital_flow.json advisor_capital_distribution.json advisor_daily_short_volume.json advisor_short_interest.json advisor_shareholders_overview.json advisor_shareholders_changes.json advisor_insider_trades.json advisor_insider_holders.json; do
  if [[ -f "${DATA_DIR}/${name}" ]]; then
    cp "${DATA_DIR}/${name}" "${BACKEND_DIR}/data/${name}"
    files_to_add+=("backend/data/${name}")
  elif [[ -f "${BACKEND_DIR}/data/${name}" ]]; then
    files_to_add+=("backend/data/${name}")
  fi
done

if [[ "${#files_to_add[@]}" -eq 0 ]]; then
  echo "No tracked runtime data files found."
  exit 0
fi

git add "${files_to_add[@]}"

if git diff --cached --quiet; then
  echo "No runtime data changes to push."
  exit 0
fi

git commit -m "Update runtime data $(date -u +%Y-%m-%d)"
git push
