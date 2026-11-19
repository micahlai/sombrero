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
swift build --disable-sandbox --cache-path "$PWD/.build/package-cache" -c "$configuration"
bin_dir="$(swift build --disable-sandbox --cache-path "$PWD/.build/package-cache" -c "$configuration" --show-bin-path)"
app_path="$PWD/build/WatercolorDuck.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$bin_dir/WatercolorDuck" "$app_path/Contents/MacOS/WatercolorDuck"
# SwiftPM's resource bundle must sit beside the executable in the signed app.
for resource_bundle in "$bin_dir"/*.bundle; do
    [[ -d "$resource_bundle" ]] && cp -R "$resource_bundle" "$app_path/Contents/Resources/"
done
cp macOS/Info.plist "$app_path/Contents/Info.plist"
codesign --force --sign - "$app_path"
echo "$app_path"
