import hashlib
import subprocess
from pathlib import Path

from lf_broker_currentness_bridge_v1 import bridge_decision
from lf_currentness_authority_v1 import compatibility_proof_sha256
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


def binding(a: str, b: str, completeness="COMPLETE"):
    stable = hashlib.sha256(b"stable-consumer").hexdigest()
    return {
        "schema_version": "LF_MATERIAL_CURRENTNESS_BINDING_V1",
        "authority": {"ref": "refs/heads/main", "bound_revision": a, "current_revision": b},
        "evidence_revision": a,
        "dependency_completeness": completeness,
        "require_ancestor": True,
        "materials": [
            {"material_id": "core", "kind": "GIT_TREE", "selectors": {"prefixes": ["core/"]}, "required": True, "depends_on": []},
            {"material_id": "consumer", "kind": "DIGEST", "bound_digest": stable, "current_digest": stable, "depends_on": ["core"]},
        ],
        "root_material_ids": ["consumer"],
    }


def with_breaking_core_proof(repo: Path, a: str, b: str, bind: dict) -> dict:
    spec = bind["materials"][0]
    old_fp, _ = git_tree_material(repo, a, spec["selectors"], True)
    new_fp, _ = git_tree_material(repo, b, spec["selectors"], True)
    bind["contract_identity"] = "LF_BROKER_TEST_CONTRACT_V1"
    bind["implementation_binding"] = "LF_BROKER_TEST_IMPL_V1"
    bind["compatibility_contract"] = {"assessments": [{
        "material_id": "core",
        "change_class": "BREAKING",
        "proof_sha256": compatibility_proof_sha256(
            material_id="core",
            change_class="BREAKING",
            bound_fingerprint=old_fp,
            current_fingerprint=new_fp,
            contract_identity=bind["contract_identity"],
            implementation_binding=bind["implementation_binding"],
        ),
    }]}
    return bind


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


def test_material_change_with_explicit_breaking_proof_blocks_selectively(tmp_path):
    repo, a = setup_repo(tmp_path)
    (repo / "core" / "a.txt").write_text("a2\n")
    b = commit(repo, "core change")
    bind = with_breaking_core_proof(repo, a, b, binding(a, b))
    r = bridge_decision(repo=repo, binding=bind, base_revision=a, current_revision=b)
    assert r["ready"] is False
    assert r["decision"] == "BLOCK_BROKER_STALE_AFFECTED"
    assert r["affected_root_material_ids"] == ["consumer"]


def test_material_change_without_assessment_blocks_as_unproven(tmp_path):
    repo, a = setup_repo(tmp_path)
    (repo / "core" / "a.txt").write_text("a2\n")
    b = commit(repo, "core change no assessment")
    r = bridge_decision(repo=repo, binding=binding(a, b), base_revision=a, current_revision=b)
    assert r["ready"] is False
    assert r["decision"] == "BLOCK_BROKER_CURRENTNESS_UNPROVEN"
    assert r["reason"] == "COMPATIBILITY_ASSESSMENT_MISSING"


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
