import base64
import hashlib
import os
import plistlib
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"


class ReleaseToolsTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.env = {**os.environ, "SOMBRERO_VERSION":"0.2.0", "SOMBRERO_BUILD":"2"}
        for name in ["SOMBRERO_SPARKLE", "SOMBRERO_NOTARY_PROFILE"]:
            self.env.pop(name, None)

    def run_tool(self, name, *args, success=True, env=None):
        result = subprocess.run([sys.executable, str(ROOT / "tools" / name), *map(str, args)],
                                cwd=ROOT, env=env or self.env, capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def test_bundle_preserves_identity_and_requires_valid_public_update_settings(self):
        path = self.root / "Info.plist"
        original = plistlib.loads((ROOT / "macOS/Info.plist").read_bytes())
        path.write_bytes(plistlib.dumps(original))
        env = {**self.env, "SOMBRERO_SPARKLE":"1", "SOMBRERO_UPDATE_FEED":"https://example.net/appcast.xml",
               "SOMBRERO_UPDATE_PUBLIC_KEY":base64.b64encode(bytes(32)).decode()}
        self.run_tool("configure-app-bundle.py", path, env=env)
        info = plistlib.loads(path.read_bytes())
        self.assertEqual(info["CFBundleIdentifier"], original["CFBundleIdentifier"])
        self.assertEqual(info["CFBundleVersion"], "2")
        self.assertTrue(info["SUVerifyUpdateBeforeExtraction"])
        self.assertTrue(info["SUAutomaticallyUpdate"])
        for feed in ["http://example.net/feed", "https://secret@example.net/feed"]:
            self.run_tool("configure-app-bundle.py", path, env={**env,"SOMBRERO_UPDATE_FEED":feed}, success=False)
        self.run_tool("configure-app-bundle.py", path, env={**env,"SOMBRERO_UPDATE_PUBLIC_KEY":"bad"}, success=False)

    def feed(self, version="2", url="https://github.com/example/releases/releases/download/v0.2.0-2/sombrero.zip"):
        archive = self.root / "sombrero.zip"
        archive.write_bytes(b"release fixture")
        feed = self.root / "appcast.xml"
        feed.write_text(f'''<rss xmlns:sparkle="{NS}"><channel><item><sparkle:version>{version}</sparkle:version>
            <enclosure url="{url}" length="{archive.stat().st_size}" sparkle:edSignature="fixture-signature"/>
            </item></channel></rss>''')
        return feed

    def test_installer_has_immutable_download_checksum_and_valid_stock_shell(self):
        self.feed()
        self.run_tool("prepare-release.py", self.root, "example/releases", "v0.2.0-2")
        installer = self.root / "install.sh"
        text = installer.read_text()
        self.assertIn(hashlib.sha256((self.root / "sombrero.zip").read_bytes()).hexdigest(), text)
        self.assertIn("/releases/download/v0.2.0-2/sombrero.zip", text)
        self.assertNotIn("@ARCHIVE_", text)
        self.assertNotIn("/usr/bin/lipo", text)
        self.assertNotIn("xattr -d", text)
        subprocess.run(["/bin/sh", "-n", str(installer)], check=True)

    def test_source_repository_can_host_release_and_installer(self):
        self.feed(url="https://github.com/micahlai/sombrero/releases/download/v0.2.0-2/sombrero.zip")
        self.run_tool("prepare-release.py", self.root, "micahlai/sombrero", "v0.2.0-2")
        installer = (self.root / "install.sh").read_text()
        self.assertIn("https://github.com/micahlai/sombrero/releases/download/v0.2.0-2/sombrero.zip", installer)
        self.assertNotIn("sombrero-releases", installer)

    def test_prepared_release_for_old_repository_cannot_be_republished_to_source(self):
        self.feed(url="https://github.com/micahlai/sombrero-releases/releases/download/v0.2.0-2/sombrero.zip")
        self.run_tool("prepare-release.py", self.root, "micahlai/sombrero-releases", "v0.2.0-2")
        before = {path.name:path.read_bytes() for path in self.root.iterdir()}
        self.run_tool("prepare-release.py", "--verify", self.root, "micahlai/sombrero", "v0.2.0-2", success=False)
        self.assertEqual({path.name:path.read_bytes() for path in self.root.iterdir()}, before)

    def test_release_refuses_wrong_archive_metadata_and_nonincreasing_build(self):
        feed = self.feed()
        self.run_tool("prepare-release.py", "--check-build", feed, "3")
        self.run_tool("prepare-release.py", "--check-build", feed, "2", success=False)
        self.run_tool("prepare-release.py", "--check-build", feed, "1", success=False)
        (self.root / "sombrero.zip").write_bytes(b"different archive size")
        self.run_tool("prepare-release.py", self.root, "example/releases", "v0.2.0-2", success=False)
        self.feed(url="https://wrong.example.net/sombrero.zip")
        self.run_tool("prepare-release.py", self.root, "example/releases", "v0.2.0-2", success=False)

    def test_publish_only_verifies_existing_artifacts_without_modifying_them(self):
        import zipfile
        self.feed()
        self.env["SOMBRERO_UPDATE_PUBLIC_KEY"] = base64.b64encode(bytes(32)).decode()
        info = {"CFBundleIdentifier":"com.desktop-pet.watercolor-duck", "CFBundleVersion":"2",
                "CFBundleShortVersionString":"0.2.0", "SUPublicEDKey":self.env["SOMBRERO_UPDATE_PUBLIC_KEY"],
                "SUFeedURL":"https://github.com/example/releases/releases/latest/download/appcast.xml"}
        archive = self.root / "sombrero.zip"
        old_length = archive.stat().st_size
        with zipfile.ZipFile(archive, "w") as bundle:
            bundle.writestr("sombrero.app/Contents/Info.plist", plistlib.dumps(info))
        feed = self.root / "appcast.xml"
        text = feed.read_text().replace(f'length="{old_length}"', f'length="{archive.stat().st_size}"')
        feed.write_text(text)
        self.run_tool("prepare-release.py", self.root, "example/releases", "v0.2.0-2")
        before = {path.name:path.read_bytes() for path in self.root.iterdir()}
        self.run_tool("prepare-release.py", "--verify", self.root, "example/releases", "v0.2.0-2")
        self.assertEqual({path.name:path.read_bytes() for path in self.root.iterdir()}, before)
        self.run_tool("prepare-release.py", "--verify", self.root, "example/releases", "v0.2.0-2",
                      env={**self.env,"SOMBRERO_UPDATE_PUBLIC_KEY":"different-key"}, success=False)
        (self.root / "SHA256SUMS").write_text("changed checksum")
        self.run_tool("prepare-release.py", "--verify", self.root, "example/releases", "v0.2.0-2", success=False)


if __name__ == "__main__":
    unittest.main()
