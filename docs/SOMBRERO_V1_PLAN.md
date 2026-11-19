# sombrero — first release plan

Updated November 19, 2026 (America/New_York). Planning deliverable; this document does not claim the release features are implemented. The running prototype remains the five-state, 6 fps app until its controller is replaced.

## Authority and release scope

The duck's name is **sombrero** and the product name is **sombrero**. Keep the native macOS Swift/AppKit app. This release adds the user's full animation graph, hover petting, a drawn speech-bubble menu, timed/manual dismissal, two-laptop photo and rich-text messaging, camera capture, and daily Bible reading. There is no LLM.

The source is the latest two-page hand-drawn PDF, visually inspected as rendered images rather than inferred from OCR. A copy is at `docs/reference/sombrero-v1-state-diagram.pdf`, SHA-256 `24b6cef91b52f27557fa3b4d4d415cd031f5cbea8a9526c848b27911464dc2ab`. The earlier five-state random controller and its 40/40/20 and 80/20 weights describe only the prototype and are superseded for the release.

Related data: `docs/sombrero-v1-state-graph.json` transcribes the colored arrows, and `docs/sombrero-v1-verse-catalog.json` lists 100 starter references and topics. New final animation sheets have not been supplied. Keep the old assets; do not assume their five numeric filenames map to this graph's numbered-lettered identifiers.

Current cadence remains 6 drawings/second: a 24 fps timeline with each drawing held for four frames. Each animation has its own complete sprite sheet identified by a string ID such as `3c`. Timeout has no sprite or active duck window. Final sheet manifests will record actual frame order/count, alpha, registration, and holds; do not assume uniform grids or interpolate missing drawings.

## State inventory and black arrows

Black arrows run only at clip completion when no permitted red/purple condition wins. Roll once per completed clip, including repeats. Single-arrow paths are deterministic. Preserve the handwritten values as relative weights, then normalize each state's eligible black edges.

| State | Animation | Default successor(s), raw weight |
| --- | --- | --- |
| 1a | Standing idle | 1a .975; 1b .02; 1c .02; 2a .005 |
| 1b | Standing look | 1a .8; 1c .2 |
| 1c | Standing wave | 1a 1 |
| 1d | Standing pet | Conditional purple arrows only |
| 2a | Sit down | 3a 1 |
| 2b | Stand up | 1a 1 |
| 3a | Sitting idle | 3a .985; 3b .01; 2b .005 |
| 3b | Sitting look | 3b .1; 3a .9 |
| 3c | Sitting pet | Conditional purple arrows only |
| 4a | Goodbye standing | timeout 1 |
| 4b | Peek in | 1b 1 |
| timeout | Hidden/static | No automatic animation; recall or a configured away timer leads to 4b |
| 5a | Grab photo | 5b 1 |
| 5b | Show photo | 5c 1 |
| 5c | Showing photo idle | Conditional purple arrows only |
| 5d | Put photo away | 1a 1 |
| 6a | Grab camera | 6b 1 |
| 6b | Camera idle | Conditional purple arrows only |
| 6c | Take photo and deliver | 1a 1 |
| 7a | Pull out Bible | 7b 1 |
| 7b | Bible idle | Conditional purple arrows only |
| 7c | Stow Bible | 1a 1 |

There are 21 animation states plus one hidden timeout state. The black weights from 1a total 1.02. Under the user's relative-weight instruction, the resulting probabilities are approximately 95.588% idle, 1.961% look, 1.961% wave, and 0.490% sit down. Keep this discrepancy visible; do not silently change a handwritten weight to make the numbers sum to one.

## Red and purple arrows

Red means interrupt the current animation immediately, including before the first drawing when entering a state. Purple means retain the current clip until its final drawing hold completes, then take the arrow. Guard evaluation must also happen on state entry so gateways can be traversed without drawing them. Use a bounded transition resolver with cycle detection rather than scheduling a zero-duration rendering loop.

