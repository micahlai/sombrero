#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
version="$(python3 -c 'import json; print(json.load(open("macOS/sparkle.json"))["version"])')"
url="$(python3 -c 'import json; print(json.load(open("macOS/sparkle.json"))["url"])')"
checksum="$(python3 -c 'import json; print(json.load(open("macOS/sparkle.json"))["sha256"])')"
destination="$PWD/.build/sparkle/$version"
mkdir -p "$destination"
archive="$destination/Sparkle.zip"
if [[ ! -f "$archive" ]]; then
    curl --fail --location --proto '=https' --proto-redir '=https' --connect-timeout 15 \
        --retry 2 "$url" -o "$archive.part"
    mv "$archive.part" "$archive"
fi
actual="$(shasum -a 256 "$archive" | cut -d ' ' -f 1)"
[[ "$actual" == "$checksum" ]] || { echo 'Sparkle checksum mismatch; refusing to use archive.' >&2; exit 1; }
# Re-extract the verified archive rather than trusting previously extracted code.
ditto -x -k "$archive" "$destination"
[[ -d "$destination/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" ]] || {
    echo 'Expected universal Sparkle framework is missing.' >&2; exit 1;
}
echo "$destination"
