# sombrero — first release plan

Updated November 21, 2026 (America/New_York). The native app runs the local animation graph at 6 fps and bundles all twenty-one calibrated clips, including the complete 5a/5b/5c photo and 6a/6b/6c camera routes. Hover petting, speech menus, goodbye/recall, and the offline daily Bible reader are implemented. Photo/messaging uses the supplied watercolor Polaroid artwork, native composition and independent resizable Keep/Close windows, rich text, explicit camera capture, image/video attachments, Keychain credentials, per-device persistent drafts/outbox/cache, polling sync, and read receipts. The user completed Pi installation, reported the HTTP/storage test command returned OK and healthy media storage, and enabled a public Tailscale Funnel at `https://home-lab.tail4869fe.ts.net`; remote client acceptance is pending. Local test tooling cannot reach that hostname or verify actual camera capture/video decoding.

## Authority and release scope

The duck's name is **sombrero** and the product name is **sombrero**. The built bundle is `build/sombrero.app`, with a `sombrero` executable. The legacy bundle identifier and application-support preferences path are retained to preserve existing settings and app identity. Keep the native macOS Swift/AppKit app. This release adds the user's full animation graph, hover petting, a drawn speech-bubble menu, timed/manual dismissal, two-laptop photo and rich-text messaging, camera capture, and daily Bible reading. There is no LLM.

The source is the latest two-page hand-drawn PDF, visually inspected as rendered images rather than inferred from OCR. A copy is at `docs/reference/sombrero-v1-state-diagram.pdf`, SHA-256 `24b6cef91b52f27557fa3b4d4d415cd031f5cbea8a9526c848b27911464dc2ab`. The earlier five-state random controller and its 40/40/20 and 80/20 weights describe only the prototype and are superseded for the release.

Related data: `docs/sombrero-v1-state-graph.json` transcribes the colored arrows, and `docs/sombrero-v1-verse-catalog.json` lists 100 starter references and topics. `tools/import-final-sprites.py` copies final source frames unchanged into the native resource bundle, including `animation-scales.json` transforms in its manifest. The Mac build runs this import automatically. Old numeric prototype assets remain in the repository and are excluded from the app bundle.

Current cadence remains 6 drawings/second: a 24 fps timeline with each drawing held for four frames. Each animation has its own complete sprite sheet identified by a string ID such as `3c`. Timeout has no sprite or active duck window. Final sheet manifests will record actual frame order/count, alpha, registration, and holds; do not assume uniform grids or interpolate missing drawings.

## Speech typography

Use **Matcha Style** only for speech-bubble text and its drawn menu controls, via `AppTypography` from PetAssets (9 pt compact menu/body text, adjusted for readability). Native macOS right-click menus, menu-bar controls, and their submenus use the standard system font. Other app UI keeps native typography unless explicitly requested otherwise.

The supplied `Downloads/matcha_style/Matcha Style.otf` is imported unchanged as `Sources/PetAssets/Resources/Fonts/MatchaStyle.otf`. Bundle the OTF once rather than registering both OTF and TTF versions of the same face. Keep the supplied `More Info.txt` and `Read Me.pdf` alongside it as `More-Info.txt` and `Read-Me.pdf`. The supplied notice permits personal and commercial use.

CoreText registers the font for this app process when speech text first requests it; no system font installation is required. Speech labels and buttons set the font explicitly. Do not set a global application font or override native menu fonts. Unsupported glyphs and missing/corrupt font resources fall back to system typography.

The local implementation status is summarized above. The sections below describe the intended behavior; real hardware and public deployment acceptance remain pending.

## State inventory and black arrows

Black arrows run only at clip completion when no permitted red/purple condition wins. Roll once per completed clip, including repeats. Single-arrow paths are deterministic. Preserve the handwritten values as relative weights, then normalize each state's eligible black edges.

| State | Animation | Default successor(s), raw weight |
| --- | --- | --- |
| 1a | Standing idle | 1a .975; 1b .02; 1c .02; 2a .005 |
| 1b | Standing look | 1a .8; 1c .2 |
| 1c | Standing wave | 1a 1 |
| 1d | Standing pet | Red release/event exits after first full cycle; purple self-loop |
| 2a | Sit down | 3a 1 |
| 2b | Stand up | 1a 1 |
| 3a | Sitting idle | 3a .985; 3b .01; 2b .005 |
| 3b | Sitting look | 3b .1; 3a .9 |
| 3c | Sitting pet | Red release/event exits after first full cycle; purple self-loop |
| 4a | Goodbye standing | timeout 1 |
| 4b | Peek in | 1b 1 |
| 4c | Window peek in | 3a 1 |
| timeout | Hidden/static | No automatic animation; recall/away timer uses the top/side clearance weights below |
| 5a | Grab photo | 5b 1 |
| 5b | Showing photo idle | Conditional purple arrows only |
| 5c | Put photo away | 1a 1 |
| 6a | Grab camera | 6b 1 |
| 6b | Camera idle | Conditional purple arrows only |
| 6c | Take photo and deliver | 1a 1 |
| 7a | Pull out Bible | 7b 1 |
| 7b | Bible idle | Conditional purple arrows only |
| 7c | Stow Bible | 1a 1 |

