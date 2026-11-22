#!/bin/zsh
# Prepare locally by default. --publish uploads only prebuilt public artifacts.
set -euo pipefail
cd "${0:A:h:h}"
[[ $# -ge 2 && $# -le 3 ]] || { echo 'Usage: release-macos.sh VERSION BUILD [--publish|--publish-only]' >&2; exit 1; }
export SOMBRERO_VERSION="$1" SOMBRERO_BUILD="$2"
[[ "$SOMBRERO_VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' && "$SOMBRERO_BUILD" =~ '^[1-9][0-9]*$' ]] || {
    echo 'Use a three-part version and a positive integer build number.' >&2; exit 1;
}
publish="${3:-}"
[[ -z "$publish" || "$publish" == '--publish' || "$publish" == '--publish-only' ]] || { echo 'Unknown option.' >&2; exit 1; }
repo="${SOMBRERO_RELEASE_REPO:-micahlai/sombrero}"
[[ "$repo" =~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' ]] || {
    echo 'Use a GitHub repository in OWNER/REPOSITORY format.' >&2; exit 1;
}
[[ -f macOS/update-public-key.txt ]] || { echo 'Run scripts/setup-sparkle.sh once first.' >&2; exit 1; }
export SOMBRERO_UPDATE_PUBLIC_KEY="$(cat macOS/update-public-key.txt)"
export SOMBRERO_UPDATE_FEED="https://github.com/$repo/releases/latest/download/appcast.xml"
export SOMBRERO_SPARKLE=1 SOMBRERO_UNIVERSAL=1
account='com.desktop-pet.watercolor-duck'
tag="v$SOMBRERO_VERSION-$SOMBRERO_BUILD"
release_dir="$PWD/build/releases/$tag"
archive="$release_dir/sombrero.zip"
if [[ "$publish" == '--publish-only' ]]; then
    [[ -d "$release_dir" ]] || { echo "No prepared release at $release_dir" >&2; exit 1; }
    python3 tools/prepare-release.py --verify "$release_dir" "$repo" "$tag"
    signature="$(python3 - "$release_dir/appcast.xml" <<'PY'
import sys, xml.etree.ElementTree as ET
print(ET.parse(sys.argv[1]).find('./channel/item/enclosure').get('{http://www.andymatuschak.org/xml-namespaces/sparkle}edSignature'))
PY
)"
    export DEVELOPER_DIR="${DEVELOPER_DIR:-/Library/Developer/CommandLineTools}"
    export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache"
    export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-module-cache"
    swift -module-cache-path "$PWD/.build/swift-module-cache" tools/verify-update.swift \
        macOS/update-public-key.txt "$archive" "$signature"
else
    [[ ! -e "$release_dir" ]] || {
        echo "Release already prepared. Publish it with: ./scripts/release-macos.sh $SOMBRERO_VERSION $SOMBRERO_BUILD --publish-only" >&2; exit 1;
    }
    sparkle_root="$(./scripts/prepare-sparkle.sh)"
    if ! keychain_public="$("$sparkle_root/bin/generate_keys" --account "$account" -p)"; then
        echo 'Could not read the Sparkle signing key. Run this build from your logged-in Mac Terminal.' >&2; exit 1;
    fi
    [[ "$keychain_public" == "$SOMBRERO_UPDATE_PUBLIC_KEY" ]] || { echo 'Signing key does not match installed update identity.' >&2; exit 1; }
    ./scripts/build-macos.sh release
    mkdir -p "$release_dir"
    ditto -c -k --sequesterRsrc --keepParent build/sombrero.app "$archive"
    if [[ -n "${SOMBRERO_NOTARY_PROFILE:-}" ]]; then
        [[ "${SOMBRERO_SIGN_IDENTITY:--}" != '-' ]] || { echo 'Notarization requires a Developer ID signing identity.' >&2; exit 1; }
        DEVELOPER_DIR="${SOMBRERO_XCODE_DIR:-/Applications/Xcode.app/Contents/Developer}" \
            xcrun notarytool submit "$archive" --keychain-profile "$SOMBRERO_NOTARY_PROFILE" --wait
        DEVELOPER_DIR="${SOMBRERO_XCODE_DIR:-/Applications/Xcode.app/Contents/Developer}" \
            xcrun stapler staple build/sombrero.app
        ditto -c -k --sequesterRsrc --keepParent build/sombrero.app "$archive"
    fi
    "$sparkle_root/bin/generate_appcast" --account "$account" \
        --download-url-prefix "https://github.com/$repo/releases/download/$tag/" "$release_dir"
    [[ -s "$release_dir/appcast.xml" ]] || { echo 'Signed appcast was not generated.' >&2; exit 1; }
    python3 tools/prepare-release.py "$release_dir" "$repo" "$tag"
fi
if [[ -n "$publish" ]]; then
    # This path intentionally never changes source-repository visibility.
    visibility="$(gh repo view "$repo" --json visibility --jq .visibility)"
    [[ "$visibility" == 'PUBLIC' ]] || { echo 'Release repository must already exist and be public.' >&2; exit 1; }
    latest_dir="$(mktemp -d "$PWD/.build/release-latest.XXXXXX")"
    trap 'rm -rf "$latest_dir"' EXIT
    latest_tag="$(gh release list --repo "$repo" --limit 100 --json tagName,isLatest --jq '.[] | select(.isLatest) | .tagName')"
    if [[ -n "$latest_tag" ]]; then
        gh release download "$latest_tag" --repo "$repo" --pattern appcast.xml --dir "$latest_dir"
        python3 tools/prepare-release.py --check-build "$latest_dir/appcast.xml" "$SOMBRERO_BUILD"
    fi
    gh release create "$tag" --repo "$repo" --draft --title "sombrero $SOMBRERO_VERSION ($SOMBRERO_BUILD)" \
        --notes-file "$release_dir/release-notes.md" \
        "$archive" "$release_dir/appcast.xml" "$release_dir/install.sh" "$release_dir/SHA256SUMS"
    gh release edit "$tag" --repo "$repo" --draft=false --latest
    echo "Published https://github.com/$repo/releases/tag/$tag"
fi
echo "Prepared $release_dir"
if [[ -n "$publish" ]]; then
    echo "Other Mac: curl -fsSL --proto '=https' --proto-redir '=https' https://github.com/$repo/releases/latest/download/install.sh | /bin/sh"
else
    echo 'LOCAL ONLY: nothing was uploaded to GitHub.'
    echo "Publish this prepared release: ./scripts/release-macos.sh $SOMBRERO_VERSION $SOMBRERO_BUILD --publish-only"
fi