| Current state(s) | Condition | Color / behavior | Destination |
| --- | --- | --- | --- |
| 1a, 1b, 1c | pet | Red, immediate | 1d |
| 1a, 1b | goodbye | Red, immediate | 4a |
| 1b | event | Purple, finish clip | 1a |
| 1d | pet and not event | Purple, repeat at end | 1d |
| 1d | event | Purple, finish clip | 1a |
| 1d | not pet | Purple, finish clip | 1c |
| 3a, 3b | pet | Red, immediate | 3c |
| 3a, 3b | event | Red, immediate | 2b |
| 3c | pet and not event | Purple, repeat at end | 3c |
| 3c | not pet or event | Purple, finish clip | 3a |
| 1a | photo-show request | Red, immediate | 5a |
| 1a | photo-take request | Red, immediate | 6a |
| 1a | Bible-read request | Red, immediate | 7a |
| 5c | showPhoto / not showPhoto | Purple, loop / exit at end | 5c / 5d |
| 6b | takingPhoto / not takingPhoto | Purple, loop / exit at end | 6b / 6c |
| 7b | reading / not reading | Purple, loop / exit at end | 7b / 7c |

No event-interrupt arrow is invented for 1c, 2a, 2b, entry/exit clips, or active page-two routines. Their ordinary completion paths eventually reach a gateway. Hover over photo/Bible routines does not interrupt them unless an arrow is supplied.

When guards conflict, proposed deterministic priority is explicit dismissal where supported, then the pending page-two request, then petting, then black flow. In particular, event wins over pet in 3a/3b and over pet-release in 1d. This tie-break is an implementation proposal, not an extra line in the drawing.

## Named events and skipped gateways

`pet`, `showPhoto`, `takingPhoto`, and `reading` are held booleans. A page-two menu action is a durable named request: `photoShow(messageID)`, `photoTake(draftID)`, or `bibleRead(verseID)`. Derive `event=true` from the pending request; do not erase the request at an intermediate return state. Distinguish `activeRequest` from `pendingRequest`, so an active routine does not keep retriggering itself when it returns to 1a.

The user's required example is an acceptance test:

| Step | Expected behavior |
| --- | --- |
| Photo-show selected during 3c | Retain photoShow request and set event true; finish 3c |
| Enter 3a | Its red event edge is already true; skip rendering 3a and start 2b |
| Finish 2b | Reach 1a |
| Enter 1a | Dispatch the retained photoShow request immediately; skip rendering 1a and start 5a |
| Enter 5a | Atomically move request from pending to active and clear aggregate pending event |
| Continue | 5a → 5b → 5c; showPhoto true holds 5c until the user closes the viewer |

For event entry from 1b, finish 1b first; from 3b, the red event edge interrupts immediately. From 2a, finish 2a, reach 3a, then take its red event edge through 2b. A later explicit menu request may queue while a page-two routine is active; do not tear props out mid-routine. Proposed policy: one active routine plus a small FIFO of explicit requests; deduplicate repeated clicks for the same message/draft. Incoming notifications never become unsolicited animation requests.

Each clip play/cancel has a generation token. Ignore stale frame completion, camera, network, or window-close callbacks. Hidden, canceled, or replaced routines must never resurrect a window. No RNG is consumed for conditional edges or skipped gateway states.

## Window lifecycle and control panel

Keep four independent concerns: foreground animation state, native visibility, bubble/viewer/composer windows, and notification availability. Timeout means the duck panel is ordered out and its animation clock stops; empty mouse capture is disabled. A Dock minimization animation is not required for this accessory app. Keep the menu-bar control panel running for recall, quit, and recovery.

The user clarified two away modes:

| Selection | Hidden behavior | Return |
| --- | --- | --- |
| Until I say so | No automatic return, including after incoming messages or a verse becoming ready | Explicit control-panel recall → 4b |
| For N minutes | Persist an absolute return deadline | Deadline → 4b; manual recall may return earlier |

Both continue 4b → 1b. Start the away duration when 4a completes and timeout is entered. Validate positive finite minutes. A sleeping/offline app returns at the next opportunity after an expired deadline; do not replay missed time. Persist hidden mode/deadline across relaunch, and preserve unread notifications while away. Clear transient pet/goodbye state on entering timeout. Timed wake never overrides a later manual-until-recall choice.

The diagram places goodbye on 1a/1b only. Proposed menu recovery from sitting or an active routine: enqueue a pending goodbye, suppress new petting, use the existing return-to-standing path, and start 4a at the next supported gateway. Sitting recovery can reuse event-style routing to 2b, but this is a proposed extension because goodbye is not a page-two event. The native control panel must retain an immediate hide/quit path even if an asset or routine fails.

## Hover, bubble menu, and notification badge