There are 21 animation states plus one hidden timeout state. The supplied November 21 photo artwork supersedes the original PDF four-state photo numbering: 5a pulls out the picture, 5b holds it, and 5c puts it away. Native playback and the web preview use that three-clip route with the existing purple loop/exit timing. The black weights from 1a total 1.02. Under the user's relative-weight instruction, the resulting probabilities are approximately 95.588% idle, 1.961% look, 1.961% wave, and 0.490% sit down. Keep this discrepancy visible; do not silently change a handwritten weight to make the numbers sum to one.

## Red and purple arrows

Red means interrupt the current animation immediately, including before the first drawing when entering a state. Purple means retain the current clip until its final drawing hold completes, then take the arrow. Guard evaluation must also happen on state entry so gateways can be traversed without drawing them. Use a bounded transition resolver with cycle detection rather than scheduling a zero-duration rendering loop. Pet states 1d and 3c have one exception: each newly entered pet session must finish its first full clip before a normal release/event exit becomes eligible. The derived `petCycleCompleted` flag stays true across self-loops, so leaving during any later loop interrupts immediately; it resets when leaving/re-entering the pet state. Stale clip callbacks cannot unlock a new session.

| Current state(s) | Condition | Color / behavior | Destination |
| --- | --- | --- | --- |
| 1a, 1b, 1c | pet | Red, immediate | 1d |
| 1a, 1b | goodbye | Red, immediate | 4a |
| 1b | event | Purple, finish clip | 1a |
| 1d | pet and not event | Purple, repeat at end | 1d |
| 1d | event and petCycleCompleted | Red, immediate | 1a |
| 1d | not pet and petCycleCompleted | Red, immediate | 1c |
| 3a, 3b | pet | Red, immediate | 3c |
| 3a, 3b | event | Red, immediate | 2b |
| 3c | pet and not event | Purple, repeat at end | 3c |
| 3c | (not pet or event) and petCycleCompleted | Red, immediate | 3a |
| 1a | photo-show request | Red, immediate | 5a |
| 1a | photo-take request | Red, immediate | 6a |
| 1a | Bible-read request | Red, immediate | 7a |
| 5b | showPhoto / not showPhoto | Purple, loop / exit at end | 5b / 5c |
| 6b | takingPhoto / sent / canceled | Purple, loop / exit at end | 6b / 6c / reversed 6a → 1a |
| 7b | reading / not reading | Purple, loop / exit at end | 7b / 7c |

No event-interrupt arrow is invented for 1c, 2a, 2b, entry/exit clips, or active page-two routines. Their ordinary completion paths eventually reach a gateway. Hover over photo/Bible routines does not interrupt them unless an arrow is supplied.

When guards conflict, proposed deterministic priority is explicit dismissal where supported, then the pending page-two request, then petting, then black flow. In particular, event wins over pet in 3a/3b and over pet-release in 1d. This tie-break is an implementation proposal, not an extra line in the drawing.

## Named events and skipped gateways

`pet`, `showPhoto`, `takingPhoto`, and `reading` are held booleans. A page-two menu action is a durable named request: `photoShow(messageID)`, `photoTake(draftID)`, or `bibleRead(verseID)`. Derive `event=true` from the pending request; do not erase the request at an intermediate return state. Distinguish `activeRequest` from `pendingRequest`, so an active routine does not keep retriggering itself when it returns to 1a.

The user's required example is an acceptance test:

| Step | Expected behavior |
| --- | --- |
| Photo-show selected during 3c | Retain photoShow request and set event true; finish the first pet cycle if still pending, otherwise interrupt 3c immediately |
| Enter 3a | Its red event edge is already true; skip rendering 3a and start 2b |
| Finish 2b | Reach 1a |
| Enter 1a | Dispatch the retained photoShow request immediately; skip rendering 1a and start 5a |
| Enter 5a | Atomically move request from pending to active and clear aggregate pending event |
| Continue | 5a → 5b; showPhoto true holds 5b until Keep or Close, then 5c → 1a |

For event entry from 1b, finish 1b first; from 3b, the red event edge interrupts immediately. From 2a, finish 2a, reach 3a, then take its red event edge through 2b. A later explicit menu request may queue while a page-two routine is active; do not tear props out mid-routine. Proposed policy: one active routine plus a small FIFO of explicit requests; deduplicate repeated clicks for the same message/draft. Incoming notifications never become unsolicited animation requests.

Each clip play/cancel has a generation token. Ignore stale frame completion, camera, network, or window-close callbacks. Hidden, canceled, or replaced routines must never resurrect a window. No RNG is consumed for conditional edges or skipped gateway states.

## Window lifecycle and control panel

Keep four independent concerns: foreground animation state, native visibility, bubble/viewer/composer windows, and notification availability. Timeout means the duck panel is ordered out and its animation clock stops; empty mouse capture is disabled. A Dock minimization animation is not required for this accessory app. Keep the menu-bar control panel running for recall, quit, and recovery.

On each new application launch, verify every permission required by implemented features before constructing the pet coordinator or starting animation. Request all missing grants, recheck actual authorization after the requests, and keep startup pending until all are granted; retain Settings/retry/quit recovery. Actual still-photo capture requires Camera authorization, registered in the startup gate. Mouse-only monitoring, geometry-only window inventory, app-owned storage, and offline Bible reading require no additional macOS privacy grants. Authorization never activates a camera; there is no microphone access, including for file-based video attachments. After the gate passes, reset to timeout and use the same weighted 4b/4c entry as recall. A saved Pause Motion setting takes effect after the entrance finishes. Explicit message/Bible actions can still animate their entry and exit while idle motion is paused; their held poses stay still. A new application launch explicitly shows the duck and clears an old away deadline.

