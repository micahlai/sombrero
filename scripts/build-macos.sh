#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

# A separately installed Command Line Tools toolchain avoids depending on a full Xcode installation.
if [[ -z "${DEVELOPER_DIR:-}" && -x /Library/Developer/CommandLineTools/usr/bin/swift ]]; then
    export DEVELOPER_DIR=/Library/Developer/CommandLineTools
fi
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-module-cache"
configuration="${1:-debug}"
python3 tools/import-final-sprites.py
swift build --disable-sandbox --cache-path "$PWD/.build/package-cache" -c "$configuration"
bin_dir="$(swift build --disable-sandbox --cache-path "$PWD/.build/package-cache" -c "$configuration" --show-bin-path)"
app_path="$PWD/build/sombrero.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$bin_dir/sombrero" "$app_path/Contents/MacOS/sombrero"
# SwiftPM's resource bundle must sit beside the executable in the signed app.
resource_bundle="$bin_dir/sombrero_PetAssets.bundle"
ditto "$resource_bundle" "$app_path/Contents/Resources/${resource_bundle:t}"
cp macOS/Info.plist "$app_path/Contents/Info.plist"
codesign --force --sign - --entitlements macOS/entitlements.plist "$app_path"
codesign --verify "$app_path"
# Retain the previous generated bundle as a recoverable backup after a successful rename.
legacy_app="$PWD/build/WatercolorDuck.app"
legacy_backup="$PWD/.build/legacy-app-backup/WatercolorDuck.app"
if [[ -d "$legacy_app" && ! -e "$legacy_backup" ]]; then
    mkdir -p "${legacy_backup:h}"
    mv "$legacy_app" "$legacy_backup"
fi
echo "$app_path"
