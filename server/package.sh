#!/bin/sh
# An explicit allowlist prevents credential files, databases and uploads entering
# a deployment archive, even if local development data exists beside the code.
set -eu
cd "$(dirname "$0")"
mkdir -p ../build
tar -czf ../build/sombrero-server.tar.gz \
    README.md requirements.txt requirements-test.txt run-local.sh package.sh setup-pi.sh \
    deploy/Caddyfile deploy/sombrero.service deploy/server.env.example \
    sombrero_server/__init__.py sombrero_server/app.py \
    sombrero_server/store.py sombrero_server/provision.py \
    tests/test_store.py tests/test_http.py
printf '%s\n' "$PWD/../build/sombrero-server.tar.gz"
