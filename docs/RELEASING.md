# sombrero distribution

## Current status

Prepared in source: Sparkle updater and its menu/preferences, pinned Sparkle 2.10.1 download with the publisher's SwiftPM SHA-256, universal packaging, inside-out Developer ID signing when configured, optional notarization, signed appcast generation, GitHub Release publishing, and a first-install script requiring only stock macOS tools. The ordinary debug build remains usable offline without Sparkle.

The user subsequently ran setup and built `build/releases/v0.1.0-1/`. Its archive checksum, app identity, embedded update key/feed, and real Sparkle Ed25519 signature have been verified locally. It is an unnotarized build. The public release has not been verified or published by this session: shell GitHub operations still fail to connect. Clean-Mac installation and updates between two real releases remain untested. Do not describe the other-Mac command as live until publication succeeds.

The corrected **0.1.1 / build 2** application is now built at `build/sombrero.app`, with the real Sparkle framework linked and embedded, both arm64/x86_64 slices, and `https://github.com/micahlai/sombrero/releases/latest/download/appcast.xml` embedded as its feed. Deep/strict code-signature verification passed. Release building here required `SOMBRERO_DEBUG_INFO_FORMAT=none` because the environment blocked dSYM generation; debug symbols are optional and the ordinary default remains unchanged. Six release-tool checks pass.

**Publication is still blocked in this session:** reading the existing Sparkle signing key returns Keychain error `-50`, and GitHub API requests fail to connect. The old key was not rotated or exported. There is no signed/published 0.1.1 archive from this session. From the owner's logged-in Terminal, the concrete release command is `./scripts/release-macos.sh 0.1.1 2 --publish` (set `SOMBRERO_DEBUG_INFO_FORMAT=none` only if the same dSYM failure occurs there). The source repository must be public; the user authorized `gh repo edit micahlai/sombrero --visibility public --accept-visibility-change-consequences`, but that request could not connect from this session.

Apple Developer Team ID supplied by the user: `98RU8TVC42`. The latest local identity check still found no valid signing identities; a Team ID alone does not provide a Developer ID Application certificate/private key.

The user chose one public repository: `micahlai/sombrero` hosts both source and GitHub Releases. It is now the default for appcast URLs, archives and the installer. The user is deleting the earlier separate `sombrero-releases` repository. No GitHub token or messaging credentials go into a public artifact. The attempted visibility change from this session failed to connect to GitHub, so remote public visibility still needs verification.

## One-time release setup on the developer Mac

Once the developer Mac can reach GitHub:

```sh
./scripts/setup-sparkle.sh
gh repo edit micahlai/sombrero --visibility public --accept-visibility-change-consequences
```

The setup script invokes Sparkle's official key tool with the product's dedicated Keychain account. It creates/reuses the private Ed25519 key in login Keychain and writes only the public key to `macOS/update-public-key.txt`. It refuses a mismatching existing public key. Keep the private key safe; do not export it into this checkout, public releases, logs, or chat. Commit the public key with the source after setup succeeds.

No Apple membership is required for an ad-hoc build. That path needs explicit initial launch approval and clean-Mac testing of Camera/Keychain continuity across an update. A Sparkle archive signature does not notarize the application. For Developer ID distribution, install the owner's existing signing identity and configure these optional settings locally:

```sh
export SOMBRERO_SIGN_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)'
export SOMBRERO_NOTARY_PROFILE='your-existing-notarytool-keychain-profile'
```

Do not purchase a membership or generate/upload Apple credentials as part of a routine build.

## Prepare and publish a release

Use a new, increasing positive integer build number; the semantic version and build are separate. The bundle identifier stays `com.desktop-pet.watercolor-duck`.

```sh
./scripts/release-macos.sh 0.2.0 2
```

This prepares `build/releases/v0.2.0-2/` without publishing. It builds both arm64 and x86_64, embeds Sparkle with symlinks intact, configures an HTTPS appcast and public verification key, signs the app, and signs the archive/appcast metadata using Sparkle's Keychain key. Automatic checking and downloading/installing updates default on; the user's subsequent Sparkle preference changes persist. The release feed URL is the public repository's stable `/releases/latest/download/appcast.xml` asset, so GitHub Pages is not needed.

The optional notarization step submits the archive, waits for acceptance, staples the application, and regenerates the archive before Sparkle signing. Without it, release notes identify the build as unnotarized.

Inspect the generated application, appcast, installer, checksums and release notes before publishing:

```sh
./scripts/release-macos.sh 0.2.0 2 --publish-only
```

