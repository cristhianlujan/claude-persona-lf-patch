"""Synthetic offline C3 preflight negatives. No PostgreSQL or Supabase required."""
import hashlib
import importlib.util
import json
import unittest
from pathlib import Path

MODULE = Path(__file__).with_name("pg00_c3_release_preflight_v1.py")
spec = importlib.util.spec_from_file_location("pg00_c3_preflight", MODULE)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

COMMIT = "a" * 40


def fixture():
    source = {"schema_version": "LF_STANDARDS_CATALOG_V1",
              "catalog_version": "0.7.0",
              "status": "BORRADOR_EN_REPO_DE_CALIFICACION",
              "rules": [{"id": "STD-GEN-01", "status": "APROBADO"}],
              "domains": [{"id": "STD-GEN"}], "decisions": [],
              "waiver_settings": {"approvers": ["paulozterra"]}}
    raw = (json.dumps(source, sort_keys=True) + "\n").encode()
    release = {**source, "status": "APROBADO"}
    candidate = {"source_repo": mod.SOURCE_REPO, "source_path": mod.SOURCE_PATH,
                 "source_commit_sha": COMMIT, "source_file_sha256": hashlib.sha256(raw).hexdigest(),
                 "catalog_version": source["catalog_version"], "release_catalog": release}
    return candidate, raw


class PreflightTests(unittest.TestCase):
    def run_check(self, edit=lambda c: None, source_edit=lambda b: b):
        c, raw = fixture()
        edit(c)
        return mod.inspect(c, source_edit(raw), expected_commit=COMMIT)

    def test_even_valid_candidate_never_grants_authority(self):
        result = self.run_check()
        self.assertEqual(result["verdict"], "BLOCKED")
        self.assertEqual(result["authority"], "NONE")
        self.assertEqual(result["reason_codes"],
                         ["AUTHENTICATED_APPROVAL_AND_TRAIN_RECEIPT_REQUIRED"])

    def test_source_digest_tamper(self):
        self.assertIn("SOURCE_BYTES_DIGEST_MISMATCH",
                      self.run_check(source_edit=lambda b: b + b" ")["reason_codes"])

    def test_source_commit_mismatch(self):
        self.assertIn("SOURCE_COMMIT_MISMATCH",
                      self.run_check(lambda c: c.update(source_commit_sha="b"*40))["reason_codes"])

    def test_forbid_rules_removed_from_release(self):
        self.assertIn("RELEASE_RULES_CHANGED",
                      self.run_check(lambda c: c["release_catalog"].update(rules=[]))["reason_codes"])

    def test_forbid_unapproved_release(self):
        self.assertIn("RELEASE_STATUS_NOT_APPROVED",
                      self.run_check(lambda c: c["release_catalog"].update(status="BORRADOR"))["reason_codes"])

    def test_forbid_extra_release_field(self):
        self.assertIn("UNAUTHORIZED_RELEASE_TRANSFORMATION",
                      self.run_check(lambda c: c["release_catalog"].update(fake_authority=True))["reason_codes"])

    def test_forbid_policy_drift(self):
        self.assertIn("RELEASE_CONTENT_DRIFT",
                      self.run_check(lambda c: c["release_catalog"].update(waiver_settings={}))["reason_codes"])

    def test_missing_source_origin(self):
        self.assertIn("SOURCE_REPO_MISMATCH",
                      self.run_check(lambda c: c.update(source_repo="evil/repo"))["reason_codes"])

    def test_non_object_candidate_fails_closed(self):
        _, raw = fixture()
        for value in (None, [], "string", 23):
            with self.subTest(candidate=value):
                result = mod.inspect(value, raw, expected_commit=COMMIT)
                self.assertEqual(result["verdict"], "BLOCKED")
                self.assertIn("INVALID_CANDIDATE_SHAPE", result["reason_codes"])

    def test_forged_approval_and_train_receipts_grant_no_authority(self):
        c, raw = fixture()
        c["approved_by"] = "owner"
        c["independent_review"] = {"decision": "APPROVE", "head_sha": COMMIT}
        c["train_receipt"] = {"result": "SUCCESS", "execution_id": "EXEC-FAKE"}
        result = mod.inspect(c, raw, expected_commit=COMMIT)
        self.assertEqual(result["verdict"], "BLOCKED")
        self.assertEqual(result["authority"], "NONE")
        self.assertIn("AUTHENTICATED_APPROVAL_AND_TRAIN_RECEIPT_REQUIRED",
                      result["reason_codes"])

    def test_catalog_version_forgery(self):
        self.assertIn("CATALOG_VERSION_MISMATCH",
                      self.run_check(lambda c: c.update(catalog_version="0.8.0"))["reason_codes"])

    def test_source_non_object_fails_closed(self):
        c, _ = fixture()
        for raw in (b"null", b"[]", b"42", b'"hello"'):
            with self.subTest(raw=raw):
                result = mod.inspect(c, raw, expected_commit=COMMIT)
                self.assertEqual(result["verdict"], "BLOCKED")
                self.assertIn("INVALID_SOURCE_JSON", result["reason_codes"])

    def test_release_rule_status_changed_even_with_matching_id(self):
        def tamper(c):
            c["release_catalog"]["rules"] = [{"id": "STD-GEN-01", "status": "VALIDAR_CON_LEGAL"}]
        result = self.run_check(tamper)
        self.assertIn("RELEASE_RULES_CHANGED", result["reason_codes"])

    def test_invalid_json(self):
        self.assertIn("INVALID_SOURCE_JSON",
                      self.run_check(source_edit=lambda b: b"invalid json")["reason_codes"])

    def test_unapproved_source_rule(self):
        c, raw = fixture()
        obj = json.loads(raw)
        obj["rules"][0]["status"] = "BORRADOR"
        altered = (json.dumps(obj, sort_keys=True)+"\n").encode()
        c["source_file_sha256"] = hashlib.sha256(altered).hexdigest()
        c["release_catalog"]["rules"] = obj["rules"]
        result = mod.inspect(c, altered, expected_commit=COMMIT)
        self.assertIn("SOURCE_RULE_STATUS_NOT_RELEASE_READY", result["reason_codes"])


if __name__ == "__main__":
    unittest.main()
