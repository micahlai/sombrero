#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-module-cache"
swift build --disable-sandbox --cache-path "$PWD/.build/package-cache"
bin_dir="$(swift build --disable-sandbox --cache-path "$PWD/.build/package-cache" --show-bin-path)"
if [[ -f "$bin_dir/PetCore.o" ]]; then
    module_path="$bin_dir"; objects=("$bin_dir/PetCore.o" "$bin_dir/PetAssets.o")
else
    module_path="$bin_dir/Modules"; objects=("$bin_dir"/PetCore.build/*.swift.o "$bin_dir"/PetAssets.build/*.swift.o)
fi
mkdir -p .build/message-windows-smoke
cp Tests/Fixtures/message-video.mp4 .build/message-windows-smoke/cached-video.mp4
swiftc -I "$module_path" Tests/MessageWindowsSmoke/main.swift Sources/DesktopPet/MessageWindows.swift Sources/DesktopPet/PolaroidView.swift \
    "${objects[@]}" -o "$bin_dir/message-windows-smoke"
"$bin_dir/message-windows-smoke"
