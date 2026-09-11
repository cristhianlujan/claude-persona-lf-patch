#!/usr/bin/env python3
from __future__ import annotations

import json
import re
from copy import deepcopy
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
CONTRACT_PATH = Path(__file__).with_name("direct_authority_adapter_candidate_v1.json")
RECORDER_PATH = ROOT / "supabase/migrations/20260903220855_lf_profile_operation_common_recorder_server_trust_v2.sql"
SHA40 = re.compile(r"^[0-9a-f]{40}$")
SHA256 = re.compile(r"^[0-9a-f]{64}$")
DIRECT = "GITHUB_ACTIONS_EXACT_SHA_POSTGRES_POOLER_V1"
EDGE = "run-creacion-perfil-lf"
WORKFLOW = ".github/workflows/s26-profile-governance-direct-db.yml"


def validate_candidate(source: str, ctx: dict, evidence: dict, execution: dict) -> tuple[bool, str]:
    if source == EDGE:
        required = {
            "resolver": "GITHUB_PUBLIC_API_EXACT_REF_V1",
            "repository": execution["target_repo"],
            "ref": "main",
            "target_path": execution["target_path"],
        }
        if any(ctx.get(k) != v for k, v in required.items()):
            return False, "EDGE_CONTEXT_IDENTITY_INVALID"
    elif source == DIRECT:
        required = {
            "resolver": "GITHUB_PUBLIC_API_EXACT_REF_V1",
            "repository": execution["target_repo"],
            "ref": "main",
            "target_path": execution["target_path"],
            "authority_mode": "S30_STYLE_MAIN_CONTROL_PLANE",
            "authority_transport": "POSTGRES_POOLER_DIRECT",
            "authority_workflow_path": WORKFLOW,
            "authority_control_plane_ref": "refs/heads/main",
        }
        if any(ctx.get(k) != v for k, v in required.items()):
            return False, "DIRECT_CONTROL_PLANE_IDENTITY_INVALID"
        if ctx.get("authority_workflow_sha") != ctx.get("revision_sha"):
            return False, "DIRECT_WORKFLOW_SHA_NOT_CURRENT"
        if not SHA256.fullmatch(str(ctx.get("authority_receipt_sha256", ""))):
            return False, "DIRECT_RECEIPT_HASH_INVALID"
    else:
        return False, "UNKNOWN_AUTHORITY_SOURCE"

    for key in ("revision_sha", "target_blob_sha", "baseline_revision"):
        if not SHA40.fullmatch(str(ctx.get(key, ""))):
            return False, f"{key.upper()}_INVALID"
    if ctx.get("bound_revision") != evidence.get("bound_revision"):
        return False, "BOUND_REVISION_EVIDENCE_MISMATCH"
    if ctx.get("bound_revision") != ctx.get("revision_sha"):
        return False, "BOUND_REVISION_NOT_CURRENT"
    if ctx.get("continuity_state") not in {"CURRENT_BOUND", "STALE_REBOUND_CURRENT"}:
        return False, "CONTINUITY_STATE_INVALID"
    return True, "PASS"


