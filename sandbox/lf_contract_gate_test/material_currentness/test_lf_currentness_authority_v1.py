import json
import subprocess
from pathlib import Path

from lf_currentness_authority_v1 import compatibility_proof_sha256, evaluate_authority
from lf_material_currentness_v1 import canonical_sha256, git_tree_material
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
    return {"material_id": mid, "kind": "GIT_TREE", "selectors": {"prefixes": [prefix]}, "required": True, "depends_on": depends or [], "consumer_gates": gates or []}


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


def assessment(repo: Path, a: str, b: str, spec: dict, klass: str, *, contract_identity="LF_TEST_CONTRACT_V1"):
    old_fp, _ = git_tree_material(repo, a, spec["selectors"], bool(spec.get("required", True)))
    new_fp, _ = git_tree_material(repo, b, spec["selectors"], bool(spec.get("required", True)))
    return {"material_id": spec["material_id"], "change_class": klass, "proof_sha256": compatibility_proof_sha256(material_id=spec["material_id"], change_class=klass, bound_fingerprint=old_fp, current_fingerprint=new_fp, contract_identity=contract_identity, implementation_binding="LF_TEST_IMPL_V1")}


def test_implementation_only_compatible_does_not_invalidate_consumer(tmp_path):
    repo, a = setup_repo(tmp_path)
    (repo / "impl" / "engine.py").write_text("v2 compatible\n")
    b = commit(repo, "implementation compatible")
    contract = material("contract", "contract/")
    implementation = material("implementation", "impl/", depends=["contract"], gates=["G_IMPL"])
    r = evaluate_authority(binding(a, b, [contract, implementation], [assessment(repo, a, b, implementation, "IMPLEMENTATION_ONLY_COMPATIBLE")], roots=["implementation"]), repo)
    assert r["decision"] == "CURRENT_REBOUND" and r["ready"]
    assert r["affected_root_material_ids"] == []
    assert not r["bounded_validation_required"]
    assert r["evidence_revision"] == a


def test_compatible_contract_change_requires_bounded_validation(tmp_path):
    repo, a = setup_repo(tmp_path)
    (repo / "contract" / "api.json").write_text('{"v":2,"compatible":true}\n')
    b = commit(repo, "contract compatible")
    contract = material("contract", "contract/", gates=["G_CONTRACT"])
    consumer = material("consumer", "impl/", depends=["contract"], gates=["G_CONSUMER"])
    r = evaluate_authority(binding(a, b, [contract, consumer], [assessment(repo, a, b, contract, "CONTRACT_COMPATIBLE")], roots=["consumer"]), repo)
    assert r["decision"] == "CURRENT_REBOUND" and r["ready"]
    assert r["bounded_validation_required"]
    assert r["bounded_validation_material_ids"] == ["consumer", "contract"]
    assert r["bounded_validation_gate_ids"] == ["G_CONSUMER", "G_CONTRACT"]


def test_breaking_contract_change_is_selectively_stale(tmp_path):
    repo, a = setup_repo(tmp_path)
    (repo / "contract" / "api.json").write_text('{"v":2,"breaking":true}\n')
    b = commit(repo, "contract breaking")
    contract = material("contract", "contract/", gates=["G_CONTRACT"])
    consumer = material("consumer", "impl/", depends=["contract"], gates=["G_CONSUMER"])
    unrelated = material("unrelated", "docs/", gates=["G_DOCS"])
    r = evaluate_authority(binding(a, b, [contract, consumer, unrelated], [assessment(repo, a, b, contract, "BREAKING")], roots=["consumer", "unrelated"]), repo)
    assert r["decision"] == "STALE_AFFECTED" and not r["ready"]
    assert r["affected_root_material_ids"] == ["consumer"]
    assert r["affected_gate_ids"] == ["G_CONSUMER", "G_CONTRACT"]
    assert "unrelated" not in r["affected_material_ids"]


