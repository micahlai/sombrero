"""Apply public release settings to a staged bundle; never store private keys."""
import base64
import os
import plistlib
import re
import sys
from pathlib import Path
from urllib.parse import urlparse

path = Path(sys.argv[1])
info = plistlib.loads(path.read_bytes())
for variable, key in [("SOMBRERO_VERSION", "CFBundleShortVersionString"), ("SOMBRERO_BUILD", "CFBundleVersion")]:
    if variable in os.environ:
        value = os.environ[variable]
        if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", value):
            raise SystemExit(f"Invalid {variable}")
        info[key] = value
if os.environ.get("SOMBRERO_SPARKLE") == "1":
    feed = os.environ["SOMBRERO_UPDATE_FEED"]
    parsed = urlparse(feed)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password or parsed.fragment:
        raise SystemExit("Update feed must be a public HTTPS URL without credentials")
    key = os.environ["SOMBRERO_UPDATE_PUBLIC_KEY"]
    if len(base64.b64decode(key, validate=True)) != 32:
        raise SystemExit("Expected a 32-byte Sparkle public key")
    info.update(SUFeedURL=feed, SUPublicEDKey=key, SUEnableAutomaticChecks=True,
                SUAutomaticallyUpdate=True, SUAllowsAutomaticUpdates=True,
                SUScheduledCheckInterval=86400, SUSendProfileInfo=False,
                SUVerifyUpdateBeforeExtraction=True)
path.write_bytes(plistlib.dumps(info))
