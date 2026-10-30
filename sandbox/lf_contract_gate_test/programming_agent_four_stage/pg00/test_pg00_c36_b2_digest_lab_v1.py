"""Exploratory B2 comparisons: no digest grants authority."""
import hashlib
import importlib.util
import json
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("b2", Path(__file__).with_name("pg00_c36_b2_digest_lab_v1.py"))
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class DigestLabTests(unittest.TestCase):
    def check(self, raw=b'{"a":1}', source=b'{"status":"BORRADOR"}', pg=None):
        out = mod.compare_representations(source, raw, pg_jsonb_text=pg)
        self.assertEqual(out["verdict"], "BLOCKED")
        self.assertEqual(out["authority"], "NONE")
        self.assertIn("CANONICALIZATION_POLICY_APPROVAL_REQUIRED", out["reason_codes"])
        return out

    def test_stable_bytes(self):
        raw = b'{"a":1}'
        out = self.check(raw)
        self.assertEqual(out["diagnostics"]["release_bytes_sha256"], hashlib.sha256(raw).hexdigest())

    def test_whitespace_changes_raw_digest(self):
        a = self.check(b'{"a":1}')["diagnostics"]
        b = self.check(b'{ "a": 1 }')["diagnostics"]
        self.assertNotEqual(a["release_bytes_sha256"], b["release_bytes_sha256"])
        self.assertEqual(a["python_diagnostic_sha256"], b["python_diagnostic_sha256"])

    def test_key_order_changes_raw_not_python_diagnostic(self):
        a = self.check(b'{"a":1,"b":2}')["diagnostics"]
        b = self.check(b'{"b":2,"a":1}')["diagnostics"]
        self.assertNotEqual(a["release_bytes_sha256"], b["release_bytes_sha256"])
        self.assertEqual(a["python_diagnostic_sha256"], b["python_diagnostic_sha256"])

    def test_postgres_representation_kept_distinct(self):
        out = self.check(b'{"a":1}', pg='{ "a": 1 }')["diagnostics"]
        self.assertFalse(out["raw_release_equals_pg_jsonb_text"])
        self.assertNotEqual(out["release_bytes_sha256"], out["pg_jsonb_text_sha256"])

    def test_duplicate_root_key(self):
        self.assertIn("INVALID_JSON", self.check(b'{"a":1,"a":2}')["reason_codes"])

    def test_duplicate_nested_key(self):
        self.assertIn("INVALID_JSON", self.check(b'{"x":{"a":1,"a":2}}')["reason_codes"])

    def test_nan(self):
        self.assertIn("INVALID_JSON", self.check(b'{"a":NaN}')["reason_codes"])

    def test_nonobject(self):
        self.assertIn("INVALID_JSON", self.check(b'[]')["reason_codes"])

    def test_unicode(self):
        out = self.check(json.dumps({"é": "ñ"}, ensure_ascii=False).encode())
        self.assertIn("python_diagnostic_sha256", out["diagnostics"])

    def test_invalid_bytes(self):
        out = mod.compare_representations("not-bytes", b'{}')
        self.assertIn("INVALID_INPUT_BYTES", out["reason_codes"])
        self.assertEqual(out["authority"], "NONE")

    def test_invalid_postgres_shape(self):
        self.assertIn("INVALID_PG_READBACK_SHAPE", self.check(pg=123)["reason_codes"])


if __name__ == "__main__":
    unittest.main()
