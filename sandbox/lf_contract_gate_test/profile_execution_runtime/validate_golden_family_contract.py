#!/usr/bin/env python3
"""Validate the LF Profiles Golden Family contract without claiming runtime proof."""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]
CONTRACT = Path(__file__).with_name("golden_family_ui_architect_v1.json")


class ContractError(RuntimeError):
    pass


def fail(code: str) -> None:
    raise ContractError(code)


def require_file(rel: str, root: Path = ROOT) -> Path:
    path = root / rel
    if not path.is_file():
        fail(f"GOLDEN_FAMILY_REQUIRED_FILE_MISSING:{rel}")
    return path


def require_receipt_fields(section_name: str, section: dict[str, Any], required: set[str]) -> None:
    observed = set(section.get("required_receipt_fields", []))
    missing = sorted(required - observed)
    if missing:
        fail(f"GOLDEN_FAMILY_{section_name}_RECEIPT_FIELDS_MISSING:" + ",".join(missing))


def validate_contract(data: dict[str, Any], root: Path = ROOT) -> str:
    if data.get("schema") != "LF_PROFILE_GOLDEN_FAMILY_CONTRACT_V1":
        fail("GOLDEN_FAMILY_SCHEMA_INVALID")
    if data.get("family_id") != "GOLDEN-FAMILY-UI-ARCHITECT-MARKETPLACE-LF-V1":
        fail("GOLDEN_FAMILY_ID_INVALID")

    allowed_statuses = {"CONTRACT_DEFINED_E2E_NOT_PROVEN", "E2E_BLOCKED", "E2E_PROVEN"}
    if data.get("status") not in allowed_statuses:
        fail("GOLDEN_FAMILY_STATUS_INVALID")

    authority = data.get("authority", {})
    if authority.get("router_asset") != "ACT-0001":
        fail("GOLDEN_FAMILY_ROUTER_AUTHORITY_INVALID")
    if authority.get("operational_source") != "public.v_lf_fuente_operativa":
        fail("GOLDEN_FAMILY_OPERATIONAL_SOURCE_INVALID")
    if authority.get("creator_asset") != "ACT-0045":
        fail("GOLDEN_FAMILY_CREATOR_AUTHORITY_INVALID")

    profile = data.get("profile", {})
    if profile.get("code") != "PERFIL-UI-ARCHITECT":
        fail("GOLDEN_FAMILY_PROFILE_CODE_INVALID")
    require_file(f"{profile.get('path')}/SKILL.md", root)
    if profile.get("runtime_enablement_must_be_live_verified_before_canary") is not True:
        fail("GOLDEN_FAMILY_PROFILE_RUNTIME_ENABLEMENT_GATE_MISSING")

    input_gov = data.get("input_governance", {})
    require_file(input_gov.get("binding_ref", ""), root)
    if input_gov.get("contract_code") != "INPUT_READINESS_CONTRACT":
        fail("GOLDEN_FAMILY_INPUT_GOVERNANCE_CONTRACT_INVALID")
    if input_gov.get("consumer") != "CONTEXT_PACK":
        fail("GOLDEN_FAMILY_INPUT_GOVERNANCE_CONSUMER_INVALID")
    require_receipt_fields(
        "INPUT_GOVERNANCE",
        input_gov,
        {
            "run_id",
            "governance_agent_used",
            "governance_version",
            "consumer",
            "sections_consumed",
            "source_refs",
            "snapshot_hash",
            "contract_snapshot_sha256",
            "currentness",
            "decision",
            "gap_or_na",
            "timestamp",
        },
    )

    card = data.get("card", {})
    require_file(f"{card.get('path')}/CARD.md", root)
    require_file(f"{card.get('path')}/validators/validate_pack.py", root)
    if card.get("expected_registry") is not None:
        fail("GOLDEN_FAMILY_CARD_RUNTIME_REGISTRY_MUST_NOT_BE_INFERRED")
    if card.get("registry_status") != "NO_COMPATIBLE_RUNTIME_REGISTRY_OBSERVED":
        fail("GOLDEN_FAMILY_CARD_REGISTRY_STATUS_INVALID")
    if card.get("runtime_materialization_required") is not True:
        fail("GOLDEN_FAMILY_CARD_RUNTIME_MATERIALIZATION_GATE_MISSING")
    require_receipt_fields(
        "CARD",
        card,
        {"request_id", "card_ref", "card_version_or_hash", "sections_consumed", "budget", "decision"},
    )
    if card.get("runtime_binding_observed_at_research_cut") is False and data.get("status") != "E2E_BLOCKED":
        fail("GOLDEN_FAMILY_CARD_BINDING_GAP_MUST_BLOCK_E2E")

    adapter = data.get("adapter", {})
    require_file(f"{adapter.get('path')}/ADAPTER.md", root)
    require_file(f"{adapter.get('path')}/manifest.yaml", root)
    if adapter.get("binding_authority") != "public.v_lf_router_adapter_bindings":
        fail("GOLDEN_FAMILY_ADAPTER_BINDING_AUTHORITY_INVALID")
    require_receipt_fields(
        "ADAPTER",
        adapter,
        {"adapter_code", "adapter_version", "activation_source", "binding_ref", "target_asset_code", "decision"},
    )

    runtime = data.get("runtime", {})
    if runtime.get("primary_target") != "HETZNER":
        fail("GOLDEN_FAMILY_PRIMARY_RUNTIME_NOT_HETZNER")
    if runtime.get("backup_target") != "GITHUB_ACTIONS":
        fail("GOLDEN_FAMILY_BACKUP_RUNTIME_INVALID")
    if runtime.get("implicit_fallback_allowed") is not False:
        fail("GOLDEN_FAMILY_IMPLICIT_FALLBACK_MUST_BE_FALSE")
    if runtime.get("queue") != "private.lf_profile_runtime_queue_v1":
        fail("GOLDEN_FAMILY_RUNTIME_QUEUE_INVALID")
    require_file(runtime.get("transport_contract_validator", ""), root)

    required_runtime_proof_fields = {
        "request_id",
        "queue_ref",
        "runtime_target",
        "runtime_provider",
        "deployed_worker_revision",
        "persisted_result_ref",
        "same_request_readback_ref",
    }
    configured_runtime_proof_fields = set(runtime.get("e2e_runtime_proof_required_fields", []))
    missing_runtime_contract = sorted(required_runtime_proof_fields - configured_runtime_proof_fields)
    if missing_runtime_contract:
        fail("GOLDEN_FAMILY_RUNTIME_PROOF_CONTRACT_MISSING:" + ",".join(missing_runtime_contract))

    success = data.get("success_rule", {})
    if success.get("primary_runtime_required_for_family_pass") is not True:
        fail("GOLDEN_FAMILY_PRIMARY_RUNTIME_GATE_MISSING")
    if success.get("github_actions_backup_can_satisfy_primary_gate") is not False:
        fail("GOLDEN_FAMILY_BACKUP_FALSE_PASS_ALLOWED")
    if success.get("isolated_component_pass_can_satisfy_family_gate") is not False:
        fail("GOLDEN_FAMILY_ISOLATED_PASS_FALSE_POSITIVE_ALLOWED")

    required_evidence = set(data.get("required_e2e_evidence", []))
    must_have = {
        "router_receipt",
        "input_governance_receipt_or_governed_na",
        "profile_source_ref_and_hash",
        "card_receipt_or_governed_na",
        "adapter_resolution_and_receipt_or_governed_na",
        "runtime_target_hetzner",
        "runtime_provider_and_model",
        "model_outcome",
        "deterministic_validator_results",
        "semantic_judge_results",
        "durable_persistence",
        "readback_same_request_id",
        "quality_and_depth_metrics",
        "stage_and_total_latency",
        "input_output_cache_tokens_when_available",
        "source_provenance_snapshot",
    }
    missing = sorted(must_have - required_evidence)
    if missing:
        fail("GOLDEN_FAMILY_E2E_EVIDENCE_MISSING:" + ",".join(missing))

    required_ekb = {
        "PROFILES-EKB-PREFLIGHT-OMISSION-001",
        "DB-SCHEMA-FIRST-COLUMN-ASSUMPTION-001",
        "DB-EKB-CONCURRENCY-001",
        "ARC-011",
        "PROFILE-CARD-RUNTIME-MATERIALIZATION-GAP-001",
        "PROFILE-RUNTIME-TRANSPORT-SUCCESS-QUALITY-001",
        "INPUT-GOV-CONSUMER-BINDING-001",
        "GOV-037",
        "BENCH-TAUTOLOGY-001",
        "GOV-024",
        "GOV-ADAPTER-POST-CLOSURE-REGRESSION-001",
    }
    missing_ekb = sorted(required_ekb - set(data.get("ekb_preflight_required_codes", [])))
    if missing_ekb:
        fail("GOLDEN_FAMILY_EKB_PREFLIGHT_CODES_MISSING:" + ",".join(missing_ekb))

    main_contract = require_file("skills/profile_creator/contracts/main_contract.md", root).read_text(encoding="utf-8")
    for token in (
        "Full family E2E success contract",
        "Input Governance",
        "Cards are referenced",
        "Adapters are resolved",
        "runtime_target=HETZNER",
        "GITHUB_ACTIONS",
        "request_id",
    ):
        if token not in main_contract:
            fail(f"GOLDEN_FAMILY_TRANSVERSAL_CONTRACT_TOKEN_MISSING:{token}")

    runtime_proof = data.get("runtime_proof")
    if data.get("status") != "E2E_PROVEN":
        if runtime_proof != "NOT_EXECUTED":
            fail("GOLDEN_FAMILY_UNPROVEN_STATUS_HAS_RUNTIME_PROOF")
        result = f"GOLDEN_FAMILY_CONTRACT_PASS status={data.get('status')} runtime_proof=NOT_EXECUTED"
    else:
        if not isinstance(runtime_proof, dict):
            fail("GOLDEN_FAMILY_E2E_PROVEN_RUNTIME_PROOF_OBJECT_REQUIRED")
        missing_proof = sorted(required_runtime_proof_fields - set(runtime_proof))
        if missing_proof:
            fail("GOLDEN_FAMILY_E2E_PROVEN_RUNTIME_PROOF_FIELDS_MISSING:" + ",".join(missing_proof))
        if runtime_proof.get("runtime_target") != "HETZNER":
            fail("GOLDEN_FAMILY_E2E_PROVEN_PRIMARY_RUNTIME_NOT_HETZNER")
        if not runtime_proof.get("request_id"):
            fail("GOLDEN_FAMILY_E2E_PROVEN_REQUEST_ID_REQUIRED")
        if not runtime_proof.get("same_request_readback_ref"):
            fail("GOLDEN_FAMILY_E2E_PROVEN_SAME_REQUEST_READBACK_REQUIRED")
        result = f"GOLDEN_FAMILY_CONTRACT_PASS runtime_proof_request_id={runtime_proof.get('request_id')}"

    if data.get("automatic_impact_authorized") is not False:
        fail("GOLDEN_FAMILY_AUTOMATIC_IMPACT_MUST_REMAIN_BLOCKED")
    if data.get("promotion_authorized") is not False:
        fail("GOLDEN_FAMILY_PROMOTION_MUST_REMAIN_BLOCKED")

    return result


def main() -> int:
    if not CONTRACT.is_file():
        raise SystemExit("GOLDEN_FAMILY_CONTRACT_MISSING")
    data = json.loads(CONTRACT.read_text(encoding="utf-8"))
    try:
        result = validate_contract(data)
    except ContractError as exc:
        raise SystemExit(str(exc)) from exc
    print(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
