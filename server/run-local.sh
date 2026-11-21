#!/bin/sh
set -eu
cd "$(dirname "$0")"
: "${SOMBRERO_DATA_DIR:?Set SOMBRERO_DATA_DIR to the provisioned data directory}"
: "${SOMBRERO_MEDIA_DIR:?Set SOMBRERO_MEDIA_DIR to the provisioned media directory}"
exec .venv/bin/python -m uvicorn sombrero_server.app:create_app --factory --host 127.0.0.1 --port "${SOMBRERO_PORT:-8765}" --workers 1 --no-access-log
