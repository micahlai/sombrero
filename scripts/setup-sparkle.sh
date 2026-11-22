#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
sparkle_root="$(./scripts/prepare-sparkle.sh)"
account='com.desktop-pet.watercolor-duck'
# Sparkle creates/reuses the private key directly in login Keychain. Only its
# public half is written into this checkout. Never export the private key here.
"$sparkle_root/bin/generate_keys" --account "$account"
public_key="$("$sparkle_root/bin/generate_keys" --account "$account" -p)"
SOMBRERO_NEW_PUBLIC_KEY="$public_key" python3 - <<'PY'
import base64, os
from pathlib import Path
value=os.environ['SOMBRERO_NEW_PUBLIC_KEY'].strip()
if len(base64.b64decode(value,validate=True)) != 32:
    raise SystemExit('Sparkle did not return a valid public key')
path=Path('macOS/update-public-key.txt')
if path.exists() and path.read_text().strip() != value:
    raise SystemExit('Existing public key differs; refusing to rotate the update identity')
path.write_text(value+'\n')
PY
echo 'Sparkle signing is configured. The private key remains in login Keychain.'
