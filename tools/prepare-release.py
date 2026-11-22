"""Validate signed feed metadata and render a stock-macOS bootstrap installer."""
import hashlib
import os
import re
import sys
import xml.etree.ElementTree as ET
import plistlib
import zipfile
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

verify_only = sys.argv[1] == "--verify"
arguments = sys.argv[2:] if verify_only else sys.argv[1:]
directory, repo, tag = Path(arguments[0]), arguments[1], arguments[2]
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
short_version = item.findtext("sparkle:shortVersionString", namespaces=namespace) or enclosure.get("{"+namespace["sparkle"]+"}shortVersionString")
if short_version and short_version != os.environ["SOMBRERO_VERSION"]:
    raise SystemExit("Appcast version differs from requested release version")
if verify_only:
    expected_sum = f"{digest}  sombrero.zip\n"
    if (directory / "SHA256SUMS").read_text() != expected_sum:
        raise SystemExit("Prepared archive checksum changed; refusing to publish")
    installer = (directory / "install.sh").read_text()
    if f"archive_url='{url}'" not in installer or f"archive_sha256='{digest}'" not in installer:
        raise SystemExit("Prepared installer does not match this archive")
    if not (directory / "release-notes.md").is_file():
        raise SystemExit("Prepared release notes are missing")
    with zipfile.ZipFile(archive) as bundle:
        info = plistlib.loads(bundle.read("sombrero.app/Contents/Info.plist"))
    required = {"CFBundleIdentifier":"com.desktop-pet.watercolor-duck", "CFBundleVersion":version,
                "CFBundleShortVersionString":os.environ["SOMBRERO_VERSION"],
                "SUPublicEDKey":os.environ["SOMBRERO_UPDATE_PUBLIC_KEY"],
                "SUFeedURL":f"https://github.com/{repo}/releases/latest/download/appcast.xml"}
    if any(info.get(key) != value for key, value in required.items()):
        raise SystemExit("Prepared app identity, version, signing key, or update feed does not match")
    print(f"Verified prepared release {tag}; existing artifacts were not modified.")
    raise SystemExit(0)
template = Path("scripts/install-macos.sh.in").read_text()
(directory / "install.sh").write_text(template.replace("@ARCHIVE_URL@", url).replace("@ARCHIVE_SHA256@", digest))
(directory / "SHA256SUMS").write_text(f"{digest}  sombrero.zip\n")
(directory / "release-notes.md").write_text(
    f"sombrero {os.environ['SOMBRERO_VERSION']} ({version}) for Intel and Apple Silicon Macs running macOS 13 or later.\n\n"
    "Includes signed Sparkle updates and one-use message setup. Camera access must be approved on this Mac.\n\n" +
    ("Developer ID signed; notarization is enabled for this release.\n" if os.environ.get("SOMBRERO_NOTARY_PROFILE") else
     "This build is not notarized. macOS may require approval in System Settings → Privacy & Security before first launch.\n"))