The user clarified two away modes:

| Selection | Hidden behavior | Return |
| --- | --- | --- |
| Until I say so | No automatic return, including after incoming messages or a verse becoming ready | Explicit control-panel recall → weighted 4b / 4c |
| For N minutes | Persist an absolute return deadline | Deadline → weighted 4b / 4c; manual recall may return earlier |

4b continues to 1b (standing look); 4c continues to 3a (sitting idle). Both clips now use their supplied artwork: 23 frames for 4b and 39 for 4c. Each recall evaluates top and side clearance separately:

| Top clearance | Side clearance | 4c window top | 4b screen edge | 4b window side |
| --- | --- | --- | --- | --- |
| False | False | 0 | 1 | 0 |
| True | False | 0.8 | 0.2 | 0 |
| False | True | 0 | 0.5 | 0.5 |
| True | True | 0.4 | 0.4 | 0.2 |

The native app reads WindowServer geometry for visible external windows, without Accessibility permission or window titles. These geometry checks do not require screen capture. It checks foreground document-window occlusion and the duck's painted footprint. Non-document floating overlays are excluded from obstruction checks because transparent overlays can report full-screen bounds with alpha 1. Top clearance requires at least 160 points above a candidate window and enough room for the normal animation bounds; side clearance requires room beside a visible window edge for the standing footprint and offset. The preview has separate `window_available` (top) and `window_side_available` checkboxes and reports the selected entry variant.

Screen-edge 4b chooses left/right with equal probability and samples the vertical position uniformly over the usable physical screen height. The calibrated vertical cut in 4b (205 source pixels from the left) is aligned to the physical screen edge, with a configurable inset defaulting to zero. This accounts for transparent source padding at every duck size. Right screen entry mirrors 4b; window-side entry mirrors the left window edge so the duck emerges outward. Window-side 4b aligns the same cut to its window border, follows that window while 4b plays, and detaches at completion. 4c aligns its authored ledge (source row 354) to the window top with zero gap, using the clip calibration and current pet size. Following clips align their shared ground to the same edge. 4c establishes a persistent attachment to one eligible visible window, follows its movement/resizing across subsequent animations, and detaches when the user drags the duck. Losing the window or sufficient clearance also detaches; geometry updates never select a replacement. A new 4c entry can establish another attachment. Native preview controls can force 4c or window-side 4b for testing.

`Sources/PetCore/PetConstants.swift` centralizes runtime settings, including entry offsets, required clearance, polling interval, sizes, timing, interaction thresholds, and bubble geometry/colors. Per-animation transforms remain in `animation-scales.json`. Free placement clamps painted bounds rather than transparent canvas padding, allowing the duck to reach physical screen corners and edges. Existing stored placement migrates on save.

For 4b screen-edge and window-side entries, macOS 14+ additionally takes one narrow screenshot of the possible landing strip using ScreenCaptureKit, excluding sombrero's own windows and the cursor. It detects strong horizontal color edges spanning at least 75% of that strip, merges nearby strokes, and randomly selects among edges whose resulting standing footprint fits the allowed height intervals. The duck's shared ground aligns to the selected edge; its calibrated horizontal cut remains unchanged. Window-side selection respects foreground occlusion and updates the temporary attachment's vertical fraction. A screenshot becomes invalid if its window moved before completion.

Screen Recording is optional and requested separately on the first real 4b entry; denial never blocks startup. Preferences offers Allow Screen Edge Detection when access is missing. The crop stays in memory and is never saved or uploaded. Missing permission, macOS 13, capture failure, a 650 ms timeout, or no qualifying edge preserves the existing random placement. Hold the first drawing hidden until selection/fallback, then ignore late callbacks so the visible duck never jumps. Dragging, sleep, display changes, shutdown, or a newer entry invalidates pending placement. This is native placement behavior; the browser state preview does not capture the desktop.

Start the away duration when 4a completes and timeout is entered. Validate positive finite minutes. A sleeping/offline app returns at the next opportunity after an expired deadline; do not replay missed time. Persist hidden mode/deadline across sleep/wake, and preserve unread notifications while away; a new application launch follows the entrance policy above. Clear transient pet/goodbye state on entering timeout. Timed wake never overrides a later manual-until-recall choice.

The diagram places goodbye on 1a/1b only. Proposed menu recovery from sitting or an active routine: enqueue a pending goodbye, suppress new petting, use the existing return-to-standing path, and start 4a at the next supported gateway. Sitting recovery can reuse event-style routing to 2b, but this is a proposed extension because goodbye is not a page-two event. The native control panel must retain an immediate hide/quit path even if an asset or routine fails.

## Hover, bubble menu, and notification badge

