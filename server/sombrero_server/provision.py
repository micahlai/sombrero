"""Explicit first-run provisioning. Credentials go into mode-0600 files, never stdout."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import secrets
import uuid
from pathlib import Path
from urllib.parse import urlparse


def private_json(path: Path, value: dict):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as stream:
        json.dump(value, stream, indent=2)
        stream.write("\n")


def provision(data_dir: Path, media_dir: Path, credentials_dir: Path, base_url: str,
              initialize_media: bool = False, labels: tuple[str, str] = ("Micah", "Angela"),
              mount_root: Path | None = None) -> list[Path]:
    parsed = urlparse(base_url)
    if parsed.scheme != "https" and not (parsed.scheme == "http" and parsed.hostname in ("localhost", "127.0.0.1", "::1")):
        raise ValueError("Use HTTPS except for localhost testing")
    if not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment or parsed.path not in ("", "/"):
        raise ValueError("Base URL must be an HTTPS origin without credentials, query or path")
    data_dir, media_dir, credentials_dir = (p.expanduser().resolve() for p in (data_dir, media_dir, credentials_dir))
    if mount_root is not None:
        mount_root = mount_root.expanduser().resolve()
        if not os.path.ismount(mount_root) or not media_dir.is_relative_to(mount_root):
            raise ValueError("The requested media mount is absent or does not contain the media directory")
    if (data_dir / "devices.json").exists() or (data_dir / "messages.sqlite3").exists():
        raise ValueError("Existing deployment detected; refusing to replace credentials/history")
    paths = [credentials_dir / f"device-{i}.json" for i in (1, 2)]
    if any(path.exists() for path in paths):
        raise ValueError("Existing client credentials detected; refusing to overwrite")
    marker = media_dir / ".sombrero-volume"
    if marker.exists():
        raise ValueError("Media directory is already provisioned")
    if not media_dir.is_dir() and not initialize_media:
        raise ValueError("Media directory does not exist; mount it first or explicitly initialize local storage")
    if not initialize_media:
        raise ValueError("Initial media provisioning requires --initialize-media after verifying the intended mount")
    # Only this explicit provisioning command creates media directories. The
    # running service never recreates a missing mount or its marker.
    for directory in (data_dir, media_dir, credentials_dir):
        directory.mkdir(parents=True, mode=0o700, exist_ok=True)
    pair_id = str(uuid.uuid4())
    devices = [{"id": str(uuid.uuid4()), "label": label, "token": secrets.token_urlsafe(32)} for label in labels]
    configuration = {"version": 1, "pairID": pair_id, "devices": [
        {"id": d["id"], "label": d["label"], "tokenSHA256": hashlib.sha256(d["token"].encode()).hexdigest()} for d in devices
    ]}
    if mount_root is not None:
        configuration["mediaMountRoot"] = str(mount_root)
    created = []
    try:
        fd = os.open(marker, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "w") as stream:
            stream.write(pair_id + "\n")
        created.append(marker)
        private_json(data_dir / "devices.json", configuration); created.append(data_dir / "devices.json")
        for index, device in enumerate(devices):
            private_json(paths[index], {"baseURL": base_url.rstrip("/"), "deviceID": device["id"],
                         "peerID": devices[1-index]["id"], "pairID": pair_id, "token": device["token"]})
            created.append(paths[index])
    except Exception:
        for path in created:
            path.unlink(missing_ok=True)
        raise
    return paths


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--data-dir", type=Path, required=True)
    parser.add_argument("--media-dir", type=Path, required=True)
    parser.add_argument("--credentials-dir", type=Path, required=True)
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--initialize-media", action="store_true")
    parser.add_argument("--mount-root", type=Path, help="Require this external-volume mount now and on every service request")
    parser.add_argument("--first-name", default="Micah")
    parser.add_argument("--second-name", default="Angela")
    args = parser.parse_args()
    try:
        paths = provision(args.data_dir, args.media_dir, args.credentials_dir, args.base_url,
                          args.initialize_media, (args.first_name, args.second_name), args.mount_root)
    except (ValueError, OSError) as error:
        parser.error(str(error))
    print("Provisioned two devices. Import one private credential file on each Mac:")
    for path in paths:
        print(path)
    print("Treat these files as passwords. Do not commit or send them through chat.")


if __name__ == "__main__":
    main()
