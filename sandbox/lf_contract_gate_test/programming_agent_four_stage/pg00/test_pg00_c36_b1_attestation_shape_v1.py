"""Synthetic B1 schema tests. No authenticated provider or DB."""
import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "b1", Path(__file__).with_name("pg00_c36_b1_attestation_shape_v1.py"))
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


def fixture():
    manifest = dict(schema_version="LF_C3_RELEASE_PROPOSAL_V1",
                    proposal_id="P1", source_repo="paulozterra/lf-programming-sandbox",
                    source_path="standards/catalog.json", source_commit_sha="a"*40,
                    source_file_sha256="b"*64, release_catalog_sha256="c"*64,
                    release_status_requested="APROBADO", catalog_version="0.7.0",
                    chg_id="CHG-1",
                    migration_path="supabase/migrations/20261030143000_c3_release.sql",
                    policy_version="POL-1")
    def review(actor):
        return dict(provider="github", review_id="RV-" + actor,
                    reviewer_id=actor, reviewed_head_sha="a"*40, state="APPROVED")
    attestation = dict(schema_version="LF_C3_RELEASE_ATTESTATION_V1",
                       proposal="P1", source="github", owner_decision=review("owner"),
                       independent_review=review("reviewer"))
    return manifest, attestation


class B1SchemaTests(unittest.TestCase):
    def check(self, edit=None):
        m, a = fixture()
        if edit:
            edit(m, a)
        result = mod.validate_shape(m, a)
        self.assertEqual(result["verdict"], "BLOCKED")
        self.assertEqual(result["authority"], "NONE")
        self.assertIn("AUTHENTICATED_AUTHORITY_NOT_VERIFIED", result["reason_codes"])
        return result["reason_codes"]

    def test_valid_shape_never_authorizes(self):
        self.assertEqual(self.check(), ["AUTHENTICATED_AUTHORITY_NOT_VERIFIED"])

    def test_forged_authority_field(self):
        self.assertIn("ATTESTATION_FIELDS_MISMATCH",
                      self.check(lambda m,a: a.update(go_write=True)))

    def test_extra_null_manifest(self):
        self.assertIn("MANIFEST_FIELDS_MISMATCH",
                      self.check(lambda m,a: m.update(approved_by=None)))

    def test_wrong_source(self):
        self.assertIn("SOURCE_LOCATOR_MISMATCH",
                      self.check(lambda m,a: m.update(source_repo="attacker/repo")))

    def test_migration_traversal(self):
        self.assertIn("INVALID_MIGRATION_PATH",
                      self.check(lambda m,a: m.update(migration_path="../evil.sql")))

    def test_invalid_hash(self):
        self.assertIn("INVALID_RELEASE_CATALOG_SHA256",
                      self.check(lambda m,a: m.update(release_catalog_sha256="fake")))

    def test_reviewer_same_as_owner(self):
        self.assertIn("REVIEWER_SEPARATION_VIOLATED",
                      self.check(lambda m,a: a["independent_review"].update(reviewer_id="owner")))

    def test_approval_in_other_head_is_only_structural(self):
        self.assertEqual(self.check(lambda m,a: a["independent_review"].update(
            reviewed_head_sha="f"*40)), ["AUTHENTICATED_AUTHORITY_NOT_VERIFIED"])

    def test_bad_attestation_proposal(self):
        self.assertIn("ATTESTATION_PROPOSAL_MISMATCH",
                      self.check(lambda m,a: a.update(proposal="other")))

    def test_fake_review_state(self):
        self.assertIn("INVALID_OWNER_DECISION_STATE",
                      self.check(lambda m,a: a["owner_decision"].update(state="COMMENTED")))

    def test_invalid_review_identity(self):
        self.assertIn("INVALID_INDEPENDENT_REVIEW_IDENTITY",
                      self.check(lambda m,a: a["independent_review"].update(reviewer_id=[])))

    def test_unhashable_release_status(self):
        self.assertIn("INVALID_RELEASE_STATUS",
                      self.check(lambda m,a: m.update(release_status_requested=[])))

    def test_nonobject_manifest(self):
        result = mod.validate_shape(None)
        self.assertEqual(result["authority"], "NONE")
        self.assertIn("INVALID_MANIFEST_SHAPE", result["reason_codes"])

    def test_nonobject_attestation(self):
        m,_ = fixture()
        result = mod.validate_shape(m, [])
        self.assertIn("INVALID_ATTESTATION_SHAPE", result["reason_codes"])
        self.assertEqual(result["authority"], "NONE")


if __name__ == "__main__":
    unittest.main()
