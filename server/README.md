# sombrero messaging service

Private two-device message/photo transport, using FastAPI, SQLite and immutable media files. Native clients authenticate with separate random credentials; the server stores only their SHA-256 hashes. No public account registration or third-device endpoint exists.

Messages use a versioned, restricted rich-text schema. Uploads stream to bounded temporary files, check the declared media type against file signatures, hash their bytes, and atomically rename before committing references. JPEG, PNG, GIF, HEIC/HEIF, MP4 and modern QuickTime containers are supported. Defaults are 10 MiB per image and 100 MiB per video. Signature validation is not a full media decoder or malware scan; clients must handle an unsupported/corrupt media file without marking its message read. SVG/HTML and arbitrary executable formats are rejected. No server-side video transcoding is performed.

Messages, uploads and read receipts are idempotent. Durable ordered `/v1/sync` pages, rather than ephemeral events, are the source of truth. The native app polls while running; there is no dependency on a public push service. The process binds to localhost; public clients use authenticated HTTPS through a reverse proxy.

## Local development

Requires Python 3.10 or later. From this `server` directory:

```sh
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

The provisioning command generates two private credential files and prints only their paths. Import one file on each Mac in the app's messaging connection settings. Never paste tokens into logs, chat, source control or shell command lines. The credential files contain `baseURL`, `deviceID`, `peerID`, `pairID` and `token`. Remote base URLs require HTTPS; plaintext is accepted only for loopback integration testing. Provisioning refuses to overwrite existing identities or message history.

Run the tests from the repository root:

```sh
PYTHONPATH=server server/.venv/bin/python -m unittest discover -s server/tests -v
```

The storage/authorization suite also runs with plain Python and no third-party packages:

```sh
PYTHONPATH=server python3 -m unittest discover -s server/tests -p test_store.py -v
```

`test_http.py` exercises the real FastAPI endpoints when FastAPI and httpx are installed; it explicitly skips those tests if the web dependencies are absent. A skipped HTTP suite is not an end-to-end validation. All tests use disposable local data and fake device credentials, not cameras or the user's real media.

## API contract

Every route except health requires `Authorization: Bearer <device token>`. Sender, peer and pair are derived from that credential. Client filenames never become server filesystem paths. IDs are UUID strings; timestamps are UTC ISO8601 with milliseconds and `Z`.

| Endpoint | Request / response |
| --- | --- |
| `GET /v1/health` | Public `{status:"ok"\|"unavailable",mediaAvailable:bool}`; unavailable media returns 503 |
| `GET /v1/me` | `{deviceID,peerID,pairID}` |
| `POST /v1/attachments` | Raw body, media `Content-Type`, optional stable `X-Client-Upload-ID: UUID`; returns Attachment |
| `GET /v1/attachments/{id}` | Attachment bytes; sender can access own uploads, peer only after sharing in a message |
| `POST /v1/messages` | `{clientRequestID:UUID,body:RichText,attachmentID?:UUID}`; returns Message |
| `GET /v1/sync?cursor=0&limit=100` | `{cursor:int,hasMore:bool,changes:[{sequence:int,type:"message"\|"read",message:Message}]}` |
| `PUT /v1/messages/{id}/read` | No body; only recipient may mark read; returns Message |

`RichText` is `{version:1,runs:[{text:string,bold?:bool,italic?:bool,underline?:bool}]}`, limited to 20,000 characters and 1,000 runs. Unknown fields, unsupported versions and invalid styles are rejected. There must be nonblank text or an attachment. Responses normalize missing style booleans to false.

`Attachment` is `{id,mediaType,byteCount,sha256,createdAt}`.

`Message` is `{id,pairID,senderID,recipientID,clientRequestID,body,attachment:Attachment|null,createdAt,readAt:string|null}`.

Both devices receive the same pair-scoped ordered history; the client filters sender/recipient for the inbox. Commit each sync page locally before advancing its cursor. Reusing a message/upload request UUID with different content is a 409 conflict. The app must preserve outbox entries and retry retriable network/503 failures with the same UUID. A cursor beyond server history is 409; a client doing an explicit full resync starts at zero. Read receipts are sent only after successfully loading and showing the message.

## Raspberry Pi deployment

The agent could not connect to the provided Pi because SSH returned `Operation not permitted`, and terminal computer control was also denied. The user subsequently completed installation in their existing SSH terminal, reported `sombrero.service` active with healthy media storage, and reported the test command returned `OK`. No remote commands were executed by the agent. The instructions below document installation and recovery; do not rerun first-time provisioning on this existing deployment.

1. Inspect the Pi's OS/Python and actual storage mounts first. The existing app plan mentions Pi 3, but this server has not been performance-tested on that hardware. Python must be at least 3.10. Confirm the intended external drive is mounted and writable; do not pick an unmounted directory with the same name.
2. Build a source archive locally with `./server/package.sh`. It includes only explicitly listed source/templates/tests, excluding credentials, databases, uploads, `.venv`, `.env` files and caches.
3. Copy the archive over SSH and extract into `/home/admin/sombrero/server`. The installer below creates the virtual environment and private storage.

Example copy/extract commands from the development machine:

```sh
./server/package.sh
scp build/sombrero-server.tar.gz admin@100.93.248.26:/home/admin/sombrero-server.tar.gz
ssh admin@100.93.248.26
mkdir -p "$HOME/sombrero/server"
tar -xzf "$HOME/sombrero-server.tar.gz" -C "$HOME/sombrero/server"
cd "$HOME/sombrero/server"
```

The user-provided inspection confirmed **ARM64 Debian 13 (trixie), Python 3.13.5, user/group `admin`, about 110 GiB free on the SD card, no external media mount, and an existing listener on port 8080**. The first deployment therefore intentionally uses `$HOME/.local/share/sombrero/media` on the SD card. It does not silently fall back from an expected external drive. Port 8080 is untouched; the private API listens on `127.0.0.1:8765`.

On that Pi, after extracting the archive:

```sh
cd "$HOME/sombrero/server"
./setup-pi.sh
```

`setup-pi.sh` creates the virtual environment, installs the web/test dependencies, runs the full real-HTTP test suite, provisions exactly two device credentials into private files, and installs/starts a hardened systemd service. It refuses an existing setup rather than replacing credentials or history. It does **not** configure DNS, router forwarding, Caddy, or a public relay. The default public origin recorded in the credential exports is `https://sombrero.micahlai.com`; an alternate HTTPS origin can be supplied as `SOMBRERO_PUBLIC_URL=https://... ./setup-pi.sh`. The service remains localhost-only until the public route is separately configured.

