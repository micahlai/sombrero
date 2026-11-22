"""Short-lived, single-use setup for an existing provisioned device."""
from __future__ import annotations

import argparse
import hashlib
import json
import secrets
import time
from pathlib import Path
from urllib.parse import urlparse

from .provision import private_json
from .store import ServiceError, Settings, Store

PREFIX = "smbr_enroll_"


def table(db):
    db.execute("""CREATE TABLE IF NOT EXISTS enrollments (
        code_hash TEXT PRIMARY KEY, device_id TEXT UNIQUE NOT NULL,
        expires_at REAL NOT NULL, credential TEXT NOT NULL)""")


def create_code(store: Store, export: dict, ttl: int = 900, now: float | None = None) -> str:
    if not 60 <= ttl <= 3600:
        raise ValueError("Setup lifetime must be between 60 and 3600 seconds")
    token = export.get("token")
    if not isinstance(token, str):
        raise ValueError("Invalid device export")
    device = store.authenticate("Bearer " + token)
    identity = store.identity(device)
    if any(export.get(key) != identity[key] for key in ("deviceID", "peerID", "pairID")):
        raise ValueError("Device export does not match this deployment")
    origin = export.get("baseURL", "")
    parsed = urlparse(origin)
    if parsed.scheme != "https" or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment or parsed.path not in ("", "/"):
        raise ValueError("Setup requires a public HTTPS origin")
    credential = {**identity, "token": token, "baseURL": origin.rstrip("/")}
    code = PREFIX + secrets.token_urlsafe(32)
    current = time.time() if now is None else now
    with store.connect() as db:
        db.execute("BEGIN IMMEDIATE")
        table(db)
        db.execute("DELETE FROM enrollments WHERE expires_at<=? OR device_id=?", (current, device))
        db.execute("INSERT INTO enrollments VALUES (?,?,?,?)",
                   (hashlib.sha256(code.encode()).hexdigest(), device, current + ttl, json.dumps(credential)))
    return code


def redeem_code(store: Store, authorization: str | None, now: float | None = None) -> dict:
    prefix = "Bearer " + PREFIX
    if not authorization or not authorization.startswith(prefix) or len(authorization) != len(prefix) + 43:
        raise ServiceError(401, "Setup code is invalid, expired, or already used")
    digest = hashlib.sha256(authorization[7:].encode()).hexdigest()
    current = time.time() if now is None else now
    result = None
    with store.connect() as db:
        db.execute("BEGIN IMMEDIATE")
        table(db)
        db.execute("DELETE FROM enrollments WHERE expires_at<=?", (current,))
        row = db.execute("SELECT credential FROM enrollments WHERE code_hash=?", (digest,)).fetchone()
        if row:
            result = json.loads(row["credential"])
            db.execute("DELETE FROM enrollments WHERE code_hash=?", (digest,))
    if result is None:
        raise ServiceError(401, "Setup code is invalid, expired, or already used")
    # Revalidate credentials against the currently provisioned two-device pair.
    store.authenticate("Bearer " + result["token"])
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device-file", required=True, type=Path)
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--output", required=True, type=Path, help="New private JSON file for the setup code")
    parser.add_argument("--ttl", type=int, default=900)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Output already exists; choose a new path")
    try:
        store = Store(Settings.from_environment())
        export = json.loads(args.device_file.expanduser().read_text())
        export["baseURL"] = args.base_url
        code = create_code(store, export, args.ttl)
        private_json(args.output, {"server": args.base_url, "setupCode": code, "expiresInSeconds": args.ttl})
    except (OSError, ValueError, ServiceError) as error:
        parser.error(str(error))
    print(f"Saved private one-use setup code to {args.output}. Existing identities and message history are unchanged.")


if __name__ == "__main__":
    main()
