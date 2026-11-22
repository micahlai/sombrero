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
build_args=(-c "$configuration")
if [[ "${SOMBRERO_UNIVERSAL:-0}" == 1 ]]; then
    build_args+=(--arch arm64 --arch x86_64)
fi
sparkle_root=""
if [[ "${SOMBRERO_SPARKLE:-0}" == 1 ]]; then
    sparkle_root="$(./scripts/prepare-sparkle.sh)"
    framework_dir="$sparkle_root/Sparkle.xcframework/macos-arm64_x86_64"
    build_args+=(-Xswiftc -DSOMBRERO_SPARKLE -Xswiftc -F -Xswiftc "$framework_dir"
        -Xlinker -F -Xlinker "$framework_dir" -Xlinker -rpath -Xlinker '@executable_path/../Frameworks')
    [[ -n "${SOMBRERO_UPDATE_FEED:-}" && -n "${SOMBRERO_UPDATE_PUBLIC_KEY:-}" ]] || {
        echo 'Set SOMBRERO_UPDATE_FEED and SOMBRERO_UPDATE_PUBLIC_KEY for an update-enabled build.' >&2; exit 1;
    }
fi
python3 tools/import-final-sprites.py
swift build --disable-sandbox --cache-path "$PWD/.build/package-cache" "${build_args[@]}"
bin_dir="$(swift build --disable-sandbox --cache-path "$PWD/.build/package-cache" "${build_args[@]}" --show-bin-path)"
mkdir -p "$PWD/build" "$PWD/.build"
staging="$(mktemp -d "$PWD/.build/app-stage.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
app_path="$staging/sombrero.app"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$bin_dir/sombrero" "$app_path/Contents/MacOS/sombrero"
# SwiftPM's resource bundle must sit beside the executable in the signed app.
resource_bundle="$bin_dir/sombrero_PetAssets.bundle"
ditto "$resource_bundle" "$app_path/Contents/Resources/${resource_bundle:t}"
cp macOS/Info.plist "$app_path/Contents/Info.plist"
cp macOS/AppIcon.icns "$app_path/Contents/Resources/AppIcon.icns"
if [[ -n "$sparkle_root" ]]; then
    mkdir -p "$app_path/Contents/Frameworks"
    ditto "$framework_dir/Sparkle.framework" "$app_path/Contents/Frameworks/Sparkle.framework"
fi
python3 tools/configure-app-bundle.py "$app_path/Contents/Info.plist"
python3 tools/sign-app-bundle.py "$app_path"
codesign --verify --deep --strict "$app_path"
# Replace only our generated product after the new bundle has passed verification.
if [[ -d "$PWD/build/sombrero.app" ]]; then
    previous="$staging/previous.app"
    mv "$PWD/build/sombrero.app" "$previous"
fi
mv "$app_path" "$PWD/build/sombrero.app"
app_path="$PWD/build/sombrero.app"
# Retain the previous generated bundle as a recoverable backup after a successful rename.
legacy_app="$PWD/build/WatercolorDuck.app"
legacy_backup="$PWD/.build/legacy-app-backup/WatercolorDuck.app"
if [[ -d "$legacy_app" && ! -e "$legacy_backup" ]]; then
    mkdir -p "${legacy_backup:h}"
    mv "$legacy_app" "$legacy_backup"
fi
echo "$app_path"
