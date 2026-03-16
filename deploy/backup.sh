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

cp "${COMPOSE_FILE}" "${TARGET_DIR}/docker-compose.prod.yml"
cp "${SCRIPT_DIR}/nginx.we-mp-rss.conf" "${TARGET_DIR}/nginx.we-mp-rss.conf"
cp "${SCRIPT_DIR}/nginx.we-mp-rss.ip.conf" "${TARGET_DIR}/nginx.we-mp-rss.ip.conf"
cp "${ENV_FILE}" "${TARGET_DIR}/.env.prod"

echo "backup created: ${TARGET_DIR}"
