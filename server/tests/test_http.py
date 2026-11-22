"""Actual HTTP contract tests; skipped only when web dependencies are unavailable."""
import importlib.util
import unittest
import uuid

import test_store

HAS_WEB = importlib.util.find_spec("fastapi") is not None and importlib.util.find_spec("httpx") is not None


@unittest.skipUnless(HAS_WEB, "Install server/requirements-test.txt to run HTTP tests")
class HTTPTests(unittest.TestCase):
    def setUp(self):
        from fastapi.testclient import TestClient
        from sombrero_server.app import create_app
        self.fixture = test_store.StoreTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.api = TestClient(create_app(self.fixture.settings))
        self.addCleanup(self.api.close)
        self.first = {"Authorization": "Bearer " + self.fixture.clients[0]["token"]}
        self.second = {"Authorization": "Bearer " + self.fixture.clients[1]["token"]}

    def test_real_send_upload_sync_download_read_roundtrip(self):
        self.assertEqual(self.api.get("/v1/health").status_code, 200)
        self.assertEqual(self.api.get("/v1/me").status_code, 401)
        self.assertEqual(self.api.get("/v1/me", headers=self.first).json()["peerID"], self.fixture.second)
        headers = {**self.first, "Content-Type": "image/png", "X-Client-Upload-ID": str(uuid.uuid4())}
        uploaded = self.api.post("/v1/attachments", content=test_store.PNG, headers=headers)
        self.assertEqual(uploaded.status_code, 200)
        attachment = uploaded.json()
        self.assertEqual(self.api.post("/v1/attachments", content=test_store.PNG, headers=headers).json(), attachment)
        self.assertEqual(self.api.get("/v1/attachments/" + attachment["id"], headers=self.second).status_code, 403)
        payload = self.fixture.message("A photo 🦆", attachmentID=attachment["id"])
        sent = self.api.post("/v1/messages", json=payload, headers=self.first)
        self.assertEqual(sent.status_code, 200)
        message = sent.json()
        self.assertEqual(self.api.post("/v1/messages", json=payload, headers=self.first).json(), message)
        page = self.api.get("/v1/sync?cursor=0", headers=self.second).json()
        self.assertEqual(page["changes"][0]["message"], message)
        downloaded = self.api.get("/v1/attachments/" + attachment["id"], headers=self.second)
        self.assertEqual(downloaded.content, test_store.PNG)
        self.assertEqual(downloaded.headers["x-content-type-options"], "nosniff")
        read = self.api.put("/v1/messages/" + message["id"] + "/read", headers=self.second)
        self.assertEqual(read.status_code, 200)
        self.assertIsNotNone(read.json()["readAt"])
        changes = self.api.get("/v1/sync?cursor=" + str(page["cursor"]), headers=self.first).json()
        self.assertEqual(changes["changes"][0]["type"], "read")

    def test_wrong_credentials_and_invalid_payloads_never_create_data(self):
        self.assertEqual(self.api.get("/v1/me", headers={"Authorization": "Bearer third-device"}).status_code, 401)
        self.assertEqual(self.api.post("/v1/messages", json={**self.fixture.message(), "senderID": self.fixture.second}, headers=self.first).status_code, 422)
        self.assertEqual(self.api.post("/v1/attachments", content=b"html", headers={**self.first, "Content-Type": "image/png"}).status_code, 415)
        self.assertEqual(self.api.get("/v1/sync", headers=self.first).json()["changes"], [])

    def test_setup_code_is_one_use_and_response_is_not_cached(self):
        from sombrero_server.enrollment import create_code
        code = create_code(self.fixture.store, {**self.fixture.clients[1], "baseURL":"https://example.net"})
        headers = {"Authorization":"Bearer " + code}
        response = self.api.post("/v1/enrollments/redeem", headers=headers)
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.headers["cache-control"], "no-store")
        self.assertEqual(response.json()["token"], self.fixture.clients[1]["token"])
        self.assertEqual(self.api.post("/v1/enrollments/redeem", headers=headers).status_code, 401)

    def test_missing_volume_is_503_and_does_not_lose_text_messages(self):
        marker = self.fixture.media / ".sombrero-volume"
        marker.unlink()
        self.assertEqual(self.api.get("/v1/health").status_code, 503)
        response = self.api.post("/v1/attachments", content=test_store.PNG, headers={**self.first, "Content-Type": "image/png"})
        self.assertEqual(response.status_code, 503)
        self.assertEqual(response.headers["retry-after"], "10")
        self.assertEqual(self.api.post("/v1/messages", json=self.fixture.message(), headers=self.first).status_code, 200)
        self.assertFalse(marker.exists())

    def test_oversized_json_and_attachment_are_bounded(self):
        response = self.api.post("/v1/messages", content=b"x" * (256 * 1024 + 1), headers={**self.first, "Content-Type": "application/json"})
        self.assertEqual(response.status_code, 413)
        response = self.api.post("/v1/attachments", content=test_store.PNG, headers={**self.first, "Content-Type": "image/png", "Content-Length": "999999999"})
        self.assertEqual(response.status_code, 413)


if __name__ == "__main__":
    unittest.main()
