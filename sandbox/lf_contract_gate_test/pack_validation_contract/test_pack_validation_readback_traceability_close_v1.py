#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PLAN = ROOT / "gobernanza/contratos/pack_validation_clean_workflow_v1.json"
CLOSE = ROOT / "gobernanza/contratos/pack_validation_readback_traceability_close_v1.json"
E2E = ROOT / "gobernanza/contratos/pack_validation_verify_e2e_flow_v1.json"
REBIN = ROOT / "gobernanza/contratos/ci_control_rebind_validate_packs_controls_v1.json"

STEP7_HEAD = "6dac16d0cbb278dd057c8f1f999de00d7c567d4f"
INTEGRITY_HEAD = "30dd7155c8c397b83ade393a6836c06422c9caf1"
EXPECTED_STEP8_FILES = {
    "gobernanza/contratos/pack_validation_clean_workflow_v1.json",
    "gobernanza/contratos/pack_validation_readback_traceability_close_v1.json",
    "sandbox/lf_contract_gate_test/pack_validation_contract/test_ci_control_rebind_validate_packs_controls_v1.py",
    "sandbox/lf_contract_gate_test/pack_validation_contract/test_clean_workflow_v1.py",
    "sandbox/lf_contract_gate_test/pack_validation_contract/test_pack_validation_readback_traceability_close_v1.py",
}


def git(*args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["git", "-C", str(ROOT), *args],
        text=True,
        capture_output=True,
        check=check,
    )


def assert_resolves(ref: str) -> str:
    resolved = git("rev-parse", "--verify", f"{ref}^{{commit}}", check=False)
    assert resolved.returncode == 0, f"FAIL_PACK_VALIDATION_REF:{ref}:{resolved.stderr}"
    value = resolved.stdout.strip()
    assert len(value) == 40, f"FAIL_PACK_VALIDATION_REF_SHAPE:{ref}:{value}"
    return value


def main() -> None:
    plan = json.loads(PLAN.read_text(encoding="utf-8"))
    close = json.loads(CLOSE.read_text(encoding="utf-8"))
    e2e = json.loads(E2E.read_text(encoding="utf-8"))
    rebind = json.loads(REBIN.read_text(encoding="utf-8"))

    assert plan["owner"] == close["owner"] == e2e["owner"] == rebind["owner"] == "PACK_VALIDATION"
    assert e2e["next_handoff"] == "STEP_08_READBACK_TRACEABILITY_CLOSE"
    assert rebind["next_handoff"] == "PACK_VALIDATION_VERIFY_E2E_FLOW"
    assert close["durable_name"] == "PACK_VALIDATION_READBACK_TRACEABILITY_CLOSE"

    op = plan["operational_plan"]
    assert op["progress_scope"] == "CANDIDATE_PACK_VALIDATION_IMPLEMENTATION_ONLY"
    assert op["global_progress_percent"] == 100
    assert op["next_step"] == "STEP_08_EXACT_HEAD_CI_READBACK"
    assert len(op["steps"]) == 8
    assert all(row["progress_percent"] == 100 for row in op["steps"])
    assert op["steps"][5]["head_sha"] == "177676b145efe31c91b4860216818cb907116570"
    assert op["steps"][6]["head_sha"] == STEP7_HEAD
    assert op["steps"][6]["integrity_head_sha"] == INTEGRITY_HEAD
    assert op["steps"][7]["status"] == "CLOSED_PENDING_EXACT_HEAD_CI"

    ext = plan["external_dependencies"]
    assert len(ext) == 1
    assert ext[0]["control"] == "CONTRACT_CHECK"
    assert ext[0]["counts_toward_pack_validation_progress"] is False
    assert plan["scope_invariants"]["changed_paths_mismatch_fails_closed_before_discovery"] is True
    assert plan["scope_invariants"]["foreign_owner_work_forbidden"] is True
    assert plan["scope_invariants"]["external_blocker_must_be_reported_not_repaired_here"] is True

    chain = close["candidate_chain"]
    assert [row["pr"] for row in chain] == [1157, 1158, 1159, 1162]
    assert [row["head_sha"] for row in chain] == [
        "97353894bce8bd050d5f7bff3de129c231c1d8e8",
        "177676b145efe31c91b4860216818cb907116570",
        STEP7_HEAD,
        INTEGRITY_HEAD,
    ]
    assert chain[1]["base_sha"] == chain[0]["head_sha"]
    assert chain[2]["base_sha"] == chain[1]["head_sha"]
    assert chain[3]["base_sha"] == chain[2]["head_sha"]
    for row in chain:
        assert_resolves(row["head_sha"])
    assert assert_resolves(INTEGRITY_HEAD) == INTEGRITY_HEAD
    assert assert_resolves("HEAD") != INTEGRITY_HEAD

    diff = git("diff", "--name-only", "--no-renames", INTEGRITY_HEAD, "HEAD", check=False)
    assert diff.returncode == 0, f"FAIL_STEP8_DIFF:{diff.stderr}"
    changed = {row.strip() for row in diff.stdout.splitlines() if row.strip()}
    assert changed == EXPECTED_STEP8_FILES, f"FAIL_STEP8_SCOPE:{sorted(changed)}"
    assert set(close["step_08_change_allowlist"]) == EXPECTED_STEP8_FILES
    assert not any(path.startswith(".github/workflows/") for path in changed)
    assert not any(path.startswith("scripts/") for path in changed)

    owned_ci = close["owned_ci_readback"]
    assert owned_ci["workflow"] == "Validate LF Packs"
    assert owned_ci["required_candidate_base_sha"] == INTEGRITY_HEAD
    assert owned_ci["conclusion"] == "PENDING_EXACT_HEAD_CI"
    assert owned_ci["counts_toward_pack_validation_progress"] is True

    external = close["external_ci_policy"]
    assert external["counts_toward_pack_validation_progress"] is False
    assert external["repair_here_forbidden"] is True
    assert external["failure_disposition"] == "BLOCKED_BY_EXTERNAL_OWNER"

    invariants = close["closure_invariants"]
    assert invariants["changed_paths_integrity_required"] is True
    assert invariants["candidate_closure_is_not_merge_or_main_closure"] is True
    assert invariants["merge_authorized"] is False
    assert invariants["deployment_authorized"] is False
    assert invariants["production_authorized"] is False

    print("PACK_VALIDATION_READBACK_TRACEABILITY_CLOSE=PASS")


if __name__ == "__main__":
    main()
