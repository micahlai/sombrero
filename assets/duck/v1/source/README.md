# Duck shared source master v1.0

This is the common source for all artist agents. The root agent accepted the neutral model for pilot production; the action-family gate remains subject to root review of that pilot.

- `master.json`: actual layers, registration, group pivots, attachment anchors, source/reference hashes, and per-layer SHA-256 hashes.
- `neutral.png`: assembled neutral on the 512 × 512 output canvas.
- `neutral-closed-eyes.png`: the same duck with only its approved eye overlays swapped.
- `neutral@2x.png`: a technical enlargement of neutral for inspection, not added source detail.
- `layers/*.png`: eight native-resolution transparent cutouts authored together by image generation from the approved reference.
- `preview-white.png` / `preview-charcoal.png`: technical alpha previews; never use as runtime art.

The fixed head layer includes all watercolor, the closed bill outline, and exactly two nostril strokes. Both eye variants are separate and share the head group, so tilts move the full face together. `whenEyeState` selects the eye overlay; the closed-eye asset is not globally hidden. The head group pivot is `(256,309)`, the standing ground pivot is `(256,448)`. Wing pivots are inside the torso overlap. The shared compositor applies intended layer viewports while preserving each PNG's intrinsic aspect ratio; the manifest positions already compensate for that behavior.

Run `node tools/build-duck-master.mjs` from the project root to reproduce extraction, registration, neutral renders, and previews. It uses the shared technical compositor in `tools/asset-contract.mjs`. This is extraction/assembly of painted inputs; it does not procedurally generate new watercolor or independently redraw any frame.

Reference: `duck-v1-nostrils`, pose 01 of `generated_images/exec-0f994ff1-3130-4298-b10e-bbb99ffb5446.png`. Imagegen parts board: `generated_images/exec-3b829145-e714-4dff-bc4e-9dd4c00261fc.png`. The generated board retains invisible RGB in some alpha-zero pixels; extraction clears those hidden RGB values, preserving every nonzero alpha value. The assembled source has no visible halo on light or dark backgrounds.

All animation is authored on an exact 12 fps timeline. Noodly motion should come from restrained torso/wing bends and delayed follow-through, with the bill and head identity held fixed. Dramatic silhouette changes need separately approved source keys. Do not silently modify this master after other action families begin; coordinate changes through root and increment the master version if needed.

Limitations: the parts were carefully repainted from the reference rather than extracted pixel-for-pixel. The master currently has a neutral front head plus eye variants; it is not a complete set of directional or flight silhouettes. The watercolor is painted into each cutout, so excessive warping can stretch pigment. Use small controlled deformation in the pilot and inspect transitions over both preview backgrounds.
