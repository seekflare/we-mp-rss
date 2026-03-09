#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env.prod"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.prod.yml"
BACKUP_ROOT="${PROJECT_ROOT}/backups"
STAMP="$(date +%Y%m%d_%H%M%S)"
TARGET_DIR="${BACKUP_ROOT}/${STAMP}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "missing ${ENV_FILE}; copy deploy/.env.example first"
  exit 1
fi

mkdir -p "${TARGET_DIR}"

if [[ -d "${PROJECT_ROOT}/runtime/data" ]]; then
  tar -czf "${TARGET_DIR}/data.tar.gz" -C "${PROJECT_ROOT}/runtime" data
fi

docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" exec -T mysql \
  sh -lc 'exec mysqldump -urss_user -p"$MYSQL_PASSWORD" --single-transaction --quick we_mp_rss' \
  > "${TARGET_DIR}/we_mp_rss.sql"

cp "${COMPOSE_FILE}" "${TARGET_DIR}/docker-compose.prod.yml"
cp "${SCRIPT_DIR}/nginx.we-mp-rss.conf" "${TARGET_DIR}/nginx.we-mp-rss.conf"
cp "${ENV_FILE}" "${TARGET_DIR}/.env.prod"

echo "backup created: ${TARGET_DIR}"
