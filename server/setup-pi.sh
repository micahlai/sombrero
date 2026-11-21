#!/bin/sh
# First installation on the inspected Debian Pi. Private service only: no DNS,
# router, firewall, Caddy or public exposure is configured by this script.
set -eu
cd "$(dirname "$0")"
install_dir="$(pwd -P)"
if [ "$(uname -s)" != Linux ] || ! command -v systemctl >/dev/null 2>&1; then
    echo 'Run this installer on the Debian Pi, not on the Mac.' >&2; exit 1
fi
if [ "$(id -u)" -eq 0 ]; then
    echo 'Run as the normal admin account, not with sudo.' >&2; exit 1
fi
case "$install_dir:$HOME" in
    *[!a-zA-Z0-9_./:-]*) echo 'Use an installation/home path without spaces or special characters.' >&2; exit 1 ;;
esac
python3 -c 'import sys; assert sys.version_info >= (3,10), "Python 3.10+ is required"'
config_dir="$HOME/.config/sombrero"
data_dir="$HOME/.local/share/sombrero"
media_dir="$data_dir/media"
credentials_dir="$config_dir/device-credentials"
public_url="${SOMBRERO_PUBLIC_URL:-https://sombrero.micahlai.com}"
if [ -e "$config_dir/server.env" ] || [ -e "$data_dir/devices.json" ] || [ -e "$data_dir/messages.sqlite3" ]; then
    echo 'Existing setup detected. Refusing to replace its settings, identities or message history.' >&2
    echo 'For an installed service, use: sudo systemctl status sombrero' >&2; exit 1
fi
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements-test.txt
PYTHONPATH=. .venv/bin/python -m unittest discover -s tests -v
umask 077
mkdir -p "$config_dir" "$data_dir"
.venv/bin/python -m sombrero_server.provision \
    --data-dir "$data_dir" --media-dir "$media_dir" \
    --credentials-dir "$credentials_dir" --base-url "$public_url" --initialize-media
cat > "$config_dir/server.env" <<EOF
SOMBRERO_DATA_DIR=$data_dir
SOMBRERO_MEDIA_DIR=$media_dir
SOMBRERO_MAX_IMAGE_BYTES=10485760
SOMBRERO_MAX_VIDEO_BYTES=104857600
EOF
chmod 600 "$config_dir/server.env"
unit_file="$(mktemp)"
trap 'rm -f "$unit_file"' EXIT HUP INT TERM
cat > "$unit_file" <<EOF
[Unit]
Description=sombrero two-device messaging
After=network-online.target
Wants=network-online.target
RequiresMountsFor=$data_dir

[Service]
Type=simple
User=$(id -un)
Group=$(id -gn)
WorkingDirectory=$install_dir
EnvironmentFile=$config_dir/server.env
ExecStart=$install_dir/.venv/bin/uvicorn sombrero_server.app:create_app --factory --host 127.0.0.1 --port 8765 --workers 1 --no-access-log --proxy-headers --forwarded-allow-ips=127.0.0.1
Restart=on-failure
RestartSec=5
UMask=0077
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=$data_dir

[Install]
WantedBy=multi-user.target
EOF
sudo install -m 644 "$unit_file" /etc/systemd/system/sombrero.service
sudo systemctl daemon-reload
sudo systemctl enable --now sombrero
sudo systemctl --no-pager --full status sombrero
.venv/bin/python - <<'PY'
import time, urllib.request
for attempt in range(30):
    try:
        print(urllib.request.urlopen("http://127.0.0.1:8765/v1/health", timeout=2).read().decode())
        break
    except OSError:
        if attempt == 29:
            raise SystemExit("Service did not become ready. Inspect: sudo journalctl -u sombrero -n 50 --no-pager")
        time.sleep(1)
PY
echo 'Local service is ready. The public HTTPS/DNS route is a separate next step.'
echo 'Import one private device credential file on each Mac; never paste the tokens into chat.'
