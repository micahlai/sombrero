# sombrero

A native macOS desktop companion: a watercolor duck that idles, responds to petting, peeks around windows, delivers Polaroid-style messages, and reads a daily Bible passage.

Built with Swift and AppKit, with a separate Python service for private messaging between two provisioned devices. Animation and Bible reading run locally; messaging uses your own server. No LLM is part of the app.

## Features

- Transparent floating duck with dragging, size presets, click-through mode, pause, and controls for appearing above windows and across desktops.
- Frame-by-frame animation with standing, sitting, petting, waving, goodbye, screen/window entries, camera, photo, and Bible routines.
- Speech-bubble controls and a persistent menu bar icon for recovery and settings.
- Timed departures with a live return countdown and **Come back now** recovery.
- Text, image, and video messages in Polaroid-style cards, rich-text composition, saved drafts, an outbox with retry controls, and read receipts.
- Optional still-photo capture from available cameras, including supported Continuity Camera devices.
- Resizable kept Polaroids that stay above ordinary windows.
- An offline catalog of 100 World English Bible passages, with a saved daily selection available throughout the local day and refreshed at midnight.
- An animated green exclamation mark for unread incoming messages.
- Optional Sparkle updates in release builds.

## Requirements

| Task | Requirements |
| --- | --- |
| Run the native app | macOS 13 or later |
| Build the native app | macOS, Swift 5.9 or later, Xcode Command Line Tools or Xcode, Python 3 |
| Use screenshot-assisted edge placement | macOS 14 or later and Screen Recording permission |
| Run the animation lab | Python 3.10 or later and a modern browser |
| Run the messaging server | Python 3.10 or later and dependencies in `server/requirements.txt` |
| Run browser-engine tests | Node.js with its built-in test runner |
| Prepare update releases | Sparkle signing setup; GitHub CLI for publication |

The native package has no mandatory remote Swift package dependencies. Ordinary debug builds do not download or embed Sparkle. Node.js and the Python server dependencies are unnecessary for a normal native build.

## Build and run

From the repository root:

```sh
./scripts/build-macos.sh
open build/sombrero.app
```

The build script imports the current animation and notification frames, compiles the Swift package, assembles the resource bundle and app icon, and verifies the signed application before replacing the generated app. By default it produces an ad-hoc-signed debug build at `build/sombrero.app`.

For a release-configuration build without the updater:

```sh
./scripts/build-macos.sh release
```

To build both Apple silicon and Intel slices:

```sh
SOMBRERO_UNIVERSAL=1 ./scripts/build-macos.sh release
```

Launch the packaged `.app` for normal use so macOS sees its permission descriptions and bundled resources. `swift build` is useful for compilation checks but does not assemble the application bundle.

### First launch and permissions

The current startup flow requires Camera approval before the duck appears. Camera authorization alone does not start capture: preview begins when you open the camera in the message composer, and a captured photo is sent only when you press **Send**.

On macOS 14 or later, the app can optionally request Screen Recording access to detect horizontal landing edges from narrow screen crops. These crops remain in memory and are not saved or uploaded. If permission is denied, capture fails, or the system is macOS 13, the app uses geometric placement instead. You can revisit the grant through **Preferences → Allow Screen Edge Detection…** when available.

## Using the duck

| Interaction | Result |
| --- | --- |
| Click the duck | Open or close its speech menu |
| Drag the duck | Move it on screen |
| Hover over the painted duck | Trigger petting where the current animation permits it |
| Right-click the duck | Open the native control menu |
| Click the menu bar icon | Open recovery and preference controls |
| Choose **Come back now** | Recall the duck to the current screen and restore interaction |
| Choose **Click Through Pet** | Let pointer input pass through the duck; use the menu bar to recover |

The main control menu contains the return countdown, **Always on Top**, **Show on All Desktops**, **Click Through Pet**, **Pause Motion**, and **Size**. The **Preferences** submenu contains visibility controls, messaging settings, the outbox, Bible reading, animation debugging, update controls, version information, and Quit. Update availability depends on how the app was built.

Use the speech menu to send or show messages, read the day's passage, or send the duck away. **Show message** remains available when the inbox is empty; an unconfigured connection opens setup. Incoming messages and daily passages retain their unread state while the duck is away without automatically recalling it. Only unread incoming messages raise the exclamation mark; the daily passage stays available from the menu.

Window ordering follows macOS behavior. Fullscreen apps, Spaces, Stage Manager, protected system windows, and display changes need testing on the target Mac.

## Messaging

Messaging is a self-hosted, private two-device service using FastAPI, SQLite, and separate media files. Each Mac has its own bearer credential; the server derives sender, peer, and pair identity from that credential. It offers no public account registration or third-device enrollment.

### Connect a Mac

1. Open **Preferences → Message Connection…** from the control menu.
2. Enter the server's HTTPS origin.
3. Enter that Mac's one-use setup code or device token, or choose **Import Device File…**.
4. Press **Connect**.

