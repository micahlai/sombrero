# Shared artist brief — duck-v1-nostrils

Read this before creating any production character art. The project plan is [PROJECT_PLAN.md](PROJECT_PLAN.md); machine-readable reference identity is [character-reference.json](character-reference.json).

## Required reference

Open and visually inspect this actual image, not just a written description:

`generated_images/exec-0f994ff1-3130-4298-b10e-bbb99ffb5446.png`

Paths are relative to the project root. The file must match the hash in `docs/character-reference.json`. Pose 01 is the neutral model. Use the full sheet to understand expression range, sitting, and subtle three-quarter views. The sheet with nostrils supersedes both older generated images.

This is the user's duck, not an invitation to design another duck. Keep the original large domed head, distinctive broad pointed-center bill, small oval body, tiny angular wings, and short thin legs. Add exactly two short nostril strokes to any newly drawn visible bill. Talking never changes the bill into an open mouth.

## Production dependency

This brief locks the design reference now, but a reusable layered master does not yet exist. The character lead must create and validate that master and a small motion pilot first. Artists working on different action families then receive the **same actual master and source layers**, not separate generated approximations of them.

Do not independently generate a master for your own action family. If a required layer or view is absent, request/produce it through the character lead and update the shared pack once. Reference or proportion changes require a new explicit character version rather than a silent local adjustment.

## Keep fixed

| Feature | Required continuity |
| --- | --- |
| Head | Tall soft dome, subtly irregular contour; same neutral width and height across clips |
| Bill | Broad low closed outline with central raised point; same placement and proportions |
| Nostrils | Two tiny dark strokes, one each side of the center; attached to bill transform |
| Eyes | Two sparse dark dash marks; closed-eye variants can be short curves |
| Body | Small narrow vertical oval under the much larger head |
| Wings / feet | Small angular wing shapes and short thin legs; no human hands or new feather anatomy |
| Palette | Golden yellow head, deeper ochre torso, pale warm bill, dark brown marks |
| Pigment | Irregular watercolor wash; same paint scale and density as shared master |
| Background | Transparent alpha; no paper, white matte, scenery, labels, or ground shadow |

Pose 01 wins over approximate ratio descriptions. For a matching front pose, neutral landmark positions should remain within about 3% of standing character height after registration; deliberate rigid transforms and approved perspective changes are exceptions. This tolerance is a QA aid, not permission to distort the duck.

## Animation method

Use reusable painted parts for small motion and a few newly drawn silhouettes for sitting, flapping, contact with props, and larger turns. Bake the finished duck animation to registered PNG frames. This is a layered **authoring** workflow; a live runtime rig is not required.

Keep watercolor pigment attached to each source part. Do not independently re-roll paint noise in adjacent frames. Do not add a global texture/filter over the screen. Controlled paint irregularity is desired; flickering grains, sliding texture, hard cutout seams, and arbitrary contour drift are defects.

## Required cadence and noodly movement

**All character animation is authored and played at exactly 12 fps. The movement style is very noodly.** This replaces the earlier 8–12 fps range and the suggestion of mostly restrained cutout motion.

- Use a 12-frame-per-second timeline. One animation tick is exactly `1000 / 12` milliseconds. Holds last whole numbers of ticks; reuse artwork during holds instead of inventing different pigment each frame.
- Every clip declares `frameRate: { "numerator": 12, "denominator": 1 }`. Each frame entry has a positive integer `durationFrames`. Derive milliseconds from that count rather than accumulating rounded 83 ms frame intervals.
- Animate loose, flowing arcs, soft torso bends, floppy curved wing motion, elastic anticipation, gentle squash/stretch, delayed settling, and playful follow-through. Allow asymmetry and overshoot so the duck feels hand-animated and noodly rather than like rigid parts on hinges.
- Preserve the recognizable model through deformation: large domed head, distinctive closed bill, two nostril strokes, small torso, and short legs. Keep the head/face group stable; place most bend and elastic movement in the torso, wing paths, posture, and timing. No melted bill, noodly nose, or permanent proportion changes.
- Do not add anatomical joints or human limbs merely to obtain bend. The existing small angular wings can follow supple, curved paths and controlled shape changes while staying recognizable.
- Smooth screen-space flight/drag positioning may be sampled at display refresh independently; visible character drawing changes remain on the 12 fps timeline.
- The idle/pet pilot must demonstrate this motion style before the action-family artists fan out. Review it at native 12 fps, not a sped-up preview.

For ordinary tilts, rotate the head, eyes, bill outline, and nostrils together. Keep bill changes to genuine perspective/occlusion; do not redraw it to express speech. Never silently substitute a generic orange duck beak or a long doglike muzzle.