Interpret “icon” as the on-screen duck sprite. Hovering its padded alpha hit area sets pet true; leaving sets false. Re-evaluate when the animation moves beneath a stationary pointer. Opening dialogue immediately sets pet false. Speech-bubble growth, open content, and collapse all suppress hover petting; native menu tracking does too. Closing dialogue leaves pet false until a fresh hover sample resumes petting. A pet animation already in its first cycle completes that cycle, then exits; a later loop exits immediately. The preview simulates this with `dialogue_open`, which clears and disables the Pet checkbox while enabled. Do not toggle on every sparse watercolor hole. Hovering a macOS menu-bar item should not trigger petting unless separately requested.

A primary click after the existing drag threshold opens a compact drawn speech bubble, approximately 118 points wide, with height measured from the project font so every menu label fits. A fixed envelope covering all conversation animations anchors it with an 8-point gap; individual states/frames never move it. Dragging, resizing the pet, or moving its attached window carries the bubble with it. Prefer above, then either side, then below if near the screen edge. The menu has no product-name heading; labels and buttons use fixed dark-brown ink in light and dark appearance. Use accessible native controls inside the bubble; the original duck panel stays non-key, while text-editing windows may become key only after explicit interaction. Retain drag and context-menu recovery. Bubble geometry counts as interactive; empty pixels outside the duck/bubble pass through.

| Menu item | Availability | Effect |
| --- | --- | --- |
| Go away | Always visible | Show second prompt: until recalled, or for 15 minutes, 1 hour, or 4 hours |
| Show message | Always enabled; only the Show message label and a green watercolor mark for unread messages | Open the inbox (or connection setup when unconfigured), then photoShow for received content |
| Send message/photo | Always visible | Open the camera/message composition workflow; photoTake is its animation event |
| Read Bible verse | Enabled when a daily verse is ready (including rereading) | Enqueue bibleRead for that day's stored verse |

“Take message/photo” and “send message/photo” are treated as the same compose command. Availability remains distinct from busy state: a repeat click focuses the current composer rather than starting another capture session.

Compute the badge from `unreadIncomingCount > 0` only. An unread daily verse never raises the exclamation mark. Use the five verbatim 512 × 512 green watercolor PNGs from `assets/exclaimation`, bundled under `PetAssets/Resources/Notifications`. Loop them at 6 drawings/sec in a separate 32-point overlay centered directly above the duck, with a 4-point gap and no screen-edge clamping (clipping is allowed); duck clip changes do not reset the marker, and Pause Motion/sleep stop its clock. Do not draw a red circle. Every sprite sheet need not include an exclamation mark. A badge's own interactive area follows the same mouse policy. If the duck is hidden, retain badge data for recall and expose counts in the control panel without showing the duck.

## Receiving and reading a message

Control panel → Debug → Receive Test Photo creates an in-memory incoming card using the bundled duck photo artwork and a styled test message. It raises the unread badge and adds the new-message signifier to Show message even without a connection. Showing the loaded card clears its test unread state; Keep/Close use the normal animation and window flow. This is a UI preview, not an end-to-end server test: no fixture messages or read receipts enter the server replica or network.

A server notification refreshes the inbox and badge only. The user chooses Show message. The workflow routes to 5a, opens a separate Polaroid window in coordination with 5b, and holds 5b until the user chooses Keep or Close. The supplied `assets/polaroid-frame.png` is bundled unchanged and frames both composition and viewing. Photo controls/navigation sit along its top edge; rich text sits directly on the lower paper lip, with a small date/footer. All app-drawn lettering uses Matcha Style and brown ink. Both windows are key-capable, draggable and resizable, with aspect-preserving layout and a bottom-corner resize grip. Keep detaches the selected card into an independent always-on-top native window and releases the duck's routine; received cards resize down to 120 points wide with proportional text/control scaling and a usable resize grip; Close dismisses it. Multiple kept cards can remain on screen while composing, viewing another photo, reading the Bible or hiding the duck. Kept cards remain for the current app session and close on disconnect/profile change or app shutdown; they are not restored automatically after quitting. Closing an old kept card never cancels a newer viewer's animation. Only loaded media can be kept, and read receipts still require successful visible presentation.

showPhoto is true while the active viewer is open and false when the user chooses Keep or Close. After false, finish 5b, play 5c, then return to 1a. Closing before 5b records false; entry animations finish normally and the exit occurs at the next eligible boundary. The optional `senderName` field comes from the server-configured device label and is displayed in the Polaroid footer. Clients cannot supply it in sends. Missing names on legacy messages use a generic fallback. The Pi needs the updated server code before live messages carry names. A message is marked read only after its content is successfully loaded and shown, never merely because its notification arrived or a request was queued. Read updates are idempotent and retried offline. Multiple unread messages keep the badge present until consumed.

## Composing, camera capture, and sending

The Polaroid composer defaults to the live camera when the user opens a new or text-only draft; a saved photo/video draft reopens for review. Start preview only after 6a reaches 6b and the composer is visible. Offer the built-in camera and discovered supported external/Continuity cameras. The top paper edge contains camera/stop/retake, attachment/removal, camera choice and shutter controls. Keep only B/I/U and Send beside the bottom date; the message editor has no separate box or panel. Matcha Style's single font face uses synthetic stroke/slant for bold/italic, preserving all three wire-format styles without switching to system fonts. Use AVFoundation capture and native text controls. Per the user’s startup policy, request Camera authorization before the launch entrance. Opening the composer can start preview; only an explicit shutter click captures a photo, and only Send queues delivery. Do not request microphone access; videos are file attachments, not recordings. Apple documents Continuity Camera support through its capture-device discovery APIs; actual device availability depends on system setup [S1].