Setup codes expire after 15 minutes, can be used once, and authorize an existing provisioned device. Issuing a replacement invalidates the previous code for that device. Device files contain private credentials; keep each one on its intended Mac and out of source control, logs, and public release artifacts.

Tokens are stored in macOS Keychain. The app keeps local message history, drafts, cached attachments, and queued sends partitioned by connection identity. It polls while running; delivery while the app is quit does not use an OS push service. A camera routine remains in its holding animation until the server acknowledges the active outgoing message.

The server can read stored message text and media; HTTPS and token authentication do not provide end-to-end encryption.

### Local server development

Run these commands in a separate terminal from the repository root:

```sh
cd server
python3 -m venv .venv
.venv/bin/python -m pip install -r requirements-test.txt
.venv/bin/python -m sombrero_server.provision \
  --data-dir "$PWD/data" --media-dir "$PWD/media" \
  --credentials-dir "$PWD/credentials" \
  --base-url http://127.0.0.1:8765 --initialize-media
export SOMBRERO_DATA_DIR="$PWD/data"
export SOMBRERO_MEDIA_DIR="$PWD/media"
./run-local.sh
```

Provisioning creates exactly two credential exports and refuses to overwrite an existing setup. **Do not rerun provisioning to repair a deployed service or fix client authorization.** Preserve its identities, database, and media. Plain HTTP is accepted by the client only for loopback development; remote connections require HTTPS.

The service listens on `127.0.0.1:8765`. Deploy it behind an HTTPS reverse proxy or a public Tailscale Funnel route. A domain is optional when using Funnel; the Macs do not need Tailscale for a public Funnel connection. The Pi still needs Tailscale running. A private tailnet address instead requires a reachable tailnet connection.

The checked-in connection window defaults to `https://home-lab.tail4869fe.ts.net`. This is a project-specific address, not a bundled public messaging service. Use the origin configured for your deployment. Importing an older device export may restore an older origin; correct the address before connecting.