## Shared coordinate/export rules

- Work from the locked master, preferably on a 1024 px source canvas.
- Export 512 × 512 RGBA PNG frames in sRGB with standing ground pivot `(256, 448)` and approximately 360 px standing height.
- Register every frame to that shared pivot; never auto-center each drawing or normalize its occupied bounds independently.
- Name frame files `<clip-id>__000.png`, with zero-based numbering and positive integer `durationFrames` on the exact 12 fps timeline. A duration hold reuses a frame.
- Keep wings, feet, and props inside the standard canvas. An expanded frame requires documented source size and anchor offset before integration.
- Deliver raw frames untrimmed. The integrator handles atlas trimming and records offsets.
- Separate prop sources from the duck. Final contact frames may be baked together. Preserve photo-image slot and front-wing occlusion metadata for the polaroid.
- Keep debug overlays, labels, and contact-sheet previews outside the runtime frame directory.

## Action assignments

| Family | Useful approved reference poses | Required acting limits |
| --- | --- | --- |
| Wait / look | 01, 04, 11, 12 | Small blink, head tilt, and weight shift; no new body proportions |
| Sit | 07 | Head stays large; body compresses into seated silhouette; feet move intentionally |
| Pet | 05, 08 | Closed eyes, noodly lean, soft torso bend and elastic settle; preserve the face and model proportions |
| Read | 07, 08 | Book physically held by wing tips; reading eye motion, optional page turn |
| Talk | 02, 04, 10 | Wing/head acting only; bill and both nostrils unchanged; bubble is runtime UI |
| Flight / landing | 03, 06 as acting cues only | New flap keys preserve recognizable head, bill, small body, and wing identity |
| Polaroid | 02, 08 as acting cues only | Fixed illustrated photo prop; believable gripping/holding; no external integration |
| Shoo | 02, 10 | Small outward dismissive wing flick; no human fingers |
| Peek | 04, 11, 12 | Curious tilt and partial entry; screen clipping handled by application |

Reference poses guide acting; they are not sequential frames to play as an animation. Prop/flight artists must follow the common rig and palette rather than reinterpret the character from those cues.

## Prompt template for a future artist agent

> Task: author only `[ACTION FAMILY]` for the existing duck desktop companion.
> Read `docs/ARTIST_BRIEF.md` and the action specification in `docs/PROJECT_PLAN.md`.
> Inspect the actual latest reference image at `[RESOLVED REFERENCE PATH]` and the locked master at `[RESOLVED MASTER PATH]`; use the shared layer pack `[RESOLVED LAYERS PATH]`.
> Character reference/version: `duck-v1-nostrils`, hash from `docs/character-reference.json`.
> Preserve the domed head, original broad pointed-center closed bill, exactly two nostril lines, small oval torso, angular wings, short thin legs, palette, linework, and master paint registration.
> Produce `[NAMED CLIPS]` with the shared registration and the agreed entrance/exit pose `[POSE ID]`.
> Animate through reusable painted parts; redraw only required silhouettes/contact. Bill never articulates for talking.
> Author exactly 12 fps with integer `durationFrames` holds. Acting must be very noodly: loose arcs, soft body bends, floppy wing motion, elastic anticipation and playful follow-through, with a stable bill/head identity.
> Submit key poses for internal continuity review before producing in-betweens, then source layers, transparent untrimmed frames, timing/attachment metadata, and a preview.
> Use no LLM integration, photo integration, new character design, background texture, labels inside runtime frames, or independent per-frame pigment generation.

The bracketed paths must be resolved to real files before assigning a task. Do not pass imaginary master/layer paths while those assets are still pending.

## Handoff checklist

1. Source reference ID/hash and master version recorded.
2. Same registered neutral entrance/exit as other families, or explicit compatible transition.
3. Exactly two nostrils on each unobscured bill; correct eye and bill placement.
4. No mouth movement in talking clips.
5. Pigment and contours stable between adjacent frames and loop endpoints.
6. All frames share the expected canvas, scale, baseline, color space, and soft alpha.
7. Wings touch props; bill/face remain readable; no cutout seams or clipped extremities.
8. Exact 12 fps, integer frame-duration holds, loop mode, interruption markers, prop sockets, and bubble attachment recorded. Noodly acting is evident at normal playback speed.
9. Preview inspected over white, charcoal, and a normal desktop background at intended small display size.
10. Layered source, raw PNG frames, metadata, and separate contact-sheet/motion preview included.

The integrator checks the combined sequence. An individually attractive clip is not acceptable if the duck changes size, bill shape, paint pattern, or palette when switching to another family's clip.