Interpret “icon” as the on-screen duck sprite. Hovering its padded alpha hit area sets pet true; leaving sets false. Re-evaluate when the animation moves beneath a stationary pointer. Moving from the duck to its active speech-bubble menu should keep that interaction stable; proposed behavior holds the last pet signal while interacting with the bubble, clearing it on dismissal/leave. Do not toggle on every sparse watercolor hole. Hovering a macOS menu-bar item should not trigger petting unless separately requested.

A primary click after the existing drag threshold opens a drawn speech bubble anchored to the duck. Use accessible native controls inside the bubble; the original duck panel stays non-key, while text-editing windows may become key only after explicit interaction. Retain drag and context-menu recovery. Bubble geometry counts as interactive; empty pixels outside the duck/bubble pass through.

| Menu item | Availability | Effect |
| --- | --- | --- |
| Go away | Always visible | Show second prompt: until recalled, or for N minutes |
| See message/photo | Enabled when an unread incoming message is available | Enqueue photoShow for a selected message |
| Send message/photo | Always visible | Open the camera/message composition workflow; photoTake is its animation event |
| Read Bible verse | Enabled when a daily verse is ready and unread | Enqueue bibleRead for that day's stored verse |

“Take message/photo” and “send message/photo” are treated as the same compose command. Availability remains distinct from busy state: a repeat click focuses the current composer rather than starting another capture session.

Compute a single badge from `unreadIncomingCount > 0 || dailyVerseUnread`. Draw it in a separate overlay layer above every animation, with a stable anchor, so every sprite sheet need not include an exclamation mark. A badge's own interactive area follows the same mouse policy. If the duck is hidden, retain badge data for recall and expose counts in the control panel without showing the duck.

## Receiving and reading a message

A server notification refreshes the inbox and badge only. The user chooses See message/photo. The workflow routes to 5a, opens a separate polaroid-style message window in coordination with 5b, and holds 5c while that viewer remains open. The photo and rich-text message live in this second window, independent of duck clipping and placement. Final polaroid artwork is deferred; native placeholder framing is acceptable for backend work.

Confirmed by the user: showPhoto is true while the viewer is open and false when the user finishes/closes it. After false, finish 5c, play 5d, then return to 1a. Closing before 5c records false; entry animations finish normally and the exit occurs at the next eligible boundary. A message is marked read only after its content is successfully loaded and shown, never merely because its notification arrived or a request was queued. Read updates are idempotent and retried offline. Multiple unread messages keep the badge present until consumed.

## Composing, camera capture, and sending

Prepare a separate composer window with a polaroid-shaped camera preview and rich-text editor. Offer the built-in camera and discovered supported external/Continuity cameras. Use AVFoundation capture and native text controls. Ask for camera permission only when the user invokes capture. Do not request microphone access for still photos. Apple documents Continuity Camera support through its capture-device discovery APIs; actual device availability depends on system setup [S1].

Set takingPhoto true while a capture is awaiting a successful photo. Start 6a → 6b and the preview. On successful photo capture, immediately retain the image/draft, freeze the preview to that image, set takingPhoto false, and stop live capture when safe. The diagram's purple exit means the current 6b clip then finishes before 6c starts; frame zero of 6c is the planned drawn camera flash. This can place the drawn flash after the physical exposure. If exact exposure-synchronized animation is required, change the 6b exit to red; the current plan preserves the purple arrow.

Capture success and message send success are distinct. Let the user review/edit the rich text and explicitly choose Send. 6c must not silently transmit a draft merely because a photo was taken. It may play its authored “take photo and deliver” gesture while the composer holds the draft; a real delivery indicator reflects server acknowledgment, independently. Closing/canceling before capture needs an authored recovery or a documented neutral fallback; do not fake a captured photo or send anything. A retake creates a fresh capture token and re-enters a camera-compatible state rather than emitting a stale second 6c completion.

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

Use two provisioned device credentials, one pairing record, and explicit peer IDs. Reject a third device. Store client credentials in Keychain and server token hashes outside source control. Binding to localhost is the test default. A home deployment uses an authenticated encrypted connection; off-home access requires a deliberate VPN/private routing or HTTPS deployment. Do not assume an always-on home Pi is reachable from outside the home network, and do not configure public forwarding as part of planning.

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

