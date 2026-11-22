import concurrent.futures
import json
import unittest

import test_store
from sombrero_server.enrollment import create_code, redeem_code
from sombrero_server.store import ServiceError


class EnrollmentTests(unittest.TestCase):
    def setUp(self):
        self.fixture = test_store.StoreTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.store = self.fixture.store
        self.export = {**self.fixture.clients[1], "baseURL": "https://home-lab.example.net"}

    def test_one_use_preserves_existing_identity_and_history(self):
        message = self.store.send(self.fixture.first, self.fixture.message())
        code = create_code(self.store, self.export, now=1000)
        with self.store.connect() as db:
            self.assertNotIn(code, str([dict(row) for row in db.execute("SELECT * FROM enrollments")]))
        result = redeem_code(self.store, "Bearer " + code, now=1001)
        self.assertEqual(result["token"], self.export["token"])
        self.assertEqual(result["deviceID"], self.fixture.second)
        self.assertEqual(result["pairID"], self.store.pair_id)
        self.assertEqual(len(self.store.devices), 2)
        self.assertEqual(self.store.sync(self.fixture.second, 0, 100)["changes"][0]["message"], message)
        with self.assertRaises(ServiceError):
            redeem_code(self.store, "Bearer " + code, now=1002)

    def test_expired_invalid_and_replaced_codes_fail(self):
        first = create_code(self.store, self.export, ttl=60, now=1000)
        with self.assertRaises(ServiceError):
            redeem_code(self.store, "Bearer " + first, now=1060)
        second = create_code(self.store, self.export, now=2000)
        third = create_code(self.store, self.export, now=2001)
        for header in [None, "Bearer " + self.export["token"], "Bearer " + second]:
            with self.assertRaises(ServiceError):
                redeem_code(self.store, header, now=2002)
        self.assertEqual(redeem_code(self.store, "Bearer " + third, now=2002)["deviceID"], self.fixture.second)

    def test_concurrent_redeem_has_one_winner(self):
        code = create_code(self.store, self.export)
        def redeem(_):
            try:
                redeem_code(self.store, "Bearer " + code)
                return True
            except ServiceError:
                return False
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            self.assertEqual(sum(pool.map(redeem, range(4))), 1)

    def test_wrong_pair_token_and_insecure_server_rejected(self):
        for export in [{**self.export, "token": "wrong"}, {**self.export, "pairID": self.fixture.first},
                       {**self.export, "baseURL": "http://public.example.net"}]:
            with self.assertRaises((ServiceError, ValueError)):
                create_code(self.store, export)


if __name__ == "__main__":
    unittest.main()