Keep takingPhoto true throughout capture, draft review, and queued/offline sending. Start 6a → 6b and preview after 6b is reached. Capturing retains the image/draft and freezes preview without ending 6b. Only server acknowledgment of the active composer’s specific message clears takingPhoto; the current 6b clip then finishes before 6c starts. Frame zero of 6c is the authored flash/delivery gesture, so it follows actual exposure and acknowledged sending.

After explicit Send, the composer prevents a second submission while the durable outbox retries as needed. It closes immediately when the server acknowledges that specific message, rather than waiting for recipient delivery/read or merely closing on local enqueue. An offline send remains queued and visible until acknowledged or manually closed; a delayed acknowledgment cannot close a newer draft.

Capture success and message send success are distinct. The user reviews/edits and explicitly chooses Send. Neither capturing nor local enqueue starts 6c. A failed/offline send holds 6b until acknowledged. Closing/canceling, including manually closing a queued send, finishes the current 6b loop, plays the existing 6a drawings backwards at the normal cadence, then returns to 1a. This stows the camera without playing 6c or implying delivery. A new composer requested during reversed 6a waits for stowing to finish, then begins a fresh forward 6a. A late acknowledgment for a manually closed composer cannot close a later draft or start its 6c. Retaking keeps the camera-holding route active. Stale camera operations cannot reopen after close or sleep.

Represent rich text as versioned JSON runs, e.g. `{text, bold, italic, underline}` plus line breaks. The server validates allowed keys, total length, and style values. Both apps reconstruct native attributed text from this schema. No raw executable HTML, arbitrary native object archives, or remote embedded resources are needed. Initial proposed bounds: one image up to 10 MiB, 20,000 text characters, and up to 1,000 runs; make these configuration values.

## Two-laptop service and Raspberry Pi migration

Implement the test server in Python from the start, using FastAPI with one Uvicorn worker, SQLite for metadata, and an on-disk media directory. FastAPI documents WebSocket endpoints and streamed/spooled upload handling [S2, S3]. This is a design choice sized for two clients, not a measured Raspberry Pi performance claim. Test on the actual Pi 3 before selecting dependencies and deployment limits.

The Swift app calls a narrow MessageService interface over URLSession. Start with an in-memory fixture implementation for offline tests and a localhost Python implementation for integration tests. Run two client profiles with different device IDs/cache roots against the same localhost service to simulate the two laptops. Later use one configured home-server URL; preserve the API, database schema, and media IDs during migration.

| Component | Responsibility |
| --- | --- |
| PetCore | Typed animation graph, conditional routing, request queue, priorities, clock, away state, daily-verse selection |
| PetAssets | Validated per-state sheets/manifests and full-frame playback resources |
| Desktop host | Duck/bubble/control windows, placement, alpha input, lifecycle, badge, coordination |
| MessageService client | Pair identity, inbox sync, attachment transfer, outbox, retry and read receipts |
| CameraService | Permissions, discovery, preview, capture callbacks, device-loss handling |
| Python service | Exactly two registered devices in one pair, authorized messages/media, durable cursor sync |
| SQLite and media store | Server-owned metadata plus immutable attachment objects; no direct app drive access |

Use two provisioned device credentials, one pairing record, and explicit peer IDs. Reject a third device. Store client credentials in Keychain and server token hashes outside source control. Binding to localhost is the test default. Both Macs must work away from home over an ordinary internet connection, without joining the home network or connecting to Tailscale/a VPN. A Pi deployment therefore needs an authenticated public HTTPS endpoint, with a reverse proxy in front of the local Python service. Public routing depends on the home ISP/router: verify inbound reachability before choosing direct port forwarding; if unavailable, choose a suitable public relay or alternative transport. A free dynamic-DNS hostname can avoid purchasing a domain for a directly reachable Pi. Do not assume an always-on home Pi is reachable from outside the home network, and do not configure public forwarding as part of planning.

Proposed versioned endpoints:

| Endpoint | Behavior |
| --- | --- |
| GET /v1/health | Service readiness; indicate unavailable media volume |
| POST /v1/attachments | Authenticated image upload; return opaque attachment ID |
| POST /v1/messages | Send rich-text runs and optional attachment ID to the fixed peer; require client request UUID |
| GET /v1/sync?cursor=... | Durable ordered changes for this device; cursor advances after local transaction |
| GET /v1/attachments/{id} | Authenticated peer-authorized download; stream bytes |
| PUT /v1/messages/{id}/read | Idempotent per-recipient read receipt |
| WS /v1/events | Optional wake-up hints; durable sync is the source of truth |

Messages store server ID, pair/sender/recipient IDs, client request UUID, timestamps, rich-text schema/body, optional attachment ID, and read state. Attachments store generated IDs, media type, size, checksum, and server-generated relative paths. Read/sync mutations include a durable sequence number. The server checks that the sender owns an attachment and both clients belong to the fixed pair; client filenames never become filesystem paths.

Write uploads to temporary files, validate and atomically rename, then commit references; clean abandoned uploads. Use unique constraints on sender plus client request UUID so retries after a lost response cannot duplicate a send. Clients retain a persistent outbox, retry with backoff, and reconcile after sleep, disconnect, or app restart. A WebSocket notification may be duplicated or missed without losing the message. No push entitlement or third-party relay is necessary for a running app's local-network polling/sync.

