"""Authorization, validation and persistence; deliberately usable without web dependencies."""
from __future__ import annotations

import hashlib
import hmac
import json
import os
import sqlite3
import tempfile
import uuid
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


def timestamp() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


class ServiceError(Exception):
    def __init__(self, status: int, detail: str):
        super().__init__(detail)
        self.status, self.detail = status, detail


def identifier(value: Any) -> str:
    try:
        if not isinstance(value, str):
            raise ValueError()
        return str(uuid.UUID(value))
    except (ValueError, AttributeError):
        raise ServiceError(422, "Expected a UUID identifier") from None


@dataclass(frozen=True)
class Settings:
    data_dir: Path
    media_dir: Path
    configuration: dict
    max_image_bytes: int = 10 * 1024 * 1024
    max_video_bytes: int = 100 * 1024 * 1024

    @classmethod
    def from_environment(cls) -> "Settings":
        data = Path(os.environ.get("SOMBRERO_DATA_DIR", "./data")).expanduser().resolve()
        media_value = os.environ.get("SOMBRERO_MEDIA_DIR")
        if not media_value:
            raise RuntimeError("SOMBRERO_MEDIA_DIR must explicitly name the provisioned media volume")
        configuration = json.loads((data / "devices.json").read_text())
        return cls(data, Path(media_value).expanduser().resolve(), configuration,
                   int(os.environ.get("SOMBRERO_MAX_IMAGE_BYTES", 10 * 1024 * 1024)),
                   int(os.environ.get("SOMBRERO_MAX_VIDEO_BYTES", 100 * 1024 * 1024)))