Configure `SOMBRERO_DATA_DIR` and `SOMBRERO_MEDIA_DIR`; use local directories for tests and an explicit mounted external-drive media path on the Pi. Refuse to silently create a replacement directory on the Pi's system disk if the intended drive is absent. Return a retriable service error, retain the client's draft, and resume after the drive returns. Back up database plus referenced media consistently. Store server times in UTC; never schedule animation from network timestamps.

## Daily Bible verse

Bundle an offline catalog of 100 familiar verses/short passages. This plan supplies references/topics, not generated scripture text. Proposed default translation is the public-domain World English Bible; ingest exact text from its publisher and record attribution/source/version before the reader ships [S4]. An ESV or other translation can replace it if requested and appropriately licensed. Short multi-verse selections count as one daily item.

On each laptop, generate and persist one uniform random ready time for each local calendar date in the inclusive 11:00–19:00 window. Persist the date, timezone, ready timestamp, chosen verse ID, and unread/read state. On app launch, wake, clock change, or timezone change, reconcile rather than starting a new random timer. A launch after today's sampled time makes today's item available immediately; an app asleep at 19:00 presents it at the next opportunity. Do not flood with missed days or re-roll until a preferred verse/time appears.

At selection, exclude every verse ID assigned in the preceding three local calendar dates, whether read or not. Choose uniformly from the remaining entries using an injectable RNG, then persist the assignment atomically. Catalog entries here do not overlap ranges for the same chapter, making the exclusion unambiguous. Keep history beyond three records long enough to reconcile date/timezone changes; one local date receives at most one assignment. Default is independent readiness/history per laptop; synchronized daily choices are a separate option if later wanted.

When due, mark dailyVerseUnread and update the shared badge. Read Bible verse routes to 7a → 7b, displaying the exact verse text and reference as rich text in the speech bubble. Set reading true until explicit Done/close, then false, finish the current 7b loop, play 7c, and return to 1a. Clear the verse badge when the user completes reading; closing before content loads preserves unread state. Reading and unread incoming messages have separate flags, so either can keep the badge active.

The menu bubble and verse bubble have separate modes. Switching to the reading content must not accidentally lose the control-panel recovery path. Dismissal, sleep, and app shutdown close UI safely; later reopening does not pretend a canceled read was completed.

## Implementation order and acceptance gates

1. **Graph controller:** replace numeric prototype states with typed string IDs, validated graph data, priority policy, pending/active requests, and tokenized clip commands. Exhaustively test every pictured edge, entry-time skips, RNG weights, stale completions, and recovery paths. Map final assets only when supplied.
2. **Local interaction and lifecycle:** hover signal, click/drag separation, drawn menu, notification overlay, timeout visibility, two away modes, recall through 4b, restart and wake reconciliation. Test input pass-through and focus behavior across every visible UI region.
3. **Python test service:** provision two test identities, SQLite/media, API contract, durable sync, read receipts, upload limits, outbox and retries. Test third-device rejection, duplicated/lost replies, corrupted upload, server restart, absent media volume, and authorization for peer attachments. Do not collect photos during tests without explicit capture interaction.
4. **Receive/compose/camera:** separate polaroid windows with native placeholder framing, rich-text round trip, camera selection/permission/device loss, successful capture flag, cancel/retake recovery, explicit send, and integration of 5a–5d/6a–6c. Confirm flash timing against the purple exit rule.
5. **Daily verse:** exact verified offline text, persisted 11:00–19:00 schedule, three-day exclusion, bubble reader and 7a–7c. Test DST, timezone/date changes, offline startup, after-hours launch, and unread/read badge independence.
6. **Two-laptop/Pi rehearsal:** app rename plus preference migration preserving old placement, actual camera/Continuity tests on target macOS versions, signed app identity and camera usage strings, realistic media transfer, drive removal/recovery, Spaces/fullscreen/sleep, then a complete real-user flow on both laptops.

The current 14 prototype checks are not proof of this release controller or server. They stay useful as regression coverage while new graph and workflow tests are added. A release build must exercise the new paths with real completion timing rather than frame-by-frame unit tests alone.

## Remaining decisions, with proposed defaults

- 1a's handwritten weights total 1.02: normalize relative weights as above.
- Multiple simultaneously true conditional edges: dismissal, pending request, pet, then default, only where the diagram provides a route.
- Camera flash: preserve purple 6b exit, so the animated flash may follow exposure; capture-versus-send remains separate.
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