Configure `SOMBRERO_DATA_DIR` and `SOMBRERO_MEDIA_DIR`. The inspected Pi has Debian 13 ARM64, Python 3.13.5, about 110 GiB free on its SD card and no external mount, so initial deployment explicitly uses `/home/admin/.local/share/sombrero` with `media` beneath it. Port 8080 is already occupied and remains untouched; the API binds to localhost port 8765. External-drive migration remains supported with an explicit verified mount. Refuse to silently create a replacement directory on the Pi's system disk if the intended drive is absent. Return a retriable service error, retain the client's draft, and resume after the drive returns. Back up database plus referenced media consistently. Store server times in UTC; never schedule animation from network timestamps.

## Daily Bible verse

The native app bundles 100 familiar verses/short passages in `Sources/PetAssets/Resources/Bible/verses.json`. `tools/import-bible-text.py` extracts exact public-domain World English Bible text from the publisher’s WEBP verse-per-line archive; the resource records the download/source URLs, retrieval time, archive SHA-256, and attribution [S4]. The reference/topic input remains in `docs/sombrero-v1-verse-catalog.json`. Reading requires no network access. An ESV or other translation can replace it if requested and appropriately licensed. Short multi-verse selections count as one daily item.

Each local calendar date receives one persisted random verse, available all day beginning at local midnight. Persist the date, timezone, midnight ready timestamp, chosen verse ID, and unread/read state. Reconcile on launch, wake, clock/timezone changes and at the next local midnight. Existing assignments from the earlier random-time schedule migrate to all-day availability while preserving their passage and read status. Never backfill missed dates or reroll an existing date.

At selection, exclude every verse ID assigned in the preceding three local calendar dates, whether read or not. Choose uniformly from the remaining entries using an injectable RNG, then persist the assignment atomically. Catalog entries here do not overlap ranges for the same chapter, making the exclusion unambiguous. Keep history beyond three records long enough to reconcile date/timezone changes; one local date receives at most one assignment. Default is independent readiness/history per laptop; synchronized daily choices are a separate option if later wanted.

At the start of each local date, mark dailyVerseUnread without raising the message badge. Read Bible verse routes to 7a → 7b. The existing speech menu animates closed while 7a plays; after 7a finishes and the bubble is fully closed, it animates open with the verse text and reference. There is no opening/loading message. Long passages have a single Previous / page count / Next row. The reader shows no source/version line or Done button. It uses a compact fixed 220 × 260 point frame, with more pages for longer passages instead of growing the bubble or requiring scrolling at normal size. Its text view remains scrollable on constrained layouts. Displaying the final page marks that day's passage read; a partial or canceled read preserves its unread state. Clicking the duck or outside the bubble closes the reader, finishes the current 7b loop, plays 7c, and returns to 1a. Daily reading state is independent of the message badge, which remains active only for unread incoming messages.

The native menu also offers Preview Bible Reader to exercise the complete animation/reader route without marking or replacing the daily assignment. Closing or sleep cancels safely; only displaying the last page of daily content marks that assignment read. Daily readiness runs independently of the animation clock, including while the duck is hidden or paused, and reconciles on wake, date, timezone and system-clock changes.

The daily Bible action is available throughout the day, including after reading it. It is omitted only if the offline catalog cannot be loaded. The earlier time-availability Debug override has been removed. The main speech menu has no Done/Close dismissal row; its existing close gesture remains available. Show message is always enabled. It shows only its label and a green watercolor exclamation mark for unread incoming messages, with no sender caption or extra text; reading clears that signifier while keeping the inbox action available. Bible and animation previews remain under Debug.

The native control panel keeps Come back now and the live return countdown first, followed by Always on Top, Show on All Desktops, Click Through Pet, Pause Motion, and Size. Everything else, including the app version/build, message connection/outbox, updates, Debug, and Quit, lives in its Preferences submenu. The countdown refreshes each second while open, and shows Not away or Away until called when no timed return is active.

The menu bubble and verse bubble have separate modes. Switching to the reading content must not accidentally lose the control-panel recovery path. Dismissal, sleep, and app shutdown close UI safely; later reopening does not pretend a canceled read was completed.

Verification: `scripts/test-macos.sh` checks the catalog, scheduling, three-day exclusion, timezone/DST reconciliation, completion rules, and cancellation/reopening transitions. `scripts/test-ui-macos.sh` renders all 100 passages and exercises the real coordinator tick sequence through menu collapse during 7a, reader expansion at 7b, presentation, cancel/reopen during 7c, persisted last-page completion, preview-to-daily switching, recovery, sleep, and readiness while hidden/paused. Presentation is acknowledged only after the verse bubble finishes opening; neither 7a nor its collapse/expansion counts as reading. The reader clamps to the available work area when a non-overlapping placement cannot fit.

## Implementation order and acceptance gates

