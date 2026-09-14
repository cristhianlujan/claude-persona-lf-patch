import hashlib
import subprocess
from pathlib import Path

from lf_broker_currentness_bridge_v1 import bridge_decision
from lf_currentness_authority_v1 import ASSESSOR_SCHEMA, compatibility_proof_sha256
from lf_material_currentness_v1 import git_tree_material


def sh(repo: Path, *args: str) -> str:
    return subprocess.run(["git", "-C", str(repo), *args], check=True, text=True, capture_output=True).stdout.strip()


def commit(repo: Path, message: str) -> str:
    sh(repo, "add", ".")
    sh(repo, "commit", "-m", message)
    return sh(repo, "rev-parse", "HEAD")


def setup_repo(tmp_path: Path):
    repo = tmp_path / "repo"
    repo.mkdir()
    sh(repo, "init")
    sh(repo, "config", "user.email", "test@example.com")
    sh(repo, "config", "user.name", "LF Test")
    (repo / "core").mkdir(); (repo / "docs").mkdir()
    (repo / "core" / "a.txt").write_text("a1\n")
    (repo / "docs" / "readme.md").write_text("d1\n")
    a = commit(repo, "A")
    return repo, a


def core_assessment(repo: Path, a: str, b: str, klass: str):
    bound_fp, _ = git_tree_material(repo, a, {"prefixes": ["core/"]}, True)
    current_fp, _ = git_tree_material(repo, b, {"prefixes": ["core/"]}, True)
    payload = {
        "material_id": "core",
        "bound_fingerprint": bound_fp,
        "current_fingerprint": current_fp,
        "change_class": klass,
        "contract_identity": "S30_GIT_BROKER_TEST_V1",
        "assessor_schema": ASSESSOR_SCHEMA,
        "issuer": "LF_TEST_ASSESSOR",
    }
    return {**payload, "proof_sha256": compatibility_proof_sha256(**payload)}


def binding(a: str, b: str, completeness="COMPLETE", assessments=None):
    stable = hashlib.sha256(b"stable-consumer").hexdigest()
    return {
        "schema_version": "LF_MATERIAL_CURRENTNESS_BINDING_V1",
        "authority": {"ref": "refs/heads/main", "bound_revision": a, "current_revision": b},
        "evidence_revision": a,
        "dependency_completeness": completeness,
        "require_ancestor": True,
        "contract_identity": "S30_GIT_BROKER_TEST_V1",
        "implementation_binding": "S30_GIT_BROKER_TEST_IMPL_V1",
        "compatibility_contract": {"assessments": assessments or []},
        "materials": [
            {
                "material_id": "core",
                "kind": "GIT_TREE",
                "selectors": {"prefixes": ["core/"]},
                "required": True,
                "depends_on": [],
            },
            {
                "material_id": "consumer",
                "kind": "DIGEST",
                "bound_digest": stable,
                "current_digest": stable,
                "depends_on": ["core"],
            },
        ],
        "root_material_ids": ["consumer"],
    }


def test_same_main_keeps_legacy_base(tmp_path):
    repo, a = setup_repo(tmp_path)
    r = bridge_decision(repo=repo, binding=binding(a, a), base_revision=a, current_revision=a)
    assert r["ready"] is True
    assert r["decision"] == "BROKER_BASE_CURRENT"
    assert r["effective_base_revision"] == a


def test_unrelated_main_advance_auto_rebinds(tmp_path):
    repo, a = setup_repo(tmp_path)
    (repo / "docs" / "readme.md").write_text("d2\n")
    b = commit(repo, "docs only")
    r = bridge_decision(repo=repo, binding=binding(a, b), base_revision=a, current_revision=b)
    assert r["ready"] is True
    assert r["decision"] == "BROKER_REBIND_CURRENT"
    assert r["effective_base_revision"] == b
    assert r["material_currentness"]["decision"] == "CURRENT_REBOUND"


def test_material_change_with_breaking_assessment_blocks_selectively(tmp_path):
    repo, a = setup_repo(tmp_path)
    (repo / "core" / "a.txt").write_text("a2\n")
    b = commit(repo, "core change")
    proof = core_assessment(repo, a, b, "BREAKING")
    r = bridge_decision(repo=repo, binding=binding(a, b, assessments=[proof]), base_revision=a, current_revision=b)
    assert r["ready"] is False
    assert r["decision"] == "BLOCK_BROKER_STALE_AFFECTED"
    assert r["affected_root_material_ids"] == ["consumer"]


def test_material_change_without_assessment_blocks_unproven(tmp_path):
    repo, a = setup_repo(tmp_path)
    (repo / "core" / "a.txt").write_text("a2\n")
    b = commit(repo, "core change unproven")
    r = bridge_decision(repo=repo, binding=binding(a, b), base_revision=a, current_revision=b)
    assert r["ready"] is False
    assert r["decision"] == "BLOCK_BROKER_CURRENTNESS_UNPROVEN"
    assert r["material_currentness"]["decision"] == "UNKNOWN_FAIL_CLOSED"
    assert r["material_currentness"]["reason"] == "MISSING_ASSESSMENT:core"


def test_incomplete_dependency_proof_blocks(tmp_path):
    repo, a = setup_repo(tmp_path)
    (repo / "docs" / "readme.md").write_text("d2\n")
    b = commit(repo, "docs only")
    r = bridge_decision(repo=repo, binding=binding(a, b, completeness="UNKNOWN"), base_revision=a, current_revision=b)
    assert r["ready"] is False
    assert r["decision"] == "BLOCK_BROKER_CURRENTNESS_UNPROVEN"
    assert r["material_currentness"]["decision"] == "UNKNOWN_FAIL_CLOSED"


def test_binding_base_mismatch_blocks_before_rebind(tmp_path):
    repo, a = setup_repo(tmp_path)
    (repo / "docs" / "readme.md").write_text("d2\n")
    b = commit(repo, "docs only")
    fake = "0" * 40
    r = bridge_decision(repo=repo, binding=binding(fake, b), base_revision=a, current_revision=b)
    assert r["ready"] is False
    assert r["decision"] == "BLOCK_BROKER_BINDING_BASE_MISMATCH"