class Store:
    def __init__(self, settings: Settings):
        self.settings = settings
        self.configuration = settings.configuration
        self.pair_id = identifier(self.configuration.get("pairID"))
        devices = self.configuration.get("devices", [])
        if self.configuration.get("version") != 1 or len(devices) != 2:
            raise ValueError("Exactly two provisioned devices are required")
        self.devices = {identifier(d["id"]): d for d in devices}
        hashes = [d.get("tokenSHA256", "") for d in devices]
        if len(self.devices) != 2 or len(set(hashes)) != 2 or any(
            not isinstance(value, str) or len(value) != 64 or any(c not in "0123456789abcdef" for c in value)
            for value in hashes
        ):
            raise ValueError("Invalid or duplicate device configuration")
        if settings.max_image_bytes < 1 or settings.max_video_bytes < 1:
            raise ValueError("Attachment limits must be positive")
        settings.data_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
        self.database = settings.data_dir / "messages.sqlite3"
        with self.connect() as db:
            db.execute("PRAGMA journal_mode=WAL")
            db.executescript("""
                CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS attachments (
                    id TEXT PRIMARY KEY, owner_id TEXT NOT NULL, client_upload_id TEXT,
                    media_type TEXT NOT NULL, byte_count INTEGER NOT NULL,
                    sha256 TEXT NOT NULL, created_at TEXT NOT NULL,
                    UNIQUE(owner_id, client_upload_id)
                );
                CREATE TABLE IF NOT EXISTS messages (
                    id TEXT PRIMARY KEY, sender_id TEXT NOT NULL, recipient_id TEXT NOT NULL,
                    client_request_id TEXT NOT NULL, body TEXT NOT NULL,
                    attachment_id TEXT REFERENCES attachments(id),
                    created_at TEXT NOT NULL, read_at TEXT,
                    UNIQUE(sender_id, client_request_id)
                );
                CREATE TABLE IF NOT EXISTS changes (
                    sequence INTEGER PRIMARY KEY AUTOINCREMENT,
                    type TEXT NOT NULL, payload TEXT NOT NULL
                );
            """)
            existing = db.execute("SELECT value FROM metadata WHERE key='pairID'").fetchone()
            if existing and existing["value"] != self.pair_id:
                raise ValueError("Database belongs to a different pair; refusing to reuse it")
            db.execute("INSERT OR IGNORE INTO metadata VALUES ('pairID', ?)", (self.pair_id,))
        os.chmod(self.database, 0o600)
        # Remove only abandoned temporary uploads on the verified media volume.
        # Unreferenced committed objects are retained for explicit backup/repair.
        if self.media_available():
            for path in settings.media_dir.glob(".upload-*"):
                if path.is_file() and path.stat().st_mtime < datetime.now().timestamp() - 86400:
                    path.unlink(missing_ok=True)

    @contextmanager
    def connect(self):
        db = sqlite3.connect(self.database, timeout=10)
        db.row_factory = sqlite3.Row
        db.execute("PRAGMA foreign_keys=ON")
        try:
            with db:
                yield db
        finally:
            db.close()

    def media_available(self) -> bool:
        try:
            mount = self.configuration.get("mediaMountRoot")
            if mount and (not os.path.ismount(mount) or not self.settings.media_dir.resolve().is_relative_to(Path(mount).resolve())):
                return False
            marker = self.settings.media_dir / ".sombrero-volume"
            return self.settings.media_dir.is_dir() and marker.read_text().strip() == self.pair_id
        except OSError:
            return False

    def require_media(self):
        if not self.media_available():
            raise ServiceError(503, "Media volume is unavailable; retry when it is mounted")

    def authenticate(self, authorization: str | None) -> str:
        if not authorization or not authorization.startswith("Bearer "):
            raise ServiceError(401, "Device authorization required")
        token = authorization[7:]
        if len(token) > 256:
            raise ServiceError(401, "Invalid device credential")
        digest = hashlib.sha256(token.encode()).hexdigest()
        for device_id, device in self.devices.items():
            if hmac.compare_digest(digest, device["tokenSHA256"]):
                return device_id
        raise ServiceError(401, "Invalid device credential")

    def identity(self, device: str) -> dict:
        return {"deviceID": device, "peerID": self.peer(device), "pairID": self.pair_id}

    def peer(self, device: str) -> str:
        return next(d for d in self.devices if d != device)

    @staticmethod
    def validate_body(body: Any) -> dict:
        if not isinstance(body, dict) or set(body) != {"version", "runs"} or type(body["version"]) is not int or body["version"] != 1:
            raise ServiceError(422, "Expected rich text version 1")
        runs = body["runs"]
        if not isinstance(runs, list) or len(runs) > 1000:
            raise ServiceError(422, "Rich text supports at most 1000 runs")
        result, length = [], 0
        for run in runs:
            if not isinstance(run, dict) or not set(run) <= {"text", "bold", "italic", "underline"} or not isinstance(run.get("text"), str):
                raise ServiceError(422, "Invalid rich text run")
            if any(type(run[key]) is not bool for key in ("bold", "italic", "underline") if key in run):
                raise ServiceError(422, "Rich text styles must be booleans")
            length += len(run["text"])
            result.append({"text": run["text"], **{k: run.get(k, False) for k in ("bold", "italic", "underline")}})
        if length > 20000:
            raise ServiceError(422, "Message exceeds 20000 characters")
        return {"version": 1, "runs": result}

    def attachment_json(self, row: sqlite3.Row) -> dict:
        return {"id": row["id"], "mediaType": row["media_type"], "byteCount": row["byte_count"],
                "sha256": row["sha256"], "createdAt": row["created_at"]}

    def message_json(self, db, row) -> dict:
        attachment = None
        if row["attachment_id"]:
            attachment = self.attachment_json(db.execute("SELECT * FROM attachments WHERE id=?", (row["attachment_id"],)).fetchone())
        return {"id": row["id"], "pairID": self.pair_id, "senderID": row["sender_id"],
                "recipientID": row["recipient_id"], "clientRequestID": row["client_request_id"],
                "body": json.loads(row["body"]), "attachment": attachment,
                "createdAt": row["created_at"], "readAt": row["read_at"]}

    def send(self, device: str, payload: Any) -> dict:
        if not isinstance(payload, dict) or not set(payload) <= {"clientRequestID", "body", "attachmentID"}:
            raise ServiceError(422, "Invalid message fields")
        request_id = identifier(payload.get("clientRequestID"))
        body = self.validate_body(payload.get("body"))
        body_json = json.dumps(body, sort_keys=True, separators=(",", ":"))
        attachment = payload.get("attachmentID")
        if attachment is not None:
            attachment = identifier(attachment)
        if not attachment and not any(run["text"].strip() for run in body["runs"]):
            raise ServiceError(422, "A message needs text or an attachment")
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            existing = db.execute("SELECT * FROM messages WHERE sender_id=? AND client_request_id=?", (device, request_id)).fetchone()
            if existing:
                if existing["body"] != body_json or existing["attachment_id"] != attachment:
                    raise ServiceError(409, "Request ID already used for different message content")
                return self.message_json(db, existing)
            if attachment:
                row = db.execute("SELECT * FROM attachments WHERE id=? AND owner_id=?", (attachment, device)).fetchone()
                if not row:
                    raise ServiceError(403, "Attachment does not belong to this sender")
                self.require_media()
                if not self.attachment_path(attachment).is_file():
                    raise ServiceError(503, "Attachment bytes are unavailable")
            message_id = str(uuid.uuid4())
            db.execute("INSERT INTO messages VALUES (?,?,?,?,?,?,?,NULL)",
                       (message_id, device, self.peer(device), request_id, body_json, attachment, timestamp()))
            result = self.message_json(db, db.execute("SELECT * FROM messages WHERE id=?", (message_id,)).fetchone())
            db.execute("INSERT INTO changes(type,payload) VALUES ('message',?)", (json.dumps(result),))
            return result

    def mark_read(self, device: str, message_id: str) -> dict:
        message_id = identifier(message_id)
        with self.connect() as db:
            db.execute("BEGIN IMMEDIATE")
            row = db.execute("SELECT * FROM messages WHERE id=?", (message_id,)).fetchone()
            if not row:
                raise ServiceError(404, "Message not found")
            if row["recipient_id"] != device:
                raise ServiceError(403, "Only the recipient may mark a message read")
            if row["read_at"] is None:
                db.execute("UPDATE messages SET read_at=? WHERE id=?", (timestamp(), message_id))
                row = db.execute("SELECT * FROM messages WHERE id=?", (message_id,)).fetchone()
                result = self.message_json(db, row)
                db.execute("INSERT INTO changes(type,payload) VALUES ('read',?)", (json.dumps(result),))
                return result
            return self.message_json(db, row)

    def sync(self, device: str, cursor: int, limit: int = 100) -> dict:
        if type(cursor) is not int or cursor < 0 or not 1 <= limit <= 200:
            raise ServiceError(422, "Invalid cursor or page limit")
        with self.connect() as db:
            latest = db.execute("SELECT COALESCE(MAX(sequence),0) FROM changes").fetchone()[0]
            if cursor > latest:
                raise ServiceError(409, "Sync cursor is ahead of server history; reset local sync cursor")
            rows = db.execute("SELECT * FROM changes WHERE sequence>? ORDER BY sequence LIMIT ?", (cursor, limit + 1)).fetchall()
            selected = rows[:limit]
            return {"cursor": selected[-1]["sequence"] if selected else cursor, "hasMore": len(rows) > limit,
                    "changes": [{"sequence": r["sequence"], "type": r["type"], "message": json.loads(r["payload"])} for r in selected]}

    def attachment_path(self, attachment_id: str) -> Path:
        return self.settings.media_dir / (identifier(attachment_id) + ".bin")

    def attachment_for_download(self, device: str, attachment_id: str) -> tuple[dict, Path]:
        attachment_id = identifier(attachment_id)
        with self.connect() as db:
            row = db.execute("SELECT * FROM attachments WHERE id=?", (attachment_id,)).fetchone()
            if not row:
                raise ServiceError(404, "Attachment not found")
            if row["owner_id"] != device and not db.execute(
                "SELECT 1 FROM messages WHERE attachment_id=? AND recipient_id=?", (attachment_id, device)).fetchone():
                raise ServiceError(403, "Attachment has not been shared with this device")
            self.require_media()
            path = self.attachment_path(attachment_id)
            if not path.is_file() or path.stat().st_size != row["byte_count"]:
                raise ServiceError(503, "Attachment bytes are unavailable")
            return self.attachment_json(row), path

    def upload(self, device: str, media_type: str, client_upload_id: str | None = None) -> "Upload":
        self.require_media()
        if client_upload_id is not None:
            client_upload_id = identifier(client_upload_id)
        return Upload(self, device, media_type, client_upload_id)


