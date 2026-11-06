"""Offline negatives for v2 gate. No fake v2 fixture, no fabricated PASS.

Once sandbox's *real* v2 artifact exists, pin its external SHA in a separate
integration fixture/test and feed the returned observations to the original
PG06 C4 and PG08 C2 producers. Until then, missing v2 -> BLOCK.
"""
from __future__ import annotations
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/"tools"))
from pg08_ex5c_v2_format_lint_adapter_v1 import (
    V2EvidenceBlocked,load_v2,stable_violation,
    V1_SHA,GJF_SHA,BASE,HEAD
)


class EX5CV2OfflineGateTests(unittest.TestCase):
    def test_missing_v2_bundle_blocks_without_synthetic_substitution(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/"lf-evidence-bundle-v2.json"
            with self.assertRaisesRegex(V2EvidenceBlocked,"FIXTURE_SHA_OR_PATH_NOT_PINNED_BLOCK"):
                load_v2(p,"0"*64)

    def test_unpinned_v2_bundle_always_blocks(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/"v2.json"
            p.write_text('{"source":"synthetic"}')
            with self.assertRaisesRegex(V2EvidenceBlocked,"FIXTURE_SHA_OR_PATH_NOT_PINNED_BLOCK"):
                load_v2(p,"")

    def test_replacement_rehashed_against_wrong_pin_blocks(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/"v2.json"
            p.write_bytes(b'{"schema_version":"FAKE"}')
            with self.assertRaisesRegex(V2EvidenceBlocked,"FIXTURE_SHA_CHANGED_BLOCK"):
                load_v2(p,"f"*64)

    def test_rehashed_authority_injection_is_blocked_at_v2(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/"v2.json"
            doc={"schema_version":"LF_EX5C_REAL_EVIDENCE_BUNDLE_V2",
                 "evidence_kind":"REAL_SANDBOX_UNAUTHENTICATED",
                 "base_commit":BASE,"candidate_commit":HEAD,
                 "v1_bundle_sha256":V1_SHA,
                 "diff_sha256":"bfba0329bcac92dbde06a1319a16acd535acd718f224df6121dae3c70fe307c6",
                 "formatter_version":"1.30.0",
                 "formatter_sha256":GJF_SHA,
                 "production_authority":True,
                 "tool_execution_verified":False,
                 "receipt_authenticated":False,
                 "worker_invoked":False,
                 "snapshots":[]}
            raw=(json.dumps(doc)+"\n").encode()
            p.write_bytes(raw)
            with self.assertRaisesRegex(V2EvidenceBlocked,"AUTHORITY_BLOCK"):
                load_v2(p,hashlib.sha256(raw).hexdigest())

    def test_violation_id_is_stable_across_base_candidate(self):
        x=stable_violation("GOOGLE_JAVA_FORMAT","apps/time-service/src/main/java/A.java",10,"z")
        self.assertEqual(x,stable_violation("GOOGLE_JAVA_FORMAT",
                                           "apps/time-service/src/main/java/A.java",10,"z"))
        self.assertNotEqual(x,stable_violation("GOOGLE_JAVA_FORMAT",
                                              "apps/time-service/src/main/java/A.java",11,"z"))

if __name__=="__main__":
    unittest.main()
