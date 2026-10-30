"""Fixture-only simulations; no DB transactions or authority."""
import importlib.util
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "b3", Path(__file__).with_name("pg00_c36_b3_replay_fixture_v1.py"))
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

def candidate(version="0.8.0", digest="b"*64, proposal_id="P-2"):
    return {"proposal_id": proposal_id, "catalog_version": version,
            "release_catalog_sha256": digest}

def registry():
    return {"consumed_proposal_ids": ["P-1"],
            "published_releases": [{"catalog_version": "0.7.0",
                                    "release_catalog_sha256": "a"*64}]}

class ReplayTests(unittest.TestCase):
    def check(self, p, f):
        r = mod.check_candidate(p, ledger_fixture=f)
        self.assertEqual(r["verdict"], "BLOCKED")
        self.assertEqual(r["authority"], "NONE")
        self.assertIn("AUTHENTICATED_LEDGER_AND_TRAIN_REQUIRED", r["reason_codes"])
        return r["reason_codes"]

    def test_fresh_still_not_authorized(self):
        self.assertEqual(self.check(candidate(), registry()),
                         ["AUTHENTICATED_LEDGER_AND_TRAIN_REQUIRED"])

    def test_replay_proposal(self):
        self.assertIn("PROPOSAL_ALREADY_CONSUMED",
                      self.check(candidate(proposal_id="P-1"), registry()))

    def test_duplicate_version(self):
        self.assertIn("CATALOG_VERSION_ALREADY_USED",
                      self.check(candidate(version="0.7.0"), registry()))

    def test_downgrade(self):
        self.assertIn("CATALOG_VERSION_NOT_MONOTONIC",
                      self.check(candidate(version="0.6.9"), registry()))

    def test_digest_reuse(self):
        self.assertIn("RELEASE_DIGEST_ALREADY_USED",
                      self.check(candidate(digest="a"*64), registry()))

    def test_invalid_semver(self):
        self.assertIn("INVALID_CATALOG_VERSION",
                      self.check(candidate(version="0.8"), registry()))

    def test_nonobject_fixture(self):
        self.assertIn("INVALID_FIXTURE_SHAPE",
                      self.check(candidate(), []))

    def test_malformed_release_fixture(self):
        f = registry()
        f["published_releases"] = [None]
        self.assertIn("INVALID_RELEASE_FIXTURE", self.check(candidate(), f))

    def test_invalid_published_version(self):
        f = registry()
        f["published_releases"][0]["catalog_version"] = "bad"
        self.assertIn("INVALID_PUBLISHED_VERSION_FIXTURE", self.check(candidate(), f))

    def test_huge_candidate_semver_fails_closed(self):
        self.assertIn("INVALID_CATALOG_VERSION",
                      self.check(candidate(version="9"*5000+".0.0"), registry()))

    def test_huge_ledger_semver_fails_closed(self):
        f = registry()
        f["published_releases"][0]["catalog_version"] = "9"*5000+".0.0"
        self.assertIn("INVALID_PUBLISHED_VERSION_FIXTURE",
                      self.check(candidate(), f))

    def test_missing_proposal_id(self):
        self.assertIn("INVALID_PROPOSAL_ID",
                      self.check(candidate(proposal_id=None), registry()))

if __name__ == "__main__":
    unittest.main()
