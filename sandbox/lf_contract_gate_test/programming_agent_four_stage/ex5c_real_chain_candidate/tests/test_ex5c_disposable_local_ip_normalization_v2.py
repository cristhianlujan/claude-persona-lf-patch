"""Offline regression: PG12/PG14 use PostgreSQL host(inet_server_addr()).

No local database, no Supabase, and no side effects: mocked psql returns
normalized text, then each runner must reach its *next* source validation.
A raw address with /32 is rejected. Never claims a PostgreSQL readback PASS.
"""
import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
for directory in ("pg12_identity_candidate", "pg14_testing_handoff_candidate"):
    sys.path.insert(0, str(ROOT / directory / "tools"))

import pg12_disposable_postgres_readback_v2 as pg12
import pg14_disposable_testing_readback_v2 as pg14


class LocalPostgresAddressNormalizationV2(unittest.TestCase):
    def test_pg12_loopback_and_socket_are_normalized_and_accepted(self):
        for host in ("127.0.0.1", "::1", "LOCAL_SOCKET"):
            with self.subTest(host=host), patch.dict(
                os.environ, {
                    "PG12_TEST_DSN": "pg12_test_probe",
                    "PG12_DISPOSABLE_DB": "YES",
                }, clear=True
            ), patch.object(pg12, "psql", return_value="pg12_test_probe|" + host) as fake:
                with self.assertRaisesRegex(
                    RuntimeError, r"^PG12_V2_SOURCE_SCHEMA_OR_AUTHORITY_INVALID$"
                ):
                    pg12.persist_readback({})
                query = fake.call_args.args[1]
                self.assertIn("host(inet_server_addr())", query)
                self.assertNotIn("inet_server_addr()::text", query)

    def test_pg14_loopback_and_socket_are_normalized_and_accepted(self):
        for host in ("127.0.0.1", "::1", "LOCAL_SOCKET"):
            with self.subTest(host=host), patch.dict(
                os.environ, {
                    "PG14_TEST_DSN": "pg14_test_probe",
                    "PG14_DISPOSABLE_DB": "YES",
                }, clear=True
            ), patch.object(pg14, "psql", return_value="pg14_test_probe|" + host) as fake:
                with self.assertRaisesRegex(
                    RuntimeError, r"^PG14_V2_LOCAL_RESPONSE_NOT_ADMISSIBLE_ACCEPT$"
                ):
                    pg14.persist_readback({}, {})
                query = fake.call_args.args[1]
                self.assertIn("host(inet_server_addr())", query)
                self.assertNotIn("inet_server_addr()::text", query)

    def test_unstripped_cidr_text_is_still_rejected(self):
        for module, env, function, diagnostic in (
            (pg12, {
                "PG12_TEST_DSN": "pg12_test_probe",
                "PG12_DISPOSABLE_DB": "YES",
            }, lambda: pg12.persist_readback({}),
                "PG12_V2_NOT_LOCAL_DISPOSABLE_DATABASE"),
            (pg14, {
                "PG14_TEST_DSN": "pg14_test_probe",
                "PG14_DISPOSABLE_DB": "YES",
            }, lambda: pg14.persist_readback({}, {}),
                "PG14_NOT_LOCAL_DISPOSABLE_POSTGRES"),
        ):
            with self.subTest(module=module.__name__), patch.dict(
                os.environ, env, clear=True
            ), patch.object(
                module, "psql",
                return_value=env[next(k for k in env if k.endswith("_DSN"))] + "|127.0.0.1/32"
            ):
                with self.assertRaisesRegex(RuntimeError, "^" + diagnostic + "$"):
                    function()


if __name__ == "__main__":
    unittest.main()
