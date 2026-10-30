"""Isolated synthetic negatives: no DB, GitHub auth or release authority."""
import hashlib
import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("c3_attest", Path(__file__).with_name("pg00_c3_attestation_consistency_v1.py"))
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
SOURCE = b'{"catalog_version":"0.7.0"}'
COMMIT = "a" * 40

def proposal():
    return dict(proposal_id="p1", source_repo=mod.REPO, source_path=mod.PATH,
                source_commit_sha=COMMIT, source_file_sha256=hashlib.sha256(SOURCE).hexdigest(),
                release_catalog_sha256="b"*64, release_status_requested="APROBADO",
                source_catalog_version="0.7.0", chg_id="CHG-1",
                migration_path="supabase/migrations/example.sql", policy_version="v1")

class AttestationConsistencyTests(unittest.TestCase):
    def evaluate(self, p, commit=COMMIT, raw=SOURCE):
        out = mod.inspect_attestation(p, trusted_source_commit=commit, trusted_source_bytes=raw)
        self.assertEqual(out["verdict"], "BLOCKED")
        self.assertEqual(out["authority"], "NONE")
        self.assertIn("EXTERNAL_AUTHENTICATED_AUTHORITY_REQUIRED", out["reason_codes"])
        return out["reason_codes"]

    def test_valid_consistency_is_not_authority(self):
        self.assertEqual(self.evaluate(proposal()), ["EXTERNAL_AUTHENTICATED_AUTHORITY_REQUIRED"])

    def test_forged_approval_field_is_rejected(self):
        p = proposal(); p["approved_by"] = "owner"
        self.assertIn("INVALID_PROPOSAL_FIELDS", self.evaluate(p))

    def test_forged_train_receipt_is_rejected(self):
        p = proposal(); p["train_receipt"] = {"PASS": True}
        self.assertIn("INVALID_PROPOSAL_FIELDS", self.evaluate(p))

    def test_commit_mismatch(self):
        self.assertIn("SOURCE_COMMIT_MISMATCH", self.evaluate(proposal(), commit="c"*40))

    def test_source_tamper(self):
        self.assertIn("SOURCE_DIGEST_MISMATCH", self.evaluate(proposal(), raw=SOURCE+b" "))

    def test_missing_reference(self):
        p = proposal(); p["proposal_id"] = None
        self.assertIn("INVALID_REQUIRED_REFERENCE", self.evaluate(p))

    def test_source_locator(self):
        p = proposal(); p["source_repo"] = "attacker/evil"
        self.assertIn("INVALID_SOURCE_LOCATOR", self.evaluate(p))

    def test_bad_status(self):
        p = proposal(); p["release_status_requested"] = "BORRADOR"
        self.assertIn("INVALID_RELEASE_STATUS", self.evaluate(p))

    def test_invalid_digest(self):
        p = proposal(); p["release_catalog_sha256"] = "invalid"
        self.assertIn("INVALID_DIGEST_FORMAT", self.evaluate(p))

    def test_missing_required_key(self):
        p = proposal(); del p["proposal_id"]
        self.assertIn("INVALID_PROPOSAL_FIELDS", self.evaluate(p))

    def test_extra_null_key(self):
        p = proposal(); p["authority"] = None
        self.assertIn("INVALID_PROPOSAL_FIELDS", self.evaluate(p))

    def test_invalid_trusted_commit_format(self):
        self.assertIn("INVALID_TRUSTED_COMMIT", self.evaluate(proposal(), commit="not-a-sha"))

    def test_trusted_source_not_bytes(self):
        self.assertIn("INVALID_TRUSTED_BYTES", self.evaluate(proposal(), raw=None))

    def test_wrong_source_digest_even_if_well_formed(self):
        p = proposal(); p["source_file_sha256"] = "c" * 64
        self.assertIn("SOURCE_DIGEST_MISMATCH", self.evaluate(p))

    def test_blank_policy_reference(self):
        p = proposal(); p["policy_version"] = " "
        self.assertIn("INVALID_REQUIRED_REFERENCE", self.evaluate(p))

    def test_non_object(self):
        out = mod.inspect_attestation(None, trusted_source_commit=COMMIT, trusted_source_bytes=SOURCE)
        self.assertEqual(out["authority"], "NONE")
        self.assertIn("INVALID_PROPOSAL_SHAPE", out["reason_codes"])

if __name__ == "__main__":
    unittest.main()