1. **Graph controller:** replace numeric prototype states with typed string IDs, validated graph data, priority policy, pending/active requests, and tokenized clip commands. Exhaustively test every pictured edge, entry-time skips, RNG weights, stale completions, and recovery paths. Map final assets only when supplied.
2. **Local interaction and lifecycle:** hover signal, click/drag separation, drawn menu, notification overlay, timeout visibility, two away modes, recall through weighted 4b/4c, restart and wake reconciliation. Test input pass-through and focus behavior across every visible UI region.
3. **Python test service:** provision two test identities, SQLite/media, API contract, durable sync, read receipts, upload limits, outbox and retries. Test third-device rejection, duplicated/lost replies, corrupted upload, server restart, absent media volume, and authorization for peer attachments. Do not collect photos during tests without explicit capture interaction.
4. **Receive/compose/camera:** supplied Polaroid artwork, independent resizable Keep/Close windows, rich-text round trip, camera selection/permission/device loss, hold 6b until send acknowledgment, cancel/retake recovery, explicit send, and integration of 5a–5c/6a–6c. Confirm flash timing against the purple exit rule.
5. **Daily verse:** exact verified offline text, persisted all-day local-date assignment, three-day exclusion, bubble reader and 7a–7c. Test DST, timezone/date changes, offline startup, after-hours launch, and independent daily read state and message badges.
6. **Two-laptop/Pi rehearsal:** app rename plus preference migration preserving old placement, actual camera/Continuity tests on target macOS versions, signed app identity and camera usage strings, realistic media transfer, drive removal/recovery, Spaces/fullscreen/sleep, then a complete real-user flow on both laptops.

The core checks cover local graph routing, authored default weights, requests through skipped gateways, drawing timing, stale completion rejection, bubble reversal, packaged assets, fallback, and placement. `scripts/test-ui-macos.sh` renders every bubble mode and checks text/control containment plus flipped and scaled placement. The daily-reader checks cover exact bundled text, persisted scheduling and DST/timezone reconciliation, no-repeat dates, cancellation/read acknowledgement, pagination, every passage’s text layout, and stable conversation anchoring. `scripts/test-messaging-client.sh` checks the real URLSession client against HTTP fixtures, including lost responses, offline read receipts, private media copies and profile isolation. `scripts/test-message-windows.sh` checks native composition/viewing with synthetic media. Python storage/authorization tests cover the server; its actual FastAPI HTTP suite must run with the web dependencies installed. Real camera hardware, two physical Macs, Pi performance and public HTTPS still require deployment acceptance checks. Rebuild with `scripts/build-macos.sh`, then reopen `build/sombrero.app`; primary-click the duck for its speech menu, or use the native control panel's Open Speech Menu / Preview Animation commands.

## Remaining decisions, with proposed defaults

- 1a's handwritten weights total 1.02: normalize relative weights as above.
- Multiple simultaneously true conditional edges: dismissal, pending request, pet, then default, only where the diagram provides a route.
- Camera flash: preserve purple 6b exit, so the animated flash may follow exposure; 6c follows server-acknowledged sending.
- Go away during a prop routine: finish its safe exit, recover to standing, then goodbye; the immediate native hide command remains available.
- Away-state incoming messages/verses: retain unread state and never summon the duck.
- Bible translation/daily sharing: use offline WEB and independent per-laptop daily schedules by default.
- Missing final sheets: plan assets by new string IDs; do not relabel existing sheets without inspecting content or generate new character artwork in this planning step.

## Sources

The user's latest PDF is the animation authority; the prose clarifications in this conversation determine flag and away semantics. External API references support capabilities only; component choices and defaults above are design proposals.

