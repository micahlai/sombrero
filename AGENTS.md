# desktop-pet project instructions

## Scope

Build an independent watercolor duck desktop companion. This project has no LLM, conversational AI, remote backend, or external integration. Talking is a gesture plus locally scripted bubble text, with no mouth movement. The polaroid is an animation prop; photo services/import/capture are outside current scope.

## Required reading

- `docs/PROJECT_PLAN.md`: animation pipeline, action inventory, desktop architecture, behavior, and implementation order.
- `docs/ARTIST_BRIEF.md`: required before creating or changing character artwork.
- `docs/character-reference.json`: authoritative image identity, hash, and design invariants.

## Art continuity

The latest nostril-bearing twelve-pose sheet at `generated_images/exec-0f994ff1-3130-4298-b10e-bbb99ffb5446.png` is the visual authority. Open the actual image. Pose 01 defines the neutral model. Older generated images are superseded.

Preserve the large domed head, distinctive broad closed bill with central raised point, exactly two nostril strokes, small oval torso, angular wings, and short thin legs. Do not redesign this as a generic duck or another creature. Preserve uneven watercolor pigment without introducing paper texture.

The user has cancelled the layered/cutout/keyframe animation method. Draw complete individual animation frames using the shared character reference; do not animate a parts rig, warp a standing sprite into motion, or synthesize tweened frames. Technical full-frame slicing, registration, packing, and video assembly are allowed. See the current artist brief; archived layered-method instructions are superseded.

Current imported character animation uses a 24 fps timeline with each drawing held for four frames: exactly 6 drawings/second. This supersedes the previous 12 fps preview contract. Movement must be very noodly: loose arcs, soft torso bends, floppy wings, elastic anticipation and follow-through. Keep the head/bill/nostrils stable and the overall model recognizable. Smooth desktop root travel is independent of the 6 fps character drawing cadence.

## Application boundaries

Keep behavior logic independent of the desktop shell. The renderer owns animation playback; the local host owns native windows, display placement, preferences, and action coordination. There is no network service required. Follow the current plan's typed IPC and interruption rules.

Only the renderer's empty areas should pass through mouse input; the duck and active UI must remain interactive. Treat flight/peek as coordinated local animation and clipping. Always retain a menu/tray recovery path.

## Current stage

Continue the native macOS Swift/AppKit app and five-state random sprite controller described in docs/BACKEND_HANDOFF.md. The first source table there, including state 5 sitting idle, is authoritative. Existing user artwork is under assets/duck/v2/; pause further generation. Technical slicing, white-backdrop extraction, registration, and runtime resource packing are authorized. Preserve originals and earlier assets. No new shoo, peeking, or other art is authorized.

Start at 1. After 1/2/4: choose 1/2/3 with probabilities 40/40/20. After 3: always 5 without RNG. After 5: loop 5 at 80%, or stand up via 4 at 20%. Decisions occur only at clip completion. Native shell and renderer remain separate from the pure controller.
