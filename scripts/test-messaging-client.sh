#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-module-cache"
swift build --disable-sandbox --cache-path "$PWD/.build/package-cache"
bin_dir="$(swift build --disable-sandbox --cache-path "$PWD/.build/package-cache" --show-bin-path)"
if [[ -f "$bin_dir/PetCore.o" ]]; then
    module_path="$bin_dir"
    objects=("$bin_dir/PetCore.o")
else
    module_path="$bin_dir/Modules"
    objects=("$bin_dir"/PetCore.build/*.swift.o)
fi
swiftc -parse-as-library -I "$module_path" Tests/MessageClientSmoke/main.swift \
    Sources/DesktopPet/MessageService.swift Sources/DesktopPet/MessageStore.swift \
    Sources/DesktopPet/MessageCredentials.swift Sources/DesktopPet/MessageDraftStore.swift \
    "${objects[@]}" -o "$bin_dir/message-client-smoke"
"$bin_dir/message-client-smoke"
