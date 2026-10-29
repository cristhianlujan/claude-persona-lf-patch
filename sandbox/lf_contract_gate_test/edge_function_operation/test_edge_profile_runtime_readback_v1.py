"""Tests for the fixed-allowlist profile runtime Edge readback."""
import io
import json
import unittest
from urllib.error import HTTPError

from edge_profile_runtime_readback_v1 import (
    ALLOWED_TARGETS, ReadbackBlocked, function_url, read_existing_function, verify_function_metadata,
)

SLUG = "run-creacion-perfil-lf"


def meta(**over):
    base = {"slug": SLUG, "status": "ACTIVE", "version": 36, "verify_jwt": True}
    base.update(over)
    return base


class FakeResponse:
    status = 200

    def __init__(self, data):
        self._data = data

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def read(self, limit):
        return json.dumps(self._data).encode("utf-8")


class ReadbackTests(unittest.TestCase):
    def test_allowlist_is_exactly_the_profile_runtime_with_jwt_required(self):
        self.assertEqual(ALLOWED_TARGETS, {SLUG: True})

    def test_valid_metadata(self):
        result = verify_function_metadata(meta(), SLUG, 36)
        self.assertEqual(result["result"], "EDGE_MANAGEMENT_READ_PASS")
        self.assertTrue(result["jwt_mode_preserved"])

    def test_other_slug_is_rejected_before_any_request(self):
        for other in ("lf-profiles-governance-caller-v1", "audit-skill-protocols", ""):
            with self.assertRaises(ReadbackBlocked):
                function_url(other)
            with self.assertRaises(ReadbackBlocked):
                read_existing_function("token", other, opener=lambda *a, **k: self.fail("request issued"))

    def test_jwt_drift_is_blocked(self):
        with self.assertRaises(ReadbackBlocked) as ctx:
            verify_function_metadata(meta(verify_jwt=False), SLUG)
        self.assertEqual(str(ctx.exception), "EDGE_MANAGEMENT_JWT_MODE_DRIFT")

    def test_version_must_reach_minimum(self):
        with self.assertRaises(ReadbackBlocked):
            verify_function_metadata(meta(version=35), SLUG, 36)

    def test_inactive_wrong_slug_and_bool_version_blocked(self):
        for bad in (meta(status="REMOVED"), meta(slug="other"), meta(version=True)):
            with self.assertRaises(ReadbackBlocked):
                verify_function_metadata(bad, SLUG)

    def test_performs_exact_get_with_bearer_only(self):
        seen = []

        def opener(request, timeout):
            seen.append((request.get_method(), request.full_url, request.get_header("Authorization")))
            return FakeResponse(meta())

        read_existing_function("secret-token", SLUG, 36, opener=opener)
        self.assertEqual(seen, [("GET", function_url(SLUG), "Bearer secret-token")])

    def test_http_errors_are_sanitized(self):
        def opener(request, timeout):
            raise HTTPError(request.full_url, 403, "denied", {}, io.BytesIO(b"secret-token"))

        with self.assertRaises(ReadbackBlocked) as ctx:
            read_existing_function("secret-token", SLUG, opener=opener)
        self.assertNotIn("secret-token", str(ctx.exception))

    def test_missing_token_blocked(self):
        with self.assertRaises(ReadbackBlocked):
            read_existing_function("", SLUG)


if __name__ == "__main__":
    unittest.main()
