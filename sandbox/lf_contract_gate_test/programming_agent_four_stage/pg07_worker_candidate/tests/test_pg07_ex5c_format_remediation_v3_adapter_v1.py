"""V3 fail-closed negatives; no fabricated v3 fixture or fake PG14 PASS."""
from __future__ import annotations
import base64
import copy
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import pg07_ex5c_format_remediation_v3_adapter_v1 as v3


def class_record(path, raw):
    return {"path": path, "bytes": len(raw), "sha256": v3.sha(raw),
            "content_base64": base64.b64encode(raw).decode()}


class EX5CV3FailClosedTests(unittest.TestCase):
    def test_v3_missing_bundle_and_sha_block(self):
        with tempfile.TemporaryDirectory() as td:
            missing = Path(td) / "v3.json"
            with self.assertRaisesRegex(v3.EX5CV3Blocked, "SHA_NOT_PINNED"):
                v3.load_v3(missing, "")
            with self.assertRaisesRegex(v3.EX5CV3Blocked, "FIXTURE_NOT_FOUND"):
                v3.load_v3(missing, "0" * 64)

    def test_v3_swapped_json_cannot_reuse_fixed_sha(self):
        with tempfile.TemporaryDirectory() as td:
            p = Path(td) / "v3.json"
            p.write_text('{"fake":"substituted"}\n')
            with self.assertRaisesRegex(v3.EX5CV3Blocked, "BUNDLE_BYTE_TAMPER"):
                v3.load_v3(p, "0" * 64)

    def test_byte_identical_class_records_are_required(self):
        raw = b"\xca\xfe\xba\xbe"
        ce = {"baseline_class_objects": [class_record("pkg/A.class", raw)],
              "candidate_class_objects": [class_record("pkg/A.class", raw)],
              "baseline": {"pkg/A.class": v3.sha(raw)},
              "candidate": {"pkg/A.class": v3.sha(raw)},
              "class_count": 1, "identical": True,
              "javac_flags": ["--release", "21", "-g:none"]}
        self.assertEqual(v3.class_objects(ce), {"pkg/A.class": v3.sha(raw)})
        altered = copy.deepcopy(ce)
        altered["candidate_class_objects"][0]["content_base64"] = base64.b64encode(raw + b"X").decode()
        with self.assertRaisesRegex(v3.EX5CV3Blocked, "CLASS_BYTE_SHA_BLOCK"):
            v3.class_objects(altered)
        changed = copy.deepcopy(ce)
        changed["candidate_class_objects"][0] = class_record("pkg/A.class", raw + b"X")
        with self.assertRaisesRegex(v3.EX5CV3Blocked, "CLASS_EQUIVALENCE_BLOCK"):
            v3.class_objects(changed)

    def test_commit_raw_byte_tamper_changes_oid(self):
        raw = b"tree 922f74a8ffaab9b8233625c804b8c92a17d8b8a3\n\nOriginal\n"
        self.assertNotEqual(v3.oid("commit", raw), v3.oid("commit", raw + b"."))
        self.assertNotEqual(v3.oid("blob", b"source"), v3.oid("blob", b"Source"))

    def test_authority_injection_blocks_even_when_record_rehashed(self):
        injected = {"evidence_kind": "REAL_SANDBOX_UNAUTHENTICATED",
                    "git": {"files": []},
                    "production_authority": False,
                    "new": {"receipt_authenticated": True}}
        self.assertEqual(len(v3.sha(json.dumps(injected).encode())), 64)
        with self.assertRaisesRegex(v3.EX5CV3Blocked, "AUTHORITY_INJECTION_BLOCK"):
            v3.flags_false(injected)


if __name__ == "__main__":
    unittest.main()