When successful, it prints a health result like `{"status":"ok","mediaAvailable":true}`. Check the service without displaying credentials:

```sh
sudo systemctl status sombrero --no-pager
curl --fail http://127.0.0.1:8765/v1/health
```

If a previously provisioned install needs only a service repair, **do not provision it again**. Confirm its private `~/.config/sombrero/server.env` and existing data paths, then adjust/install `deploy/sombrero.service` and start it with `sudo systemctl enable --now sombrero`.

For later external storage, stop the service and move/copy database plus media consistently. Verify the real mount first, update `SOMBRERO_MEDIA_DIR`, add `mediaMountRoot` to the existing private device configuration and the mount to `RequiresMountsFor`/`ReadWritePaths`, then restart and verify health. Every media operation checks its pair-specific volume marker; missing/replaced storage returns 503 rather than recreating directories. Text-only messages remain usable while media is unavailable.

Each Mac imports its own private file using **Message Connection → Import Device File → Connect**. Tokens are stored in that Mac's Keychain. The app's Outbox provides retry and removal controls; an undelivered draft and its media are stored privately per server/pair/device. Never paste the credential file contents into chat. Administrative file transfer can use the existing Tailscale SSH path; ordinary app use must not require Tailscale on either Mac.

Install Caddy using the Pi distribution's supported package instructions. `deploy/Caddyfile` is prepared for **sombrero.micahlai.com**, proxying only to `127.0.0.1:8765`. Before enabling it, configure the DNS record and verify an inbound public route to this Pi. The supplied `100.93.248.26` SSH address is not the public DNS target. A domain alone does not bypass an ISP's inbound restrictions or CGNAT. Both Macs use the HTTPS origin directly; neither must connect to Tailscale. Do not expose Uvicorn's port 8765 publicly.

### Current route: Tailscale Funnel

The user cannot change home router settings. They enabled Funnel on the Pi with `sudo tailscale funnel --bg http://127.0.0.1:8765`; its reported public origin is `https://home-lab.tail4869fe.ts.net`, proxying only to the local API. Caddy and GoDaddy DNS changes are unnecessary for this route. Tailscale must remain running on the Pi; normal Mac app connections use public HTTPS without a VPN. Funnel uses a `.ts.net` hostname and has bandwidth limits; realistic video transfer remains an acceptance check. See the official [Funnel documentation](https://tailscale.com/docs/features/tailscale-funnel).

Check `/v1/health` from a Mac without Tailscale connected before claiming public reachability. The agent's environment could not resolve/reach this hostname, so public access is not independently verified yet. Existing credential exports still contain the originally provisioned `baseURL`; after importing each Mac's own device file, replace the server address with the Funnel origin before pressing Connect. Changing the endpoint does not require new server identities or tokens. Administrative credential copying can use the existing Tailscale SSH path; ordinary app use does not.

Back up the SQLite database consistently (SQLite backup API, or stop the service before copying database/WAL), `devices.json`, the media volume marker and all committed `.bin` objects together. Keep client credential exports separately encrypted/private. Never rerun provisioning to recover an existing pair; restore its configuration/database/media together. Tokens can be revoked by replacing the corresponding hash in the private device configuration and restarting the service; new credentials must be securely delivered to that Mac.

## Implementation limits

The Python storage/authorization suite is executable without internet dependencies; real HTTP integration and Pi deployment require installing the listed packages. Native client checks cover durable retries, media verification and read receipts; native window checks cover composition and displayed photos. Positive video playback could not be verified here because the native VideoToolbox decoder returned error -12911; failed video correctly remains unread. Actual camera capture and video playback need a desktop check. Real-world sleep/network interruptions, actual Pi performance, the public TLS endpoint, external drive removal and two physical Macs still require deployment acceptance testing. Polling provides updates while the native app runs; OS push delivery while it is quit is not implemented.
