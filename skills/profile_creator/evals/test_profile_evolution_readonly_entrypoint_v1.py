"""Unit tests for CLI source-reader wiring; no real database/credentials."""
from __future__ import annotations

import os
import sys
import types
import unittest
from unittest.mock import patch
from skills.profile_creator.validators.plan_profile_evolution import (
    make_readonly_authority_binding_from_environment as bind,
)

REGISTRY_DIGEST = "a" * 64
ASSESSMENT_DIGEST = "b" * 64
MANIFEST_DIGEST = "c" * 64


class ReadOnlyBindingTests(unittest.TestCase):
    def test_no_opt_in_blocks(self):
        with patch.dict(os.environ, {}, clear=True):
            self.assertIsNone(bind())

    def test_missing_readonly_dsn_blocks(self):
        with patch.dict(os.environ, {"LF_PROFILE_READBACK_MODE": "SUPABASE_READ_ONLY"}, clear=True):
            self.assertIsNone(bind())

    def test_invalid_opt_in_blocks(self):
        with patch.dict(os.environ, {"LF_PROFILE_READBACK_MODE": "REAL",
                  "LF_PROFILE_READ_ONLY_DATABASE_URL": "mock://secret"}, clear=True):
            self.assertIsNone(bind())

    def test_verified_readback_via_readonly_queries(self):
        from skills.profile_creator.validators.profile_evolution_trusted_readback_v1 import (
            METHOD_CURRENT_SQL, PROFILE_ASSESSMENT_RECEIPT_SQL
        )
        calls = []
        class Column:
            def __init__(self, name):
                self.name = name
        class Cursor:
            def __enter__(self): return self
            def __exit__(self, *exc): pass
            def execute(self, query, params):
                calls.append((query, params))
                if query == METHOD_CURRENT_SQL:
                    self.row = {
                        "capability_code": "METHOD_PACK_REGISTRY",
                        "registry_status": "ACTIVE", "release_state": "RELEASED",
                        "version": "1.0.0", "current_version": "1.0.0",
                        "manifest_sha256": MANIFEST_DIGEST,
                        "current_manifest_sha256": MANIFEST_DIGEST,
                        "manifest": {"catalog_payload_sha256": REGISTRY_DIGEST,
                                     "qualified_method_portfolio": []}
                    }
                elif query == PROFILE_ASSESSMENT_RECEIPT_SQL:
                    self.row = {
                        "subject_type": "PROFILE_ASSESSMENT",
                        "subject_ref": "quality_pack",
                        "subject_sha256": ASSESSMENT_DIGEST,
                        "source_head_sha": "a" * 40,
                        "receipt_kind": "PROFILE_ASSESSMENT_RESULT",
                        "verification_state": "VERIFIED",
                        "provider": "GITHUB",
                        "provider_ref": "github-api://repos/owner/repo@" + "a" * 40 + "/actions/runs/1",
                        "verification_method": "GITHUB_API_READBACK_PLUS_OFFLINE_HASH",
                        "receipt_sha256": "d" * 64,
                        "verified_at": "2026-10-22T01:29:16Z",
                        "resolver_id": "LF_GITHUB_SOURCE_READBACK_V1",
                        "resolver_active": True,
                        "resolver_trust_level": "TRUSTED_PROVIDER_BOUND",
                        "receipt_id": "9f758577-c9f6-4744-852b-a03827b466f6"
                    }
                else:
                    raise AssertionError("Only two SELECTs expected with empty portfolio")
                self.description = [Column(k) for k in self.row]
            def fetchall(self): return [tuple(self.row.values())]
        class Connection:
            def __enter__(self): return self
            def __exit__(self, *exc): pass
            def cursor(self): return Cursor()
        def connect(dsn, **kwargs):
            self.assertEqual(dsn, "mock://read-only")
            self.assertIn("default_transaction_read_only=on", kwargs.get("options", ""))
            return Connection()
        mock_psycopg = types.ModuleType("psycopg")
        mock_psycopg.connect = connect
        with patch.dict(sys.modules, {"psycopg": mock_psycopg}):
            with patch.dict(os.environ, {"LF_PROFILE_READBACK_MODE": "SUPABASE_READ_ONLY",
                   "LF_PROFILE_READ_ONLY_DATABASE_URL": "mock://read-only"}, clear=True):
                reader = bind()
                self.assertIsNotNone(reader)
                result = reader("quality_pack", REGISTRY_DIGEST, ASSESSMENT_DIGEST)
                self.assertEqual(result["status"], "VERIFIED_CURRENT")
                self.assertEqual(result["qualified_method_ids"], [])
        self.assertEqual(len(calls), 2)
        self.assertTrue(all(x[0].lstrip().startswith("SELECT") for x in calls))

    def test_reader_failure_is_not_an_authorization(self):
        mock_psycopg = types.ModuleType("psycopg")
        def fail_connect(*args, **kwargs): raise RuntimeError("service unavailable")
        mock_psycopg.connect = fail_connect
        with patch.dict(sys.modules, {"psycopg": mock_psycopg}):
            with patch.dict(os.environ, {"LF_PROFILE_READBACK_MODE": "SUPABASE_READ_ONLY",
                   "LF_PROFILE_READ_ONLY_DATABASE_URL": "mock://offline"}, clear=True):
                r = bind()("quality_pack", REGISTRY_DIGEST, ASSESSMENT_DIGEST)
                self.assertEqual(r["status"], "UNRESOLVED")
                self.assertEqual(r["reason"], "TRUSTED_SOURCE_UNAVAILABLE")


if __name__ == "__main__":
    unittest.main(verbosity=2)