Without a flag, the script prepares locally and explicitly reports that nothing was uploaded. `--publish-only` verifies the existing archive, installer/checksums, bundled version/identity/update key/feed, and Ed25519 signature using the public key; it does not rebuild, modify artifacts, or access the private signing key. The old `v0.1.0-1` archive embeds the removed repository’s update URL and cannot be republished unchanged to `sombrero`. Build and publish the corrected next release with `./scripts/release-macos.sh 0.1.1 2 --publish`.

`--publish` builds a new version and publishes it in one invocation; use it only with an unused version/build directory. Both publishing modes verify that the target repository is public, reject build numbers at or below the published feed, upload the artifacts into a draft, then publish it as latest. A GitHub failure when looking up published builds stops publication rather than bypassing the version check. If an upload fails, inspect/recover the draft with `gh`; do not silently overwrite an existing tag or reuse a published build number. An existing prepared directory can be published with `--publish-only`.

## Other Mac: one command after publication

After the actual public release is verified, the release script prints:

```sh
curl -fsSL --proto '=https' --proto-redir '=https' https://github.com/micahlai/sombrero/releases/latest/download/install.sh | /bin/sh
```

**This URL is planned, not published by this session.** The command needs macOS 13+, Internet and Terminal; no Homebrew, Git, Python, Xcode, or sudo. The downloaded installer contains a version-specific HTTPS archive URL and expected SHA-256. It verifies the downloaded bytes, bundle identity and code signature, installs to `~/Applications/sombrero.app`, preserves Gatekeeper approval using quarantine metadata, launches the app, and opens message setup after the existing Camera permission flow. It does not replace an existing app; installed users use Sparkle's update menu.

For an ad-hoc/unnotarized release, the person at that Mac may need System Settings → Privacy & Security → Open Anyway. Camera access requires their approval. The installer never disables Gatekeeper or removes quarantine. No universal-architecture developer tool is invoked by the installer; both architectures are validated on the developer Mac before publishing.

## Private message enrollment

The new `POST /v1/enrollments/redeem` endpoint and native secure setup-code field are implemented locally, **not yet deployed to the existing Pi**. The deployment archive's explicit allowlist includes this code and its tests. Upgrade existing server source and restart `sombrero.service`; do not run first-run provisioning or replace its private data/config directories. Existing two-device tokens, pairing, media and history must remain intact.

On the Pi, with the service's existing `SOMBRERO_DATA_DIR` and `SOMBRERO_MEDIA_DIR` environment set, create a one-use code from the **second device's existing private export**:

```sh
cd /home/admin/sombrero/server
.venv/bin/python -m sombrero_server.enrollment \
  --device-file /home/admin/.config/sombrero/device-credentials/device-2.json \
  --base-url https://home-lab.tail4869fe.ts.net \
  --output /home/admin/.config/sombrero/device-credentials/device-2-setup.json
```

The output is a mode-0600 private JSON file, never printed by the tool. Open it privately on the Pi and transfer its `setupCode` directly to the secure connection field on the other Mac. Codes contain 256 random bits, expire after 15 minutes, and can be redeemed once. Issuing a newer code invalidates the older code for that device. No third device is provisioned; this authorizes the existing second identity. The setup code travels in an Authorization header over the configured HTTPS origin, never a URL/command argument or public script. The returned normal device token is verified with `/v1/me` and stored using the existing Keychain path.

Pending enrollment temporarily stores the existing device credential in the private SQLite database so it can be returned once; the code itself is stored only as a SHA-256 hash. Expired rows are removed during subsequent enrollment creation/redemption. Protect this database and existing device exports as credentials. If redemption consumes a code but the response is lost or local Keychain saving fails, issue a new code; the client does not automatically replay the one-use request. Do not share a first-device code with the second Mac.

## Validation

Local checks cover all-day verses and saved-schedule migration, menu visibility, acknowledged-send animation gating, single-use enrollment, expiry/replacement, concurrent redemption, credential and pair validation, and existing message persistence. Web transport tests require `server/requirements-test.txt`; they are skipped on this host because FastAPI/httpx are unavailable. Live Funnel access and cross-Mac camera/message/update acceptance remain pending.

Before shipping, test two successive real releases on a clean Mac: first-launch approval, Camera approval, setup redemption, sending/receiving, keeping/resizing a card, automatic/manual update, relaunch, and retention of permissions, Keychain connection, drafts/outbox and daily Bible state. This is especially necessary for the free ad-hoc signing path.

Official references: [Sparkle setup](https://sparkle-project.org/documentation/), [programmatic API](https://sparkle-project.org/documentation/programmatic-setup/), [publishing](https://sparkle-project.org/documentation/publishing/), and [pinned publisher manifest](https://github.com/sparkle-project/Sparkle/blob/2.10.1/Package.swift).
