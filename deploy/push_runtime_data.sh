#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/moomoo-backend/app}"
DATA_DIR="${DATA_DIR:-/opt/moomoo-backend/data}"

cd "${APP_DIR}"
git config --global --add safe.directory "${APP_DIR}" 2>/dev/null || true

mkdir -p data

files_to_add=()

for name in asset_snapshots.json trade_deals.json advisor_state.json advisor_symbol_meta.json; do
  if [[ -f "${DATA_DIR}/${name}" ]]; then
    cp "${DATA_DIR}/${name}" "data/${name}"
    files_to_add+=("data/${name}")
  elif [[ -f "data/${name}" ]]; then
    files_to_add+=("data/${name}")
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
