from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from lf_broker_request_currentness_v1 import build_broker_request


def sh(repo: Path, *args: str) -> str:
    cp = subprocess.run(["git", "-C", str(repo), *args], check=True, text=True, capture_output=True)
    return cp.stdout.strip()


def commit(repo: Path, message: str) -> str:
    sh(repo, "add", ".")
    sh(repo, "commit", "-m", message)
    return sh(repo, "rev-parse", "HEAD")


def setup_repo(tmp_path: Path) -> tuple[Path, str]:
    repo = tmp_path / "repo"
    repo.mkdir()
    sh(repo, "init")
    sh(repo, "config", "user.email", "test@example.com")
    sh(repo, "config", "user.name", "LF Test")
    (repo / "control").mkdir()
    (repo / "docs").mkdir()
    (repo / "receipts").mkdir()
    (repo / "control" / "broker.txt").write_text("v1\n", encoding="utf-8")
    (repo / "docs" / "readme.md").write_text("d1\n", encoding="utf-8")
    a = commit(repo, "A")
    return repo, a


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
        "materials": [
            {
                "material_id": "broker_control_plane",
                "kind": "GIT_TREE",
                "selectors": {"paths": ["control/broker.txt"]},
                "required": True,
                "depends_on": [],
                "consumer_gates": ["S30_GIT_BROKER_WRITE_GATE"],
            }
        ],
        "root_material_ids": ["broker_control_plane"],
    }


def write_receipt(path: Path, *, base: str, source_ref: str, target: str) -> None:
    path.write_text(
        json.dumps(
            {
                "git_write_binding": {
                    "status": "OPERATIONAL",
                    "source_branch": source_ref,
                    "target_branch": target,
                    "base_main_sha": base,
                    "secret_present": True,
                    "promotion_authority": "BROKER_ONLY",
                }
            },
            sort_keys=True,
        ),
        encoding="utf-8",
    )


def test_unrelated_main_advance_rebinds_request_without_weakening_atomic_guard(tmp_path: Path):
    repo, a = setup_repo(tmp_path)
    (repo / "docs" / "readme.md").write_text("d2\n", encoding="utf-8")
    b = commit(repo, "unrelated main")
    source_ref = "lf/staging-s30-cutover-test"
    target = "lf/s30-cutover-test"
    receipt = repo / "receipts" / "prewrite.json"
    write_receipt(receipt, base=b, source_ref=source_ref, target=target)
    (repo / "candidate.txt").write_text("candidate\n", encoding="utf-8")
    source = commit(repo, "candidate on current main")

    result = build_broker_request(
        repo=repo,
        binding=binding(a, b),
        requested_base_revision=a,
        current_revision=b,
        source_revision=source,
        source_ref=source_ref,
        target_branch=target,
        receipt_path=receipt,
    )
    assert result["ready"] is True, result
    assert result["currentness_decision"] == "BROKER_REBIND_CURRENT", result
    assert result["effective_base_revision"] == b
    assert result["request"]["base_main_sha"] == b


def test_source_must_descend_from_effective_base(tmp_path: Path):
    repo, a = setup_repo(tmp_path)
    source_ref = "lf/staging-s30-cutover-test"
    target = "lf/s30-cutover-test"
    receipt = repo / "receipts" / "prewrite.json"
    write_receipt(receipt, base=a, source_ref=source_ref, target=target)
    (repo / "candidate.txt").write_text("old-base-candidate\n", encoding="utf-8")
    source = commit(repo, "candidate on old base")
    sh(repo, "checkout", "-b", "main-advance", a)
    (repo / "docs" / "readme.md").write_text("d2\n", encoding="utf-8")
    b = commit(repo, "unrelated main")

    result = build_broker_request(
        repo=repo,
        binding=binding(a, b),
        requested_base_revision=a,
        current_revision=b,
        source_revision=source,
        source_ref=source_ref,
        target_branch=target,
        receipt_path=receipt,
    )
    assert result["ready"] is False
    assert result["decision"] == "BLOCK_BROKER_SOURCE_NOT_DESCENDANT_OF_EFFECTIVE_BASE"


def test_receipt_must_be_rehydrated_to_effective_base(tmp_path: Path):
    repo, a = setup_repo(tmp_path)
    (repo / "docs" / "readme.md").write_text("d2\n", encoding="utf-8")
    b = commit(repo, "unrelated main")
    source_ref = "lf/staging-s30-cutover-test"
    target = "lf/s30-cutover-test"
    receipt = repo / "receipts" / "prewrite.json"
    write_receipt(receipt, base=a, source_ref=source_ref, target=target)
    (repo / "candidate.txt").write_text("candidate\n", encoding="utf-8")
    source = commit(repo, "candidate on current main")

    result = build_broker_request(
        repo=repo,
        binding=binding(a, b),
        requested_base_revision=a,
        current_revision=b,
        source_revision=source,
        source_ref=source_ref,
        target_branch=target,
        receipt_path=receipt,
    )
    assert result["ready"] is False
    assert result["decision"] == "BLOCK_BROKER_RECEIPT_REHYDRATION_REQUIRED"
    assert "base_main_sha" in result["mismatched_fields"]


def test_material_change_remains_fail_closed(tmp_path: Path):
    repo, a = setup_repo(tmp_path)
    (repo / "control" / "broker.txt").write_text("v2\n", encoding="utf-8")
    b = commit(repo, "material broker change")
    source_ref = "lf/staging-s30-cutover-test"
    target = "lf/s30-cutover-test"
    receipt = repo / "receipts" / "prewrite.json"
    write_receipt(receipt, base=b, source_ref=source_ref, target=target)
    source = b

    result = build_broker_request(
        repo=repo,
        binding=binding(a, b),
        requested_base_revision=a,
        current_revision=b,
        source_revision=source,
        source_ref=source_ref,
        target_branch=target,
        receipt_path=receipt,
    )
    assert result["ready"] is False
    assert result["decision"] in {
        "BLOCK_BROKER_STALE_AFFECTED",
        "BLOCK_BROKER_BOUNDED_VALIDATION_REQUIRED",
        "BLOCK_BROKER_CURRENTNESS_UNPROVEN",
    }
