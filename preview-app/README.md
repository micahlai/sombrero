# sombrero animation lab

A separate, local test bench for the full v1 animation graph. It does not change
the native desktop pet or start any camera, messaging, notification, or remote
service.

## Run

From the repository root:

```sh
python3 preview-app/launch.py
```

Requires Python 3.10+ and a modern browser. No packages, build tooling, network
connection, or server are required. The launcher scans the current assets and
generates an ignored HTML file under `preview-app/.generated/`, then opens it in
your default browser. The web interface uses the system font. Matcha Style is
reserved for speech bubbles and is not loaded or bundled by this preview app.

**Reload assets** in this file-based mode opens a folder picker: choose
`assets/duck/final-v1`, containing the animation folders. The files stay inside
your browser; nothing is uploaded. Rerunning the launcher also rescans the frames
and graph. Keep the generated page inside this checkout, since its initial image
URLs point to the original local files.

For development, an optional live file server supports rescanning with one click:

```sh
python3 preview-app/server.py
# Open http://127.0.0.1:8765
# Or choose a different port: python3 preview-app/server.py --port 8766
```

The server binds only to localhost. If this environment blocks local sockets,
use `launch.py` instead. Stop the server with Ctrl+C.

## Animation folders

```text
assets/duck/final-v1/
  1A/
    frame_0001.png
    frame_0002.png
  1B/
  ...
```

Folder IDs are case insensitive (`1a` and `1A` both work). Use the exact ID as the
folder name. Supported individual drawing files: PNG, WebP, JPEG, and AVIF. Files
are sorted naturally (`frame_2` before `frame_10`); hidden and unsupported files
are ignored. Alpha and partial transparency are rendered directly over a
checkerboard, white, or dark preview background. Drawings keep their aspect ratio;
one scale is used across every frame of a clip. Likely next clips are loaded and
decoded ahead of time, with a three-clip cache. Transitions retain the last drawing
until the next clip is ready; loading feedback appears only after a 250 ms wait.

`assets/duck/final-v1/animation-scales.json` records the reviewed scale and position
of every animation in one shared coordinate system. **Use scale map** applies each
available clip's fixed transform; disabling it shows original source framing.
The same scene fit and scene-zoom setting apply across calibrated animations, so
the player does not independently resize them to fill its window. **Fit scene**
shows the entire shared canvas, including smoke; 1.5×/2× zoom enlarges the character
around the common ground anchor. PNG originals are never changed.

The initial calibration visually reviewed the first two and last two frames of
the initial eight available clips. Later reviews add 1D, 3C, 4B (23 frames), 4C (39 frames), and the 7A/7B/7C Bible route (17/14/11 frames),
followed by the 6A/6B camera route (14/12 frames), bringing the calibrated set to
seventeen clips. It includes
sample hashes, measurements, adjacent-state seam checks, and missing/hidden state
entries. Re-review this file after changing artwork; it is a calibration snapshot,
not an automatic character detector. A single transform preserves each clip's
internal motion but cannot remove authored proportion differences (notably 2B).
When choosing a folder through **Reload assets**, select the whole `final-v1`
folder so the JSON is loaded along with the frames.

Every missing or empty animation has **exactly 10 frames of a pink square**. A
clip with an unreadable image also falls back to these ten frames and reports the
problem. Timeout is genuinely hidden, with zero frames. Nothing is written into
the animation folders, including the existing empty `1a` folder.

## Controls

- **State machine** follows the graph. **Solo clip** loops the current/selected
  clip and suspends graph conditions, so you can inspect any unfinished animation.
- **Show photo**, **Take photo**, and **Read Bible** enqueue named requests.
  Requests remain pending through return/gateway states. There is an eight-item
  FIFO; every explicit button press is a separate test request.
- **Pet**, **Goodbye**, **Showing photo**, **Taking photo**, and **Reading** are
  held checkboxes. Events do not silently set them. Check the corresponding held
  boolean when you want an idle routine to loop.
- The `event` checkbox is read-only, true when Goodbye is checked or the request
  queue has pending events.
- **Recall duck** and **Away timer expired** are event buttons available in
  timeout. The latter simulates timer expiry; it does not schedule a real timer.
- **Pause**, frame stepping, scrubbing, **Finish clip**, drawing FPS, and speed
  are independent preview controls. Defaults come from the graph: 6 drawings/sec.
