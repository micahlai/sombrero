# Artist brief — individually drawn idle and pet frames

Updated November 18, 2026. **This brief supersedes the layered master / cutout rig / transformed-keyframe animation method.** Earlier notes remain only in `docs/archive/ARTIST_BRIEF_layered_superseded.md`.

## Current scope and review gate

Produce **idle and petting only**, then a video preview for the user. Do not start shoo, peeking, sitting, flight, book, or polaroid production under this brief. Shoo and peeking may proceed only after the user sees this preview and asks to continue.

The character is animated at exactly **12 fps** with a very **noodly** movement style.

## Authoritative appearance

Open the actual latest nostril-bearing sheet:

`generated_images/exec-0f994ff1-3130-4298-b10e-bbb99ffb5446.png`

Reference/version: `duck-v1-nostrils`. Neutral model: pose 01. SHA-256:

`284d1c9d54fd373d19a8b5a7c7ea680f08df5252dc08ed275eda56ef507f4ca1`

The same reference must accompany both artists' image-generation calls. Maintain the large tall domed head, broad low closed bill with its central raised point, exactly two small nostril strokes, sparse dash eyes, small oval torso, angular wings, and short thin legs.

Golden yellow head, deeper ochre body, pale warm bill, sparse dark brown lines. Uneven watercolor wash and soft irregular paint boundaries matter; paper grain and a textured backdrop do not. Older character explorations and the nostril-free sheet are superseded.

## Production method

1. Draw complete character images for every animation frame. Do not pose reusable painted body-part layers, rotate a cutout rig, warp a standing sprite into each frame, or interpolate between a few rendered key poses.
2. With the currently available tool, generate an ordered board containing **24 complete sequential drawings**, exactly **four columns × six rows**, read left to right, top to bottom. Every equal-size cell contains a whole duck, not a body part.
3. Use a transparent backdrop, generous cell margin, consistent scale and ground baseline. No labels, frame numbers, grid lines, or decorations.
4. Technical grid slicing, uniform resizing, alpha inspection, whole-frame translation for registration, packing, and video assembly are allowed. They prepare complete drawings; they must not synthesize movement through cutout transforms or tweening.
5. Start with watercolor painted directly into the drawings in the same generation pass. A reused texture overlay is optional if a simpler drawing pass proves more practical. Do not claim measured cost savings without evidence.
6. Inspect the board before treating it as animation. Still-image generation does not guarantee ordered motion, stable faces, correct frame count, or distinct drawings. Fix/regenerate failures rather than disguising them with morphing.

### Tool capability and limits

The current tool generates **still images**, including a static sheet of sequential drawings. It is **not a video-generation model** and provides no temporal-consistency guarantee. Its underlying architecture is not exposed; do not claim a particular diffusion architecture. The preview video is assembled from those still drawings. Acceptance depends on actual motion quality, not merely on having 24 PNG files.

## Cadence and acting

- Playback is exactly 12 fps: `frameRate: { "numerator": 12, "denominator": 1 }`, with positive integer `durationFrames`. Initial boards use one tick per drawing: 24 drawings = 2 seconds.
- Derive time from frame index and rational rate; do not accumulate rounded 83 ms delays. MP4 must report `12/1` fps.
- Very noodly means loose flowing arcs, soft body bends, supple wings, elastic anticipation and follow-through, and playful delayed settling. It does not mean a permanently distorted face or a different duck in each frame.
- Preserve head/bill identity and both nostrils while torso, wings, and posture flow.
- Idle: soft breathing/sway, a complete blink, light wing follow-through, compatible loop endpoints.
- Petting: start neutral, anticipate an invisible hand from upper right, lean toward it, close eyes comfortably, wiggle wings, settle, and return to neutral. No human hand in the transparent asset.

## Files and handoff

New work belongs under `assets/duck/frame-by-frame/v1/`. Older `assets/duck/v1/` layered assets remain preserved and excluded from this deliverable.

- Keep original board and source path/hash.
- Export 512 × 512 untrimmed RGBA PNGs, with consistent baseline near ground pivot `(256,448)`. Do not stretch the duck differently between frames.
- Record natural source-cell resolution; enlarging a cell adds no detail.
- Per clip: reference identity/hash, board identity/hash, `animationMethod: "individually-drawn-frames"`, canvas, pivot, exact rate, files, integer tick durations, loop/entry/exit metadata, and quality notes.
- Check duplicate hashes, alpha, clipping, and temporal drift. Different hashes alone do not prove useful motion.
- Deliver one combined idle/pet MP4 at exactly 12 fps, contact sheets, and an optional offline player. Review on light and dark backgrounds.

The user must see a real video preview before any shoo or peeking production resumes.