def test_unknown_compatibility_fails_closed(tmp_path):
    repo, a = setup_repo(tmp_path)
    (repo / "impl" / "engine.py").write_text("v2\n")
    b = commit(repo, "unknown")
    implementation = material("implementation", "impl/")
    r = evaluate_authority(binding(a, b, [implementation], [assessment(repo, a, b, implementation, "UNKNOWN")]), repo)
    assert r["decision"] == "UNKNOWN_FAIL_CLOSED" and not r["ready"]
    assert r["reason"] == "COMPATIBILITY_UNKNOWN"


def test_missing_assessment_fails_closed_instead_of_assuming_breaking(tmp_path):
    repo, a = setup_repo(tmp_path)
    (repo / "impl" / "engine.py").write_text("v2\n")
    b = commit(repo, "missing assessment")
    implementation = material("implementation", "impl/")
    r = evaluate_authority(binding(a, b, [implementation]), repo)
    assert r["decision"] == "UNKNOWN_FAIL_CLOSED" and not r["ready"]
    assert r["reason"] == "COMPATIBILITY_ASSESSMENT_MISSING"
    assert r["unknown_material_ids"] == ["implementation"]


def test_replayed_or_wrong_context_proof_fails_closed(tmp_path):
    repo, a = setup_repo(tmp_path)
    (repo / "impl" / "engine.py").write_text("v2\n")
    b = commit(repo, "context mismatch")
    implementation = material("implementation", "impl/")
    replayed = assessment(repo, a, b, implementation, "IMPLEMENTATION_ONLY_COMPATIBLE", contract_identity="OTHER_CONTRACT")
    r = evaluate_authority(binding(a, b, [implementation], [replayed]), repo)
    assert r["decision"] == "UNKNOWN_FAIL_CLOSED" and not r["ready"]
    assert r["reason"] == "COMPATIBILITY_PROOF_CONTEXT_MISMATCH:implementation"


def test_unrelated_main_change_rebind_preserves_evidence_revision(tmp_path):
    repo, a = setup_repo(tmp_path)
    (repo / "docs" / "readme.md").write_text("d2\n")
    b = commit(repo, "unrelated")
    r = evaluate_authority(binding(a, b, [material("contract", "contract/")]), repo)
    assert r["decision"] == "CURRENT_REBOUND" and r["ready"]
    assert r["evidence_revision"] == a
    assert r["bound_revision"] == a and r["current_revision"] == b


def test_source_attestation_verifies_offline_and_detects_rehashed_material_tamper(tmp_path):
    repo, a = setup_repo(tmp_path)
    bind = binding(a, a, [material("contract", "contract/")])
    receipt = create_attestation(repo=repo, repo_identity="github://example/lf", authority_ref="refs/heads/main", resolved_revision=a, binding=bind)
    ok = verify_attestation(repo=repo, receipt=receipt, expected_repo_identity="github://example/lf", expected_authority_ref="refs/heads/main", expected_binding=bind)
    assert ok["ready"] and ok["decision"] == "ATTESTATION_VERIFIED_OFFLINE"
    assert ok["authority_level"] == "CANDIDATE_LOCAL_INTEGRITY"
    assert ok["durable_evidence_anchor_required"] is True
    tampered = json.loads(json.dumps(receipt))
    tampered["material_fingerprints"]["contract"] = "0" * 64
    tampered.pop("receipt_sha256")
    tampered["receipt_sha256"] = canonical_sha256(tampered)
    blocked = verify_attestation(repo=repo, receipt=tampered, expected_repo_identity="github://example/lf", expected_authority_ref="refs/heads/main", expected_binding=bind)
    assert not blocked["ready"]
    assert blocked["decision"] == "BLOCK_ATTESTATION_MATERIAL_FINGERPRINT_MISMATCH"


def test_source_attestation_rejects_wrong_expected_authority(tmp_path):
    repo, a = setup_repo(tmp_path)
    bind = binding(a, a, [material("contract", "contract/")])
    receipt = create_attestation(repo=repo, repo_identity="github://example/lf", authority_ref="refs/heads/main", resolved_revision=a, binding=bind)
    blocked = verify_attestation(repo=repo, receipt=receipt, expected_repo_identity="github://other/repo", expected_authority_ref="refs/heads/main", expected_binding=bind)
    assert not blocked["ready"]
    assert blocked["decision"] == "BLOCK_ATTESTATION_REPO_IDENTITY_MISMATCH"