- [S1 — Apple: Supporting Continuity Camera in your macOS app](https://developer.apple.com/documentation/avfoundation/supporting-continuity-camera-in-your-macos-app)
- [S2 — FastAPI: WebSockets](https://fastapi.tiangolo.com/advanced/websockets/)
- [S3 — FastAPI: Request Files](https://fastapi.tiangolo.com/tutorial/request-files/)
- [S4 — eBible: World English Bible source and public-domain notice](https://ebible.org/details.php?id=engwebp)

## Starter verse catalog

These are 100 editorially selected familiar references, not a measured popularity ranking. Exact translation text is a later ingestion/verification task before the reading feature ships. The matching JSON contains stable IDs and parsed book/chapter/ranges.

| # | Reference | Topic |
| --- | --- | --- |
| 1 | Genesis 1:1 | Creation |
| 2 | Numbers 6:24-26 | Blessing |
| 3 | Deuteronomy 6:5 | Love God |
| 4 | Deuteronomy 31:6 | Courage |
| 5 | Joshua 1:9 | Strength |
| 6 | Joshua 24:15 | Serving God |
| 7 | 1 Samuel 16:7 | The heart |
| 8 | 2 Chronicles 7:14 | Humility and prayer |
| 9 | Nehemiah 8:10 | Joy |
| 10 | Job 19:25 | Redeemer |
| 11 | Psalm 16:8 | Steadfastness |
| 12 | Psalm 19:14 | Words and meditation |
| 13 | Psalm 23:1 | Shepherd |
| 14 | Psalm 27:1 | Confidence |
| 15 | Psalm 34:8 | God's goodness |
| 16 | Psalm 34:18 | Comfort |
| 17 | Psalm 37:4 | Delight in God |
| 18 | Psalm 46:1 | Refuge |
| 19 | Psalm 46:10 | Stillness |
| 20 | Psalm 51:10 | A clean heart |
| 21 | Psalm 55:22 | Burdens |
| 22 | Psalm 56:3 | Trust |
| 23 | Psalm 90:12 | Wisdom |
| 24 | Psalm 100:4 | Thanksgiving |
| 25 | Psalm 103:12 | Forgiveness |
| 26 | Psalm 118:24 | Rejoicing |
| 27 | Psalm 119:105 | Guidance |
| 28 | Psalm 121:1-2 | Help |
| 29 | Psalm 139:14 | Wonderfully made |
| 30 | Psalm 139:23-24 | Examination |
| 31 | Proverbs 3:5-6 | Trust and direction |
| 32 | Proverbs 4:23 | Guarding the heart |
| 33 | Proverbs 9:10 | Wisdom |
| 34 | Proverbs 16:3 | Commitment |
| 35 | Proverbs 17:17 | Friendship |
| 36 | Proverbs 18:10 | Refuge |
| 37 | Proverbs 22:6 | Teaching children |
| 38 | Proverbs 27:17 | Encouragement |
| 39 | Ecclesiastes 3:1 | Seasons |
| 40 | Isaiah 9:6 | The promised Son |
| 41 | Isaiah 26:3 | Peace |
| 42 | Isaiah 40:31 | Renewed strength |
| 43 | Isaiah 41:10 | Fearlessness |
| 44 | Isaiah 43:2 | God's presence |
| 45 | Isaiah 53:5 | Healing and redemption |
| 46 | Isaiah 55:8-9 | God's ways |
| 47 | Jeremiah 29:11 | Hope in exile |
| 48 | Jeremiah 33:3 | Calling on God |
| 49 | Lamentations 3:22-23 | Mercies |
| 50 | Micah 6:8 | Justice and humility |
| 51 | Zephaniah 3:17 | God's delight |
| 52 | Matthew 5:14-16 | Light |
| 53 | Matthew 6:33 | Priorities |
| 54 | Matthew 7:7 | Prayer |
| 55 | Matthew 11:28 | Rest |
| 56 | Matthew 22:37-39 | Love God and neighbor |
| 57 | Matthew 28:19-20 | Discipleship |
| 58 | Mark 10:45 | Service |
| 59 | Luke 1:37 | God's power |
| 60 | Luke 6:31 | Kindness |
| 61 | John 1:1 | The Word |
| 62 | John 1:12 | Children of God |
| 63 | John 3:16 | God's love |
| 64 | John 8:12 | Light of life |
| 65 | John 10:10 | Abundant life |
| 66 | John 11:25-26 | Resurrection |
| 67 | John 13:34-35 | Love one another |
| 68 | John 14:6 | The way |
| 69 | John 14:27 | Peace |
| 70 | John 15:5 | Abiding |
| 71 | John 15:13 | Sacrificial love |
| 72 | Acts 1:8 | Witness |
| 73 | Acts 4:12 | Salvation |
| 74 | Romans 3:23 | Human need |
| 75 | Romans 5:8 | Grace |
| 76 | Romans 6:23 | Eternal life |
| 77 | Romans 8:1 | No condemnation |
| 78 | Romans 8:28 | God's purpose |
| 79 | Romans 8:38-39 | Enduring love |
| 80 | Romans 10:9 | Faith |
| 81 | Romans 12:1-2 | Renewal |
| 82 | Romans 12:12 | Hope and prayer |
| 83 | 1 Corinthians 10:13 | Temptation |
| 84 | 1 Corinthians 13:4-7 | Love |
| 85 | 1 Corinthians 16:14 | Acting in love |
| 86 | 2 Corinthians 5:7 | Walking by faith |
| 87 | 2 Corinthians 5:17 | New creation |
| 88 | 2 Corinthians 12:9 | Sufficient grace |
| 89 | Galatians 2:20 | Life in Christ |
| 90 | Galatians 5:22-23 | Fruit of the Spirit |
| 91 | Galatians 6:9 | Perseverance |
| 92 | Ephesians 2:8-9 | Grace through faith |
| 93 | Ephesians 3:20 | God's power |
| 94 | Ephesians 4:32 | Kindness and forgiveness |
| 95 | Philippians 4:6-7 | Prayer and peace |
| 96 | Philippians 4:13 | Strength in Christ |
| 97 | Colossians 3:23 | Wholehearted work |
| 98 | 2 Timothy 1:7 | Courage and love |
| 99 | Hebrews 11:1 | Faith |
| 100 | 1 Peter 5:7 | Casting anxiety |

## Distribution

Sparkle integration, a checksum-pinned dependency fetch, universal release packaging, signed appcast generation, GitHub Release publishing, and a stock-macOS installer are implemented in source. See `docs/RELEASING.md` for current setup and validation status. The user has prepared a first update-enabled archive locally; its checksum and real Sparkle signature were verified. The user now wants one public `micahlai/sombrero` repository for source and releases and is deleting the separate release repository. All new builds use the source repository's feed and download URLs. The existing first archive embeds the old feed, so it must be replaced by a new build with an incremented build number. GitHub API access from this session still fails, so remote visibility/publication has not been verified. Apple Team ID is `98RU8TVC42`, but no valid Developer ID signing identity was found locally. One-use enrollment reuses the second existing provisioned device; it never provisions another pair or changes history. The new server endpoint still needs deployment on the Pi.
