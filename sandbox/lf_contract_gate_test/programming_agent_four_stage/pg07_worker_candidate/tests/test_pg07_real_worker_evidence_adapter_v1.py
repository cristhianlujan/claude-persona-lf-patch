"""Standalone adversarial unit tests. Real fixture is NOT fabricated.

The integration test on the exact real bundle must be added only after the
sandbox workflow generates its SHA-pinned JSON. No real chain PASS claimed here.
"""
from __future__ import annotations
import base64
import copy
import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
import pg07_real_worker_evidence_adapter_v1 as a


def rec(raw: bytes):
    return {"base64": base64.b64encode(raw).decode(), "bytes": len(raw),
            "sha256": hashlib.sha256(raw).hexdigest()}


def command():
    return {"argv": ["mvn", "-B", "-f", "apps/time-service/pom.xml", "verify"],
            "stdout": rec(b"BUILD SUCCESS\n"), "stderr": rec(b""),
            "result": "PASS", "exit_code": 0}


def smoke():
    statuses = [("healthcheck", 200), ("create", 201), ("search", 200),
                ("delete", 204), ("get_after_delete", 404)]
    return {"stdout": rec(b"server started"), "stderr": rec(b""),
            "steps": [{"step": name, "status": status, "body_base64": rec(b"ok")["base64"],
                       "body_sha256": a.digest(b"ok"), "body_bytes": 2}
                      for name, status in statuses]}


def sample_patch():
    path = "apps/time-service/src/main/java/lf/sandbox/time/reminder/"
    files = ["InMemoryReminderRepository.java", "ReminderController.java",
             "ReminderRepository.java"]
    fragments = []
    rows = []
    for name, count in zip(files, (2, 3, 1)):
        fragments.append("diff --git a/" + path + name + " b/" + path + name + "\n")
        for i in range(count):
            h = "@@ -" + str(i+1) + ",1 +" + str(i+1) + ",1 @@\n"
            raw = (h + "-old\n+new\n").encode()
            fragments.append(raw.decode())
            rows.append({"path": path + name, "header": h.strip(),
                         "sha256": a.digest(raw), "bytes": len(raw),
                         "content_base64": base64.b64encode(raw).decode(),
                         "requirements": ["REM-C" + str(len(rows) + 1)]})
    full = "".join(fragments).encode()
    return {"text_base64": base64.b64encode(full).decode(),
            "sha256": a.digest(full), "worker_patch_sha256": a.digest(full),
            "bytes": len(full), "hunks": rows}


class RealEvidenceNegativeTests(unittest.TestCase):
    def test_missing_fixture_or_sha_blocks(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "not-created.json"
            with self.assertRaisesRegex(a.RealEvidenceBlocked, "SHA_NOT_PINNED"):
                a.load_real_bundle(p, "")
            with self.assertRaisesRegex(a.RealEvidenceBlocked, "FIXTURE_MISSING"):
                a.load_real_bundle(p, "0" * 64)

    def test_replaced_package_sha_blocks_before_parsing(self):
        with tempfile.TemporaryDirectory() as d:
            p = Path(d) / "bundle.json"
            p.write_bytes(b'{"fake":"replacement"}')
            with self.assertRaisesRegex(a.RealEvidenceBlocked, "SHA_CHANGED"):
                a.load_real_bundle(p, "0" * 64)

    def test_injected_authority_blocks_even_when_json_rehashed(self):
        content = {"production_authority": True, "nested": [{"receipt_authenticated": False}]}
        # Rehashing the packet cannot make True authority acceptable.
        self.assertEqual(len(a.digest(json.dumps(content).encode())), 64)
        with self.assertRaisesRegex(a.RealEvidenceBlocked, "AUTHORITY_INJECTION"):
            a.check_authority(content)

    def test_command_stdout_digest_tamper_and_inverse_block(self):
        base = {"maven": command(), "smoke": smoke()}
        for kind in ("hash_only", "bytes_only", "exit_pass"):
            x = copy.deepcopy(base)
            if kind == "hash_only":
                x["maven"]["stdout"]["sha256"] = "f" * 64
            if kind == "bytes_only":
                x["maven"]["stdout"]["base64"] = base64.b64encode(b"DIFFERENT").decode()
            else:
                x["maven"]["exit_code"] = 1
            with self.subTest(kind=kind), self.assertRaises(a.RealEvidenceBlocked):
                a.check_execution({"execution": x})

    def test_cost_warning_decision_and_over_cap_block(self):
        self.assertEqual(a.cost_verdict("0.070022"), "REPORTED_WITHIN_BUDGET_UNVERIFIED")
        self.assertEqual(a.cost_verdict("0.28"), "WARN")
        self.assertEqual(a.cost_verdict("0.35"), "REQUIRES_DECISION")
        with self.assertRaisesRegex(a.RealEvidenceBlocked, "OVER_CAP"):
            a.cost_verdict("0.350001")

    def test_changed_patch_byte_blocks(self):
        obj = sample_patch()
        with patch.object(a, "PATCH_SHA", obj["sha256"]):
            original = copy.deepcopy(obj)
            altered = bytearray(base64.b64decode(original["text_base64"]))
            altered[-1] = ord("x")
            original["text_base64"] = base64.b64encode(altered).decode()
            with self.assertRaisesRegex(a.RealEvidenceBlocked, "PATCH_SHA"):
                a.check_patch({"patch": original})

    def test_hunk_without_requirement_blocks(self):
        obj = sample_patch()
        obj["hunks"][0]["requirements"] = []
        with patch.object(a, "PATCH_SHA", obj["sha256"]):
            with self.assertRaisesRegex(a.RealEvidenceBlocked, "HUNK_REQUIREMENT"):
                a.check_patch({"patch": obj})

    def test_requirement_without_hunk_blocks(self):
        obj = sample_patch()
        obj["hunks"][-1]["requirements"] = ["REM-C6"]
        with patch.object(a, "PATCH_SHA", obj["sha256"]):
            with self.assertRaisesRegex(a.RealEvidenceBlocked, "REQUIREMENT_COVERAGE"):
                a.check_patch({"patch": obj})

    def test_blob_oid_tampering_blocks(self):
        rows = [{"path": f"apps/time-service/file{i}.txt", "mode": "100644",
                 "bytes": 29347 if i == 0 else 0, "oid": "f"*40,
                 "content_base64": base64.b64encode(b"x"*29347 if i==0 else b"").decode()}
                for i in range(18)]
        with self.assertRaisesRegex(a.RealEvidenceBlocked, "BLOB_OID"):
            a.rebuild_subtree(rows)

    def test_untrusted_commit_altered_oid(self):
        original = b"tree " + a.TREE.encode() + b"\n\nmsg\n"
        self.assertNotEqual(a.oid("commit", original + b"x"), a.oid("commit", original))


if __name__ == "__main__":
    unittest.main(verbosity=2)
