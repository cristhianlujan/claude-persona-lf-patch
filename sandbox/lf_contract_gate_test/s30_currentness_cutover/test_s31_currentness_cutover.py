from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
S31 = ROOT / "sandbox" / "lf_contract_gate_test" / "s31_currentness_cutover"
sys.path.insert(0, str(S31))

from lf_broker_request_currentness_v1 import build_broker_request


def sh(repo: Path, *args: str) -> str:
    cp = subprocess.run(["git", "-C", str(repo), *args], check=True, text=True, capture_output=True)
    return cp.stdout.strip()


def commit(repo: Path, message: str) -> str:
    sh(repo, "add", ".")
    sh(repo, "commit", "-m", message)
    return sh(repo, "rev-parse", "HEAD")


def setup_repo(root: Path) -> tuple[Path, str]:
    repo = root / "repo"
    repo.mkdir()
    sh(repo, "init")
    sh(repo, "config", "user.email", "test@example.com")
    sh(repo, "config", "user.name", "LF Test")
    (repo / "control").mkdir(); (repo / "docs").mkdir(); (repo / "receipts").mkdir()
    (repo / "control" / "broker.txt").write_text("v1\n", encoding="utf-8")
    (repo / "docs" / "readme.md").write_text("d1\n", encoding="utf-8")
    return repo, commit(repo, "A")


def binding(a: str, b: str) -> dict:
    return {
        "schema_version": "LF_MATERIAL_CURRENTNESS_BINDING_V1",
        "authority": {"ref": "refs/heads/main", "bound_revision": a, "current_revision": b},
        "evidence_revision": a,
        "dependency_completeness": "COMPLETE",
        "require_ancestor": True,
        "contract_identity": "S30_GIT_BROKER_CONTROL_PLANE_V1",
        "implementation_binding": "CURRENT_MAIN_IMPLEMENTATION",
        "compatibility_contract": {"assessments": []},
        "materials": [{
            "material_id": "broker_control_plane",
            "kind": "GIT_TREE",
            "selectors": {"paths": ["control/broker.txt"]},
            "required": True,
            "depends_on": [],
            "consumer_gates": ["S30_GIT_BROKER_WRITE_GATE"],
        }],
        "root_material_ids": ["broker_control_plane"],
    }


def write_receipt(path: Path, base: str, source_ref: str, target: str) -> None:
    path.write_text(json.dumps({"git_write_binding": {
        "status": "OPERATIONAL",
        "source_branch": source_ref,
        "target_branch": target,
        "base_main_sha": base,
        "secret_present": True,
        "promotion_authority": "BROKER_ONLY",
    }}, sort_keys=True), encoding="utf-8")


class CurrentnessCutoverTests(unittest.TestCase):
    source_ref = "lf/staging-s30-cutover-test"
    target = "lf/s30-cutover-test"

    def test_unrelated_main_advance_rebinds_request(self):
        with tempfile.TemporaryDirectory() as td:
            repo, a = setup_repo(Path(td))
            (repo / "docs" / "readme.md").write_text("d2\n", encoding="utf-8")
            b = commit(repo, "unrelated main")
            receipt = repo / "receipts" / "prewrite.json"
            write_receipt(receipt, b, self.source_ref, self.target)
            (repo / "candidate.txt").write_text("candidate\n", encoding="utf-8")
            source = commit(repo, "candidate")
            r = build_broker_request(repo=repo,binding=binding(a,b),requested_base_revision=a,current_revision=b,source_revision=source,source_ref=self.source_ref,target_branch=self.target,receipt_path=receipt)
            self.assertTrue(r["ready"], r)
            self.assertEqual(r["currentness_decision"], "BROKER_REBIND_CURRENT")
            self.assertEqual(r["request"]["base_main_sha"], b)

    def test_source_not_descendant_of_effective_base_blocks(self):
        with tempfile.TemporaryDirectory() as td:
            repo, a = setup_repo(Path(td))
            receipt = repo / "receipts" / "prewrite.json"
            write_receipt(receipt, a, self.source_ref, self.target)
            (repo / "candidate.txt").write_text("old\n", encoding="utf-8")
            source = commit(repo, "old candidate")
            sh(repo, "checkout", "-b", "main-advance", a)
            (repo / "docs" / "readme.md").write_text("d2\n", encoding="utf-8")
            b = commit(repo, "unrelated main")
            r = build_broker_request(repo=repo,binding=binding(a,b),requested_base_revision=a,current_revision=b,source_revision=source,source_ref=self.source_ref,target_branch=self.target,receipt_path=receipt)
            self.assertFalse(r["ready"])
            self.assertEqual(r["decision"], "BLOCK_BROKER_SOURCE_NOT_DESCENDANT_OF_EFFECTIVE_BASE")

    def test_stale_receipt_base_blocks(self):
        with tempfile.TemporaryDirectory() as td:
            repo, a = setup_repo(Path(td))
            (repo / "docs" / "readme.md").write_text("d2\n", encoding="utf-8")
            b = commit(repo, "unrelated main")
            receipt = repo / "receipts" / "prewrite.json"
            write_receipt(receipt, a, self.source_ref, self.target)
            (repo / "candidate.txt").write_text("candidate\n", encoding="utf-8")
            source = commit(repo, "candidate")
            r = build_broker_request(repo=repo,binding=binding(a,b),requested_base_revision=a,current_revision=b,source_revision=source,source_ref=self.source_ref,target_branch=self.target,receipt_path=receipt)
            self.assertFalse(r["ready"])
            self.assertEqual(r["decision"], "BLOCK_BROKER_RECEIPT_REHYDRATION_REQUIRED")

    def test_material_change_remains_fail_closed(self):
        with tempfile.TemporaryDirectory() as td:
            repo, a = setup_repo(Path(td))
            (repo / "control" / "broker.txt").write_text("v2\n", encoding="utf-8")
            b = commit(repo, "material broker change")
            receipt = repo / "receipts" / "prewrite.json"
            write_receipt(receipt, b, self.source_ref, self.target)
            r = build_broker_request(repo=repo,binding=binding(a,b),requested_base_revision=a,current_revision=b,source_revision=b,source_ref=self.source_ref,target_branch=self.target,receipt_path=receipt)
            self.assertFalse(r["ready"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
