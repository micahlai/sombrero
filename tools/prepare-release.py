"""Validate signed feed metadata and render a stock-macOS bootstrap installer."""
import hashlib
import os
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

namespace = {"sparkle":"http://www.andymatuschak.org/xml-namespaces/sparkle"}
if sys.argv[1] == "--check-build":
    root = ET.parse(sys.argv[2]).getroot()
    versions = [item.findtext("sparkle:version", namespaces=namespace) or
                item.find("enclosure").get("{"+namespace["sparkle"]+"}version", "")
                for item in root.findall("./channel/item")]
    if not versions or any(not v.isdigit() or int(v) >= int(sys.argv[3]) for v in versions):
        raise SystemExit("Build number must exceed every build in the published feed")
    raise SystemExit(0)

directory, repo, tag = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repo) or not re.fullmatch(r"v[0-9.]+-[0-9]+", tag):
    raise SystemExit("Invalid release URL components")
archive = directory / "sombrero.zip"
digest = hashlib.sha256(archive.read_bytes()).hexdigest()
url = f"https://github.com/{repo}/releases/download/{tag}/sombrero.zip"
feed = ET.parse(directory / "appcast.xml").getroot()
items = feed.findall("./channel/item")
if len(items) != 1:
    raise SystemExit("Expected exactly one release in the generated feed")
item = items[0]
enclosure = item.find("enclosure")
if enclosure is None or enclosure.get("url") != url or not enclosure.get("{"+namespace["sparkle"]+"}edSignature") or int(enclosure.get("length", "0")) != archive.stat().st_size:
    raise SystemExit("Release archive does not match the signed appcast")
version = item.findtext("sparkle:version", namespaces=namespace) or enclosure.get("{"+namespace["sparkle"]+"}version")
if version != os.environ["SOMBRERO_BUILD"]:
    raise SystemExit("Appcast build differs from requested release build")
template = Path("scripts/install-macos.sh.in").read_text()
(directory / "install.sh").write_text(template.replace("@ARCHIVE_URL@", url).replace("@ARCHIVE_SHA256@", digest))
(directory / "SHA256SUMS").write_text(f"{digest}  sombrero.zip\n")
(directory / "release-notes.md").write_text(
    f"sombrero {os.environ['SOMBRERO_VERSION']} ({version}) for Intel and Apple Silicon Macs running macOS 13 or later.\n\n"
    "Includes signed Sparkle updates and one-use message setup. Camera access must be approved on this Mac.\n\n" +
    ("Developer ID signed; notarization is enabled for this release.\n" if os.environ.get("SOMBRERO_NOTARY_PROFILE") else
     "This build is not notarized. macOS may require approval in System Settings → Privacy & Security before first launch.\n"))
