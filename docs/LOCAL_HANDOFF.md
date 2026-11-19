# Desktop pet — local continuation handoff

Project directory: `/Users/micahlai/code/desktop-pet`.

The user requested a local chat. Automatic local-task setup could not be completed: the Codex project-list API returned a tool request failure, and computer control was denied access to the ChatGPT application. No claim is made that this conversation was converted. The files below already exist on the local computer and can be used by a new local task.

## Immediate next action

Show the user the completed preview at `assets/duck/frame-by-frame/v1/previews/idle-and-pet.mp4`. It is eight seconds, 96 video frames at exactly 12 fps: the 24-frame idle sequence twice, followed by the 24-frame petting sequence twice. Do not generate more art before the user reviews it.

## Latest user decisions

- Independent watercolor duck desktop pet, with no LLM, remote backend, or external integrations.
- Preserve the blackboard duck's large domed head, distinctive broad pointed-center closed bill, two nostril strokes, small oval torso, angular wings, and short thin legs.
- Exactly 12 fps and a very noodly animation style.
- The user cancelled the layered/cutout/keyframe method. Current animations are complete individually drawn frames, not a parts rig or tweened render.
- Only idle and petting are in scope now. The user must see a video preview and explicitly continue before shoo and peeking. Book, talking, flight, and polaroid remain future ideas. The polaroid is only an animation prop, with no photo integration.
- The current available generator produces still images. Each action was generated as an ordered board of 24 complete drawings, then technically sliced and registered. A video-generation/diffusion model was not used; the tool's underlying architecture is not exposed.
- Watercolor is already baked into the drawings. No separate texture pass or cost-saving claim was needed.

## Current files

- `AGENTS.md`: current instructions, updated to the user’s new method.
- `docs/PROJECT_PLAN.md`: current art workflow and local desktop backend plan.
- `docs/ARTIST_BRIEF.md`: exact production method, style, cadence, and review gate.
- `docs/character-reference.json`: immutable appearance reference and current production status.
- `generated_images/exec-0f994ff1-3130-4298-b10e-bbb99ffb5446.png`: authoritative nostril-bearing character sheet.
- `assets/duck/frame-by-frame/v1/idle/clip.json`: idle, 24 full-frame drawings, two seconds.
- `assets/duck/frame-by-frame/v1/pet/clip.json`: petting, 24 full-frame drawings, two seconds.
- `assets/duck/frame-by-frame/v1/previews/idle-and-pet.mp4`: combined video.
- `assets/duck/frame-by-frame/v1/previews/index.html`: local video player.
- `assets/duck/frame-by-frame/v1/previews/frame-validation.json` and `video-validation.json`: validation evidence.

## Verification completed

Both clip validators pass: 24 distinct raw pixel hashes each, transparent RGBA 512 × 512 frames, valid source-board hashes, exact 12/1 frame rate and integer tick duration. The MP4 was separately checked with ffprobe: 12/1 average and nominal rate, 96 frames, 8.000 seconds. Root reviewed the source boards, alpha composites, contact sheets, and encoded video sample contact sheet. Small contour/pigment variations and imperfect loop seams remain visible review considerations; the user has not approved the motion quality yet.

## Reproduction

Node.js, sharp, ffmpeg, and ffprobe are required. `tools/image-library.mjs` resolves a locally installed sharp package or the bundled application copy available on this machine. No application framework is required to play the existing MP4.

```sh
node tools/validate-frame-assets.mjs assets/duck/frame-by-frame/v1/idle/clip.json assets/duck/frame-by-frame/v1/pet/clip.json
node tools/build-frame-preview.mjs assets/duck/frame-by-frame/v1/idle/clip.json assets/duck/frame-by-frame/v1/pet/clip.json
```

The earlier `assets/duck/v1/` rig/cutout experiments and corresponding old tools/previews are preserved for history only. Do not resume them or mistake them for the current deliverable. No desktop app scaffold has been implemented yet.