See [the server guide](server/README.md) for the API contract, media limits, Raspberry Pi/systemd deployment, Funnel routing, backups, and recovery. See [release and enrollment instructions](docs/RELEASING.md#private-message-enrollment) for creating private setup codes. Existing deployment notes record user-reported Pi health; this README does not verify a live endpoint or cross-Mac delivery.

## Animation and artwork

The active artwork source is `assets/duck/final-v1/`. Numbered-lettered folders contain ordered PNG drawings; `animation-scales.json` stores each clip's shared scale and position. Originals are copied unchanged into `Sources/PetAssets/Resources/FinalDuck/` by `tools/import-final-sprites.py` during an app build.

Playback uses **6 drawings per second**, equivalent to holding each drawing for four frames on a 24 fps timeline. It preserves the authored stepped motion without interpolation. Behavior choices happen at clip boundaries, with queued requests and safe entry/exit routes for prop routines.

| Source | Purpose |
| --- | --- |
| `Sources/PetCore/SpritePlayback.swift` | Native animation states, transitions, and playback clock |
| `Sources/PetCore/PetConstants.swift` | Runtime timing, weights, interaction, and placement tuning |
| `docs/sombrero-v1-state-graph.json` | Animation-lab graph and clip IDs used during import |
| `assets/duck/final-v1/animation-scales.json` | Authored clip registration |
| `Sources/PetAssets/SpriteLibrary.swift` | Resource validation, rendering metadata, and hit masks |

Keep the native controller, preview graph, and calibration aligned when changing behavior. Missing active clips use a visible ten-drawing pink placeholder; timeout is intentionally hidden. Older `assets/duck/v1/`, `assets/duck/v2/`, and `assets/duck/frame-by-frame/v1/` material preserves earlier artwork and experiments.

### Animation lab

Inspect animations and transitions without launching the native app, camera, or messaging:

```sh
python3 preview-app/launch.py
```

This generates a local HTML preview and opens it in your browser. For a live rescan server:

```sh
python3 preview-app/server.py --port 8766
```

Open `http://127.0.0.1:8766`. The preview server defaults to port 8765, which conflicts with the messaging server if both are running; use 8766 in that case. See [the animation-lab guide](preview-app/README.md) for solo playback, stepping, held flags, graph overrides, and asset reloads.

Standalone sprite-sheet utilities are also available as `split_spritesheet.py` and `preview_animation.py`; their image operations require Pillow, and the interactive sheet preview uses Tkinter. Run either with `--help` for options. They are separate from the final-frame native import pipeline.

## Project layout

| Path | Contents |
| --- | --- |
| `Package.swift` | Swift package with `DesktopPet`, `PetCore`, `PetAssets`, and core tests |
| `Sources/DesktopPet/` | AppKit windows, coordinator, permissions, camera, messaging client, and updater |
| `Sources/PetCore/` | Behavior/playback, placement, messaging models, and Bible selection/pagination |
| `Sources/PetAssets/` | Resource loaders, artwork, typography, and bundled assets |
| `assets/` | Artwork sources, calibration, and earlier production iterations |
| `preview-app/` | Independent browser animation lab and its tests |
| `server/` | Messaging API, storage, provisioning/enrollment, deployment templates, and tests |
| `Tests/` | Swift core tests, native smoke harnesses, and Python tooling tests |
| `scripts/` | Native build/test scripts and release entry points |
| `tools/` | Asset import/calibration and release packaging utilities |
| `macOS/` | Bundle metadata, entitlements, icon, and Sparkle configuration |
| `docs/` | Product plans, state graph, release guide, and historical handoffs |

## Local data

The app retains its original bundle identifier, `com.desktop-pet.watercolor-duck`, and legacy data paths so the sombrero rename preserves existing settings.

| Location | Data |
| --- | --- |
| `~/Library/Application Support/WatercolorDuck/preferences.json` | Display, placement, and behavior preferences |
| `~/Library/Application Support/WatercolorDuck/daily-verses.json` | Daily passage selection and read state |
| `~/Library/Application Support/WatercolorDuck/Messages/` | Connection metadata, replicated messages, outbox, and media cache |
| `~/Library/Application Support/WatercolorDuck/MessageDrafts/` | Draft text and copied draft attachments |
| `~/Library/Caches/WatercolorDuck/Camera/` | Temporary camera files |
| macOS Keychain service `com.desktop-pet.watercolor-duck.messages` | Device bearer tokens |

Server-side storage paths come from `SOMBRERO_DATA_DIR` and `SOMBRERO_MEDIA_DIR`. Back up the database, device configuration, media marker, and committed media consistently; keep private credential exports protected separately.

## Verification

Run the native checks on macOS from the repository root:

```sh
./scripts/test-macos.sh
./scripts/test-ui-macos.sh
./scripts/test-messaging-client.sh
./scripts/test-message-windows.sh
```

The core script runs the synchronous XCTest methods through a lightweight assertion harness for Command Line Tools installations without a usable XCTest runtime. The other scripts cover the native coordinator/UI, messaging transport and persistence, and Polaroid windows. UI checks need an appropriate desktop environment.

Browser and Python tooling checks:

```sh
node --test preview-app/tests/*.test.mjs
python3 -B -m unittest discover -s preview-app/tests -p 'test_*.py' -v
python3 -B -m unittest discover -s Tests -p 'test_*.py' -v
python3 -B -m unittest discover -s Tests/ReleaseTools -p 'test_*.py' -v
```

After installing the server test dependencies:

```sh
PYTHONPATH=server server/.venv/bin/python -m unittest discover -s server/tests -v
```

Server HTTP tests explicitly skip when FastAPI/httpx are missing. A skipped suite is not transport verification. Existing handoffs also record an environment-specific VideoToolbox decoder failure (`-12911`), so successful video playback, real camera capture, public routing, two-Mac delivery, and clean-Mac update continuity still need hardware acceptance checks.

## Releases and automatic updates

Release tooling supports universal builds, Sparkle-signed update archives, an appcast, a stock-macOS installer, and GitHub Releases. Developer ID signing and notarization are optional when the required credentials are configured. Sparkle signing and Apple notarization serve different purposes; an ad-hoc build remains unnotarized.

The default source/release repository is `micahlai/sombrero`. Ordinary debug builds have no Sparkle updater. For signing setup, increasing build numbers, preparing artifacts, publication, and the installer command, follow [the release guide](docs/RELEASING.md). Its example version/build numbers are historical; choose unused values greater than the published build.

Release tooling being present does not establish that a release is live. Published artifacts, the public messaging origin, and installation/update behavior must be verified separately.

## Documentation and asset notices

- [Release and enrollment guide](docs/RELEASING.md)
- [Messaging server guide](server/README.md)
- [Animation-lab guide](preview-app/README.md)
- [Sombrero v1 design plan](docs/SOMBRERO_V1_PLAN.md)
- [Project implementation notes](docs/PROJECT_PLAN.md)
- [Dated continuation handoff](docs/HANDOFF_2026-11-21.md)

Plans and handoffs include superseded scopes and historical deployment observations. Use the current source for implemented behavior, the focused guides for workflows, and dated notes for context. Earlier notes describing a five-state prototype, 12 fps animation, or messaging as future work do not describe the current app.

The bundled Bible catalog records the World English Bible text as public domain, with source metadata in `Sources/PetAssets/Resources/Bible/verses.json`. Matcha Style is used for speech-bubble typography; supplied font notices are under `Sources/PetAssets/Resources/Fonts/`. This repository currently has no top-level license file; do not assume that the code, duck artwork, or bundled font share the Bible text's public-domain status.
