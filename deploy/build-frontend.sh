#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${PROJECT_ROOT}/web_ui"

docker run --rm \
  -u "$(id -u):$(id -g)" \
  -v "${PWD}:/app" \
  -w /app \
  node:20 \
  bash -lc "corepack enable && yarn install --frozen-lockfile && yarn build"

mkdir -p "${PROJECT_ROOT}/static"
rm -rf "${PROJECT_ROOT}/static"/*
cp -rf dist/* "${PROJECT_ROOT}/static/"

echo "frontend build copied to ${PROJECT_ROOT}/static"
