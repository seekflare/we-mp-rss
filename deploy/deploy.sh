#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env.prod"
COMPOSE_FILE="${SCRIPT_DIR}/docker-compose.prod.yml"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "missing ${ENV_FILE}; copy deploy/.env.example first"
  exit 1
fi

docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" config >/dev/null
docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" build --pull app
docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" up -d app
docker compose --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" ps
