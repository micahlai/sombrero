"""Sign nested release code inside out; default to local ad-hoc signing."""
import os
import subprocess
import sys
from pathlib import Path

app = Path(sys.argv[1]).resolve()
identity = os.environ.get("SOMBRERO_SIGN_IDENTITY", "-")
options = ["--options", "runtime", "--timestamp"] if identity != "-" else []
frameworks = app / "Contents/Frameworks"
if frameworks.exists():
    # Preserve Sparkle's vendor signatures for local ad-hoc builds. Developer ID
    # releases require all nested code to be signed with our distribution identity.
    if identity != "-":
        files, bundles = [], []
        for root, dirs, names in os.walk(frameworks, followlinks=False):
            dirs[:] = [d for d in dirs if not (Path(root) / d).is_symlink()]
            for name in names:
                path = Path(root) / name
                if path.is_symlink():
                    continue
                kind = subprocess.check_output(["/usr/bin/file", "-b", str(path)], text=True)
                if "Mach-O" in kind:
                    files.append(path)
            for name in dirs:
                path = Path(root) / name
                if path.suffix in (".app", ".xpc", ".framework"):
                    bundles.append(path)
        for path in files + sorted(bundles, key=lambda p: len(p.parts), reverse=True):
            subprocess.run(["/usr/bin/codesign", "--force", "--sign", identity, *options, str(path)], check=True)
subprocess.run(["/usr/bin/codesign", "--force", "--sign", identity, *options,
                "--entitlements", "macOS/entitlements.plist", str(app)], check=True)