def main() -> int:
    contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    recorder = RECORDER_PATH.read_text(encoding="utf-8")

    assert contract["status"] == "SOURCE_ONLY_NOT_APPLIED"
    assert contract["activation"]["recorder_change_applied"] is False
    assert contract["activation"]["supabase_migration_applied"] is False
    assert contract["activation"]["main_control_plane_materialized"] is False
    assert contract["activation"]["step_60_recorded"] is False
    assert "p_evidence_payload->>'server_trust_context_source'<>'run-creacion-perfil-lf'" in recorder
    assert DIRECT not in recorder, "candidate authority must not already be live in canonical recorder source"

    A = "a" * 40
    B = "b" * 40
    blob = "c" * 40
    receipt = "d" * 64
    execution = {
        "target_repo": "cristhianlujan/claude-persona-lf-patch",
        "target_path": "profiles/ui_architect/SKILL.md",
    }
    base_ctx = {
        "resolver": "GITHUB_PUBLIC_API_EXACT_REF_V1",
        "repository": execution["target_repo"],
        "ref": "main",
        "target_path": execution["target_path"],
        "revision_sha": B,
        "target_blob_sha": blob,
        "baseline_revision": A,
        "bound_revision": B,
        "continuity_state": "STALE_REBOUND_CURRENT",
        "authority_mode": "S30_STYLE_MAIN_CONTROL_PLANE",
        "authority_transport": "POSTGRES_POOLER_DIRECT",
        "authority_workflow_path": WORKFLOW,
        "authority_control_plane_ref": "refs/heads/main",
        "authority_workflow_sha": B,
        "authority_receipt_sha256": receipt,
    }
    evidence = {"bound_revision": B}

    cases: list[tuple[str, str, dict, dict, dict, bool, str]] = []
    cases.append(("POS_DIRECT_EXACT", DIRECT, base_ctx, evidence, execution, True, "PASS"))
    edge_ctx = {k: v for k, v in base_ctx.items() if not k.startswith("authority_")}
    cases.append(("POS_EDGE_PRESERVED", EDGE, edge_ctx, evidence, execution, True, "PASS"))

    def mutated(name: str, key: str, value: object, expected: str) -> None:
        c = deepcopy(base_ctx); c[key] = value
        cases.append((name, DIRECT, c, evidence, execution, False, expected))

    cases.append(("NEG_UNKNOWN_SOURCE", "FAKE_AUTHORITY", base_ctx, evidence, execution, False, "UNKNOWN_AUTHORITY_SOURCE"))
    mutated("NEG_NON_MAIN_REF", "authority_control_plane_ref", "refs/heads/feature", "DIRECT_CONTROL_PLANE_IDENTITY_INVALID")
    mutated("NEG_WRONG_WORKFLOW", "authority_workflow_path", ".github/workflows/other.yml", "DIRECT_CONTROL_PLANE_IDENTITY_INVALID")
    mutated("NEG_STALE_WORKFLOW_SHA", "authority_workflow_sha", A, "DIRECT_WORKFLOW_SHA_NOT_CURRENT")
    mutated("NEG_MISSING_RECEIPT", "authority_receipt_sha256", "", "DIRECT_RECEIPT_HASH_INVALID")
    mutated("NEG_WRONG_REPOSITORY", "repository", "other/repo", "DIRECT_CONTROL_PLANE_IDENTITY_INVALID")
    mutated("NEG_WRONG_TARGET_PATH", "target_path", "profiles/other/SKILL.md", "DIRECT_CONTROL_PLANE_IDENTITY_INVALID")
    mutated("NEG_BAD_TARGET_BLOB", "target_blob_sha", "bad", "TARGET_BLOB_SHA_INVALID")
    mutated("NEG_BAD_BASELINE", "baseline_revision", "bad", "BASELINE_REVISION_INVALID")
    mutated("NEG_BOUND_NOT_CURRENT", "bound_revision", A, "BOUND_REVISION_EVIDENCE_MISMATCH")
    c = deepcopy(base_ctx); c["bound_revision"] = A
    e = {"bound_revision": A}
    cases.append(("NEG_EVIDENCE_AND_CONTEXT_STALE", DIRECT, c, e, execution, False, "BOUND_REVISION_NOT_CURRENT"))
    mutated("NEG_BAD_CONTINUITY", "continuity_state", "CALLER_DECLARED", "CONTINUITY_STATE_INVALID")

    failures: list[str] = []
    for name, source, ctx, ev, ex, expected_ok, expected_code in cases:
        ok, code = validate_candidate(source, ctx, ev, ex)
        if (ok, code) != (expected_ok, expected_code):
            failures.append(f"{name}: expected={(expected_ok, expected_code)} observed={(ok, code)}")
    if failures:
        raise SystemExit("FAIL_S26_DIRECT_AUTHORITY_CANDIDATE=" + ";".join(failures))

    print(f"PASS_S26_DIRECT_AUTHORITY_CANDIDATE={len(cases)}/{len(cases)}")
    print("LIVE_RECORDER_UNCHANGED=true")
    print("SUPABASE_MIGRATION_APPLIED=false")
    print("STEP_60_RECORDED=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