class Upload:
    IMAGE_TYPES = {"image/jpeg", "image/png", "image/gif", "image/heic", "image/heif"}
    VIDEO_TYPES = {"video/mp4", "video/quicktime"}

    def __init__(self, store: Store, owner: str, media_type: str, client_id: str | None):
        self.store, self.owner, self.client_id = store, owner, client_id
        self.media_type = media_type.split(";", 1)[0].strip().lower()
        if self.media_type not in self.IMAGE_TYPES | self.VIDEO_TYPES:
            raise ServiceError(415, "Unsupported attachment type")
        self.limit = store.settings.max_image_bytes if self.media_type in self.IMAGE_TYPES else store.settings.max_video_bytes
        try:
            file = tempfile.NamedTemporaryFile(prefix=".upload-", dir=store.settings.media_dir, delete=False)
        except OSError:
            raise ServiceError(503, "Media volume is not writable") from None
        self.file, self.path = file, Path(file.name)
        self.size, self.digest, self.prefix, self.tail = 0, hashlib.sha256(), b"", b""
        self.done = False

    def write(self, chunk: bytes):
        if self.size + len(chunk) > self.limit:
            raise ServiceError(413, "Attachment exceeds the configured size limit")
        self.size += len(chunk); self.digest.update(chunk)
        self.prefix = (self.prefix + chunk)[:65536]
        self.tail = (self.tail + chunk)[-16:]
        try:
            self.file.write(chunk)
        except OSError:
            raise ServiceError(503, "Attachment storage failed; retry later") from None

    def valid_signature(self) -> bool:
        header = self.prefix
        if self.media_type == "image/jpeg":
            return len(header) >= 4 and header.startswith(b"\xff\xd8\xff") and self.tail.endswith(b"\xff\xd9")
        if self.media_type == "image/png":
            if len(header) < 33 or not header.startswith(b"\x89PNG\r\n\x1a\n") or header[12:16] != b"IHDR":
                return False
            width, height = int.from_bytes(header[16:20], "big"), int.from_bytes(header[20:24], "big")
            return 0 < width * height <= 100_000_000
        if self.media_type == "image/gif":
            return len(header) >= 10 and header[:6] in (b"GIF87a", b"GIF89a") and int.from_bytes(header[6:8], "little") > 0 and int.from_bytes(header[8:10], "little") > 0
        if len(header) < 16 or header[4:8] != b"ftyp":
            return False
        size = int.from_bytes(header[:4], "big")
        if size < 16 or size > min(self.size, len(header)):
            return False
        brands = {header[8:12]} | {header[i:i+4] for i in range(16, size, 4)}
        if self.media_type in ("image/heic", "image/heif"):
            return bool(brands & {b"heic", b"heix", b"hevc", b"hevx", b"mif1", b"msf1"})
        if self.media_type == "video/quicktime":
            return b"qt  " in brands
        return bool(brands & {b"isom", b"iso2", b"mp41", b"mp42", b"avc1", b"M4V "})

    def finish(self) -> dict:
        if self.done:
            raise RuntimeError("Upload already finished")
        if not self.valid_signature():
            self.abort()
            raise ServiceError(415, "Attachment bytes do not match the declared media type")
        self.store.require_media()
        checksum = self.digest.hexdigest()
        try:
            self.file.flush(); os.fsync(self.file.fileno()); self.file.close()
            with self.store.connect() as db:
                db.execute("BEGIN IMMEDIATE")
                if self.client_id:
                    existing = db.execute("SELECT * FROM attachments WHERE owner_id=? AND client_upload_id=?", (self.owner, self.client_id)).fetchone()
                    if existing:
                        if existing["sha256"] != checksum or existing["media_type"] != self.media_type:
                            raise ServiceError(409, "Upload ID already used for different content")
                        self.done = True
                        return self.store.attachment_json(existing)
                attachment_id = str(uuid.uuid4())
                destination = self.store.attachment_path(attachment_id)
                os.replace(self.path, destination)
                try:
                    db.execute("INSERT INTO attachments VALUES (?,?,?,?,?,?,?)", (attachment_id, self.owner, self.client_id, self.media_type, self.size, checksum, timestamp()))
                except Exception:
                    destination.unlink(missing_ok=True)
                    raise
                result = self.store.attachment_json(db.execute("SELECT * FROM attachments WHERE id=?", (attachment_id,)).fetchone())
            self.done = True
            return result
        except OSError:
            raise ServiceError(503, "Attachment storage failed; retry later") from None
        finally:
            self.abort()

    def abort(self):
        # Cleanup must not replace a useful 413/415/503 with an unrelated error
        # if a physical media volume disappears while its upload is open.
        try:
            self.file.close()
        except OSError:
            pass
        try:
            self.path.unlink(missing_ok=True)
        except OSError:
            pass