- Select a graph node to inspect its outgoing edges and normalized probabilities
  in **Details**. If the clicked node is a directly connected default
  successor of the current state **and the current state has multiple weighted
  default exits**, it also arms a **one-shot next-roll override**: that route gets
  weight 1 and the others get 0. No animation is skipped or interrupted. The gold
  outline, highlighted route, and **Next roll** label identify the choice directly
  on the diagram without resizing it or opening **Details**. Click the chosen
  node again to cancel. Authored weights are restored after the next transition; conditional
  routes still have priority, and any conditional transition clears the override.
  Other node clicks only inspect. This control is disabled in Solo clip mode.
  **Play this state** remains a separate explicit debug jump, clearing
  pending/active requests while retaining checkboxes. Red entry guards still
  apply in state-machine mode. Use Solo clip for an unconditional audition.
- **Details** toggles the inspector/log. **Find current**, **Fit all**, the zoom
  buttons, mouse-wheel zoom, and drag-to-pan help navigate the complete graph.
  Playback, graph, and inputs have separate panels on desktop; the parameter
  panel scrolls independently when necessary.
- Missing or empty animation folders have dashed graph boxes and a **Missing**
  label, not merely a colored dot. Unreadable frames also count as missing artwork.
  The intentional hidden timeout state is not marked missing.
- **Restart** resets the state, booleans, and request queue. **Clear pending
  events** retains the active routine.

Keyboard shortcuts when not editing a control: Space pauses/resumes, arrows step
a drawing, and Enter finishes the current clip. Stepping past the last drawing
takes the applicable transition. Pause, loading, and background tabs stop the
drawing clock without fast-forwarding on return.

## Graph behavior and authority

The app reads `docs/sombrero-v1-state-graph.json`, with the semantics described in
`docs/SOMBRERO_V1_PLAN.md`. All 23 states and 50 edges are shown. Graph labels show
raw default weights; hover an edge or open Details for normalized probabilities.
The raw `1a` total is 1.02 and is intentionally preserved.

- Red edges interrupt immediately and are re-evaluated **before rendering a new
  state**. Skipped gateways appear dashed in the recent-path display/log.
- Purple edges wait for the last drawing's hold to finish. Defaults are sampled
  only at clip completion, with one normalized weighted choice. Deterministic
  and conditional routes consume no randomness. Pet release/event exits are red but require the first full pet cycle to finish. Each new pet-state entry resets that protection; self-loops keep exits immediately eligible after the first cycle. `dialogue_open` clears Pet and blocks re-enabling it until dialogue closes. Held pet self-loops remain purple. Manual/timed recall uses separate top and side clearance checkboxes. With neither: 100% screen-edge 4B, without a random roll. With top only: 80% 4C / 20% screen-edge 4B. With side only: 50% screen-edge 4B / 50% window-side 4B. With both: 40% 4C / 40% screen-edge 4B / 20% window-side 4B. The inspector records the chosen variant. In the native app, window-side 4B detaches when its clip finishes; 4C stays attached until dragged or its window/clearance becomes unavailable.
- The plan's proposed tie-break is explicit here: goodbye, pending page-two
  request, pet, then default, only where the graph provides a route.
- The required `3c → 3a (skip) → 2b → 1a (skip) → 5a` path retains the photo-show
  request until it starts at `5a`. Active requests are separate from the pending
  queue, preventing repeated self-dispatch at `1a`.
- Clip generation tokens reject stale completions after an interrupt/reset/jump.
  A bounded resolver detects immediate-transition cycles.

This JavaScript test controller and the native Swift controller implement the same pet-exit and recall branches. The native app obtains window availability from focused-window geometry; this preview simulates it with a checkbox.
Away timers, viewers, camera capture, photo delivery, and reading content are
represented by buttons/flags, not real external operations.

## Validation

```sh
node --test preview-app/tests/*.test.mjs
python3 -B -m unittest discover -s preview-app/tests -p 'test_*.py' -v
```

Node 18+ is needed only for tests. Checks cover every authored edge, conditional
priority, normalized weights, FIFO routing, skipped gateways, stale completions,
timeout/recall, exact placeholder timing, clock freezing, natural file order,
case-insensitive folder names, missing/empty assets, and the file-based bundle.

## Files

- `web/engine.mjs`: pure state and event controller.
- `web/playback.mjs`: monotonic drawing clock and frame-size calculation.
- `web/alignment.mjs`: validated source-to-scene transforms and shared scene zoom.
- `web/graph.mjs`: interactive SVG graph, layout, and live highlighting.
- `web/app.mjs`, `index.html`, `styles.css`: test controls and renderer.
- `server.py`: asset inventory and optional localhost file server.
- `launch.py`: dependency-free browser launcher/bundler.

The current worktree also includes the matching native app/controller, graph data, and compact speech-bubble updates. Source artwork is copied unchanged into the native bundle.
