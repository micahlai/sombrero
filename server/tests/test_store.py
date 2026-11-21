import base64
import concurrent.futures
import hashlib
import json
import os
import tempfile
import unittest
import unittest
import uuid
from unittest import mock
from pathlib import Path

from sombrero_server.provision import provision
from sombrero_server.store import ServiceError, Settings, Store


PNG = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jKZkAAAAASUVORK5CYII=")


class StoreTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.data, self.media, self.credentials = [self.root / name for name in ("data", "media", "credentials")]
        paths = provision(self.data, self.media, self.credentials, "http://127.0.0.1:8765", True)
        self.clients = [json.loads(path.read_text()) for path in paths]
        configuration = json.loads((self.data / "devices.json").read_text())
        self.settings = Settings(self.data, self.media, configuration)
        self.store = Store(self.settings)
        self.first, self.second = [c["deviceID"] for c in self.clients]

    def body(self, text="hello"):
        return {"version": 1, "runs": [{"text": text, "bold": True}]}

    def message(self, text="hello", **extra):
        return {"clientRequestID": str(uuid.uuid4()), "body": self.body(text), **extra}

    def attachment(self, owner=None, upload_id=None, data=PNG, media_type="image/png"):
        upload = self.store.upload(owner or self.first, media_type, upload_id)
        try:
            # Deliberately split signatures across chunks.
            upload.write(data[:3]); upload.write(data[3:])
            return upload.finish()
        finally:
            upload.abort()

    def error(self, code, call):
        with self.assertRaises(ServiceError) as caught:
            call()
        self.assertEqual(caught.exception.status, code)

    def test_credentials_are_private_and_only_hashes_are_on_server(self):
        config = (self.data / "devices.json").read_text()
        self.assertEqual(len(self.store.devices), 2)
        for index, client in enumerate(self.clients, 1):
            self.assertNotIn(client["token"], config)
            self.assertEqual(self.store.authenticate("Bearer " + client["token"]), client["deviceID"])
            self.assertEqual((self.credentials / f"device-{index}.json").stat().st_mode & 0o777, 0o600)
        self.error(401, lambda: self.store.authenticate("Bearer third-device"))
        self.error(401, lambda: self.store.authenticate(None))
        self.assertEqual(self.store.identity(self.first)["peerID"], self.second)

    def test_reprovisioning_never_overwrites_identity_or_history(self):
        original = (self.data / "devices.json").read_bytes()
        with self.assertRaises(ValueError):
            provision(self.data, self.media, self.credentials, "https://sombrero.micahlai.com", True)
        self.assertEqual((self.data / "devices.json").read_bytes(), original)

    def test_external_volume_is_not_created_implicitly(self):
        with self.assertRaises(ValueError):
            provision(self.root / "otherdata", self.root / "not-mounted", self.root / "othercredentials", "https://sombrero.micahlai.com")
        self.assertFalse((self.root / "not-mounted").exists())

    def test_plaintext_remote_base_url_is_rejected(self):
        with self.assertRaises(ValueError):
            provision(self.root / "x", self.root / "y", self.root / "z", "http://192.168.1.3:8765", True)

    def test_duplicate_send_and_read_receipts_are_idempotent(self):
        payload = self.message()
        sent = self.store.send(self.first, payload)
        self.assertEqual(sent, self.store.send(self.first, payload))
        self.assertEqual(sent["recipientID"], self.second)
        self.assertEqual(sent["body"]["runs"][0], {"text": "hello", "bold": True, "italic": False, "underline": False})
        self.error(403, lambda: self.store.mark_read(self.first, sent["id"]))
        read = self.store.mark_read(self.second, sent["id"])
        self.assertTrue(read["readAt"].endswith("Z"))
        self.assertEqual(read, self.store.mark_read(self.second, sent["id"]))
        changes = self.store.sync(self.first, 0)["changes"]
        self.assertEqual([r["type"] for r in changes], ["message", "read"])
        self.assertIsNone(changes[0]["message"]["readAt"])

    def test_reused_request_id_cannot_change_content(self):
        payload = self.message()
        self.store.send(self.first, payload)
        payload["body"] = self.body("changed")
        self.error(409, lambda: self.store.send(self.first, payload))

    def test_two_senders_can_use_same_request_uuid(self):
        payload = self.message()
        self.assertNotEqual(self.store.send(self.first, payload)["id"], self.store.send(self.second, payload)["id"])

    def test_concurrent_retries_produce_one_message_and_change(self):
        payload = self.message()
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            results = list(pool.map(lambda _: self.store.send(self.first, payload), range(12)))
        self.assertEqual(len({r["id"] for r in results}), 1)
        self.assertEqual(len(self.store.sync(self.second, 0)["changes"]), 1)

    def test_cursor_pagination_and_restart_preserve_order(self):
        for index in range(5):
            self.store.send(self.first, self.message(str(index)))
        page = self.store.sync(self.second, 0, 2)
        self.assertTrue(page["hasMore"]); self.assertEqual(page["cursor"], 2)
        restarted = Store(self.settings)
        second = restarted.sync(self.second, page["cursor"], 2)
        last = restarted.sync(self.second, second["cursor"], 2)
        self.assertEqual([x["sequence"] for x in second["changes"]], [3, 4])
        self.assertEqual(last["cursor"], 5); self.assertFalse(last["hasMore"])
        self.error(409, lambda: self.store.sync(self.second, 6))

    def test_rich_text_rejects_unknown_fields_invalid_styles_and_limits(self):
        for body in [None, {"version": 2, "runs": []}, {"version": True, "runs": []},
                     {"version": 1, "runs": [{"text": "x", "html": "<script>"}]},
                     {"version": 1, "runs": [{"text": "x", "bold": 1}]},
                     self.body("x" * 20001), {"version": 1, "runs": [{"text": "x"}] * 1001}]:
            self.error(422, lambda: self.store.send(self.first, {"clientRequestID": str(uuid.uuid4()), "body": body}))
        self.error(422, lambda: self.store.send(self.first, self.message("  \n")))
        self.error(422, lambda: self.store.send(self.first, self.message(recipientID=str(uuid.uuid4()))))

    def test_attachment_is_owned_and_peer_cannot_fetch_until_shared(self):
        attachment = self.attachment()
        self.assertEqual(attachment["byteCount"], len(PNG))
        self.assertEqual(attachment["sha256"], hashlib.sha256(PNG).hexdigest())
        self.error(403, lambda: self.store.attachment_for_download(self.second, attachment["id"]))
        self.error(403, lambda: self.store.send(self.second, self.message(attachmentID=attachment["id"])))
        self.store.send(self.first, self.message("", attachmentID=attachment["id"]))
        metadata, path = self.store.attachment_for_download(self.second, attachment["id"])
        self.assertEqual(path.read_bytes(), PNG); self.assertEqual(metadata, attachment)
        self.error(422, lambda: self.store.attachment_for_download(self.first, "../../devices.json"))

    def test_upload_dedupe_requires_identical_bytes_and_type(self):
        upload_id = str(uuid.uuid4())
        first = self.attachment(upload_id=upload_id)
        self.assertEqual(first, self.attachment(upload_id=upload_id))
        changed = PNG + b"new"
        self.error(409, lambda: self.attachment(upload_id=upload_id, data=changed))
        self.assertEqual(len(list(self.media.glob("*.bin"))), 1)
        self.assertEqual(list(self.media.glob(".upload-*")), [])

    def test_attachment_limits_and_magic_reject_bad_or_executable_content(self):
        self.error(415, lambda: self.attachment(data=b"<html>not an image</html>"))
        self.error(415, lambda: self.attachment(media_type="image/svg+xml"))
        small = Store(Settings(self.data, self.media, self.settings.configuration, max_image_bytes=10))
        upload = small.upload(self.first, "image/png")
        try:
            self.error(413, lambda: upload.write(PNG))
        finally:
            upload.abort()
        self.assertEqual(list(self.media.glob(".upload-*")), [])

    def test_video_container_signatures_and_independent_video_limit(self):
        video = (24).to_bytes(4, "big") + b"ftypisom" + bytes(4) + b"isommp42" + b"media bytes"
        result = self.attachment(data=video, media_type="video/mp4")
        self.assertEqual(result["mediaType"], "video/mp4")
        self.error(415, lambda: self.attachment(data=video, media_type="image/heic"))

    def test_missing_or_replaced_volume_returns_retryable_error_without_recreating_it(self):
        attachment = self.attachment()
        detached = self.root / "detached"
        self.media.rename(detached)
        self.assertFalse(self.store.media_available())
        self.error(503, lambda: self.store.upload(self.first, "image/png"))
        self.error(503, lambda: self.store.attachment_for_download(self.first, attachment["id"]))
        self.assertFalse(self.media.exists())
        self.media.mkdir()
        (self.media / ".sombrero-volume").write_text("wrong volume")
        self.assertFalse(self.store.media_available())
        os.rename(self.media, self.root / "wrong-volume")
        detached.rename(self.media)
        self.assertTrue(self.store.media_available())
        self.assertEqual(self.store.attachment_for_download(self.first, attachment["id"])[1].read_bytes(), PNG)

    def test_wrong_pair_cannot_reuse_existing_database(self):
        config = dict(self.settings.configuration, pairID=str(uuid.uuid4()))
        with self.assertRaises(ValueError):
            Store(Settings(self.data, self.media, config))

    def test_production_mount_guard_rejects_absent_mount_even_with_a_marker(self):
        config = dict(self.settings.configuration, mediaMountRoot=str(self.root))
        with mock.patch("os.path.ismount", return_value=False):
            production = Store(Settings(self.data, self.media, config))
            self.assertFalse(production.media_available())
            self.error(503, lambda: production.upload(self.first, "image/png"))
            with self.assertRaises(ValueError):
                provision(self.root / "x", self.root / "y", self.root / "z", "https://sombrero.micahlai.com", True,
                          mount_root=self.root)


if __name__ == "__main__":
    unittest.main()
