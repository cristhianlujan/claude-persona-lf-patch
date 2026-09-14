import hashlib
import json
import subprocess
from pathlib import Path

from lf_currentness_authority_v1 import evaluate_authority
from lf_source_attestation_v1 import create_attestation, verify_attestation


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
    (repo / "contract").mkdir(); (repo / "impl").mkdir(); (repo / "docs").mkdir()
    (repo / "contract" / "api.json").write_text('{"v":1}\n')
    (repo / "impl" / "engine.py").write_text("v1\n")
    (repo / "docs" / "readme.md").write_text("d1\n")
    a = commit(repo, "A")
    return repo, a


def material(mid: str, prefix: str, depends=None, gates=None):
    return {
        "material_id": mid,
        "kind": "GIT_TREE",
        "selectors": {"prefixes": [prefix]},
        "required": True,
        "depends_on": depends or [],
        "consumer_gates": gates or [],
    }


def assessment(mid: str, klass: str):
    proof = hashlib.sha256(f"{mid}:{klass}".encode()).hexdigest()
    return {"material_id": mid, "change_class": klass, "proof_sha256": proof}


def binding(a, b, mats, assessments=None, roots=None, completeness="COMPLETE"):
    return {
        "schema_version": "LF_MATERIAL_CURRENTNESS_BINDING_V1",
        "authority": {"ref": "refs/heads/main", "bound_revision": a, "current_revision": b},
        "evidence_revision": a,
        "dependency_completeness": completeness,
        "require_ancestor": True,
        "contract_identity": "LF_TEST_CONTRACT_V1",
        "implementation_binding": "LF_TEST_IMPL_V1",
        "compatibility_contract": {"assessments": assessments or []},
        "materials": mats,
        "root_material_ids": roots or [m["material_id"] for m in mats],
    }


def test_implementation_only_compatible_does_not_invalidate_consumer(tmp_path):
    repo, a = setup_repo(tmp_path)
    (repo / "impl" / "engine.py").write_text("v2 compatible\n")
    b = commit(repo, "implementation compatible")
    mats = [material("contract", "contract/"), material("implementation", "impl/", depends=["contract"], gates=["G_IMPL"])]
    r = evaluate_authority(binding(a, b, mats, [assessment("implementation", "IMPLEMENTATION_ONLY_COMPATIBLE")], roots=["implementation"]), repo)
    assert r["decision"] == "CURRENT_REBOUND" and r["ready"]
    assert r["affected_root_material_ids"] == []
    assert not r["bounded_validation_required"]
    assert r["evidence_revision"] == a


def test_compatible_contract_change_requires_bounded_validation(tmp_path):
    repo, a = setup_repo(tmp_path)
    (repo / "contract" / "api.json").write_text('{"v":2,"compatible":true}\n')
    b = commit(repo, "contract compatible")
    mats = [material("contract", "contract/", gates=["G_CONTRACT"]), material("consumer", "impl/", depends=["contract"], gates=["G_CONSUMER"])]
    r = evaluate_authority(binding(a, b, mats, [assessment("contract", "CONTRACT_COMPATIBLE")], roots=["consumer"]), repo)
    assert r["decision"] == "CURRENT_REBOUND" and r["ready"]
    assert r["bounded_validation_required"]
    assert r["bounded_validation_material_ids"] == ["consumer", "contract"]
    assert r["bounded_validation_gate_ids"] == ["G_CONSUMER", "G_CONTRACT"]


def test_breaking_contract_change_is_selectively_stale(tmp_path):
    repo, a = setup_repo(tmp_path)
    (repo / "contract" / "api.json").write_text('{"v":2,"breaking":true}\n')
    b = commit(repo, "contract breaking")
    mats = [material("contract", "contract/", gates=["G_CONTRACT"]), material("consumer", "impl/", depends=["contract"], gates=["G_CONSUMER"]), material("unrelated", "docs/", gates=["G_DOCS"])]
    r = evaluate_authority(binding(a, b, mats, [assessment("contract", "BREAKING")], roots=["consumer", "unrelated"]), repo)
    assert r["decision"] == "STALE_AFFECTED" and not r["ready"]
    assert r["affected_root_material_ids"] == ["consumer"]
    assert r["affected_gate_ids"] == ["G_CONSUMER", "G_CONTRACT"]
    assert "unrelated" not in r["affected_material_ids"]


def test_unknown_compatibility_fails_closed(tmp_path):
    repo, a = setup_repo(tmp_path)
    (repo / "impl" / "engine.py").write_text("v2\n")
    b = commit(repo, "unknown")
    mats = [material("implementation", "impl/")]
    r = evaluate_authority(binding(a, b, mats, [assessment("implementation", "UNKNOWN")]), repo)
    assert r["decision"] == "UNKNOWN_FAIL_CLOSED" and not r["ready"]
    assert r["reason"] == "COMPATIBILITY_UNKNOWN"


def test_unrelated_main_change_rebind_preserves_evidence_revision(tmp_path):
    repo, a = setup_repo(tmp_path)
    (repo / "docs" / "readme.md").write_text("d2\n")
    b = commit(repo, "unrelated")
    mats = [material("contract", "contract/")]
    r = evaluate_authority(binding(a, b, mats), repo)
    assert r["decision"] == "CURRENT_REBOUND" and r["ready"]
    assert r["evidence_revision"] == a
    assert r["bound_revision"] == a and r["current_revision"] == b


def test_source_attestation_verifies_offline_and_detects_tamper(tmp_path):
    repo, a = setup_repo(tmp_path)
    mats = [material("contract", "contract/")]
    bind = binding(a, a, mats)
    receipt = create_attestation(repo=repo, repo_identity="github://example/lf", authority_ref="refs/heads/main", resolved_revision=a, binding=bind)
    ok = verify_attestation(repo=repo, receipt=receipt)
    assert ok["ready"] and ok["decision"] == "ATTESTATION_VERIFIED_OFFLINE"
    tampered = json.loads(json.dumps(receipt))
    tampered["tree_sha"] = "0" * 40
    blocked = verify_attestation(repo=repo, receipt=tampered)
    assert not blocked["ready"] and blocked["decision"] == "BLOCK_ATTESTATION_TAMPERED"
