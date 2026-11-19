# Watercolor duck desktop pet — current implementation plan

Updated November 18, 2026. Current scope follows BACKEND_HANDOFF.md and the user's five-state correction. The earlier 12 fps preview/Electron proposal is preserved in docs/archive/PROJECT_PLAN_12fps_preview_superseded.md.

## Scope and architecture

Build a macOS-only local Swift/AppKit desktop companion. No LLM, account, network service, or external integration. Pause artwork generation; import the user's existing sheets under assets/duck/v2/.

PetCore owns typed state selection, timing, preferences models, and screen placement without AppKit. PetAssets loads validated packaged RGBA frames and precomputes hit masks. DesktopPet owns the transparent non-activating NSPanel, renderer, menu-bar status item, drag capture, screen recovery, preferences, and lifecycle. Calls between these components are typed Swift APIs in the same process; Electron IPC/preload requirements are superseded.

## Verified source inventory and timing

| State | Source | Drawings by row | Count | Duration |
| --- | --- | --- | --- | --- |
| 1 | 1-look.png | 6 / 6 / 6 / 5 | 23 | ≈3.833 s |
| 2 | 2-look.png | 5 / 6 / 7 / 7 | 25 | ≈4.167 s |
| 3 | 3-sitdown.png | 5 / 5 / 5 / 5 | 20 | ≈3.333 s |
| 4 | 4-standup.png | 5 / 5 / 5 / 5 | 20 | ≈3.333 s |
| 5 | 5-sitting.png | 5 / 5 / 5 / 5 | 20 | ≈3.333 s |

Every original is 4800 × 3584 RGB, without alpha. Read left to right, then top to bottom. Do not use a six-column uniform grid for all files. The importer detects occupied column spans within four 896-pixel rows and validates the inspected per-row counts; sheet 1's final blank is excluded.

Use timelineFPS 24, drawingFPS 6, holdFrames 4. Each drawing lasts exactly 1/6 second. No interpolation. Elapsed monotonic time determines the drawing, independently of mouse polling or window dragging. Pause/hide/sleep rebase the wall clock and preserve clip progress; relaunch starts at state 1.

## Controller

| Completed state | Next state | Probability |
| --- | --- | --- |
| 1, 2, 4 | 1 | 40% |
| 1, 2, 4 | 2 | 40% |
| 1, 2, 4 | 3 | 20% |
| 3 | 5 | 100%, no random sample |
| 5 | 5 | 80% |
| 5 | 4 | 20% |

Random sampling is injectable. Every clip plays once and signals completion, including repeats. Automatic choices never interrupt a clip. Dragging does not restart the animation. Hide/quit remain immediately responsive.

## Resources and art continuity

The authoritative model remains generated_images/exec-0f994ff1-3130-4298-b10e-bbb99ffb5446.png, pose 01; identity/hash/invariants remain in character-reference.json. Preserve complete authored drawings; no parts rigs, tweening, or shape morphing.

Run node tools/import-v2-sprites.mjs for deterministic full-frame slicing, perimeter-connected white-background removal, uniform one-third scaling, and whole-frame registration onto 320 × 320 RGBA canvases with shared anchor (160,288). Keep authored ground lines. The generated manifest records source SHA-256, row counts, frame rectangles, scale/offsets, and integer holds. Runtime output lives under Sources/PetAssets/Resources/Duck/.

108 decoded RGBA frames require approximately 42.2 MiB of pixel data, excluding AppKit/image caches and masks. This is not a full-app memory measurement. The sheet artwork contains visible head/pose/scale drift, including clip seams; technical registration cannot guarantee smooth source motion. No new drawings have been synthesized.

Missing/corrupt manifests, bundles, or frames yield an interactive visible square with the menu recovery path.

## Native window behavior

Use a transparent, borderless, non-key/non-main NSPanel with nonactivatingPanel, hidesOnDeactivate false, and a persistent menu-bar status item near Control Center. It is not a custom Control Center module. Always-on-top uses statusBar level; all-Spaces and fullscreen auxiliary are configurable platform policies, not guarantees over protected UI.

Only the current duck alpha mask, padded for thin strokes, captures input. Empty pixels pass through; drag retains pointer capture until release. Menus provide show/hide, restore to pointer screen, always-on-top, all desktops, click-through, pause, size, and quit. Recovery clears click-through. There is no petting asset in this imported batch, so do not show a misleading Pet command.

Restore placement by display ID and normalized visible work area; clamp on release and screen changes, supporting negative display origins. Stop drawing while hidden or suspended. Persist schema-versioned preferences atomically after meaningful changes, never per frame. No halfway routine is persisted.

## Build and validation

- scripts/build-macos.sh builds and ad-hoc-signs build/WatercolorDuck.app with its resource bundle.
- scripts/test-macos.sh runs the existing synchronous test methods with lightweight assertions under Command Line Tools, whose installation lacks XCTest. Standard swift test remains supported with a compatible full Xcode toolchain; the installed Xcode and CLT XCTest modules are incompatible.
- Test probabilities/boundaries, required no-RNG transition, clip durations/completions/repeats, pause/hide/sleep clock rebasing, packaged frame counts/masks, missing/corrupt resource fallback, preferences, and negative-origin/disconnected-display geometry.
- Manual tests remain necessary for topmost focus, transparent mouse pass-through, drag/recover, hide/show, Spaces, fullscreen, Stage Manager, screen unplugging, sleep/wake, and relaunch.

Future updates, pairing, geographic proximity, messages, and BeReal events remain unimplemented. Retain their boundaries in BACKEND_HANDOFF.md; do not activate services or request permissions for them.
