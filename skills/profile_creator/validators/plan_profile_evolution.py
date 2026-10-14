#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
import sys
from pathlib import Path
from typing import Any, Callable
import hashlib

ROOT = Path(__file__).resolve().parents[3]
ASSESS_DIR = ROOT / "sandbox/lf_contract_gate_test/transversal_assets/profile_assessment"
SELECT_DIR = ROOT / "sandbox/lf_contract_gate_test/transversal_assets/capability_selector"
VALIDATOR_DIR = ROOT / "skills/profile_creator/validators"
for p in (ASSESS_DIR, SELECT_DIR, VALIDATOR_DIR):
    if str(p) not in sys.path:
        sys.path.insert(0, str(p))

from evaluate_s26_learning_preflight import evaluate_learning_preflight
from evaluate_s26_profile_baseline import evaluate as evaluate_s26
from profile_assessment_v1 import assess_profile
from profile_evolution_step_candidates_v1 import derive_step_candidates
from capability_selector_v2 import compose_capabilities


def build_evolution_plan(
    repo: Path,
    slug: str,
    preflight_payload: object,
    assessment_payload: dict[str, Any],
    capability_catalog: list[dict[str, Any]],
    capability_policy: dict[str, Any],
    method_registry: dict[str, Any],
    *,
    current_revision: str | None = None,
    trusted_source_readback: Callable[[str, str, str], dict[str, Any]] | None = None,
) -> dict[str, Any]:
    structural = evaluate_s26(repo, slug)
    learning = evaluate_learning_preflight(
        preflight_payload, slug, repo_root=repo, current_revision=current_revision,
        assessment_only=True,
    )
    preflight_pass = learning["status"] == "PASS"

    normalized = copy.deepcopy(assessment_payload)
    normalized.setdefault("evidence", {})
    if structural["decision"] == "NO_UPDATE_REQUIRED":
        normalized["evidence"]["structural_compatibility"] = {
            "status": "PASS",
            "refs": ["s26://13-of-13"],
        }
    elif structural["decision"] == "UPDATE_REQUIRED":
        normalized["evidence"]["structural_compatibility"] = {
            "status": "FAIL",
            "refs": structural.get("repair_actions", []),
        }
    else:
        normalized["evidence"]["structural_compatibility"] = {
            "status": "UNKNOWN",
            "refs": structural.get("blocking_codes", []),
        }

    assessment = assess_profile(normalized)
    composition = compose_capabilities(
        {
            **normalized.get("signals", {}),
            "profile_gaps": assessment["profile_gaps"],
            "budget": normalized.get("budget", {}),
            "precondition_evidence": normalized.get("precondition_evidence", {}),
            "method_evidence": normalized.get("method_evidence", {}),
        },
        capability_catalog,
        capability_policy,
        method_registry,
    )

    # The catalog and assessment must be verified by a trusted source reader,
    # not by flags or references inside the caller-controlled input JSON.
    # Without this binding the plan remains shadow-only.
    registry_digest = hashlib.sha256(
        json.dumps(method_registry, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    assessment_digest = hashlib.sha256(
        json.dumps(normalized, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    source_status = {"status": "UNRESOLVED", "reason": "TRUSTED_SOURCE_READBACK_MISSING"}
    if trusted_source_readback is not None:
        try:
            receipt = trusted_source_readback(slug, registry_digest, assessment_digest)
            if (isinstance(receipt, dict)
                and receipt.get("status") == "VERIFIED_CURRENT"
                and receipt.get("registry_sha256") == registry_digest
                and receipt.get("assessment_sha256") == assessment_digest
                and isinstance(receipt.get("registry_version"), str)
                and bool(receipt["registry_version"].strip())
                and isinstance(receipt.get("authority_ref"), str)
                and bool(receipt["authority_ref"].strip())
                and receipt.get("method_catalog_released") is True
                and receipt.get("assessment_evidence_verified") is True
                and isinstance(receipt.get("qualified_method_ids"), list)
                and all(isinstance(mid, str) and bool(mid.strip()) for mid in receipt["qualified_method_ids"])
                and len(set(receipt["qualified_method_ids"])) == len(receipt["qualified_method_ids"])
                and all(m["method_id"] in receipt["qualified_method_ids"]
                        for m in composition.get("method_requirements", [])
                        if m.get("eligible_for_composition") is True)) :
                source_status = {"status": "VERIFIED_CURRENT",
                                 "authority_ref": receipt["authority_ref"],
                                 "registry_version": receipt["registry_version"],
                                 "registry_sha256": registry_digest,
                                 "assessment_sha256": assessment_digest}
            else:
                source_status = {"status": "UNRESOLVED",
                                 "reason": "SOURCE_RECEIPT_INVALID_OR_STALE"}
        except Exception:
            source_status = {"status": "UNRESOLVED",
                             "reason": "SOURCE_READBACK_FAILED"}

    blockers: list[str] = []
    if not preflight_pass:
        blockers.append("BLOCKED_LEARNING_PREFLIGHT")
    if structural["decision"] == "BLOCKED_AUTHORITY_REQUIRED":
        blockers.append("BLOCKED_AUTHORITY_REQUIRED")
    if composition["fallback_state"] in {"CONTRADICTORY", "CAPABILITY_FAILURE"}:
        blockers.append("BLOCKED_SELECTOR_UNRESOLVED")

    if assessment.get("assessment_status") != "EVIDENCE_SUFFICIENT":
        blockers.append("PROFILE_ASSESSMENT_NEEDS_MORE_EVIDENCE")
    if source_status["status"] != "VERIFIED_CURRENT":
        blockers.append("METHOD_AND_ASSESSMENT_AUTHORITY_UNRESOLVED")

    mode = assessment["evolution_mode"]
    change_needed = mode is not None and mode != "NO_CHANGE"
    candidate_allowed = (
        assessment.get("assessment_status") == "EVIDENCE_SUFFICIENT"
        and change_needed
        and not blockers
    )
    patch_minimality_required = mode == "PATCH"

    plan = {
        "schema": "PROFILE_EVOLUTION_PLAN_V1",
        "operation_code": "ACTUALIZACION_PERFIL_LF",
        "conceptual_responsibility": "PROFILE_EVOLUTION_ORCHESTRATOR",
        "profile_slug": slug,
        "structural_baseline": structural,
        "structural_status": (
            "STRUCTURALLY_COMPATIBLE"
            if structural["decision"] == "NO_UPDATE_REQUIRED"
            else structural["decision"]
        ),
        "learning_preflight": learning,
        "profile_assessment": assessment,
        "evolution_mode": mode,
        "selection": composition,
        "source_readback": source_status,
        "candidate_materialization_allowed": candidate_allowed,
        "candidate_boundary": "REVERSIBLE_NON_AUTHORITY",
        "profile_source_write_allowed": False,
        "write_requires_admission": True,
        "patch_minimality_required": patch_minimality_required,
        "bounded_delta_required": change_needed,
        "blocking_codes": blockers,
        "next_gate": (
            "CANDIDATE_MATERIALIZATION"
            if candidate_allowed
            else "NO_CHANGE"
            if mode == "NO_CHANGE" and not blockers
            else "TARGETED_EVIDENCE_ACQUISITION"
            if "PROFILE_ASSESSMENT_NEEDS_MORE_EVIDENCE" in blockers
            else "RETURN_TO_EVIDENCE_OR_AUTHORITY"
        ),
        "automatic_runtime_activation": False,
        "automatic_production_activation": False,
    }
    plan["step_candidates"] = derive_step_candidates(plan)
    return plan



def make_readonly_authority_binding_from_environment():
    """Resolve trusted source evidence only from an explicitly enabled reader.

    No implicit use of write-capable database secrets, untrusted CLI JSON
    receipt, or direct authority mutation. Connection privilege is owned by
    the invoking runtime. Absence/unavailability preserves the fail-closed
    planner behavior.
    """
    import os
    if os.environ.get("LF_PROFILE_READBACK_MODE", "").strip() != "SUPABASE_READ_ONLY":
        return None
    dsn = os.environ.get("LF_PROFILE_READ_ONLY_DATABASE_URL", "").strip()
    if not dsn:
        return None
    try:
        import psycopg
        from profile_evolution_trusted_readback_v1 import (
            make_postgres_trusted_readback,
            METHOD_CURRENT_SQL,
            PROFILE_ASSESSMENT_RECEIPT_SQL,
            METHOD_QUALIFICATION_RECEIPT_SQL,
        )
    except ImportError:
        return None

    allowed_queries = frozenset({
        METHOD_CURRENT_SQL, PROFILE_ASSESSMENT_RECEIPT_SQL,
        METHOD_QUALIFICATION_RECEIPT_SQL,
    })

    def fetch_rows(query: str, params: tuple[str, ...]) -> list[dict[str, Any]]:
        if query not in allowed_queries or not isinstance(params, tuple):
            raise ValueError("READ_ONLY_AUTHORITY_QUERY_NOT_ALLOWED")
        # PostgreSQL enforces read-only mode for the entire session.
        # The DSN must have SELECT-only privileges assigned by the host.
        with psycopg.connect(
            dsn, connect_timeout=8,
            options="-c default_transaction_read_only=on",
        ) as conn:
            with conn.cursor() as cur:
                cur.execute(query, params)
                names = [column.name for column in cur.description]
                return [dict(zip(names, values)) for values in cur.fetchall()]

    return make_postgres_trusted_readback(fetch_rows)


def main() -> int:
    if len(sys.argv) != 7:
        print(
            "usage: plan_profile_evolution.py <slug> <preflight.json> <assessment.json> "
            "<capability_catalog.json> <capability_policy.json> <method_registry.json>",
            file=sys.stderr,
        )
        return 2
    slug = sys.argv[1]
    payloads = [json.loads(Path(p).read_text(encoding="utf-8")) for p in sys.argv[2:]]
    result = build_evolution_plan(
        ROOT, slug, *payloads,
        trusted_source_readback=make_readonly_authority_binding_from_environment(),
    )
    print(json.dumps(result, indent=2, sort_keys=True))
    return 0 if not result["blocking_codes"] else 3


if __name__ == "__main__":
    raise SystemExit(main())
