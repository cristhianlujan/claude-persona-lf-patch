"""C3.6-A synthetic fixture tests. These NEVER prove authority or DB write safety."""
import hashlib
import importlib.util
import json
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("c36", Path(__file__).with_name("pg00_c36_offline_plan_v1.py"))
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
COMMIT = "a" * 40
SOURCE_DOC = {"schema_version": "LF_STANDARDS_CATALOG_V1", "catalog_version": "0.7.0",
              "status": "BORRADOR_EN_REPO_DE_CALIFICACION",
              "rules": [{"id": "x", "status": "APROBADO"}]}
SOURCE = json.dumps(SOURCE_DOC, sort_keys=True).encode()
RELEASE = json.dumps({**SOURCE_DOC, "status": "APROBADO"}, sort_keys=True).encode()


def fixture():
    proposal = {"proposal_id": "P1", "source_repo": "paulozterra/lf-programming-sandbox",
                "source_path": "standards/catalog.json", "source_commit_sha": COMMIT,
                "source_file_sha256": hashlib.sha256(SOURCE).hexdigest(),
                "release_catalog_sha256": hashlib.sha256(RELEASE).hexdigest(),
                "release_status_requested": "APROBADO",
                "source_catalog_version": "0.7.0", "chg_id": "CHG-123",
                "migration_path": "supabase/migrations/20261030143000_c3_release.sql",
                "policy_version": "POL-1"}
    fields = ("source_commit_sha", "source_file_sha256", "release_catalog_sha256",
              "chg_id", "migration_path", "policy_version")
    registry = {"P1": {field: proposal[field] for field in fields}}
    registry["P1"]["consumed"] = False
    return proposal, registry


class OfflinePlanTests(unittest.TestCase):
    def evaluate(self, edit=None, *, source=SOURCE, release=RELEASE, commit=COMMIT, registry_override=None):
        proposal, registry = fixture()
        if edit:
            edit(proposal, registry)
        if registry_override is not None:
            registry = registry_override
        out = mod.inspect_plan(proposal, source_bytes=source, release_bytes=release,
                               trusted_commit=commit, fixture_registry=registry)
        self.assertEqual(out["verdict"], "BLOCKED")
        self.assertEqual(out["authority"], "NONE")
        self.assertIn("EXTERNAL_AUTHENTICATED_AUTHORITY_REQUIRED", out["reason_codes"])
        return out["reason_codes"]

    def test_consistent_still_blocked(self):
        self.assertEqual(self.evaluate(), ["EXTERNAL_AUTHENTICATED_AUTHORITY_REQUIRED"])

    def test_forged_approval(self):
        self.assertIn("INVALID_PROPOSAL_FIELDS",
                      self.evaluate(lambda p,r: p.update(approved_by="owner")))

    def test_forged_train_receipt(self):
        self.assertIn("INVALID_PROPOSAL_FIELDS",
                      self.evaluate(lambda p,r: p.update(train_receipt={"PASS": True})))

    def test_proposal_substitution(self):
        self.assertIn("PROPOSAL_NOT_IN_FIXTURE_REGISTRY",
                      self.evaluate(lambda p,r: p.update(proposal_id="P2")))

    def test_chg_substitution(self):
        self.assertIn("FIXTURE_BINDING_MISMATCH",
                      self.evaluate(lambda p,r: p.update(chg_id="CHG-999")))

    def test_migration_path_traversal(self):
        self.assertIn("INVALID_MIGRATION_PATH",
                      self.evaluate(lambda p,r: p.update(migration_path="../../evil.sql")))

    def test_replay_fixture(self):
        self.assertIn("FIXTURE_REPLAY_OR_UNKNOWN",
                      self.evaluate(lambda p,r: r["P1"].update(consumed=True)))

    def test_digest_substitution(self):
        self.assertIn("RELEASE_DIGEST_MISMATCH",
                      self.evaluate(lambda p,r: p.update(release_catalog_sha256="b"*64)))

    def test_release_tamper(self):
        self.assertIn("RELEASE_DIGEST_MISMATCH", self.evaluate(release=RELEASE+b" "))

    def test_rule_drift(self):
        altered = json.dumps({**SOURCE_DOC, "status": "APROBADO", "rules": []},
                             sort_keys=True).encode()
        self.assertIn("RELEASE_CONTENT_DRIFT", self.evaluate(release=altered))

    def test_null_extra(self):
        altered = json.dumps({**SOURCE_DOC, "status": "APROBADO", "evil": None},
                             sort_keys=True).encode()
        self.assertIn("RELEASE_CONTENT_DRIFT", self.evaluate(release=altered))

    def test_duplicate_source_key(self):
        self.assertIn("INVALID_SOURCE_JSON", self.evaluate(source=b'{"id":1,"id":2}'))

    def test_duplicate_nested_release_key(self):
        self.assertIn("INVALID_RELEASE_JSON",
                      self.evaluate(release=b'{"rules":[{"id":1,"id":2}]}'))

    def test_unhashable_release_status_fails_closed(self):
        for invalid in ([], {}, ["APROBADO"]):
            with self.subTest(status=invalid):
                altered = json.dumps({**SOURCE_DOC, "status": invalid}, sort_keys=True).encode()
                reasons = self.evaluate(release=altered)
                self.assertIn("INVALID_RELEASE_STATUS", reasons)

    def test_invalid_proposal_shape(self):
        _, registry = fixture()
        result = mod.inspect_plan(None, source_bytes=SOURCE, release_bytes=RELEASE,
                                  trusted_commit=COMMIT, fixture_registry=registry)
        self.assertEqual(result["authority"], "NONE")
        self.assertIn("INVALID_PROPOSAL_SHAPE", result["reason_codes"])

    def test_invalid_registry(self):
        self.assertIn("INVALID_FIXTURE_REGISTRY", self.evaluate(registry_override=[]))

    def test_trusted_commit_mismatch(self):
        self.assertIn("COMMIT_MISMATCH", self.evaluate(commit="b"*40))


if __name__ == "__main__":
    unittest.main()
